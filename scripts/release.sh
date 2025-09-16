#!/usr/bin/env bash

# 直接重命名文件到临时目录准备上传
prepare_arceos_direct_release() {
    local images_dir="IMAGES"
    # local temp_dir=$(mktemp -d)
    local temp_dir="$PWD/release_temp"
    mkdir -p "$temp_dir"
    
    echo "🚀 开始准备 release 文件..."
    echo "📁 临时目录: $temp_dir"
    
    # 查找所有 .bin 文件并直接重命名复制到临时目录
    local file_count=0
    find "$images_dir" -name "*.bin" | while IFS= read -r file; do
        # 解析路径组件
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
                echo "Debug: 4层结构 - board: $board, project: $project, arch: $arch, filename: $filename"
                ;;
            3)
                # 3层结构: board/project/file
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
        
        # 复制文件到临时目录
        if cp "$file" "$temp_dir/$new_name"; then
            echo "✅ $(printf '%-50s' "$file") -> $new_name"
            ((file_count++))
        else
            echo "❌ 复制失败: $file"
        fi
    done
    
    echo ""
    echo "🎉 准备完成！"
    echo "📊 统计信息:"
    echo "   - 源目录: $images_dir" 
    echo "   - 临时目录: $temp_dir"
    echo "   - 处理文件数: $(find "$images_dir" -name "*.bin" | wc -l)"
    echo ""
    
    echo "📋 准备上传的文件:"
    if [ -d "$temp_dir" ]; then
        ls -la "$temp_dir"
        echo ""
        echo "💾 总大小: $(du -sh "$temp_dir" | cut -f1)"
    fi
    
    # 输出临时目录路径供 GitHub Actions 使用
    echo "RELEASE_DIR=$temp_dir" >> $GITHUB_OUTPUT
}

main() {
    case "${1:-}" in
        "prepare" | "")
            prepare_arceos_direct_release
            
            ;;
        *)
            echo "用法: $0 {prepare}"
            echo ""
            echo "选项:"
            echo "  prepare  - 准备 release 文件到临时目录 (默认)"
            echo ""
            echo "示例:"
            echo "  $0           # 准备文件"
            echo "  $0 prepare   # 准备文件"
            ;;
    esac
}

# 运行主函数
main "$@"