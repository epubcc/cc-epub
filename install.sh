#!/usr/bin/env bash
# ============================================================
#  cc-epub 一键部署脚本（Termux 专用，兼容 Android）
#  用户名: epubcc | 仓库: cc-epub
#  功能: 换国内镜像源 → 装依赖 → 配 cc 快捷命令
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  cc-epub 部署工具 v2"
echo "  Termux + OpenCC + Kindle 简体转换"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 必须在 Termux 中运行
if [ -z "$PREFIX" ] || [ ! -d "$PREFIX" ]; then
    warn "未检测到 Termux 环境 (\$PREFIX 为空)。"
    warn "请在 Termux App 中运行本脚本。"
    echo "    下载: F-Droid 2.0-rc1 → Termux 0.118.3"
    exit 1
fi
ok "检测到 Termux: $PREFIX"

# [1/5] 换清华镜像源（避免 pkg 卡顿，需求：国内网络）
info "[1/5] 切换清华镜像源（国内加速）..."
if command -v termux-change-repo >/dev/null 2>&1; then
    # 非交互方式写入源配置（Tsinghua）
    mkdir -p "$PREFIX/etc/apt/sources.list.d" 2>/dev/null || true
    cat > "$PREFIX/etc/apt/sources.list" <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-main stable main
EOF
    ok "已切换清华源"
else
    warn "未找到 termux-change-repo，跳过换源（可手动执行 termux-change-repo）"
fi

# [2/5] 更新 + 授予存储权限
info "[2/5] 更新软件包列表..."
pkg update -y

info "申请存储权限（访问手机 Download 目录）..."
termux-setup-storage 2>/dev/null || true
sleep 2

# [3/5] 安装系统依赖（OpenCC 正确包名: libopencc + opencc-tools）
info "[3/5] 安装系统依赖 (python, git, zip, unzip, libopencc, opencc-tools)..."
pkg install -y python git zip unzip libopencc opencc-tools

# 验证 opencc
if command -v opencc >/dev/null 2>&1; then
    ok "opencc 命令可用: $(opencc --version 2>&1 | head -1)"
else
    warn "opencc 未出现在 PATH，尝试重装: pkg reinstall opencc-tools"
fi

# [4/5] 安装 Python 库（走清华 PyPI 镜像）
info "[4/5] 安装 Python 库 (beautifulsoup4)..."
pip install --index-url https://pypi.tuna.tsinghua.edu.cn/simple beautifulsoup4

# [5/5] 配置 cc 快捷命令（PATH + alias + wrapper 三保险）
info "[5/5] 配置 cc 快捷命令..."
mkdir -p "$HOME/bin"

# 写入 PATH（幂等）
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -qF 'export PATH="$HOME/bin:$PATH"' "$rc" 2>/dev/null || \
        echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
    grep -qF "alias cc=" "$rc" 2>/dev/null || \
        echo "alias cc='python \$HOME/cc-epub/cc.py'" >> "$rc"
done
export PATH="$HOME/bin:$PATH"

# wrapper script（优先级最高，覆盖 clang 的 cc）
cat > "$HOME/bin/cc" <<'WRAPPER_EOF'
#!/bin/bash
exec python "$HOME/cc-epub/cc.py" "$@"
WRAPPER_EOF
chmod +x "$HOME/bin/cc"

# 验证
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "部署完成！"
echo ""
echo "  验证命令:"
echo "    type cc              # 应显示 ~/bin/cc"
echo "    cc --version         # 显示版本号"
echo "    opencc --version     # 显示 OpenCC 版本"
echo ""
echo "  使用方法:"
echo "    cc 书名.epub                    # 单本转换"
echo "    cc ~/Download/ --batch          # 批量转换目录"
echo "    cc 书名.epub --dry-run          # 仅检测排版方向"
echo ""
echo "  输出位置:"
echo "    ~/storage/shared/Download/E-book/书名-简中.epub"
echo ""
warn "若提示 'command not found: cc'，请重启 Termux 或执行: source ~/.bashrc"
warn "保持后台运行: termux-wake-lock（避免息屏被杀进程）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
