#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 仓库 URL
ROC_RK3568_LINUX_REPO_URL=""
ROC_RK3568_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 目录配置
LINUX_SRC_DIR="${BUILD_DIR}/roc-rk3588-pc"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${WORK_ROOT}/patches/roc-rk3588-pc"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/roc-rk3588-pc/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/roc-rk3588-pc/arceos"

# 输出帮助信息
usage() {
    printf '%s\n' "${0} - Phytium Pi OS 构建助手"
    printf '\n用法:\n'
    printf '  %s [命令] [选项]\n' "$0"
    printf '\n命令:\n'
    printf '  all               构建 Linux 和 ArceOS (默认)\n'
    printf '  linux             仅构建 Linux 系统\n'
    printf '  arceos            仅构建 ArceOS 系统\n'
    printf '  help, -h, --help  显示此帮助信息\n'
    printf '\n环境变量:\n'
    printf '  ROC_RK3568_LINUX_REPO_URL    Linux 仓库 URL\n'
    printf '  ROC_RK3568_ARCEOS_REPO_URL   ArceOS 仓库 URL\n'
    printf '\n构建流程:\n'
    printf '  1. 克隆仓库 (如果不存在)\n'
    printf '  2. 应用补丁 (幂等操作)\n'
    printf '  3. 配置和编译\n'
    printf '  4. 复制构建产物到镜像目录\n'
    printf '\n示例:\n'
    printf '  %s                    # 构建全部\n' "$0"
    printf '  %s linux              # 仅构建 Linux\n' "$0"
}

build_linux() {
    # 由于瑞芯微的 Linux SDK 是由 repo 管理的大型仓库，且各厂家也不提供在线仓库（通常只给了压缩包），因此这里我们 SSH 登录准备好的 SDK 服务器进行构建
    REMOTE_HOST="10.0.0.110"
    REMOTE_DIR="/runner/firefly_rk3568_sdk"
    REMOTE_IMAGES_DIR="output/RK3568-FIREFLY-ROC-PC-SE/latest/IMAGES"

    info "通过 SSH 登录远程服务器构建..."
    ssh "${REMOTE_HOST}" "cd '${REMOTE_DIR}' && ./build.sh firefly_rk3568_roc-rk3568-pc_ubuntu_defconfig && ./build.sh"

    info "复制构建产物: -> $LINUX_IMAGES_DIR"
    mkdir -p "${LINUX_IMAGES_DIR}"
    scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/boot.img" "${LINUX_IMAGES_DIR}/"
    scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/parameter.txt" "${LINUX_IMAGES_DIR}/"
    scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/MiniLoaderAll.bin" "${LINUX_IMAGES_DIR}/"
    scp "${REMOTE_HOST}:${REMOTE_DIR}/${REMOTE_IMAGES_DIR}/../kernel/rk3568-firefly-roc-pc-se.dtb" "${LINUX_IMAGES_DIR}/"
    scp "${REMOTE_HOST}:${REMOTE_DIR}/kernel/arch/arm64/boot/Image" "${LINUX_IMAGES_DIR}/"
}

linux() {
    info "开始构建 Linux 系统..."
    build_linux "$@"
}

build_arceos() {
    pushd "$ARCEOS_SRC_DIR" >/dev/null
    info "清理旧构建文件：make clean"
    make clean >/dev/null 2>&1 || true

    info "开始编译: make A=examples/helloworld-myplat LOG=debug LD_SCRIPT=link.x MYPLAT=axplat-aarch64-dyn APP_FEATURES=aarch64-dyn FEATURES=driver-dyn,page-alloc-4g SMP=1"
    make A=examples/helloworld-myplat LOG=debug LD_SCRIPT=link.x MYPLAT=axplat-aarch64-dyn APP_FEATURES=aarch64-dyn FEATURES=driver-dyn,page-alloc-4g SMP=1
    popd >/dev/null

    info "复制构建产物 -> $ARCEOS_IMAGES_DIR"
    mkdir -p "$ARCEOS_IMAGES_DIR"
    cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_aarch64-dyn.bin" "$ARCEOS_IMAGES_DIR/arceos-dyn-smp1.bin"
}

arceos() {
    info "克隆 ArceOS 源码仓库 $ROC_RK3568_ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ROC_RK3568_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "应用补丁..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "开始构建 ArceOS 系统..."
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
        *)
            die "未知命令: $cmd" >&2
            ;;
    esac
fi