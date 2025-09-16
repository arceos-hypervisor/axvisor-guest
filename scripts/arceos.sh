#!/bin/bash

# ArceOS 构建脚本函数库

# 默认配置常量
readonly REPO_URL="https://github.com/arceos-hypervisor/arceos.git"
readonly DEFAULT_PLATFORM="axplat-aarch64-qemu-virt"
readonly DEFAULT_APP="examples/helloworld-myplat"
readonly DEFAULT_LINKER="link.x"
readonly DEFAULT_BOARD="all"
readonly DEFAULT_LOG="debug"
readonly DEFAULT_SMP=1

readonly OUTPUT="IMAGES"
readonly BUILD="build"

# 支持的平台列表
STATIC_PLATFORMS=("axplat-x86-pc" "axplat-aarch64-qemu-virt" "axplat-riscv64-qemu-virt" "axplat-loongarch64-qemu-virt")
DYN_PLATFORMS=("axplat-aarch64-dyn")

# 路径变量
PWD_DIR=$(pwd)
BUILD_DIR=$(realpath -m "$PWD_DIR/$BUILD")
LOG_FILE="${BUILD_DIR}/arceos_patch.log"
APP_NAME=$(basename "$DEFAULT_APP")
REPO_DIR="$BUILD_DIR/arceos"
PATCH_DIR=$(realpath -m "$PWD_DIR/patches/arceos")

# 全局变量初始化
init_vars() {
    LOG="$DEFAULT_LOG"
    PLATFORM="$DEFAULT_PLATFORM"
    LINKER="$DEFAULT_LINKER"
    SMP="$DEFAULT_SMP"
    BOARD="$DEFAULT_BOARD"
    APP="$DEFAULT_APP"

    FORCE_CLONE=false
    VERBOSE=false
}

# 显示帮助信息
show_help() {
    local script_name="${1:-$0}"
    cat << EOF
ArceOS 构建脚本

用法: $script_name [选项]

选项:
    -h, --help                  显示此帮助信息
    -a, --app APP               应用路径 (默认: $DEFAULT_APP)
    -l, --log LEVEL             日志级别 (默认: $DEFAULT_LOG)
    -p, --platform PLATFORM     完整平台名称 (默认: $DEFAULT_PLATFORM)
    -b, --board BOARD           开发板类型 (默认: $DEFAULT_BOARD)
    -s, --smp COUNT             SMP核心数 (默认: $DEFAULT_SMP)
    -f, --force-clone           强制重新克隆仓库
    -v, --verbose               启用详细输出

支持的开发板: all, qemu, phytiumpi, roc-rk3568-pc

示例:
    $script_name                                    # 使用默认配置构建
    $script_name -l info -p axplat-aarch64-dyn      # 设置日志级别和平台
    $script_name --force-clone --verbose            # 强制重新克隆并启用详细输出
    $script_name -b phytiumpi -s 4                  # 树莓派开发板，4核SMP
    $script_name -b qemu -s 2                       # QEMU模拟器，2核SMP

EOF
}

# 详细输出函数
log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo "🔍 $1"
    fi
}

log() { 
    printf '%s\n' "$*" >&2; echo "$(date '+%F %T') $*" >>"${LOG_FILE}";
}

# 错误处理函数
die() {
    echo "❌ 错误: $1" >&2
    exit "${2:-1}"
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--app)
                [[ -z "$2" || "$2" =~ ^- ]] && die "--app 需要一个参数"
                APP="$2"
                APP_NAME=$(basename "$APP")
                shift 2
                ;;
            -b|--board)
                [[ -z "$2" || "$2" =~ ^- ]] && die "--board 需要一个参数"
                BOARD="$2"
                shift 2
                ;;
            -p|--platform)
                [[ -z "$2" || "$2" =~ ^- ]] && die "--platform 需要一个参数"
                PLATFORM="$2"
                shift 2
                ;;
            -h|--help)
                show_help "$0"
                exit 0
                ;;
            -l|--log)
                [[ -z "$2" || "$2" =~ ^- ]] && die "--log 需要一个参数"
                LOG="$2"
                shift 2
                ;;
            -s|--smp)
                [[ -z "$2" || "$2" =~ ^- ]] && die "--smp 需要一个参数"
                if ! [[ "$2" =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                    die "SMP核心数必须是正整数"
                fi
                SMP="$2"
                shift 2
                ;;
            -f|--force-clone)
                FORCE_CLONE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                die "未知选项: $1\n使用 -h 或 --help 查看帮助信息"
                ;;
        esac
    done
}

# 显示配置信息
show_config() {
    echo "📋 当前配置:"
    echo "  构建目录: $BUILD_DIR"
    echo "  应用路径: $APP"
    echo "  应用名称: $APP_NAME"
    echo "  日志级别: $LOG"
    echo "  开发板型: $BOARD"
    echo "  SMP 核数: $SMP"
    echo "  详细输出: $VERBOSE"
    echo ""
}

# 克隆或更新ArceOS仓库
setup_repo() {
    if [ ! -d "$REPO_DIR" ] || [ "$FORCE_CLONE" = true ]; then
        if [ "$FORCE_CLONE" = true ] && [ -d "$REPO_DIR" ]; then
            echo "🗑️ 强制重新克隆，正在删除现有目录..."
            rm -rf "$REPO_DIR" || die "无法删除现有目录: $REPO_DIR"
        fi
        
        echo "📦 克隆ArceOS仓库..."
        if ! git clone "$REPO_URL" "$REPO_DIR"; then
            die "克隆仓库失败"
        fi
        echo "✅ 克隆完成！"
        apply_patches
    else
        echo "📁 ArceOS目录已存在，跳过克隆"
    fi
}

# 执行make命令
run_make() {
    local args="$1"
    
    echo "🔨 开始构建ArceOS..."
    echo "📋 构建参数: $args"
    echo "📍 构建目录: $REPO_DIR"
    

    make clean -C "$REPO_DIR" >/dev/null 2>&1
    
    if [ "$VERBOSE" = true ]; then
        make -C "$REPO_DIR" $args
    else
        make -C "$REPO_DIR" $args 2>&1 | \
        grep -E "(error|Error|ERROR|warning|Warning|WARNING|✅|❌|完成|失败|Finished)" || \
        make -C "$REPO_DIR" $args
    fi
    
    local result=$?
    if [ $result -ne 0 ]; then
        die "构建失败 (退出码: $result)"
    fi
}

# 创建必要目录并清空内容
create_dirs() {
    local output_dir="$1"
    
    # 创建目录（如果不存在）
    if ! mkdir -p "$output_dir"; then
        die "无法创建目录: $output_dir"
    fi
    
    log_verbose "准备目录: $output_dir"
}

# 构建动态版本
build_dynamic() {
    local platform="$1"
    local board="$2"
    local plat=$(echo "$platform" | sed 's/axplat-//')
    local arch=$(echo "$plat" | cut -d'-' -f1)
    local features="driver-dyn,page-alloc-4g"
    local args="A=$APP LOG=$LOG LD_SCRIPT=$LINKER MYPLAT=$platform APP_FEATURES=$plat FEATURES=$features"

    show_config
    
    if [ "$SMP" != "1" ]; then
        args="$args SMP=$SMP"
    fi

    run_make "$args"

    local output_dir=$(realpath -m "$PWD_DIR/$OUTPUT/$board/arceos")
    local output_file="$REPO_DIR/$APP/${APP_NAME}_${plat}.bin"
    create_dirs "$output_dir"
    copy_output "$output_file" "dyn" "$output_dir"
}

# 构建静态版本
build_static() {
    local platform="$1"
    local board="$2"
    local plat=$(echo "$platform" | sed 's/axplat-//')
    local arch=$(echo "$plat" | cut -d'-' -f1)
    local args="A=$APP LOG=$LOG MYPLAT=$platform APP_FEATURES=$plat"

    show_config
    
    if [ "$SMP" != "1" ]; then
        args="$args SMP=$SMP"
    fi

    run_make "$args"

    local output_dir=$(realpath -m "$PWD_DIR/$OUTPUT/$board/arceos/$arch")
    local output_file="$REPO_DIR/$APP/${APP_NAME}_${plat}.bin"
    create_dirs "$output_dir"
    copy_output "$output_file" "static" "$output_dir"
}

# 复制构建结果
copy_output() {
    local source="$1"
    local type="$2"
    local output_dir="$3"
    local target="arceos-${type}-smp${SMP}.bin"

    if [ -f "$source" ]; then
        echo "✅ 构建成功，生成的文件: $source"
        
        if cp "$source" "$output_dir/$target"; then
            echo "📁 文件已复制到: $output_dir/$target"
            
            local size
            size=$(ls -lh "$output_dir/$target" | awk '{print $5}')
            echo "📊 文件大小: $size"
        else
            die "复制文件失败: $source -> $output_dir/$target"
        fi
    else
        echo "❌ 构建失败，未找到输出文件: $source"
        echo "🔍 查找可能的输出文件..."
        
        local paths=("$REPO_DIR" "$REPO_DIR/examples")
        for path in "${paths[@]}"; do
            if [ -d "$path" ]; then
                echo "  在 $path 中查找:"
                find "$path" -name "*.bin" -type f -printf "    %p (%s bytes)\n" 2>/dev/null | head -3
            fi
        done
        
        die "构建输出验证失败"
    fi
}

apply_patches() {
    # Search patch directory
    if [[ ! -d "${PATCH_DIR}" ]]; then
        log "[PATCH] Directory not found: ${PATCH_DIR} (skip)"; return 0
    fi
    shopt -s nullglob
    local patch_files=("${PATCH_DIR}"/*.patch "${PATCH_DIR}"/*.diff)
    if (( ${#patch_files[@]} == 0 )); then
        log "[PATCH] No patch files in ${PATCH_DIR}"; return 0
    fi
    log "[PATCH] Found ${#patch_files[@]} patch file(s)"
    pushd "${REPO_DIR}" >/dev/null
    mkdir -p .patch_stamps
    for p in "${patch_files[@]}"; do
        [[ -f "$p" ]] || continue
        local base stamp type applied cid
        base=$(basename "$p")
        stamp=.patch_stamps/${base}.applied
        if [[ -f "$stamp" ]]; then
            log "[SKIP] $base (stamp exists)"; continue
        fi
        type="diff"
        if grep -q '^From [0-9a-f]\{7,40\} ' "$p" 2>/dev/null && grep -q '^Subject:' "$p" 2>/dev/null; then
            type="mbox"
        fi
        log "[APPLY] $base type=$type"
        applied=0
        if [[ $type == mbox ]]; then
            cid=$(grep -m1 '^From [0-9a-f]\{7,40\} ' "$p" | awk '{print $2}') || true
            if [[ -n "$cid" ]] && git rev-list --all | grep -q "^$cid"; then
                log "[SKIP] $base commit $cid already in history"; echo > "$stamp"; applied=1
            else
                if git am --keep-cr < "$p" >>"${LOG_FILE}" 2>&1; then
                    applied=1; echo > "$stamp"
                else
                    log "[WARN] git am failed; fallback to git apply path"; git am --abort || true
                fi
            fi
        fi
        if [[ $applied -eq 0 ]]; then
            if git apply --check "$p" >/dev/null 2>&1; then
                if git apply "$p" >>"${LOG_FILE}" 2>&1; then
                    applied=1; echo > "$stamp"; log "  git apply ok"
                fi
            else
                if git apply --reverse --check "$p" >/dev/null 2>&1; then
                    log "[INFO] $base appears already applied (reverse check)"; echo > "$stamp"; applied=1
                fi
            fi
        fi
        if [[ $applied -eq 0 ]]; then
            for plevel in 1 0; do
                if patch -p${plevel} --dry-run < "$p" >/dev/null 2>&1; then
                    if patch -p${plevel} < "$p" >>"${LOG_FILE}" 2>&1; then
                        applied=1; echo > "$stamp"; log "  fallback patch -p${plevel} applied"; break
                    fi
                fi
                vlog "  fallback patch -p${plevel} failed"
            done
        fi
        if [[ $applied -eq 0 ]]; then
            log "[ERROR] Cannot apply $base"; popd >/dev/null; return 1
        fi
    done
    popd >/dev/null
    return 0
}

build_all_boards_with_smp() {
    local smp_value="$1"

    echo "🔧 SMP=$smp_value 配置构建"

    SMP="$smp_value"
    
    for platform in "${STATIC_PLATFORMS[@]}"; do
        echo "    构建平台: $platform"
        build_static "$platform" "qemu"
    done
    echo "  构建 phytiumpi 动态平台..."
    for platform in "${DYN_PLATFORMS[@]}"; do
        echo "    构建平台: $platform"
        build_dynamic "$platform" "phytiumpi"
    done
    echo "  构建 roc-rk3568-pc 动态平台..."
    for platform in "${DYN_PLATFORMS[@]}"; do
        echo "    构建平台: $platform"
        build_dynamic "$platform" "roc-rk3568-pc"
    done
}


# 主函数
main() {
    set -euo pipefail
    
    echo "🚀 ArceOS 构建脚本启动"
    echo ""
    
    init_vars
    parse_args "$@"
    setup_repo
    
    # 根据开发板类型选择构建方法
    case "$BOARD" in
        "all")
            echo "🎯 构建所有平台版本"
            echo "  构建 qemu 所有静态平台..."
            local smp_configs=(1 2)
            
            for smp_val in "${smp_configs[@]}"; do
                build_all_boards_with_smp "$smp_val"
            done
            ;;
        "qemu")
            echo "🎯 QEMU开发板，构建所有静态支持的平台"
            echo "  构建平台: $PLATFORM"
            build_static "$PLATFORM" "qemu"
            ;;
        "phytiumpi" | "roc-rk3568-pc")
            echo "🎯 Phytium-Pi开发板，构建所有动态支持的平台"
            echo "  构建平台: $PLATFORM"
            build_dynamic "$PLATFORM" "$BOARD"
            ;;
        *)
            die "不支持的开发板类型: $BOARD\n支持的类型: all, qemu, phytiumpi, roc-rk3568-pc"
            ;;
    esac
    
    make clean -C "$REPO_DIR" >/dev/null 2>&1
    
    rm -rf "$PWD_DIR/target"

    echo ""
    echo "🎉 构建完成！"
}

# 如果作为独立脚本运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi