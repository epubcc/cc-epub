#!/data/data/com.termux/files/usr/bin/bash
# cc-epub: 港台繁体EPUB转简体横排工具
# 用法: cc 书名.epub

set -e

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

# 检查参数
if [ $# -eq 0 ]; then
    echo -e "${RED}用法: cc 书名.epub${NC}"
    exit 1
fi

INPUT_FILE="$1"
if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}错误: 找不到文件 '$INPUT_FILE'${NC}"
    exit 1
fi

# 提取书名
BASENAME=$(basename "$INPUT_FILE" .epub)
OUTPUT_DIR="${HOME}/storage/downloads/E-book"
TMP_DIR="${HOME}/.cc_epub_tmp"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"
mkdir -p "$TMP_DIR"

echo -e "${BLUE}[1/8] 正在解压与准备...${NC}"
rm -rf "${TMP_DIR}"/*
unzip -q "$INPUT_FILE" -d "$TMP_DIR"

# 检查是否为有效EPUB
if [ ! -f "${TMP_DIR}/mimetype" ]; then
    echo -e "${RED}错误: 不是有效的EPUB文件${NC}"
    rm -rf "$TMP_DIR"
    exit 1
fi

echo -e "${BLUE}[2/8] 正在清除全角空格...${NC}"
find "$TMP_DIR" -type f \( -name "*.xhtml" -o -name "*.html" -o -name "*.htm" \) | while read -r file; do
    sed -i 's/^\([[:space:]]*\)　\+/\1/g' "$file"
    sed -i 's/>　\+</></g' "$file"
done

echo -e "${BLUE}[3/8] 正在转换竖排标点为横排标点...${NC}"
find "$TMP_DIR" -type f \( -name "*.xhtml" -o -name "*.html" -o -name "*.htm" \) | while read -r file; do
    sed -i \
        -e 's/︑/、/g' \
        -e 's/︒/。/g' \
        -e 's/︓/：/g' \
        -e 's/︔/；/g' \
        -e 's/︕/！/g' \
        -e 's/︖/？/g' \
        -e 's/︗/（/g' \
        -e 's/︘/）/g' \
        -e 's/︙/…/g' \
        -e 's/︹/（/g' \
        -e 's/︺/）/g' \
        -e 's/︻/【/g' \
        -e 's/︼/】/g' \
        -e 's/︽/《/g' \
        -e 's/︾/》/g' \
        -e 's/︿/《/g' \
        -e 's/﹀/》/g' \
        "$file"
done

echo -e "${BLUE}[4/8] 正在检测排版方向...${NC}"
IS_VERTICAL=0
if grep -rq "writing-mode.*vertical" "${TMP_DIR}/OEBPS" 2>/dev/null || \
   grep -rq "writing-mode.*vertical" "${TMP_DIR}/EPUB" 2>/dev/null || \
   find "$TMP_DIR" -name "*.css" -exec grep -l "vertical" {} \; | head -1 | grep -q .; then
    IS_VERTICAL=1
    echo -e "${YELLOW}  检测到竖排排版，将进行转换${NC}"
else
    echo -e "${YELLOW}  检测到横排排版，跳过竖排转换${NC}"
fi

echo -e "${BLUE}[5/8] 正在处理排版方向...${NC}"
# 处理所有CSS文件：竖排转横排 + 统一字体
CSS_DIRS=""
for d in "${TMP_DIR}/OEBPS" "${TMP_DIR}/EPUB" "${TMP_DIR}"; do
    if [ -d "$d" ]; then CSS_DIRS="$CSS_DIRS $d"; fi
done

find $CSS_DIRS -type f -name "*.css" 2>/dev/null | while read -r cssfile; do
    if [ $IS_VERTICAL -eq 1 ]; then
        # 竖排转横排
        sed -i \
            -e 's/writing-mode[^;]*vertical-rl[^;]*/writing-mode: horizontal-tb/gi' \
            -e 's/writing-mode[^;]*vertical-lr[^;]*/writing-mode: horizontal-tb/gi' \
            -e 's/-epub-writing-mode[^;]*vertical-rl[^;]*/-epub-writing-mode: horizontal-tb/gi' \
            -e 's/-epub-writing-mode[^;]*vertical-lr[^;]*/-epub-writing-mode: horizontal-tb/gi' \
            -e 's/text-orientation[^;]*/text-orientation: mixed/gi' \
            -e 's/-webkit-writing-mode[^;]*vertical[^;]*/-webkit-writing-mode: horizontal-tb/gi' \
            "$cssfile"
    fi
    # 统一字体族（Kindle兼容）
    sed -i \
        -e 's/font-family[^;]*;/font-family: serif;/gi' \
        -e 's/font-family[^;]*!/font-family: serif !important;/gi' \
        "$cssfile"
done

# 处理HTML内联样式
find "$TMP_DIR" -type f \( -name "*.xhtml" -o -name "*.html" -o -name "*.htm" \) | while read -r file; do
    if [ $IS_VERTICAL -eq 1 ]; then
        sed -i \
            -e 's/style="[^"]*writing-mode[^"]*vertical-rl[^"]*"/style="writing-mode: horizontal-tb;"/gi' \
            -e 's/style="[^"]*writing-mode[^"]*vertical-lr[^"]*"/style="writing-mode: horizontal-tb;"/gi' \
            "$file"
    fi
    # 统一内联字体
    sed -i \
        -e 's/style="[^"]*font-family[^"]*"/style="font-family: serif;"/gi' \
        "$file"
done

# 移除内嵌字体文件（Kindle兼容性）
find "$TMP_DIR" -type f \( -name "*.ttf" -o -name "*.otf" -o -name "*.woff" -o -name "*.woff2" \) -delete 2>/dev/null || true

# 从OPF文件中移除font-face引用
find "$TMP_DIR" -name "*.opf" | while read -r opffile; do
    sed -i '/<item[^>]*\.ttf[^>]*\/>/Id' "$opffile"
    sed -i '/<item[^>]*\.otf[^>]*\/>/Id' "$opffile"
    sed -i '/<item[^>]*\.woff[^>]*\/>/Id' "$opffile"
done

echo -e "${BLUE}[6/8] 正在执行繁简转换 (OpenCC)...${NC}"
find "$TMP_DIR" -type f \( -name "*.xhtml" -o -name "*.html" -o -name "*.htm" \) | while read -r file; do
    opencc -i "$file" -o "${file}.tmp" -c t2s.json
    mv "${file}.tmp" "$file"
done

# 转换OPF中的元数据
find "$TMP_DIR" -name "*.opf" | while read -r opffile; do
    opencc -i "$opffile" -o "${opffile}.tmp" -c t2s.json
    mv "${opffile}.tmp" "$opffile"
    # 修正语言标签
    sed -i 's/<dc:language>zh-Hant<\/dc:language>/<dc:language>zh-CN<\/dc:language>/gi' "$opffile"
    sed -i 's/<dc:language>zh-TW<\/dc:language>/<dc:language>zh-CN<\/dc:language>/gi' "$opffile"
    sed -i 's/<dc:language>zh-HK<\/dc:language>/<dc:language>zh-CN<\/dc:language>/gi' "$opffile"
done

# 转换目录文件
find "$TMP_DIR" -name "*.ncx" -o -name "toc.xhtml" -o -name "toc.html" | while read -r file; do
    if [ -f "$file" ]; then
        opencc -i "$file" -o "${file}.tmp" -c t2s.json
        mv "${file}.tmp" "$file"
    fi
done

echo -e "${BLUE}[7/8] 正在执行智能排版 (Python)...${NC}"
python3 - "$TMP_DIR" <<'PYTHON_SCRIPT'
import os
import re
import sys
from bs4 import BeautifulSoup, NavigableString

# 排除列表：这些标签内的文本不添加缩进
EXCLUDE_TAGS = {'pre', 'code', 'script', 'style', 'title', 'head', 'meta', 'link'}
# 特殊段落标签：不添加缩进
SPECIAL_CLASSES = ['poem', 'verse', 'quote', 'blockquote', 'citation', 'lyric', 'song']
SPECIAL_TAGS = {'blockquote', 'pre', 'table', 'ul', 'ol', 'dl', 'figure', 'img'}

def should_indent(p_tag):
    """判断段落是否应该添加首行缩进"""
    # 检查标签本身
    if p_tag.name in SPECIAL_TAGS:
        return False

    # 检查class
    classes = p_tag.get('class', [])
    if isinstance(classes, str):
        classes = classes.split()
    for cls in classes:
        cls_lower = cls.lower()
        for sp in SPECIAL_CLASSES:
            if sp in cls_lower:
                return False

    # 检查父元素链
    parent = p_tag.parent
    while parent:
        if parent.name in SPECIAL_TAGS:
            return False
        p_classes = parent.get('class', [])
        if isinstance(p_classes, str):
            p_classes = p_classes.split()
        for cls in p_classes:
            cls_lower = cls.lower()
            for sp in SPECIAL_CLASSES:
                if sp in cls_lower:
                    return False
        parent = parent.parent

    # 检查内容：纯图片段落不缩进
    imgs = p_tag.find_all('img')
    text = p_tag.get_text(strip=True)
    if len(imgs) > 0 and len(text) == 0:
        return False

    # 检查是否为标题
    if p_tag.name in ['h1', 'h2', 'h3', 'h4', 'h5', 'h6']:
        return False

    # 检查class中是否包含title/chapter等
    for cls in classes:
        cls_lower = cls.lower()
        if 'title' in cls_lower or 'chapter' in cls_lower or 'heading' in cls_lower:
            return False

    return True

def process_html_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception:
        return

    # 尝试解析HTML
    try:
        soup = BeautifulSoup(content, 'html.parser')
    except Exception:
        return

    modified = False

    # 处理所有段落标签
    for p in soup.find_all(['p', 'div']):
        # 跳过无文本内容的
        text = p.get_text(strip=True)
        if not text:
            continue

        if should_indent(p):
            style = p.get('style', '')
            # 检查是否已有text-indent
            if 'text-indent' not in style.lower():
                if style:
                    p['style'] = style.rstrip(';') + '; text-indent: 2em;'
                else:
                    p['style'] = 'text-indent: 2em;'
                modified = True

            # 确保有margin
            if 'margin' not in style.lower() and 'margin-' not in style.lower():
                style = p.get('style', '')
                if style:
                    p['style'] = style.rstrip(';') + '; margin: 0.5em 0;'
                else:
                    p['style'] = 'margin: 0.5em 0; text-indent: 2em;'
                modified = True

    if modified:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(str(soup))
        except Exception:
            pass

# 遍历所有HTML文件
tmp_dir = sys.argv[1] if len(sys.argv) > 1 else os.environ.get('TMP_DIR', '')
if tmp_dir and os.path.isdir(tmp_dir):
    for root, dirs, files in os.walk(tmp_dir):
        for fname in files:
            if fname.endswith(('.xhtml', '.html', '.htm')):
                filepath = os.path.join(root, fname)
                process_html_file(filepath)

PYTHON_SCRIPT

echo -e "${BLUE}[8/8] 正在清理与打包...${NC}"
# 确保mimetype是第一个且未压缩
cd "$TMP_DIR"

# 删除旧的输出文件（如果有）
rm -f "${OUTPUT_DIR}/${BASENAME}_简中.epub"

# 打包
zip -X0 "${OUTPUT_DIR}/${BASENAME}_简中.epub" mimetype
find . -type f ! -name "mimetype" | zip -X9r "${OUTPUT_DIR}/${BASENAME}_简中.epub" -@

# 清理临时文件
rm -rf "$TMP_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/${BASENAME}_简中.epub"
FILESIZE=$(du -sh "$OUTPUT_FILE" | cut -f1)

echo -e "${GREEN}✅ 处理完成: ${BASENAME}_简中.epub${NC}"
echo -e "${GREEN}  已保存至: ${OUTPUT_DIR}/${NC}"
echo -e "${GREEN}  文件大小: ${FILESIZE}${NC}"
