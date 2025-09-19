#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 仓库 URL
RK3568_LINUX_REPO_URL="https://gitee.com/phytium_embedded/phytium-pi-os.git"
RK3568_ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 目录配置
LINUX_SRC_DIR="${BUILD_DIR}/phytium-pi-os"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${WORK_ROOT}/patches/phytiumpi"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/phytiumpi/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/phytiumpi/arceos"

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
    printf '  RK3568_LINUX_REPO_URL    Linux 仓库 URL\n'
    printf '  RK3568_ARCEOS_REPO_URL   ArceOS 仓库 URL\n'
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
    pushd "$LINUX_SRC_DIR" >/dev/null
    info "配置构建: make phytiumpi_desktop_defconfig"
    make phytiumpi_desktop_defconfig

    info "开始编译: make"
    make
    popd >/dev/null
    
    info "复制构建产物: $LINUX_SRC_DIR/output/images -> $LINUX_IMAGES_DIR"
    mkdir -p "$LINUX_IMAGES_DIR"
    if ! cp -a "$LINUX_SRC_DIR/output/images/* $LINUX_IMAGES_DIR/"; then
        die "复制构建产物失败"
    fi
}

cmd_build_linux() {
    info "克隆 Linux 源码仓库 $RK3568_LINUX_REPO_URL"
    clone_repository "$RK3568_LINUX_REPO_URL" "$LINUX_SRC_DIR"
    
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

cmd_build_arceos() {
    info "克隆 ArceOS 源码仓库 $RK3568_ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$RK3568_ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "应用补丁..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "开始构建 ArceOS 系统..."
    build_arceos "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        -h|--help|help)
            usage
            exit 0
            ;;
        linux)
            cmd_build_linux "$@"
            ;;
        arceos)
            cmd_build_arceos "$@"
            ;;
        all|"")
            cmd_build_linux "$@"

            cmd_build_arceos "$@"
            ;;
        *)
            die "未知命令: $cmd" >&2
            ;;
    esac
fi