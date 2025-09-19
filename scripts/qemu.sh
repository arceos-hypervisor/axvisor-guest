#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 环境变量
VERBOSE="${VERBOSE:-0}"

# 仓库 URL
LINUX_REPO_URL="https://github.com/torvalds/linux.git"
ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 源码目录
LINUX_SRC_DIR="${BUILD_DIR}/qemu_linux"
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/arceos"

# ArceOS 默认配置
readonly DEFAULT_ARCEOS_PLATFORM="axplat-aarch64-dyn"
readonly DEFAULT_ARCEOS_APP="examples/helloworld-myplat"
readonly DEFAULT_ARCEOS_LOG="debug"
declare -g ARCEOS_APP="$DEFAULT_ARCEOS_APP"
declare -g ARCEOS_LOG="$DEFAULT_ARCEOS_LOG"

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

    printf '\nArceOS 选项:\n'
    printf '  -a, --app APP         应用程序路径\n'
    printf '  -l, --log LEVEL       日志级别 (debug, info, warn, error)\n'
    printf '  -s, --smp COUNT       SMP 核心数\n'

    printf '\n环境变量:\n'
    printf '  VERBOSE=1             显示详细构建过程\n'
    printf '  LINUX_REPO_URL        Linux 仓库地址\n'
    printf '  ARCEOS_REPO_URL       ArceOS 仓库地址\n'

    printf '\n示例:\n'
    printf '  scripts/qemu.sh aarch64 linux        # 构建 ARM64 Linux\n'
    printf '  scripts/qemu.sh x86_64 arceos        # 构建 x86_64 ArceOS\n'
    printf '  scripts/qemu.sh riscv64 all          # 构建 RISC-V 所有系统\n'
    printf '  scripts/qemu.sh aarch64 arceos -s 4  # 构建 4核 ARM64 ArceOS\n'
}

run_make() {
    local make_args=("$@")
    
    if [[ $VERBOSE -eq 1 ]]; then
        info "执行: make ${make_args[*]}"
        make "${make_args[@]}"
    else
        info "执行: make ${make_args[*]}"
        make "${make_args[@]}" >/dev/null 2>&1
    fi
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
        run_make ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${defconfig}"
    fi
    
    info "构建 Linux: make -j$(nproc) ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${commands[*]:-}"
    run_make -j"$(nproc)" ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${commands[@]}"
    
    popd >/dev/null

    # 如果是完整构建，复制镜像和创建根文件系统
    if [[ ${#commands[@]} -eq 0 ]] || [[ "${commands[0]}" == "all" ]]; then
        IMAGES_DIR="${LINUX_IMAGES_DIR}/${ARCH}"
        mkdir -p "${IMAGES_DIR}"
        KIMG_PATH="${LINUX_SRC_DIR}/${kimg_subpath}"
        [[ -f "${KIMG_PATH}" ]] || die "内核镜像未找到: ${KIMG_PATH}"
        info "复制镜像: ${KIMG_PATH} -> ${IMAGES_DIR}/"
        cp -f "${KIMG_PATH}" "${IMAGES_DIR}/"
        success "镜像复制完成"
        
        build_rootfs
    fi
}

cmd_build_linux() {
    info "克隆 ${ARCH} Linux 源码仓库 $LINUX_REPO_URL"
    clone_repository "$LINUX_REPO_URL" "$LINUX_SRC_DIR"

    info "开始构建 ${ARCH} Linux 系统..."
    build_linux "$@"
}

# 创建根文件系统
build_rootfs() {
    if [ ! -f "${SCRIPT_DIR}/mkfs.sh" ]; then
        die "根文件系统脚本不存在: ${SCRIPT_DIR}/mkfs.sh"
    fi
    info "创建根文件系统: ${SCRIPT_DIR}/mkfs.sh -> ${IMAGES_DIR}"
    OUT_DIR=${IMAGES_DIR}
    export OUT_DIR
    bash "${SCRIPT_DIR}/mkfs.sh" "${ARCH}"
    success "根文件系统创建完成"
}

parse_arceos_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--app)
                [[ -z "${2:-}" || "$2" =~ ^- ]] && die "--app 需要一个参数"
                ARCEOS_APP="$2"
                shift 2
                ;;
            -l|--log)
                [[ -z "${2:-}" || "$2" =~ ^- ]] && die "--log 需要一个参数"
                ARCEOS_LOG="$2"
                shift 2
                ;;
            -s|--smp)
                [[ -z "${2:-}" || "$2" =~ ^- ]] && die "--smp 需要一个参数"
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]]; then
                    die "SMP 核心数必须是正整数"
                fi
                ARCEOS_SMP="$2"
                shift 2
                ;;
            clean|all)
                # 将构建命令返回给调用者
                echo "$1"
                shift
                ;;
            *)
                die "未知的 ArceOS 参数: $1"
                ;;
        esac
    done
}

copy_arceos_output() {
    local source="$1"
    local build_type="$2"
    local arch="$3"
    
    local target="arceos-${build_type}-smp${ARCEOS_SMP}.bin"
    local dest_path="$ARCEOS_IMAGES_DIR/$arch/$target"
    
    # 确保目标目录存在
    mkdir -p "$ARCEOS_IMAGES_DIR/$arch" || die "无法创建目录: $ARCEOS_IMAGES_DIR/$arch"
    
    if [[ -f "$source" ]]; then
        success "找到构建产物: $source"
        
        if cp "$source" "$dest_path"; then
            success "文件已复制到: $dest_path"
            
            # 显示文件信息
            if command -v ls >/dev/null 2>&1; then
                local file_size
                file_size="$(ls -lh "$dest_path" | awk '{print $5}')"
                info "文件大小: $file_size"
            fi
        else
            die "复制文件失败: $source -> $dest_path"
        fi
    else
        warn "未找到构建产物: $source"
        info "搜索可能的输出文件..."
        
        # 搜索可能的构建产物
        local search_paths=("$ARCEOS_SRC_DIR" "$ARCEOS_SRC_DIR/examples")
        for path in "${search_paths[@]}"; do
            if [[ -d "$path" ]]; then
                info "在 $path 中搜索:"
                if command -v find >/dev/null 2>&1; then
                    find "$path" -name "*.bin" -type f -printf "    %p (%s bytes)\n" 2>/dev/null | head -3
                fi
            fi
        done
        
        die "构建产物验证失败"
    fi
}

build_arceos() {
    local remaining_args=("$@")
    
    # 初始化 ArceOS 变量
    ARCEOS_APP="$DEFAULT_ARCEOS_APP"
    ARCEOS_LOG="$DEFAULT_ARCEOS_LOG"

    # 解析 ArceOS 特定参数
    local build_commands=()
    local parsed_commands
    
    # 解析参数并提取构建命令
    for arg in "${remaining_args[@]}"; do
        if [[ "$arg" =~ ^(clean|all)$ ]]; then
            build_commands+=("$arg")
        fi
    done
    
    # 解析 ArceOS 选项
    parse_arceos_args "${remaining_args[@]}"
    
    # 设置架构相关配置
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

    pushd "${ARCEOS_SRC_DIR}" >/dev/null
    
    # 处理清理命令
    if [[ " ${build_commands[*]} " =~ " clean " ]]; then
        info "清理 ArceOS 构建文件"
        run_make clean || true
        popd >/dev/null
        return 0
    fi
    
    # 构建 ArceOS
    local app_name="$(basename "$ARCEOS_APP")"

    if [ "${ARCH}" == "aarch64" ]; then
        local make_args="A=$ARCEOS_APP MYPLAT=$platform APP_FEATURES=$app_features LOG=$ARCEOS_LOG LD_SCRIPT=link.x FEATURES=driver-dyn,paging"
    else
        local make_args="A=$ARCEOS_APP MYPLAT=$platform APP_FEATURES=$app_features LOG=$ARCEOS_LOG"
    fi

    if [[ "$ARCEOS_SMP" != "1" ]]; then
        make_args="$make_args SMP=$ARCEOS_SMP"
    fi
    
    info "ArceOS 构建配置:"
    info "  应用: $ARCEOS_APP"
    info "  平台: $platform"
    info "  日志级别: $ARCEOS_LOG"
    info "  SMP 核心数: $ARCEOS_SMP"
    
    info "构建 ArceOS: make ${make_args}"

    make clean -C "$ARCEOS_SRC_DIR" >/dev/null 2>&1 || true

    if [[ $VERBOSE -eq 1 ]]; then
        make -C "$ARCEOS_SRC_DIR" $make_args
    else
        make -C "$ARCEOS_SRC_DIR" $make_args >/dev/null 2>&1
    fi
    
    popd >/dev/null
    
    # 查找并复制构建产物
    local possible_output="${ARCEOS_SRC_DIR}/${ARCEOS_APP}/${app_name}_${app_features}.bin"

    if [ "${ARCH}" == "aarch64" ]; then
        copy_arceos_output "$possible_output" "dyn" "${ARCH}"
    else
        copy_arceos_output "$possible_output" "static" "${ARCH}"
    fi
}

cmd_build_arceos() {
    info "克隆 ${ARCH} ArceOS 源码仓库：$ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "应用补丁..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "开始构建 ${ARCH} ArceOS 系统..."
    if [ -z "${ARCEOS_SMP:-}" ]; then
        smp_args=(1 2)
        for smp in "${smp_args[@]}"; do
            echo "=== 构建 SMP = $smp 配置 ==="
            ARCEOS_SMP=$smp
            build_arceos "$@"
            echo ""
        done
        exit 0
    else
        build_arceos "$@"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift 1 || true
    case "${cmd}" in
        help|-h|--help|"")
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
        *)
        die "未知命令: $cmd" >&2
        ;;
    esac
fi