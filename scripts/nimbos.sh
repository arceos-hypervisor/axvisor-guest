#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
ROOT_DIR=$(cd "${SCRIPT_DIR}/.." && pwd -P)
BUILD_DIR="$(cd "${ROOT_DIR}" && mkdir -p "build" && cd "build" && pwd -P)"

source $SCRIPT_DIR/utils.sh

# Repository URLs
NIMBOS_SRC_DIR="${BUILD_DIR}/nimbos"
IMAGES_BASE_DIR="${ROOT_DIR}/IMAGES/qemu"
AXVM_BIOS_X86_SRC_DIR="${BUILD_DIR}/axvm-bios-x86"
NIMBOS_REPO_URL="https://github.com/arceos-hypervisor/nimbos.git"
AXVM_BIOS_X86_REPO_URL="https://github.com/arceos-hypervisor/axvm-bios-x86.git"

# Display help information
usage() {
    printf 'Build script for NimbOS\n'
    printf '\n'
    printf 'Usage:\n'
    printf '  scripts/nimbos.sh <architecture> [options]\n'
    printf '\n'
    printf 'Architectures:\n'
    printf '  aarch64                           Build for AArch64 architecture\n'
    printf '  x86_64                            Build for x86_64 architecture\n'
    printf '  riscv64                           Build for RISC-V architecture\n'
    printf '  help, -h, --help                  Display this help information\n'
    printf '  clean                             Clean build output artifacts\n'
    printf '\n'
    printf 'Options:\n'
    printf '  Optional, all options will be directly passed to the build system\n'
    printf '\n'
    printf 'Examples:\n'
    printf '  scripts/nimbos.sh aarch64         # Build ARM64 NimbOS\n'
    printf '  scripts/nimbos.sh x86_64 clean    # Clean x86_64 NimbOS build\n'
}

build_nimbos() {
    # Check if clean command
    if [[ "$@" == *"clean"* ]]; then
        pushd "$NIMBOS_SRC_DIR" >/dev/null
        info "Cleaning NimbOS: make -C kernel clean"
        make -C kernel clean ARCH="${ARCH}" || true
        info "Cleaning user: make -C user clean"
        make -C user clean ARCH="${ARCH}" || true
        popd >/dev/null
        
        # Clean BIOS for x86_64
        if [ "${ARCH}" == "x86_64" ] && [ -d "$AXVM_BIOS_X86_SRC_DIR" ]; then
            pushd "$AXVM_BIOS_X86_SRC_DIR" >/dev/null
            info "Cleaning AXVM BIOS: make clean"
            make clean || true
            popd >/dev/null
        fi
        
        NIMBOS_IMAGES_DIR="${IMAGES_BASE_DIR}/${ARCH}/nimbos"
        info "Removing ${NIMBOS_IMAGES_DIR}/*"
        rm -rf ${NIMBOS_IMAGES_DIR}/* || true
        return 0
    fi

    # Verify architecture support
    case "${ARCH}" in
        x86_64|aarch64|riscv64)
            ;;
        *)
            die "Unsupported NimbOS architecture: ${ARCH}"
            ;;
    esac

    # Build axvm-bios-x86 for x86_64 architecture
    if [ "${ARCH}" == "x86_64" ]; then
        info "Building axvm-bios-x86 for x86_64..."
        axvm_bios_x86
    fi

    pushd "$NIMBOS_SRC_DIR" >/dev/null

    # Install musl toolchain
    local musl_prefix=""
    local musl_path=""
    case "${ARCH}" in
        x86_64)
            musl_prefix="x86_64-linux-musl"
            musl_path="x86_64-linux-musl-cross"
            ;;
        aarch64)
            musl_prefix="aarch64-linux-musl"
            musl_path="aarch64-linux-musl-cross"
            ;;
        riscv64)
            musl_prefix="riscv64-linux-musl"
            musl_path="riscv64-linux-musl-cross"
            ;;
    esac

    # Check if musl toolchain is available
    if ! command -v ${musl_prefix}-gcc &> /dev/null; then
        warn "musl toolchain ${musl_prefix}-gcc not found in PATH"
        
        # Try to download and install musl toolchain
        local musl_dir="${BUILD_DIR}/musl-${ARCH}"
        if [ ! -d "$musl_dir" ]; then
            info "Downloading musl toolchain from https://musl.cc/${musl_path}.tgz"
            
            pushd "${BUILD_DIR}" >/dev/null
            if wget -q "https://musl.cc/${musl_path}.tgz"; then
                info "Extracting musl toolchain..."
                tar -xf "${musl_path}.tgz"
                mv "${musl_path}" "musl-${ARCH}"
                rm -f "${musl_path}.tgz"
                success "musl toolchain installed to ${musl_dir}"
            else
                warn "Failed to download musl toolchain, attempting to build without it..."
            fi
            popd >/dev/null
        fi
        
        # Add musl toolchain to PATH if it exists
        if [ -d "$musl_dir/bin" ]; then
            export PATH="$musl_dir/bin:$PATH"
            info "Added musl toolchain to PATH: $musl_dir/bin"
        fi
    else
        info "musl toolchain ${musl_prefix}-gcc found in PATH"
    fi

    # Build user programs
    info "Building user programs: make -C user build ARCH=${ARCH}"
    make -C user build ARCH="${ARCH}" "$@"

    # Build kernel (standard build)
    info "Building kernel: make -C kernel build ARCH=${ARCH}"
    make -C kernel build ARCH="${ARCH}" "$@"

    # Copy the standard build binary
    local binary_path="$NIMBOS_SRC_DIR/kernel/target/${ARCH}/release/nimbos.bin"
    
    if [[ ! -f "$binary_path" ]]; then
        die "NimbOS binary not found: ${binary_path}"
    fi

    NIMBOS_IMAGES_DIR="${IMAGES_BASE_DIR}/${ARCH}/nimbos"
    info "Copying build artifacts -> $NIMBOS_IMAGES_DIR"
    mkdir -p "$NIMBOS_IMAGES_DIR"
    
    info "Found binary: $binary_path"
    cp "$binary_path" "$NIMBOS_IMAGES_DIR/qemu-${ARCH}"

    # Build kernel for usertests
    info "Building kernel for usertests: make -C kernel build ARCH=${ARCH} USER_ENTRY=usertests"
    make -C kernel build ARCH="${ARCH}" USER_ENTRY=usertests "$@"

    # Copy the usertests build binary
    if [[ ! -f "$binary_path" ]]; then
        die "NimbOS usertests binary not found: ${binary_path}"
    fi
    
    info "Found usertests binary: $binary_path"
    cp "$binary_path" "$NIMBOS_IMAGES_DIR/qemu-${ARCH}_usertests"

    popd >/dev/null

    # Create disk image for NimbOS
    info "Creating NimbOS disk image..."
    create_nimbos_disk_image
    
    success "NimbOS build completed successfully"
}

axvm_bios_x86() {
    info "Cloning axvm-bios-x86 source repository $AXVM_BIOS_X86_REPO_URL -> $AXVM_BIOS_X86_SRC_DIR"
    clone_repository "$AXVM_BIOS_X86_REPO_URL" "$AXVM_BIOS_X86_SRC_DIR"

    info "Starting to build axvm-bios-x86..."
    build_axvm_bios_x86 "$@"
}

build_axvm_bios_x86() {
    pushd "$AXVM_BIOS_X86_SRC_DIR" >/dev/null

    info "Building axvm-bios-x86: make"
    make

    popd >/dev/null

    # Copy the built BIOS binary
    local bios_bin="$AXVM_BIOS_X86_SRC_DIR/out/axvm-bios.bin"
    
    if [[ ! -f "$bios_bin" ]]; then
        die "axvm-bios.bin not found: ${bios_bin}"
    fi

    NIMBOS_IMAGES_DIR="${IMAGES_BASE_DIR}/x86_64/nimbos"
    mkdir -p "$NIMBOS_IMAGES_DIR"
    info "Copying axvm-bios.bin -> $NIMBOS_IMAGES_DIR/"
    cp "$bios_bin" "$NIMBOS_IMAGES_DIR/axvm-bios.bin"
    
    success "axvm-bios-x86 build completed successfully"
}

create_nimbos_disk_image() {
    NIMBOS_IMAGES_DIR="${IMAGES_BASE_DIR}/${ARCH}/nimbos"
    local disk_image_path="${NIMBOS_IMAGES_DIR}/rootfs.img"
    local nimbos_binary="${NIMBOS_IMAGES_DIR}/qemu-${ARCH}_usertests"
    local mount_point="${BUILD_DIR}/nimbos_mount_${ARCH}"
    
    # Check if nimbos binary exists
    if [ ! -f "$nimbos_binary" ]; then
        die "NimbOS usertests binary not found: $nimbos_binary"
    fi
    
    info "Creating disk image: $disk_image_path"
    
    # Create a 64MB disk image (adjust size as needed)
    local disk_size_mb=64
    dd if=/dev/zero of="$disk_image_path" bs=1M count=$disk_size_mb status=progress
    
    # Format with ext4 filesystem
    info "Formatting disk image with ext4..."
    mkfs.fat -F 32 "$disk_image_path"
    
    # Mount and copy NimbOS binary
    info "Mounting disk image and copying NimbOS binary..."
    
    sudo rm -rf "$mount_point"
    sudo mkdir -p "$mount_point"
    
    # Mount the disk image
    sudo mount -o loop "$disk_image_path" "$mount_point"
    
    # Copy NimbOS binary
    sudo cp "$nimbos_binary" "$mount_point/nimbos-${ARCH}.bin"
    
    # Copy BIOS for x86_64
    if [ "${ARCH}" == "x86_64" ] && [ -f "$AXVM_BIOS_X86_SRC_DIR/out/axvm-bios.bin" ]; then
        info "Copying AXVM BIOS to disk image..."
        sudo cp "$AXVM_BIOS_X86_SRC_DIR/out/axvm-bios.bin" "$mount_point/axvm-bios.bin"
    fi
    
    # Set proper permissions
    sudo chown -R root:root "$mount_point"
    sudo chmod 755 "$mount_point"
    sudo chmod 644 "$mount_point"/*
    
    # Unmount
    sudo umount "$mount_point"
    
    # Cleanup mount point
    sudo rm -rf "$mount_point"
    
    success "NimbOS disk image created: $disk_image_path (${disk_size_mb}MB)"
}

nimbos() {
    info "Cloning NimbOS source repository $NIMBOS_REPO_URL -> $NIMBOS_SRC_DIR"
    clone_repository "$NIMBOS_REPO_URL" "$NIMBOS_SRC_DIR"

    info "Starting to build NimbOS system..."
    build_nimbos "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift 1 || true
    case "${cmd}" in
        ""|help|-h|--help)
            usage
            exit 0
            ;;
        aarch64|riscv64|x86_64)
            ARCH="$cmd"
            nimbos "$@"
            ;;
        clean)
            for arch in aarch64 riscv64 x86_64; do
                ARCH="$arch"
                nimbos "clean" || { echo "[ERROR] $arch clean failed" >&2; exit 1; }
            done
            ;;
        *)
            die "Unknown command: $cmd" >&2
            ;;
    esac
fi