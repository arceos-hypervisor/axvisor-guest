#!/usr/bin/env bash
set -euo pipefail

# Unified build entry script
# Supported platform argument (first positional parameter):
#   phytiumpi
#   roc-rk3568-pc
#   arceos
#   qemu-aarch64
#   qemu-x86_64
#   qemu-riscv64
#
# Remaining arguments are forwarded to the platform script.
# Expected scripts (create as needed):
#   scripts/phytiumpi.sh
#   scripts/roc-rk3568-pc.sh
#   scripts/arceos.sh
#   scripts/qemu.sh architecture
#
# Exit codes:
#   0 success
#   1 platform script missing or execution failure
#   2 usage / unknown platform

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

usage() {
    printf '%s\n' "Usage:"
    printf '%s\n' "$0 <platform> [subcommand/args...]"
    printf '%s\n' "$0 help | -h | --help"
    printf '%s\n' "$0 <platform> help       (show platform-specific help)"
    printf '%s\n' ""
    printf '%s\n' "Platforms:"
    printf '%s\n' "    phytiumpi            -> scripts/phytiumpi.sh"
    printf '%s\n' "    roc-rk3568-pc        -> scripts/roc-rk3568-pc.sh"
    printf '%s\n' "    arceos               -> scripts/arceos.sh"
    printf '%s\n' "    qemu-aarch64         -> scripts/qemu.sh aarch64"
    printf '%s\n' "    qemu-x86_64          -> scripts/qemu.sh xx86_64"
    printf '%s\n' "    qemu-riscv64         -> scripts/qemu.sh riscv64"
    printf '%s\n' ""
    printf '%s\n' "Examples:"
    printf '%s\n' "    $0 phytiumpi build"
    printf '%s\n' "    $0 phytiumpi clean"
    printf '%s\n' "    $0 roc-rk3568-pc"
    printf '%s\n' "    $0 qemu-aarch64"
    printf '%s\n' "    $0 arceos --help     (forwarded to platform script)"
    printf '%s\n' "    $0 help              (show this dispatcher help)"
    printf '%s\n' "    $0 phytiumpi help    (invoke 'phytiumpi.sh help')"
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
    arceos)
        shift
        script_path="${SCRIPTS_DIR}/arceos.sh"
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
    *)
        echo "[ERROR] Unknown platform: $1" >&2
        usage; exit 2 ;;
esac
