#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

usage() {
    printf '%s\n' "Usage:"
    printf '%s\n' "$0 <command> [os_type]"
    printf '%s\n' "$0 help | -h | --help"
    printf '%s\n' ""
    printf '%s\n' "Commands:"
    printf '%s\n' "    phytiumpi            -> scripts/phytiumpi.sh"
    printf '%s\n' "    roc-rk3568-pc        -> scripts/roc-rk3568-pc.sh"
    printf '%s\n' "    evm3588              -> scripts/evm3588.sh"
    printf '%s\n' "    tac-e400-plc         -> scripts/tac-e400-plc.sh"
    printf '%s\n' "    qemu-aarch64         -> scripts/qemu.sh aarch64"
    printf '%s\n' "    qemu-x86_64          -> scripts/qemu.sh x86_64"
    printf '%s\n' "    qemu-riscv64         -> scripts/qemu.sh riscv64"
    printf '%s\n' "    release              -> scripts/release.sh"
    printf '%s\n' "    all                  -> build all platforms sequentially"
    printf '%s\n' ""
    printf '%s\n' "os_type:                 build all supported OSes, if Not Specified"
    printf '%s\n' "    linux                build linux kernel"
    printf '%s\n' "    arceos               build ArceOS"
    printf '%s\n' ""
    printf '%s\n' "Examples:"
    printf '%s\n' "    $0 phytiumpi"
    printf '%s\n' "    $0 roc-rk3568-pc"
    printf '%s\n' "    $0 qemu-aarch64"
    printf '%s\n' "    $0 all"
    printf '%s\n' ""
    printf '%s\n' "Environment passthrough: All current env vars are forwarded."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "${cmd}" in
        help|-h|--help|"")
            usage
            exit 0
            ;;
        phytiumpi)
            script_path="${SCRIPTS_DIR}/phytiumpi.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        roc-rk3568-pc)
            script_path="${SCRIPTS_DIR}/roc-rk3568-pc.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        evm3588)
            script_path="${SCRIPTS_DIR}/evm3588.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        tac-e400-plc)
            script_path="${SCRIPTS_DIR}/tac-e400-plc.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        qemu-aarch64)
            script_path="${SCRIPTS_DIR}/qemu.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "aarch64" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        qemu-x86_64)
            script_path="${SCRIPTS_DIR}/qemu.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            exec "$script_path" x86_64 "$@"
            if [ $# -eq 0 ]; then
                exec "$script_path" "x86_64" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        qemu-riscv64)
            script_path="${SCRIPTS_DIR}/qemu.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "riscv64" "all"
            else
                exec "$script_path" "$@"
            fi
            ;;
        release)
            script_path="${SCRIPTS_DIR}/release.sh"
            [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
            chmod +x "$script_path" 2>/dev/null || true
            if [ $# -eq 0 ]; then
                exec "$script_path" "pack"
            else
                exec "$script_path" "$@"
            fi
            ;;
        all)
            platforms=(phytiumpi roc-rk3568-pc evm3588 tac-e400-plc qemu-aarch64 qemu-x86_64 qemu-riscv64)
            for p in "${platforms[@]}"; do
                echo "[ALL] Building: $p $*"
                "$0" "$p" "$@" || { echo "[ERROR] $p build failed" >&2; exit 1; }
            done
            ;;
        *)
            echo "[ERROR] Unknown platform: $cmd" >&2
            usage
            exit 2
            ;;
    esac
fi
