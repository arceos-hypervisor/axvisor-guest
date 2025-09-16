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

# 环境变量
VERBOSE="${VERBOSE:-0}"

ARCEOS_PATCH_DIR="${WORK_ROOT}/patches/arceos"
ARCEOS_LOG_FILE="${BUILD_DIR}/qemu_arceos_patch.log"

LINUX_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/linux"
ARCEOS_IMAGES_DIR="${WORK_ROOT}/IMAGES/qemu/arceos"

# ArceOS 默认配置
readonly DEFAULT_ARCEOS_PLATFORM="axplat-aarch64-dyn"
readonly DEFAULT_ARCEOS_APP="examples/helloworld-myplat"
readonly DEFAULT_ARCEOS_LOG="debug"


# 显示帮助信息
usage() {
    cat << 'EOF'
QEMU Linux & ArceOS 构建工具

用法:
  scripts/qemu.sh <arch> <system> [command] [options]
  scripts/qemu.sh help | -h | --help

架构:
  aarch64      ARM64 架构
  x86_64       x86_64 架构
  riscv64      RISC-V 64位架构

系统:
  linux        构建 Linux 系统
  arceos       构建 ArceOS 系统
  all          构建所有系统 (默认)

命令:
  (default)    配置并构建系统
  clean        清理构建文件
  all          构建所有目标

ArceOS 选项:
  -a, --app APP         应用程序路径
  -l, --log LEVEL       日志级别 (debug, info, warn, error)
  -s, --smp COUNT       SMP 核心数

环境变量:
  VERBOSE=1             显示详细构建过程
  LINUX_REPO_URL        Linux 仓库地址
  ARCEOS_REPO_URL       ArceOS 仓库地址

示例:
  scripts/qemu.sh aarch64 linux        # 构建 ARM64 Linux
  scripts/qemu.sh x86_64 arceos        # 构建 x86_64 ArceOS
  scripts/qemu.sh riscv64 all          # 构建 RISC-V 所有系统
  scripts/qemu.sh aarch64 arceos -s 4  # 构建 4核 ARM64 ArceOS
EOF
}

# 日志函数
log() {
    printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*" >&2
}

vlog() {
    [[ $VERBOSE -eq 1 ]] && log "$@" || true
}

die() {
    log "❌ 错误: $1"
    exit "${2:-1}"
}

success() {
    log "✅ $1"
}

info() {
    log "ℹ️  $1"
}

# 执行 make 命令 (支持 VERBOSE)
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

# 应用补丁
apply_patches() {
    local patch_dir="$1"
    local src_dir="$2"

    if [[ -z "${patch_dir}" || -z "${src_dir}" ]]; then
        echo "用法: apply_patches <patch_dir> <src_dir>" >&2
        return 1
    fi
    
    # Search patch directory
    if [[ ! -d "${patch_dir}" ]]; then
        log "[PATCH] Directory not found: ${patch_dir} (skip)"; return 0
    fi
    shopt -s nullglob
    local patch_files=("${patch_dir}"/*.patch "${patch_dir}"/*.diff)
    if (( ${#patch_files[@]} == 0 )); then
        log "[PATCH] No patch files in ${patch_dir}"; return 0
    fi
    log "[PATCH] Found ${#patch_files[@]} patch file(s)"
    pushd "${src_dir}" >/dev/null
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
                if git am --keep-cr < "$p" >>"${ARCEOS_LOG_FILE}" 2>&1; then
                    applied=1; echo > "$stamp"
                else
                    log "[WARN] git am failed; fallback to git apply path"; git am --abort || true
                fi
            fi
        fi
        if [[ $applied -eq 0 ]]; then
            if git apply --check "$p" >/dev/null 2>&1; then
                if git apply "$p" >>"${ARCEOS_LOG_FILE}" 2>&1; then
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
                    if patch -p${plevel} < "$p" >>"${ARCEOS_LOG_FILE}" 2>&1; then
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

# 构建 Linux 系统
build_linux() {
    local arch="$1"
    shift
    local commands=("$@")
    
    case "${arch}" in
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
        x86|x86_64)
            local linux_arch="x86"
            local cross_compile="${X86_CROSS_COMPILE:-}"
            local defconfig="x86_64_defconfig"
            local kimg_subpath="arch/x86/boot/bzImage"
            arch="x86_64"  # 统一架构名称
            ;;
        *)
            die "不支持的 Linux 架构: ${arch}"
            ;;
    esac
    
    pushd "${LINUX_SRC_DIR}" >/dev/null

    info "清理 Linux: make distclean"
    make distclean || true

    if [[ ${#commands[@]} -eq 0 ]]; then
        info "配置 Linux: make ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${defconfig}"
        run_make ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${defconfig}"
    fi
    
    info "构建 Linux: make -j$(nproc) ARCH=${linux_arch} CROSS_COMPILE=${cross_compile} ${commands[*]:-}"
    run_make -j"$(nproc)" ARCH="${linux_arch}" CROSS_COMPILE="${cross_compile}" "${commands[@]}"
    
    popd >/dev/null

    # 如果是完整构建，复制镜像和创建根文件系统
    if [[ ${#commands[@]} -eq 0 ]] || [[ "${commands[0]}" == "all" ]]; then
        IMAGES_DIR="${LINUX_IMAGES_DIR}/${arch}"
        mkdir -p "${IMAGES_DIR}"
        KIMG_PATH="${LINUX_SRC_DIR}/${kimg_subpath}"
        [[ -f "${KIMG_PATH}" ]] || die "内核镜像未找到: ${KIMG_PATH}"
        info "复制镜像: ${KIMG_PATH} -> ${IMAGES_DIR}/"
        cp -f "${KIMG_PATH}" "${IMAGES_DIR}/"
        success "镜像复制完成"
        
        OUT_DIR=${IMAGES_DIR}
        export OUT_DIR
        build_rootfs "${arch}"
    fi
}

# 创建根文件系统
build_rootfs() {
    if [ ! -f "${SCRIPT_DIR}/mkfs.sh" ]; then
        die "根文件系统脚本不存在: ${SCRIPT_DIR}/mkfs.sh"
    fi
    info "创建根文件系统: ${SCRIPT_DIR}/mkfs.sh -> ${IMAGES_DIR}"
    bash "${SCRIPT_DIR}/mkfs.sh" "${1}"
    success "根文件系统创建完成"
}

# ArceOS 全局变量
declare -g ARCEOS_APP="$DEFAULT_ARCEOS_APP"
declare -g ARCEOS_LOG="$DEFAULT_ARCEOS_LOG"

# 解析 ArceOS 参数
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

# 复制 ArceOS 构建产物
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

# 构建 ArceOS 系统
build_arceos() {
    local arch="$1"
    shift
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
    case "${arch}" in
        aarch64)
            local platform="axplat-aarch64-dyn"
            local app_features="aarch64-dyn"

            ;;
        riscv64)
            local platform="axplat-riscv64-qemu-virt"
            local app_features="riscv64-qemu-virt"
            ;;
        x86|x86_64)
            local platform="axplat-x86-pc"
            local app_features="x86-pc"
            arch="x86_64"  # 统一架构名称
            ;;
        *)
            die "不支持的 ArceOS 架构: ${arch}"
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

    if [ "$arch" == "aarch64" ]; then
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

    if [ "$arch" == "aarch64" ]; then
        copy_arceos_output "$possible_output" "dyn" "$arch"
    else
        copy_arceos_output "$possible_output" "static" "$arch"
    fi
}

build_os() {
    arch="$1"
    system="${2:-all}"
    shift 2 || true

    # 根据系统类型执行构建
    case "$system" in
        linux)
            info "构建 ${arch} Linux 系统"

            clone_repository "$LINUX_REPO_URL" "$LINUX_SRC_DIR"

            build_linux "$arch" "$@"
            ;;
        arceos)
            info "构建 ${arch} ArceOS 系统"

            clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

            apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

            if [ -z "${ARCEOS_SMP:-}" ]; then
                echo "ARCEOS_SMP未定义，将构建多个SMP配置..."
                smp_args=(1 2)
                for smp in "${smp_args[@]}"; do
                    echo "=== 构建 SMP=$smp 配置 ==="
                    ARCEOS_SMP=$smp
                    build_arceos "$arch" "$@"
                    echo ""
                done
                exit 0
            else
                build_arceos "$arch" "$@"
            fi
            ;;
        all)
            info "构建 ${arch} 所有系统 (Linux + ArceOS)"

            clone_repository "$LINUX_REPO_URL" "$LINUX_SRC_DIR"

            build_linux "$arch" "$@"

            clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

            apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

            if [ -z "${ARCEOS_SMP:-}" ]; then
                echo "ARCEOS_SMP未定义，将构建多个SMP配置..."
                smp_args=(1 2)
                for smp in "${smp_args[@]}"; do
                    echo "=== 构建 SMP=$smp 配置 ==="
                    ARCEOS_SMP=$smp
                    build_arceos "$arch" "$@"
                    echo ""
                done
                exit 0
            else
                build_arceos "$arch" "$@"
            fi
            ;;
        *)
            die "未知系统: $system (支持: linux, arceos, all)"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        help|-h|--help|"")
            usage; exit 0 ;;
        aarch64|riscv64|x86|x86_64)
            build_os "$@"
            ;;
        *)
        echo "[ERROR] Unknown cmd: $1" >&2
        usage; exit 2 ;;
    esac
fi