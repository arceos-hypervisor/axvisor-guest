#!/usr/bin/env bash

set -u

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
WORK_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd -P)

IMAGES_DIR="${WORK_ROOT}/IMAGES"
RELEASE_DIR="${WORK_ROOT}/release"
GITHUB_TOKEN=""
REPO="arceos-hypervisor/axvisor-guest"
TAG="v0.0.10"
ASSET_DIR="$RELEASE_DIR"

usage() {
    echo "Usage: $0 pack [options]"
    echo ""
    echo "Commands:"
    echo "  pack                        Package the image file"
    echo "  github                      Publish GitHub Release"
    echo "  -h|--help|help              Display this help information"
    echo ""
    echo "Options for pack:"
    echo "  <input_dir>                 Directory where the image file is located (default: $IMAGES_DIR)"
    echo "  <output_dir>                The storage directory for the packaged image (default: $RELEASE_DIR)"
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

pack_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --in_dir|--input_dir|-i)
                IMAGES_DIR="$2"; shift 2;;
            --out_dir|--output_dir|-o)
                RELEASE_DIR="$2"; shift 2;;
            *)
                echo "Unknown option for github: $1" >&2
                usage; exit 2;;
        esac
    done
}

pack() {
    pack_parse_args "$@"

    if [ ! -d "$IMAGES_DIR" ]; then
        echo "错误: 输入目录不存在: $IMAGES_DIR"
        exit 1
    fi

    echo "开始打包 $IMAGES_DIR 目录下的系统镜像..."
    pack_images
}

github_parse_args() {
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

github_create_release() {
    repo="$1"
    tag="$2"
    response=$(curl -s -w "%{http_code}" -X POST "https://api.github.com/repos/$repo/releases" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "{\"tag_name\": \"$tag\", \"name\": \"Release $tag\", \"body\": \"Auto-generated release\", \"draft\": false, \"prerelease\": false}")
    status_code=${response: -3}
    response_body=${response:0:${#response}-3}
    if [ "$status_code" -eq 201 ]; then
        echo "$response_body" | grep -oP '"upload_url":\s*"\K[^"{]+'
        return 0
    else
        echo "错误: 创建 release 失败 (HTTP $status_code)" >&2
        echo "$response_body" >&2
        return 1
    fi
}

github_upload() {
    base_url="$1"
    file_name=$(basename "$2")
    local upload_url="${base_url%%\{*}?name=$file_name"
    response=$(curl -s -w "%{http_code}" -X POST "$upload_url" \
        -H "Authorization: token $GITHUB_TOKEN" \
        -H "Content-Type: application/octet-stream" \
        -H "Accept: application/vnd.github.v3+json" \
        --data-binary @"$2")
    status_code=${response: -3}
    response_body=${response:0:${#response}-3}
    if [ "$status_code" -eq 201 ]; then
        echo "上传成功: $upload_url"
        return 0
    else
        echo "上传失败: $upload_url (HTTP $status_code)" >&2
        echo "$response_body" >&2
        return 1
    fi
}

github() {
    github_parse_args "$@"

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

    echo "GitHub Release"
    echo "仓库: $REPO"
    echo "版本: $TAG"
    echo "资源目录: $ASSET_DIR"
    echo "资源文件数: $(find "$ASSET_DIR" -maxdepth 1 -type f | wc -l)"
    echo "----------------------------------------"
    echo "创建 Release..."
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
    shopt -s nullglob dotglob
    files=("$ASSET_DIR"/*)
    if [ ${#files[@]} -eq 0 ]; then
        echo "警告: 资源目录为空，无文件可上传。"
    else
        for file in "${files[@]}"; do
            if [ -f "$file" ]; then
                github_upload "$upload_url" "$file"
                if [ $? -eq 0 ]; then
                    ((uploaded_count++))
                fi
            fi
        done
    fi
    shopt -u nullglob dotglob

    echo "----------------------------------------"
    echo "完成上传文件数: $uploaded_count"
    echo "Release URL: https://github.com/$REPO/releases/tag/$TAG"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd="${1:-}"
    shift || true
    case "$cmd" in
        ""|-h|--help|help)
            usage
            exit 0
            ;;
        pack)
            pack "$@"
            ;;
        github)
            github "$@"
            ;;
        *)
            echo "Unknown command: $cmd" >&2
            usage
            exit 2
            ;;
    esac
fi
