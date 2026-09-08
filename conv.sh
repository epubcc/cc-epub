#!/bin/bash
# conv.sh — EPUB 繁→简 + 排版标准化（纯 Termux 原生版）
# 依赖: opencc-tools (提供 opencc 命令) + libopencc (运行时库), unzip, zip, sed, grep, findutils, perl（全部 Termux 原生包）
# 纯 Termux 原生运行，无需额外容器环境

set -uo pipefail

# ── Termux 环境检测 ──
IS_TERMUX=0
if [ -d "/data/data/com.termux" ] || [ -n "$TERMUX_VERSION" ]; then
    IS_TERMUX=1
    : "${TERMUX_PREFIX:=$PREFIX}"
    : "${TERMUX_HOME:=$HOME}"
fi

# ── 路径配置（Termux 原生存储路径自动探测） ──
W="${TERMUX_HOME:-$HOME}/w"

if [ -d "$HOME/storage/downloads" ]; then
    D="$HOME/storage/downloads"
elif [ -d "$HOME/storage/external-1/Download" ]; then
    D="$HOME/storage/external-1/Download"
elif [ -d "$HOME/storage/emulated/0/Download" ]; then
    D="$HOME/storage/emulated/0/Download"
elif [ -d "$HOME/Download" ]; then
    D="$HOME/Download"
else
    D="$HOME"
fi
A="$D/E-book"

# ── 工具函数 ──
die() { echo "❌ $*" >&2; exit 1; }
log() { echo "ℹ️  $*"; }
ok()  { echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }

trap 'rm -rf "$W" 2>/dev/null; termux-wake-unlock 2>/dev/null; exit 130' INT TERM

# ── 参数校验 ──
[ $# -ne 1 ] && { echo "用法: conv.sh <文件名.epub>"; exit 0; }

# ── 依赖检测（Termux 原生包） ──
command -v opencc >/dev/null 2>&1 || die "opencc 命令未找到，请安装: pkg install -y opencc-tools libopencc"
command -v unzip  >/dev/null 2>&1 || die "unzip 未安装: pkg install -y unzip"
command -v zip     >/dev/null 2>&1 || die "zip 未安装: pkg install -y zip"
command -v sed     >/dev/null 2>&1 || die "sed 未安装: pkg install -y sed"
command -v grep    >/dev/null 2>&1 || die "grep 未安装: pkg install -y grep"
command -v find    >/dev/null 2>&1 || die "find 未安装: pkg install -y findutils"
command -v perl    >/dev/null 2>&1 || die "perl 未安装: pkg install -y perl"

# ── Termux 唤醒锁 ──
if [ "$IS_TERMUX" = "1" ] && command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock
    log "已获取 Termux 唤醒锁"
fi

# ── 输入路径处理 ──
arg="$1"
[[ "$arg" = /* ]] && [ -f "$arg" ] && IN="$arg" || IN="$D/$arg"
[ ! -f "$IN" ] && IN="${IN%.*}.epub"; [ -f "$IN" ] || die "找不到文件: $IN"
NAME="$(basename "${IN%.*}")-简中.epub"
OUT="$W/$NAME"

# ── OpenCC 配置定位 ──
OCC=""
for p in \
    "$TERMUX_PREFIX/share/opencc/t2s.json" \
    "/usr/share/opencc/t2s.json" \
    "/usr/local/share/opencc/t2s.json" \
    "/data/data/com.termux/files/usr/share/opencc/t2s.json"; do
    [ -f "$p" ] && OCC="$p" && break
done
if [ -z "$OCC" ]; then
    OCC=$(find /data -name 't2s*.json' -type f 2>/dev/null | head -1)
    if [ -z "$OCC" ]; then
        OCC=$(find /usr -name 't2s*.json' -type f 2>/dev/null | head -1)
    fi
fi
[ -z "$OCC" ] && die "找不到 opencc 配置 t2s.json，请确认 libopencc 已安装"
log "OpenCC 配置: $OCC"

# ── 准备工作目录 ──
log "准备..."
rm -rf "$W"; mkdir -p "$W" "$A" && cd "$W" || die "工作目录异常"
log "解压..."; unzip -o "$IN" >/dev/null 2>&1 || die "解压失败"

# ── 清理垃圾文件 ──
find . \( -name '.DS_Store' -o -name 'Thumbs.db' -o -name '__MACOSX' \) -exec rm -rf {} + 2>/dev/null
find . -iname '*.svg' -size -1k -delete 2>/dev/null
find . \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
    -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.bmp' \) \
    -exec chmod 444 {} + 2>/dev/null

# ── 清除全角引导空格 ──
log "清除全角引导空格..."
while IFS= read -r -d '' f; do
    sed -E -i 's#<p([^>]*)>[[:space:] ]*#<p\1>#g' "$f" 2>/dev/null
done < <(find . \( -name '*.xhtml' -o -name '*.html' -o -name '*.htm' \) -print0 2>/dev/null)

# ── 检测排版方向并处理竖排 ──
log "检测排版方向..."
VERTICAL=0
if grep -rE 'writing-mode\s*:\s*(vertical|tb-rl|tb-lr)' . --include='*.css' --include='*.xhtml' --include='*.html' 2>/dev/null | grep -q .; then
    VERTICAL=1
    log "检测到竖排，转横排..."
    while IFS= read -r -d '' c; do
        [ -f "$c" ] || continue
        sed -i 's#writing-mode\s*:[^;{}]*;\s*##gI' "$c" 2>/dev/null
        sed -i 's#writing-mode\s*:[^;{}]*##gI' "$c" 2>/dev/null
        if command -v perl >/dev/null 2>&1; then
            perl -0777 -i -pe 's/\@page\s*\{[^}]*\}//g' "$c" 2>/dev/null
        else
            sed -i '/@page/,/}/d' "$c" 2>/dev/null
        fi
    done < <(find . -name '*.css' -print0 2>/dev/null)
    while IFS= read -r -d '' f; do
        sed -i 's#writing-mode\s*:[^;"]*;\s*##gI; s#writing-mode\s*:[^;"]*##gI' "$f" 2>/dev/null
    done < <(find . \( -name '*.xhtml' -o -name '*.html' \) -print0 2>/dev/null)
else
    log "未发现竖排，跳过"
fi

# ── 收集待处理文本文件 ──
TEXT_FILES=()
while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    grep -q 'data:image' "$f" 2>/dev/null && { log "跳过 Base64: $(basename "$f")"; continue; }
    TEXT_FILES+=("$f")
done < <(find . -type f \( -name '*.xhtml' -o -name '*.html' -o -name '*.htm' \) -size -5M -print0 2>/dev/null)

# ── 繁体特征检测 ──
FT_WORDS='軟體|網路|記憶體|這邊|時候|裡面|樣子|資訊|電腦|檔案|程式'
FT_HITS=$(grep -rohE "$FT_WORDS" . --include='*.xhtml' --include='*.html' 2>/dev/null | wc -l)
FT_HITS="${FT_HITS// /}"
[ "$FT_HITS" -gt 0 ] && log "检测到繁体特征词 $FT_HITS 处" || log "按繁→简执行"

# ── 空数组保护 ──
if [ "${#TEXT_FILES[@]}" -eq 0 ]; then
    warn "无可处理的文本文件，跳过繁→简转换"
    CC_OK=0; CC_FAIL=0
else
    log "将处理 ${#TEXT_FILES[@]} 个文件..."
    for f in "${TEXT_FILES[@]}"; do
        [ -f "$f" ] || continue
        grep -q '\x00' "$f" 2>/dev/null && tr -d '\000' < "$f" > "$f.clean" && mv "$f.clean" "$f"
    done
    CC_OK=0; CC_FAIL=0
    for f in "${TEXT_FILES[@]}"; do
        [ -f "$f" ] || continue; rm -f "$f.out"; success=0
        if opencc -c "$OCC" -i "$f" -o "$f.out" 2>/dev/null && [ -s "$f.out" ]; then
            success=1
        fi
        if [ "$success" = "1" ]; then
            orig=$(wc -c < "$f" | tr -d ' ')
            new=$(wc -c < "$f.out" | tr -d ' ')
            if [ "$new" -gt $((orig * 3)) ] 2>/dev/null; then
                warn "输出异常偏大，回滚: $(basename "$f")"
                rm -f "$f.out"; CC_FAIL=$((CC_FAIL + 1))
            else
                mv "$f.out" "$f"; CC_OK=$((CC_OK + 1))
            fi
        else
            CC_FAIL=$((CC_FAIL + 1))
            warn "转换失败(可能已是简体/纯英文): $(basename "$f")"
            rm -f "$f.out"
        fi
    done
    log "转换结果: 成功 $CC_OK, 失败 $CC_FAIL"
fi

# ── 自检：抽样多个文件 ──
if [ "$CC_OK" -gt 0 ] && [ "${#TEXT_FILES[@]}" -gt 0 ]; then
    if command -v shuf >/dev/null 2>&1; then
        SAMPLE_CMD="shuf"
    else
        SAMPLE_CMD="cat"
        warn "shuf 未安装，自检将按文件顺序抽样（非随机）"
    fi
    TOTAL_LEFT=0; SAMPLE_COUNT=0
    while IFS= read -r s; do
        [ -f "$s" ] || continue
        cnt=$(grep -ohE "$FT_WORDS" "$s" 2>/dev/null | wc -l)
        cnt="${cnt// /}"
        TOTAL_LEFT=$((TOTAL_LEFT + cnt))
        SAMPLE_COUNT=$((SAMPLE_COUNT + 1))
    done < <(printf '%s\n' "${TEXT_FILES[@]}" | $SAMPLE_CMD | head -n 5)
    if [ "$TOTAL_LEFT" -gt 10 ] 2>/dev/null; then
        warn "自检：抽样 $SAMPLE_COUNT 个文件中仍含 $TOTAL_LEFT 处繁体特征词，转换可能未完全生效"
    else
        ok "自检通过：繁体特征词已基本清除"
    fi
fi

# ── 清理残留 text-indent ──
log "清理残留 text-indent..."
while IFS= read -r -d '' c; do
    sed -i 's#text-indent\s*:[^;{}]*;\s*##gI; s#text-indent\s*:[^;{}]*##gI' "$c" 2>/dev/null
done < <(find . -name '*.css' -print0 2>/dev/null)
while IFS= read -r -d '' f; do
    sed -i 's#text-indent\s*:[^;"]*;\s*##gI; s#text-indent\s*:[^;"]*##gI' "$f" 2>/dev/null
done < <(find . \( -name '*.xhtml' -o -name '*.html' \) -print0 2>/dev/null)

# ── 写入排版规则 ──
log "写入排版规则..."
CSS_RULES='body{writing-mode:horizontal-tb!important}p,div>p,section>p{text-indent:2em!important;margin:0!important;padding:0!important;line-height:1.75!important}h1+p,h2+p,h3+p{text-indent:0!important}h1{text-align:center!important;text-indent:0!important;margin:2.5em 0 1.2em!important;font-weight:bold!important;font-size:1.4em!important}h2{text-align:center!important;text-indent:0!important;margin:2em 0 1em!important;font-weight:bold!important;font-size:1.2em!important}h3,h4{text-align:left!important;text-indent:0!important;margin:1.5em 0 0.6em!important;font-weight:bold!important}h5,h6{text-align:left!important;text-indent:0!important;margin:1em 0 0.4em!important;font-weight:bold!important}blockquote{text-indent:0!important;margin:0.8em 2em!important;font-style:italic!important}'

first_css=$(find . -name '*.css' 2>/dev/null | head -n 1)
if [ -n "$first_css" ]; then
    printf '%s\n' "$CSS_RULES" >> "$first_css"
else
    warn "未找到 CSS，注入到第一个 xhtml 的 <head>..."
    first_xhtml=$(find . \( -name '*.xhtml' -o -name '*.html' \) 2>/dev/null | head -n 1)
    if [ -n "$first_xhtml" ]; then
        sed -i "/<\/head>/i\\\n<style>$CSS_RULES</style>" "$first_xhtml" 2>/dev/null
    fi
fi

# ── 清理内联样式 ──
log "清理内联样式..."
while IFS= read -r -d '' f; do
    sed -i 's# style="text-align\s*:[^;"]*"##gI' "$f" 2>/dev/null
    sed -i 's# style="text-align\s*:[^;"]*;\s*# style="#gI' "$f" 2>/dev/null
    sed -i 's#;\s*text-align\s*:[^;"]*##gI' "$f" 2>/dev/null
    sed -i "s# style='text-align\s*:[^;']*'##gI" "$f" 2>/dev/null
    sed -i "s# style='text-align\s*:[^;']*;\s*# style='#gI" "$f" 2>/dev/null
    sed -i "s#;\s*text-align\s*:[^;']*##gI" "$f" 2>/dev/null
    sed -i 's#lang="zh-Hant"#lang="zh-CN"#gI;s#lang="zh-TW"#lang="zh-CN"#gI' "$f" 2>/dev/null
    sed -i 's#<p></p>##g;s#<p> </p>##g;s#<p>&nbsp;</p>##g' "$f" 2>/dev/null
done < <(find . \( -name '*.xhtml' -o -name '*.html' -o -name '*.htm' \) -print0 2>/dev/null)

# ── 更新 OPF 元数据 ──
log "更新 OPF 元数据..."
while IFS= read -r -d '' opf; do
    [ -f "$opf" ] || continue
    sed -i 's#<dc:language>zh-TW</dc:language>#<dc:language>zh-CN</dc:language>#gI' "$opf"
    sed -i 's#<dc:language>zh-Hant</dc:language>#<dc:language>zh-CN</dc:language>#gI' "$opf"
    sed -i 's#<dc:language>zh-HK</dc:language>#<dc:language>zh-CN</dc:language>#gI' "$opf"
    sed -i 's#xml:lang="zh-TW"#xml:lang="zh-CN"#gI' "$opf"
    sed -i 's#xml:lang="zh-Hant"#xml:lang="zh-CN"#gI' "$opf"
    sed -i 's#xml:lang="zh-HK"#xml:lang="zh-CN"#gI' "$opf"
    sed -i 's#page-progression-direction="rtl"#page-progression-direction="ltr"#gI' "$opf"
    sed -i 's#primary-writing-mode" content="vertical-rl"#primary-writing-mode" content="horizontal-tb"#gI' "$opf"
    sed -i 's#primary-writing-mode" content="vertical-lr"#primary-writing-mode" content="horizontal-tb"#gI' "$opf"
done < <(find . -name '*.opf' -print0 2>/dev/null)

# ── 清理转换残留临时文件 ──
find . -name '*.out' -delete 2>/dev/null
find . -name '*.clean' -delete 2>/dev/null

# ── 打包 ──
log "打包..."
TMPOUT="$W/.tmp_build_$$.epub"
if [ -f "mimetype" ]; then
    zip -X -0 "$TMPOUT" mimetype >/dev/null 2>&1
    zip -r -X -9 "$TMPOUT" . -x 'mimetype' -x '*.epub' >/dev/null 2>&1
else
    zip -r -X -9 "$TMPOUT" . -x '*.epub' >/dev/null 2>&1
fi
[ -f "$TMPOUT" ] || die "打包失败"
mv "$TMPOUT" "$OUT"
zip -T "$OUT" >/dev/null 2>&1 || die "校验失败"

# ── 输出结果 ──
sz=$(du -h "$OUT" | awk '{print $1}')
ok "$NAME ($sz) → E-book/"
log "输出路径: $A/$NAME"

if [ "$IS_TERMUX" = "1" ] && command -v termux-wake-unlock >/dev/null 2>&1; then
    termux-wake-unlock
    log "已释放 Termux 唤醒锁"
fi

rm -rf "$W"
