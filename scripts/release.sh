#!/usr/bin/env bash

# 将 IMAGES 目录中的文件复制并重命名到 IMAGES/releases 目录
copy_to_releases() {
    local images_dir="IMAGES"
    local releases_dir="$images_dir/releases"
    
    echo "🚀 开始复制文件到 releases 目录..."
    
    # 创建 releases 目录
    if ! mkdir -p "$releases_dir"; then
        echo "❌ 无法创建目录: $releases_dir"
        exit 1
    fi
    
    # 清空 releases 目录（如果有旧文件）
    if [ "$(ls -A "$releases_dir" 2>/dev/null)" ]; then
        echo "🧹 清空已存在的 releases 目录..."
        rm -f "$releases_dir"/*
    fi
    
    echo "📁 创建目录: $releases_dir"
    
    # 查找所有 .bin 文件并复制重命名
    local file_count=0
    find "$images_dir" -name "*.bin" -not -path "$releases_dir/*" | while IFS= read -r file; do
        # 解析路径组件
        # 例如: IMAGES/qemu/arceos/x86/arceos-static-smp4.bin
        relative_path="${file#$images_dir/}"  # 去掉 IMAGES/ 前缀
        
        # 分割路径
        IFS='/' read -ra path_parts <<< "$relative_path"

        case ${#path_parts[@]} in
            4)
                # 4层结构: board/project/arch/file
                board="${path_parts[0]}"     # qemu
                project="${path_parts[1]}"   # arceos  
                arch="${path_parts[2]}"      # x86
                filename="${path_parts[3]}"  # arceos-static-smp4.bin
                ;;
            3)
                # 3层结构: board/project/file (如 phytiumpi 可能没有 arch 层)
                board="${path_parts[0]}"     # phytiumpi
                project="${path_parts[1]}"   # arceos
                arch="noarch"                # 默认值
                filename="${path_parts[2]}"  # arceos-dyn-smp1.bin
                ;;
            *)
                echo "⚠️  跳过未识别的路径结构: $file"
                continue
                ;;
        esac
        
        # 提取文件名的后半部分 (去掉 arceos- 前缀)
        if [[ "$filename" =~ ^arceos-(.+)$ ]]; then
            suffix="${BASH_REMATCH[1]}"    # static-smp4.bin 或 dyn-smp1.bin
            extension="${suffix##*.}"      # bin
            name_part="${suffix%.*}"       # static-smp4 或 dyn-smp1
            
            # 生成新文件名
            if [ "$arch" = "noarch" ]; then
                # 没有架构信息的情况: arceos-phytiumpi-dyn-smp1.bin
                new_name="arceos-${board}-${name_part}.${extension}"
            else
                # 有架构信息的情况: arceos-qemu-x86-static-smp4.bin
                new_name="arceos-${board}-${arch}-${name_part}.${extension}"
            fi
        else
            # 如果不匹配 arceos-* 模式，使用原文件名
            echo "⚠️  文件名格式不匹配，保持原名: $filename"
            new_name="$filename"
        fi
        
        # 复制文件
        if cp "$file" "$releases_dir/$new_name"; then
            echo "✅ $(printf '%-50s' "$file") -> $new_name"
            ((file_count++))
        else
            echo "❌ 复制失败: $file"
        fi
    done
    
    echo ""
    echo "🎉 复制完成！"
    echo "📊 统计信息:"
    echo "   - 源目录: $images_dir"
    echo "   - 目标目录: $releases_dir"
    echo "   - 处理文件数: $(find "$images_dir" -name "*.bin" -not -path "$releases_dir/*" | wc -l)"
    echo ""
    
    echo "📋 releases 目录内容:"
    if [ -d "$releases_dir" ]; then
        ls -la "$releases_dir"
        echo ""
        echo "💾 总大小: $(du -sh "$releases_dir" | cut -f1)"
    fi
}

# 显示预览（不实际复制）
preview_rename() {
    local images_dir="IMAGES"
    
    echo "🔍 重命名预览 (不会实际复制文件):"
    echo ""
    printf "%-60s %s\n" "原文件路径" "新文件名"
    echo "--------------------------------------------------------------------------------------------------------"
    
    find "$images_dir" -name "*.bin" | while IFS= read -r file; do
        relative_path="${file#$images_dir/}"
        IFS='/' read -ra path_parts <<< "$relative_path"
        
        case ${#path_parts[@]} in
            4)
                board="${path_parts[0]}"
                arch="${path_parts[2]}"
                filename="${path_parts[3]}"
                ;;
            3)
                board="${path_parts[0]}"
                arch="noarch"
                filename="${path_parts[2]}"
                ;;
            *)
                echo "$(printf '%-60s' "$file") [跳过-路径格式不支持]"
                continue
                ;;
        esac
        
        if [[ "$filename" =~ ^arceos-(.+)$ ]]; then
            suffix="${BASH_REMATCH[1]}"
            extension="${suffix##*.}"
            name_part="${suffix%.*}"
            
            if [ "$arch" = "noarch" ]; then
                new_name="arceos-${board}-${name_part}.${extension}"
            else
                new_name="arceos-${board}-${arch}-${name_part}.${extension}"
            fi
        else
            new_name="$filename"
        fi
        
        printf "%-60s %s\n" "$file" "$new_name"
    done
}

# 清理 releases 目录
clean_releases() {
    local releases_dir="IMAGES/releases"
    
    if [ -d "$releases_dir" ]; then
        echo "🧹 清理 releases 目录..."
        rm -rf "$releases_dir"
        echo "✅ $releases_dir 已删除"
    else
        echo "ℹ️  $releases_dir 目录不存在"
    fi
}

main() {
    case "${1:-}" in
        "copy" | "")
            copy_to_releases
            ;;
        "preview")
            preview_rename
            ;;
        "clean")
            clean_releases
            ;;
        *)
            echo "用法: $0 {copy|preview|clean}"
            echo ""
            echo "选项:"
            echo "  copy     - 复制文件到 IMAGES/releases 并重命名 (默认)"
            echo "  preview  - 预览重命名效果，不实际复制"
            echo "  clean    - 清理 IMAGES/releases 目录"
            echo ""
            echo "示例:"
            echo "  $0           # 执行复制"
            echo "  $0 copy      # 执行复制"
            echo "  $0 preview   # 预览效果"
            echo "  $0 clean     # 清理目录"
            ;;
    esac
}

# 运行主函数
main "$@"