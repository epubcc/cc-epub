#!/usr/bin/env bash

# Termux EPUB 繁简转换工具安装脚本
# 功能：安装依赖、配置环境、设置快捷命令

set -e  # 遇到错误立即停止

echo "========================================"
echo "  EPUB 繁简转换工具 (cc.py) 安装程序"
echo "  适用于 Termux (Android)"
echo "========================================"

# 1. 更新源
echo "[1/5] 正在更新软件包列表..."
pkg update -y > /dev/null 2>&1

# 2. 安装基础依赖
echo "[2/5] 正在安装基础依赖 (python, git, opencc)..."
pkg install python git zip unzip opencc-tools -y

# 3. 安装 Python 库
echo "[3/5] 正在安装 Python 库 (beautifulsoup4)..."
pip install --upgrade pip
pip install beautifulsoup4

# 4. 赋予脚本执行权限
echo "[4/5] 正在配置执行权限..."
chmod +x cc.py

# 5. 创建快捷命令 (可选)
# 检查是否已经存在 alias
if ! grep -q "alias cc=" ~/.bashrc 2>/dev/null; then
    echo "alias cc='python ~/cc-epub/cc.py'" >> ~/.bashrc
    echo "[+] 已创建快捷命令 'cc'"
fi

echo ""
echo "========================================"
echo "✅ 安装完成！"
echo ""
echo "🚀 使用方法："
echo "   方法1 (推荐): 直接在任意目录输入 'cc 文件名.epub'"
echo "   方法2: 输入 'python ~/cc-epub/cc.py 文件名.epub'"
echo ""
echo "💡 提示：如果提示 'command not found'，请重启 Termux 或运行 'source ~/.bashrc'"
echo "========================================"
