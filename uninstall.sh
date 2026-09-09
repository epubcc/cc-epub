#!/bin/bash
# ============================================================
#  cc-epub 卸载脚本
# ============================================================

set -e

echo "============================================"
echo "  cc-epub 卸载脚本"
echo "============================================"
echo ""

# 1. 移除命令别名
BASHRC="$HOME/.bashrc"
MARKER="# >>> cc-epub >>>"
if grep -q "$MARKER" "$BASHRC" 2>/dev/null; then
    # 使用 sed 删除标记之间的内容（macOS/BSD sed 兼容）
    sed -i '/# >>> cc-epub >>>/,/# <<< cc-epub <<</d' "$BASHRC"
    echo "  ✓ 已移除 ~/.bashrc 中的 cc-epub 配置"
else
    echo "  · ~/.bashrc 中未找到 cc-epub 配置，跳过"
fi

# 2. 移除软链接
if [ -L "$HOME/.local/bin/cc" ]; then
    rm "$HOME/.local/bin/cc"
    echo "  ✓ 已移除命令软链接"
fi

# 3. 询问是否删除项目目录
echo ""
read -p "  是否删除 cc-epub 项目目录？[y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/cc-epub"
    echo "  ✓ 已删除项目目录"
fi

# 4. 询问是否删除输出文件
echo ""
read -p "  是否删除已转换的输出文件（Download/E-book）？[y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$HOME/storage/downloads/E-book"
    echo "  ✓ 已删除输出目录"
fi

echo ""
echo "============================================"
echo "  卸载完成。依赖包（libopencc 等）未移除。"
echo "  如需彻底清理：pkg uninstall libopencc opencc-tools"
echo "============================================"
