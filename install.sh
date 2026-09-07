#!/usr/bin/env bash
# cc-epub v2.6 一键安装 + 自动更新脚本
# 用法: bash install.sh
#   - 首次: 换源 / 装依赖 / 设 cc 别名 / 跑自检
#   - 之后每次运行: 自动 git pull 检查更新，有新版本则拉取并重启

set -e

# ---------- 颜色 ----------
if [ -t 1 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi
info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()   { echo -e "${RED}[ERR]${NC}  $*"; }

# Python 解释器（提前定义，供版本读取使用）
PYTHON_BIN="${PYTHON_BIN:-python3}"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || PYTHON_BIN="python"

# 版本：从 cc_epub.py 的 __version__ 读取，保持单一来源
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="$("$PYTHON_BIN" -c "import re;print(re.search(r'__version__\s*=\s*[\"\\x27]([^\"\\x27]+)',open('$SCRIPT_DIR/cc_epub.py',encoding='utf-8').read()).group(1))" 2>/dev/null || echo "2.4")"
cd "$SCRIPT_DIR"

# ============================================================
# 步骤 0: 自动更新检查（核心功能）
# ============================================================
check_for_updates() {
    # 已更新并重启的情况下，跳过二次检查
    if [ "$CC_EPUB_UPDATED" = "1" ]; then
        return 0
    fi
    # 仅在 git 仓库 + 有 origin + 联网时检查
    if [ ! -d .git ] || ! git remote get-url origin >/dev/null 2>&1; then
        return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        return 0
    fi

    info "正在检查更新 (当前 v${VERSION})..."
    git fetch --quiet origin 2>/dev/null || {
        warn "无法访问远程仓库，跳过更新检查（离线或网络受限）"
        return 0
    }

    # 比较本地与远程 main/master
    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse "origin/${branch}" 2>/dev/null)

    if [ -z "$remote_commit" ] || [ "$local_commit" = "$remote_commit" ]; then
        ok "已是最新版本 (v${VERSION})"
        return 0
    fi

    warn "发现新版本，正在更新..."
    echo "    本地: $local_commit"
    echo "    远程: $remote_commit"
    git pull --ff-only origin "$branch" 2>&1 | sed 's/^/    /'

    if [ -f "$SCRIPT_DIR/install.sh" ]; then
        ok "更新完成，重启安装脚本以应用新版本"
        # 标记已更新，重启后跳过更新检查（避免重复 pull）
        export CC_EPUB_UPDATED=1
        exec bash "$SCRIPT_DIR/install.sh" "$@"
    fi
}

check_for_updates "$@"

echo ""
echo "=============================================="
echo "  cc-epub 一键安装脚本  v${VERSION}"
echo "=============================================="
echo ""

# ============================================================
# 步骤 1: 包管理器探测（Termux / Debian/Ubuntu / macOS）
# ============================================================
info "[1/7] 检测运行环境..."
PKG=""
if command -v pkg >/dev/null 2>&1 && [ -n "$PREFIX" ] && echo "$PREFIX" | grep -qi termux; then
    PKG="termux"
    ok "检测到 Termux 环境 (PREFIX=$PREFIX)"
elif command -v apt-get >/dev/null 2>&1; then
    PKG="apt"
    ok "检测到 Debian/Ubuntu 环境"
elif command -v brew >/dev/null 2>&1; then
    PKG="brew"
    ok "检测到 macOS 环境"
else
    warn "未识别的 Linux 发行版，将尝试通用 pip 安装"
fi

# ============================================================
# 步骤 2: 换清华源（仅 Termux，交互式，自动选中国镜像）
# ============================================================
info "[2/7] 配置软件源..."
if [ "$PKG" = "termux" ]; then
    if [ -f "$PREFIX/etc/apt/sources.list" ]; then
        ok "Termux 软件源已配置（如需切换清华源，请手动运行: termux-change-repo）"
    fi
    pkg update -y 2>&1 | tail -3 | sed 's/^/    /' || true
fi

# ============================================================
# 步骤 3: 安装系统依赖
# ============================================================
info "[3/7] 安装系统依赖 (python, git, unzip, libopencc, opencc-tools)..."

# ⚠️ Termux 官方仓库的包名是「libopencc」(最新 1.4.2)，不是「opencc」
#   - libopencc      : 核心库 (含字典数据 /usr/share/opencc)
#   - opencc-tools   : 命令行工具 `opencc` (可选，cc-epub 主要用 Python 绑定)
#   Debian/Ubuntu 用 libopencc-dev，Fedora 用 opencc，Arch 用 opencc
# 🛡️ 防御性处理：Termux 下若出现裸包名「opencc」，自动改写为「libopencc」，
#    从根本上杜绝 `pkg install opencc` → "Unable to locate package opencc"。
fix_termux_pkg_names() {
    local out= pkg
    for pkg in "$@"; do
        if [ "$PKG" = "termux" ] && [ "$pkg" = "opencc" ]; then
            warn "Termux 无『opencc』包，自动改用『libopencc』(最新 1.4.2)"
            out="$out libopencc"
        else
            out="$out $pkg"
        fi
    done
    echo "${out# }"
}

install_pkg() {
    case "$PKG" in
        termux) set -- $(fix_termux_pkg_names "$@")
                pkg install -y "$@" 2>&1 | tail -5 | sed 's/^/    /' ;;
        apt)    sudo apt-get install -y "$@" 2>&1 | tail -5 | sed 's/^/    /' ;;
        brew)   brew install "$@" 2>&1 | tail -5 | sed 's/^/    /' ;;
        *)      warn "请手动安装: $*" ;;
    esac
}

case "$PKG" in
    termux) install_pkg python git unzip libopencc opencc-tools || true ;;
    apt)    install_pkg python3 git unzip libopencc-dev opencc opencc-data || true ;;
    brew)   install_pkg python git unzip opencc || true ;;
    *)      install_pkg python git unzip ;;
esac

# ============================================================
# 步骤 4: 安装/验证 opencc（降级兜底，解决 Unable to locate package opencc）
# ============================================================
info "[4/7] 验证 opencc 转换引擎..."
PYTHON_BIN="${PYTHON_BIN:-python3}"
command -v "$PYTHON_BIN" >/dev/null 2>&1 || PYTHON_BIN="python"

if ! command -v opencc >/dev/null 2>&1 && ! "$PYTHON_BIN" -c "import opencc" >/dev/null 2>&1; then
    warn "系统 opencc 不可用，自动降级安装 Python 绑定 (opencc-python-reimplemented)"
    info "pip install opencc-python-reimplemented..."
    "$PYTHON_BIN" -m pip install --upgrade pip 2>&1 | tail -2 | sed 's/^/    /' || true
    "$PYTHON_BIN" -m pip install opencc-python-reimplemented 2>&1 | tail -5 | sed 's/^/    /' || true
fi

# 验证
if "$PYTHON_BIN" -c "from opencc import OpenCC; assert '软件' in OpenCC('tw2sp').convert('軟體')" 2>/dev/null; then
    ok "OpenCC 转换引擎正常 (軟體→软件)"
else
    err "OpenCC 验证失败，请检查 Python 环境"
    "$PYTHON_BIN" -c "from opencc import OpenCC; print(OpenCC('tw2sp').convert('軟體'))"
fi

# ============================================================
# 步骤 5: 配置存储与输出目录
# ============================================================
info "[5/7] 配置目录..."
OUT_DIR="$HOME/Download/E-book"
mkdir -p "$OUT_DIR"
ok "输出目录: $OUT_DIR"

# Termux 访问手机存储
if [ "$PKG" = "termux" ] && [ ! -d /storage/emulated/0 ]; then
    info "请求存储权限（termux-setup-storage）..."
    termux-setup-storage 2>/dev/null || true
fi

# ============================================================
# 步骤 6: 设置 'cc' 别名
# ============================================================
info "[6/7] 设置 'cc' 命令别名..."
SHELL_RC=""
for rc in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$rc" ] && { SHELL_RC="$rc"; break; }
done
[ -z "$SHELL_RC" ] && SHELL_RC="$HOME/.bashrc"

ALIAS_LINE="alias cc='$PYTHON_BIN $SCRIPT_DIR/cc_epub.py'"
if grep -q "cc_epub.py" "$SHELL_RC" 2>/dev/null; then
    ok "别名已存在于 $SHELL_RC"
else
    {
        echo ""
        echo "# cc-epub (港台繁体 EPUB → 简体)"
        echo "$ALIAS_LINE"
    } >> "$SHELL_RC"
    ok "已写入别名到 $SHELL_RC"
fi
ok "用法: cc 書名   （自动在 ~/Download 查找 .epub）"

# ============================================================
# 步骤 7: 运行自检
# ============================================================
info "[7/7] 运行自检..."
if [ -f verify_note.py ]; then
    "$PYTHON_BIN" verify_note.py 2>&1 | tail -20 | sed 's/^/    /' || true
elif [ -f run_tests.sh ]; then
    bash run_tests.sh 2>&1 | tail -15 | sed 's/^/    /' || true
fi

echo ""
echo "=============================================="
echo -e "  ${GREEN}🎉 cc-epub v${VERSION} 安装/更新完成！${NC}"
echo "=============================================="
echo ""
echo "  下一步:"
echo "    1) source ~/.bashrc   (或重开终端，让 cc 别名生效)"
echo "    2) cc 書名             (把港台繁体书放到 ~/Download/)"
echo "    3) 输出 → $OUT_DIR"
echo ""
echo "  升级: 直接再跑  bash install.sh  (自动 git pull 检查更新)"
echo ""
