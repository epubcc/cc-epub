#!/usr/bin/env bash
# ============================================================
# CC-EPUB —— 港台繁体 EPUB 转简体横排 (Kindle/多设备优化) v6.0
#
# 用法:
#   cc-epub <输入.epub> [选项]
#   cc-epub --batch <目录> [选项]
#   cc-epub --interactive
#
# 选项详见: cc-epub --help
# ============================================================

set -euo pipefail

# ---- 定位脚本与库目录 ----
CCEPUB_BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -d "$CCEPUB_BIN_DIR/lib" ]; then
    CCEPUB_LIB_DIR="$CCEPUB_BIN_DIR/lib"
else
    # 安装后位于 $PREFIX/bin，lib 在 $CONFIG_DIR
    CCEPUB_LIB_DIR="${HOME}/.cc-epub/lib"
fi

# ---- 加载库 ----
# shellcheck source=lib/common.sh
source "$CCEPUB_LIB_DIR/common.sh"
# shellcheck source=lib/args.sh
source "$CCEPUB_LIB_DIR/args.sh"
# shellcheck source=lib/convert.sh
source "$CCEPUB_LIB_DIR/convert.sh"
# shellcheck source=lib/batch.sh
source "$CCEPUB_LIB_DIR/batch.sh"

# ---- 版本 ----
VERSION="$CCEPUB_VERSION"

# ---- 0. 参数解析 ----
CCEPUB_ARGS_parse "$@"

# ---- 日志重定向（必须在 parse 之后，因为 --log 已解析）----
if [ -n "$CFG_LOG_FILE" ]; then
    mkdir -p "$(dirname "$CFG_LOG_FILE")"
    exec 3>>"$CFG_LOG_FILE"
    LOG_FD=3
    # 重新导出日志函数使其写入文件
    info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*" >&"$LOG_FD"; [ "$QUIET" -eq 0 ] && printf "${BLUE}[INFO]${NC} %s\n" "$*" >&2; }
    success() { printf "${GREEN}[OK]${NC} %s\n" "$*" >&"$LOG_FD"; [ "$QUIET" -eq 0 ] && printf "${GREEN}[OK]${NC} %s\n" "$*" >&2; }
    warn()    { printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&"$LOG_FD"; printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&2; }
    error()   { printf "${RED}[ERR]${NC} %s\n" "$*" >&"$LOG_FD"; printf "${RED}[ERR]${NC} %s\n" "$*" >&2; }
fi

# ---- 列出模式 ----
if [ "$CFG_LIST_MODES" -eq 1 ]; then
    info "可用的 OpenCC 转换模式:"
    list_opencc_modes | while IFS= read -r m; do
        case "$m" in
            tw2s) echo "  tw2s  - 台湾繁体 → 简体（默认）" ;;
            hk2s) echo "  hk2s  - 香港繁体 → 简体" ;;
            t2s)  echo "  t2s   - 通用繁体 → 简体" ;;
            *)    echo "  $m" ;;
        esac
    done
    exit 0
fi

# ---- 交互式菜单 ----
if [ "$CFG_INTERACTIVE" -eq 1 ]; then
    if command -v CCEPUB_interactive_menu &>/dev/null; then
        CCEPUB_interactive_menu
    else
        error "交互式菜单需要完整安装（当前运行环境未加载 lib/batch.sh）"
        exit 1
    fi
    exit 0
fi

# ---- 1. 依赖检查 ----
# unzip / zip / python3 为硬依赖；opencc 允许「系统二进制」或「pip 模块」任一可用
require unzip zip python3
if ! detect_opencc_backend; then
    error "缺少 OpenCC：请安装其一"
    error "  Termux:  pkg install libopencc"
    error "  通用:    pip3 install opencc-python-reimplemented"
    exit 127
fi

# 验证 OpenCC 配置
if ! opencc_available "$CFG_MODE"; then
    error "OpenCC 转换配置 '${CFG_MODE}' 不可用，请检查安装"
    exit 3
fi

# ---- 2. 加载配置文件（命令行之后，可被子命令覆盖逻辑）----
if [ -n "$CFG_CONFIG_FILE" ]; then
    CCEPUB_ARGS_load_config "$CFG_CONFIG_FILE"
fi

# ---- 3. 恢复模式 ----
if [ -n "$CFG_RESTORE_FILE" ]; then
    step "正在从备份恢复: $CFG_RESTORE_FILE ..."
    mkdir -p "$CFG_OUTPUT_DIR"
    DEST="$CFG_OUTPUT_DIR/$(basename "$CFG_RESTORE_FILE" .backup)"
    cp "$CFG_RESTORE_FILE" "$DEST"
    success "恢复完成: $DEST"
    exit 0
fi

# ---- 4. 批量处理模式 ----
if [ -n "$CFG_BATCH_DIR" ]; then
    CCEPUB_batch_main
    exit 0
fi

# ---- 5. 单文件处理 ----
if [ ${#INPUT_FILES[@]} -eq 0 ]; then
    error "未指定输入文件"
    echo "用法: cc-epub <输入.epub> [选项]"
    echo "       cc-epub --interactive"
    exit 1
fi

INPUT_EPUB="${INPUT_FILES[0]}"

# 校验文件存在
if [ ! -f "$INPUT_EPUB" ]; then
    error "文件不存在: $INPUT_EPUB"
    exit 2
fi

# DRM 检查
if [ "$CFG_CHECK_DRM" -eq 1 ]; then
    step "正在检查 DRM 保护..."
    DRM_FOUND=0
    if unzip -l "$INPUT_EPUB" 2>/dev/null | grep -qi "encryption\|rights\|drmtype"; then
        DRM_FOUND=1
    fi
    if unzip -l "$INPUT_EPUB" 2>/dev/null | grep -q "META-INF/encryption\|META-INF/rights\|META-INF/drmtype"; then
        DRM_FOUND=1
    fi
    if [ "$DRM_FOUND" -eq 1 ]; then
        error "检测到 DRM 保护！本工具不支持转换受 DRM 保护的 EPUB 文件。"
        info "请使用 Calibre 等工具移除 DRM 后再转换。"
        exit 6
    else
        success "未检测到 DRM 保护，可以安全转换"
    fi
fi

# 执行转换
CCEPUB_convert "$INPUT_EPUB"

# 批量 / 交互式逻辑均已迁移至 lib/batch.sh 与 lib/convert.sh
# （此处不再重复定义，避免与库文件冲突）
