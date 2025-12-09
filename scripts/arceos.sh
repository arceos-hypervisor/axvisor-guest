#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Default values
ARCEOS_REPO_URL="${ARCEOS_REPO_URL:-https://github.com/arceos-hypervisor/arceos.git}"
ARCEOS_SRC_DIR="${ARCEOS_SRC_DIR:-${BUILD_DIR}/arceos}"
ARCEOS_PATCH_DIR="${ARCEOS_PATCH_DIR:-${ROOT_DIR}/patches/arceos}"

# Platform-specific configurations
declare -A PLATFORM_CONFIGS
PLATFORM_CONFIGS[aarch64-dyn]="ld_script:link.x features:driver-dyn,page-alloc-4g,paging smp:1 log_level:info app_features:aarch64-dyn"
PLATFORM_CONFIGS[riscv64-qemu-virt]="ld_script: features:driver-dyn,page-alloc-4g,paging smp:1 log_level:info app_features:riscv64-qemu-virt"
PLATFORM_CONFIGS[x86-pc]="ld_script: features:driver-dyn,page-alloc-4g,paging smp:1 log_level:info app_features:x86-pc"

# Function to get platform-specific config value
get_platform_config() {
    local platform="$1"
    local config_key="$2"
    local config_str="${PLATFORM_CONFIGS[$platform]}"
    
    if [[ -z "$config_str" ]]; then
        die "Unsupported platform: $platform"
    fi
    
    # Parse the configuration string and return the requested value
    for item in $config_str; do
        local key="${item%%:*}"
        local value="${item#*:}"
        if [[ "$key" == "$config_key" ]]; then
            echo "$value"
            return 0
        fi
    done
    
    return 1
}

# Display help information
usage() {
    printf 'ArceOS build script for various platforms\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/arceos.sh <platform> <output_dir> [output_name] [options]\n'
    printf '\n'
    printf 'Platforms:\n'
    printf '  aarch64-dyn                      Build for aarch64-dyn platform\n'
    printf '  riscv64-qemu-virt               Build for riscv64-qemu-virt platform\n'
    printf '  x86-pc                          Build for x86-pc platform\n'
    printf '\n'
    printf 'Parameters:\n'
    printf '  platform                        Target platform (required)\n'
    printf '  output_dir                      Output directory for build artifacts (required)\n'
    printf '  output_name                     Output file name (optional, defaults to platform name)\n'
    printf '\n'
    printf 'Options:\n'
    printf '  --repo-url <url>                ArceOS repository URL (default: https://github.com/arceos-hypervisor/arceos.git)\n'
    printf '  --src-dir <dir>                 Source directory (default: build/arceos)\n'
    printf '  --patch-dir <dir>               Patch directory (default: patches/arceos)\n'
    printf '  --make-args <args>              Additional make arguments\n'
    printf '  clean                           Clean build artifacts\n'
    printf '  help, -h, --help                Display this help information\n'
    printf '\n'
    printf 'Environment Variables:\n'
    printf '  ARCEOS_REPO_URL                 ArceOS repository URL\n'
    printf '  ARCEOS_SRC_DIR                  ArceOS source directory\n'
    printf '  ARCEOS_PATCH_DIR                ArceOS patch directory\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/arceos.sh aarch64-dyn IMAGES/bst-a1000/arceos bst-a1000\n'
    printf '  scripts/arceos.sh riscv64-qemu-virt IMAGES/qemu/riscv64/arceos qemu-riscv64\n'
    printf '  scripts/arceos.sh x86-pc IMAGES/qemu/x86_64/arceos qemu-x86_64\n'
    printf '  scripts/arceos.sh aarch64-dyn /tmp/output clean\n'
}

build_arceos() {
    local platform="$1"
    local output_dir="$2"
    local output_name="${3:-$platform}"
    local make_args="${4:-}"
    
    # Get platform-specific configuration
    local ld_script=$(get_platform_config "$platform" "ld_script")
    local features=$(get_platform_config "$platform" "features")
    local smp=$(get_platform_config "$platform" "smp")
    local log_level=$(get_platform_config "$platform" "log_level")
    local app_features=$(get_platform_config "$platform" "app_features")
    
    pushd "$ARCEOS_SRC_DIR" >/dev/null
    info "Cleaning old build files: make clean"
    make clean || true

    # Special case for aarch64-dyn platform (needs LD_SCRIPT parameter)
    if [[ "$platform" == "aarch64-dyn" ]]; then
        local make_cmd="A=examples/helloworld-myplat LOG=$log_level MYPLAT=axplat-$platform APP_FEATURES=$app_features LD_SCRIPT=$ld_script FEATURES=$features SMP=$smp $make_args"
    else
        local make_cmd="A=examples/helloworld-myplat LOG=$log_level MYPLAT=axplat-$platform APP_FEATURES=$app_features FEATURES=$features SMP=$smp $make_args"
    fi
    
    info "Starting compilation: make $make_cmd"
    make $make_cmd
    popd >/dev/null

    if [[ "${make_cmd}" != *"clean"* ]]; then
        info "Copying build artifacts -> $output_dir"
        mkdir -p "$output_dir"
        cp "$ARCEOS_SRC_DIR/examples/helloworld-myplat/helloworld-myplat_$app_features.bin" "$output_dir/$output_name"
    else
        rm -rf "$output_dir/$output_name" || true
    fi
}

arceos() {
    local platform="$1"
    local output_dir="$2"
    local output_name="${3:-$platform}"
    local make_args="${4:-}"
    
    info "Cloning ArceOS source repository $ARCEOS_REPO_URL -> $ARCEOS_SRC_DIR"
    clone_repository "$ARCEOS_REPO_URL" "$ARCEOS_SRC_DIR"

    info "Applying patches..."
    apply_patches "$ARCEOS_PATCH_DIR" "$ARCEOS_SRC_DIR"

    info "Starting to build the ArceOS system..."
    build_arceos "$platform" "$output_dir" "$output_name" "$make_args"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Default values
    platform=""
    output_dir=""
    output_name=""
    make_args=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            aarch64-dyn|riscv64-qemu-virt|x86-pc)
                platform="$1"
                shift
                ;;
            --repo-url)
                ARCEOS_REPO_URL="$2"
                shift 2
                ;;
            --src-dir)
                ARCEOS_SRC_DIR="$2"
                shift 2
                ;;
            --patch-dir)
                ARCEOS_PATCH_DIR="$2"
                shift 2
                ;;
            --make-args)
                make_args="$2"
                shift 2
                ;;
            clean)
                make_args="clean $make_args"
                shift
                ;;
            help|-h|--help)
                usage
                exit 0
                ;;
            *)
                if [[ -z "$platform" ]]; then
                    platform="$1"
                elif [[ -z "$output_dir" ]]; then
                    output_dir="$1"
                elif [[ -z "$output_name" ]]; then
                    output_name="$1"
                else
                    make_args="$1 $make_args"
                fi
                shift
                ;;
        esac
    done
    
    # Check required arguments
    if [[ -z "$platform" ]]; then
        die "Platform is required. Use 'help' for usage information."
    fi
    
    if [[ -z "$output_dir" ]]; then
        die "Output directory is required. Use 'help' for usage information."
    fi
    
    # Set default output name if not specified
    if [[ -z "$output_name" ]]; then
        output_name="$platform"
    fi
    
    # Call the main function
    arceos "$platform" "$output_dir" "$output_name" "$make_args"
fi