#!/usr/bin/env bash
# ============================================================
# CC-EPUB v6.0 — 通用函数库 (lib/common.sh)
# 颜色、日志、工具函数
# ============================================================

# 防止重复加载
[ -n "${CCEPUB_COMMON_LOADED:-}" ] && return 0
CCEPUB_COMMON_LOADED=1

# ---- 版本信息 ----
CCEPUB_VERSION="6.0"

# ---- 颜色定义（检测终端是否支持）----
if [ -t 1 ] && [ "${NO_COLOR:-0}" != "1" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

# ---- 日志级别（可被调用方覆盖）----
VERBOSE=${VERBOSE:-0}
QUIET=${QUIET:-0}
LOG_FD=${LOG_FD:-2}  # 默认输出到 stderr，重定向由主脚本控制

# ---- 日志函数 ----
# 用法: info "消息" ；支持 printf 格式
info() {
    [ "$QUIET" -eq 1 ] && return 0
    printf "${BLUE}[INFO]${NC} %s\n" "$*" >&"$LOG_FD"
}

success() {
    [ "$QUIET" -eq 1 ] && return 0
    printf "${GREEN}[OK]${NC} %s\n" "$*" >&"$LOG_FD"
}

warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$*" >&"$LOG_FD"
}

error() {
    printf "${RED}[ERR]${NC} %s\n" "$*" >&2
}

verbose() {
    [ "$VERBOSE" -eq 1 ] || return 0
    printf "${CYAN}[DBG]${NC} %s\n" "$*" >&"$LOG_FD"
}

step() {
    [ "$QUIET" -eq 1 ] && return 0
    printf "\n${CYAN}${BOLD}==>${NC} %s\n" "$*" >&"$LOG_FD"
}

sep() {
    [ "$QUIET" -eq 1 ] && return 0
    printf "${CYAN}──────────────────────────────────────────────${NC}\n" >&"$LOG_FD"
}

# ---- 确认函数 ----
confirm() {
    local prompt="${1:-继续?}"
    [ "${AUTO_ACCEPT:-0}" -eq 1 ] && return 0
    printf "${YELLOW}[确认]${NC} %s [Y/n]: " "$prompt" >&2
    read -r resp
    case "$resp" in
        [Yy]*|yes|YES|Yes|"") return 0 ;;
        *) return 1 ;;
    esac
}

# ---- 可移植的 sed -i ----
# 用法: SED_I 's/foo/bar/' file
SED_I() {
    if sed --version >/dev/null 2>&1; then
        # GNU sed
        sed -i "$@"
    else
        # BSD sed (macOS)
        local file="${!#}"
        sed -i '' "${@:1:$#-1}" "$file"
    fi
}

# ---- 依赖检查 ----
# 用法: require cmd1 cmd2 ...
require() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        error "缺少依赖: ${missing[*]}"
        error "请先运行 install.sh 安装依赖"
        exit 127
    fi
}

# ---- 临时目录管理 ----
CCEPUB_TMP="${HOME}/.cc-epub-tmp"
mk_workdir() {
    mkdir -p "$CCEPUB_TMP"
    mktemp -d "${CCEPUB_TMP}/work.XXXXXX"
}

cleanup_workdir() {
    local dir="$1"
    [ -n "$dir" ] && [ -d "$dir" ] && rm -rf "$dir"
}

# ---- 文件类型检测（判断是否为二进制）----
is_binary() {
    local file="$1"
    local mime
    mime=$(file -b --mime-type "$file" 2>/dev/null || echo "")
    case "$mime" in
        image/*|audio/*|video/*|application/font*|application/octet-stream|application/zip|application/x-*|font/*)
            return 0  # 是二进制
            ;;
        *)
            # 二次校验：检测是否含 null 字节
            if grep -qI "." "$file" 2>/dev/null; then
                return 1  # 文本
            else
                return 0  # 含 null，视为二进制
            fi
            ;;
    esac
}

# ---- JSON 转义（用于 --dry-run --json）----
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    printf '%s' "$s"
}

# ---- 字节单位换算 ----
human_size() {
    local bytes="$1"
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec "$bytes" 2>/dev/null || echo "${bytes}B"
    else
        # 降级：手动换算
        awk -v b="$bytes" 'BEGIN{
            if (b >= 1073741824) printf "%.1fGB", b/1073741824;
            else if (b >= 1048576) printf "%.1fMB", b/1048576;
            else if (b >= 1024) printf "%.1fKB", b/1024;
            else printf "%dB", b;
        }'
    fi
}

# ---- 编码校验 ----
validate_encoding() {
    local enc="$1"
    [ "$enc" = "utf-8" ] || [ "$enc" = "utf8" ] && return 0
    if command -v iconv &>/dev/null; then
        if echo "" | iconv -f "$enc" -t utf-8 &>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
    return 0  # 无 iconv 时不阻塞
}

# ---- OpenCC 后端探测（二进制优先，Python 回退）----
# 设置全局变量：CCEPUB_OPENCC_BACKEND = "binary" | "python" | ""
#                 CCEPUB_OPENCC_RUN   = 可调用的转换命令构造函数
detect_opencc_backend() {
    CCEPUB_OPENCC_BACKEND=""
    # 1) 系统 opencc 二进制（Termux: pkg install libopencc）
    if command -v opencc >/dev/null 2>&1; then
        CCEPUB_OPENCC_BACKEND="binary"
        return 0
    fi
    # 2) Python opencc 模块（pip install opencc-python-reimplemented）
    if command -v python3 >/dev/null 2>&1 \
       && python3 -c "import opencc" 2>/dev/null; then
        CCEPUB_OPENCC_BACKEND="python"
        return 0
    fi
    return 1
}

# 运行一次转换：$1=mode  $2=input_file  $3=output_file
# 返回 0 成功，非 0 失败
run_opencc() {
    local mode="$1" infile="$2" outfile="$3"
    if [ "$CCEPUB_OPENCC_BACKEND" = "binary" ]; then
        opencc -c "$mode" -i "$infile" -o "$outfile" 2>/dev/null && [ -s "$outfile" ]
    elif [ "$CCEPUB_OPENCC_BACKEND" = "python" ]; then
        python3 - "$infile" "$outfile" "$mode" <<'PY' 2>/dev/null
import sys, opencc
src, dst, mode = sys.argv[1], sys.argv[2], sys.argv[3]
cc = opencc.OpenCC(mode)
with open(src, encoding="utf-8") as f, open(dst, "w", encoding="utf-8") as g:
    g.write(cc.convert(f.read()))
PY
        [ -s "$outfile" ]
    else
        return 1
    fi
}

# ---- OpenCC 配置可用性检测 ----
# 注意：不能用 -i /dev/null -o /dev/null，OpenCC 会报
# "input and output refer to the same file" 导致误判为不可用。
# 改用真实临时文件做探测，且兼容 binary / python 两种后端。
opencc_available() {
    local mode="${1:-tw2s}" tmp_in tmp_out rc=1
    detect_opencc_backend || return 1
    tmp_in=$(mktemp); tmp_out=$(mktemp)
    echo "測試軟體網路連線" >"$tmp_in"
    if run_opencc "$mode" "$tmp_in" "$tmp_out" 2>/dev/null && [ -s "$tmp_out" ]; then
        rc=0
    fi
    rm -f "$tmp_in" "$tmp_out"
    return $rc
}

# ---- 列出可用 OpenCC 模式 ----
# 优先解析 `opencc -l` 输出；若当前 OpenCC 版本输出格式不包含标准模式名，
# 则回退到内置的标准模式列表，保证 --list-modes 始终有内容。
list_opencc_modes() {
    local detected
    detected=$(opencc -l 2>/dev/null | grep -E "s2t|t2s|s2tw|tw2s|s2hk|hk2s" | sort -u || true)
    if [ -n "$detected" ]; then
        echo "$detected"
    else
        # 内置标准模式（OpenCC 官方默认配置）
        echo "tw2s"
        echo "hk2s"
        echo "s2tw"
        echo "t2s"
        echo "s2hk"
        echo "hk2t"
    fi
}

# ---- 退出时清理 ----
setup_cleanup_trap() {
    trap 'cleanup_workdir "$WORK_DIR"' EXIT
}

# ---- 导出函数（供子 shell 使用）----
export -f info success warn error verbose step SED_I is_binary
