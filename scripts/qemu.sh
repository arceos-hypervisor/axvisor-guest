#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)

CREATE_RAMFS_SH=${CREATE_RAMFS_SH:-"${SCRIPT_DIR}/create-ramfs.sh"}
LINUX_REPO_URL=${LINUX_REPO_URL:-"https://github.com/torvalds/linux.git"}

usage() {
    printf '%s\n' "QEMU Linux builder"
    printf '%s\n' ""
    printf '%s\n' "Usage:"
    printf '%s\n' "  scripts/qemu.sh <aarch64|x86|x86_64|riscv64> [clean|distclean|help]"
    printf '%s\n' "  scripts/qemu.sh help | -h | --help"
    printf '%s\n' ""
    printf '%s\n' "Environment:"
    printf '%s\n' "  LINUX_REPO_URL       Linux mainline repo (default: https://github.com/torvalds/linux.git)"
    printf '%s\n' "  BUILD_DIR            Build root (default: build/qemu-<arch>-linux)"
    printf '%s\n' "  IMAGES_DIR           Output images dir (default: IMAGES/qemu/linux)"
    printf '%s\n' "  AARCH64_CROSS_COMPILE  (default: aarch64-linux-gnu-)"
    printf '%s\n' "  RISCV64_CROSS_COMPILE   (default: riscv64-linux-gnu-)"
    printf '%s\n' "  X86_CROSS_COMPILE       (default: empty/native)"
}

clone_repository() {
    if [[ -d "${SRC_DIR}/.git" ]]; then
        echo "[SKIP] linux repo exists: ${SRC_DIR}" >&2
    else
        echo "[CLONE] ${LINUX_REPO_URL} -> ${SRC_DIR}" >&2
        git clone --depth=1 "${LINUX_REPO_URL}" "${SRC_DIR}"
    fi
}

do_copy() {
    [[ -f "${KIMG_PATH}" ]] || { echo "[ERROR] Kernel image not found: ${KIMG_PATH}" >&2; exit 1; }
    echo "[COPY] ${KIMG_PATH} -> ${IMAGES_DIR}/" >&2
    cp -f "${KIMG_PATH}" "${IMAGES_DIR}/"
}

do_rootfs() {
    if [ ! -f "${CREATE_RAMFS_SH}" ]; then
        echo "[ERROR] ramfs script not exist: ${CREATE_RAMFS_SH}" >&2
        exit 1
    fi
    echo "[RAMFS] ${CREATE_RAMFS_SH} -> "${IMAGES_DIR}"" >&2
    . "${CREATE_RAMFS_SH}" "${IMAGES_DIR}"
}

cmd=${1:-}
shift || true

case "${cmd}" in
    help|-h|--help)
        usage
        exit 0
        ;;
    aarch64)
        SRC_DIR=${BUILD_DIR:-"${WORK_ROOT}/build/qemu-aarch64-linux"}
        mkdir -p "${SRC_DIR}"
        clone_repository

        pushd "${SRC_DIR}" >/dev/null
        if [ $# -eq 0 ]; then
            echo "[CONF] make ARCH=arm64 CROSS_COMPILE="${AARCH64_CROSS_COMPILE:-"aarch64-linux-gnu-"}" defconfig" >&2
            make ARCH=arm64 CROSS_COMPILE="${AARCH64_CROSS_COMPILE:-"aarch64-linux-gnu-"}" defconfig
        fi
        echo "[MAKE] make -j$(nproc) ARCH=arm64 CROSS_COMPILE="${AARCH64_CROSS_COMPILE:-"aarch64-linux-gnu-"}" $@" >&2
        make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE="${AARCH64_CROSS_COMPILE:-"aarch64-linux-gnu-"}" "$@"
        popd >/dev/null

        if [ $# -eq 0 ] || [[ "$1" == all ]]; then
            IMAGES_DIR=${IMAGES_DIR:-"${WORK_ROOT}/IMAGES/qemu/linux/aarch64"}
            mkdir -p "${IMAGES_DIR}"
            KIMG_PATH="${SRC_DIR}/arch/arm64/boot/Image"
            do_copy
            OUT_DIR=${IMAGES_DIR}
            export OUT_DIR
            do_rootfs
        fi
        ;;
    riscv64)
        SRC_DIR=${BUILD_DIR:-"${WORK_ROOT}/build/qemu-riscv64-linux"}
        mkdir -p "${SRC_DIR}"
        clone_repository

        pushd "${SRC_DIR}" >/dev/null
        if [ $# -eq 0 ]; then
            echo "[CONF] make ARCH=riscv CROSS_COMPILE="${RISCV64_CROSS_COMPILE:-"riscv64-linux-gnu-"}" defconfig" >&2
            make ARCH=riscv CROSS_COMPILE="${RISCV64_CROSS_COMPILE:-"riscv64-linux-gnu-"}" defconfig
        fi
        echo "[MAKE] make -j$(nproc) ARCH=riscv CROSS_COMPILE="${RISCV64_CROSS_COMPILE:-"riscv64-linux-gnu-"}" $@" >&2
        make -j"$(nproc)" ARCH=riscv CROSS_COMPILE="${RISCV64_CROSS_COMPILE:-"riscv64-linux-gnu-"}" "$@"
        popd >/dev/null

        if [ $# -eq 0 ] || [[ "$1" == all ]]; then
            IMAGES_DIR=${IMAGES_DIR:-"${WORK_ROOT}/IMAGES/qemu/linux/riscv64"}
            mkdir -p "${IMAGES_DIR}"
            KIMG_PATH="${SRC_DIR}/arch/riscv/boot/Image"
            do_copy
            OUT_DIR=${IMAGES_DIR}
            export OUT_DIR
            do_rootfs
        fi
        ;;
    x86|x86_64)
        SRC_DIR=${BUILD_DIR:-"${WORK_ROOT}/build/qemu-x86_64-linux"}
        mkdir -p "${SRC_DIR}"
        clone_repository

        pushd "${SRC_DIR}" >/dev/null
        if [ $# -eq 0 ]; then
            echo "[CONF] make ARCH=x86 CROSS_COMPILE="${X86_CROSS_COMPILE:-""}" x86_64_defconfig" >&2
            make ARCH=x86 CROSS_COMPILE="${X86_CROSS_COMPILE:-""}" x86_64_defconfig
        fi
        echo "[MAKE] make -j$(nproc) ARCH=x86 CROSS_COMPILE="${X86_CROSS_COMPILE:-""}" $@" >&2
        make -j"$(nproc)" ARCH=x86 CROSS_COMPILE="${X86_CROSS_COMPILE:-""}" "$@"
        popd >/dev/null

        if [ $# -eq 0 ] || [[ "$1" == all ]]; then
            IMAGES_DIR=${IMAGES_DIR:-"${WORK_ROOT}/IMAGES/qemu/linux/x86_64"}
            mkdir -p "${IMAGES_DIR}"
            KIMG_PATH="${SRC_DIR}/arch/x86/boot/bzImage"
            do_copy
            OUT_DIR=${IMAGES_DIR}
            export OUT_DIR
            do_rootfs
        fi
        ;;
    *)
        echo "Unknown command: ${cmd}" >&2
        usage
        exit 2
        ;;
esac
