#!/bin/bash
# install.sh — 一键部署 cc-epub (Termux / 普通 Linux / macOS)
set -e

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) Termux 环境适配
if [ -n "$PREFIX" ] && command -v termux-setup-storage >/dev/null 2>&1; then
    termux-setup-storage || true
    BIN="$PREFIX/bin"
    SHARE="$PREFIX/share/cc-epub"
else
    BIN="$HOME/.local/bin"
    SHARE="$HOME/.local/share/cc-epub"
fi

mkdir -p "$BIN" "$SHARE"
cp "$SRC/converter.py" "$SHARE/converter.py"
cp "$SRC/audit.py"    "$SHARE/audit.py"    2>/dev/null || true

# 2) 生成 `cc-` 便捷命令（用环境变量硬编码 share 路径，避免解析脆弱）
cat > "$BIN/cc-" <<EOF
#!/bin/bash
# 用法: cc- 书名   (支持模糊匹配，等价于 converter.py 的 find_epub)
export CC_EPUB_SHARE="$SHARE"
exec python3 "$SHARE/converter.py" "\$@"
EOF
chmod +x "$BIN/cc-"

# 3) 依赖检查（Termux 用 pkg，其余提示 pip）
if [ -n "$PREFIX" ]; then
    command -v python3 >/dev/null 2>&1 || pkg install -y python
else
    command -v python3 >/dev/null 2>&1 || echo "请先安装 python3"
fi

echo "安装完成: $BIN/cc-"
echo "  转换:  cc- 书名"
echo "  列出:  cc- --list"
