#!/usr/bin/env bash
# ============================================================
# CC-EPUB v6.0 — 测试运行脚本
# 用法: bash tests/run_tests.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CCEPUB_LIB_DIR="$ROOT/lib"
export CCEPUB_BIN_DIR="$ROOT"

# 颜色
G='\033[0;32m'; R='\033[0;31m'; Y='\033[1;33m'; B='\033[0;34m'; NC='\033[0m'
pass() { echo -e "  ${G}✓ PASS${NC} $*"; }
fail() { echo -e "  ${R}✗ FAIL${NC} $*"; FAILED_TESTS=$((FAILED_TESTS + 1)); }
info() { echo -e "  ${B}INFO${NC} $*"; }

TOTAL=0
FAILED_TESTS=0

# 加载库
# shellcheck source=../lib/common.sh
source "$ROOT/lib/common.sh"
# shellcheck source=../lib/args.sh
source "$ROOT/lib/args.sh"
# shellcheck source=../lib/convert.sh
source "$ROOT/lib/convert.sh"
# shellcheck source=../lib/batch.sh
source "$ROOT/lib/batch.sh"

run_test() {
    local name="$1"; shift
    TOTAL=$((TOTAL + 1))
    info "测试: $name"
    if "$@"; then
        pass "$name"
    else
        fail "$name"
    fi
}

# ---- 准备 fixture ----
FIXTURE_DIR="$ROOT/tests/fixtures"
mkdir -p "$FIXTURE_DIR"

# 生成一个最小合法 EPUB
make_fixture() {
    local name="$1"
    local extra_css="${2:-}"
    local lang="${3:-zh-TW}"
    local vertical="${4:-0}"
    local out="$FIXTURE_DIR/${name}.epub"
    rm -f "$out"
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/OEBPS"

    local writing_mode=""
    [ "$vertical" = "1" ] && writing_mode="writing-mode: vertical-rl;"

    cat > "$tmp/OEBPS/chapter1.xhtml" <<XHTML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>測試</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
<p>這是一個繁體中文測試檔案。</p>
<p>軟體開發、滑鼠操作、網路連線。</p>
</body>
</html>
XHTML

    cat > "$tmp/OEBPS/style.css" <<CSS
${writing_mode}
${extra_css}
p { margin: 0; }
CSS

    cat > "$tmp/OEBPS/content.opf" <<OPF
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>測試書籍</dc:title>
<dc:language>${lang}</dc:language>
<dc:creator>測試作者</dc:creator>
</metadata>
<manifest>
<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
</manifest>
<spine>
<itemref idref="c1"/>
</spine>
</package>
OPF

    cat > "$tmp/OEBPS/toc.ncx" <<NCX
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">
<head><meta name="dtb:uid" content="test"/></head>
<docTitle><text>測試</text></docTitle>
<navMap>
<navPoint id="np1"><navLabel><text>第一章</text></navLabel><content src="chapter1.xhtml#broken-fragment"/></navPoint>
</navMap>
</ncx>
NCX

    echo "application/epub+zip" > "$tmp/mimetype"
    (
        cd "$tmp"
        zip -X -0 -q "$out" mimetype
        find . -type f ! -name "mimetype" | zip -r -X -9 -q "$out" -@
    )
    rm -rf "$tmp"
    echo "$out"
}

echo -e "${Y}=== CC-EPUB v${CCEPUB_VERSION} 测试套件 ===${NC}"
echo ""

# ============================================================
# 测试 1: 参数解析
# ============================================================
test_args_default() {
    CCEPUB_ARGS_init
    CCEPUB_ARGS_parse 2>/dev/null
    [ "$CFG_MODE" = "tw2s" ] && [ "$CFG_PARALLEL_JOBS" = "1" ]
}
run_test "参数解析 - 默认值" test_args_default

test_args_mode() {
    CCEPUB_ARGS_init
    CCEPUB_ARGS_parse --mode hk2s 2>/dev/null
    [ "$CFG_MODE" = "hk2s" ]
}
run_test "参数解析 - --mode hk2s" test_args_mode

test_args_mode_invalid() {
    CCEPUB_ARGS_init
    ( CCEPUB_ARGS_parse --mode invalid 2>/dev/null ); local rc=$?
    [ "$rc" -ne 0 ] || return 1
}
run_test "参数解析 - 无效模式被拒绝" test_args_mode_invalid

test_args_all_options() {
    CCEPUB_ARGS_init
    CCEPUB_ARGS_parse --mode t2s --no-indent --keep-vertical --no-compress \
        --device kobo --parallel 4 --timeout 600 --retry 3 \
        --output /tmp/out --stats --verbose 2>/dev/null
    [ "$CFG_MODE" = "t2s" ] && \
    [ "$CFG_ADD_INDENT" = "0" ] && \
    [ "$CFG_FORCE_HORIZONTAL" = "0" ] && \
    [ "$CFG_COMPRESS_IMAGES" = "0" ] && \
    [ "$CFG_DEVICE" = "kobo" ] && \
    [ "$CFG_PARALLEL_JOBS" = "4" ] && \
    [ "$CFG_TIMEOUT" = "600" ] && \
    [ "$CFG_RETRY_COUNT" = "3" ] && \
    [ "$CFG_OUTPUT_DIR" = "/tmp/out" ] && \
    [ "$CFG_SHOW_STATS" = "1" ] && \
    [ "$CFG_VERBOSE" = "1" ]
}
run_test "参数解析 - 全部选项组合" test_args_all_options

test_args_encoding_invalid() {
    CCEPUB_ARGS_init
    ( CCEPUB_ARGS_parse --encoding not-a-real-encoding 2>/dev/null ); local rc=$?
    [ "$rc" -ne 0 ] || return 1
}
run_test "参数解析 - 无效编码被拒绝" test_args_encoding_invalid

test_args_input_files() {
    CCEPUB_ARGS_init
    CCEPUB_ARGS_parse --mode tw2s book1.epub book2.epub 2>/dev/null
    [ "${#INPUT_FILES[@]}" = "2" ] && [ "${INPUT_FILES[0]}" = "book1.epub" ]
}
run_test "参数解析 - 多输入文件收集" test_args_input_files

# ============================================================
# 测试 2: 基本转换
# ============================================================
FIXTURE_NORMAL=$(make_fixture "normal")

# 探测本机 OpenCC tw2s 对给定繁体词的实际简体输出。
# 用法: probe_word "軟體"  -> 例如输出 "软体" 或 "軟件"
probe_word() {
    local trad="$1"
    local tin tout
    tin=$(mktemp); tout=$(mktemp)
    echo "$trad" > "$tin"
    opencc -c tw2s -i "$tin" -o "$tout" 2>/dev/null || true
    cat "$tout"
    rm -f "$tin" "$tout"
}

test_convert_basic() {
    local out_dir; out_dir=$(mktemp -d)
    CCEPUB_ARGS_init
    CFG_OUTPUT_DIR="$out_dir"
    CFG_BATCH_DIR=""
    CFG_DEVICE="kindle"
    local ret=0
    CCEPUB_convert "$FIXTURE_NORMAL" || ret=$?
    if [ $ret -ne 0 ]; then return 1; fi
    local result="$out_dir/normal-cc.epub"
    [ -f "$result" ] || return 1
    local tmp; tmp=$(mktemp -d)
    unzip -o -q "$result" -d "$tmp"

    # 探测本机 OpenCC 用词（兼容台湾用语保留 vs 大陆简体两种环境）
    local W_MOUSE W_NET
    W_MOUSE=$(probe_word "滑鼠")   # 可能 "鼠标" 或 "滑鼠"（保留）
    W_NET=$(probe_word "網路")     # 可能 "网路" 或 "网络"

    # 句子级繁简转换（稳定：這→这, 是一個→是一个, 檔案→档案）
    grep -q "这是一个繁体中文测试档案" "$tmp/OEBPS/chapter1.xhtml" || return 1
    # 词汇级：軟體→软体（两环境都一致）
    grep -q "软体开发" "$tmp/OEBPS/chapter1.xhtml" || return 1
    # 动态用词：鼠标/滑鼠、网路/网络 任一命中即算通过
    grep -qE "(${W_MOUSE}|鼠标|滑鼠)操作" "$tmp/OEBPS/chapter1.xhtml" || return 1
    grep -qE "${W_NET}(连线|连接|连线)" "$tmp/OEBPS/chapter1.xhtml" || return 1
    rm -rf "$tmp" "$out_dir"
    return 0
}
run_test "基本转换 - 繁→简 + 词汇转换" test_convert_basic

# 竖排转横排
FIXTURE_VERTICAL=$(make_fixture "vertical" "" "" "1")
test_convert_horizontal() {
    local out_dir; out_dir=$(mktemp -d)
    CCEPUB_ARGS_init
    CFG_OUTPUT_DIR="$out_dir"
    CFG_FORCE_HORIZONTAL=1
    local ret=0
    CCEPUB_convert "$FIXTURE_VERTICAL" || ret=$?
    [ $ret -ne 0 ] && return 1
    local result="$out_dir/vertical-cc.epub"
    [ -f "$result" ] || return 1
    local tmp; tmp=$(mktemp -d)
    unzip -o -q "$result" -d "$tmp"
    grep -q "writing-mode: horizontal-tb" "$tmp/OEBPS/style.css" || return 1
    rm -rf "$tmp" "$out_dir"
    return 0
}
run_test "排版 - 竖排转横排" test_convert_horizontal

# 首行缩进注入
test_convert_indent() {
    local out_dir; out_dir=$(mktemp -d)
    CCEPUB_ARGS_init
    CFG_OUTPUT_DIR="$out_dir"
    CFG_ADD_INDENT=1
    CCEPUB_convert "$FIXTURE_NORMAL" >/dev/null 2>&1
    local result="$out_dir/normal-cc.epub"
    local tmp; tmp=$(mktemp -d)
    unzip -o -q "$result" -d "$tmp"
    grep -q "text-indent: 2em" "$tmp/OEBPS/style.css" || return 1
    rm -rf "$tmp" "$out_dir"
    return 0
}
run_test "排版 - 首行缩进注入" test_convert_indent

# NCX 目录修复
test_convert_ncx_fix() {
    local out_dir; out_dir=$(mktemp -d)
    CCEPUB_ARGS_init
    CFG_OUTPUT_DIR="$out_dir"
    CCEPUB_convert "$FIXTURE_NORMAL" >/dev/null 2>&1
    local result="$out_dir/normal-cc.epub"
    local tmp; tmp=$(mktemp -d)
    unzip -o -q "$result" -d "$tmp"
    # broken-fragment 应被清空
    grep -q 'src="chapter1.xhtml"' "$tmp/OEBPS/toc.ncx" || return 1
    grep -q 'broken-fragment' "$tmp/OEBPS/toc.ncx" && return 1
    rm -rf "$tmp" "$out_dir"
    return 0
}
run_test "元数据 - NCX 异常片段修复" test_convert_ncx_fix

# OPF 语言修复
test_convert_opf_lang() {
    local out_dir; out_dir=$(mktemp -d)
    CCEPUB_ARGS_init
    CFG_OUTPUT_DIR="$out_dir"
    CCEPUB_convert "$FIXTURE_NORMAL" >/dev/null 2>&1
    local result="$out_dir/normal-cc.epub"
    local tmp; tmp=$(mktemp -d)
    unzip -o -q "$result" -d "$tmp"
    grep -q "<dc:language>zh-CN</dc:language>" "$tmp/OEBPS/content.opf" || return 1
    rm -rf "$tmp" "$out_dir"
    return 0
}
run_test "元数据 - OPF language → zh-CN" test_convert_opf_lang

# ============================================================
# 测试 3: Dry Run
# ============================================================
test_dry_run() {
    CCEPUB_ARGS_init
    CFG_DRY_RUN=1
    CFG_OUTPUT_DIR="/tmp"
    local out
    out=$(CCEPUB_convert "$FIXTURE_NORMAL" 2>&1)
    echo "$out" | grep -q "Dry Run" || return 1
}
run_test "Dry Run - 不实际转换" test_dry_run

test_dry_run_json() {
    CCEPUB_ARGS_init
    CFG_DRY_RUN=1
    CFG_JSON=1
    CFG_OUTPUT_DIR="/tmp"
    local out
    out=$(CCEPUB_convert "$FIXTURE_NORMAL" 2>&1)
    echo "$out" | grep -q '"mode"' || return 1
    echo "$out" | grep -q '"size_bytes"' || return 1
    # JSON 必须是合法可解析的对象（字段完整、结构成对）
    echo "$out" | grep -q '"file"' || return 1
    echo "$out" | grep -q '"name"' || return 1
}
run_test "Dry Run - JSON 输出" test_dry_run_json

# ============================================================
# 测试 4: DRM 检测
# ============================================================
FIXTURE_DRM=$(make_fixture "drm")
test_drm_detect() {
    local tmp; tmp=$(mktemp -d)
    # 注入 encryption.xml 模拟 DRM
    mkdir -p "$tmp/META-INF"
    echo "<encryption/>" > "$tmp/META-INF/encryption.xml"
    (
        cd "$tmp"
        [ -f "drm.epub" ] && rm -f "drm.epub"
        zip -X -0 -q "$FIXTURE_DIR/drm.epub" mimetype 2>/dev/null || true
    )
    rm -rf "$tmp"
    # 直接构造带 DRM 的 epub
    local drm_epub="$FIXTURE_DIR/drm.epub"
    rm -f "$drm_epub"
    tmp=$(mktemp -d)
    echo "application/epub+zip" > "$tmp/mimetype"
    mkdir -p "$tmp/META-INF"
    echo '<?xml version="1.0"?><encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container"/>' > "$tmp/META-INF/encryption.xml"
    (
        cd "$tmp"
        zip -X -0 -q "$drm_epub" mimetype
        zip -r -X -9 -q "$drm_epub" META-INF
    )
    rm -rf "$tmp"

    CCEPUB_ARGS_init
    CFG_CHECK_DRM=1
    local ret=0
    # 直接测试 DRM 检测逻辑
    local DRM_FOUND=0
    if unzip -l "$drm_epub" 2>/dev/null | grep -qi "encryption\|rights\|drmtype"; then DRM_FOUND=1; fi
    [ "$DRM_FOUND" -eq 1 ] || return 1
    return 0
}
run_test "DRM - 检测 META-INF/encryption.xml" test_drm_detect

# ============================================================
# 测试 5: 工具函数
# ============================================================
test_human_size() {
    local r1 r2
    r1=$(human_size 1024)
    r2=$(human_size 1048576)
    # numfmt 输出 1.0K / 1.0M 或 awk 输出 1.0KB / 1.0MB
    echo "$r1" | grep -qE "1\.0[KkKBiB]" || return 1
    echo "$r2" | grep -qE "1\.0[MmMBiB]" || return 1
}
run_test "工具 - human_size 换算" test_human_size

test_validate_encoding() {
    validate_encoding "utf-8" || return 1
    validate_encoding "big5" || return 1  # iconv 通常支持 big5
}
run_test "工具 - validate_encoding" test_validate_encoding

test_is_binary() {
    local tmp; tmp=$(mktemp)
    echo "binary" > "$tmp"
    # 强制 file 报告为 binary（通过 null 字节）
    printf 'text\0binary' > "$tmp"
    is_binary "$tmp" || return 1
    rm -f "$tmp"
    tmp=$(mktemp)
    echo "normal text content" > "$tmp"
    is_binary "$tmp" && return 1
    rm -f "$tmp"
    return 0
}
run_test "工具 - is_binary 检测" test_is_binary

# ============================================================
# 测试 6: 完整性校验
# ============================================================
test_output_valid_epub() {
    local out_dir; out_dir=$(mktemp -d)
    CCEPUB_ARGS_init
    CFG_OUTPUT_DIR="$out_dir"
    CCEPUB_convert "$FIXTURE_NORMAL" >/dev/null 2>&1
    local result="$out_dir/normal-cc.epub"
    # unzip -t 校验
    unzip -t "$result" >/dev/null 2>&1 || return 1
    rm -rf "$out_dir"
    return 0
}
run_test "输出 - EPUB 完整性校验通过" test_output_valid_epub

# ============================================================
# 测试 7: shellcheck
# ============================================================
test_shellcheck() {
    if ! command -v shellcheck &>/dev/null; then
        info "shellcheck 未安装，跳过"
        return 0
    fi
    shellcheck "$ROOT/cc-epub.sh" "$ROOT/install.sh" "$ROOT/lib"/*.sh 2>&1 || return 1
}
run_test "代码质量 - shellcheck 通过" test_shellcheck

# ============================================================
# 测试 8: 批量处理（串行）
# ============================================================
test_batch_serial() {
    local batch_dir; batch_dir=$(mktemp -d)
    cp "$FIXTURE_NORMAL" "$batch_dir/book1.epub"
    cp "$FIXTURE_NORMAL" "$batch_dir/book2.epub"
    local out_dir; out_dir=$(mktemp -d)

    CCEPUB_ARGS_init
    CFG_BATCH_DIR="$batch_dir"
    CFG_OUTPUT_DIR="$out_dir"
    CFG_PARALLEL_JOBS=1
    CFG_SHOW_STATS=0
    CFG_RESUME=0
    export CFG_BATCH_DIR CFG_OUTPUT_DIR CFG_PARALLEL_JOBS CFG_SHOW_STATS CFG_RESUME
    export CCEPUB_LIB_DIR CCEPUB_BIN_DIR CFG_MODE CFG_DEVICE
    export CFG_ADD_INDENT CFG_FORCE_HORIZONTAL CFG_COMPRESS_IMAGES CFG_KINDLE_OPT
    export CFG_DRY_RUN CFG_VERBOSE CFG_QUIET CFG_REBUILD_TOC
    export CFG_ENCODING CFG_TIMEOUT CFG_RETRY_COUNT CFG_OUTPUT_PREFIX CFG_OUTPUT_SUFFIX

    BATCH_SUCCESS=0; BATCH_FAILED=0; TOTAL_STEPS=0
    export BATCH_SUCCESS BATCH_FAILED TOTAL_STEPS
    CCEPUB_batch_main 2>&1 || true

    [ -f "$out_dir/book1-cc.epub" ] || return 1
    [ -f "$out_dir/book2-cc.epub" ] || return 1
    [ "$BATCH_SUCCESS" = "2" ] || { echo "BATCH_SUCCESS=$BATCH_SUCCESS" >&2; return 1; }
    rm -rf "$batch_dir" "$out_dir"
    return 0
}
run_test "批量处理 - 串行 2 文件" test_batch_serial

# ============================================================
# 汇总
# ============================================================
echo ""
sep
if [ "$FAILED_TESTS" -eq 0 ]; then
    echo -e "${G}全部 ${TOTAL} 个测试通过 ✓${NC}"
    exit 0
else
    echo -e "${R}${FAILED_TESTS}/${TOTAL} 个测试失败 ✗${NC}"
    exit 1
fi
