#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository URLs
PHYTIUM_LINUX_REPO_URL="https://gitee.com/phytium_embedded/phytium-pi-os.git"
PHYTIUM_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# Directory configuration
LINUX_SRC_DIR="${BUILD_DIR}/phytium-pi-os"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${ROOT_DIR}/patches/phytiumpi"
ARCEOS_PATCH_DIR="${ROOT_DIR}/patches/arceos"
LINUX_IMAGES_DIR="${ROOT_DIR}/IMAGES/phytiumpi/linux"
ARCEOS_IMAGES_DIR="${ROOT_DIR}/IMAGES/phytiumpi/arceos"

# Output help information
usage() {
    printf 'Build script for Phytium development board Linux & ArceOS\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/phytiumpi.sh <command> [options]\n'
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
    printf '  PHYTIUM_LINUX_REPO_URL            Linux repository URL\n'
    printf '  PHYTIUM_ARCEOS_REPO_URL           ArceOS repository URL\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/phytiumpi.sh all          # Build everything\n'
    printf '  scripts/phytiumpi.sh linux        # Build only Linux\n'
}

build_linux() {
    pushd "$LINUX_SRC_DIR" >/dev/null
    if [[ "$@" != *"clean"* ]]; then
        info "Configuring build: make phytiumpi_desktop_defconfig"
        make phytiumpi_desktop_defconfig

        info "Starting compilation: make $@"
        make $@ > /dev/null
        
        info "Copying build artifacts: $LINUX_SRC_DIR/output/images -> $LINUX_IMAGES_DIR"
        mkdir -p "$LINUX_IMAGES_DIR"
        rsync -av --ignore-missing-args "$LINUX_SRC_DIR/output/images/fip-all.bin" \
        "$LINUX_SRC_DIR/output/images/fitImage" \
        "$LINUX_SRC_DIR/output/images/kernel.its" \
        "$LINUX_SRC_DIR/output/images/Image" \
        "$LINUX_SRC_DIR/output/images/phytiumpi_firefly.dtb" \
        "$LINUX_IMAGES_DIR/"
        gzip -dc "$LINUX_SRC_DIR/output/images/Image.gz" > "$LINUX_IMAGES_DIR/Image"
    else
        info "Starting compilation: make $@"
        make $@ > /dev/null
    fi
    popd >/dev/null
}

linux() {
    info "Cloning Linux source repository $PHYTIUM_LINUX_REPO_URL -> $LINUX_SRC_DIR"
    clone_repository "$PHYTIUM_LINUX_REPO_URL" "$LINUX_SRC_DIR"
    
    info "Applying patches..."
    apply_patches "$LINUX_PATCH_DIR" "$LINUX_SRC_DIR"

    info "Starting to build the Linux system..."
    build_linux "$@"
}

build_arceos() {
    pushd "$ARCEOS_SRC_DIR" >/dev/null
    info "Cleaning old build files: make clean"
    make clean >/dev/null 2>&1 || true

    local make_args="A=examples/helloworld-myplat LOG=debug LD_SCRIPT=link.x MYPLAT=axplat-aarch64-dyn APP_FEATURES=aarch64-dyn FEATURES=driver-dyn,page-alloc-4g SMP=1 $@"
    info "Starting compilation: make $make_args"
    make $make_args
    popd >/dev/null

    if [[ "${make_args}" != *"clean"* ]]; then
        info "Copying build artifacts -> $ARCEOS_IMAGES_DIR"
        mkdir -p "$ARCEOS_IMAGES_DIR"
        cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_aarch64-dyn.bin" "$ARCEOS_IMAGES_DIR/arceos-aarch64-dyn-smp1.bin"
    fi
}

arceos() {
    info "Cloning ArceOS source repository $PHYTIUM_ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$PHYTIUM_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

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