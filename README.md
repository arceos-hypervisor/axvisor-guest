
# AxVisor 客户机固件仓库

本仓库用于统一构建和存放 AxVisor 支持的各平台客户机固件镜像，便于测试和分发。

## 支持平台

- **飞腾派**：基于 [Phytium Pi OS](https://gitee.com/phytium_embedded/phytium-pi-os) 构建，详见 [快速开始文档](https://arceos-hypervisor.github.io/axvisorbook/docs/quickstart/phytiumpi)
- **ROC-RK3568-PC**：基于官方 SDK 构建，详见 [快速开始文档](https://arceos-hypervisor.github.io/axvisorbook/docs/quickstart/roc-rk3568-pc)
- **QEMU 虚拟机**：支持多架构（aarch64/riscv64/x86_64），可用于本地测试
- **TAC-E400-PLC**：支持智能 PLC 设备

## 镜像分发服务

可通过 `http_server.py` 在本地的 IMAGES 目录下启动 HTTP 服务，便于通过 wget 等工具下载镜像文件。

启动示例：
```bash
python3 http_server.py
```

## 构建

建议在 Ubuntu 24.04 环境下操作。

1. 安装依赖：
	```bash
	sudo apt install flex bison libelf-dev gcc-aarch64-linux-gnu g++-aarch64-linux-gnu gcc-riscv64-linux-gnu g++-riscv64-linux-gnu bc fakeroot coreutils cpio gzip debootstrap binfmt-support debian-archive-keyring eatmydata file rsync
	```
2. 赋予构建脚本执行权限：
	```bash
	chmod +x ./build.sh
	```
3. 启动构建：
	```bash
	./build.sh <command> [os_type]
	# 查看帮助
	./build.sh help
	```

---

## 构建相关脚本说明

### scripts/mkfs.sh
生成包含 BusyBox 和基础设备节点的最小根文件系统镜像，支持 aarch64/riscv64/x86_64 架构。
示例：
```bash
scripts/mkfs.sh aarch64 --dir <输出目录>
```

### scripts/phytiumpi.sh
自动化构建 Phytium Pi OS 和 ArceOS 镜像，支持 all/linux/arceos 命令。
示例：
```bash
scripts/phytiumpi.sh all
scripts/phytiumpi.sh linux
scripts/phytiumpi.sh arceos
```

### scripts/qemu.sh
自动化构建 QEMU 虚拟机用 Linux/ArceOS 镜像，支持 aarch64/riscv64/x86_64 架构。
示例：
```bash
scripts/qemu.sh aarch64 linux
scripts/qemu.sh x86_64 arceos
scripts/qemu.sh riscv64 all
```

### scripts/roc-rk3568-pc.sh
构建 ROC-RK3568-PC 平台的 Linux/ArceOS 镜像。
示例：
```bash
scripts/roc-rk3568-pc.sh all
scripts/roc-rk3568-pc.sh linux
scripts/roc-rk3568-pc.sh arceos
```

### scripts/tac-e400-plc.sh
构建 TAC-E400-PLC 平台的 Linux/ArceOS 镜像。
示例：
```bash
scripts/tac-e400-plc.sh all
scripts/tac-e400-plc.sh linux
scripts/tac-e400-plc.sh arceos
```

### scripts/release.sh
打包 IMAGES 目录下所有镜像文件，并可自动发布到 GitHub Release。
示例：
```bash
scripts/release.sh pack
scripts/release.sh github --token <GITHUB_TOKEN> --repo <owner/repo> --tag <tag>
```