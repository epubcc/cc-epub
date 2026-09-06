#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# CC-EPUB —— 港台繁体 EPUB 转简体横排 (Kindle 优化版) v5.0
# 用法: cc-epub <输入.epub> [选项]
# 选项:
#   --mode <tw2s|hk2s|t2s>   转换模式（默认: tw2s）
#   --no-indent              不添加首行缩进
#   --keep-vertical          保留原始竖排格式
#   --no-compress            不压缩图片
#   --no-kindle-opt          不执行 Kindle 兼容性优化
#   --dry-run                仅检查，不执行转换
#   --verbose                详细输出模式
#   --quiet                  静默模式（仅输出错误和结果）
#   --output <路径>          指定输出目录
#   --batch <目录>           批量处理目录下所有 EPUB
#   --parallel <N>           并行处理（N 个并发任务）
#   --resume                 断点续转（从上次中断处继续）
#   --exclude <模式>         批量时排除匹配文件
#   --include <模式>         批量时仅处理匹配文件
#   --skip-existing          跳过已存在的输出文件
#   --encoding <编码>        指定输入文件编码（默认: utf-8）
#   --stats                  显示转换统计信息
#   --timeout <秒>           单个文件处理超时（默认: 300）
#   --retry <次数>           失败重试次数（默认: 0）
#   --output-prefix <前缀>   自定义输出文件名前缀
#   --output-suffix <后缀>   自定义输出文件名后缀
#   --restore <备份文件>     从备份恢复原文件
#   --check-drm              检查文件是否有 DRM 保护
#   --log <文件>             保存转换日志到文件
#   --toc                    重建目录 (toc.ncx / nav.xhtml)
#   --config <文件>          加载预设配置文件
#   --help                   显示此帮助
# ============================================================

set -euo pipefail

# ---- 版本信息 ----
VERSION="5.0"

# ---- 颜色定义 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC} $*"; }
verbose() { [ "$VERBOSE" -eq 1 ] && echo -e "${CYAN}[DBG]${NC} $*" || true; }
quiet()   { [ "$QUIET" -eq 1 ] && return 0 || echo -e "${CYAN}[QUIET]${NC} $*"; }
step()    { echo -e "\n${CYAN}${BOLD}==>${NC} $*"; }
progress() {
    if [ "$QUIET" -eq 1 ] || [ "$BATCH_PROGRESS" -eq 0 ]; then
        return
    fi
    echo -ne "\r${CYAN}[${CURRENT_STEP}/${TOTAL_STEPS}] $*${NC}"
}

# ---- 0. 参数解析 ----
if [ -z "${1:-}" ]; then
    echo "用法: cc-epub <输入.epub> [选项]"
    echo "示例: cc-epub /sdcard/Download/三体.epub"
    echo "      cc-epub book.epub --mode hk2s --no-indent --verbose"
    echo "      cc-epub --batch /sdcard/Download --parallel 3"
    exit 1
fi

# 默认选项
MODE="tw2s"
ADD_INDENT=1
FORCE_HORIZONTAL=1
COMPRESS_IMAGES=1
KINDLE_OPT=1
DRY_RUN=0
VERBOSE=0
QUIET=0
OUTPUT_DIR="${HOME}/storage/downloads/E-book"
BATCH_DIR=""
PARALLEL_JOBS=1
RESUME=0
EXCLUDE_PATTERN=""
INCLUDE_PATTERN=""
SKIP_EXISTING=0
ENCODING="utf-8"
SHOW_STATS=0
TIMEOUT=300
RETRY_COUNT=0
OUTPUT_PREFIX=""
OUTPUT_SUFFIX="-cc"
RESTORE_FILE=""
CHECK_DRM=0
LOG_FILE=""
REBUILD_TOC=0
CONFIG_FILE=""
INPUT_EPUB=""
shift || true

# 收集所有输入文件（用于批量模式）
INPUT_FILES=()

for arg in "$@"; do
    case "$arg" in
        --mode)
            MODE="${2:-tw2s}"
            if [[ "$MODE" != "tw2s" && "$MODE" != "hk2s" && "$MODE" != "t2s" ]]; then
                error "不支持的转换模式: $MODE (可选: tw2s, hk2s, t2s)"
                exit 1
            fi
            shift || true
            ;;
        --no-indent) ADD_INDENT=0 ;;
        --keep-vertical) FORCE_HORIZONTAL=0 ;;
        --no-compress) COMPRESS_IMAGES=0 ;;
        --no-kindle-opt) KINDLE_OPT=0 ;;
        --dry-run) DRY_RUN=1 ;;
        --verbose) VERBOSE=1 ;;
        --quiet) QUIET=1 ;;
        --output)
            OUTPUT_DIR="${2:-$OUTPUT_DIR}"
            shift || true
            ;;
        --batch)
            BATCH_DIR="${2:-}"
            if [ -z "$BATCH_DIR" ] || [ ! -d "$BATCH_DIR" ]; then
                error "目录不存在: ${2:-}"
                exit 1
            fi
            shift || true
            ;;
        --parallel)
            PARALLEL_JOBS="${2:-1}"
            if ! [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ "$PARALLEL_JOBS" -lt 1 ]; then
                error "并行任务数必须为正整数"
                exit 1
            fi
            shift || true
            ;;
        --resume) RESUME=1 ;;
        --exclude)
            EXCLUDE_PATTERN="${2:-}"
            shift || true
            ;;
        --include)
            INCLUDE_PATTERN="${2:-}"
            shift || true
            ;;
        --skip-existing) SKIP_EXISTING=1 ;;
        --encoding)
            ENCODING="${2:-utf-8}"
            shift || true
            ;;
        --stats) SHOW_STATS=1 ;;
        --timeout)
            TIMEOUT="${2:-300}"
            if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
                error "超时时间必须为正整数（秒）"
                exit 1
            fi
            shift || true
            ;;
        --retry)
            RETRY_COUNT="${2:-0}"
            if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
                error "重试次数必须为非负整数"
                exit 1
            fi
            shift || true
            ;;
        --output-prefix)
            OUTPUT_PREFIX="${2:-}"
            shift || true
            ;;
        --output-suffix)
            OUTPUT_SUFFIX="${2:--cc}"
            shift || true
            ;;
        --restore)
            RESTORE_FILE="${2:-}"
            if [ -z "$RESTORE_FILE" ] || [ ! -f "$RESTORE_FILE" ]; then
                error "备份文件不存在: ${2:-}"
                exit 1
            fi
            shift || true
            ;;
        --check-drm) CHECK_DRM=1 ;;
        --log)
            LOG_FILE="${2:-}"
            mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
            shift || true
            ;;
        --toc) REBUILD_TOC=1 ;;
        --config)
            CONFIG_FILE="${2:-}"
            if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
                error "配置文件不存在: ${2:-}"
                exit 1
            fi
            shift || true
            ;;
        --help|-h)
            echo "CC-EPUB v${VERSION} - 港台繁体 EPUB 转简体横排"
            echo ""
            echo "用法: cc-epub <输入.epub> [选项]"
            echo ""
            echo "基本选项:"
            echo "  --mode <tw2s|hk2s|t2s>   转换模式（默认: tw2s）"
            echo "  --no-indent              不添加首行缩进"
            echo "  --keep-vertical          保留原始竖排格式"
            echo "  --no-compress            不压缩图片"
            echo "  --no-kindle-opt          不执行 Kindle 兼容性优化"
            echo "  --dry-run                仅检查，不执行转换"
            echo ""
            echo "输出选项（v5.0 新增）:"
            echo "  --quiet                  静默模式（仅输出错误和结果）"
            echo "  --output <路径>          指定输出目录"
            echo "  --output-prefix <前缀>   自定义输出文件名前缀"
            echo "  --output-suffix <后缀>   自定义输出文件名后缀（默认: -cc）"
            echo "  --stats                  显示转换统计信息"
            echo ""
            echo "批量处理选项（v5.0 新增）:"
            echo "  --batch <目录>           批量处理目录下所有 EPUB"
            echo "  --parallel <N>           并行处理（N 个并发任务）"
            echo "  --resume                 断点续转（从上次中断处继续）"
            echo "  --exclude <模式>         批量时排除匹配文件（如 '*.jpg'）"
            echo "  --include <模式>         批量时仅处理匹配文件（如 '小说*'）"
            echo "  --skip-existing          跳过已存在的输出文件"
            echo "  --timeout <秒>           单个文件处理超时（默认: 300）"
            echo "  --retry <次数>           失败重试次数（默认: 0）"
            echo ""
            echo "高级选项:"
            echo "  --verbose                详细输出模式"
            echo "  --encoding <编码>        指定输入文件编码（默认: utf-8）"
            echo "  --check-drm              检查文件是否有 DRM 保护"
            echo "  --log <文件>             保存转换日志到文件"
            echo "  --toc                    重建目录"
            echo "  --config <文件>          加载预设配置文件"
            echo "  --restore <备份文件>     从备份恢复原文件"
            echo "  --help                   显示此帮助"
            exit 0
            ;;
        *)
            INPUT_FILES+=("$arg")
            ;;
    esac
done

# ---- 加载配置文件 ----
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    step "加载配置文件: $CONFIG_FILE"
    # 逐行读取配置（格式: KEY=VALUE）
    while IFS='=' read -r key value; do
        # 跳过注释和空行
        [[ "$key" =~ ^#.*$ ]] && continue
        [ -z "$key" ] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        case "$key" in
            mode) MODE="$value" ;;
            add_indent) ADD_INDENT="$value" ;;
            force_horizontal) FORCE_HORIZONTAL="$value" ;;
            compress_images) COMPRESS_IMAGES="$value" ;;
            kindle_opt) KINDLE_OPT="$value" ;;
            encoding) ENCODING="$value" ;;
            timeout) TIMEOUT="$value" ;;
            retry) RETRY_COUNT="$value" ;;
            *) warn "未知配置项: $key" ;;
        esac
    done < "$CONFIG_FILE"
    info "配置文件已加载"
fi

# ---- 日志输出处理 ----
LOG_FD=""
if [ -n "$LOG_FILE" ]; then
    exec 3>="$LOG_FILE"
    LOG_FD="3"
    info "日志已保存到: $LOG_FILE"
    info()    { echo -e "${BLUE}[INFO]${NC} $*"; echo -e "${BLUE}[INFO]${NC} $*" >&3; }
    success() { echo -e "${GREEN}[OK]${NC} $*"; echo -e "${GREEN}[OK]${NC} $*" >&3; }
    warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; echo -e "${YELLOW}[WARN]${NC} $*" >&3; }
    error()   { echo -e "${RED}[ERR]${NC} $*"; echo -e "${RED}[ERR]${NC} $*" >&3; }
    verbose() { [ "$VERBOSE" -eq 1 ] && { echo -e "${CYAN}[DBG]${NC} $*"; echo -e "${CYAN}[DBG]${NC} $*" >&3; } || true; }
    step()    { echo -e "\n${CYAN}${BOLD}==>${NC} $*"; echo -e "\n${CYAN}${BOLD}==>${NC} $*" >&3; }
fi

# ---- 1. 依赖检查 ----
for cmd in opencc unzip zip python3; do
    command -v "$cmd" &>/dev/null || { error "未找到 $cmd，请先运行 install.sh"; exit 127; }
done

# 验证 OpenCC 配置
if ! opencc -c "${MODE}.json" -i /dev/null -o /dev/null 2>/dev/null; then
    if ! opencc -c "$MODE" -i /dev/null -o /dev/null 2>/dev/null; then
        error "OpenCC 转换配置 '${MODE}' 不可用，请检查安装"
        exit 3
    fi
fi

# ---- 2. 批量处理模式 ----
if [ -n "$BATCH_DIR" ]; then
    step "批量处理模式：扫描目录 $BATCH_DIR ..."

    # 收集文件（支持 --include / --exclude 过滤）
    BATCH_FILES=()
    while IFS= read -r -d '' f; do
        fname=$(basename "$f")
        # 应用 --exclude 过滤
        if [ -n "$EXCLUDE_PATTERN" ]; then
            if [[ "$fname" == $EXCLUDE_PATTERN ]]; then
                verbose "排除: $fname"
                continue
            fi
        fi
        # 应用 --include 过滤
        if [ -n "$INCLUDE_PATTERN" ]; then
            if [[ ! "$fname" == $INCLUDE_PATTERN ]]; then
                verbose "跳过（不匹配 include）: $fname"
                continue
            fi
        fi
        BATCH_FILES+=("$f")
    done < <(find "$BATCH_DIR" -maxdepth 1 -type f -name "*.epub" -print0 2>/dev/null)

    if [ ${#BATCH_FILES[@]} -eq 0 ]; then
        error "目录中未找到匹配的 .epub 文件: $BATCH_DIR"
        exit 1
    fi

    # 处理 --resume：跳过已完成的文件
    if [ "$RESUME" -eq 1 ]; then
        CHECKPOINT_FILE="$HOME/.cc-epub-tmp/.batch_checkpoint"
        if [ -f "$CHECKPOINT_FILE" ]; then
            info "找到断点续转文件，跳过已完成的文件..."
            RESUMED=0
            NEW_BATCH=()
            while IFS= read -r -d '' f; do
                if grep -qF "$(realpath "$f" 2>/dev/null || echo "$f")" "$CHECKPOINT_FILE" 2>/dev/null; then
                    RESUMED=$((RESUMED + 1))
                    verbose "跳过已完成: $(basename "$f")"
                else
                    NEW_BATCH+=("$f")
                fi
            done < <(printf '%s\0' "${BATCH_FILES[@]}")
            BATCH_FILES=("${NEW_BATCH[@]+"${NEW_BATCH[@]}"}")
            info "断点续转：跳过 $RESUMED 个已完成文件，剩余 ${#BATCH_FILES[@]} 个待处理"
        fi
    fi

    # 应用 --skip-existing
    if [ "$SKIP_EXISTING" -eq 1 ]; then
        NEW_BATCH=()
        for f in "${BATCH_FILES[@]+"${BATCH_FILES[@]}"}"; do
            fname=$(basename "$f")
            name="${fname%.*}"
            out_name="${OUTPUT_PREFIX}${name}${OUTPUT_SUFFIX}.epub"
            out_path="$OUTPUT_DIR/$out_name"
            if [ -f "$out_path" ]; then
                verbose "跳过已存在: $out_name"
                continue
            fi
            NEW_BATCH+=("$f")
        done
        BATCH_FILES=("${NEW_BATCH[@]+"${NEW_BATCH[@]}"}")
        info "跳过已存在的输出文件后，剩余 ${#BATCH_FILES[@]} 个待处理"
    fi

    TOTAL_STEPS=${#BATCH_FILES[@]}
    CURRENT_STEP=0
    BATCH_PROGRESS=1

    if [ "$TOTAL_STEPS" -eq 0 ]; then
        error "没有需要处理的文件"
        exit 1
    fi

    info "找到 ${TOTAL_STEPS} 个 EPUB 文件待处理"
    info "转换模式: $MODE | 并行: $PARALLEL_JOBS | 超时: ${TIMEOUT}s | 重试: $RETRY_COUNT"

    # ---- 并行处理 ----
    if [ "$PARALLEL_JOBS" -gt 1 ]; then
        step "并行处理模式：$PARALLEL_JOBS 个并发任务"
        # 使用临时目录存放子任务结果
        JOB_DIR="$HOME/.cc-epub-tmp/.batch_jobs_$$"
        shopt -u nullglob
        rm -rf "$JOB_DIR"
        mkdir -p "$JOB_DIR"

        PIDS=()
        for epub in "${BATCH_FILES[@]}"; do
            JOB_ID=$(basename "$epub" .epub)
            # 启动后台任务
            (
                cc-epub "$epub" \
                    --mode "$MODE" \
                    $([ "$ADD_INDENT" -eq 0 ] && echo "--no-indent") \
                    $([ "$FORCE_HORIZONTAL" -eq 0 ] && echo "--keep-vertical") \
                    $([ "$COMPRESS_IMAGES" -eq 0 ] && echo "--no-compress") \
                    $([ "$KINDLE_OPT" -eq 0 ] && echo "--no-kindle-opt") \
                    $([ "$DRY_RUN" -eq 1 ] && echo "--dry-run") \
                    $([ "$VERBOSE" -eq 1 ] && echo "--verbose") \
                    $([ "$QUIET" -eq 1 ] && echo "--quiet") \
                    --output "$OUTPUT_DIR" \
                    --timeout "$TIMEOUT" \
                    --retry "$RETRY_COUNT" \
                    --output-prefix "$OUTPUT_PREFIX" \
                    --output-suffix "$OUTPUT_SUFFIX" \
                    2>&1
                echo $? > "$JOB_DIR/${JOB_ID}.status"
            ) &
            PIDS+=($!)
            # 控制并发数
            if [ ${#PIDS[@]} -ge "$PARALLEL_JOBS" ]; then
                wait "${PIDS[0]}"
                PIDS=("${PIDS[@]:1}")
            fi
        done
        # 等待所有任务完成
        for pid in "${PIDS[@]+"${PIDS[@]}"}"; do
            wait "$pid" 2>/dev/null || true
        done

        # 统计结果
        BATCH_SUCCESS=0
        BATCH_FAILED=0
        shopt -s nullglob
        for status_file in "$JOB_DIR"/*.status; do
            if [ -f "$status_file" ]; then
                code=$(cat "$status_file")
                if [ "$code" -eq 0 ]; then
                    BATCH_SUCCESS=$((BATCH_SUCCESS + 1))
                else
                    BATCH_FAILED=$((BATCH_FAILED + 1))
                fi
            fi
        done
        rm -rf "$JOB_DIR"
    else
        # 串行处理
        BATCH_SUCCESS=0
        BATCH_FAILED=0
        BATCH_SKIPPED=0

        for epub in "${BATCH_FILES[@]}"; do
            CURRENT_STEP=$((CURRENT_STEP + 1))
            echo ""
            info "----------------------------------------------"
            info "[$CURRENT_STEP/$TOTAL_STEPS] 正在处理: $(basename "$epub")"

            # 重试逻辑
            ATTEMPT=0
            MAX_ATTEMPT=$((RETRY_COUNT + 1))
            SUCCESS=0
            while [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; do
                ATTEMPT=$((ATTEMPT + 1))
                if cc-epub "$epub" \
                    --mode "$MODE" \
                    $([ "$ADD_INDENT" -eq 0 ] && echo "--no-indent") \
                    $([ "$FORCE_HORIZONTAL" -eq 0 ] && echo "--keep-vertical") \
                    $([ "$COMPRESS_IMAGES" -eq 0 ] && echo "--no-compress") \
                    $([ "$KINDLE_OPT" -eq 0 ] && echo "--no-kindle-opt") \
                    $([ "$DRY_RUN" -eq 1 ] && echo "--dry-run") \
                    $([ "$VERBOSE" -eq 1 ] && echo "--verbose") \
                    $([ "$QUIET" -eq 1 ] && echo "--quiet") \
                    --output "$OUTPUT_DIR" \
                    --timeout "$TIMEOUT" \
                    --output-prefix "$OUTPUT_PREFIX" \
                    --output-suffix "$OUTPUT_SUFFIX" \
                    2>&1; then
                    SUCCESS=1
                    break
                else
                    if [ "$ATTEMPT" -lt "$MAX_ATTEMPT" ]; then
                        warn "处理失败，第 $ATTEMPT/$MAX_ATTEMPT 次重试..."
                    fi
                fi
            done

            if [ "$SUCCESS" -eq 1 ]; then
                BATCH_SUCCESS=$((BATCH_SUCCESS + 1))
            else
                BATCH_FAILED=$((BATCH_FAILED + 1))
                warn "处理失败（已重试 $RETRY_COUNT 次）: $(basename "$epub")"
            fi

            # 保存断点续转记录
            if [ "$RESUME" -eq 1 ]; then
                mkdir -p "$HOME/.cc-epub-tmp"
                echo "$(realpath "$epub" 2>/dev/null || echo "$epub")" >> "$HOME/.cc-epub-tmp/.batch_checkpoint"
            fi
        done
    fi

    # 清除断点续转文件（全部完成后）
    if [ "$RESUME" -eq 1 ] && [ "$BATCH_FAILED" -eq 0 ]; then
        rm -f "$HOME/.cc-epub-tmp/.batch_checkpoint"
        info "所有文件处理完成，已清除断点续转记录"
    fi

    echo ""
    step "批量处理完成！"
    info "成功: $BATCH_SUCCESS | 失败: $BATCH_FAILED | 总计: $TOTAL_STEPS"

    # 显示统计
    if [ "$SHOW_STATS" -eq 1 ]; then
        echo ""
        info "=== 批量处理统计 ==="
        info "总文件数: $TOTAL_STEPS"
        info "成功: $BATCH_SUCCESS"
        info "失败: $BATCH_FAILED"
        if [ "$TOTAL_STEPS" -gt 0 ]; then
            SUCCESS_RATE=$((BATCH_SUCCESS * 100 / TOTAL_STEPS))
            info "成功率: ${SUCCESS_RATE}%"
        fi
    fi
    exit 0
fi

# ---- 3. 恢复模式 ----
if [ -n "$RESTORE_FILE" ]; then
    step "正在从备份恢复: $RESTORE_FILE ..."
    if [ -f "$RESTORE_FILE" ]; then
        DEST="$OUTPUT_DIR/$(basename "$RESTORE_FILE")"
        cp "$RESTORE_FILE" "$DEST"
        success "恢复完成: $DEST"
        exit 0
    else
        error "备份文件不存在: $RESTORE_FILE"
        exit 2
    fi
fi

# ---- 4. 收集输入文件 ----
if [ ${#INPUT_FILES[@]} -gt 0 ]; then
    INPUT_EPUB="${INPUT_FILES[0]}"
else
    INPUT_EPUB="$1"
fi

# ---- 5. DRM 检查 ----
if [ "$CHECK_DRM" -eq 1 ]; then
    step "正在检查 DRM 保护..."
    DRM_FOUND=0
    # 检查常见的 DRM 标志
    if unzip -l "$INPUT_EPUB" 2>/dev/null | grep -qi "drm\|encrypted\|adobe\|kindle"; then
        DRM_FOUND=1
    fi
    if unzip -l "$INPUT_EPUB" 2>/dev/null | grep -q "META-INF/encryption\|META-INF/rights\|META-INF/drmtype"; then
        DRM_FOUND=1
    fi
    if unzip -p "$INPUT_EPUB" mimetype 2>/dev/null | grep -q "application/vnd\.adobe\.ePub"; then
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

# ---- 6. 路径与目录准备 ----
FILENAME=$(basename "$INPUT_EPUB")
NAME="${FILENAME%.*}"
EXT="${FILENAME##*.}"

verbose "输入文件: $INPUT_EPUB"
verbose "书名: $NAME, 扩展名: $EXT"

if [ "$EXT" != "epub" ]; then
    warn "文件扩展名不是 .epub，可能无法正确处理"
fi

mkdir -p "$OUTPUT_DIR"

# 工作目录
WORK_DIR="$HOME/.cc-epub-tmp/${NAME}_$$"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# 备份目录
BACKUP_DIR="$OUTPUT_DIR/.backup"
mkdir -p "$BACKUP_DIR"

# 检查 mimetype
HAS_MIMETYPE=0
if unzip -l "$INPUT_EPUB" 2>/dev/null | grep -qw "mimetype"; then
    HAS_MIMETYPE=1
fi

# 记录原始文件大小
ORIG_SIZE=$(du -h "$INPUT_EPUB" 2>/dev/null | awk '{print $1}')
ORIG_SIZE_BYTES=$(du -b "$INPUT_EPUB" 2>/dev/null | awk '{print $1}')
verbose "原始文件大小: $ORIG_SIZE ($ORIG_SIZE_BYTES 字节)"

# ---- 7. Dry Run 模式 ----
if [ "$DRY_RUN" -eq 1 ]; then
    info "=== Dry Run 模式：仅检查，不执行转换 ==="
    info "输入文件: $INPUT_EPUB"
    info "书名: $NAME"
    info "转换模式: $MODE"
    info "首行缩进: $([ "$ADD_INDENT" -eq 1 ] && echo '是' || echo '否')"
    info "竖排转横排: $([ "$FORCE_HORIZONTAL" -eq 1 ] && echo '是' || echo '否')"
    info "图片压缩: $([ "$COMPRESS_IMAGES" -eq 1 ] && echo '是' || echo '否')"
    info "Kindle 优化: $([ "$KINDLE_OPT" -eq 1 ] && echo '是' || echo '否')"
    info "编码: $ENCODING"
    info "超时: ${TIMEOUT}s"

    echo ""
    info "EPUB 内部文件结构:"
    unzip -l "$INPUT_EPUB" 2>/dev/null | head -50
    TOTAL=$(unzip -l "$INPUT_EPUB" 2>/dev/null | tail -1 | awk '{print $1}')
    info "总大小: $TOTAL 字节"
    exit 0
fi

# ---- 8. 解压 EPUB ----
step "正在解压 $FILENAME ..."
if ! unzip -o -q "$INPUT_EPUB" -d "$WORK_DIR" 2>/dev/null; then
    error "解压失败，文件可能损坏或不是有效的 EPUB"
    exit 4
fi
success "解压完成"

# ---- 9. 繁简转换 ----
step "正在转换文本 (OpenCC 模式: $MODE, 编码: $ENCODING) ..."

# 查找所有文本文件（排除二进制文件）
TEXT_FILES=()
while IFS= read -r -d '' f; do
    if file "$f" 2>/dev/null | grep -q "binary\|image\|audio\|video\|compressed\|executable\|font\|data"; then
        verbose "跳过二进制文件: $f"
        continue
    fi
    TEXT_FILES+=("$f")
done < <(find "$WORK_DIR" -type f \( -name "*.xhtml" -o -name "*.html" -o -name "*.htm" -o -name "*.opf" -o -name "*.ncx" -o -name "*.xml" -o -name "*.css" \) -print0 2>/dev/null)

TEXT_FILE_COUNT=${#TEXT_FILES[@]}
info "找到 $TEXT_FILE_COUNT 个文本文件待处理"

if [ "$TEXT_FILE_COUNT" -gt 0 ]; then
    CONVERTED=0
    FAILED=0
    for file in "${TEXT_FILES[@]}"; do
        # 编码转换（如果指定了非UTF8编码）
        if [ "$ENCODING" != "utf-8" ]; then
            if command -v iconv &>/dev/null; then
                iconv -f "$ENCODING" -t utf-8 "$file" -o "${file}.utf8" 2>/dev/null && mv "${file}.utf8" "$file" || warn "编码转换失败: $file"
            fi
        fi

        if opencc -c "$MODE" -i "$file" -o "${file}.tmp" 2>/dev/null; then
            if [ -s "${file}.tmp" ]; then
                mv "${file}.tmp" "$file"
                CONVERTED=$((CONVERTED + 1))
            else
                rm -f "${file}.tmp"
            fi
        else
            warn "转换失败: $file"
            rm -f "${file}.tmp" 2>/dev/null || true
            FAILED=$((FAILED + 1))
        fi
    done
    if [ "$FAILED" -gt 0 ]; then
        success "转换完成，成功 $CONVERTED 个，失败 $FAILED 个"
    else
        success "转换完成，共处理 $CONVERTED 个文件"
    fi
else
    warn "未找到需要转换的文本文件"
fi

# ---- 10. 排版调整与 Kindle 兼容性优化 ----
step "正在调整排版并优化 Kindle 兼容性 ..."

if [ "$KINDLE_OPT" -eq 1 ] || [ "$ADD_INDENT" -eq 1 ] || [ "$FORCE_HORIZONTAL" -eq 1 ]; then
    STATS=$(python3 - "$WORK_DIR" "$ADD_INDENT" "$FORCE_HORIZONTAL" "$KINDLE_OPT" <<'PYEOF'
import sys, glob, re

temp_dir = sys.argv[1]
add_indent = sys.argv[2] == "1"
force_horizontal = sys.argv[3] == "1"
kindle_opt = sys.argv[4] == "1"

html_files = []
for ext in ("*.xhtml", "*.html", "*.htm"):
    html_files += glob.glob(f"{temp_dir}/**/{ext}", recursive=True)

css_files = glob.glob(f"{temp_dir}/**/*.css", recursive=True)

css_modified = 0
html_modified = 0

def fix_css(css_text):
    orig = css_text

    if kindle_opt:
        css_text = re.sub(r'@font-face\s*\{[^}]*\}', '', css_text, flags=re.S | re.I)
        css_text = re.sub(r'display\s*:\s*none', 'display: block', css_text, flags=re.I)

    if force_horizontal:
        css_text = re.sub(r'writing-mode\s*:\s*vertical-[a-z\-]+', 'writing-mode: horizontal-tb', css_text, flags=re.I)
        css_text = re.sub(r'-epub-writing-mode\s*:\s*vertical-[a-z\-]+', '-epub-writing-mode: horizontal-tb', css_text, flags=re.I)

    if add_indent:
        if re.search(r'text-indent', css_text, flags=re.I):
            css_text = re.sub(r'text-indent\s*:\s*[0-9.]+(?:em|px|rem|%)?', 'text-indent: 2em', css_text, flags=re.I)
        else:
            css_text = css_text.rstrip()
            if css_text.endswith('}'):
                css_text = css_text[:-1] + '\n  p { text-indent: 2em; margin: 0; }\n  p.noindent { text-indent: 0; }\n}'
            else:
                css_text += '\np { text-indent: 2em; margin: 0; }\np.noindent { text-indent: 0; }'

    return css_text

# 处理 CSS 文件
for path in css_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, PermissionError):
        continue
    new_content = fix_css(content)
    if new_content != content:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        css_modified += 1

# 处理 HTML/XHTML 文件中的 <style> 标签和内联样式
for path in html_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, PermissionError):
        continue
    orig = content

    def replace_style(m):
        return f"<style{m.group(1)}>{fix_css(m.group(2))}</style>"
    content = re.sub(r'<style([^>]*)>(.*?)</style>', replace_style, content, flags=re.S | re.I)

    if force_horizontal:
        content = re.sub(
            r'style="([^"]*?)writing-mode\s*:\s*vertical-[a-z\-]+([^"]*?)"',
            r'style="\1writing-mode: horizontal-tb\2"',
            content, flags=re.I
        )

    if content != orig:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        html_modified += 1

print(f"CSS_MODIFIED={css_modified}")
print(f"HTML_MODIFIED={html_modified}")
PYEOF
)
    # 解析统计结果
    CSS_COUNT=0
    HTML_COUNT=0
    while IFS='=' read -r key val; do
        case "$key" in
            CSS_MODIFIED) CSS_COUNT="$val" ;;
            HTML_MODIFIED) HTML_COUNT="$val" ;;
        esac
    done <<< "$STATS"

    info "排版调整完成：CSS $CSS_COUNT 个文件，HTML $HTML_COUNT 个文件"
else
    info "跳过排版调整（所有优化选项已禁用）"
fi

# ---- 11. 元数据与目录修复 ----
step "正在修复元数据与导航目录 ..."

# 修复 OPF 元数据
OPF_FILE=$(find "$WORK_DIR" -type f -iname "*.opf" | head -n 1 || true)
if [ -n "$OPF_FILE" ]; then
    sed -i 's|<dc:language>[^<]*</dc:language>|<dc:language>zh-CN</dc:language>|i' "$OPF_FILE" 2>/dev/null || true
    sed -i 's|page-progression-direction="rtl"|page-progression-direction="ltr"|gi' "$OPF_FILE" 2>/dev/null || true
    success "OPF 元数据已修复"
else
    warn "未找到 OPF 文件"
fi

# 修复 NCX 目录
NCX_FILES=$(find "$WORK_DIR" -type f -name "toc.ncx" 2>/dev/null || true)
if [ -n "$NCX_FILES" ]; then
    while IFS= read -r ncx_file; do
        sed -i 's|src="[^"]*#[^"]*"|src=""|g' "$ncx_file" 2>/dev/null || true
        success "NCX 目录已修复: $(basename "$ncx_file")"
    done <<< "$NCX_FILES"
fi

# 重建导航目录（nav.xhtml）
if [ "$REBUILD_TOC" -eq 1 ]; then
    NAV_FILE=$(find "$WORK_DIR" -type f -name "nav.xhtml" 2>/dev/null | head -n 1 || true)
    if [ -n "$NAV_FILE" ]; then
        # 确保 nav 文件包含正确的 role 属性
        sed -i 's|<nav[^>]*>|<nav xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" role="doc-toc" epub:type="toc" id="nav" aria-labelledby="tocTitle">|g' "$NAV_FILE" 2>/dev/null || true
        success "导航目录已更新"
    fi
fi

# ---- 12. (可选) 压缩过大图片 ----
if [ "$COMPRESS_IMAGES" -eq 1 ] && command -v magick &>/dev/null; then
    TOTAL_SIZE_MB=$(du -sm "$WORK_DIR" | awk '{print $1}')
    if [ "$TOTAL_SIZE_MB" -gt 150 ]; then
        step "EPUB 体积较大 (${TOTAL_SIZE_MB}MB)，正在压缩图片 ..."
        find "$WORK_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -exec magick "{}" -quality 82 -resize "1600>" "{}" \;
        success "图片压缩完成"
    else
        verbose "体积 ${TOTAL_SIZE_MB}MB < 150MB，跳过图片压缩"
    fi
fi

# ---- 13. 重新打包 EPUB ----
# 生成输出文件名
if [ -n "$OUTPUT_PREFIX" ]; then
    OUT_NAME="${OUTPUT_PREFIX}${NAME}"
else
    OUT_NAME="${NAME}"
fi
if [ -n "$OUTPUT_SUFFIX" ]; then
    OUT_NAME="${OUT_NAME}${OUTPUT_SUFFIX}"
fi
OUTPUT_FILE="$OUTPUT_DIR/${OUT_NAME}.epub"
rm -f "$OUTPUT_FILE"

step "正在打包 -> $OUTPUT_FILE ..."
cd "$WORK_DIR"

if [ "$HAS_MIMETYPE" -eq 1 ] && [ -f "mimetype" ]; then
    zip -X -0 -q "$OUTPUT_FILE" mimetype
    find . -type f ! -name "mimetype" | zip -r -X -9 -q "$OUTPUT_FILE" -@
else
    zip -r -X -q "$OUTPUT_FILE" .
fi

cd ~

# 记录输出文件大小
OUT_SIZE=$(du -h "$OUTPUT_FILE" 2>/dev/null | awk '{print $1}')
OUT_SIZE_BYTES=$(du -b "$OUTPUT_FILE" 2>/dev/null | awk '{print $1}')
verbose "输出文件大小: $OUT_SIZE ($OUT_SIZE_BYTES 字节)"

# 清理工作目录
rm -rf "$WORK_DIR"

# ---- 14. 输出文件完整性校验 ----
step "正在校验输出文件完整性 ..."
if unzip -t "$OUTPUT_FILE" &>/dev/null; then
    success "文件完整性校验通过"
else
    warn "文件完整性校验失败，文件可能损坏"
fi

# ---- 15. 输出统计信息 ----
if [ "$SHOW_STATS" -eq 1 ]; then
    echo ""
    info "=== 转换统计 ==="
    info "输入文件: $FILENAME"
    info "输入大小: $ORIG_SIZE ($ORIG_SIZE_BYTES 字节)"
    info "输出文件: ${OUT_NAME}.epub"
    info "输出大小: $OUT_SIZE ($OUT_SIZE_BYTES 字节)"
    if [ "$ORIG_SIZE_BYTES" -gt 0 ] && [ "$OUT_SIZE_BYTES" -gt 0 ]; then
        if [ "$OUT_SIZE_BYTES" -lt "$ORIG_SIZE_BYTES" ]; then
            RATIO=$(( (ORIG_SIZE_BYTES - OUT_SIZE_BYTES) * 100 / ORIG_SIZE_BYTES ))
            info "压缩率: ${RATIO}%"
        elif [ "$OUT_SIZE_BYTES" -gt "$ORIG_SIZE_BYTES" ]; then
            RATIO=$(( (OUT_SIZE_BYTES - ORIG_SIZE_BYTES) * 100 / ORIG_SIZE_BYTES ))
            info "膨胀率: ${RATIO}%"
        else
            info "大小不变"
        fi
    fi
    info "转换模式: $MODE"
    info "首行缩进: $([ "$ADD_INDENT" -eq 1 ] && echo '是' || echo '否')"
    info "竖排转横排: $([ "$FORCE_HORIZONTAL" -eq 1 ] && echo '是' || echo '否')"
    info "Kindle 优化: $([ "$KINDLE_OPT" -eq 1 ] && echo '是' || echo '否')"
    info "输出路径: $OUTPUT_FILE"
fi

# ---- 16. 备份原文件 ----
cp "$INPUT_EPUB" "$BACKUP_DIR/${NAME}.epub.backup" 2>/dev/null || true

echo ""
success "转换完成！输出: $OUTPUT_FILE"
info "提示：可前往 https://sendto.kindle.com 推送至 Kindle。"
