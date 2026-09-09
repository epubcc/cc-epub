#!/bin/bash
# ============================================================
#  cc — 繁体 EPUB → 简体横排 一键转换命令
#  用法：cc 书名 [--keep-font]
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONVERT_PY="$SCRIPT_DIR/convert.py"
CONFIG_DIR="$SCRIPT_DIR/../config"
OUTPUT_DIR="${CC_EPUB_OUTPUT:-$HOME/storage/downloads/E-book}"

# --- 参数解析 ---
KEEP_FONT="false"
BOOK_NAME=""

for arg in "$@"; do
    case "$arg" in
        --keep-font)
            KEEP_FONT="true"
            ;;
        -h|--help)
            echo "用法：cc 书名 [--keep-font] [--output DIR]"
            echo ""
            echo "选项："
            echo "  --keep-font    保留原 EPUB 内嵌字体（不推荐，Kindle 可能白页）"
            echo "  --output DIR   指定输出目录（默认：~/storage/downloads/E-book）"
            echo "  -h, --help     显示帮助"
            exit 0
            ;;
        --output)
            # next arg is dir
            shift
            OUTPUT_DIR="$1"
            ;;
        *)
            if [ -z "$BOOK_NAME" ]; then
                BOOK_NAME="$arg"
            fi
            ;;
    esac
done

# --- 校验 ---
if [ -z "$BOOK_NAME" ]; then
    echo "❌ 错误：请指定书名"
    echo "用法：cc 书名 [--keep-font]"
    echo "示例：cc 我的第一本书"
    exit 1
fi

# 查找源文件（支持带或不带 .epub 后缀）
SEARCH_DIRS=("$HOME/storage/downloads" "$HOME/downloads" ".")
SOURCE_FILE=""

for dir in "${SEARCH_DIRS[@]}"; do
    # 尝试精确匹配
    if [ -f "$dir/${BOOK_NAME}.epub" ]; then
        SOURCE_FILE="$dir/${BOOK_NAME}.epub"
        break
    fi
    # 尝试模糊匹配（包含书名）
    if [ -d "$dir" ]; then
        MATCH=$(find "$dir" -maxdepth 2 -iname "*${BOOK_NAME}*.epub" 2>/dev/null | head -1)
        if [ -n "$MATCH" ]; then
            SOURCE_FILE="$MATCH"
            break
        fi
    fi
done

if [ -z "$SOURCE_FILE" ]; then
    echo "❌ 未找到文件：*${BOOK_NAME}*.epub"
    echo "   搜索目录：~/storage/downloads, ~/downloads, 当前目录"
    echo "   请将 EPUB 文件放入 Downloads 目录后重试"
    exit 1
fi

echo "📖 源文件：$SOURCE_FILE"
echo "📁 输出目录：$OUTPUT_DIR"
echo ""

# --- 执行转换 ---
mkdir -p "$OUTPUT_DIR"

python "$CONVERT_PY" \
    --input "$SOURCE_FILE" \
    --output "$OUTPUT_DIR" \
    --book-name "$BOOK_NAME" \
    --keep-font "$KEEP_FONT" \
    --config "$CONFIG_DIR"

echo ""
echo "✅ 转换完成！"
echo "📄 输出：$OUTPUT_DIR/${BOOK_NAME}-简中.epub"
echo ""
echo "   接下来可通过 Send to Kindle 网页版推送至设备。"
