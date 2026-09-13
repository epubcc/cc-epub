#!/usr/bin/env bash
# conv.sh v3.15.0 - 港台繁体EPUB → Kindle 简中横排
# github.com/epubcc/cc-epub

set -uo pipefail

# ========== 常量 ==========
readonly VERSION="3.15.0"
readonly BASE_W="$HOME/w"
readonly OUT_DEFAULT="$HOME/storage/downloads/E-book"
readonly LOG="$HOME/cc-epub.log"
readonly CFG_CACHE="$HOME/.cc_config"
readonly RESUME_DB="$HOME/.cc_resume"
readonly LOCK_FILE="$HOME/.cc_epub.lock"
readonly VERSION_CACHE="$HOME/.cc_version_check"

# ========== 全局状态 ==========
KEEP=0
DRY=0
INTERACTIVE=0
RESUME=0
QUIET=0
OUTDIR=""
INFILE=""
OCC_CFG=""
W=""
START=0
LOCK_ACQUIRED=0

# ========== 工具函数 ==========
abort() {
  echo "✗ $*" >&2
  echo "[$(date '+%H:%M:%S')] ERROR: $*" >> "$LOG"
  exit 1
}

warn()  { [ "$QUIET" = "0" ] && echo "  ⚠ $*" >&2; echo "[$(date '+%H:%M:%S')] WARN: $*" >> "$LOG"; }
info()  { [ "$QUIET" = "0" ] && echo "  $*" >&2; echo "[$(date '+%H:%M:%S')] $*" >> "$LOG"; }
ok()    { [ "$QUIET" = "0" ] && echo "  ✓ $*" >&2; echo "[$(date '+%H:%M:%S')] OK: $*" >> "$LOG"; }

_step_count=0
step() {
  [ "$QUIET" = "1" ] && return 0
  _step_count=$((_step_count + 1))
  [ "$_step_count" -gt 1 ] && echo ""
  echo "[$1] $2"
}

cleanup() {
  [ "$KEEP" = "1" ] && return 0
  [ -z "$W" ] || [ ! -d "$W" ] && return 0
  if [[ "$W" == "$BASE_W/$$"* ]]; then
    rm -rf "$W"
  fi
}

# ========== 文件锁 ==========
acquire_lock() {
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if flock -n 9; then
      echo $$ >&9
      LOCK_ACQUIRED=1
    else
      local other_pid
      other_pid=$(cat "$LOCK_FILE" 2>/dev/null)
      abort "另一个实例正在运行 (PID: ${other_pid:-未知})"
    fi
  else
    if [ -f "$LOCK_FILE" ] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
      abort "另一个实例正在运行 (PID: $(cat "$LOCK_FILE"))"
    fi
    echo $$ > "$LOCK_FILE"
    LOCK_ACQUIRED=1
  fi
}

release_lock() {
  [ "$LOCK_ACQUIRED" = "1" ] || return 0
  command -v flock >/dev/null 2>&1 && flock -u 9 2>/dev/null
  rm -f "$LOCK_FILE"
  LOCK_ACQUIRED=0
}

trap 'cleanup; release_lock' EXIT INT TERM

# ========== 自洁 ==========
self_clean() {
  [ -d "$BASE_W" ] || return 0
  local now cutoff d
  now=$(date +%s)
  cutoff=$((now - 86400))
  for d in "$BASE_W"/*/; do
    [ -d "$d" ] || continue
    if [ "$(stat -c%Y "$d" 2>/dev/null || echo 0)" -lt "$cutoff" ]; then
      rm -rf "$d"
      echo "[$(date '+%H:%M:%S')] 自洁: $d" >> "$LOG"
    fi
  done
}

# ========== 版本检查（每周一次） ==========
version_check() {
  [ "$QUIET" = "1" ] && return 0
  local now last latest
  now=$(date +%s)
  last=$(cat "$VERSION_CACHE" 2>/dev/null | head -1 | tr -d '[:space:]')
  [ -n "$last" ] && [ "$((now - last))" -lt 604800 ] && return 0

  if command -v curl >/dev/null 2>&1; then
    latest=$(curl -fsSL --max-time 5 "https://raw.githubusercontent.com/epubcc/cc-epub/main/VERSION" 2>/dev/null | head -1 | tr -d '[:space:]')
  elif command -v wget >/dev/null 2>&1; then
    latest=$(wget -q --timeout=5 -O - "https://raw.githubusercontent.com/epubcc/cc-epub/main/VERSION" 2>/dev/null | head -1 | tr -d '[:space:]')
  fi

  if [ -n "$latest" ]; then
    echo "$now" > "$VERSION_CACHE"
    [ "$latest" != "$VERSION" ] && echo "" && echo "  📦 新版本可用: v$VERSION → $latest (zh --update)" && echo ""
  fi
}

# ========== 参数解析 ==========
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)     KEEP=1 ;;
    -i)         INTERACTIVE=1 ;;
    --resume)   RESUME=1 ;;
    -o)         shift; OUTDIR="$1" ;;
    --update)
      [ -f "$HOME/.local/bin/zh" ] && cp "$HOME/.local/bin/zh" "$HOME/.local/bin/zh.bak" 2>/dev/null
      info "更新中..."
      if command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 10 "https://raw.githubusercontent.com/epubcc/cc-epub/main/conv.sh" -o "$HOME/.local/bin/zh" \
          && chmod +x "$HOME/.local/bin/zh" && ok "更新成功 (备份: zh.bak)" || abort "更新失败"
      elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=10 "https://raw.githubusercontent.com/epubcc/cc-epub/main/conv.sh" -O "$HOME/.local/bin/zh" \
          && chmod +x "$HOME/.local/bin/zh" && ok "更新成功 (备份: zh.bak)" || abort "更新失败"
      else
        abort "需要 curl 或 wget"
      fi
      exit 0 ;;
    --check)
      echo "cc-epub v$VERSION 环境诊断"
      echo "─────────────────────────────"
      for c in opencc unzip zip perl; do
        command -v "$c" >/dev/null 2>&1 && echo "  ✓ $c" || echo "  ✗ $c (缺失)"
      done
      command -v flock >/dev/null 2>&1 && echo "  ✓ flock" || echo "  · flock (可选)"
      [ -f "$CFG_CACHE" ] && echo "  ✓ OpenCC: $(cat "$CFG_CACHE")" || echo "  · OpenCC: 未缓存"
      echo "  存储: $([ -d "$HOME/storage/downloads" ] && echo '可访问' || echo '不可访问')"
      echo "  输出: $([ -d "$OUT_DEFAULT" ] && echo '存在' || echo '不存在')"
      exit 0 ;;
    -n) DRY=1 ;;
    -q|--quiet) QUIET=1 ;;
    -v|--version) echo "conv.sh v$VERSION"; exit 0 ;;
    -h|--help)
      echo "用法: zh [选项] <文件.epub>"
      echo "  -n         试运行"
      echo "  -i         交互确认"
      echo "  -q         静默模式"
      echo "  -o DIR     输出目录"
      echo "  --keep     保留临时文件"
      echo "  --resume   断点续传（跳过已完成的文件）"
      echo "  --check    环境诊断"
      echo "  --update   更新"
      exit 0 ;;
    --) shift; [ -z "$INFILE" ] && INFILE="$1"; break ;;
    -*) abort "未知选项: $1 (-h 查看帮助)" ;;
    *)  [ -z "$INFILE" ] && INFILE="$1" || abort "多余参数: $1" ;;
  esac
  shift
done

[ -z "$INFILE" ] && abort "请指定文件"
[ -d "$INFILE" ] && abort "不支持目录，请指定单个 .epub 文件"

START=$(date +%s)
self_clean
acquire_lock
version_check

# ========== 依赖检查 ==========
for cmd in opencc unzip zip perl; do
  command -v "$cmd" >/dev/null 2>&1 || abort "缺少依赖: $cmd (运行 deploy.sh)"
done

# ========== OpenCC 配置 ==========
if [ -f "$CFG_CACHE" ]; then
  OCC_CFG=$(cat "$CFG_CACHE")
else
  for cfg in tw2s hk2s t2s; do
    if echo "這是一個臺灣測試" | opencc -c "$cfg" 2>/dev/null | grep -q "这"; then
      OCC_CFG="$cfg"; break
    fi
  done
  [ -n "$OCC_CFG" ] && echo "$OCC_CFG" > "$CFG_CACHE"
fi
[ -z "$OCC_CFG" ] && abort "OpenCC 无可用配置 (pkg reinstall libopencc opencc-tools)"

# ========== 路径解析（subshell 不污染 cwd） ==========
resolve_path() {
  local p="$1"
  p="${p/#\~/$HOME}"
  if [[ "$p" != /* ]]; then
    p="$(pwd)/$p"
  fi
  ( cd "$(dirname "$p")" 2>/dev/null && echo "$(pwd)/$(basename "$p")" ) || echo "$p"
}

# ========== 并行转换 ==========
parallel_convert() {
  local w="$1" nproc f file_list total pids=()
  nproc=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
  [ "$nproc" -gt 4 ] && nproc=4

  file_list="$w/.cc_files"
  : > "$file_list"

  while IFS= read -r f; do
    [ -f "$f" ] || continue
    perl -CSD -ne 'exit 0 if /[\x{4e00}-\x{9fa5}]/; END { exit 1 }' "$f" || continue
    echo "$f" >> "$file_list"
  done < <(find "$w" \( -name '*.html' -o -name '*.htm' -o -name '*.xml' -o -name '*.opf' \) -type f)

  total=$(wc -l < "$file_list" 2>/dev/null || echo 0)
  [ "$total" -eq 0 ] && return 0

  while IFS= read -r f; do
    (
      opencc -c "$OCC_CFG" -i "$f" -o "$f.__cc" >/dev/null 2>&1
      if [ -s "$f.__cc" ]; then
        mv "$f.__cc" "$f"
      else
        rm -f "$f.__cc"
      fi
    ) &
    pids+=($!)
    if [ "${#pids[@]}" -ge "$nproc" ]; then
      for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
      pids=()
    fi
  done < "$file_list"

  for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null; done
  rm -f "$file_list"
  echo "$total"
}

# ========== EPUB 预检 ==========
epub_preflight() {
  local epub="$1" mt sz
  sz=$(stat -c%s "$epub" 2>/dev/null || echo 0)
  [ "$sz" -lt 100 ] && { warn "文件过小 (<100B)"; return 1; }
  unzip -l "$epub" >/dev/null 2>&1 || { warn "不是有效的 ZIP/EPUB"; return 1; }

  mt=$(unzip -p "$epub" mimetype 2>/dev/null | head -1 | tr -d '\0\r\n')
  if [ -z "$mt" ] || [ "$mt" != "application/epub+zip" ]; then
    warn "mimetype 异常: '${mt:-空}' (可能损坏)"
    return 1
  fi

  unzip -l "$epub" 2>/dev/null | grep -qi 'container.xml' || { warn "缺少 container.xml"; return 1; }
  return 0
}

# ========== 封面检测 ==========
detect_cover() {
  local w="$1" opf cover_id cover_href cover_path fallback sq
  opf=$(find "$w" -name '*.opf' -type f | head -1)
  [ -z "$opf" ] && return 1

  sq=$(printf "'")  # 单引号字符，避免 shell 转义地狱

  # 解析 meta name="cover" content="xxx"
  cover_id=$(perl -CSD -ne '
    my $sq = chr(39);
    if (/meta[^>]*(?:name\s*=\s*["${sq}]cover["${sq}]|content\s*=\s*["${sq}])/i) {
      if (/name\s*=\s*["${sq}]cover["${sq}][^>]*content\s*=\s*["${sq}]?([^"${sq}\s>]+)/i) { print $1; }
      elsif (/content\s*=\s*["${sq}]?([^"${sq}\s>]+)["${sq}]?\s+name\s*=\s*["${sq}]cover["${sq}]/i) { print $1; }
    }
  ' "$opf" 2>/dev/null)

  if [ -z "$cover_id" ]; then
    # fallback: 找第一个 image media-type 的 item id
    cover_id=$(perl -CSD -ne '
      my $sq = chr(39);
      if (/item[^>]*id\s*=\s*["${sq}]?([^"${sq}\s>]+)["${sq}]?\s+[^>]*media-type\s*=\s*["${sq}]image\//i) { print $1; exit; }
    ' "$opf" 2>/dev/null)
  fi

  if [ -n "$cover_id" ]; then
    cover_href=$(perl -CSD -ne '
      my $sq = chr(39);
      if (/item[^>]*id\s*=\s*["${sq}]'"$cover_id"'["${sq}][^>]*href\s*=\s*["${sq}]?([^"${sq}\s>]+)/i) { print $1; }
      elsif (/item[^>]*href\s*=\s*["${sq}]?([^"${sq}\s>]+)["${sq}]?\s+[^>]*id\s*=\s*["${sq}]'"$cover_id"'["${sq}]/i) { print $1; }
    ' "$opf" 2>/dev/null)
    if [ -n "$cover_href" ]; then
      cover_path="$(dirname "$opf")/$cover_href"
      [ -f "$cover_path" ] && echo "$cover_path" && return 0
    fi
  fi

  fallback=$(find "$w" \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \) -type f | head -1)
  [ -n "$fallback" ] && echo "$fallback" && return 0
  return 1
}

# ========== 单文件转换 ==========
convert_one() {
  local epub="$1" outdir="${2:-$OUT_DEFAULT}"
  local name out sz sz_b img_bytes img_pct total fc fx
  local cover_img opf_file cover_rel kcss

  epub=$(resolve_path "$epub")
  [ ! -f "$epub" ] && { warn "不存在: $epub"; return 1; }

  if [ "$RESUME" = "1" ] && grep -qxF "$(basename "$epub")" "$RESUME_DB" 2>/dev/null; then
    info "跳过(已完成): $(basename "$epub")"
    return 0
  fi

  if [ "$DRY" = "1" ]; then
    echo "Dry-run: $(basename "$epub")"
    unzip -l "$epub" 2>/dev/null | head -20
    echo "  ..."
    return 0
  fi

  if [ "$INTERACTIVE" = "1" ]; then
    echo ""; echo "  文件: $(basename "$epub")"; echo "  大小: $(du -h "$epub" | awk '{print $1}')"
    read -r -p "  转换？[Y/n] " c
    case "$c" in [nN]*) return 0 ;; esac
  fi

  epub_preflight "$epub" || return 1

  W="$BASE_W/$$/"
  mkdir -p "$W" || { warn "无法创建工作目录"; return 1; }
  cd "$W" || { warn "无法进入工作目录"; return 1; }
  step "1/7" "解包 $(basename "$epub")"
  unzip -o -q "$epub" -d "$W" || { warn "解包失败"; cd "$HOME"; return 1; }

  name=$(basename "$epub")
  name="${name%.*}"
  name=$(printf '%s' "$name" | perl -CSD -pe 's/[^\p{Han}\w._-]//g; s/\s+/_/g; s/_+/_/g')
  [ -z "$name" ] && name="book_$$"
  name="${name}-简中.epub"
  out="$W/$name"

  step "2/7" "清理竖排与字体引用"
  find "$W" \( -name '*.css' -o -name '*.html' -o -name '*.htm' -o -name '*.xml' -o -name '*.opf' \) -type f -exec perl -CSD -pi -e '
    my @p = qw(writing-mode text-orientation glyph-orientation-vertical text-combine-upright orientation -webkit-writing-mode -epub-writing-mode);
    my $re = join("|", @p);
    s/(?:^|;|\{)\s*[^;{]*\b(?:$re)\b[^;]*;?//gi;
    s/font-family\s*:\s*[^;"]*(serif|sans-serif|monospace)[^;"]*//gi;
    s/@font-face\s*\{[^}]*\}//gi;
  ' {} + 2>/dev/null

  step "3/7" "繁简转换 ($OCC_CFG, 并行)"
  total=$(parallel_convert "$W")
  info "转换了 $total 个文件"

  step "4/7" "注入 Kindle 样式"
  # Kindle 横排优化 CSS：强制 serif、水平书写、行高、首行缩进
  kcss='body{font-family:serif!important;writing-mode:horizontal-tb!important;line-height:1.8!important}p,div>p{text-indent:2em!important}h1,h2,h3{font-family:serif!important}img{max-width:100%!important}'
  echo "$kcss" > "$W/_k.css"
  fc=$(find "$W" -name '*.css' -not -name '.*' -type f | head -1)
  if [ -n "$fc" ]; then
    cat "$W/_k.css" >> "$fc"
  else
    fx=$(find "$W" -name '*.html' -o -name '*.htm' | head -1)
    [ -n "$fx" ] && perl -CSD -pi -e 'BEGIN{undef $/;} my $c=do{open my $h,"'"$W/_k.css"'";<my $h>}; s|</head>|<style>'"$c"'</style></head>|i' "$fx"
  fi

  step "5/7" "修正元数据与封面"
  find "$W" \( -name '*.opf' -o -name '*.html' \) -type f -exec perl -CSD -pi -e '
    s|<dc:language>[^<]*</dc:language>|<dc:language>zh-CN</dc:language>|gi;
    s|xml:lang="[^"]*"|xml:lang="zh-CN"|gi;
    s|lang="[^"]*"|lang="zh-CN"|gi;
  ' {} + 2>/dev/null

  if cover_img=$(detect_cover "$W"); then
    opf_file=$(find "$W" -name '*.opf' -type f | head -1)
    if [ -n "$opf_file" ] && ! grep -qi 'cover' "$opf_file"; then
      cover_rel=$(echo "$cover_img" | sed "s|$W/||")
      perl -CSD -pi -e 's|(<metadata[^>]*>)|$1<meta name="cover" content="cover-img"/>|i' "$opf_file"
      perl -CSD -pi -e 's|(<manifest[^>]*>)|$1<item id="cover-img" href="'"$cover_rel"'" media-type="image/jpeg"/>|i' "$opf_file" 2>/dev/null || true
      ok "封面 → $(basename "$cover_img")"
    fi
  fi

  step "6/7" "打包 EPUB"
  cd "$W" || { warn "打包时无法进入工作目录"; return 1; }
  zip -X -0 "$out" mimetype >/dev/null 2>&1
  zip -r -X -9 "$out" . \
    -x 'mimetype' -x "$name" -x '.cc_files' \
    -x '*.DS_Store' -x '._*' -x '_k.css' -x '__cc*' -x '.cc_*' \
    >/dev/null 2>&1
  [ -f "$out" ] || { warn "打包失败"; cd "$HOME"; return 1; }

  sz=$(du -h "$out" | awk '{print $1}')
  sz_b=$(stat -c%s "$out" 2>/dev/null || echo 0)
  [ "$sz_b" -gt 209715200 ] && warn "文件 ${sz} > 200MB！Send to Kindle 网页版无法推送"

  if [ "$sz_b" -gt 0 ]; then
    img_bytes=$(find "$W" \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.gif' \) -type f -exec du -cb {} + 2>/dev/null | tail -1 | awk '{print $1}')
    if [ -n "$img_bytes" ] && [ "$img_bytes" -gt 10485760 ]; then
      img_pct=$((img_bytes * 100 / sz_b))
      [ "$img_pct" -gt 70 ] && warn "图片占比 ${img_pct}%，如推送失败可尝试压缩图片"
    fi
  fi

  step "7/7" "输出"
  mkdir -p "$outdir"
  cp "$out" "$outdir/"
  ok "$name ($sz) → $outdir/"

  echo "$(basename "$epub")" >> "$RESUME_DB" 2>/dev/null

  cd "$HOME" 2>/dev/null
  rm -rf "$W"
  W=""
  return 0
}

# ========== 入口 ==========
convert_one "$INFILE" "${OUTDIR:-$OUT_DEFAULT}"
echo ""
echo "完成 ($(($(date +%s) - START))s)"
