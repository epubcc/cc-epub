#!/data/data/com.termux/files/usr/bin/bash
# -*- coding: utf-8 -*-
#
# Termux 一键部署脚本
# 功能：自动安装依赖、配置 cc 快捷命令
#
# 使用方法：
#   1. 将 cc.py 和 install.sh 放在同一目录
#   2. 运行: bash install.sh
#

set -e

echo "[*] 正在更新 Termux 仓库..."
pkg update -y && pkg upgrade -y

echo "[*] 正在安装必要依赖 (Python3, opencc-tools, zip, unzip, libxslt)..."
pkg install -y python zip unzip libxslt opencc-tools

echo "[*] 正在安装 Python 库 beautifulsoup4 和 lxml..."
pip install --upgrade pip
pip install beautifulsoup4 lxml

# 将 cc.py 移动到 Termux 全局可执行路径
echo "[*] 正在配置 cc 命令..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/cc.py" ]; then
    chmod +x "$SCRIPT_DIR/cc.py"
    cp "$SCRIPT_DIR/cc.py" "$PREFIX/bin/cc"
    echo "[+] cc 命令已配置完成！"
else
    echo "[-] 未找到 cc.py 文件，请确保 cc.py 与 install.sh 在同一目录下"
    exit 1
fi

echo ""
echo "=========================================="
echo " 部署完成！"
echo " 1. 将待转换的 EPUB 文件放入任意目录"
echo " 2. 在 Termux 中运行: cc 书名.epub"
echo " 3. 转换后的文件将自动存入: /sdcard/Download/E-book"
echo "=========================================="
