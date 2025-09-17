#!/usr/bin/env bash
# Phytium Pi OS 构建脚本 - 支持 Linux 和 ArceOS 构建

set -euo pipefail

#==============================================================================
# 全局常量和默认配置
#==============================================================================
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${WORK_ROOT}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# 环境变量默认值
VERBOSE="${VERBOSE:-0}"

# 仓库 URL
LINUX_REPO_URL=""
ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 目录配置
LINUX_PATCH_DIR="${WORK_ROOT}/patches/roc-rk3568-pc"
ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/roc-rk3568-pc/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/roc-rk3568-pc/arceos"

# 源码目录
ARCEOS_SRC_DIR="${BUILD_DIR}/arceos"


# ArceOS 默认配置
readonly DEFAULT_PLATFORM="axplat-aarch64-dyn"
readonly DEFAULT_APP="examples/helloworld-myplat"
readonly DEFAULT_LINKER="link.x"
readonly DEFAULT_LOG_LEVEL="debug"

# 输出帮助信息
usage() {
    cat << EOF
${SCRIPT_NAME} - ROC-RK3568-PC OS 构建助手

用法:
  ${SCRIPT_NAME} [命令] [选项]

命令:
  all               构建 Linux 和 ArceOS (默认)
  linux             仅构建 Linux 系统
  arceos            仅构建 ArceOS 系统
  -h, --help        显示此帮助信息

ArceOS 选项:
  -a, --app PATH            应用路径 (默认: ${DEFAULT_APP})
  -p, --platform PLATFORM   平台名称 (默认: ${DEFAULT_PLATFORM})
  -l, --log LEVEL           日志级别 (默认: ${DEFAULT_LOG_LEVEL})
  -s, --smp COUNT           SMP 核心数

环境变量:
  LINUX_REPO_URL            Linux 仓库 URL
  ARCEOS_REPO_URL           ArceOS 仓库 URL
  VERBOSE=1                 启用详细日志输出和编译过程显示

构建流程:
  1. 克隆仓库 (如果不存在)
  2. 应用补丁 (幂等操作)
  3. 配置和编译
  4. 复制构建产物到镜像目录

示例:
  ${SCRIPT_NAME}                    # 构建全部
  ${SCRIPT_NAME} linux              # 仅构建 Linux
  ${SCRIPT_NAME} arceos -s 4        # 构建 ArceOS (4核)
  ${SCRIPT_NAME} remove all         # 删除所有源码
  VERBOSE=1 ${SCRIPT_NAME} linux    # 详细模式构建 Linux (显示编译过程)

EOF
}

# 构建 Linux 系统
cmd_build_linux() {
    echo "🚀 开始构建 Phytium Pi Linux 系统"
    echo "=================================="
    
    # 显示构建结果
    echo ""
    echo "🎉 Linux 系统构建完成！"
    echo "📁 构建产物位置: $LINUX_IMAGES_DIR"
    
    if command -v ls >/dev/null 2>&1; then
        echo "📊 构建产物列表:"
        ls -lh "$LINUX_IMAGES_DIR" | while read -r line; do
            echo "   $line"
        done
    fi
}

# ArceOS 全局变量
declare -g ARCEOS_LOG_LEVEL="$DEFAULT_LOG_LEVEL"
declare -g ARCEOS_PLATFORM="$DEFAULT_PLATFORM"
declare -g ARCEOS_LINKER="$DEFAULT_LINKER"
declare -g ARCEOS_APP="$DEFAULT_APP"
declare -g ARCEOS_APP_NAME

# 初始化 ArceOS 变量
init_arceos_vars() {
    ARCEOS_LOG_LEVEL="$DEFAULT_LOG_LEVEL"
    ARCEOS_PLATFORM="$DEFAULT_PLATFORM"
    ARCEOS_LINKER="$DEFAULT_LINKER"
    ARCEOS_APP="$DEFAULT_APP"
    ARCEOS_APP_NAME="$(basename "$ARCEOS_APP")"
}

# 显示 ArceOS 帮助
show_arceos_help() {
    cat << EOF
ArceOS 构建选项:

  -a, --app PATH           应用路径 (默认: $DEFAULT_APP)
  -p, --platform PLATFORM 平台名称 (默认: $DEFAULT_PLATFORM)
  -l, --log LEVEL          日志级别 (默认: $DEFAULT_LOG_LEVEL)
#   -s, --smp COUNT          SMP 核心数 (默认: $DEFAULT_SMP)
  -h, --help               显示此帮助信息

示例:
  $SCRIPT_NAME arceos -a examples/myapp -s 4
  $SCRIPT_NAME arceos --platform axplat-x86_64-dyn --log info
EOF
}

# 解析 ArceOS 命令行参数
parse_arceos_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--app)
                [[ -z "${2:-}" || "$2" =~ ^- ]] && die "--app 需要一个参数"
                ARCEOS_APP="$2"
                ARCEOS_APP_NAME="$(basename "$ARCEOS_APP")"
                shift 2
                ;;
            -p|--platform)
                [[ -z "${2:-}" || "$2" =~ ^- ]] && die "--platform 需要一个参数"
                ARCEOS_PLATFORM="$2"
                shift 2
                ;;
            -l|--log)
                [[ -z "${2:-}" || "$2" =~ ^- ]] && die "--log 需要一个参数"
                ARCEOS_LOG_LEVEL="$2"
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
            -h|--help)
                show_arceos_help
                exit 0
                ;;
            *)
                die "未知的 ArceOS 选项: $1"
                ;;
        esac
    done
}

# 执行 ArceOS make 命令
run_arceos_make() {
    local make_args="$1"
    local src_dir="$2"
    
    info "开始构建 ArceOS..."
    info "构建参数: $make_args"
    info "源码目录: $src_dir"
    
    # 清理之前的构建
    make clean -C "$src_dir" >/dev/null 2>&1 || true
    
    # 执行构建
    if [[ $VERBOSE -eq 1 ]]; then
        make -C "$src_dir" $make_args 2>&1
        local make_result=${PIPESTATUS[0]}
    else
        make -C "$src_dir" $make_args 2>&1
        local make_result=$?
    fi
    
    if [[ $make_result -ne 0 ]]; then
        die "ArceOS 构建失败"
    fi
    
    success "ArceOS 构建完成"
}

# 复制 ArceOS 构建产物
copy_arceos_output() {
    local source="$1"
    local build_type="$2"
    
    local target="arceos-${build_type}-smp${ARCEOS_SMP}.bin"
    local dest_path="$ARCEOS_IMAGES_DIR/$target"
    
    # 确保目标目录存在
    mkdir -p "$ARCEOS_IMAGES_DIR" || die "无法创建目录: $ARCEOS_IMAGES_DIR"
    
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

# 构建动态版本 ArceOS
build_arceos() {
    local platform="$1"
    local src_dir="$2"
    
    # 解析平台信息
    local plat="$(echo "$platform" | sed 's/axplat-//')"
    local arch="$(echo "$plat" | cut -d'-' -f1)"
    local features="driver-dyn,page-alloc-4g"
    
    # 构建 make 参数
    local make_args="A=$ARCEOS_APP LOG=$ARCEOS_LOG_LEVEL LD_SCRIPT=$ARCEOS_LINKER"
    make_args="$make_args MYPLAT=$platform APP_FEATURES=$plat FEATURES=$features"
    
    if [[ "$ARCEOS_SMP" != "1" ]]; then
        make_args="$make_args SMP=$ARCEOS_SMP"
    fi
    
    # 执行构建
    run_arceos_make "$make_args" "$src_dir"
    
    # 查找构建产物
    local output_file="$src_dir/$ARCEOS_APP/${ARCEOS_APP_NAME}_${plat}.bin"
    
    # 复制构建产物
    copy_arceos_output "$output_file" "dyn"
}

# 构建 ArceOS 系统
cmd_build_arceos() {
    echo "🚀 开始构建 ArceOS 系统"
    echo "========================"
    
    # 初始化变量
    init_arceos_vars
    
    # 解析命令行参数
    parse_arceos_args "$@"
    
    # 显示配置信息
    info "ArceOS 构建配置:"
    info "  应用: $ARCEOS_APP"
    info "  平台: $ARCEOS_PLATFORM"
    info "  日志级别: $ARCEOS_LOG_LEVEL"
    info "  SMP 核心数: $ARCEOS_SMP"
    
    # 克隆仓库
    clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"
    
    # 应用补丁
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"
    
    # 构建系统
    build_arceos "$ARCEOS_PLATFORM" "$ARCEOS_SRC_DIR"
    
    # 清理临时文件
    # make clean -C "$ARCEOS_SRC_DIR" >/dev/null 2>&1 || true
    rm -rf "${WORK_ROOT}/target" 2>/dev/null || true
    
    echo ""
    echo "🎉 ArceOS 系统构建完成！"
    echo "📁 构建产物位置: $ARCEOS_IMAGES_DIR"
    
    if command -v ls >/dev/null 2>&1; then
        echo "📊 构建产物列表:"
        ls -lh "$ARCEOS_IMAGES_DIR" | while read -r line; do
            echo "   $line"
        done
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    
    # 处理命令
    case "$cmd" in
        -h|--help)
            usage
            exit 0
            ;;
        linux)
            echo "not implemented yet"
            # cmd_build_linux
            ;;
        arceos)
            if [ -z "${ARCEOS_SMP:-}" ]; then
                echo "ARCEOS_SMP未定义，将构建多个SMP配置..."
                smp_args=(1 2)
                for smp in "${smp_args[@]}"; do
                    echo "=== 构建 SMP=$smp 配置 ==="
                    ARCEOS_SMP=$smp
                    cmd_build_arceos "$@"
                    echo ""
                done
                exit 0
            else
                cmd_build_arceos "$@"
            fi
            ;;
        all|"")
            info "构建所有系统 (Linux + ArceOS)"
            # cmd_build_linux
            echo ""
            if [ -z "${ARCEOS_SMP:-}" ]; then
                smp_args=(1 2)
                for smp in "${smp_args[@]}"; do
                    ARCEOS_SMP=$smp
                    cmd_build_arceos "$@"
                    echo ""
                done
                exit 0
            else
                cmd_build_arceos "$@"
            fi
            ;;
        *)
            echo "❌ 未知命令: $cmd" >&2
            echo ""
            usage
            exit 2
            ;;
    esac
fi