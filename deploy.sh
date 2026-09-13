#!/usr/bin/env bash
# deploy.sh v3.15.0

set -e

FORCE=0; ROLLBACK=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --rollback) ROLLBACK=1 ;;
    --uninstall) UNINSTALL=1 ;;
  esac
done

die()  { echo "✗ $*" >&2; exit 1; }
info() { echo "  $*" >&2; }
ok()   { echo "  ✓ $*" >&2; }

if [ "$UNINSTALL" = "1" ]; then
  rm -f "$HOME/.local/bin/zh" "$HOME/.local/bin/zh.bak" "$HOME/cc-epub.log" \
        "$HOME/.cc_resume" "$HOME/.cc_config" "$HOME/.cc_epub.lock" "$HOME/.cc_version_check"
  rm -rf "$HOME/w"
  sed -i '\|export PATH="$HOME/.local/bin:$PATH"|d' "$HOME/.bashrc" 2>/dev/null
  ok "卸载完成"; exit 0
fi

if [ "$ROLLBACK" = "1" ]; then
  [ -f "$HOME/.local/bin/zh.bak" ] && mv "$HOME/.local/bin/zh.bak" "$HOME/.local/bin/zh" && ok "已回滚" || die "无备份"
  exit 0
fi

echo "cc-epub 部署 v3.15.0"
echo "─────────────────────────────"

command -v pkg >/dev/null 2>&1 || die "非 Termux 环境"

info "更新源..."
pkg update -y 2>/dev/null || true

info "安装核心依赖..."
pkg install -y libopencc opencc-tools zip unzip perl 2>/dev/null || die "核心依赖失败"

info "安装可选依赖..."
pkg install -y git curl wget util-linux 2>/dev/null || true

echo ""
info "依赖检查:"
all_ok=1
for c in opencc unzip zip perl; do
  command -v "$c" >/dev/null 2>&1 && echo "  ✓ $c" || { echo "  ✗ $c"; all_ok=0; }
done
command -v flock >/dev/null 2>&1 && echo "  ✓ flock" || echo "  · flock (可选)"
[ "$all_ok" = "0" ] && die "核心依赖缺失"

info "安装 zh 命令..."
mkdir -p "$HOME/.local/bin"
[ -f "$HOME/.local/bin/zh" ] && cp "$HOME/.local/bin/zh" "$HOME/.local/bin/zh.bak" 2>/dev/null

SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/conv.sh"
if [ -f "$SRC" ] && [ "$FORCE" = "0" ]; then
  cp "$SRC" "$HOME/.local/bin/zh" && ok "从本地复制"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL --max-time 10 "https://raw.githubusercontent.com/epubcc/cc-epub/main/conv.sh" -o "$HOME/.local/bin/zh" 2>/dev/null && ok "从 GitHub 下载"
elif command -v wget >/dev/null 2>&1; then
  wget -q --timeout=10 "https://raw.githubusercontent.com/epubcc/cc-epub/main/conv.sh" -O "$HOME/.local/bin/zh" 2>/dev/null && ok "从 GitHub 下载"
else
  die "无法获取 conv.sh"
fi

chmod +x "$HOME/.local/bin/zh"

if ! grep -qF '$HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  ok "PATH 已配置"
fi

mkdir -p "$HOME/storage/downloads/E-book" 2>/dev/null

echo ""
echo "─────────────────────────────"
ok "部署完成"
echo ""
echo "  验证: zh -v"
echo "  诊断: zh --check"
echo "  使用: zh 书.epub"
echo "  卸载: bash deploy.sh --uninstall"
