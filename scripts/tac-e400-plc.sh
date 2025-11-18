#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository URLs
TAC_E400_LINUX_REPO_URL="git@github.com:arceos-hypervisor/tac-e400-plc.git"
TAC_E400_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# Directory configuration
LINUX_SRC_DIR="${BUILD_DIR}/tac-e400-plc"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${ROOT_DIR}/patches/tac-e400-plc"
ARCEOS_PATCH_DIR="${ROOT_DIR}/patches/arceos"
LINUX_IMAGES_DIR="${ROOT_DIR}/IMAGES/tac-e400-plc/linux"
ARCEOS_IMAGES_DIR="${ROOT_DIR}/IMAGES/tac-e400-plc/arceos"

# Output help information
usage() {
    printf 'Build script for TAC-E400 series intelligent PLC products Linux & ArceOS\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/tac-e400-plc.sh <command> [options]\n'
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
    printf '  TAC_E400_LINUX_REPO_URL           Linux repository URL\n'
    printf '  TAC_E400_ARCEOS_REPO_URL          ArceOS repository URL\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/tac-e400-plc.sh all       # Build everything\n'
    printf '  scripts/tac-e400-plc.sh linux     # Build only Linux\n'
}

build_linux() {
    pushd "$LINUX_SRC_DIR/EDGE_KERNEL" >/dev/null
    if [[ "$@" != *"clean"* ]]; then
        info "Configuring kernel: cp "$LINUX_SRC_DIR/.config" .config"
        cp "$LINUX_SRC_DIR/.config" .config

        info "Starting compilation: make -j$(nproc) $@"
        make -j$(nproc) $@ 2>&1

        info "Copying build artifacts -> $LINUX_IMAGES_DIR"
        mkdir -p "$LINUX_IMAGES_DIR"
        cp "$LINUX_SRC_DIR/EDGE_KERNEL/arch/arm64/boot/Image" "$LINUX_IMAGES_DIR/tac-e400-plc"
        cp "$LINUX_SRC_DIR/EDGE_KERNEL/arch/arm64/boot/dts/phytium/e2000q-hanwei-board.dtb" "$LINUX_IMAGES_DIR/tac-e400-plc.dtb"
    else
        info "Cleaning: make -j$(nproc) clean"
        make -j$(nproc) clean 2>&1
        info "Removing ${LINUX_IMAGES_DIR}/*"
        rm ${LINUX_IMAGES_DIR}/* || true
    fi
    popd >/dev/null
}

linux() {
    info "Cloning Linux source repository $TAC_E400_LINUX_REPO_URL -> $LINUX_SRC_DIR"
    clone_repository "$TAC_E400_LINUX_REPO_URL" "$LINUX_SRC_DIR"

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
        cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_aarch64-dyn.bin" "$ARCEOS_IMAGES_DIR/tac-e400-plc"
    else
        rm -rf $ARCEOS_IMAGES_DIR/tac-e400-plc || true
    fi
}

arceos() {
    info "Cloning ArceOS source repository $TAC_E400_ARCEOS_REPO_URL"
    clone_repository "$TAC_E400_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

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
