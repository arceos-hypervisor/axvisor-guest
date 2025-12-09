#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Default values
RTTHREAD_REPO_URL="${RTTHREAD_REPO_URL:-https://github.com/RT-Thread/rt-thread.git}"
RTTHREAD_SRC_DIR="${RTTHREAD_SRC_DIR:-${BUILD_DIR}/rtthread}"
RTTHREAD_PATCH_DIR="${RTTHREAD_PATCH_DIR:-${ROOT_DIR}/patches/rtthread}"

# Global variables for parsed arguments
RTTHREAD_PLATFORM=""
RTTHREAD_PLATFORM_DIR=""
RTTHREAD_BIN_DIR="IMAGES/rtthread"
RTTHREAD_BIN_NAME="rtthread"
RTTHREAD_ARGS=""

rtthread_usage() {
    printf 'RT-Thread build script for various platforms\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/rtthread.sh [options] <platform>\n'
    printf '\n'
    printf '<platform>:                     Target platform\n'
    printf '  phytiumpi                     PhytiumPi\n'
    printf '  help, -h, --help              Display this help information\n'
    printf '\n'
    printf '[options]:\n'
    printf '  --repo-url <url>              RT-Thread repository URL (default: https://github.com/RT-Thread/rt-thread.git)\n'
    printf '  --src-dir <dir>               Source directory (default: build/rtthread)\n'
    printf '  --patch-dir <dir>             Patch directory (default: patches/rtthread)\n'
    printf '  --bin-dir <name>              Output binary directory(default: IMAGES/rtthread/rtthread)\n'
    printf '  --bin-name <name>             Output binary name\n'
    printf '  --clean|-c                    clean\n'
    printf '\n'
    printf 'Environment Variables:\n'
    printf '  RTTHREAD_REPO_URL             RT-Thread repository URL\n'
    printf '  RTTHREAD_SRC_DIR              RT-Thread source directory\n'
    printf '  RTTHREAD_PATCH_DIR            RT-Thread patch directory\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/rtthread.sh --bin-name rt.bin phytiumpi\n'
    printf '  scripts/rtthread.sh -c phytiumpi\n'
}

rtthread_parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            help|-h|--help)
                rtthread_usage
                exit 0
                ;;
           phytiumpi)
                RTTHREAD_PLATFORM="$1"
                RTTHREAD_PLATFORM_DIR="$RTTHREAD_SRC_DIR/bsp/phytium/aarch64"
                shift 1
                ;;
            --clean|-c)
                RTTHREAD_ARGS="$RTTHREAD_ARGS -c"
                shift 1
                ;;
            --repo-url)
                RTTHREAD_REPO_URL="$2"
                shift 2
                ;;
            --src-dir)
                RTTHREAD_SRC_DIR="$2"
                shift 2
                ;;
            --patch-dir)
                RTTHREAD_PATCH_DIR="$2"
                shift 2
                ;;
            --bin-dir)
                RTTHREAD_BIN_DIR="$2"
                shift 2
                ;;
            --bin-name)
                RTTHREAD_BIN_NAME="$2"
                shift 2
                ;;
            *)
                RTTHREAD_ARGS="$RTTHREAD_ARGS $1"
                shift
                ;;
        esac
    done
}

rtthread_build() {
    pushd "$RTTHREAD_PLATFORM_DIR" >/dev/null
    info "EXEC: scons -j$(nproc) $RTTHREAD_ARGS"
    export RTT_EXEC_PATH="/opt/arm-gnu-toolchain-11.3.rel1-x86_64-aarch64-none-elf/bin"
    scons -j$(nproc) $RTTHREAD_ARGS
    popd >/dev/null

    if [[ "${RTTHREAD_ARGS}" != *"-c"* ]]; then
        info "Copying build artifacts: $RTTHREAD_PLATFORM_DIR/rtthread_a64.bin -> $RTTHREAD_BIN_DIR/$RTTHREAD_BIN_NAME"
        mkdir -p "${RTTHREAD_BIN_DIR}"
        cp "${RTTHREAD_PLATFORM_DIR}/rtthread_a64.bin" "${RTTHREAD_BIN_DIR}/$RTTHREAD_BIN_NAME"
    else
        info "Cleaning build artifacts in $RTTHREAD_BIN_DIR"
        rm -rf "${RTTHREAD_BIN_DIR}" || true
    fi
}

rtthread() {
    if [[ "${RTTHREAD_ARGS}" != *"-c"* ]]; then
        info "Cloning RT-Thread source repository $RTTHREAD_REPO_URL -> $RTTHREAD_SRC_DIR"
        clone_repository "$RTTHREAD_REPO_URL" "$RTTHREAD_SRC_DIR"

        info "Applying patches..."
        apply_patches "$RTTHREAD_PATCH_DIR" "$RTTHREAD_SRC_DIR"
    fi

    rtthread_build
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        rtthread_usage
        exit 0
    fi

    # Parse arguments using the dedicated function
    rtthread_parse_args "$@"

    if [[ -z "$RTTHREAD_PLATFORM" ]]; then
        printf 'Error: No platform specified.\n\n'
        rtthread_usage
        exit 1
    fi

    # Call the main function
    rtthread
fi
