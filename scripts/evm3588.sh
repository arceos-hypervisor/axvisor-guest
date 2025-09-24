#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 仓库 URL
EVM3588_LINUX_REPO_URL=""
EVM3588_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 目录配置
LINUX_SRC_DIR="${BUILD_DIR}/evm3588"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${WORK_ROOT}/patches/evm3588"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/evm3588/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/evm3588/arceos"

# 输出帮助信息
usage() {
    printf '适用于 EVM3588 开发板的 Linux & ArceOS 构建脚本\n'
    printf '\n'
    printf '用法:\n'
    printf '  scripts/evm3588.sh [命令] [选项]\n'
    printf '\n'
    printf '命令:\n'
    printf '  all               构建 Linux 和 ArceOS (默认)\n'
    printf '  linux             仅构建 Linux 系统\n'
    printf '  arceos            仅构建 ArceOS 系统\n'
    printf '  help, -h, --help  显示此帮助信息\n'
    printf '\n'
    printf '环境变量:\n'
    printf '  PHYTIUM_LINUX_REPO_URL    Linux 仓库 URL\n'
    printf '  PHYTIUM_ARCEOS_REPO_URL   ArceOS 仓库 URL\n'
    printf '\n'
    printf '示例:\n'
    printf '  scripts/evm3588.sh all                # 构建全部\n'
    printf '  scripts/evm3588.sh linux              # 仅构建 Linux\n'
}

build_linux() {
    # 由于瑞芯微的 Linux SDK 是由 repo 管理的大型仓库，且各厂家也不提供在线仓库（通常只给了压缩包），因此这里我们 SSH 登录准备好的 SDK 服务器进行构建
    REMOTE_HOST="10.0.0.110"
    REMOTE_DIR="/runner/evm3588_linux_sdk_v1.0.3"

    info "通过 SSH 登录远程服务器构建..."
    ssh "${REMOTE_HOST}" "cd '${REMOTE_DIR}' && ./build.sh cleanall  && ./build.sh BoardConfig-evm3588.mk && ./build.sh kernel"

    info "复制构建产物: -> $LINUX_IMAGES_DIR"
    mkdir -p "${LINUX_IMAGES_DIR}"
    scp "${REMOTE_HOST}:${REMOTE_DIR}/kernel/arch/arm64/boot/dts/rockchip/evm3588.dtb" "${LINUX_IMAGES_DIR}/"
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
    info "克隆 ArceOS 源码仓库 $EVM3588_ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$EVM3588_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

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