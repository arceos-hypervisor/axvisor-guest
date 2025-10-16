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
LINUX_SRC_DIR="${BUILD_DIR}/roc-rk3568-pc"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${ROOT_DIR}/patches/roc-rk3568-pc"
ARCEOS_PATCH_DIR="${ROOT_DIR}/patches/arceos"
LINUX_IMAGES_DIR="${ROOT_DIR}/IMAGES/roc-rk3568-pc/linux"
ARCEOS_IMAGES_DIR="${ROOT_DIR}/IMAGES/roc-rk3568-pc/arceos"

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
    REMOTE_HOST="10.3.10.194"
    REMOTE_DIR="/home/runner/repository/firefly_rk3568_sdk"
    REMOTE_IMAGES_DIR="output/RK3568-FIREFLY-ROC-PC-SE/latest/IMAGES"
    # Determine local IP addresses (IPv4) to detect if we are on REMOTE_HOST.
    # We collect all non-loopback IPv4 addresses assigned to the host.
    mapfile -t _local_ips < <(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1)

    is_remote=true
    for ipaddr in "${_local_ips[@]:-}"; do
        if [[ "$ipaddr" == "$REMOTE_HOST" ]]; then
            is_remote=false
            break
        fi
    done

    if [[ "$@" != *"clean"* ]]; then
        if $is_remote; then
            info "Building remotely via SSH: ssh ${REMOTE_HOST} cd '${REMOTE_DIR}' && ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh $@"
            ssh "${REMOTE_HOST}" "cd '${REMOTE_DIR}' && ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh $@"

            info "Copying build artifacts: -> $LINUX_IMAGES_DIR"
            mkdir -p "${LINUX_IMAGES_DIR}"
            scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/boot.img" "${LINUX_IMAGES_DIR}/"
            scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/parameter.txt" "${LINUX_IMAGES_DIR}/"
            scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/MiniLoaderAll.bin" "${LINUX_IMAGES_DIR}/"
            scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/../kernel/rk3568-firefly-roc-pc-se.dtb" "${LINUX_IMAGES_DIR}/"
            scp "${REMOTE_HOST}:${REMOTE_DIR}/kernel/arch/arm64/boot/Image" "${LINUX_IMAGES_DIR}/"
        else
            info "Detected REMOTE_HOST ($REMOTE_HOST) is the current machine; building locally in ${REMOTE_DIR}"
            # If the REMOTE_DIR doesn't exist locally, fall back to running commands in place (assume local repo available at REMOTE_DIR)
            if [[ -d "$REMOTE_DIR" ]]; then
                (cd "$REMOTE_DIR" && ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh $@)
            else
                # If REMOTE_DIR is unavailable, attempt to run build in current directory as a best-effort
                info "Local REMOTE_DIR ${REMOTE_DIR} not found; running ./build.sh here as fallback"
                ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh $@
            fi

            info "Copying build artifacts: -> $LINUX_IMAGES_DIR"
            mkdir -p "${LINUX_IMAGES_DIR}"
            cp "${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/boot.img" "${LINUX_IMAGES_DIR}/" 2>/dev/null || true
            cp "${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/parameter.txt" "${LINUX_IMAGES_DIR}/" 2>/dev/null || true
            cp "${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/MiniLoaderAll.bin" "${LINUX_IMAGES_DIR}/" 2>/dev/null || true
            cp "${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/../kernel/rk3568-firefly-roc-pc-se.dtb" "${LINUX_IMAGES_DIR}/" 2>/dev/null || true
            cp "${REMOTE_DIR}/kernel/arch/arm64/boot/Image" "${LINUX_IMAGES_DIR}/" 2>/dev/null || true
        fi
    else
        if $is_remote; then
            info "Cleaning remotely via SSH: ssh ${REMOTE_HOST} cd '${REMOTE_DIR}' && ./build.sh cleanall"
            ssh "${REMOTE_HOST}" "cd '${REMOTE_DIR}' && ./build.sh cleanall"
        else
            info "Detected REMOTE_HOST ($REMOTE_HOST) is the current machine; cleaning locally in ${REMOTE_DIR}"
            if [[ -d "$REMOTE_DIR" ]]; then
                (cd "$REMOTE_DIR" && ./build.sh cleanall)
            else
                info "Local REMOTE_DIR ${REMOTE_DIR} not found; running ./build.sh cleanall here as fallback"
                ./build.sh cleanall || true
            fi
        fi

        info "Removing ${LINUX_IMAGES_DIR}/*"
        rm -f ${LINUX_IMAGES_DIR}/* || true
    fi
}

linux() {
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
        cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_aarch64-dyn.bin" "$ARCEOS_IMAGES_DIR/arceos-aarch64-dyn-smp1.bin"
    else
        rm -rf $ARCEOS_IMAGES_DIR/arceos-aarch64-dyn-smp1.bin || true
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