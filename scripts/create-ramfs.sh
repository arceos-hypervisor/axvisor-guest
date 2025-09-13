#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)

DEFAULT_OUT_DIR="${WORK_ROOT}/IMAGES/qemu/linux"
OUTPUT_FILE="${OUTPUT_FILE:-initramfs.cpio.gz}"

usage() {
    printf '%s\n' 'create-ramfs: generate a minimal initramfs (cpio+gzip) containing BusyBox and basic device nodes.' >&2
    printf '%s\n' '' >&2
    printf '%s\n' 'Usage:' >&2
    printf '  %s [output_file] [busybox_path]\n' "$0" >&2
    printf '  %s -h|--help|help\n' "$0" >&2
    printf '%s\n' '' >&2
    printf '%s\n' 'Positional arguments:' >&2
    printf '  output_file     Output initramfs file name (default: initramfs.cpio.gz)\n' >&2
    printf '  busybox_path    Path to busybox binary (default: first found in PATH, else /bin/busybox)\n' >&2
    printf '%s\n' '' >&2
    printf '%s\n' 'Commands:' >&2
    printf '  help            Show this help and exit\n' >&2
    printf '%s\n' '' >&2
    printf '%s\n' 'Environment variables:' >&2
    printf '  OUT_DIR         Base output directory (default: %s)\n' "${DEFAULT_OUT_DIR}" >&2
    printf '                  The final file is written to: ${OUT_DIR}/<dir part of output_file>/<basename>.\n' >&2
    printf '%s\n' '' >&2
    printf '%s\n' 'Notes:' >&2
    printf '%s\n' '  * Creates minimal /dev nodes only if running as root (console, null, zero, tty, ttyS0).' >&2
    printf '%s\n' '  * If BusyBox is dynamically linked, required shared libraries are copied automatically.' >&2
    printf '%s\n' '  * The init script drops to an interactive shell after mounting basic pseudo filesystems.' >&2
}

prepare_tools_and_busybox() {
    local given="${1:-}"
    for tool in cpio gzip; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            echo "Error: required tool '$tool' not found in PATH" >&2
            exit 1
        fi
    done
    local bb
    if [[ -n "$given" ]]; then
        bb="$given"
    else
        bb="$(command -v busybox 2>/dev/null || echo /bin/busybox)"
    fi
    if [[ ! -f "$bb" ]]; then
        echo "Error: busybox not found at $bb" >&2
        echo "Install busybox or specify path explicitly." >&2
        exit 1
    fi
    echo "$bb"
}

create_init() {
    printf '%s\n' \
        '#!/bin/sh' \
        'export PATH=/bin:/sbin:/usr/bin:/usr/sbin' \
        '' \
        '# Ensure directories exist for busybox symlinks' \
        'mkdir -p /sbin /usr/bin /usr/sbin' \
        '' \
        '# Install busybox applet symlinks (ignore errors if already exist)' \
        '/bin/busybox --install -s' \
        '' \
        '# Use explicit busybox invocation for early mounts (in case mount symlink missing)' \
        '/bin/busybox mount -t proc proc /proc || echo "warn: proc mount failed"' \
        '/bin/busybox mount -t sysfs sysfs /sys || echo "warn: sysfs mount failed"' \
        '/bin/busybox mount -t devtmpfs devtmpfs /dev 2>/dev/null || echo "info: devtmpfs not available"' \
        'mkdir -p /dev/pts' \
        '/bin/busybox mount -t devpts devpts /dev/pts 2>/dev/null || true' \
        '' \
        'choose_tty() {' \
        '    for d in /dev/ttyS0 /dev/console /dev/tty; do' \
        '        [ -c "$d" ] && echo "$d" && return 0' \
        '    done' \
        '    return 1' \
        '}' \
        '' \
        'TTY_DEV=$(choose_tty || echo /dev/console)' \
        'exec <"$TTY_DEV" >"$TTY_DEV" 2>&1' \
        '' \
        'echo' \
        'echo "Initramfs test OK! Starting interactive shell..."' \
        'echo' \
        '' \
        '# Start interactive shell with job control if possible' \
        'if command -v setsid >/dev/null 2>&1; then' \
        '    # Use setsid -c if busybox supports it, else fall back' \
        '    setsid -c /bin/sh -i 2>/dev/null || setsid /bin/sh -i 2>/dev/null || exec /bin/sh -i' \
        'else' \
        '    exec /bin/sh -i' \
        'fi' \
        '' \
        'echo' \
        'echo "[init] reached end of /init unexpectedly; sleeping 10s (will then exit to trigger panic)" >&2' \
        'sleep 10' \
        'exit 1' \
        > init
    chmod +x init
}

pack_ramfs() {
    local abs_out="$OUTPUT_DIR/$(basename "$OUTPUT_FILE")"
    echo "Packing ramfs -> $abs_out"
    # Ensure deterministic permissions for reproducibility (optional)
    chmod 755 . || true
    find . -print0 | sort -z | cpio --null -H newc -o 2>/dev/null | gzip -9 > "$abs_out"
    echo "Minimal ramfs created: $abs_out"
    du -h "$abs_out" | awk '{print "Size: "$1}'
}

pack_rootfs() {
    local img_out="$OUTPUT_DIR/rootfs.img"
    local size_mb=32
    echo "Packing ext4 rootfs (debugfs write) -> $img_out"
    dd if=/dev/zero of="$img_out" bs=1M count=$size_mb status=none
    mkfs.ext4 -q -F "$img_out"
    # Use debugfs to import files
    if ! command -v debugfs >/dev/null 2>&1; then
        echo "Error: debugfs not found. Please install: sudo apt install e2fsprogs" >&2
        return 1
    fi
    # Create directories
    find . -type d | while read -r d; do
        debugfs -w -R "mkdir ${d#.}" "$img_out" >/dev/null 2>&1
    done
    # Write files
    find . -type f | while read -r f; do
        debugfs -w -R "write $f ${f#.}" "$img_out" >/dev/null 2>&1
    done
    echo "rootfs.img created: $img_out"
    du -h "$img_out" | awk '{print "Size: "$1}'
}

case "${1:-}" in
    -h|--help|help)
        usage
        exit 0
        ;;
    *)
        BUSYBOX_PATH="$(prepare_tools_and_busybox "${2:-}")"

        # 0. 准备工作目录
        OUTPUT_DIR="${OUT_DIR:-${DEFAULT_OUT_DIR}}/$(dirname "$OUTPUT_FILE")"
        mkdir -p "$OUTPUT_DIR"
        TMP_DIR=$(mktemp -d)
        cleanup() { rm -rf "$TMP_DIR"; }
        trap cleanup EXIT
        cd "$TMP_DIR"
        echo "Creating minimal ramfs in $TMP_DIR"

        # 1. 创建必要的目录结构
        mkdir -p bin sbin usr/bin usr/sbin dev dev/pts etc proc sys
        # 2. 使用 fakeroot 创建设备节点
        fakeroot bash -c '
            mknod dev/console c 5 1 || true
            mknod dev/null c 1 3 || true
            mknod dev/zero c 1 5 || true
            mknod dev/tty c 5 0 || true
            mknod dev/ttyS0 c 4 64 || true
        '
        # 3. 安装 busybox（如果 busybox 是动态链接的，复制所需的共享库） 并创建必要的符号链接
        cp "$BUSYBOX_PATH" bin/
        [[ -e bin/sh ]] || ln -s busybox bin/sh
        if command -v ldd >/dev/null 2>&1; then
            ldd_output="$(ldd "$BUSYBOX_PATH" 2>&1 || true)"
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
        ls -al "$TMP_DIR"
        # 4. 创建 init 脚本
        create_init
        # 5. 打包镜像
        pack_ramfs
        pack_rootfs
        ;;
esac
