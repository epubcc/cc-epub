#!/usr/bin/env bash
# cc-epub 一键部署脚本（Termux）
# 仓库：https://github.com/epubcc/cc-epub
# 用法：bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${BLUE}[*]${NC} $*"; }
ok()   { echo -e "${GREEN}[+]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  cc-epub 部署工具  (Termux / Linux)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1) 更新软件源
log "更新软件包列表..."
if command -v pkg >/dev/null 2>&1; then
  pkg update -y >/dev/null 2>&1 || true
else
  warn "未检测到 Termux 'pkg'，假定为 Linux/macOS，跳过 pkg update"
fi

# 2) 系统依赖（Termux 官方仓库：libopencc + opencc-tools，没有 "Open CC" 这个包）
log "安装系统依赖 (python, git, zip, unzip, libopencc, opencc-tools)..."
if command -v pkg >/dev/null 2>&1; then
  pkg install -y python git zip unzip libopencc opencc-tools 2>&1 | tail -3 || true
elif command -v apt-get >/dev/null 2>&1; then
  sudo apt-get install -y python3 git zip unzip libopencc-dev 2>&1 | tail -3 || true
fi

# 3) Python 依赖
log "安装 Python 库 (beautifulsoup4)..."
pip install --quiet beautifulsoup4 2>&1 | tail -2 || true

# 4) 克隆 / 更新仓库到 ~/cc-epub
INSTALL_DIR="$HOME/cc-epub"
if [ -d "$INSTALL_DIR/.git" ]; then
  log "更新已有仓库: $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only 2>&1 | tail -2 || true
else
  log "克隆仓库到 $INSTALL_DIR ..."
  if [ -d "$INSTALL_DIR" ]; then rm -rf "$INSTALL_DIR"; fi
  git clone https://github.com/epubcc/cc-epub.git "$INSTALL_DIR" 2>&1 | tail -3
fi

# 5) 配置 'cc' 快捷命令（三保险：~/bin/cc wrapper + PATH + alias）
mkdir -p "$HOME/bin"
export PATH="$HOME/bin:$PATH"

# wrapper script（优先级最高，覆盖 clang 自带的 cc）
cat > "$HOME/bin/cc" <<WRAPPER
#!/bin/bash
# cc-epub 快捷命令
exec python "\$HOME/cc-epub/cc.py" "\$@"
WRAPPER
chmod +x "$HOME/bin/cc"

# 写入 shell rc，保证新会话也生效
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
  [ -f "$rc" ] || continue
  grep -qF 'export PATH="$HOME/bin:$PATH"' "$rc" 2>/dev/null || \
    echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
  grep -qF 'alias cc=' "$rc" 2>/dev/null || \
    echo "alias cc='python \$HOME/cc-epub/cc.py'" >> "$rc"
done

# 6) 验证
echo ""
log "验证安装："
if command -v cc >/dev/null 2>&1; then
  ok "cc 命令已就绪：$(command -v cc)"
else
  warn "cc 命令暂未进入当前 PATH，请运行：source ~/.bashrc  或重启 Termux"
fi

python "$HOME/cc-epub/cc.py" --version 2>&1 || true
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "部署完成！"
echo ""
echo "  使用方法："
echo "    cc 书名.epub                         # 单本转换"
echo "    cc ~/Download/                       # 批量转换整目录"
echo "  输出位置："
echo "    ~/storage/shared/Download/E-book/书名-简中.epub"
echo ""
echo "  若提示 'command not found'，请运行：source ~/.bashrc  或重启 Termux"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
