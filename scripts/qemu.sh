#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository URLs
LINUX_REPO_URL="https://github.com/torvalds/linux.git"
ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# Source directories
LINUX_SRC_DIR="${BUILD_DIR}/qemu_linux"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${WORK_ROOT}/patches/qemu"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/arceos"

# Display help information
usage() {
    printf 'Build script for QEMU Linux & ArceOS\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/qemu.sh <command> <system> [options]\n'
    printf '\n'
    printf 'Commands:\n'
    printf '  aarch64                           Build all systems for AArch64 architecture\n'
    printf '  x86_64                            Build all systems for x86_64 architecture\n'
    printf '  riscv64                           Build all systems for RISC-V architecture\n'
    printf '  all                               Build all supported architectures and systems\n'
    printf '  help, -h, --help                  Display this help information\n'
    printf '  clean                             Clean build output artifacts\n'
    printf '\n'
    printf 'Systems:\n'
    printf '  linux                             Build the Linux system\n'
    printf '  arceos                            Build the ArceOS system\n'
    printf '  all|""                            Build all systems (default)\n'
    printf '  clean                             Clean build output artifacts\n'
    printf '\n'
    printf 'Options:\n'
    printf '  Optional, all options will be directly passed to the specific build system\n'
    printf '\n'
    printf 'Environment Variables:\n'
    printf '  LINUX_REPO_URL                    Linux repository URL\n'
    printf '  ARCEOS_REPO_URL                   ArceOS repository URL\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/qemu.sh aarch64 linux     # Build ARM64 Linux\n'
    printf '  scripts/qemu.sh x86_64 arceos     # Build x86_64 ArceOS\n'
    printf '  scripts/qemu.sh riscv64 all       # Build all systems for RISC-V\n'
}

build_linux() {
    local commands=("$@")
    case "${ARCH}" in
        aarch64)
            local linux_arch="arm64"
            local cross_compile="${AARCH64_CROSS_COMPILE:-aarch64-linux-gnu-}"
            local defconfig="defconfig"
            local kimg_subpath="arch/arm64/boot/Image"
            ;;
        riscv64)
            local linux_arch="riscv"
            local cross_compile="${RISCV64_CROSS_COMPILE:-riscv64-linux-gnu-}"
            local defconfig="defconfig"
            local kimg_subpath="arch/riscv/boot/Image"
            ;;
        x86_64)
            local linux_arch="x86"
            local cross_compile="${X86_CROSS_COMPILE:-}"
            local defconfig="x86_64_defconfig"
            local kimg_subpath="arch/x86/boot/bzImage"
            ;;
        *)
            die "Unsupported Linux architecture: ${ARCH}"
            ;;
    esac
    
    pushd "${LINUX_SRC_DIR}" >/dev/null

    # info "Cleaning Linux: make distclean"
    # make distclean || true

    if [[ ${#commands[@]} -eq 0 ]] || [[ "${commands[0]}" == "all" ]]; then
        info "Configuring Linux: make ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${defconfig}"
        make ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${defconfig}"
    fi
    
    info "Building Linux: make -j$(nproc) ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${commands[@]}"
    make -j"$(nproc)" ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${commands[@]}"
    
    popd >/dev/null

    # If it's a full build, copy the image and create the root filesystem
    if [[ ${#commands[@]} -eq 0 ]] || [[ "${commands[0]}" == "all" ]]; then
        mkdir -p "${LINUX_IMAGES_DIR}/${ARCH:-}"
        KIMG_PATH="${LINUX_SRC_DIR}/${kimg_subpath}"
        [[ -f "${KIMG_PATH}" ]] || die "Kernel image not found: ${KIMG_PATH}"
        info "Copying image: ${KIMG_PATH} -> ${LINUX_IMAGES_DIR}/${ARCH:-}"
        cp -f "${KIMG_PATH}" "${LINUX_IMAGES_DIR}/${ARCH:-}/"
        
        info "Creating root filesystem: ${SCRIPT_DIR}/mkfs.sh -> ${LINUX_IMAGES_DIR}/${ARCH:-}"
        build_rootfs
    fi
}

linux() {
    info "Cloning ${ARCH} Linux source repository $LINUX_REPO_URL"
    clone_repository "$LINUX_REPO_URL" "$LINUX_SRC_DIR"

    info "Applying patches..."
    apply_patches "$LINUX_PATCH_DIR" "$LINUX_SRC_DIR"

    info "Starting to build ${ARCH} Linux system..."
    build_linux "$@"
}

build_rootfs() {
    if [ ! -f "${SCRIPT_DIR}/mkfs.sh" ]; then
        die "Root filesystem script does not exist: ${SCRIPT_DIR}/mkfs.sh"
    fi
    bash "${SCRIPT_DIR}/mkfs.sh" "${ARCH}" "--dir ${LINUX_IMAGES_DIR}/${ARCH:-}"
    success "Root filesystem creation completed"
}

build_arceos() {
    case "${ARCH}" in
        aarch64)
            local platform="axplat-aarch64-dyn"
            local app_features="aarch64-dyn"
            ;;
        riscv64)
            local platform="axplat-riscv64-qemu-virt"
            local app_features="riscv64-qemu-virt"
            ;;
        x86_64)
            local platform="axplat-x86-pc"
            local app_features="x86-pc"
            ;;
        *)
            die "Unsupported ArceOS architecture: ${ARCH}"
            ;;
    esac

    pushd "$ARCEOS_SRC_DIR" >/dev/null
    # info "Cleaning old build files: make clean"
    # make clean >/dev/null 2>&1 || true

    if [ "${ARCH}" == "aarch64" ]; then
        local make_args="A=examples/helloworld-myplat LOG=info MYPLAT=$platform APP_FEATURES=$app_features LD_SCRIPT=link.x FEATURES=driver-dyn,page-alloc-4g SMP=1 $@"
    else
        local make_args="A=examples/helloworld-myplat LOG=info MYPLAT=$platform APP_FEATURES=$app_features SMP=1 $@"
    fi
    info "Starting compilation: make $make_args"
    make $make_args
    popd >/dev/null

    if [[ "${make_args}" != *"clean"* ]]; then
        info "Copying build artifacts -> $ARCEOS_IMAGES_DIR/${ARCH:-}"
        mkdir -p "$ARCEOS_IMAGES_DIR/${ARCH:-}"
        cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_$app_features.bin" "$ARCEOS_IMAGES_DIR/${ARCH:-}/arceos-dyn-smp1.bin"
    fi
}

arceos() {
    info "Cloning ArceOS source repository $ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "Applying patches..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "Starting to build ArceOS system..."
    build_arceos "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift 1 || true
    case "${cmd}" in
        ""|help|-h|--help)
            usage
            exit 0
            ;;
        aarch64|riscv64|x86_64)
            ARCH="$cmd"
            SYSTEM="${1:-all}"
            shift 1 || true
            case "${SYSTEM}" in
                linux)
                    linux "$@"
                    ;;
                arceos)
                    arceos "$@"
                    ;;
                all)
                    linux "$@"

                    arceos "$@"
                    ;;
                clean)
                    linux "clean"

                    arceos "clean"
                    ;;
                *)
                    die "Unknown system: "${SYSTEM}" (supported: linux, arceos, all)"
                    ;;
            esac
            ;;
        all)
            for arch in aarch64 riscv64 x86_64; do
                "$0" "$arch" "$@" || { echo "[ERROR] $arch build failed" >&2; exit 1; }
            done
            ;;
        clean)
            for arch in aarch64 riscv64 x86_64; do
                "$0" "$arch" "clean" || { echo "[ERROR] $arch build failed" >&2; exit 1; }
            done
            ;;
        *)
        die "Unknown command: $cmd" >&2
        ;;
    esac
fi