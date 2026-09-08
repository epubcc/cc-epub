#!/usr/bin/env bash

# cc-epub 一键部署脚本
# 用户名: epubcc | 仓库名: cc-epub
# 功能：安装依赖、配置环境、设置 cc 快捷命令

set -e  # 遇到错误立即停止

echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "  cc-epub 部署开始"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

# [1/4] 更新软件包列表
echo "[1/4] 正在更新软件包列表..."
pkg update -y >/dev/null 2>&1

# [2/4] 安装系统依赖
echo "[2/4] 正在安装基础依赖 (python, git, zip, unzip, opencc)..."
pkg install -y python git zip unzip libopencc opencc-tools

# [3/4] 安装 Python 库
echo "[3/4] 正在安装 Python 库 (beautifulsoup4)..."
pip install beautifulsoup4

# [4/4] 配置 cc 快捷命令（三保险：PATH + alias + wrapper script）
echo "[4/4] 正在配置快捷命令..."

# 创建 ~/bin 目录并加入 PATH 最前面（覆盖系统 cc 命令）
mkdir -p ~/bin

# 写入 PATH 配置（同时写入 .bashrc 和 .zshrc）
for rc in ~/.bashrc ~/.zshrc; do
    if [ -f "$rc" ]; then
        # 避免重复写入 PATH
        if ! grep -qF 'export PATH="$HOME/bin:$PATH"' "$rc" 2>/dev/null; then
            echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
        fi
        # 避免重复写入 alias
        if ! grep -qF "alias cc=" "$rc" 2>/dev/null; then
            echo "alias cc='python \$HOME/cc-epub/cc.py'" >> "$rc"
        fi
    fi
done

# 立即生效 PATH
export PATH="$HOME/bin:$PATH"

# 创建 wrapper script（最可靠的覆盖方式，优先级高于 clang 的 cc）
cat > ~/bin/cc << 'WRAPPER_EOF'
#!/bin/bash
python "$HOME/cc-epub/cc.py" "$@"
WRAPPER_EOF

chmod +x ~/bin/cc

# 验证安装
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 部署完成！"
echo ""
echo "验证 cc 命令是否生效："
echo "  type cc"
echo ""
echo "使用方法："
echo "  cc 书名.epub"
echo "  cc ~/storage/shared/Download/原子习惯.epub"
echo ""
echo "输出位置："
echo "  ~/storage/shared/Download/E-book/书名-简中.epub"
echo ""
echo "💡 提示：如果提示 'command not found'，请重启 Termux 或运行 'source ~/.bashrc'"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
