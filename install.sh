#!/usr/bin/env bash
# ============================================================
# CC-EPUB 一键部署脚本 v6.0
#
# 用法:
#   bash <(curl -fsSL <URL>)            # 一键安装
#   bash install.sh [选项]
#
# 选项:
#   --force          强制覆盖已安装的文件
#   --local          使用本地 cc-epub.sh 文件（不下载）
#   --uninstall      完全卸载
#   --update         更新到最新版本
#   --check-update   检查更新
#   --cleanup        清理旧备份和临时文件
#   --config         显示当前配置
#   --report         系统诊断报告
#   --mirror <源>    切换镜像源 (github/gitlab)
#   --auto-accept    自动确认所有提示
#   --dry-install    模拟安装，不实际修改
#   --help           显示帮助
# ============================================================

set -euo pipefail

# ---- 版本信息 ----
VERSION="6.0"
REPO_USER="epubcc"
REPO_NAME="cc-epub"
BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/cc-epub.sh"
BACKUP_URL="https://gitlab.com/${REPO_USER}/${REPO_NAME}/-/raw/main/cc-epub.sh"
README_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/README.md"
INSTALL_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/install.sh"
SHA256_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/SHA256SUMS"

# ---- 路径常量 ----
PREFIX_BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
TARGET_SCRIPT="$PREFIX_BIN/cc-epub.sh"
TARGET_LINK="$PREFIX_BIN/cc-epub"
CONFIG_DIR="$HOME/.cc-epub"
LIB_DIR="$CONFIG_DIR/lib"
README_DEST="$CONFIG_DIR/README.md"
MIRROR_LIST="$PREFIX/etc/apt/sources.list.d/mirrors-tuna.list"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="$CONFIG_DIR/install.log"

# ---- 颜色 ----
if [ -t 1 ] && [ "${NO_COLOR:-0}" != "1" ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC} $*" >&2; }
step()    { echo -e "\n${CYAN}${BOLD}==>${NC} $*"; }
sep()     { echo -e "${CYAN}──────────────────────────────────────────────${NC}"; }

# ---- 日志 ----
log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || return 0
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
}

# ---- 确认 ----
confirm() {
    [ "${AUTO_ACCEPT:-0}" -eq 1 ] && return 0
    echo -ne "${YELLOW}[确认]${NC} $* [Y/n]: "
    read -r resp
    case "$resp" in
        [Yy]*|yes|YES|Yes|"") return 0 ;;
        *) return 1 ;;
    esac
}

# ---- 参数解析 ----
FORCE=0; LOCAL=0; UNINSTALL=0; UPDATE=0; CHECK_UPDATE=0; CLEANUP=0
SHOW_CONFIG=0; SHOW_REPORT=0; MIRROR_SOURCE=""; AUTO_ACCEPT=0; DRY_INSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --local) LOCAL=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --update) UPDATE=1; shift ;;
        --check-update) CHECK_UPDATE=1; shift ;;
        --cleanup) CLEANUP=1; shift ;;
        --config) SHOW_CONFIG=1; shift ;;
        --report) SHOW_REPORT=1; shift ;;
        --mirror)
            [ $# -ge 2 ] || { error "--mirror 需要参数"; exit 1; }
            MIRROR_SOURCE="$2"; shift 2 ;;
        --auto-accept) AUTO_ACCEPT=1; shift ;;
        --dry-install) DRY_INSTALL=1; shift ;;
        --help|-h)
            sed -n '3,30p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) warn "未知参数: $1"; shift ;;
    esac
done

# ---- Dry Install 模式 ----
if [ "$DRY_INSTALL" -eq 1 ]; then
    step "模拟安装模式（不实际修改任何文件）"
    info "目标脚本: $TARGET_SCRIPT"
    info "命令链接: $TARGET_LINK"
    info "配置目录: $CONFIG_DIR"
    info "镜像源:   $MIRROR_LIST"
    info "输出目录: ${HOME}/storage/downloads/E-book"
    info "依赖: unzip zip opencc python3 imagemagick git curl"
    success "模拟安装完成（未做任何修改）"
    exit 0
fi

# ============================================================
# --uninstall
# ============================================================
if [ "$UNINSTALL" -eq 1 ]; then
    step "正在卸载 CC-EPUB v${VERSION} ..."
    confirm "确认卸载 CC-EPUB？所有脚本和链接将被删除。" || { info "已取消卸载。"; exit 0; }

    rm -f "$TARGET_SCRIPT" 2>/dev/null && success "已删除 cc-epub.sh" || warn "cc-epub.sh 不存在"
    rm -f "$TARGET_LINK" 2>/dev/null && success "已删除 cc-epub 命令链接" || warn "cc-epub 链接不存在"
    rm -rf "$CONFIG_DIR" 2>/dev/null && success "已删除配置目录 ~/.cc-epub" || warn "配置目录不存在"
    rm -f "$MIRROR_LIST" 2>/dev/null && success "已删除镜像源配置文件" || warn "镜像源配置文件不存在"
    if [ -f "$PREFIX/etc/apt/sources.list.bak" ]; then
        cp "$PREFIX/etc/apt/sources.list.bak" "$PREFIX/etc/apt/sources.list" 2>/dev/null
        rm -f "$PREFIX/etc/apt/sources.list.bak"
        success "已恢复原始源配置"
    fi
    if [ -d "$HOME/storage/downloads/E-book/.backup" ]; then
        if confirm "是否同时删除转换备份目录 (E-book/.backup)？"; then
            rm -rf "$HOME/storage/downloads/E-book/.backup"
            success "已删除备份目录"
        else
            warn "保留备份目录"
        fi
    fi
    echo ""
    success "CC-EPUB 已完全卸载"
    exit 0
fi

# ============================================================
# --check-update
# ============================================================
if [ "$CHECK_UPDATE" -eq 1 ]; then
    step "正在检查更新..."
    local CURRENT_VERSION="未知（未安装）"
    if [ -f "$TARGET_SCRIPT" ]; then
        CURRENT_VERSION=$(grep -E '^VERSION=' "$TARGET_SCRIPT" 2>/dev/null | head -1 | cut -d'"' -f2 || echo "unknown")
    fi
    info "当前安装版本: $CURRENT_VERSION"

    REMOTE_VERSION=""
    if curl -fsSL --connect-timeout 10 --max-time 30 -o /tmp/cc-epub-version "$INSTALL_URL" 2>/dev/null; then
        REMOTE_VERSION=$(grep -E '^VERSION=' /tmp/cc-epub-version 2>/dev/null | head -1 | cut -d'"' -f2 || echo "unknown")
        rm -f /tmp/cc-epub-version
    else
        warn "无法连接到远程仓库检查更新"
        exit 1
    fi

    if [ "$CURRENT_VERSION" = "$REMOTE_VERSION" ]; then
        success "当前版本 ($CURRENT_VERSION) 已是最新"
    else
        warn "发现新版本: $CURRENT_VERSION -> $REMOTE_VERSION"
        info "运行 'bash install.sh --update' 进行更新"
    fi
    exit 0
fi

# ============================================================
# --cleanup
# ============================================================
if [ "$CLEANUP" -eq 1 ]; then
    step "正在清理 CC-EPUB 旧文件和临时文件 ..."
    CLEANED=0

    if [ -d "$HOME/.cc-epub-tmp" ]; then
        local TMP_COUNT
        TMP_COUNT=$(find "$HOME/.cc-epub-tmp" -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [ "$TMP_COUNT" -gt 0 ] && confirm "清理 $TMP_COUNT 个临时目录？"; then
            rm -rf "$HOME/.cc-epub-tmp"
            success "已清理临时目录"; CLEANED=$((CLEANED + 1))
        fi
    fi

    BACKUP_DIR="$HOME/storage/downloads/E-book/.backup"
    if [ -d "$BACKUP_DIR" ]; then
        local OLD_COUNT
        OLD_COUNT=$(find "$BACKUP_DIR" -type f -mtime +7 2>/dev/null | wc -l)
        if [ "$OLD_COUNT" -gt 0 ] && confirm "清理 $OLD_COUNT 个超过7天的备份文件？"; then
            find "$BACKUP_DIR" -type f -mtime +7 -delete 2>/dev/null
            success "已清理旧备份文件"; CLEANED=$((CLEANED + 1))
        fi
    else
        success "备份目录不存在"
    fi

    [ -f "$LOG_FILE" ] && confirm "清理安装日志 ($LOG_FILE)？" && { rm -f "$LOG_FILE"; success "已清理安装日志"; CLEANED=$((CLEANED + 1)); }

    [ "$CLEANED" -eq 0 ] && info "没有需要清理的文件" || success "清理完成，共清理 $CLEANED 项"
    exit 0
fi

# ============================================================
# --config
# ============================================================
if [ "$SHOW_CONFIG" -eq 1 ]; then
    step "CC-EPUB 配置信息"
    sep
    info "版本: $VERSION"
    info "仓库: ${REPO_USER}/${REPO_NAME} (分支: ${BRANCH})"
    info "脚本路径: $TARGET_SCRIPT"
    info "命令链接: $TARGET_LINK"
    info "配置目录: $CONFIG_DIR"
    info "库目录: $LIB_DIR"
    info "镜像源配置: $MIRROR_LIST"
    info "输出目录: ${HOME}/storage/downloads/E-book"
    info "备份目录: ${HOME}/storage/downloads/E-book/.backup"
    info "日志文件: $LOG_FILE"
    echo ""
    info "已安装依赖:"
    for cmd in opencc unzip zip python3 imagemagick git curl; do
        if command -v "$cmd" &>/dev/null; then
            local ver=""
            case "$cmd" in
                python3) ver=$(python3 --version 2>&1 | head -1) ;;
                opencc)  ver=$(opencc --version 2>&1 || echo "unknown") ;;
                git)     ver=$(git --version 2>&1 | head -1) ;;
                curl)    ver=$(curl --version 2>&1 | head -1) ;;
                *)       ver=$(pkg list-installed 2>/dev/null | grep " $cmd " | head -1 | awk '{print $2}' || echo "") ;;
            esac
            success "  $cmd: ${ver:-已安装}"
        else
            warn "  $cmd: 未安装"
        fi
    done
    echo ""
    info "PATH 配置:"
    if echo "$PATH" | grep -q "$PREFIX_BIN"; then
        success "  $PREFIX_BIN 已在 PATH 中"
    else
        warn "  $PREFIX_BIN 不在 PATH 中"
    fi
    exit 0
fi

# ============================================================
# --report
# ============================================================
if [ "$SHOW_REPORT" -eq 1 ]; then
    step "系统诊断报告"
    sep
    info "Termux 版本: $(termux-version 2>/dev/null || echo '未知')"
    info "Android API: $(termux-api-package 2>/dev/null || echo '未知')"
    info "处理器: $(uname -m 2>/dev/null || echo '未知')"
    info "内核: $(uname -r 2>/dev/null || echo '未知')"
    echo ""
    info "磁盘空间:"
    df -h "$HOME" 2>/dev/null | head -3
    echo ""
    info "OpenCC 配置:"
    opencc -l 2>/dev/null | head -10 || warn "  opencc 不可用"
    echo ""
    info "网络连通性:"
    if curl -fsSL --connect-timeout 5 -o /dev/null "https://www.google.com" 2>/dev/null; then
        success "  网络正常"
    else
        warn "  网络连接可能受限"
    fi
    exit 0
fi

# ============================================================
# --mirror
# ============================================================
if [ -n "$MIRROR_SOURCE" ]; then
    step "切换镜像源为: $MIRROR_SOURCE"
    case "$MIRROR_SOURCE" in
        github)
            SCRIPT_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/cc-epub.sh"
            BACKUP_URL="https://gitlab.com/${REPO_USER}/${REPO_NAME}/-/raw/main/cc-epub.sh"
            ;;
        gitlab)
            SCRIPT_URL="https://gitlab.com/${REPO_USER}/${REPO_NAME}/-/raw/main/cc-epub.sh"
            BACKUP_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/cc-epub.sh"
            ;;
        *) error "不支持的镜像源: $MIRROR_SOURCE (可选: github, gitlab)"; exit 1 ;;
    esac
    success "镜像源已切换"
    info "后续下载将使用: $SCRIPT_URL"
    exit 0
fi

# ---- 记录安装日志 ----
mkdir -p "$(dirname "$LOG_FILE")"
log "=== CC-EPUB v${VERSION} 安装开始 ==="

# ============================================================
# 主安装流程
# ============================================================

# ---- 0. 存储权限 ----
step "正在请求存储权限（请在弹窗中点击\"允许\"）..."
if ! termux-setup-storage 2>/dev/null; then
    warn "termux-setup-storage 执行失败，请手动运行: termux-setup-storage"
fi

# ---- 1. 镜像源 ----
step "正在配置清华大学镜像源..."
mkdir -p "$PREFIX/etc/apt/sources.list.d"
if [ -f "$PREFIX/etc/apt/sources.list" ] && [ ! -f "$PREFIX/etc/apt/sources.list.bak" ]; then
    cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.bak" 2>/dev/null || true
    success "已备份原始源配置"
fi
if [ -f "$MIRROR_LIST" ] && grep -q "mirrors.tuna.tsinghua.edu.cn" "$MIRROR_LIST" 2>/dev/null; then
    success "清华镜像源已配置，跳过"
else
    cat > "$MIRROR_LIST" <<'MIRROREOF'
deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main
MIRROREOF
    success "镜像源已切换为清华 TUNA"
fi
if [ "$FORCE" -eq 1 ] || [ ! -s "$PREFIX/etc/apt/sources.list" ]; then
    > "$PREFIX/etc/apt/sources.list"
fi

# ---- 2. 依赖 ----
step "正在更新包列表并安装依赖..."
pkg update -y
pkg upgrade -y

DEPS="unzip zip opencc python3 imagemagick git curl"
for dep in $DEPS; do
    if command -v "$dep" &>/dev/null; then
        success "$dep 已安装"
    else
        info "正在安装 $dep ..."
        pkg install -y "$dep"
    fi
done

# ---- 3. 下载主脚本 + 库 ----
step "正在部署 CC-EPUB v${VERSION} ..."
mkdir -p "$CONFIG_DIR" "$LIB_DIR"

deploy_file() {
    local src="$1" dst="$2"
    if [ "$LOCAL" -eq 1 ]; then
        cp "$src" "$dst" && success "已部署: $(basename "$dst")" || { error "未找到本地文件: $src"; exit 1; }
    else
        # 尝试主源 + 备用源
        if curl -fsSL --connect-timeout 10 --max-time 60 -o "$dst" "$src" 2>/dev/null; then
            success "下载完成: $(basename "$dst")"
        else
            warn "主源下载失败，尝试备用源..."
            if curl -fsSL --connect-timeout 10 --max-time 60 -o "$dst" "$BACKUP_URL" 2>/dev/null; then
                success "备用源下载完成: $(basename "$dst")"
            else
                error "无法下载 $(basename "$dst")，请检查网络"
                exit 1
            fi
        fi
    fi
}

# 本地模式：从脚本同目录复制
if [ "$LOCAL" -eq 1 ]; then
    SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    deploy_file "$SRC_DIR/cc-epub.sh" "$TARGET_SCRIPT"
    mkdir -p "$LIB_DIR"
    for lib in common.sh args.sh convert.sh; do
        deploy_file "$SRC_DIR/lib/$lib" "$LIB_DIR/$lib"
    done
else
    deploy_file "$SCRIPT_URL" "$TARGET_SCRIPT"
    # 库文件从同一仓库下载
    local BASE_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}"
    mkdir -p "$LIB_DIR"
    for lib in common.sh args.sh convert.sh; do
        deploy_file "${BASE_URL}/lib/${lib}" "$LIB_DIR/$lib"
    done
fi

# SHA256 校验
if command -v sha256sum &>/dev/null && [ "$LOCAL" -eq 0 ]; then
    info "正在验证脚本完整性..."
    if curl -fsSL --connect-timeout 10 --max-time 15 -o /tmp/cc-epub-sha "$SHA256_URL" 2>/dev/null; then
        local REMOTE_SHA LOCAL_SHA
        REMOTE_SHA=$(grep "cc-epub.sh$" /tmp/cc-epub-sha 2>/dev/null | awk '{print $1}' || echo "")
        if [ -n "$REMOTE_SHA" ]; then
            LOCAL_SHA=$(sha256sum "$TARGET_SCRIPT" | awk '{print $1}')
            if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
                success "SHA256 校验通过"
            else
                warn "SHA256 校验不匹配！"
                warn "远程: $REMOTE_SHA"
                warn "本地: $LOCAL_SHA"
                confirm "是否继续安装？（建议取消并检查）" || { rm -f "$TARGET_SCRIPT"; exit 1; }
            fi
        fi
        rm -f /tmp/cc-epub-sha
    else
        warn "无法获取远程 SHA256，跳过完整性校验"
    fi
fi

chmod +x "$TARGET_SCRIPT" "$LIB_DIR"/*.sh 2>/dev/null || true

# ---- 4. README ----
step "正在部署 README.md ..."
if [ "$LOCAL" -eq 1 ]; then
    [ -f "$(dirname "${BASH_SOURCE[0]}")/README.md" ] && cp "$(dirname "${BASH_SOURCE[0]}")/README.md" "$README_DEST" || true
else
    curl -fsSL --connect-timeout 10 --max-time 30 "$README_URL" -o "$README_DEST" 2>/dev/null || warn "README.md 下载失败"
fi

# ---- 5. 全局命令 ----
if [ -L "$TARGET_LINK" ] || [ -f "$TARGET_LINK" ]; then
    if [ "$FORCE" -eq 1 ]; then
        rm -f "$TARGET_LINK"
    else
        warn "$TARGET_LINK 已存在，使用 --force 强制覆盖"
    fi
fi
ln -sf "$TARGET_SCRIPT" "$TARGET_LINK"
success "全局命令 cc-epub 已创建"

# ---- 6. PATH ----
step "正在验证 PATH 配置..."
if echo "$PATH" | grep -q "$PREFIX_BIN"; then
    success "PATH 配置正确"
else
    warn "PATH 中未包含 $PREFIX_BIN，尝试自动修复..."
    if ! grep -q "export PATH=.*$PREFIX_BIN" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo 'export PATH="$HOME/bin:$PREFIX/bin:$PATH"' >> ~/.bashrc
        success "已将 $PREFIX_BIN 添加到 .bashrc"
    fi
    info "请运行 source ~/.bashrc 使配置生效"
fi

# ---- 7. 验证安装 ----
step "正在验证安装..."
FAIL=0
for cmd in opencc unzip zip; do
    if command -v "$cmd" &>/dev/null; then
        success "$cmd 可用"
    else
        error "$cmd 未安装"; FAIL=1
    fi
done
if command -v cc-epub &>/dev/null; then
    success "cc-epub 命令可用"
else
    error "cc-epub 命令不可用，请检查 PATH 配置"; FAIL=1
fi
# 验证库文件
for lib in common.sh args.sh convert.sh; do
    if [ -f "$LIB_DIR/$lib" ]; then
        success "库文件 $lib 已部署"
    else
        error "库文件 $lib 缺失"; FAIL=1
    fi
done
# shellcheck 语法检查
if command -v shellcheck &>/dev/null; then
    shellcheck "$TARGET_SCRIPT" "$LIB_DIR"/*.sh 2>/dev/null && success "shellcheck 通过" || warn "shellcheck 发现问题"
fi
if [ "$FAIL" -eq 1 ]; then
    error "安装验证失败"
    exit 1
fi

log "=== 安装完成 ==="

# ---- 8. 使用说明 ----
cat <<EOF

==========================================================
  ${BOLD}CC-EPUB v${VERSION} 安装成功！${NC}
==========================================================

  使用方法:
    1. 将繁体 EPUB 文件放入手机的 Download 目录
    2. 在 Termux 中执行:
       cc-epub /sdcard/Download/你的书名.epub
    3. 转换后的文件保存在:
       Download/E-book/你的书名-cc.epub

  v6.0 新特性:
    --device <kindle|kobo|nook|generic>  多设备适配
    --dry-run --json                     机器可读报告
    --list-modes                         列出 OpenCC 模式
    --interactive                        交互式菜单
    --dry-install                        模拟安装

  批量处理:
    cc-epub --batch /sdcard/Download --parallel 4

  推送到 Kindle:
    前往 https://sendto.kindle.com 上传 -cc.epub 文件

  ${YELLOW}注意:${NC}
    - 源文件须为 DRM-Free
    - 单个文件建议小于 200MB
    - 确保源 EPUB 编码为 UTF-8

  管理命令:
    bash install.sh --check-update   检查更新
    bash install.sh --update         更新到最新版
    bash install.sh --cleanup        清理旧文件
    bash install.sh --config         查看配置
    bash install.sh --report         系统诊断
    bash install.sh --uninstall      完全卸载

==========================================================
EOF
