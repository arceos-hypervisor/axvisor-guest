#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)

IMAGES_DIR="${WORK_ROOT}/IMAGES"
RELEASE_DIR="${WORK_ROOT}/release"
GITHUB_TOKEN=""
REPO="axvisor-guest"
TAG="v0.0.10"
ASSET_DIR="$RELEASE_DIR"

usage() {
    echo "Usage: $0 pack [options]"
    echo "Commands:"
    echo "  pack                        打包镜像文件"
    echo "  github                      发布 GitHub Release"
    echo "  -h|--help|help              发布 GitHub Release"
    echo ""
    echo "Options for pack:"
    echo "  <input_dir>                 输入目录 (默认: $IMAGES_DIR)"
    echo "  <output_dir>                输出目录 (默认: $RELEASE_DIR)"
    echo ""
    echo "Options for github:"
    echo "  --token <GITHUB_TOKEN>      GitHub access token (required)"
    echo "  --repo <owner/repo>         GitHub repo, e.g. arceos-hypervisor/axvisor-guest (required)"
    echo "  --tag <tag>                 Release tag, e.g. v0.0.10 (required)"
    echo "  --dir <asset_dir>           Directory of release assets (default: ./release)"
}

pack_images() {
    # 打包 IMAGES 下所有二级子文件夹为 tar.gz
    # 例如 IMAGES/phytiumpi/arceos -> phytiumpi_arceos.tar.gz
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
    cd - >/dev/null
}

cmd_pack_images() {
    IMAGES_DIR="${WORK_ROOT}/${1:-"IMAGES"}"
    shift 1 || true
    RELEASE_DIR="${WORK_ROOT}/${1:-"release"}"
    shift 1 || true

    echo "开始打包 $IMAGES_DIR 目录下的系统镜像..."
    pack_images
}

parse_github_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --token)
                GITHUB_TOKEN="$2"; shift 2;;
            --repo)
                REPO="$2"; shift 2;;
            --tag)
                TAG="$2"; shift 2;;
            --dir)
                ASSET_DIR="$2"; shift 2;;
            *)
                echo "Unknown option for github: $1" >&2
                usage; exit 2;;
        esac
    done
}

validate_input() {
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "错误: 需要设置 GITHUB_TOKEN 环境变量"
        exit 1
    fi
    
    if [ -z "$REPO" ]; then
        echo "错误: 需要设置 REPO 环境变量 (格式: owner/repo)"
        exit 1
    fi
    
    if [ -z "$TAG" ]; then
        echo "错误: 需要设置 TAG 环境变量"
        exit 1
    fi
    
    if [ ! -d "$ASSET_DIR" ]; then
        echo "错误: 资源目录不存在: $ASSET_DIR"
        exit 1
    fi
}

github_create_release() {
    local repo="$1"
    local tag="$2"
    local title="${3:-Release $tag}"
    local notes="${4:-Auto-generated release}"
    local draft="${5:-false}"
    local prerelease="${6:-false}"
    
    local api_url="https://api.github.com/repos/$repo/releases"
    
    local response=$(curl -s -w "%{http_code}" -X POST "$api_url" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{
            \"tag_name\": \"$tag\",
            \"name\": \"$title\",
            \"body\": \"$notes\",
            \"draft\": $draft,
            \"prerelease\": $prerelease
        }")
    
    local status_code=${response: -3}
    local response_body=${response:0:${#response}-3}
    
    if [ "$status_code" -eq 201 ]; then
        echo "$response_body" | grep -oP '"upload_url": "\K[^"]*'
    else
        echo "错误: 创建 release 失败 (HTTP $status_code)"
        echo "响应: $response_body"
        return 1
    fi
}

github_upload() {
    local upload_url="$1"
    local file_path="$2"
    
    local file_name=$(basename "$file_path")
    local file_size=$(stat -c%s "$file_path")
    
    # 准备上传 URL
    upload_url="${upload_url%\{*}?name=$file_name"
    
    echo "上传: $file_name ($((file_size/1024/1024))MB)"
    
    local response=$(curl -s -w "%{http_code}" -X POST "$upload_url" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Accept: application/vnd.github.v3+json" \
        --data-binary @"$file_path")
    
    local status_code=${response: -3}
    local response_body=${response:0:${#response}-3}
    
    if [ "$status_code" -eq 201 ]; then
        echo "✓ 上传成功: $file_name"
    else
        echo "❌ 上传失败: $file_name (HTTP $status_code)"
        echo "响应: $response_body"
        return 1
    fi
}

cmd_github() {
    parse_github_args "$@"

    validate_input

    echo "开始发布到 GitHub Release"
    echo "仓库: $REPO"
    echo "版本: $TAG"
    echo "资源目录: $ASSET_DIR"
    echo "----------------------------------------"
    # 创建 release
    echo "创建 release..."
    local upload_url
    local rc
    upload_url=$(github_create_release "$REPO" "$TAG")
    rc=$?
    if [ $rc -ne 0 ] || [ -z "$upload_url" ]; then
        echo "创建 release 失败"
        exit 1
    fi
    echo "Release 创建成功"
    echo "----------------------------------------"
    # 上传文件
    echo "开始上传资源文件..."
    uploaded_count=0
    for file in "$ASSET_DIR"/*; do
        if [ -f "$file" ]; then
            if github_upload "$upload_url" "$file"; then
                ((uploaded_count++))
            fi
        fi
    done

    echo "----------------------------------------"
    echo "✅ 发布完成！"
    echo "上传文件数: $uploaded_count"
    echo "Release URL: https://github.com/$REPO/releases/tag/$TAG"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        pack)
            cmd_pack_images "$@"
            ;;
        github)
            cmd_github "$@"
            ;;
        -h|--help|help|"")
            usage
            exit 0
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            usage
            exit 2
            ;;
    esac
fi
