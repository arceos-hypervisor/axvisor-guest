#!/bin/bash

set -e  # 遇到错误时退出

PWD=$(pwd)
BUILD_DIR="$PWD/build"
SRC_DIR="$PWD/src/arceos"

ARCEOS_DIR="$BUILD_DIR/arceos"
ARCEOS_REPO_URL="https://github.com/arceos-hypervisor/arceos.git"

# 检查arceos目录是否存在
if [ ! -d "$ARCEOS_DIR" ]; then
    echo "📦 ArceOS目录不存在，正在克隆仓库..."
    git clone "$ARCEOS_REPO_URL" "$ARCEOS_DIR"
    echo "✅ 克隆完成！"
else
    echo "📁 ArceOS目录已存在，跳过克隆"
fi

# 执行make命令
echo "🔨 开始构建ArceOS..."
make -C "$ARCEOS_DIR" A=$SRC_DIR LOG=debug LD_SCRIPT=link.x MYPLAT=axplat-aarch64-dyn

if [! -f "$SRC_DIR/arceos_aarch64-dyn.bin" ]; then
    echo "❌ 构建失败，未找到生成的文件"
    exit 1
elif [ -f "$SRC_DIR/arceos_aarch64-dyn.bin" ]; then
    echo "✅ 构建成功，生成的文件位于 $SRC_DIR/arceos_aarch64-dyn.bin"
    cp "$SRC_DIR/arceos_aarch64-dyn.bin" "IMAGES/arceos/arceos_aarch64-dyn.bin"
fi

echo "🎉 构建完成！"