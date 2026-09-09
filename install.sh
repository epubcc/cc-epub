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
if python3 -c "import opencc; print('opencc:', opencc.OpenCC('tw2sp').convert('測試'))" 2>/dev/null | grep -q "测试"; then
    echo ""
    echo "=========================================="
    echo " ✅ 部署完成！"
    echo " ✅ opencc 工作正常"
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
    exit 0
else
    echo "⚠️  警告：opencc 自检未通过，请手动检查："
    echo "   pkg install libopencc opencc-tools"
    echo "   pip install opencc beautifulsoup4"
    exit 1
fi
