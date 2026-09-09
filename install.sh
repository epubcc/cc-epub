#!/bin/bash
# ============================================================
#  cc-epub 一键部署脚本
#  功能：配置 PATH、命令别名、字体规范、输出目录
# ============================================================

set -e

echo "============================================"
echo "  cc-epub 部署脚本 v1.0"
echo "  Kindle Paperwhite SE (12th) + Termux"
echo "============================================"
echo ""

REPO_DIR="$HOME/cc-epub"
SCRIPTS_DIR="$REPO_DIR/scripts"
CONFIG_DIR="$REPO_DIR/config"
OUTPUT_DIR="$HOME/storage/downloads/E-book"
BIN_DIR="$HOME/.local/bin"

# --- 1. 检查依赖 ---
echo "[1/5] 检查依赖..."

check_pkg() {
    if ! command -v "$1" &>/dev/null && ! dpkg -l | grep -q "$1"; then
        echo "  ✗ $1 未安装，正在安装..."
        pkg install -y "$1"
    else
        echo "  ✓ $1 已就绪"
    fi
}

# Termux 包名是 opencc-tools / libopencc
if ! command -v opencc &>/dev/null; then
    echo "  ✗ opencc 未安装，正在安装 libopencc + opencc-tools..."
    pkg install -y libopencc opencc-tools
else
    echo "  ✓ opencc 已就绪 ($(opencc --version 2>&1 | head -1))"
fi

check_pkg zip
check_pkg unzip
check_pkg python

# --- 2. 存储权限 ---
echo ""
echo "[2/5] 检查存储权限..."
if [ ! -d "$HOME/storage/downloads" ]; then
    echo "  需要授予存储权限..."
    termux-setup-storage
    sleep 2
fi
mkdir -p "$OUTPUT_DIR"
echo "  ✓ 输出目录：$OUTPUT_DIR"

# --- 3. 配置 PATH ---
echo ""
echo "[3/5] 配置 PATH 与命令别名..."

mkdir -p "$BIN_DIR"

# 创建 `cc` 命令软链接
ln -sf "$SCRIPTS_DIR/cc.sh" "$BIN_DIR/cc"
chmod +x "$SCRIPTS_DIR/cc.sh"
chmod +x "$SCRIPTS_DIR/convert.py"

# 写入 ~/.bashrc 配置
BASHRC="$HOME/.bashrc"
MARKER="# >>> cc-epub >>>"
if ! grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    cat >> "$BASHRC" << 'EOF'

# >>> cc-epub >>>
export PATH="$HOME/.local/bin:$PATH"
export CC_EPUB_HOME="$HOME/cc-epub"
export CC_EPUB_OUTPUT="$HOME/storage/downloads/E-book"
alias cc='$HOME/cc-epub/scripts/cc.sh'
# <<< cc-epub <<<
EOF
    echo "  ✓ 已写入 ~/.bashrc"
else
    echo "  ✓ ~/.bashrc 已配置，跳过"
fi

# 立即生效（当前会话）
export PATH="$BIN_DIR:$PATH"
export CC_EPUB_HOME="$REPO_DIR"
export CC_EPUB_OUTPUT="$OUTPUT_DIR"

# --- 4. 部署配置文件 ---
echo ""
echo "[4/5] 部署配置文件..."

# 确保 config 文件存在
if [ ! -f "$CONFIG_DIR/opencc-chain.json" ]; then
    echo "  ⚠ config/opencc-chain.json 缺失，请检查仓库完整性"
else
    echo "  ✓ OpenCC 转换链配置就绪"
fi

if [ ! -f "$CONFIG_DIR/kindle-css.css" ]; then
    echo "  ⚠ config/kindle-css.css 缺失，请检查仓库完整性"
else
    echo "  ✓ Kindle CSS 模板就绪"
fi

# --- 5. 完成 ---
echo ""
echo "[5/5] 部署完成！"
echo "============================================"
echo ""
echo "  📖 使用方式："
echo "     cc 书名              # 转换为简体横排"
echo "     cc 书名 --keep-font  # 保留原字体（不推荐）"
echo ""
echo "  📁 输出目录：$OUTPUT_DIR"
echo ""
echo "  ⚠ 首次使用请先执行：source ~/.bashrc"
echo "     或者重新打开 Termux 会话"
echo ""
echo "============================================"
