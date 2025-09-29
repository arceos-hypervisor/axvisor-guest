#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

BUSYBOX_REPO_URL="git://busybox.net/busybox.git"
BUSYBOX_SRC_DIR="${BUILD_DIR}/busybox"
BUSYBOX_PATCH_DIR="${ROOT_DIR}/patches/busybox"

usage() {
    printf '%s\n' 'Generate a filesystem image containing BusyBox and basic device nodes.'
    printf '%s\n' ''
    printf '%s\n' 'Usage:'
    printf '%s\n' "  scripts/mkfs.sh <aarch64|riscv64|x86_64> --dir|-d <out_dir>"
    printf '%s\n' "  scripts/mkfs.sh -h|--help|help"
    printf '%s\n' ''
    printf '%s\n' 'Commands:'
    printf '%s\n' '  help            Show this help and exit'
    printf '%s\n' '  aarch64         Build minimal filesystem for aarch64 (cross-compile BusyBox, pack images)'
    printf '%s\n' '  riscv64         Build minimal filesystem for riscv64 (cross-compile BusyBox, pack images)'
    printf '%s\n' '  x86_64          Build minimal filesystem for x86_64 (native BusyBox build, pack images)'
    printf '%s\n' ''
    printf '%s\n' 'Environment:'
    printf '%s\n' "  OUT_DIR         Base output directory"
    printf '%s\n' ''
    printf '%s\n' 'Notes:'
    printf '%s\n' '  * If BusyBox is dynamically linked, required shared libraries are copied automatically.'
    printf '%s\n' '  * The init script drops to an interactive shell after mounting basic pseudo filesystems.'
}

build_busybox() {
    local cross=""
    if [[ "$ARCH" == "x86_64" ]]; then
        cross=""
    else
        cross="${ARCH}-linux-gnu-"
    fi
    pushd "$BUSYBOX_SRC_DIR" >/dev/null
    info "Cleaning: make distclean"
    make distclean

    info "Configuring: make defconfig"
    make defconfig

    info "Building: make -j$(nproc) CROSS_COMPILE=$cross"
    sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config
    sed -i 's/^CONFIG_TC=y$/# CONFIG_TC is not set/' .config
    make -j$(nproc) CROSS_COMPILE="$cross"
    popd >/dev/null
}

create_init() {
    printf '%s\n' \
        '#!/bin/sh' \
        'export PATH=/bin:/sbin:/usr/bin:/usr/sbin' \
        '' \
        'if [ -x /bin/busybox ]; then' \
        '    /bin/busybox --install -s >/dev/null 2>&1' \
        'fi' \
        '' \
        'TTY_DEV=/dev/console' \
        '[ -c /dev/ttyAMA0 ] && TTY_DEV=/dev/ttyAMA0' \
        '[ -c /dev/ttyS0 ] && TTY_DEV=/dev/ttyS0' \
        '' \
        'if [ ! -w "$TTY_DEV" ]; then' \
        '    echo "[ERROR] TTY_DEV ($TTY_DEV) is not writable. Falling back to /dev/console."' \
        '    TTY_DEV=/dev/console' \
        'fi' \
        '' \
        '/bin/busybox mkdir -p /proc /sys /dev /dev/pts /etc/init.d' \
        '/bin/busybox mount -t proc proc /proc >/dev/null 2>&1' \
        '/bin/busybox mount -t sysfs sysfs /sys >/dev/null 2>&1' \
        '/bin/busybox mount -t devtmpfs devtmpfs /dev >/dev/null 2>&1 || true' \
        '/bin/busybox mount -t devpts devpts /dev/pts >/dev/null 2>&1 || true' \
        '' \
        'echo "test pass!" > "$TTY_DEV" 2>/dev/null || echo "test pass!"' \
        'if command -v cttyhack >/dev/null 2>&1; then' \
        '    exec /bin/busybox cttyhack /bin/sh -i' \
        'elif command -v setsid >/dev/null 2>&1; then' \
        '    exec /bin/busybox setsid /bin/sh -i' \
        'else' \
        '    exec /bin/sh -i' \
        'fi' \
        > init
    chmod +x init
    # 创建 /etc/init.d/rcS，避免 busybox init 报错
    mkdir -p etc/init.d
    echo '#!/bin/sh' > etc/init.d/rcS
    echo 'echo rcS running' >> etc/init.d/rcS
    chmod +x etc/init.d/rcS
}

pack_fs() {
    # 0. Prepare working directory
    OUTPUT_DIR="${OUT_DIR:-${ROOT_DIR}/IMAGES/qemu/linux/${ARCH}}"
    mkdir -p "$OUTPUT_DIR"
    TMP_DIR=$(mktemp -d)
    cleanup() { rm -rf "$TMP_DIR"; }
    trap cleanup EXIT
    cd "$TMP_DIR"
    echo "Creating minimal ramfs in $TMP_DIR"

    # 1. Create necessary directory structure
    mkdir -p bin sbin usr/bin usr/sbin dev dev/pts etc proc sys
    # 2. Use fakeroot to create device nodes
    fakeroot bash -c '
        mknod dev/console c 5 1 || true
        mknod dev/null c 1 3 || true
        mknod dev/zero c 1 5 || true
        mknod dev/tty c 5 0 || true
        mknod dev/ttyS0 c 4 64 || true
    '
    # 3. Install busybox (if dynamically linked, copy required shared libraries) and create necessary symlinks
    cp "$BUSYBOX_SRC_DIR/busybox" bin/
    if command -v ldd >/dev/null 2>&1; then
        ldd_output="$(ldd "$BUSYBOX_SRC_DIR/busybox" 2>&1 || true)"
        if ! printf '%s' "$ldd_output" | grep -q "not a dynamic executable"; then
            echo "BusyBox is dynamically linked; copying dependent libraries..."
            printf '%s' "$ldd_output" | awk '{ if ($3 ~ /^\//) print $3; else if ($1 ~ /^\//) print $1 }' | sort -u | while IFS= read -r lib; do
                [ -f "$lib" ] || continue
                rel_dir="${lib%/*}"
                mkdir -p ".${rel_dir}"
                cp -u "$lib" ".${lib}" 2>/dev/null || cp "$lib" ".${lib}" || true
            done
        fi
    fi
    [[ -e bin/sh ]] || ln -s busybox bin/sh
    # 4. Create init script
    create_init
    [[ -e bin/init ]] || ln -s ../init bin/init

    # 5. Pack ramfs
    local abs_out="$OUTPUT_DIR/initramfs.cpio.gz"
    echo "Packing ramfs -> $abs_out"
    chmod 755 . || true
    find . -print0 | sort -z 2>/dev/null | cpio --null -H newc -o 2>/dev/null | gzip -9 > "$abs_out"
    echo "Minimal ramfs created: $abs_out"
    du -h "$abs_out" | awk '{print "Size: "$1}'

    # 6. Pack ext4 rootfs.img
    local img_out="$OUTPUT_DIR/rootfs.img"
    local size_mb=32
    echo "Packing ext4 rootfs (debugfs write) -> $img_out"
    dd if=/dev/zero of="$img_out" bs=1M count=$size_mb status=none
    mkfs.ext4 -q -F "$img_out"
    if ! command -v debugfs >/dev/null 2>&1; then
        echo "Error: debugfs not found. Please install: sudo apt install e2fsprogs" >&2
        return 1
    fi
    find . -type d | while read -r d; do
        debugfs -w -R "mkdir ${d#.}" "$img_out" >/dev/null 2>&1
    done
    # Write regular files
    find . -type f | while read -r f; do
        debugfs -w -R "write $f ${f#.}" "$img_out" >/dev/null 2>&1
    done
    # Write symlinks
    find . -type l | while read -r lnk; do
        target=$(readlink "$lnk")
        debugfs -w -R "symlink ${lnk#.} $target" "$img_out" >/dev/null 2>&1
    done
    echo "rootfs.img created: $img_out"
    du -h "$img_out" | awk '{print "Size: "$1}'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "${cmd}" in
        ""|-h|--help|help)
            usage
            exit 0
            ;;
        aarch64|riscv64|x86_64)
            ARCH="$cmd"
            # Check if first arg is --dir or -d, only if at least one extra arg
            if [[ $# -ge 2 && ( "$1" == "--dir" || "$1" == "-d" ) ]]; then
                OUT_DIR="$2"
                shift 2
            fi
            info "Cloning busybox source repository $BUSYBOX_REPO_URL -> $BUSYBOX_SRC_DIR"
            clone_repository "$BUSYBOX_REPO_URL" "$BUSYBOX_SRC_DIR"

            info "Applying patches..."
            apply_patches "$BUSYBOX_PATCH_DIR" "$BUSYBOX_SRC_DIR"

            info "Starting to build busybox..."
            build_busybox "$@"

            info "Packing filesystem..."
            pack_fs
            ;;
        *)
            echo "Unknown cmd: ${cmd}" >&2
            exit 2
            ;;
    esac
fi
