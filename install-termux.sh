#!/bin/bash
# Termux 一键部署脚本（OPPO Find X8s / 任意 Android）
# 用法：bash install-termux.sh
set -e

echo "==> [1/5] 更新 Termux 软件源..."
pkg update -y && pkg upgrade -y

echo "==> [2/5] 安装 Python + OpenCC（系统包，比 pip 编译快）..."
pkg install -y python opencc

echo "==> [3/5] 授予存储权限（可访问 /sdcard/Download）..."
termux-setup-storage

echo "==> [4/5] 安装 Python 依赖..."
pip install --upgrade pip
pip install -r requirements.txt

echo "==> [5/5] 创建命令别名 'cc'..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "alias cc='python \"$SCRIPT_DIR/convert.py\"'" >> "$HOME/.bashrc"
echo "alias cc='python \"$SCRIPT_DIR/convert.py\"'" >> "$HOME/.zshrc" 2>/dev/null || true

echo ""
echo "✅ 安装完成！"
echo "用法示例："
echo "  cc /sdcard/Download/E-book/某书.epub"
echo "  → 输出：/sdcard/Download/E-book/某书-cc.epub"
echo ""
echo "（新终端生效；或执行 source ~/.bashrc）"
