#!/usr/bin/env bash
set -euo pipefail

VERBOSE=${VERBOSE:-0}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
PHYTIUM_REPO_URL=${PHYTIUM_REPO_URL:-"https://gitee.com/phytium_embedded/phytium-pi-os.git"}
BUILD_DIR=$(cd "${WORK_ROOT}" && mkdir -p "${BUILD_DIR:-build}" && cd "${BUILD_DIR:-build}" && pwd -P)
LOG_FILE=${LOG_FILE:-"${BUILD_DIR}/phytiumpi_patch.log"}
PATCH_DIR=${PATCH_DIR:-"${WORK_ROOT}/patchs/phytiumpi"}
TARGET_IMAGES_DIR=${IMAGES_DIR:-"${WORK_ROOT}/IMAGES/phytiumpi/linux"}
SRC_DIR="${BUILD_DIR}/phytium-pi-os"

usage() {
    printf '%s\n' "Phytium Pi OS build helper"
    printf '%s\n' ""
    printf '%s\n' "Usage:"
    printf '%s\n' "  scripts/phytiumpi.sh [command]"
    printf '%s\n' ""
    printf '%s\n' "Commands:"
    printf '%s\n' "  build         Clone (if missing), apply patches, build and copy images (default)"
    printf '%s\n' "  clean         Run 'make clean' inside the source tree"
    printf '%s\n' "  distclean     Run 'make distclean' inside the source tree"
    printf '%s\n' "  rm | remove   Delete the cloned source directory entirely"
    printf '%s\n' "  help, -h, --help  Show this help"
    printf '%s\n' ""
    printf '%s\n' "Patch application logic:"
    printf '%s\n' "  - Detects git format-patch (mbox) vs plain diff automatically"
    printf '%s\n' "  - For format-patch: git am --keep-cr; skips if commit already in history"
    printf '%s\n' "  - For diff: git apply --check then git apply; if already applied (reverse check) it stamps"
    printf '%s\n' "  - Fallback: patch -p1 then -p0"
    printf '%s\n' "  - Each applied/skip creates .patch_stamps/<file>.applied in the source tree"
    printf '%s\n' ""
    printf '%s\n' "Environment variables:"
    printf '%s\n' "  PHYTIUM_REPO_URL   Git repo URL (default: https://gitee.com/phytium_embedded/phytium-pi-os.git)"
    printf '%s\n' "  BUILD_DIR          Build root (default: build) (normalized to absolute)"
    printf '%s\n' "  PATCH_DIR          Patch directory (default: patchs/phytiumpi) (absolute)"
    printf '%s\n' "  IMAGES_DIR         Destination for copied images (default: IMAGES/phytiumpi/linux) (absolute)"
    printf '%s\n' "  VERBOSE=1          Enable extra patch fallback logging"
    printf '%s\n' "  LOG_FILE           Patch/application log file (default: BUILD_DIR/phytiumpi_patch.log)"
    printf '%s\n' ""
    printf '%s\n' "Process (build):"
    printf '%s\n' "  1. clone_repository -> shallow clone if missing"
    printf '%s\n' "  2. apply_patches (idempotent)"
    printf '%s\n' "  3. make phytiumpi_desktop_defconfig"
    printf '%s\n' "  4. make -j\$(nproc)"
    printf '%s\n' "  5. Copy output/images/* to IMAGES_DIR"
    printf '%s\n' ""
    printf '%s\n' "Exit codes:"
    printf '%s\n' "  0 success; 1 failure in build/patch/apply; 2 invalid command"
    printf '%s\n' ""
    printf '%s\n' "Examples:"
    printf '%s\n' "  scripts/phytiumpi.sh"
    printf '%s\n' "  VERBOSE=1 scripts/phytiumpi.sh build"
    printf '%s\n' "  scripts/phytiumpi.sh clean"
    printf '%s\n' "  scripts/phytiumpi.sh rm"
    printf '%s\n' ""
}

log() { 
    printf '%s\n' "$*" >&2; echo "$(date '+%F %T') $*" >>"${LOG_FILE}";
}

vlog() {
    [[ $VERBOSE -eq 1 ]] && log "$@" || true;
}

clone_repository() {
    mkdir -p "${BUILD_DIR}" || true
    if [[ ! -d "${SRC_DIR}" ]]; then
        log "[CLONE] ${PHYTIUM_REPO_URL} -> ${SRC_DIR}"
        git clone --depth=1 "${PHYTIUM_REPO_URL}" "${SRC_DIR}"
    else
        log "[SKIP] Source already exists: ${SRC_DIR}"
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
    pushd "${SRC_DIR}" >/dev/null
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

cmd_clean() {
    if [[ -d "${SRC_DIR}" ]]; then
        pushd "${SRC_DIR}" >/dev/null
        log "[CLEAN] make clean"
        make clean || true
        popd >/dev/null
    else
        log "[CLEAN] Source dir missing: ${SRC_DIR}"
    fi
}

cmd_distclean() {
    if [[ -d "${SRC_DIR}" ]]; then
        pushd "${SRC_DIR}" >/dev/null
        log "[CLEAN] make distclean"
        make distclean || true
        popd >/dev/null
    else
        log "[CLEAN] Source dir missing: ${SRC_DIR}"
    fi
}

cmd_remove() {
    if [[ -d "${SRC_DIR}" ]]; then
        log "[REMOVE] rm -rf ${SRC_DIR}"
        rm -rf "${SRC_DIR}"
    else
        log "[REMOVE] Source dir missing: ${SRC_DIR}"
    fi
}

cmd_build() {
    clone_repository
    apply_patches
    pushd "${SRC_DIR}" >/dev/null
    log "[BUILD] make phytiumpi_desktop_defconfig"
    make phytiumpi_desktop_defconfig
    log "[BUILD] make -j$(nproc)"
    make -j"$(nproc)"
    popd >/dev/null
    IMAGES_SRC_DIR="${SRC_DIR}/output/images"
    if [[ ! -d "${IMAGES_SRC_DIR}" ]]; then
        log "[ERROR] Images directory not found: ${IMAGES_SRC_DIR}"; exit 1
    fi
    mkdir -p "${TARGET_IMAGES_DIR}" || true
    log "[COPY] ${IMAGES_SRC_DIR} -> ${TARGET_IMAGES_DIR}"
    shopt -s dotglob nullglob
    cp -a "${IMAGES_SRC_DIR}"/* "${TARGET_IMAGES_DIR}/"
    log "[DONE] Files copied to ${TARGET_IMAGES_DIR}"
}

cmd=${1:-}
shift || true

case "${cmd}" in
    -h|--help|help)
        usage ;;
    clean)
        cmd_clean ;;
    distclean)
        cmd_distclean ;;
    rm|remove)
        cmd_remove ;;
    build|"")
        cmd_build ;;
    *)
        echo "Unknown command: ${cmd}" >&2
        usage
        exit 2 ;;
esac
