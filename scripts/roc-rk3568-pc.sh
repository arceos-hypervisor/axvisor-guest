#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository URLs
ROC_RK3568_LINUX_REPO_URL=""
ROC_RK3568_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# Directory configuration
LINUX_SRC_DIR="${BUILD_DIR}/roc-rk3588-pc"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${ROOT_DIR}/patches/roc-rk3588-pc"
ARCEOS_PATCH_DIR="${ROOT_DIR}/patches/arceos"
LINUX_IMAGES_DIR="${ROOT_DIR}/IMAGES/roc-rk3588-pc/linux"
ARCEOS_IMAGES_DIR="${ROOT_DIR}/IMAGES/roc-rk3588-pc/arceos"

# Output help information
usage() {
    printf 'Build script for ROC-RK3588-PC development board Linux & ArceOS\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/roc-rk3568-pc.sh <command> [options]\n'
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
    printf '  ROC_RK3568_LINUX_REPO_URL         Linux repository URL\n'
    printf '  ROC_RK3568_ARCEOS_REPO_URL        ArceOS repository URL\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/roc-rk3568-pc.sh all      # Build everything\n'
    printf '  scripts/roc-rk3568-pc.sh linux    # Build only Linux\n'
}

build_linux() {
    # Since Rockchip's Linux SDK is managed by a large repository using repo, and manufacturers usually do not provide online repositories (typically only compressed packages), we log in to a prepared SDK server via SSH for building.
    REMOTE_HOST="10.0.0.110"
    REMOTE_DIR="/runner/firefly_rk3568_sdk"
    REMOTE_IMAGES_DIR="output/RK3568-FIREFLY-ROC-PC-SE/latest/IMAGES"

    info "Building remotely via SSH: ssh ${REMOTE_HOST} cd '${REMOTE_DIR}' && ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh $@"
    ssh "${REMOTE_HOST}" "cd '${REMOTE_DIR}' && ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh $@"

    if [[ "$@" != *"clean"* ]]; then
        info "Copying build artifacts: -> $LINUX_IMAGES_DIR"
        mkdir -p "${LINUX_IMAGES_DIR}"
        scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/boot.img" "${LINUX_IMAGES_DIR}/"
        scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/parameter.txt" "${LINUX_IMAGES_DIR}/"
        scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/MiniLoaderAll.bin" "${LINUX_IMAGES_DIR}/"
        scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/../kernel/rk3568-firefly-roc-pc-se.dtb" "${LINUX_IMAGES_DIR}/"
        scp "${REMOTE_HOST}:${REMOTE_DIR}/kernel/arch/arm64/boot/Image" "${LINUX_IMAGES_DIR}/"
    fi
}

linux() {
    info "Starting to build the Linux system..."
    build_linux "$@"
}

build_arceos() {
    pushd "$ARCEOS_SRC_DIR" >/dev/null
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
    info "Cloning ArceOS source repository $ROC_RK3568_ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ROC_RK3568_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

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