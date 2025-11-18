#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository URLs
ORANGEPI_LINUX_REPO_URL="https://github.com/orangepi-xunlong/orangepi-build.git"
ORANGEPI_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# Directory configuration
LINUX_SRC_DIR="${BUILD_DIR}/orangepi"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${ROOT_DIR}/patches/orangepi"
ARCEOS_PATCH_DIR="${ROOT_DIR}/patches/arceos"
LINUX_IMAGES_DIR="${ROOT_DIR}/IMAGES/orangepi/linux"
ARCEOS_IMAGES_DIR="${ROOT_DIR}/IMAGES/orangepi/arceos"

# Output help information
usage() {
    printf 'Build script for Phytium development board Linux & ArceOS\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/orangepi.sh <command> [options]\n'
    printf '\n'
    printf 'Commands:\n'
    printf '  all                               Build Linux and ArceOS (default)\n'
    printf '  linux                             Build only the Linux system\n'
    printf '  arceos                            Build only the ArceOS system\n'
    printf '  help, -h, --help                  Display this help information\n'
    printf '  clean                             Clean build output artifacts\n'
    printf '\n'
    printf 'Options:\n'
    printf '  Optional, all options will be directly passed to the specific build system\n'
    printf '\n'
    printf 'Environment Variables:\n'
    printf '  ORANGEPI_LINUX_REPO_URL            Linux repository URL\n'
    printf '  ORANGEPI_ARCEOS_REPO_URL           ArceOS repository URL\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/orangepi.sh all          # Build everything\n'
    printf '  scripts/orangepi.sh linux        # Build only Linux\n'
}

build_linux() {
    pushd "$LINUX_SRC_DIR" >/dev/null
    if [[ "$@" != *"clean"* ]]; then
        info "Starting compilation: ./build.sh BOARD=orangepi5plus BRANCH=current BUILD_OPT=image RELEASE=jammy BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_CONFIGURE=no"
        ./build.sh BOARD=orangepi5plus BRANCH=current BUILD_OPT=image RELEASE=jammy BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_CONFIGURE=no
        
        info "Copying build artifacts: $LINUX_SRC_DIR/* -> $LINUX_IMAGES_DIR/*"
        mkdir -p "$LINUX_IMAGES_DIR"
        rsync -av --ignore-missing-args "$LINUX_SRC_DIR/kernel/orange-pi-6.1-rk35xx/arch/arm64/boot/Image" \
        "$LINUX_SRC_DIR/kernel/orange-pi-6.1-rk35xx/arch/arm64/boot/dts/rockchip/rk3588-orangepi-5-plus.dtb" \
        "$LINUX_IMAGES_DIR/"
        mv "$LINUX_IMAGES_DIR/Image" "$LINUX_IMAGES_DIR/orangepi-5-plus"
        mv "$LINUX_IMAGES_DIR/rk3588-orangepi-5-plus.dtb" "$LINUX_IMAGES_DIR/orangepi-5-plus.dtb"
    else
        info "Cleaning: nothing to do for Orange Pi Linux, just removing ${LINUX_IMAGES_DIR}/*"
        rm ${LINUX_IMAGES_DIR}/* || true
    fi
    popd >/dev/null
}

linux() {
    info "Cloning Linux source repository $ORANGEPI_LINUX_REPO_URL -> $LINUX_SRC_DIR"
    clone_repository "$ORANGEPI_LINUX_REPO_URL" "$LINUX_SRC_DIR"
    
    info "Applying patches..."
    apply_patches "$LINUX_PATCH_DIR" "$LINUX_SRC_DIR"

    info "Starting to build the Linux system..."
    build_linux "$@"
}

build_arceos() {
    pushd "$ARCEOS_SRC_DIR" >/dev/null
    info "Cleaning old build files: make clean"
    make clean >/dev/null 2>&1 || true

    local make_args="A=examples/helloworld-myplat LOG=info MYPLAT=axplat-aarch64-dyn APP_FEATURES=aarch64-dyn LD_SCRIPT=link.x FEATURES=driver-dyn,page-alloc-4g,paging SMP=1 $@"
    info "Starting compilation: make $make_args"
    make $make_args
    popd >/dev/null

    if [[ "${make_args}" != *"clean"* ]]; then
        info "Copying build artifacts -> $ARCEOS_IMAGES_DIR"
        mkdir -p "$ARCEOS_IMAGES_DIR"
        cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_aarch64-dyn.bin" "$ARCEOS_IMAGES_DIR/orangepi-5-plus"
    else
        rm -rf $ARCEOS_IMAGES_DIR/orangepi-5-plus || true
    fi
}

arceos() {
    info "Cloning ArceOS source repository $ORANGEPI_ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ORANGEPI_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "Applying patches..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "Starting to build the ArceOS system..."
    build_arceos "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        ""|-h|--help|help)
            usage
            exit 0
            ;;
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
            die "Unknown command: $cmd" >&2
            ;;
    esac
fi