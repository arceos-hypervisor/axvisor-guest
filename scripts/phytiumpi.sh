#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository and directory configuration
LINUX_REPO_URL="https://gitee.com/phytium_embedded/phytium-pi-os.git"
LINUX_SRC_DIR="${BUILD_DIR}/phytium-pi-os"
LINUX_PATCH_DIR="${ROOT_DIR}/patches/phytiumpi"
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
        make $@
        
        info "Copying build artifacts: $LINUX_SRC_DIR/output/images -> $LINUX_IMAGES_DIR"
        mkdir -p "$LINUX_IMAGES_DIR"
        rsync -av --ignore-missing-args "$LINUX_SRC_DIR/output/images/fip-all.bin" \
        "$LINUX_SRC_DIR/output/images/fitImage" \
        "$LINUX_SRC_DIR/output/images/kernel.its" \
        "$LINUX_SRC_DIR/output/images/Image" \
        "$LINUX_SRC_DIR/output/images/phytiumpi_firefly.dtb" \
        "$LINUX_IMAGES_DIR/"
        mv "$LINUX_IMAGES_DIR/phytiumpi_firefly.dtb" "$LINUX_IMAGES_DIR/phytiumpi.dtb"
        gzip -dc "$LINUX_SRC_DIR/output/images/Image.gz" > "$LINUX_IMAGES_DIR/phytiumpi"
    else
        info "Cleaning: make $@"
        make $@
        info "Removing ${LINUX_IMAGES_DIR}/*"
        rm ${LINUX_IMAGES_DIR}/* || true
    fi
    popd >/dev/null
}

linux() {
    info "Cloning Linux source repository $LINUX_REPO_URL -> $LINUX_SRC_DIR"
    clone_repository "$LINUX_REPO_URL" "$LINUX_SRC_DIR"
    
    info "Applying patches..."
    apply_patches "$LINUX_PATCH_DIR" "$LINUX_SRC_DIR"

    info "Starting to build the Linux system..."
    build_linux "$@"
}

arceos() {
    info "Building ArceOS using common arceos.sh script"
    bash "${SCRIPT_DIR}/arceos.sh" aarch64-dyn "$ARCEOS_IMAGES_DIR" phytiumpi $@
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