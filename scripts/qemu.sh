#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 仓库 URL
LINUX_REPO_URL="https://github.com/torvalds/linux.git"
ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 源码目录
LINUX_SRC_DIR="${BUILD_DIR}/qemu_linux"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
LINUX_PATCH_DIR="${WORK_ROOT}/patches/qemu"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/arceos"

# 显示帮助信息
usage() {
    printf '%s\n' "QEMU Linux & ArceOS 构建工具"
    printf '\n用法:\n'
    printf '  scripts/qemu.sh <命令> <系统> [options]\n'
    printf '  scripts/qemu.sh help | -h | --help\n'

    printf '\n命令:\n'
    printf '  aarch64               构建 Linux 和 ArceOS (默认)\n'
    printf '  x86_64                仅构建 Linux 系统\n'
    printf '  riscv64               仅构建 ArceOS 系统\n'
    printf '  help, -h, --help      显示此帮助信息\n'

    printf '\n系统:\n'
    printf '  linux        构建 Linux 系统\n'
    printf '  arceos       构建 ArceOS 系统\n'
    printf '  all          构建所有系统 (默认)\n'

    printf '\n环境变量:\n'
    printf '  LINUX_REPO_URL        Linux 仓库地址\n'
    printf '  ARCEOS_REPO_URL       ArceOS 仓库地址\n'

    printf '\n示例:\n'
    printf '  scripts/qemu.sh aarch64 linux        # 构建 ARM64 Linux\n'
    printf '  scripts/qemu.sh x86_64 arceos        # 构建 x86_64 ArceOS\n'
    printf '  scripts/qemu.sh riscv64 all          # 构建 RISC-V 所有系统\n'
}

build_linux() {
    local commands=("$@")
    case "${ARCH}" in
        aarch64)
            local linux_arch="arm64"
            local cross_compile="${AARCH64_CROSS_COMPILE:-aarch64-linux-gnu-}"
            local defconfig="defconfig"
            local kimg_subpath="arch/arm64/boot/Image"
            ;;
        riscv64)
            local linux_arch="riscv"
            local cross_compile="${RISCV64_CROSS_COMPILE:-riscv64-linux-gnu-}"
            local defconfig="defconfig"
            local kimg_subpath="arch/riscv/boot/Image"
            ;;
        x86_64)
            local linux_arch="x86"
            local cross_compile="${X86_CROSS_COMPILE:-}"
            local defconfig="x86_64_defconfig"
            local kimg_subpath="arch/x86/boot/bzImage"
            ;;
        *)
            die "不支持的 Linux 架构: ${ARCH}"
            ;;
    esac
    
    pushd "${LINUX_SRC_DIR}" >/dev/null

    info "清理 Linux: make distclean"
    make distclean || true

    if [[ ${#commands[@]} -eq 0 ]] || [[ "${commands[0]}" == "all" ]]; then
        info "配置 Linux: make ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${defconfig}"
        make ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${defconfig}"
    fi
    
    info "构建 Linux: make -j$(nproc) ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${commands[@]}"
    make -j"$(nproc)" ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${commands[@]}"
    
    popd >/dev/null

    # 如果是完整构建，复制镜像和创建根文件系统
    if [[ ${#commands[@]} -eq 0 ]] || [[ "${commands[0]}" == "all" ]]; then
        mkdir -p "${LINUX_IMAGES_DIR}/${ARCH:-}"
        KIMG_PATH="${LINUX_SRC_DIR}/${kimg_subpath}"
        [[ -f "${KIMG_PATH}" ]] || die "内核镜像未找到: ${KIMG_PATH}"
        info "复制镜像: ${KIMG_PATH} -> ${LINUX_IMAGES_DIR}/${ARCH:-}"
        cp -f "${KIMG_PATH}" "${LINUX_IMAGES_DIR}/${ARCH:-}/"
        
        info "创建根文件系统: ${SCRIPT_DIR}/mkfs.sh -> ${LINUX_IMAGES_DIR}/${ARCH:-}"
        build_rootfs
    fi
}

cmd_build_linux() {
    info "克隆 ${ARCH} Linux 源码仓库 $LINUX_REPO_URL"
    clone_repository "$LINUX_REPO_URL" "$LINUX_SRC_DIR"

    info "应用补丁..."
    apply_patches "$LINUX_PATCH_DIR" "$LINUX_SRC_DIR"

    info "开始构建 ${ARCH} Linux 系统..."
    build_linux "$@"
}

build_rootfs() {
    if [ ! -f "${SCRIPT_DIR}/mkfs.sh" ]; then
        die "根文件系统脚本不存在: ${SCRIPT_DIR}/mkfs.sh"
    fi
    bash "${SCRIPT_DIR}/mkfs.sh" "${ARCH}" "--dir ${LINUX_IMAGES_DIR}/${ARCH:-}"
    success "根文件系统创建完成"
}

build_arceos() {
    case "${ARCH}" in
        aarch64)
            local platform="axplat-aarch64-dyn"
            local app_features="aarch64-dyn"
            ;;
        riscv64)
            local platform="axplat-riscv64-qemu-virt"
            local app_features="riscv64-qemu-virt"
            ;;
        x86_64)
            local platform="axplat-x86-pc"
            local app_features="x86-pc"
            ;;
        *)
            die "不支持的 ArceOS 架构: ${ARCH}"
            ;;
    esac

    pushd "$ARCEOS_SRC_DIR" >/dev/null
    info "清理旧构建文件：make clean"
    make clean >/dev/null 2>&1 || true

    if [ "${ARCH}" == "aarch64" ]; then
        local make_args="A=examples/helloworld-myplat LOG=info MYPLAT=$platform APP_FEATURES=$app_features LD_SCRIPT=link.x FEATURES=driver-dyn,page-alloc-4g SMP=1"
    else
        local make_args="A=examples/helloworld-myplat LOG=info MYPLAT=$platform APP_FEATURES=$app_features SMP=1"
    fi
    info "开始编译: make $make_args"
    make $make_args
    popd >/dev/null

    info "复制构建产物 -> $ARCEOS_IMAGES_DIR/${ARCH:-}"
    mkdir -p "$ARCEOS_IMAGES_DIR/${ARCH:-}"
    cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_$app_features.bin" "$ARCEOS_IMAGES_DIR/${ARCH:-}/arceos-dyn-smp1.bin"
}

cmd_build_arceos() {
    info "克隆 ArceOS 源码仓库 $ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "应用补丁..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "开始构建 ArceOS 系统..."
    build_arceos "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift 1 || true
    case "${cmd}" in
        help|-h|--help)
            usage
            exit 0
            ;;
        aarch64|riscv64|x86_64)
            ARCH="$cmd"
            SYSTEM="${1:-all}"
            shift 1 || true
            case "${SYSTEM}" in
                linux)
                    cmd_build_linux "$@"
                    ;;
                arceos)
                    cmd_build_arceos "$@"
                    ;;
                all)
                    cmd_build_linux "$@"

                    cmd_build_arceos "$@"
                    ;;
                *)
                    die "未知系统: "${SYSTEM}" (支持: linux, arceos, all)"
                    ;;
            esac
            ;;
        "")
            for arch in aarch64 riscv64 x86_64; do
                ARCH="$arch"
                info "=== 构建架构: $ARCH ==="
                cmd_build_linux "$@"

                cmd_build_arceos "$@"
            done
            ;;
        *)
        die "未知命令: $cmd" >&2
        ;;
    esac
fi