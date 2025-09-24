#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 仓库 URL
TAC_E400_LINUX_REPO_URL="git@github.com:arceos-hypervisor/tac-e400-plc.git"
TAC_E400_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 目录配置
LINUX_SRC_DIR="${BUILD_DIR}/tac-e400-plc"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${WORK_ROOT}/patches/tac-e400-plc"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/tac-e400-plc/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/tac-e400-plc/arceos"

# 输出帮助信息
usage() {
    printf '适用于 TAC-E400 系列智能 PLC 产品的 Linux & ArceOS 构建脚本\n'
    printf '\n'
    printf '用法:\n'
    printf '  scriptstac-e400-plc.sh [命令] [选项]\n'
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
    printf '  scripts/tac-e400-plc.sh all                # 构建全部\n'
    printf '  scripts/tac-e400-plc.sh linux              # 仅构建 Linux\n'
}

build_linux() {
    pushd "$LINUX_SRC_DIR/EDGE_KERNEL" >/dev/null

    info "配置内核：cp "$LINUX_SRC_DIR/.config" .config"
    cp "$LINUX_SRC_DIR/.config" .config

    info "开始编译: make -j$(nproc)"
    make -j$(nproc) 2>&1

    popd >/dev/null

    info "复制构建产物 -> $LINUX_IMAGES_DIR"
    mkdir -p "$LINUX_IMAGES_DIR"
    cp "$LINUX_SRC_DIR/EDGE_KERNEL/arch/arm64/boot/Image" "$LINUX_IMAGES_DIR/"
    cp "$LINUX_SRC_DIR/EDGE_KERNEL/arch/arm64/boot/dts/phytium/e2000q-hanwei-board.dtb" "$LINUX_IMAGES_DIR/"
}

linux() {
    info "克隆 Linux 源码仓库 $TAC_E400_LINUX_REPO_URL -> $LINUX_SRC_DIR"
    clone_repository "$TAC_E400_LINUX_REPO_URL" "$LINUX_SRC_DIR"

    info "应用补丁..."
    apply_patches "$LINUX_PATCH_DIR" "$LINUX_SRC_DIR"

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
    info "克隆 ArceOS 源码仓库 $TAC_E400_ARCEOS_REPO_URL"
    clone_repository "$TAC_E400_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

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
