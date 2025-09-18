#!/usr/bin/env bash

set -euo pipefail

# 打包 IMAGES 下所有二级子文件夹为 tar.gz
# 例如 IMAGES/phytiumpi/arceos -> phytiumpi_arceos.tar.gz
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)
IMAGES_DIR="${WORK_ROOT}/IMAGES"
RELEASE_DIR="${WORK_ROOT}/release"
mkdir -p "$RELEASE_DIR"
cd "$IMAGES_DIR"

# 遍历 IMAGES 下所有二级子目录，qemu 为三级，其余为二级，打包到 release 目录
count_packed=0
count_skipped=0
for top in *; do
    [[ -d "$top" ]] || continue
    if [[ "$(basename "$top")" == "qemu" ]]; then
        # qemu: 三级目录
        for mid in "$top"/*; do
            [[ -d "$mid" ]] || continue
            for leaf in "$mid"/*; do
                [[ -d "$leaf" ]] || continue
                rel_path="${leaf#$IMAGES_DIR/}"
                pkg_name="${rel_path//\//_}.tar.gz"
                out_path="$RELEASE_DIR/$pkg_name"
                if find "$leaf" -mindepth 1 | read; then
                    mkdir -p "$RELEASE_DIR"
                    echo "[PACK] $rel_path -> $out_path"
                    tar -czf "$out_path" -C "$leaf" .
                    count_packed=$((count_packed+1))
                else
                    echo "[SKIP] 空目录 $rel_path"
                    count_skipped=$((count_skipped+1))
                fi
            done
        done
    else
        # 其他: 二级目录
        for leaf in "$top"/*; do
            [[ -d "$leaf" ]] || continue
            rel_path="${leaf#$IMAGES_DIR/}"
            pkg_name="${rel_path//\//_}.tar.gz"
            out_path="$RELEASE_DIR/$pkg_name"
            if find "$leaf" -mindepth 1 | read; then
                mkdir -p "$RELEASE_DIR"
                echo "[PACK] $rel_path -> $out_path"
                tar -czf "$out_path" -C "$leaf" .
                count_packed=$((count_packed+1))
            else
                echo "[SKIP] 空目录 $rel_path"
                count_skipped=$((count_skipped+1))
            fi
        done
    fi
done

echo "打包完成：$count_packed 个目录，跳过 $count_skipped 个空目录"
