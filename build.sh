#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

usage() {
    printf '%s\n' "Usage:"
    printf '%s\n' "$0 <platform> [os_type]"
    printf '%s\n' "$0 help | -h | --help"
    printf '%s\n' ""
    printf '%s\n' "Platforms:"
    printf '%s\n' "    phytiumpi            -> scripts/phytiumpi.sh"
    printf '%s\n' "    roc-rk3568-pc        -> scripts/roc-rk3568-pc.sh"
    printf '%s\n' "    tac-e400-plc         -> scripts/tac-e400-plc.sh"
    printf '%s\n' "    qemu-aarch64         -> scripts/qemu.sh aarch64"
    printf '%s\n' "    qemu-x86_64          -> scripts/qemu.sh x86_64"
    printf '%s\n' "    qemu-riscv64         -> scripts/qemu.sh riscv64"
    printf '%s\n' ""
    printf '%s\n' "os_type:                 build all supported OSes, if Not Specified"
    printf '%s\n' "    linux                build linux kernel"
    printf '%s\n' "    arceos               build ArceOS"
    printf '%s\n' ""
    printf '%s\n' "Examples:"
    printf '%s\n' "    $0 phytiumpi"
    printf '%s\n' "    $0 roc-rk3568-pc"
    printf '%s\n' "    $0 qemu-aarch64"
    printf '%s\n' ""
    printf '%s\n' "Environment passthrough: All current env vars are forwarded."
}

# -------------------------------
# Dispatch
# -------------------------------
case "${1:-}" in
    help|-h|--help|"")
        usage; exit 0 ;;
    phytiumpi)
        shift
        script_path="${SCRIPTS_DIR}/phytiumpi.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" "$@" ;;
    roc-rk3568-pc)
        shift
        script_path="${SCRIPTS_DIR}/roc-rk3568-pc.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" "$@" ;;
    tac-e400-plc)
        shift
        script_path="${SCRIPTS_DIR}/tac-e400-plc.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" "$@" ;;
    qemu-aarch64)
        shift
        script_path="${SCRIPTS_DIR}/qemu.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" aarch64 "$@" ;;
    qemu-x86_64)
        shift
        script_path="${SCRIPTS_DIR}/qemu.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" x86_64 "$@" ;;
    qemu-riscv64)
        shift
        script_path="${SCRIPTS_DIR}/qemu.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" riscv64 "$@" ;;
    release)
        shift
        script_path="${SCRIPTS_DIR}/release.sh"
        [[ -f "$script_path" ]] || { echo "[ERROR] Script not found: $script_path" >&2; exit 1; }
        chmod +x "$script_path" 2>/dev/null || true
        exec "$script_path" "$@" ;;
    *)
        echo "[ERROR] Unknown platform: $1" >&2
        usage; exit 2 ;;
esac
