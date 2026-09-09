#!/bin/bash
# 港台繁体 EPUB 转换工具 · 一键部署脚本
# 适用：Termux（自动检测） / 普通 Linux / macOS

set -e

CONVERTER="converter.py"
COMMAND_NAME="cc-"
SHARE_DIR=""
BIN_DIR=""

echo "=========================================="
echo " 港台繁体 EPUB 转换工具 1.0 · 部署"
echo "=========================================="

# ---------- 1. 检测环境 ----------
IS_TERMUX=false
if [ -n "$PREFIX" ] && [ -d "$PREFIX/usr" ]; then
    IS_TERMUX=true
fi

if $IS_TERMUX; then
    SHARE_DIR="$PREFIX/share/cc-epub"
    BIN_DIR="$PREFIX/bin"
    echo "[1/6] 环境：Termux"
else
    SHARE_DIR="$HOME/.local/share/cc-epub"
    BIN_DIR="$HOME/.local/bin"
    echo "[1/6] 环境：普通 Linux / macOS"
fi

# ---------- 2. 安装依赖 ----------
echo "[2/6] 检查依赖..."

install_pkg() {
    if $IS_TERMUX; then
        pkg install -y "$@" 2>/dev/null || true
    else
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y "$@" 2>/dev/null || true
        fi
    fi
}

# 系统包
if $IS_TERMUX; then
    install_pkg libopencc opencc-tools python git unzip zip
else
    install_pkg libopencc-dev 2>/dev/null || true
fi

# Python 包
python3 -c "import opencc" 2>/dev/null || pip install opencc || true
python3 -c "import bs4"   2>/dev/null || pip install beautifulsoup4 || true

# ---------- 3. 授权存储（Termux） ----------
if $IS_TERMUX; then
    echo "[3/6] 授权存储..."
    termux-setup-storage 2>/dev/null || true
fi

# ---------- 4. 安装文件 ----------
echo "[4/6] 安装文件到 $SHARE_DIR ..."
mkdir -p "$SHARE_DIR"
cp "$CONVERTER" "$SHARE_DIR/" 2>/dev/null || cp "$(dirname "$0")/$CONVERTER" "$SHARE_DIR/"
mkdir -p "$BIN_DIR"

# 生成 cc- 命令
cat > "$BIN_DIR/$COMMAND_NAME" <<EOF
#!/bin/bash
# 自动生成，请勿手动编辑
export CC_EPUB_SHARE="$SHARE_DIR"
exec python3 "$SHARE_DIR/$CONVERTER" "\$@"
EOF
chmod +x "$BIN_DIR/$COMMAND_NAME"
echo "   → $BIN_DIR/$COMMAND_NAME"

# ---------- 5. 创建输出目录 ----------
echo "[5/6] 创建输出目录..."
if $IS_TERMUX; then
    OUT_BASE="$HOME/storage/downloads"
else
    OUT_BASE="$HOME/Download"
fi
mkdir -p "$OUT_BASE/E-book" 2>/dev/null || true

# ---------- 6. 自检 ----------
echo "[6/6] 运行自检..."

# 强自检：真实 EPUB 端到端转换，直接读输出文件判定（不只 import）
SELFTEST_DIR=$(mktemp -d)
SELFTEST_EPUB="$SELFTEST_DIR/src.epub"
cat > "$SELFTEST_DIR/build.py" <<'PY'
import zipfile, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import converter as C
# 构造繁体+竖排测试书
content = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>
@page{writing-mode:vertical-rl}
body{font-family:'微軟正黑體'}
</style></head><body>
<p>矽二極體壞了，電腦無法運作。</p>
</body></html>"""
epub = os.environ["SELFTEST_EPUB"]
with zipfile.ZipFile(epub, "w") as z:
    zi = zipfile.ZipInfo("mimetype"); zi.compress_type = zipfile.ZIP_STORED
    z.writestr(zi, b"application/epub+zip")
    z.writestr("META-INF/container.xml", b"""<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="content.xhtml" media-type="application/xhtml+xml"/></rootfiles>
</container>""")
    z.writestr("content.xhtml", content.encode("utf-8"))
out_dir = os.path.join(os.environ["SELFTEST_DIR"], "out")
os.makedirs(out_dir, exist_ok=True)
C.get_output_dir = lambda: out_dir
result = C.convert_epub(epub, output_path=os.path.join(out_dir, "out-简中.epub"))
# 读取真实输出判定
import zipfile as Z
extract = os.path.join(os.environ["SELFTEST_DIR"], "ex")
os.makedirs(extract, exist_ok=True)
with Z.ZipFile(result) as z: z.extractall(extract)
html = open(os.path.join(extract, "content.xhtml"), encoding="utf-8", errors="replace").read()
ok_opencc = ("硅二极管" in html) and ("坏" in html) and ("电脑" in html) and ("矽" not in html)
ok_horizontal = ("horizontal-tb" in html) and ("vertical-rl" not in html)
ok_font = "微軟正黑體" not in html
print("OPENCC_OK=%s" % ok_opencc)
print("HORIZONTAL_OK=%s" % ok_horizontal)
print("FONT_OK=%s" % ok_font)
PY

SELFTEST_DIR="$SELFTEST_DIR" SELFTEST_EPUB="$SELFTEST_EPUB" \
    python3 "$SELFTEST_DIR/build.py" > "$SELFTEST_DIR/result.log" 2>&1
cat "$SELFTEST_DIR/result.log"

if grep -q "OPENCC_OK=True" "$SELFTEST_DIR/result.log" \
   && grep -q "HORIZONTAL_OK=True" "$SELFTEST_DIR/result.log" \
   && grep -q "FONT_OK=True" "$SELFTEST_DIR/result.log"; then
    echo ""
    echo "=========================================="
    echo " ✅ 部署完成！"
    echo " ✅ opencc 真实生效（矽二極體→硅二极管）"
    echo " ✅ 横排生效（vertical-rl→horizontal-tb）"
    echo " ✅ 字体统一（清除繁体 font-family）"
    echo "=========================================="
    echo ""
    echo "使用方法："
    echo "   cc- --list         # 列出可转换的书"
    echo "   cc- 书名            # 转换，输出 书名-简中.epub"
    echo ""
    echo " 输出目录：$OUT_BASE/E-book/"
    echo ""
    echo " 首次使用请先：termux-setup-storage"
    echo "=========================================="
    rm -rf "$SELFTEST_DIR"
    exit 0
else
    echo ""
    echo "⚠️  警告：自检未通过，opencc 未真实生效。"
    echo "    常见原因：只装了 pip opencc 但缺系统库，或反之。"
    echo "    请手动检查："
    echo "      pkg install libopencc opencc-tools"
    echo "      pip install opencc beautifulsoup4"
    echo "      python3 -c \"import opencc; print(opencc.OpenCC('tw2sp').convert('矽二極體'))\""
    echo "      # 期望输出：硅二极管"
    rm -rf "$SELFTEST_DIR"
    exit 1
fi
