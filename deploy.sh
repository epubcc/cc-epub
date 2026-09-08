#!/data/data/com.termux/files/usr/bin/bash
# cc-epub 一键部署脚本
# 用法: bash deploy.sh

set -e

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}  cc-epub 部署脚本${NC}"
echo -e "${GREEN}====================================${NC}"
echo ""

# 检查是否在Termux中运行
if [ ! -d "/data/data/com.termux" ]; then
    echo -e "${RED}错误: 此脚本只能在 Termux 中运行${NC}"
    exit 1
fi

echo -e "${YELLOW}[1/5] 更新包管理器...${NC}"
pkg update -y && pkg upgrade -y

echo -e "${YELLOW}[2/5] 安装系统依赖...${NC}"
pkg install libopencc opencc-tools zip unzip python curl -y

echo -e "${YELLOW}[3/5] 安装 Python 库...${NC}"
pip install beautifulsoup4

echo -e "${YELLOW}[4/5] 下载核心脚本...${NC}"
RAW_URL="https://raw.githubusercontent.com/epubcc/cc-epub/main/conv.sh"
curl -fsSL "$RAW_URL" -o "${HOME}/conv.sh"
chmod +x "${HOME}/conv.sh"

echo -e "${YELLOW}[5/5] 配置快捷命令...${NC}"
# 添加到 bashrc
if ! grep -q "alias cc=" "${HOME}/.bashrc" 2>/dev/null; then
    echo "" >> "${HOME}/.bashrc"
    echo "# cc-epub alias" >> "${HOME}/.bashrc"
    echo "alias cc='bash \${HOME}/conv.sh'" >> "${HOME}/.bashrc"
fi

# 同时配置 zshrc
if [ -f "${HOME}/.zshrc" ]; then
    if ! grep -q "alias cc=" "${HOME}/.zshrc" 2>/dev/null; then
        echo "" >> "${HOME}/.zshrc"
        echo "# cc-epub alias" >> "${HOME}/.zshrc"
        echo "alias cc='bash \${HOME}/conv.sh'" >> "${HOME}/.zshrc"
    fi
fi

# 创建输出目录
mkdir -p "${HOME}/storage/downloads/E-book"

# 重新加载配置
source "${HOME}/.bashrc" 2>/dev/null || true

echo ""
echo -e "${GREEN}====================================${NC}"
echo -e "${GREEN}  🎉 部署完成！${NC}"
echo -e "${GREEN}====================================${NC}"
echo ""
echo "使用方法："
echo "  cc 书名.epub"
echo ""
echo "示例："
echo "  cc 行为.epub"
echo ""
echo "输出文件将保存在："
echo "  ~/storage/downloads/E-book/"
echo ""
echo -e "${YELLOW}⚠️ 请重启 Termux 或执行 'source ~/.bashrc' 使 cc 命令生效${NC}"
