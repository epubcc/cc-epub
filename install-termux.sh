#!/bin/bash
# ============================================================
#  cc-epub —— Termux 一键部署脚本
#  适用：OPPO Find X8s / 任意 Android 7.0+ 手机
#  用法：bash install-termux.sh
# ============================================================
set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${CYAN}==>${NC} $*"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------
# 0. 环境校验
# ------------------------------------------------------------
echo ""
echo "=============================================="
echo "  cc-epub  Termux 部署向导"
echo "=============================================="
echo ""

if [ -z "$PREFIX" ] || [ -z "$HOME" ]; then
    warn "看起来不在 Termux 环境中（$PREFIX 为空）"
    warn "本脚本专为 Termux 设计。若在普通 Linux/macOS 测试，请改用："
    echo "    python -m venv .venv && source .venv/bin/activate"
    echo "    pip install -r requirements.txt"
    echo ""
fi

# ------------------------------------------------------------
# 1. 换国内镜像源（关键！官方源在国内慢/不稳定）
# ------------------------------------------------------------
log "[1/8] 配置软件源..."
if [ -n "$PREFIX" ] && command -v termux-change-repo >/dev/null 2>&1; then
    # 尝试使用 termux-change-repo（Termux 官方推荐方式）
    mkdir -p "$PREFIX/etc/apt"
    cat > "$PREFIX/etc/apt/sources.list" <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main
EOF
    # root 源（若有）
    if [ -f "$PREFIX/etc/apt/sources.list.d/root.list" ]; then
        cat > "$PREFIX/etc/apt/sources.list.d/root.list" <<'EOF'
deb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-root-packages-24 root stable
EOF
    fi
    ok "已切换清华 TUNA 镜像（国内加速）"
else
    warn "未检测到 termux-change-repo，跳过换源（自行确认源可用）"
fi

# ------------------------------------------------------------
# 2. 更新系统包
# ------------------------------------------------------------
log "[2/8] 更新 Termux 软件源..."
pkg update -y && pkg upgrade -y
ok "系统包已最新"

# ------------------------------------------------------------
# 3. 系统级依赖（pkg）
#    python    : 运行脚本
#    opencc    : OpenCC 命令行 + 词典数据（比 pip 编译快）
#    libopencc : opencc 的共享库
#    git       : 克隆仓库 / 后续更新
#    unzip zip : EPUB 本质是 ZIP，部分工具需要
#    clang     : 极少数 Python 包可能需要编译（备用）
# ------------------------------------------------------------
log "[3/8] 安装系统依赖（python / opencc / libopencc / git）..."
pkg install -y python opencc libopencc git unzip zip
ok "系统依赖安装完成"

# ------------------------------------------------------------
# 4. 授予存储权限
# ------------------------------------------------------------
log "[4/8] 授予存储权限（访问 /sdcard/Download）..."
if [ -n "$PREFIX" ] && command -v termux-setup-storage >/dev/null 2>&1; then
    termux-setup-storage || true
    sleep 2
    if [ -d "/sdcard/Download" ]; then
        ok "已可访问 /sdcard/Download"
    else
        warn "/sdcard/Download 暂不可见，请到系统弹窗中『允许』后重试本脚本"
    fi
else
    ok "非 Termux 环境，跳过存储授权（脚本会自动建输出目录）"
fi

# ------------------------------------------------------------
# 5. Python 依赖（pip）
#    requirements.txt 包含 opencc + chardet
#    其它全部用标准库（zipfile / re / os / shutil / argparse）
# ------------------------------------------------------------
log "[5/8] 安装 Python 依赖..."
pip install --upgrade pip
pip install -r "$SCRIPT_DIR/requirements.txt"
ok "Python 依赖安装完成"

# ------------------------------------------------------------
# 6. 创建命令别名 'cc'
# ------------------------------------------------------------
log "[6/8] 创建命令别名 'cc'..."
ALIAS_CMD="alias cc='python \"$SCRIPT_DIR/convert.py\"'"
add_alias() {
    local rc="$1"
    [ -f "$rc" ] || touch "$rc"
    if grep -q "cc-epub alias" "$rc" 2>/dev/null; then
        # 已存在则更新路径（防止移动目录后失效）
        # 兼容 GNU sed 和 BSD sed：先删旧行再追加
        if sed --version >/dev/null 2>&1; then
            # GNU sed
            sed -i "/cc-epub alias/d" "$rc"
        else
            # BSD sed（macOS）需要备份后缀
            sed -i '' "/cc-epub alias/d" "$rc" 2>/dev/null || true
        fi
    fi
    echo "# cc-epub alias" >> "$rc"
    echo "$ALIAS_CMD" >> "$rc"
}
add_alias "$HOME/.bashrc"
add_alias "$HOME/.zshrc" 2>/dev/null || true
ok "别名 'cc' 已写入 ~/.bashrc 与 ~/.zshrc"

# ------------------------------------------------------------
# 7. 自检
# ------------------------------------------------------------
log "[7/8] 运行自检..."
python "$SCRIPT_DIR/test_convert.py"

# ------------------------------------------------------------
# 8. 安装 chardet（可选，用于自动检测文件编码）
# ------------------------------------------------------------
log "[8/8] 安装 chardet（可选，提升编码兼容性）..."
pip install chardet 2>/dev/null || warn "chardet 安装失败（不影响基本功能）"
ok "chardet 安装完成（或已存在）"

echo ""
echo "=============================================="
ok "🎉 部署完成！"
echo ""
echo "用法（新终端生效，或先执行 source ~/.bashrc）："
echo "    cc /sdcard/Download/E-book/某书.epub"
echo "    → 输出：/sdcard/Download/E-book/某书-cc.epub"
echo ""
echo "常用选项："
echo "    cc 某书.epub --config tw2sp   # 台湾惯用词更彻底"
echo "    cc 某书.epub -o 自定义路径.epub"
echo "    cc 某书.epub --no-css          # 只转文字，不注入 CSS"
echo ""
echo "批量转换整个文件夹："
echo "    for f in /sdcard/Download/E-book/*.epub; do cc \"\$f\"; done"
echo ""
echo "推送到 Kindle：把 -cc.epub 上传到 Send to Kindle 网页版即可"
echo "  （单文件 ≤ 200MB；国行走 amazon.co.jp）"
echo "=============================================="
