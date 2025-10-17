# AxVisor Guest Firmware Repository

English | [中文](README_CN.md)

## Introduction

This repository aggregates every Linux and ArceOS guest image supported by the AxVisor hypervisor together with the scripts and patches required to build them. It offers an end-to-end pipeline that spans source cloning, configuration delivery, artifact collection, and publication, covering local builds, remote SDK invocations, and GitHub Release uploads:

- The utilities under `scripts/` compile Linux and ArceOS images for each board, apply bundled patches, and gather the resulting binaries automatically.
- `build.sh` exposes a single entry point for bulk builds and clean-ups across all supported targets.
- `scripts/release.sh` packages finished images and pushes them to GitHub Release in one command.
- `http_server.py` starts a lightweight HTTP file server rooted at the local image directory, making it easy to share artifacts inside the team or serve them to CI jobs. 

## Guest Targets

The table below lists the hardware boards and QEMU virtual machines currently maintained. Match the rows with the script names and output directories to locate the generated images quickly.
Each platform script prepares the cross compiler, replays the built-in patches, downloads upstream sources, and emits both Linux and ArceOS images for testing and release workflows.

| Platform | Target Architecture | Linux Build Method | ArceOS Configuration | Output Directories |
| --- | --- | --- | --- | --- |
| Phytium Pi development board | aarch64 | Clone the official [Phytium Pi OS](https://gitee.com/phytium_embedded/phytium-pi-os) repository and build locally | `axplat-aarch64-dyn` with `driver-dyn,page-alloc-4g,SMP=1` | `IMAGES/phytiumpi/linux`, `IMAGES/phytiumpi/arceos` |
| ROC-RK3588-PC development board | aarch64 | Run the Firefly SDK script on the intranet builder `10.0.0.110` and fetch the artifacts | Same as above | `IMAGES/roc-rk3588-pc/linux`, `IMAGES/roc-rk3588-pc/arceos` |
| EVM3588 development board | aarch64 | Build with the `evm3588_linux_sdk` hosted on the intranet builder `10.0.0.110` | Same as above | `IMAGES/evm3588/linux`, `IMAGES/evm3588/arceos` |
| TAC-E400-PLC industrial controller | aarch64 | Clone the `tac-e400-plc` repository locally and compile the kernel | Same as above | `IMAGES/tac-e400-plc/linux`, `IMAGES/tac-e400-plc/arceos` |
| QEMU virtual machine | aarch64 / riscv64 / x86_64 | Clone mainline Linux, cross-compile it, and use `scripts/mkfs.sh` to build the root file system | `axplat-aarch64-dyn` for aarch64; `axplat-riscv64-qemu-virt` for riscv64; `axplat-x86-pc` for x86_64 | `IMAGES/qemu/linux/<arch>`, `IMAGES/qemu/arceos/<arch>` |
| Orange Pi 5 Plus | aarch64 | Build using the official `orangepi-build` tool | Same as above | `IMAGES/orangepi/linux`, `IMAGES/orangepi/arceos` |
| Black Sesame A1000 domain controller | aarch64 | Clone the `bst-a1000` repository and build locally | Same as above | `IMAGES/bst-a1000/linux`, `IMAGES/bst-a1000/arceos` |

> **Note:** The scripts clone upstream repositories and apply patches on demand. Ensure you have access to the referenced repositories and to the intranet builders required by remote workflows. 

## Build

`build.sh` works hand in hand with `scripts/*.sh`: the former provides the unified command surface while the latter implements platform-specific steps.
Before launching full builds, back up any images you still need so that `clean` does not delete them.


### Prerequisites

Check that the host machine has at least 30 GB of free disk space and can reach the vendor source repositories or intranet SDK services.
Install the required cross toolchains, kernel utilities, and root file system tooling on Ubuntu 24.04 (or a compatible distribution) with:

```bash
sudo apt update
sudo apt install \
  flex bison libelf-dev libssl-dev \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  gcc-riscv64-linux-gnu g++-riscv64-linux-gnu \
  bc fakeroot coreutils cpio gzip rsync file \
  debootstrap binfmt-support debian-archive-keyring eatmydata \
  python3 python3-venv curl git openssh-client libmpc-dev libgmp-dev \
  lz4 chrpath gawk texinfo chrpath diffstat expect cmake
```

When running inside containers or CI, prepare proxies, APT caches, and SSH credentials in advance; failing to do so will break cloning and remote build actions.
Grant execute permission to the top-level scripts so they can be invoked directly:

```bash
chmod +x build.sh scripts/*.sh
```

### `build.sh`

`build.sh` bundles source checkout, patch replay, platform script execution, and artifact collection into a set of subcommands.
It automatically determines whether to build the root file system first or refresh external repositories, preventing repeated work:

```bash
./build.sh help                # List every available command
./build.sh phytiumpi           # Build Phytium Pi Linux + ArceOS
./build.sh roc-rk3568-pc linux # Build only the ROC-RK3588-PC Linux kernel and image
./build.sh qemu-aarch64 all    # Build QEMU aarch64 Linux + ArceOS + root file system
./build.sh all                 # Build every platform in sequence (takes time)
./build.sh clean               # Remove build caches and images for all platforms
```

### Platform Scripts

To debug a single platform, run the corresponding `scripts/<board>.sh` directly for finer control.
Most scripts provide a `help` subcommand that documents the Linux, ArceOS, and rootfs tasks and their parameters, which helps when integrating with CI:

```bash
scripts/phytiumpi.sh all              # Linux + ArceOS
scripts/phytiumpi.sh linux            # Linux only
scripts/phytiumpi.sh clean            # Clean artifacts

scripts/qemu.sh aarch64 linux         # QEMU aarch64 Linux
scripts/qemu.sh riscv64 all           # riscv64 Linux + ArceOS + rootfs
scripts/qemu.sh x86_64 clean          # Clean QEMU x86_64 artifacts

scripts/tac-e400-plc.sh all           # TAC-E400-PLC full build
scripts/evm3588.sh arceos             # ArceOS firmware only
```

> **Remote build workflow:** `evm3588.sh` and `roc-rk3568-pc.sh` log into `10.0.0.110` via SSH, run the vendor-provided SDK scripts, and download the generated artifacts. Use a dedicated read-only account and SSH key for this process and restrict access through a bastion host if necessary.

If you only need a minimal root file system, run `scripts/mkfs.sh` directly to produce `initramfs.cpio.gz` and `rootfs.img` (the QEMU flow calls this script automatically).
The script accepts flags such as `--extra-package` and `--apt-mirror`, allowing you to add BusyBox applets or Debian packages so the rootfs matches the target environment more closely:

```bash
scripts/mkfs.sh aarch64 --dir IMAGES/qemu/linux/aarch64
```

## Images

All build artifacts are written to `IMAGES/<platform>/<os>`, where `<os>` is either `linux` or `arceos`.
The directory names match the script output conventions so that `scripts/release.sh`, `http_server.py`, and external automation can reuse them directly:

| Output Directory | Description | Typical Files / Naming |
| --- | --- | --- |
| `phytiumpi/linux` | Phytium Pi Linux SDK deliverables | `Image`, `fitImage`, `fip-all.bin`, `phytiumpi_firefly.dtb`, etc. |
| `phytiumpi/arceos` | Phytium Pi ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |
| `roc-rk3588-pc/linux` | Images generated by the Firefly SDK | `boot.img`, `MiniLoaderAll.bin`, `parameter.txt`, `rk3568-firefly-roc-pc-se.dtb`, `Image` |
| `roc-rk3588-pc/arceos` | Matching ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |
| `evm3588/linux` | Images generated by the EVM3588 SDK | `boot.img`, `MiniLoaderAll.bin`, `parameter.txt`, `evm3588.dtb`, `Image` |
| `evm3588/arceos` | Matching ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |
| `tac-e400-plc/linux` | PLC Linux kernel and device tree | `Image`, `e2000q-hanwei-board.dtb` |
| `tac-e400-plc/arceos` | Matching ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |
| `qemu/linux/aarch64` | QEMU aarch64 kernel and rootfs | `Image`, `initramfs.cpio.gz`, `rootfs.img` |
| `qemu/linux/riscv64` | QEMU riscv64 kernel and rootfs | `Image`, `initramfs.cpio.gz`, `rootfs.img` |
| `qemu/linux/x86_64` | QEMU x86_64 kernel and rootfs | `bzImage`, `initramfs.cpio.gz`, `rootfs.img` |
| `qemu/arceos/aarch64` | QEMU aarch64 ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |
| `qemu/arceos/riscv64` | QEMU riscv64 ArceOS firmware | `arceos-riscv64-dyn-smp1.bin` |
| `qemu/arceos/x86_64` | QEMU x86_64 ArceOS firmware | `arceos-x86_64-dyn-smp1.bin` |
| `orangepi/linux` | Orange Pi 5 Plus vendor SDK or local builds | `boot.img`, `parameter.txt`, `u-boot.img`, `orangepi5-plus.dtb`, `Image` |
| `orangepi/arceos` | Matching ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |
| `bst-a1000/linux` | Black Sesame A1000 domain controller Linux kernel and device trees | `Image`, `bsta1000b-fada.dtb`, `bsta1000b-fadb.dtb` |
| `bst-a1000/arceos` | Matching ArceOS firmware | `arceos-aarch64-dyn-smp1.bin` |

Download caches, build logs, and intermediate packages live under `build/`, while packaged archives are stored in `release/`; inspect these folders first when troubleshooting failures.

For QEMU images, you can quickly validate them with `run.sh`. The script selects the appropriate QEMU architecture, kernel, and rootfs parameters to boot the VM:

```bash
./run.sh aarch64 ramfs   # Boot QEMU AArch64 with an initramfs
./run.sh riscv64 rootfs  # Boot QEMU RISC-V with an ext4 rootfs
```

### Packaging and Release

After all images are built, use the packaging scripts to produce tarballs and upload them under a chosen tag.
`scripts/release.sh` reads the directories inside `IMAGES/`, generates archives, and can feed them either to GitHub Release or to internal HTTP mirrors.

#### Package Images

The packaging step iterates over every platform directory under `IMAGES/`, creates separate archives for the Linux and ArceOS outputs, and places them in `release/`.
Use `--include` or `--exclude` to skip debug images and keep upload sizes manageable:

```bash
./build.sh release pack
# Or call the lower-level script:
scripts/release.sh pack --in_dir IMAGES --out_dir release
```

#### GitHub Release

Before pushing to GitHub, export `GITHUB_TOKEN` and confirm the repository has permission to publish releases.
The script creates or updates the specified tag and attaches every archive found in `release/`:

```bash
scripts/release.sh github \
    --token <GITHUB_TOKEN> \
    --repo arceos-hypervisor/axvisor-guest \
    --tag v0.0.10 \
    --dir release
```

The repository ships with `.github/workflows/releases.yml`, which runs `build.sh release pack` and `scripts/release.sh github` whenever a tag is pushed or `workflow_dispatch` is triggered via the GitHub UI.

### Local Distribution

`http_server.py` can daemonize a lightweight HTTP server rooted at `IMAGES/`, delivering images over the network.
It relies solely on the Python standard library and also supports logging, health checks, and PID files, making it suitable for developer machines or CI staging nodes.

#### Startup and Management

```bash
# Serve IMAGES on port 8000 by default
python3 http_server.py start

# Override directory and port
python3 http_server.py start --dir IMAGES --port 9000 --bind 127.0.0.1

# Query status / health
python3 http_server.py status --port 9000

# Restart or stop
python3 http_server.py restart --port 9000
python3 http_server.py stop --port 9000
```

On startup the script writes the process ID to `IMAGES/.images_http.pid`; the `status`, `restart`, and `stop` commands read that file to control the service. If the default port is busy, pass `--bind` to move it elsewhere.
Common environment variables and flags:

- `SERVE_DIR`: Override the default root directory (defaults to the repository `IMAGES` folder).
- `--log-file`: Write logs to the specified file (defaults to `IMAGES/.images_http.log`).
- `--timeout`: Health-check timeout in seconds (default: 3).

#### Client Examples

Once the server is up, directory indexing stays enabled so you can browse and download builds directly.
When exposing the service on shared networks, pair it with Nginx basic auth or firewall rules to limit access.

```bash
# Download the QEMU aarch64 kernel image
wget http://127.0.0.1:9000/qemu/linux/aarch64/Image

# Download the Phytium ArceOS firmware
curl -O http://127.0.0.1:9000/phytiumpi/arceos/arceos-aarch64-dyn-smp1.bin
``` 

## Contributing

We welcome new platform scripts, improvements to the existing build flows, and documentation updates. During review we will help align artifact locations and naming conventions where needed.
Before submitting a pull request, read the inline script comments, keep shell style consistent, and include the steps required to reproduce your results.

1. FORK -> PR

2. If you have further requirements around the build, release, or distribution workflow, please open an issue so we can discuss them.