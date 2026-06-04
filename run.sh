#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}" && pwd -P)
IMAGES_DIR="${ROOT_DIR}/IMAGES/qemu"

first_existing() {
    local path
    for path in "$@"; do
        if [[ -f "$path" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done
    return 1
}

usage() {
    printf '%s\n' "run.sh: QEMU boot helper for aarch64, riscv64, x86_64, loongarch64."
    printf '%s\n' ''
    printf '%s\n' "Usage:"
    printf '%s\n' "  $0 <aarch64|riscv64|x86_64|loongarch64> [ramfs|rootfs]"
    printf '%s\n' "  $0 -h|--help|help"
    printf '%s\n' ''
    printf '%s\n' "Commands:"
    printf '%s\n' "  help            Show this help and exit"
    printf '%s\n' "  aarch64 ramfs   Run QEMU for aarch64 with initramfs.cpio.gz (initramfs)"
    printf '%s\n' "  aarch64 rootfs  Run QEMU for aarch64 with rootfs.img (ext4 rootfs)"
    printf '%s\n' "  riscv64 ramfs   Run QEMU for riscv64 with initramfs.cpio.gz (initramfs)"
    printf '%s\n' "  riscv64 rootfs  Run QEMU for riscv64 with rootfs.img (ext4 rootfs)"
    printf '%s\n' "  x86_64 ramfs    Run QEMU for x86_64 with initramfs.cpio.gz (initramfs)"
    printf '%s\n' "  x86_64 rootfs   Run QEMU for x86_64 with rootfs.img (ext4 rootfs)"
    printf '%s\n' "  loongarch64 ramfs   Run QEMU for loongarch64 with initramfs.cpio.gz"
    printf '%s\n' "  loongarch64 rootfs  Run QEMU for loongarch64 with rootfs.img"
    printf '%s\n' ''
    printf '%s\n' "Examples:"
    printf '%s\n' "  $0 aarch64 ramfs   # QEMU aarch64, use initramfs.cpio.gz"
    printf '%s\n' "  $0 aarch64 rootfs  # QEMU aarch64, use rootfs.img"
    printf '%s\n' "  $0 x86_64 rootfs   # QEMU x86_64, use rootfs.img"
}

run_qemu_aarch64() {
    local fs_type="${1:-ramfs}"
    local KERNEL
    KERNEL="$(first_existing "${IMAGES_DIR}/aarch64/linux/qemu-aarch64" "${IMAGES_DIR}/linux/aarch64/Image")" || {
        echo "[ERROR] Missing kernel for aarch64." >&2
        exit 1
    }
    if [[ "$fs_type" == "ramfs" ]]; then
        local INITRAMFS
        INITRAMFS="$(first_existing "${IMAGES_DIR}/aarch64/linux/initramfs.cpio.gz" "${IMAGES_DIR}/linux/aarch64/initramfs.cpio.gz")" || true
        if [[ ! -f "$KERNEL" || ! -f "$INITRAMFS" ]]; then
            echo "[ERROR] Missing kernel or initramfs for aarch64." >&2
            exit 1
        fi
        qemu-system-aarch64 \
            -machine virt \
            -cpu cortex-a53 \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "root=/dev/ram rw console=ttyAMA0 init=/init" \
            -no-reboot
    elif [[ "$fs_type" == "rootfs" ]]; then
        local ROOTFS
        ROOTFS="$(first_existing "${IMAGES_DIR}/aarch64/linux/rootfs.img" "${IMAGES_DIR}/linux/aarch64/rootfs.img")" || true
        if [[ ! -f "$KERNEL" || ! -f "$ROOTFS" ]]; then
            echo "[ERROR] Missing kernel or rootfs for aarch64." >&2
            exit 1
        fi
        qemu-system-aarch64 \
            -machine virt \
            -cpu cortex-a53 \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -append "root=/dev/vda rw console=ttyAMA0 init=/init" \
            -drive file="$ROOTFS",format=raw,if=virtio \
            -no-reboot
    else
        usage
        exit 2
    fi
}

run_qemu_riscv64() {
    local fs_type="${1:-ramfs}"
    local KERNEL
    KERNEL="$(first_existing "${IMAGES_DIR}/riscv64/linux/qemu-riscv64" "${IMAGES_DIR}/linux/riscv64/Image")" || {
        echo "[ERROR] Missing kernel for riscv64." >&2
        exit 1
    }
    if [[ "$fs_type" == "ramfs" ]]; then
        local INITRAMFS
        INITRAMFS="$(first_existing "${IMAGES_DIR}/riscv64/linux/initramfs.cpio.gz" "${IMAGES_DIR}/linux/riscv64/initramfs.cpio.gz")" || true
        if [[ ! -f "$KERNEL" || ! -f "$INITRAMFS" ]]; then
            echo "[ERROR] Missing kernel or initramfs for riscv64." >&2
            exit 1
        fi
        qemu-system-riscv64 \
            -machine virt \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "root=/dev/ram rw console=ttyS0 init=/init" \
            -no-reboot
    elif [[ "$fs_type" == "rootfs" ]]; then
        local ROOTFS
        ROOTFS="$(first_existing "${IMAGES_DIR}/riscv64/linux/rootfs.img" "${IMAGES_DIR}/linux/riscv64/rootfs.img")" || true
        if [[ ! -f "$KERNEL" || ! -f "$ROOTFS" ]]; then
            echo "[ERROR] Missing kernel or rootfs for riscv64." >&2
            exit 1
        fi
        qemu-system-riscv64 \
            -machine virt \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -append "root=/dev/vda rw console=ttyS0 init=/init" \
            -drive file="$ROOTFS",format=raw,if=virtio \
            -no-reboot
    else
        usage
        exit 2
    fi
}

run_qemu_x86_64() {
    local fs_type="${1:-ramfs}"
    local KERNEL
    KERNEL="$(first_existing "${IMAGES_DIR}/x86_64/linux/qemu-x86_64" "${IMAGES_DIR}/linux/x86_64/bzImage")" || {
        echo "[ERROR] Missing kernel for x86_64." >&2
        exit 1
    }
    if [[ "$fs_type" == "ramfs" ]]; then
        local INITRAMFS
        INITRAMFS="$(first_existing "${IMAGES_DIR}/x86_64/linux/initramfs.cpio.gz" "${IMAGES_DIR}/linux/x86_64/initramfs.cpio.gz")" || true
        if [[ ! -f "$KERNEL" || ! -f "$INITRAMFS" ]]; then
            echo "[ERROR] Missing kernel or initramfs for x86_64." >&2
            exit 1
        fi
        qemu-system-x86_64 \
            -machine q35 \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "root=/dev/ram rw console=ttyS0 init=/init" \
            -no-reboot
    elif [[ "$fs_type" == "rootfs" ]]; then
        local ROOTFS
        ROOTFS="$(first_existing "${IMAGES_DIR}/x86_64/linux/rootfs.img" "${IMAGES_DIR}/linux/x86_64/rootfs.img")" || true
        if [[ ! -f "$KERNEL" || ! -f "$ROOTFS" ]]; then
            echo "[ERROR] Missing kernel or rootfs for x86_64." >&2
            exit 1
        fi
        qemu-system-x86_64 \
            -machine q35 \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -append "root=/dev/sda rw console=ttyS0 init=/init" \
            -drive file="$ROOTFS",format=raw,if=ide \
            -no-reboot
    else
        usage
        exit 2
    fi
}

run_qemu_loongarch64() {
    local fs_type="${1:-ramfs}"
    local KERNEL
    KERNEL="$(first_existing "${IMAGES_DIR}/loongarch64/linux/qemu-loongarch64" "${IMAGES_DIR}/linux/loongarch64/vmlinux.elf")" || {
        echo "[ERROR] Missing kernel for loongarch64." >&2
        exit 1
    }
    if [[ "$fs_type" == "ramfs" ]]; then
        local INITRAMFS
        INITRAMFS="$(first_existing "${IMAGES_DIR}/loongarch64/linux/initramfs.cpio.gz" "${IMAGES_DIR}/linux/loongarch64/initramfs.cpio.gz")" || true
        if [[ ! -f "$KERNEL" || ! -f "$INITRAMFS" ]]; then
            echo "[ERROR] Missing kernel or initramfs for loongarch64." >&2
            exit 1
        fi
        qemu-system-loongarch64 \
            -machine virt \
            -cpu la464 \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -initrd "$INITRAMFS" \
            -append "root=/dev/ram rw console=ttyS0 init=/init" \
            -no-reboot
    elif [[ "$fs_type" == "rootfs" ]]; then
        local ROOTFS
        ROOTFS="$(first_existing "${IMAGES_DIR}/loongarch64/linux/rootfs.img" "${IMAGES_DIR}/linux/loongarch64/rootfs.img")" || true
        if [[ ! -f "$KERNEL" || ! -f "$ROOTFS" ]]; then
            echo "[ERROR] Missing kernel or rootfs for loongarch64." >&2
            exit 1
        fi
        qemu-system-loongarch64 \
            -machine virt \
            -cpu la464 \
            -m 1024 \
            -nographic \
            -kernel "$KERNEL" \
            -append "root=/dev/vda rw console=ttyS0 init=/init" \
            -drive file="$ROOTFS",format=raw,if=virtio \
            -no-reboot
    else
        usage
        exit 2
    fi
}

case "${1:-}" in
    ""|-h|--help|help)
        usage
        exit 0
        ;;
    aarch64)
        run_qemu_aarch64 "${2:-ramfs}"
        ;;
    riscv64)
        run_qemu_riscv64 "${2:-ramfs}"
        ;;
    x86_64)
        run_qemu_x86_64 "${2:-ramfs}"
        ;;
    loongarch64)
        run_qemu_loongarch64 "${2:-ramfs}"
        ;;
    *)
        echo "Unknown command: $1" >&2
        usage
        exit 2
        ;;
esac
