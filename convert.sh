#!/usr/bin/env bash
# ============================================================
# CC-EPUB v6.0 — 核心转换逻辑 (lib/convert.sh)
# 单一 EPUB 文件的完整转换流程
# ============================================================

[ -n "${CCEPUB_CONVERT_LOADED:-}" ] && return 0
CCEPUB_CONVERT_LOADED=1

# 依赖主脚本已 source common.sh / args.sh

# ---- 设备适配参数 ----
CCEPUB_device_settings() {
    case "$CFG_DEVICE" in
        kindle)
            DEV_OPT_KINDLE=1
            DEV_PAGINATION="ltr"
            DEV_CSS_OVERRIDES=1
            ;;
        kobo)
            DEV_OPT_KINDLE=0
            DEV_PAGINATION="ltr"
            DEV_CSS_OVERRIDES=1
            ;;
        nook)
            DEV_OPT_KINDLE=0
            DEV_PAGINATION="ltr"
            DEV_CSS_OVERRIDES=0
            ;;
        generic)
            DEV_OPT_KINDLE=0
            DEV_PAGINATION="ltr"
            DEV_CSS_OVERRIDES=0
            ;;
    esac
    # kindle-opt 显式关闭时，设备适配也关闭
    if [ "$CFG_KINDLE_OPT" -eq 0 ]; then
        DEV_OPT_KINDLE=0
    fi
    return 0
}

# ---- 构建递归调用参数数组（避免空参数问题）----
CCEPUB_build_child_args() {
    CHILD_ARGS=()
    CHILD_ARGS+=(--mode "$CFG_MODE")
    CHILD_ARGS+=(--encoding "$CFG_ENCODING")
    CHILD_ARGS+=(--timeout "$CFG_TIMEOUT")
    CHILD_ARGS+=(--retry "$CFG_RETRY_COUNT")
    CHILD_ARGS+=(--output "$CFG_OUTPUT_DIR")
    CHILD_ARGS+=(--output-prefix "$CFG_OUTPUT_PREFIX")
    CHILD_ARGS+=(--output-suffix "$CFG_OUTPUT_SUFFIX")
    CHILD_ARGS+=(--device "$CFG_DEVICE")
    [ "$CFG_ADD_INDENT" -eq 0 ]      && CHILD_ARGS+=(--no-indent)
    [ "$CFG_FORCE_HORIZONTAL" -eq 0 ] && CHILD_ARGS+=(--keep-vertical)
    [ "$CFG_COMPRESS_IMAGES" -eq 0 ]  && CHILD_ARGS+=(--no-compress)
    [ "$CFG_KINDLE_OPT" -eq 0 ]       && CHILD_ARGS+=(--no-kindle-opt)
    [ "$CFG_DRY_RUN" -eq 1 ]          && CHILD_ARGS+=(--dry-run)
    [ "$CFG_VERBOSE" -eq 1 ]           && CHILD_ARGS+=(--verbose)
    [ "$CFG_QUIET" -eq 1 ]             && CHILD_ARGS+=(--quiet)
    [ "$CFG_REBUILD_TOC" -eq 1 ]       && CHILD_ARGS+=(--toc)
    [ -n "$CFG_LOG_FILE" ]             && CHILD_ARGS+=(--log "$CFG_LOG_FILE")
}

# ============================================================
# 主转换函数：CCEPUB_convert <input.epub>
# ============================================================
CCEPUB_convert() {
    local INPUT_EPUB="$1"
    local WORK_DIR=""
    local ret=0

    CCEPUB_device_settings

    # ---- 路径与目录准备 ----
    local FILENAME
    FILENAME=$(basename "$INPUT_EPUB")
    local NAME="${FILENAME%.*}"
    local EXT="${FILENAME##*.}"

    verbose "输入文件: $INPUT_EPUB"
    verbose "书名: $NAME, 扩展名: $EXT"

    if [ "$EXT" != "epub" ]; then
        warn "文件扩展名不是 .epub，可能无法正确处理"
    fi

    mkdir -p "$CFG_OUTPUT_DIR"

    # 工作目录
    WORK_DIR=$(mk_workdir)
    verbose "工作目录: $WORK_DIR"

    # 备份目录
    local BACKUP_DIR="$CFG_OUTPUT_DIR/.backup"
    mkdir -p "$BACKUP_DIR"

    # 记录原始文件大小
    local ORIG_SIZE_BYTES
    ORIG_SIZE_BYTES=$(du -b "$INPUT_EPUB" 2>/dev/null | awk '{print $1}')
    verbose "原始文件大小: $(human_size "$ORIG_SIZE_BYTES")"

    # ---- Dry Run（在解压前，纯检查）----
    if [ "$CFG_DRY_RUN" -eq 1 ]; then
        CCEPUB_dry_run_report "$INPUT_EPUB" "$NAME"
        cleanup_workdir "$WORK_DIR"
        return 0
    fi

    # ---- 8. 解压 ----
    step "正在解压 $FILENAME ..."
    if ! unzip -o -q "$INPUT_EPUB" -d "$WORK_DIR"; then
        error "解压失败，文件可能损坏或不是有效的 EPUB"
        cleanup_workdir "$WORK_DIR"
        return 4
    fi
    success "解压完成"

    # 检查 mimetype（解压后检查 WORK_DIR 中是否存在）
    local HAS_MIMETYPE=0
    if [ -f "$WORK_DIR/mimetype" ]; then
        HAS_MIMETYPE=1
    fi

    # ---- 9. 繁简转换 ----
    step "正在转换文本 (OpenCC 模式: $CFG_MODE, 编码: $CFG_ENCODING) ..."
    CCEPUB_run_conversion "$WORK_DIR"

    # ---- 10. 排版调整 + 设备适配 ----
    step "正在调整排版并优化 (设备: $CFG_DEVICE) ..."
    CCEPUB_adjust_layout "$WORK_DIR"

    # ---- 11. 元数据与目录修复 ----
    step "正在修复元数据与导航目录 ..."
    CCEPUB_fix_metadata "$WORK_DIR"

    # ---- 12. 图片压缩 ----
    if [ "$CFG_COMPRESS_IMAGES" -eq 1 ] && command -v magick &>/dev/null; then
        local TOTAL_SIZE_MB
        TOTAL_SIZE_MB=$(du -sm "$WORK_DIR" | awk '{print $1}')
        if [ "$TOTAL_SIZE_MB" -gt 150 ]; then
            step "EPUB 体积较大 (${TOTAL_SIZE_MB}MB)，正在压缩图片 ..."
            find "$WORK_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
                -exec magick "{}" -quality 82 -resize "1600>" "{}" \;
            success "图片压缩完成"
        else
            verbose "体积 ${TOTAL_SIZE_MB}MB < 150MB，跳过图片压缩"
        fi
    fi

    # ---- 13. 打包 ----
    local OUT_NAME="$CFG_OUTPUT_PREFIX${NAME}${CFG_OUTPUT_SUFFIX}"
    local OUTPUT_FILE="$CFG_OUTPUT_DIR/${OUT_NAME}.epub"
    rm -f "$OUTPUT_FILE"

    step "正在打包 -> $OUTPUT_FILE ..."
    (
        cd "$WORK_DIR"
        if [ "$HAS_MIMETYPE" -eq 1 ] && [ -f "mimetype" ]; then
            zip -X -0 -q "$OUTPUT_FILE" mimetype
            find . -type f ! -name "mimetype" | zip -r -X -9 -q "$OUTPUT_FILE" -@
        else
            zip -r -X -q "$OUTPUT_FILE" .
        fi
    )

    # 记录输出文件大小
    local OUT_SIZE_BYTES
    OUT_SIZE_BYTES=$(du -b "$OUTPUT_FILE" 2>/dev/null | awk '{print $1}')

    # ---- 14. 完整性校验 ----
    step "正在校验输出文件完整性 ..."
    if unzip -t "$OUTPUT_FILE" &>/dev/null; then
        success "文件完整性校验通过"
    else
        warn "文件完整性校验失败，文件可能损坏"
        ret=5
    fi

    # ---- 15. 统计 ----
    if [ "$CFG_SHOW_STATS" -eq 1 ]; then
        echo ""
        info "=== 转换统计 ==="
        info "输入文件: $FILENAME"
        info "输入大小: $(human_size "$ORIG_SIZE_BYTES")"
        info "输出文件: ${OUT_NAME}.epub"
        info "输出大小: $(human_size "$OUT_SIZE_BYTES")"
        if [ "$ORIG_SIZE_BYTES" -gt 0 ] && [ "$OUT_SIZE_BYTES" -gt 0 ]; then
            if [ "$OUT_SIZE_BYTES" -lt "$ORIG_SIZE_BYTES" ]; then
                local RATIO=$(( (ORIG_SIZE_BYTES - OUT_SIZE_BYTES) * 100 / ORIG_SIZE_BYTES ))
                info "压缩率: ${RATIO}%"
            elif [ "$OUT_SIZE_BYTES" -gt "$ORIG_SIZE_BYTES" ]; then
                local RATIO=$(( (OUT_SIZE_BYTES - ORIG_SIZE_BYTES) * 100 / ORIG_SIZE_BYTES ))
                info "膨胀率: ${RATIO}%"
            else
                info "大小不变"
            fi
        fi
        info "转换模式: $CFG_MODE"
        info "目标设备: $CFG_DEVICE"
        info "输出路径: $OUTPUT_FILE"
    fi

    # ---- 16. 备份 ----
    cp "$INPUT_EPUB" "$BACKUP_DIR/${NAME}.epub.backup" 2>/dev/null || true

    cleanup_workdir "$WORK_DIR"

    if [ $ret -eq 0 ]; then
        success "转换完成！输出: $OUTPUT_FILE"
        info "提示：可前往 https://sendto.kindle.com 推送至 Kindle。"
    fi
    return $ret
}

# ---- Dry Run 报告 ----
CCEPUB_dry_run_report() {
    local INPUT_EPUB="$1"
    local NAME="$2"
    # 以 CFG_JSON 为单一事实源（同时兼容旧的 JSON_OUTPUT 变量名）
    if [ "${CFG_JSON:-0}" = "1" ] || [ "${JSON_OUTPUT:-0}" = "1" ]; then
        CCEPUB_dry_run_json "$INPUT_EPUB" "$NAME"
        return
    fi
    info "=== Dry Run 模式：仅检查，不执行转换 ==="
    info "输入文件: $INPUT_EPUB"
    info "书名: $NAME"
    info "转换模式: $CFG_MODE"
    info "首行缩进: $([ "$CFG_ADD_INDENT" -eq 1 ] && echo '是' || echo '否')"
    info "竖排转横排: $([ "$CFG_FORCE_HORIZONTAL" -eq 1 ] && echo '是' || echo '否')"
    info "图片压缩: $([ "$CFG_COMPRESS_IMAGES" -eq 1 ] && echo '是' || echo '否')"
    info "设备优化: $CFG_DEVICE"
    info "编码: $CFG_ENCODING"
    info "超时: ${CFG_TIMEOUT}s"
    echo ""
    info "EPUB 内部文件结构:"
    unzip -l "$INPUT_EPUB" 2>/dev/null | head -50
    local TOTAL
    TOTAL=$(unzip -l "$INPUT_EPUB" 2>/dev/null | tail -1 | awk '{print $1}')
    info "总大小: $(human_size "$TOTAL")"
}

CCEPUB_dry_run_json() {
    local INPUT_EPUB="$1"
    local NAME="$2"
    local sz
    sz=$(du -b "$INPUT_EPUB" 2>/dev/null | awk '{print $1}')
    printf '{\n'
    printf '  "file": "%s",\n' "$(json_escape "$INPUT_EPUB")"
    printf '  "name": "%s",\n' "$(json_escape "$NAME")"
    printf '  "size_bytes": %s,\n' "${sz:-0}"
    printf '  "mode": "%s",\n' "$CFG_MODE"
    printf '  "device": "%s",\n' "$CFG_DEVICE"
    printf '  "add_indent": %s,\n' "$CFG_ADD_INDENT"
    printf '  "force_horizontal": %s,\n' "$CFG_FORCE_HORIZONTAL"
    printf '  "compress_images": %s,\n' "$CFG_COMPRESS_IMAGES"
    printf '  "encoding": "%s",\n' "$CFG_ENCODING"
    printf '  "timeout": %s\n' "$CFG_TIMEOUT"
    printf '}\n'
}

# ---- 繁简转换核心 ----
CCEPUB_run_conversion() {
    local WORK_DIR="$1"
    local TEXT_FILES=()
    while IFS= read -r -d '' f; do
        if is_binary "$f"; then
            verbose "跳过二进制文件: $f"
            continue
        fi
        TEXT_FILES+=("$f")
    done < <(find "$WORK_DIR" -type f \( -name "*.xhtml" -o -name "*.html" -o -name "*.htm" -o -name "*.opf" -o -name "*.ncx" -o -name "*.xml" -o -name "*.css" \) -print0 2>/dev/null)

    local TEXT_FILE_COUNT=${#TEXT_FILES[@]}
    info "找到 $TEXT_FILE_COUNT 个文本文件待处理"

    if [ "$TEXT_FILE_COUNT" -gt 0 ]; then
        local CONVERTED=0 FAILED=0
        for file in "${TEXT_FILES[@]}"; do
            # 编码转换
            if [ "$CFG_ENCODING" != "utf-8" ] && [ "$CFG_ENCODING" != "utf8" ]; then
                if command -v iconv &>/dev/null; then
                    if iconv -f "$CFG_ENCODING" -t utf-8 "$file" -o "${file}.utf8" 2>/dev/null; then
                        mv "${file}.utf8" "$file"
                    else
                        warn "编码转换失败: $file"
                    fi
                fi
            fi
            # OpenCC 转换（自动适配 binary / python 后端）
            detect_opencc_backend
            if run_opencc "$CFG_MODE" "$file" "${file}.tmp" 2>/dev/null && [ -s "${file}.tmp" ]; then
                mv "${file}.tmp" "$file"
                CONVERTED=$((CONVERTED + 1))
            else
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
}

# ---- 排版调整（调用 Python）----
CCEPUB_adjust_layout() {
    local WORK_DIR="$1"
    if [ "$CFG_KINDLE_OPT" -eq 0 ] && [ "$CFG_ADD_INDENT" -eq 0 ] && [ "$CFG_FORCE_HORIZONTAL" -eq 0 ] && [ "$DEV_CSS_OVERRIDES" -eq 0 ]; then
        info "跳过排版调整（所有优化选项已禁用）"
        return 0
    fi

    local STATS
    STATS=$(python3 - "$WORK_DIR" "$CFG_ADD_INDENT" "$CFG_FORCE_HORIZONTAL" "$CFG_KINDLE_OPT" "$DEV_CSS_OVERRIDES" "$CFG_DEVICE" <<'PYEOF'
import sys, glob, re

temp_dir = sys.argv[1]
add_indent = sys.argv[2] == "1"
force_horizontal = sys.argv[3] == "1"
kindle_opt = sys.argv[4] == "1"
css_overrides = sys.argv[5] == "1"
device = sys.argv[6]

html_files = []
for ext in ("*.xhtml", "*.html", "*.htm"):
    html_files += glob.glob(f"{temp_dir}/**/{ext}", recursive=True)
css_files = glob.glob(f"{temp_dir}/**/*.css", recursive=True)

css_modified = 0
html_modified = 0


def fix_css(css_text):
    global css_modified_flag
    orig = css_text

    if kindle_opt:
        # 移除 @font-face（避免白页）
        css_text = re.sub(r'@font-face\s*\{[^}]*\}', '', css_text, flags=re.S | re.I)
        # 清理 display:none 等可能导致转换失败的属性
        css_text = re.sub(r'display\s*:\s*none(?:\s*!important)?', 'display: block', css_text, flags=re.I)

    if force_horizontal:
        css_text = re.sub(r'writing-mode\s*:\s*vertical-[a-z\-]+',
                          'writing-mode: horizontal-tb', css_text, flags=re.I)
        css_text = re.sub(r'-epub-writing-mode\s*:\s*vertical-[a-z\-]+',
                          '-epub-writing-mode: horizontal-tb', css_text, flags=re.I)
        # 处理 -webkit-writing-mode
        css_text = re.sub(r'-webkit-writing-mode\s*:\s*vertical-[a-z\-]+',
                          '-webkit-writing-mode: horizontal-tb', css_text, flags=re.I)

    if add_indent:
        if re.search(r'text-indent', css_text, flags=re.I):
            css_text = re.sub(r'text-indent\s*:\s*[0-9.]+(?:em|px|rem|%)?',
                              'text-indent: 2em', css_text, flags=re.I)
        else:
            css_text = css_text.rstrip()
            if css_text.endswith('}'):
                css_text = css_text[:-1] + '\n  p { text-indent: 2em; margin: 0; }\n  p.noindent { text-indent: 0; }\n}'
            else:
                css_text += '\np { text-indent: 2em; margin: 0; }\np.noindent { text-indent: 0; }'

    if css_overrides:
        # Kobo/Nook 设备适配：注入通用兼容样式
        if device in ("kobo", "nook"):
            css_text = css_text.rstrip()
            if css_text.endswith('}'):
                css_text = css_text[:-1] + '\n  body { margin: 0; padding: 0; }\n}'
            else:
                css_text += '\nbody { margin: 0; padding: 0; }'

    if css_text != orig:
        css_modified_flag = True
    return css_text


# 处理 CSS 文件
for path in css_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, PermissionError):
        continue
    css_modified_flag = False
    new_content = fix_css(content)
    if new_content != content:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        css_modified += 1

# 处理 HTML <style> 与内联样式
for path in html_files:
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, PermissionError):
        continue
    orig = content

    def replace_style(m):
        global css_modified_flag
        css_modified_flag = False
        return f"<style{m.group(1)}>{fix_css(m.group(2))}</style>"
    content = re.sub(r'<style([^>]*)>(.*?)</style>', replace_style, content, flags=re.S | re.I)

    if force_horizontal:
        content = re.sub(
            r'style="([^"]*?)writing-mode\s*:\s*vertical-[a-z\-]+([^"]*?)"',
            r'style="\1writing-mode: horizontal-tb\2"',
            content, flags=re.I)

    if content != orig:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        html_modified += 1

print(f"CSS_MODIFIED={css_modified}")
print(f"HTML_MODIFIED={html_modified}")
PYEOF
    )
    local CSS_COUNT=0 HTML_COUNT=0
    while IFS='=' read -r key val; do
        case "$key" in
            CSS_MODIFIED) CSS_COUNT="$val" ;;
            HTML_MODIFIED) HTML_COUNT="$val" ;;
        esac
    done <<< "$STATS"
    info "排版调整完成：CSS $CSS_COUNT 个文件，HTML $HTML_COUNT 个文件"
}

# ---- 元数据修复 ----
CCEPUB_fix_metadata() {
    local WORK_DIR="$1"

    # OPF 元数据
    local OPF_FILE
    OPF_FILE=$(find "$WORK_DIR" -type f -iname "*.opf" | head -n 1 || true)
    if [ -n "$OPF_FILE" ]; then
        # 语言
        if grep -qi "<dc:language>" "$OPF_FILE" 2>/dev/null; then
            SED_I 's|<dc:language>[^<]*</dc:language>|<dc:language>zh-CN</dc:language>|i' "$OPF_FILE"
        else
            # 无 language 标签则插入
            SED_I '/<metadata>/a\  <dc:language>zh-CN</dc:language>' "$OPF_FILE"
        fi
        # 翻页方向
        SED_I 's|page-progression-direction="rtl"|page-progression-direction="ltr"|gi' "$OPF_FILE"
        # 设备特定
        if [ "$DEV_PAGINATION" = "ltr" ]; then
            if ! grep -qi "page-progression-direction" "$OPF_FILE" 2>/dev/null; then
                SED_I '/<spine /s|<spine |<spine page-progression-direction="ltr" |' "$OPF_FILE"
            fi
        fi
        success "OPF 元数据已修复"
    else
        warn "未找到 OPF 文件"
    fi

    # NCX 目录修复
    local NCX_FILES
    NCX_FILES=$(find "$WORK_DIR" -type f -name "toc.ncx" 2>/dev/null || true)
    if [ -n "$NCX_FILES" ]; then
        while IFS= read -r ncx_file; do
            # 修复异常 URL 片段引用（保留 src 的文件部分，清空 # 后片段）
            SED_I 's|src="\([^"#]*\)#[^"]*"|src="\1"|g' "$ncx_file" 2>/dev/null || true
            success "NCX 目录已修复: $(basename "$ncx_file")"
        done <<< "$NCX_FILES"
    fi

    # 重建导航目录
    if [ "$CFG_REBUILD_TOC" -eq 1 ]; then
        local NAV_FILE
        NAV_FILE=$(find "$WORK_DIR" -type f -name "nav.xhtml" 2>/dev/null | head -n 1 || true)
        if [ -n "$NAV_FILE" ]; then
            SED_I 's|<nav[^>]*>|<nav xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" role="doc-toc" epub:type="toc" id="nav" aria-labelledby="tocTitle">|g' "$NAV_FILE" 2>/dev/null || true
            success "导航目录已更新"
        fi
    fi
}
