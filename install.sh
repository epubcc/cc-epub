#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# CC-EPUB 一键部署脚本 v5.0
# 用法: bash <(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)
#        或: bash install.sh [--force] [--local] [--uninstall] [--update]
#              [--check-update] [--cleanup] [--config] [--report]
#              [--mirror <源>] [--auto-accept] [--dry-install]
# ============================================================

set -euo pipefail

# ---- 版本信息 ----
VERSION="5.0"
REPO_USER="epubcc"
REPO_NAME="cc-epub"
BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/cc-epub.sh"
BACKUP_URL="https://gitlab.com/${REPO_USER}/${REPO_NAME}/-/raw/main/cc-epub.sh"
README_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/README.md"
INSTALL_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/install.sh"
SHA256_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH}/SHA256SUMS"

# ---- 路径常量 ----
PREFIX_BIN="$PREFIX/bin"
TARGET_SCRIPT="$PREFIX_BIN/cc-epub.sh"
TARGET_LINK="$PREFIX_BIN/cc-epub"
CONFIG_DIR="$HOME/.cc-epub"
README_DEST="$CONFIG_DIR/README.md"
MIRROR_LIST="$PREFIX/etc/apt/sources.list.d/mirrors-tuna.list"
CONFIG_FILE="$CONFIG_DIR/config"
LOG_FILE="$CONFIG_DIR/install.log"

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
UNDERLINE='\033[4m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC} $*"; }
step()    { echo -e "\n${CYAN}${BOLD}==>${NC} $*"; }
bar()     { echo -e "${CYAN}  $*${NC}"; }
sep()     { echo -e "${CYAN}──────────────────────────────────────────────${NC}"; }

# ---- 参数解析 ----
FORCE=0
LOCAL=0
UNINSTALL=0
UPDATE=0
CHECK_UPDATE=0
CLEANUP=0
SHOW_CONFIG=0
SHOW_REPORT=0
MIRROR_SOURCE=""
AUTO_ACCEPT=0
DRY_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        --local) LOCAL=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --update) UPDATE=1 ;;
        --check-update) CHECK_UPDATE=1 ;;
        --cleanup) CLEANUP=1 ;;
        --config) SHOW_CONFIG=1 ;;
        --report) SHOW_REPORT=1 ;;
        --mirror)
            MIRROR_SOURCE="${2:-}"
            if [ -z "$MIRROR_SOURCE" ]; then
                error "请指定镜像源: github 或 gitlab"
                exit 1
            fi
            shift || true
            ;;
        --auto-accept) AUTO_ACCEPT=1 ;;
        --dry-install) DRY_INSTALL=1 ;;
        --help|-h)
            echo "CC-EPUB v${VERSION} 一键部署脚本"
            echo ""
            echo "用法: bash $0 [选项]"
            echo ""
            echo "安装选项:"
            echo "  --force          强制覆盖已安装的文件"
            echo "  --local          使用本地 cc-epub.sh 文件（不下载）"
            echo "  --auto-accept    自动确认所有提示（适合自动化脚本）"
            echo "  --dry-install    模拟安装，不实际修改任何文件"
            echo ""
            echo "管理选项:"
            echo "  --uninstall      卸载 CC-EPUB（删除脚本和链接）"
            echo "  --update         更新脚本到最新版本"
            echo "  --check-update   检查是否有可用更新"
            echo "  --cleanup        清理旧备份和临时文件"
            echo "  --config         显示当前配置信息"
            echo "  --report         显示系统诊断报告"
            echo "  --mirror <源>    手动指定镜像源 (github/gitlab)"
            echo "  --help           显示此帮助"
            exit 0
            ;;
        *) warn "未知参数: $arg" ;;
    esac
done

# ---- 日志函数（追加到日志文件） ----
log() {
    if [ -n "$LOG_FILE" ] && [ -d "$(dirname "$LOG_FILE")" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# ---- 确认函数 ----
confirm() {
    if [ "$AUTO_ACCEPT" -eq 1 ]; then
        return 0
    fi
    echo -ne "${YELLOW}[确认]${NC} $* [Y/n]: "
    read -r resp
    case "$resp" in
        [Yy]*|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================
# --uninstall 模式
# ============================================================
if [ "$UNINSTALL" -eq 1 ]; then
    step "正在卸载 CC-EPUB v${VERSION} ..."
    confirm "确认卸载 CC-EPUB？所有脚本和链接将被删除。" || { info "已取消卸载。"; exit 0; }

    rm -f "$TARGET_SCRIPT" 2>/dev/null && success "已删除 cc-epub.sh" || warn "cc-epub.sh 不存在"
    rm -f "$TARGET_LINK" 2>/dev/null && success "已删除 cc-epub 命令链接" || warn "cc-epub 链接不存在"
    rm -rf "$CONFIG_DIR" 2>/dev/null && success "已删除配置目录 ~/.cc-epub" || warn "配置目录不存在"
    rm -f "$MIRROR_LIST" 2>/dev/null && success "已删除镜像源配置文件" || warn "镜像源配置文件不存在"
    # 恢复备份的源配置
    if [ -f "$PREFIX/etc/apt/sources.list.bak" ]; then
        cp "$PREFIX/etc/apt/sources.list.bak" "$PREFIX/etc/apt/sources.list" 2>/dev/null
        rm -f "$PREFIX/etc/apt/sources.list.bak"
        success "已恢复原始源配置"
    fi
    # 清理 E-book 备份目录
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
    info "如需彻底清除，请手动删除 ~/storage/downloads/E-book/.backup 目录"
    exit 0
fi

# ============================================================
# --check-update 模式
# ============================================================
if [ "$CHECK_UPDATE" -eq 1 ]; then
    step "正在检查更新..."
    CURRENT_VERSION="未知（未安装）"
    if [ -f "$TARGET_SCRIPT" ]; then
        CURRENT_VERSION=$(grep '^VERSION=' "$TARGET_SCRIPT" 2>/dev/null | cut -d'"' -f2 || echo "unknown")
    fi
    info "当前安装版本: $CURRENT_VERSION"

    # 下载远程版本信息
    REMOTE_VERSION=""
    if curl -fsSL --connect-timeout 10 --max-time 30 -o /tmp/cc-epub-version "$INSTALL_URL" 2>/dev/null; then
        REMOTE_VERSION=$(grep '^VERSION=' /tmp/cc-epub-version 2>/dev/null | cut -d'"' -f2 || echo "unknown")
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
# --cleanup 模式
# ============================================================
if [ "$CLEANUP" -eq 1 ]; then
    step "正在清理 CC-EPUB 旧文件和临时文件 ..."
    CLEANED=0

    # 清理临时工作目录
    if [ -d "$HOME/.cc-epub-tmp" ]; then
        TMP_COUNT=$(find "$HOME/.cc-epub-tmp" -maxdepth 1 -type d 2>/dev/null | wc -l)
        if [ "$TMP_COUNT" -gt 0 ]; then
            if confirm "清理 $TMP_COUNT 个临时目录？"; then
                rm -rf "$HOME/.cc-epub-tmp"
                success "已清理临时目录"
                CLEANED=$((CLEANED + 1))
            fi
        fi
    fi

    # 清理旧备份（超过7天的）
    BACKUP_DIR="$HOME/storage/downloads/E-book/.backup"
    if [ -d "$BACKUP_DIR" ]; then
        OLD_COUNT=$(find "$BACKUP_DIR" -type f -mtime +7 2>/dev/null | wc -l)
        if [ "$OLD_COUNT" -gt 0 ]; then
            if confirm "清理 $OLD_COUNT 个超过7天的备份文件？"; then
                find "$BACKUP_DIR" -type f -mtime +7 -delete 2>/dev/null
                success "已清理旧备份文件"
                CLEANED=$((CLEANED + 1))
            fi
        else
            success "没有需要清理的旧备份文件"
        fi
    else
        success "备份目录不存在"
    fi

    # 清理旧日志
    if [ -f "$LOG_FILE" ]; then
        if confirm "清理安装日志 ($LOG_FILE)？"; then
            rm -f "$LOG_FILE"
            success "已清理安装日志"
            CLEANED=$((CLEANED + 1))
        fi
    fi

    if [ "$CLEANED" -eq 0 ]; then
        info "没有需要清理的文件"
    else
        success "清理完成，共清理 $CLEANED 项"
    fi
    exit 0
fi

# ============================================================
# --config 模式
# ============================================================
if [ "$SHOW_CONFIG" -eq 1 ]; then
    step "CC-EPUB 配置信息"
    sep
    info "版本: $VERSION"
    info "仓库: ${REPO_USER}/${REPO_NAME} (分支: ${BRANCH})"
    info "脚本路径: $TARGET_SCRIPT"
    info "命令链接: $TARGET_LINK"
    info "配置目录: $CONFIG_DIR"
    info "镜像源配置: $MIRROR_LIST"
    info "输出目录: ${HOME}/storage/downloads/E-book"
    info "备份目录: ${HOME}/storage/downloads/E-book/.backup"
    info "日志文件: $LOG_FILE"
    echo ""
    info "已安装依赖:"
    for cmd in opencc unzip zip python3 imagemagick git curl; do
        if command -v "$cmd" &>/dev/null; then
            ver=""
            case "$cmd" in
                python3) ver=$("$cmd" --version 2>&1 | head -1) ;;
                opencc)  ver=$(opencc --version 2>&1 || echo "unknown") ;;
                git)     ver=$(git --version 2>&1 | head -1) ;;
                curl)    ver=$(curl --version 2>&1 | head -1) ;;
                *)       ver=$(pkg list-installed 2>/dev/null | grep " $cmd " | head -1 | awk '{print $2}' || echo "") ;;
            esac
            if [ -n "$ver" ]; then
                success "  $cmd: $ver"
            else
                success "  $cmd: 已安装"
            fi
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
# --report 模式（系统诊断）
# ============================================================
if [ "$SHOW_REPORT" -eq 1 ]; then
    step "系统诊断报告"
    sep
    info "Termux 版本: $(termux-version 2>/dev/null || echo '未知')"
    info "Android API: $(termux-api-package 2>/dev/null || echo '未知')"
    info "处理器: $(uname -m 2>/dev/null || echo '未知')"
    info "内核: $(uname -r 2>/dev/null || echo '未知')"
    info "存储权限: $(termux-setup-storage --print 2>/dev/null || echo '未检查')"
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
# --mirror 切换镜像源
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
        *)
            error "不支持的镜像源: $MIRROR_SOURCE (可选: github, gitlab)"
            exit 1
            ;;
    esac
    success "镜像源已切换"
    info "后续下载将使用: $SCRIPT_URL"
    exit 0
fi

# ============================================================
# 主安装流程
# ============================================================

# ---- 0. 请求存储权限 ----
step "正在请求存储权限（请在弹窗中点击\"允许\"）..."
if ! termux-setup-storage 2>/dev/null; then
    warn "termux-setup-storage 执行失败，请手动运行: termux-setup-storage"
fi

# ---- 1. 更换清华 TUNA 镜像源 ----
step "正在配置清华大学镜像源..."
mkdir -p "$PREFIX/etc/apt/sources.list.d"

# 备份原有配置（仅首次）
if [ -f "$PREFIX/etc/apt/sources.list" ] && [ ! -f "$PREFIX/etc/apt/sources.list.bak" ]; then
    cp "$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.bak" 2>/dev/null || true
    success "已备份原始源配置"
fi

# 检查是否已配置清华源，避免重复写入
if [ -f "$MIRROR_LIST" ] && grep -q "mirrors.tuna.tsinghua.edu.cn" "$MIRROR_LIST" 2>/dev/null; then
    success "清华镜像源已配置，跳过"
else
    cat > "$MIRROR_LIST" <<'MIRROREOF'
deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main
MIRROREOF
    success "镜像源已切换为清华 TUNA"
fi

# 清空默认源列表，避免冲突
if [ "$FORCE" -eq 1 ] || [ ! -s "$PREFIX/etc/apt/sources.list" ]; then
    > "$PREFIX/etc/apt/sources.list"
fi

# ---- 2. 更新并安装依赖 ----
step "正在更新包列表并安装依赖..."
pkg update -y
pkg upgrade -y

DEPS="unzip zip opencc python3 imagemagick git curl"
for dep in $DEPS; do
    if command -v "$dep" &>/dev/null; then
        ver=""
        case "$dep" in
            python3) ver=$("$dep" --version 2>&1 | head -1) ;;
            opencc)  ver=$(opencc --version 2>&1 || echo "unknown") ;;
            git)     ver=$(git --version 2>&1 | head -1) ;;
            curl)    ver=$(curl --version 2>&1 | head -1) ;;
            *)       ver=$(pkg list-installed 2>/dev/null | grep " $dep " | head -1 | awk '{print $2}' || echo "") ;;
        esac
        if [ -n "$ver" ]; then
            success "$dep 已安装 ($ver)"
        else
            success "$dep 已安装"
        fi
    else
        info "正在安装 $dep ..."
        pkg install -y "$dep"
    fi
done

# ---- 3. 下载主脚本 ----
step "正在下载主转换脚本 cc-epub.sh ..."
mkdir -p "$CONFIG_DIR"

if [ "$LOCAL" -eq 1 ]; then
    if [ -f "./cc-epub.sh" ]; then
        cp "./cc-epub.sh" "$TARGET_SCRIPT"
        success "已从本地文件复制 cc-epub.sh"
    else
        error "未找到本地 cc-epub.sh 文件，请提供文件路径"
        exit 1
    fi
else
    # 在线下载，双源 fallback，带进度显示
    if curl -fsSL --connect-timeout 10 --max-time 30 -# "$SCRIPT_URL" -o "$TARGET_SCRIPT" 2>/dev/null; then
        success "主脚本下载成功（GitHub）"
    else
        warn "GitHub 下载失败，尝试备用源 (GitLab)..."
        if curl -fsSL --connect-timeout 10 --max-time 30 -# "$BACKUP_URL" -o "$TARGET_SCRIPT" 2>/dev/null; then
            success "主脚本下载成功（GitLab 备用源）"
        else
            error "无法从任何源下载主脚本，请检查网络连接后重试"
            exit 1
        fi
    fi

    # SHA256 校验（如果远程有校验文件）
    if command -v sha256sum &>/dev/null; then
        info "正在验证脚本完整性..."
        REMOTE_SHA=""
        if curl -fsSL --connect-timeout 10 --max-time 15 -o /tmp/cc-epub-sha "$SHA256_URL" 2>/dev/null; then
            REMOTE_SHA=$(grep "cc-epub.sh$" /tmp/cc-epub-sha 2>/dev/null | awk '{print $1}' || echo "")
            if [ -n "$REMOTE_SHA" ]; then
                LOCAL_SHA=$(sha256sum "$TARGET_SCRIPT" | awk '{print $1}')
                if [ "$REMOTE_SHA" = "$LOCAL_SHA" ]; then
                    success "SHA256 校验通过"
                else
                    warn "SHA256 校验不匹配！可能文件已被篡改"
                    warn "远程: $REMOTE_SHA"
                    warn "本地: $LOCAL_SHA"
                    if ! confirm "是否继续安装？（建议取消并检查）"; then
                        rm -f "$TARGET_SCRIPT"
                        exit 1
                    fi
                fi
            fi
            rm -f /tmp/cc-epub-sha
        else
            warn "无法获取远程 SHA256，跳过完整性校验"
        fi
    fi
fi

chmod +x "$TARGET_SCRIPT"

# ---- 4. 下载 README（可选） ----
step "正在下载 README.md ..."
if [ "$LOCAL" -eq 1 ];  then
    if [ -f "./README.md" ]; then
        cp "./README.md" "$README_DEST"
    fi
else
    curl -fsSL --connect-timeout 10 --max-time 30 "$README_URL" -o "$README_DEST" 2>/dev/null || warn "README.md 下载失败，可稍后手动获取"
fi

# ---- 5. 创建全局命令链接 ----
if [ -L "$TARGET_LINK" ] || [ -f "$TARGET_LINK" ]; then
    if [ "$FORCE" -eq 1 ]; then
        rm -f "$TARGET_LINK"
        info "已移除旧链接（--force）"
    else
        warn "$TARGET_LINK 已存在，使用 --force 强制覆盖"
    fi
fi
ln -sf "$TARGET_SCRIPT" "$TARGET_LINK"
success "全局命令 cc-epub 已创建"

# ---- 6. 验证 PATH 配置 ----
step "正在验证 PATH 配置..."
if echo "$PATH" | grep -q "$PREFIX_BIN"; then
    success "PATH 配置正确"
else
    warn "PATH 中未包含 $PREFIX_BIN，尝试自动修复..."
    if grep -q "export PATH=.*$PREFIX_BIN" ~/.bashrc 2>/dev/null; then
        info "PATH 配置已存在于 .bashrc"
    else
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
        error "$cmd 未安装"
        FAIL=1
    fi
done

if command -v "$TARGET_LINK" &>/dev/null || command -v cc-epub &>/dev/null; then
    success "cc-epub 命令可用"
else
    error "cc-epub 命令不可用，请检查 PATH 配置"
    FAIL=1
fi

if [ "$FAIL" -eq 1 ]; then
    error "安装验证失败，请检查上述错误信息"
    exit 1
fi

# ---- 8. 输出使用说明 ----
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

  批量处理（v5.0 新增）:
    cc-epub --batch /sdcard/Download
    cc-epub --batch /sdcard/Download --parallel 3

  可选参数:
    --mode <tw2s|hk2s|t2s>   转换模式（默认: tw2s）
    --no-indent              不添加首行缩进
    --keep-vertical          保留原始竖排格式
    --no-compress            不压缩图片
    --no-kindle-opt          不执行 Kindle 兼容性优化
    --dry-run                仅检查，不执行转换
    --verbose                详细输出模式
    --output <路径>          指定输出目录
    --batch <目录>           批量处理目录下所有 EPUB
    --parallel <N>           并行处理（N 个并发，v5.0 新增）
    --resume                 断点续转（v5.0 新增）
    --exclude <模式>         批量时排除匹配文件（v5.0 新增）
    --include <模式>         批量时仅处理匹配文件（v5.0 新增）
    --skip-existing          跳过已存在的输出文件（v5.0 新增）
    --encoding <编码>        指定输入编码（v5.0 新增）
    --stats                  显示转换统计（v5.0 新增）
    --quiet                  静默模式（v5.0 新增）
    --restore <备份文件>     从备份恢复原文件
    --check-drm              检查文件是否有 DRM 保护
    --log <文件>             保存转换日志到文件
    --toc                    重建目录

  推送到 Kindle:
    前往 https://sendto.kindle.com 上传 -cc.epub 文件

  ${YELLOW}注意:${NC}
    - 源文件须为 DRM-Free（无数字版权保护）
    - 单个文件建议小于 200MB
    - 确保源 EPUB 编码为 UTF-8

  管理命令:
    bash install.sh --check-update   检查更新
    bash install.sh --update         更新到最新版
    bash install.sh --cleanup        清理旧文件和临时文件
    bash install.sh --config         查看当前配置
    bash install.sh --report         系统诊断报告
    bash install.sh --uninstall      完全卸载

==========================================================
EOF
