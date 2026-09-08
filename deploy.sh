#!/bin/bash
# deploy.sh - cc-epub 一键部署脚本
# 功能: 自动安装依赖、部署 conv.sh、配置 cc 别名

set -e

REPO_RAW="https://raw.githubusercontent.com/epubcc/cc-epub/main"

echo "🚀 正在部署 cc-epub 环境..."
echo "================================================"

# --- 1. 检查并安装系统依赖 ---
echo "🔍 正在检查系统依赖..."

NEED_INSTALL=""
for cmd in unzip zip opencc python3; do
    if ! command -v "$cmd" &> /dev/null; then
        NEED_INSTALL="$NEED_INSTALL $cmd"
    fi
done

if [ -n "$NEED_INSTALL" ]; then
    echo "📦 正在安装缺失的依赖:$NEED_INSTALL ..."
    pkg update -y
    pkg install $NEED_INSTALL -y
else
    echo "✅ 系统依赖已就绪"
fi

# --- 2. 检查并安装 Python 库 ---
echo "🐍 正在检查 Python 库..."
pip show beautifulsoup4 > /dev/null 2>&1 || {
    echo "📦 正在安装 beautifulsoup4..."
    pip install beautifulsoup4
}
echo "✅ Python 库已就绪"

# --- 3. 授权存储访问 ---
echo "📂 正在配置存储访问..."
if [ ! -d "$HOME/storage" ]; then
    termux-setup-storage
    echo "⚠️  请在弹出的对话框中点击「允许」授权存储访问"
    sleep 3
fi
mkdir -p "$HOME/storage/downloads/E-book"
echo "✅ 存储已就绪"

# --- 4. 下载核心脚本 ---
echo "⬇️  正在下载核心脚本..."
curl -fsSL "$REPO_RAW/conv.sh" -o "$HOME/conv.sh" || {
    echo "❌ 下载失败，请检查网络连接"
    echo "   你也可以手动将 conv.sh 放到 ~/conv.sh"
    exit 1
}
chmod +x "$HOME/conv.sh"
echo "✅ conv.sh 已部署到 ~/conv.sh"

# --- 5. 配置别名 ---
echo "⚙️  正在配置命令别名..."
if ! grep -q "alias cc=" "$HOME/.bashrc" 2>/dev/null; then
    echo "" >> "$HOME/.bashrc"
    echo "# cc-epub 快捷命令" >> "$HOME/.bashrc"
    echo "alias cc='~/conv.sh'" >> "$HOME/.bashrc"
    echo "✅ 已添加 'cc' 别名到 ~/.bashrc"
else
    echo "✅ 'cc' 别名已存在，跳过"
fi

# --- 6. 语法检查 ---
echo "🔧 正在验证脚本..."
bash -n "$HOME/conv.sh" || {
    echo "❌ conv.sh 语法检查失败"
    exit 1
}
echo "✅ 语法检查通过"

# --- 完成 ---
echo "================================================"
echo "🎉 cc-epub 部署成功！"
echo ""
echo "使用方法:"
echo "  cc 书名.epub"
echo ""
echo "示例:"
echo "  cc san-ti.epub"
echo ""
echo "输出目录: ~/storage/downloads/E-book/"
echo ""
echo "⚠️  请执行以下命令使 cc 命令立即生效:"
echo "  source ~/.bashrc"
echo "  (或者直接重启 Termux)"
echo "================================================"
