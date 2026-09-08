#!/bin/bash
# setup_termux.sh — conv.sh 一键环境搭建脚本（纯 Termux 原生）
# 用法: bash setup_termux.sh
# 本脚本会在 Termux 原生环境中安装所有依赖，无需额外容器环境

set -e

echo "============================================"
echo "  conv.sh Termux 环境搭建脚本"
echo "============================================"
echo ""

# ── 检测运行环境 ──
if [ -d "/data/data/com.termux" ] || [ -n "$TERMUX_VERSION" ]; then
    echo "✅ 检测到 Termux 环境"
else
    echo "⚠️  当前可能不在 Termux 环境中运行"
    echo "   本脚本设计用于 Termux，在非 Termux 环境中可能失败"
    echo "   如需继续，请确保已安装: opencc-tools (提供 opencc 命令) + libopencc (运行时库), unzip, zip, sed, grep, findutils, perl"
    read -p "是否继续? (y/N) " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        exit 0
    fi
fi

# ── 更新包索引 ──
echo ""
echo ">>> 正在更新包索引..."
pkg update -y

# ── 安装核心依赖 ──
echo ""
echo ">>> 正在安装核心依赖..."
pkg install -y \
    libopencc \
    opencc-tools \
    unzip \
    zip \
    sed \
    grep \
    findutils \
    perl \
    coreutils \
    bash

# ── 验证安装 ──
echo ""
echo "============================================"
echo "  验证安装..."
echo "============================================"

ALL_OK=1

check_cmd() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "✅ $1 已安装"
    else
        echo "❌ $1 未找到"
        ALL_OK=0
    fi
}

check_cmd opencc
check_cmd unzip
check_cmd zip
check_cmd sed
check_cmd grep
check_cmd find
check_cmd perl

# ── 验证 OpenCC 配置（动态查找，不硬编码路径） ──
OCC_PATH=$(find /data -name 't2s*.json' -type f 2>/dev/null | head -1)
if [ -z "$OCC_PATH" ]; then
    OCC_PATH=$(find /usr -name 't2s*.json' -type f 2>/dev/null | head -1)
fi
if [ -n "$OCC_PATH" ]; then
    echo "✅ OpenCC 配置: $OCC_PATH"
else
    echo "❌ 未找到 OpenCC 配置文件 t2s.json"
    ALL_OK=0
fi

# ── 创建 E-book 输出目录 ──
mkdir -p "$HOME/storage/downloads/E-book" 2>/dev/null || true
echo "✅ 输出目录: $HOME/storage/downloads/E-book"

# ── 结果 ──
echo ""
if [ "$ALL_OK" = "1" ]; then
    echo "============================================"
    echo "  ✅ 环境搭建完成！"
    echo "============================================"
    echo ""
    echo "使用方法:"
    echo "  1. 将 conv.sh 复制到 Termux 任意目录"
    echo "  2. 赋予执行权限: chmod +x conv.sh"
    echo "  3. 运行: ./conv.sh 你的书.epub"
    echo ""
    echo "EPUB 文件可放在:"
    echo "  - $HOME/storage/downloads/  （下载目录）"
    echo "  - 任意绝对路径，如 /sdcard/Download/书.epub"
    echo ""
    echo "提示: 如果转换大文件时 Termux 被杀后台，"
    echo "      请先运行 termux-wake-lock 保持后台运行"
else
    echo "============================================"
    echo "  ❌ 部分依赖安装失败，请检查上方错误信息"
    echo "============================================"
    exit 1
fi
