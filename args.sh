#!/usr/bin/env bash
# ============================================================
# CC-EPUB v6.0 — 参数解析模块 (lib/args.sh)
# 使用 while+shift 标准模式，避免 for+shift 错位问题
# ============================================================

# 防止重复加载
[ -n "${CCEPUB_ARGS_LOADED:-}" ] && return 0
CCEPUB_ARGS_LOADED=1

# ---- 默认值 ----
CCEPUB_ARGS_init() {
    CFG_MODE="tw2s"
    CFG_ADD_INDENT=1
    CFG_FORCE_HORIZONTAL=1
    CFG_COMPRESS_IMAGES=1
    CFG_KINDLE_OPT=1
    CFG_DRY_RUN=0
    CFG_VERBOSE=0
    CFG_QUIET=0
    CFG_OUTPUT_DIR="${HOME}/storage/downloads/E-book"
    CFG_BATCH_DIR=""
    CFG_PARALLEL_JOBS=1
    CFG_RESUME=0
    CFG_EXCLUDE_PATTERN=""
    CFG_INCLUDE_PATTERN=""
    CFG_SKIP_EXISTING=0
    CFG_ENCODING="utf-8"
    CFG_SHOW_STATS=0
    CFG_TIMEOUT=300
    CFG_RETRY_COUNT=0
    CFG_OUTPUT_PREFIX=""
    CFG_OUTPUT_SUFFIX="-cc"
    CFG_RESTORE_FILE=""
    CFG_CHECK_DRM=0
    CFG_LOG_FILE=""
    CFG_REBUILD_TOC=0
    CFG_CONFIG_FILE=""
    CFG_LIST_MODES=0
    CFG_JSON=0
    CFG_INTERACTIVE=0
    CFG_DEVICE="kindle"  # kindle | kobo | nook | generic
    INPUT_FILES=()
}

# ---- 打印帮助 ----
CCEPUB_ARGS_help() {
    cat <<EOF
CC-EPUB v${CCEPUB_VERSION} - 港台繁体 EPUB 转简体横排（Kindle/多设备优化）

用法: cc-epub <输入.epub> [选项]
      cc-epub --batch <目录> [选项]
      cc-epub --interactive          # 交互式菜单

基本选项:
  --mode <tw2s|hk2s|t2s>   转换模式（默认: tw2s）
  --no-indent              不添加首行缩进
  --keep-vertical          保留原始竖排格式
  --no-compress            不压缩图片
  --no-kindle-opt          不执行 Kindle 兼容性优化
  --device <kindle|kobo|nook|generic>
                           目标设备（默认: kindle）
  --dry-run                仅检查，不执行转换
  --dry-run --json         以 JSON 输出检查报告

输出选项:
  --quiet                  静默模式（仅输出错误和结果）
  --output <路径>          指定输出目录
  --output-prefix <前缀>   自定义输出文件名前缀
  --output-suffix <后缀>   自定义输出文件名后缀（默认: -cc）
  --stats                  显示转换统计信息

批量处理选项:
  --batch <目录>           批量处理目录下所有 EPUB
  --parallel <N>           并行处理（N 个并发任务）
  --resume                 断点续转（从上次中断处继续）
  --exclude <模式>         批量时排除匹配文件（如 '*.jpg'）
  --include <模式>         批量时仅处理匹配文件（如 '小说*'）
  --skip-existing          跳过已存在的输出文件
  --timeout <秒>           单个文件处理超时（默认: 300）
  --retry <次数>           失败重试次数（默认: 0）

高级选项:
  --verbose                详细输出模式
  --encoding <编码>        指定输入文件编码（默认: utf-8）
  --check-drm              检查文件是否有 DRM 保护
  --log <文件>             保存转换日志到文件
  --toc                    重建目录
  --config <文件>          加载预设配置文件
  --restore <备份文件>     从备份恢复原文件
  --list-modes             列出可用的 OpenCC 转换模式
  --interactive            进入交互式菜单
  --help                   显示此帮助
EOF
}

# ---- 参数解析主函数 ----
# 用法: CCEPUB_ARGS_parse "$@"
# 解析结果存入 CFG_* 全局变量；位置参数中未被消费的文件名存入 INPUT_FILES
CCEPUB_ARGS_parse() {
    CCEPUB_ARGS_init

    # 无参数 → 交互式
    if [ $# -eq 0 ]; then
        CFG_INTERACTIVE=1
        return 0
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --mode)
                [ $# -ge 2 ] || { error "--mode 需要参数"; exit 1; }
                CFG_MODE="$2"
                case "$CFG_MODE" in
                    tw2s|hk2s|t2s) ;;
                    *) error "不支持的转换模式: $CFG_MODE (可选: tw2s, hk2s, t2s)"; exit 1 ;;
                esac
                shift 2
                ;;
            --no-indent)        CFG_ADD_INDENT=0; shift ;;
            --keep-vertical)    CFG_FORCE_HORIZONTAL=0; shift ;;
            --no-compress)      CFG_COMPRESS_IMAGES=0; shift ;;
            --no-kindle-opt)    CFG_KINDLE_OPT=0; shift ;;
            --dry-run)          CFG_DRY_RUN=1; shift ;;
            --verbose)          CFG_VERBOSE=1; shift ;;
            --quiet)            CFG_QUIET=1; shift ;;
            --stats)            CFG_SHOW_STATS=1; shift ;;
            --resume)           CFG_RESUME=1; shift ;;
            --skip-existing)    CFG_SKIP_EXISTING=1; shift ;;
            --check-drm)        CFG_CHECK_DRM=1; shift ;;
            --toc)              CFG_REBUILD_TOC=1; shift ;;
            --list-modes)       CFG_LIST_MODES=1; shift ;;
            --json)             CFG_JSON=1; shift ;;
            --interactive)      CFG_INTERACTIVE=1; shift ;;
            --output)
                [ $# -ge 2 ] || { error "--output 需要参数"; exit 1; }
                CFG_OUTPUT_DIR="$2"; shift 2 ;;
            --batch)
                [ $# -ge 2 ] || { error "--batch 需要参数"; exit 1; }
                CFG_BATCH_DIR="$2"
                [ -d "$CFG_BATCH_DIR" ] || { error "目录不存在: $CFG_BATCH_DIR"; exit 1; }
                shift 2 ;;
            --parallel)
                [ $# -ge 2 ] || { error "--parallel 需要参数"; exit 1; }
                CFG_PARALLEL_JOBS="$2"
                [[ "$CFG_PARALLEL_JOBS" =~ ^[0-9]+$ ]] && [ "$CFG_PARALLEL_JOBS" -ge 1 ] || {
                    error "并行任务数必须为正整数"; exit 1; }
                shift 2 ;;
            --exclude)
                [ $# -ge 2 ] || { error "--exclude 需要参数"; exit 1; }
                CFG_EXCLUDE_PATTERN="$2"; shift 2 ;;
            --include)
                [ $# -ge 2 ] || { error "--include 需要参数"; exit 1; }
                CFG_INCLUDE_PATTERN="$2"; shift 2 ;;
            --encoding)
                [ $# -ge 2 ] || { error "--encoding 需要参数"; exit 1; }
                CFG_ENCODING="$2"
                validate_encoding "$CFG_ENCODING" || { error "不支持的编码: $CFG_ENCODING"; exit 1; }
                shift 2 ;;
            --timeout)
                [ $# -ge 2 ] || { error "--timeout 需要参数"; exit 1; }
                CFG_TIMEOUT="$2"
                [[ "$CFG_TIMEOUT" =~ ^[0-9]+$ ]] || { error "超时时间必须为正整数（秒）"; exit 1; }
                shift 2 ;;
            --retry)
                [ $# -ge 2 ] || { error "--retry 需要参数"; exit 1; }
                CFG_RETRY_COUNT="$2"
                [[ "$CFG_RETRY_COUNT" =~ ^[0-9]+$ ]] || { error "重试次数必须为非负整数"; exit 1; }
                shift 2 ;;
            --output-prefix)
                [ $# -ge 2 ] || { error "--output-prefix 需要参数"; exit 1; }
                CFG_OUTPUT_PREFIX="$2"; shift 2 ;;
            --output-suffix)
                [ $# -ge 2 ] || { error "--output-suffix 需要参数"; exit 1; }
                CFG_OUTPUT_SUFFIX="$2"; shift 2 ;;
            --restore)
                [ $# -ge 2 ] || { error "--restore 需要参数"; exit 1; }
                CFG_RESTORE_FILE="$2"
                [ -f "$CFG_RESTORE_FILE" ] || { error "备份文件不存在: $CFG_RESTORE_FILE"; exit 1; }
                shift 2 ;;
            --log)
                [ $# -ge 2 ] || { error "--log 需要参数"; exit 1; }
                CFG_LOG_FILE="$2"
                mkdir -p "$(dirname "$CFG_LOG_FILE")" 2>/dev/null || true
                shift 2 ;;
            --config)
                [ $# -ge 2 ] || { error "--config 需要参数"; exit 1; }
                CFG_CONFIG_FILE="$2"
                [ -f "$CFG_CONFIG_FILE" ] || { error "配置文件不存在: $CFG_CONFIG_FILE"; exit 1; }
                shift 2 ;;
            --device)
                [ $# -ge 2 ] || { error "--device 需要参数"; exit 1; }
                CFG_DEVICE="$2"
                case "$CFG_DEVICE" in
                    kindle|kobo|nook|generic) ;;
                    *) error "不支持的设备: $CFG_DEVICE (可选: kindle, kobo, nook, generic)"; exit 1 ;;
                esac
                shift 2 ;;
            --help|-h)
                CCEPUB_ARGS_help
                exit 0 ;;
            --*)
                error "未知选项: $1"
                echo "运行 'cc-epub --help' 查看可用选项"
                exit 1 ;;
            *)
                # 非选项参数视为输入文件
                INPUT_FILES+=("$1")
                shift ;;
        esac
    done

    # 同步到旧变量名（兼容主脚本引用）
    MODE="$CFG_MODE"
    ADD_INDENT="$CFG_ADD_INDENT"
    FORCE_HORIZONTAL="$CFG_FORCE_HORIZONTAL"
    COMPRESS_IMAGES="$CFG_COMPRESS_IMAGES"
    KINDLE_OPT="$CFG_KINDLE_OPT"
    DRY_RUN="$CFG_DRY_RUN"
    VERBOSE="$CFG_VERBOSE"
    QUIET="$CFG_QUIET"
    OUTPUT_DIR="$CFG_OUTPUT_DIR"
    BATCH_DIR="$CFG_BATCH_DIR"
    PARALLEL_JOBS="$CFG_PARALLEL_JOBS"
    RESUME="$CFG_RESUME"
    EXCLUDE_PATTERN="$CFG_EXCLUDE_PATTERN"
    INCLUDE_PATTERN="$CFG_INCLUDE_PATTERN"
    SKIP_EXISTING="$CFG_SKIP_EXISTING"
    ENCODING="$CFG_ENCODING"
    SHOW_STATS="$CFG_SHOW_STATS"
    TIMEOUT="$CFG_TIMEOUT"
    RETRY_COUNT="$CFG_RETRY_COUNT"
    OUTPUT_PREFIX="$CFG_OUTPUT_PREFIX"
    OUTPUT_SUFFIX="$CFG_OUTPUT_SUFFIX"
    RESTORE_FILE="$CFG_RESTORE_FILE"
    CHECK_DRM="$CFG_CHECK_DRM"
    LOG_FILE="$CFG_LOG_FILE"
    REBUILD_TOC="$CFG_REBUILD_TOC"
    CONFIG_FILE="$CFG_CONFIG_FILE"
    LIST_MODES="$CFG_LIST_MODES"
    JSON_OUTPUT="$CFG_JSON"
    INTERACTIVE="$CFG_INTERACTIVE"
    DEVICE="$CFG_DEVICE"
}

# ---- 从配置文件加载（覆盖默认值，但不覆盖命令行显式指定的）----
CCEPUB_ARGS_load_config() {
    local config_file="$1"
    [ -f "$config_file" ] || return 1
    step "加载配置文件: $config_file"
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^#.*$ ]] && continue
        [ -z "${key:-}" ] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "${value:-}" | xargs)
        case "$key" in
            mode)               CFG_MODE="$value" ;;
            add_indent)         CFG_ADD_INDENT="$value" ;;
            force_horizontal)   CFG_FORCE_HORIZONTAL="$value" ;;
            compress_images)    CFG_COMPRESS_IMAGES="$value" ;;
            kindle_opt)         CFG_KINDLE_OPT="$value" ;;
            device)             CFG_DEVICE="$value" ;;
            encoding)            CFG_ENCODING="$value" ;;
            timeout)             CFG_TIMEOUT="$value" ;;
            retry)               CFG_RETRY_COUNT="$value" ;;
            *) warn "未知配置项: $key" ;;
        esac
    done < "$config_file"
    info "配置文件已加载"
}
