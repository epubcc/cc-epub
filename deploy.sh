#!/bin/bash
# deploy.sh - 一键部署 EPUB 繁简通 Pro (Termux 版)
# 用法: bash deploy.sh
# 作者: 基于开源工具构建
# 许可: Apache 2.0

set -e

echo "🚀 正在部署 EPUB 繁简通 Pro 环境..."

# 1. 检查依赖
echo "🔍 正在检查依赖..."
for cmd in unzip zip opencc python3; do
    if ! command -v $cmd &> /dev/null; then
        echo "❌ 错误: 缺少依赖 '$cmd'。正在尝试自动安装..."
        pkg update -y && pkg install unzip zip opencc python3 -y
    fi
done

# 检查 Python 库
pip show beautifulsoup4 lxml > /dev/null 2>&1 || {
    echo "🐍 正在安装 Python 库 (beautifulsoup4, lxml)..."
    pip install beautifulsoup4 lxml
}

# 2. 写入核心脚本 conv.sh
cat > ~/conv.sh << 'EOF_INNER'
#!/bin/bash
# conv.sh - EPUB 繁简转换 + 排版标准化 + Kindle 优化
# 用法: cc <文件名.epub>
# 作者: 基于开源工具 OpenCC 构建
# 许可: Apache 2.0

set -uo pipefail

# --- 配置 ---
W="$HOME/.epub_work"
D="$HOME/storage/downloads"
A="$D/E-book"
NAME_SUFFIX="-简中"

# --- 辅助函数 ---
die() { echo "❌ 错误: $*" >&2; exit 1; }
log() { echo "ℹ️  $*"; }
ok() { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }

# --- 参数检查 ---
[ $# -eq 0 ] && die "用法: cc <文件名.epub>"
INPUT="$1"

if [[ "$INPUT" == /* ]]; then
    IN="$INPUT"
elif [[ "$INPUT" == ~* ]]; then
    IN="${INPUT/#\~/$HOME}"
else
    IN="$D/$INPUT"
fi

[ ! -f "$IN" ] && [ -f "${IN}.epub" ] && IN="${IN}.epub"
[ ! -f "$IN" ] && die "找不到文件: $IN"

BASENAME=$(basename "$IN" .epub)
OUT_NAME="${BASENAME}${NAME_SUFFIX}.epub"
OUT_FILE="$W/$OUT_NAME"

cleanup() { rm -rf "$W"; }
trap cleanup EXIT

log "1/6 正在解压与准备..."
rm -rf "$W"
mkdir -p "$W" "$A"
unzip -q "$IN" -d "$W" || die "解压失败，文件可能损坏"

find "$W" -name ".DS_Store" -delete 2>/dev/null
find "$W" -name "Thumbs.db" -delete 2>/dev/null

mapfile -t HTML_FILES < <(find "$W" -type f \( -iname "*.xhtml" -o -iname "*.html" -o -iname "*.htm" \) -size -5M)
[ ${#HTML_FILES[@]} -eq 0 ] && die "未找到有效的 HTML/XHTML 内容文件"

log "2/6 正在处理竖排转横排..."
find "$W" -type f \( -name "*.css" -o -name "*.xhtml" -o -name "*.html" \) -exec sed -i \
    -e 's/writing-mode\s*:\s*vertical-rl/writing-mode: horizontal-tb/gI' \
    -e 's/writing-mode\s*:\s*vertical-lr/writing-mode: horizontal-tb/gI' \
    -e 's/-epub-writing-mode\s*:\s*vertical-rl/-epub-writing-mode: horizontal-tb/gI' \
    -e 's/-webkit-writing-mode\s*:\s*vertical-rl/-webkit-writing-mode: horizontal-tb/gI' \
    {} +

log "3/6 正在执行繁简转换 (OpenCC)..."
OCC_CFG=$(find /usr/share/opencc /data/data/com.termux/files/usr/share/opencc 2>/dev/null -name "t2s.json" | head -1)
[ -z "$OCC_CFG" ] && OCC_CFG="t2s.json"

for f in "${HTML_FILES[@]}"; do
    if grep -q "data:image" "$f"; then continue; fi
    opencc -i "$f" -o "$f.out" -c "$OCC_CFG"
    if [ -s "$f.out" ]; then
        mv "$f.out" "$f"
    else
        rm -f "$f.out"
    fi
done

log "4/6 正在执行智能排版 (Python)..."
python3 - "$W" << 'PYTHON_EOF'
import sys, os, re
from bs4 import BeautifulSoup, Comment

WORK_DIR = sys.argv[1]
SHORT_TEXT_THRESHOLD = 10

EXEMPT_KEYWORDS = ['no-indent', 'poem', 'verse', 'lyric', 'dialog', 'copyright', 'image', 'figure']

def should_indent(p_tag):
    parent = p_tag.parent
    while parent and parent.name != '[document]':
        if parent.name in ['table', 'ul', 'ol', 'pre', 'blockquote']:
            return False
        parent = parent.parent

    class_id_str = " ".join(p_tag.get("class", []) + [p_tag.get("id", "")]).lower()
    if any(kw in class_id_str for kw in EXEMPT_KEYWORDS):
        return False

    style = (p_tag.get("style") or "").lower()
    if "center" in style or "right" in style:
        return False

    text = p_tag.get_text(strip=True)
    if len(text) < SHORT_TEXT_THRESHOLD:
        return False
    if len(re.sub(r'[^\w\s]', '', text)) == 0:
        return False

    return True

for root, _, files in os.walk(WORK_DIR):
    for file in files:
        if file.endswith(('.html', '.xhtml', '.htm')):
            path = os.path.join(root, file)
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    soup = BeautifulSoup(f, 'html.parser')

                modified = False

                for p in soup.find_all('p'):
                    if should_indent(p):
                        current_class = p.get("class", [])
                        if "first-line-indent" not in current_class:
                            p["class"] = current_class + ["first-line-indent"]
                            modified = True

                for tag in soup.find_all(['p', 'div', 'span']):
                    if not tag.get_text(strip=True) and not tag.find():
                        tag.decompose()
                        modified = True

                if modified:
                    with open(path, 'w', encoding='utf-8') as f:
                        f.write(str(soup))
            except Exception as e:
                print(f"⚠️ 处理 {file} 时出错: {e}")
PYTHON_EOF

log "5/6 正在注入标准 CSS 样式..."
MAIN_CSS=$(find "$W" -name "*.css" | head -1)
if [ -z "$MAIN_CSS" ]; then
    MAIN_CSS="$W/style.css"
    echo "body {}" > "$MAIN_CSS"
fi

cat >> "$MAIN_CSS" << 'CSS_EOF'
/* === EPUB 繁简通 Pro 标准样式 === */
body, html { writing-mode: horizontal-tb !important; -epub-writing-mode: horizontal-tb !important; }
* { font-family: "Songti SC", "STSong", "SimSun", serif !important; }
p.first-line-indent { text-indent: 2em !important; }
p, div, li { margin: 0 !important; padding: 0 !important; line-height: 1.75 !important; text-align: justify !important; }
h1, h2, h3, h4, h5, h6 { text-align: center !important; text-indent: 0 !important; font-weight: bold !important; page-break-after: avoid; page-break-inside: avoid; }
h1 { margin: 1.5em 0 1em; font-size: 1.6em; }
h2 { margin: 1.2em 0 0.8em; font-size: 1.4em; }
h3 { margin: 1em 0 0.6em; font-size: 1.2em; text-align: left !important; }
blockquote { margin: 1em 2em; font-style: italic; border-left: 3px solid #ccc; padding-left: 1em; }
CSS_EOF

log "6/6 正在清理与打包..."
find "$W" -type f \( -iname "*.ttf" -o -iname "*.otf" -o -iname "*.woff" -o -iname "*.woff2" \) -delete 2>/dev/null

find "$W" -name "*.opf" -exec sed -i 's/xml:lang="zh-Hant"/xml:lang="zh-CN"/gI' {} + 2>/dev/null
find "$W" -name "*.opf" -exec sed -i 's/<dc:language>zh-Hant/<dc:language>zh-CN/gI' {} + 2>/dev/null

cd "$W"
rm -f "$OUT_FILE"

if [ -f "mimetype" ]; then
    zip -X0 "$OUT_FILE" mimetype
    zip -rX9 "$OUT_FILE" . -x "mimetype"
else
    zip -rX9 "$OUT_FILE" .
fi

zip -T "$OUT_FILE" > /dev/null || die "打包校验失败"

cp "$OUT_FILE" "$A/"
SIZE=$(du -h "$OUT_FILE" | cut -f1)

ok "处理完成: $OUT_NAME"
echo "📁 已保存至: $A"
echo "📊 文件大小: $SIZE"
EOF_INNER

# 3. 设置权限和别名
chmod +x ~/conv.sh

if ! grep -q "alias cc=" ~/.bashrc; then
    echo "alias cc='~/conv.sh'" >> ~/.bashrc
    echo "✅ 已添加别名 'cc' 到 .bashrc"
fi

source ~/.bashrc

echo ""
echo "🎉 部署成功！"
echo "------------------------------------------------"
echo "使用方法: cc 文件名.epub"
echo "示例: cc 三体.epub"
echo "文件将自动保存到: ~/storage/downloads/E-book/"
echo "------------------------------------------------"
