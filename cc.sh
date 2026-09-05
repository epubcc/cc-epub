#!/data/data/com.termux/files/usr/bin/bash
# =============================================================================
# cc-epub v2.0 - 核心转换脚本 (Kindle 深度适配版)
# 功能：EPUB 繁体转简体、竖排转横排、Kindle 防 PDF 化清洗、图片压缩
# 用法：cc <书名关键词>  或  EPUB_BACKUP=on cc <书名>
# =============================================================================

set -euo pipefail

CC_VERSION="2.0"

BASE_DIR="${EPUB_BASE_DIR:-$HOME/storage/downloads}"
OUT_BASE="$BASE_DIR/E-book"
TMP_DIR=""

# --- 颜色工具函数 ---
log()    { echo -e "\033[1;34m[i]\033[0m $*"; }
ok()     { echo -e "\033[1;32m[OK]\033[0m $*"; }
err()    { echo -e "\033[1;31m[ERR]\033[0m $*"; exit 1; }
warn()   { echo -e "\033[1;33m[WARN]\033[0m $*"; }
info()   { echo -e "\033[1;36m[INFO]\033[0m $*"; }

# --- 清理临时目录 ---
cleanup() {
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# --- 智能查找书籍文件 ---
find_book() {
  local query="$1"
  local -a candidates=()

  if [[ ! -d "$BASE_DIR" ]]; then
    err "下载目录不存在！请先执行: termux-setup-storage"
  fi

  # 1. 精确匹配（支持直接传完整路径）
  if [[ -f "$BASE_DIR/$query" ]]; then
    echo "$(basename "$BASE_DIR/$query")"
    return 0
  fi

  # 2. 模糊匹配
  shopt -s nullglob
  for file in "$BASE_DIR"/*"${query}"*.epub; do
    candidates+=("$(basename "$file")")
  done
  shopt -u nullglob

  if [[ ${#candidates[@]} -eq 0 ]]; then
    err "在 $BASE_DIR 中未找到包含 '$query' 的 EPUB 文件"
  fi

  if [[ ${#candidates[@]} -eq 1 ]]; then
    echo "${candidates[0]}"
    return 0
  fi

  # 3. 多个结果，让用户选择
  warn "找到多个匹配项："
  for i in "${!candidates[@]}"; do
    echo "   $((i+1)). ${candidates[$i]}"
  done
  echo -n "请输入编号选择 [1]: "
  read -r choice
  choice=${choice:-1}

  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#candidates[@]} )); then
    echo "${candidates[$((choice-1))]}"
  else
    err "无效选择"
  fi
}

# --- 检查运行环境 ---
cc_doctor() {
  log "正在检查运行环境..."
  local env_ok=1
  for cmd in unzip zip opencc; do
    if command -v "$cmd" &>/dev/null; then
      log "   $cmd 可用"
    else
      err "   $cmd 缺失（请运行: pkg install $cmd）"
      env_ok=0
    fi
  done
  if command -v mogrify &>/dev/null; then
    log "   imagemagick (mogrify) 可用"
  else
    warn "   imagemagick 未安装（图片压缩功能将不可用，安装: pkg install imagemagick）"
  fi
  if (( env_ok == 1 )); then
    ok "环境检查通过，可以开始转换。"
  else
    err "环境检查未通过。"
  fi
}

# --- 显示用法 ---
usage() {
  cat << 'EOF'
用法: cc <书名关键词>
   或: cc [选项]

选项:
   --doctor    检查运行环境依赖
   --list      列出 Downloads 目录下的所有 EPUB 文件
   --version   显示版本号
   -h, --help  显示此帮助信息

环境变量:
   EPUB_BACKUP=on   转换前备份原文件
   EPUB_IMG=off     跳过图片压缩（画册模式）
   EPUB_BASE_DIR    自定义下载目录（默认: ~/storage/downloads）

示例:
   cc 三体                    # 查找并转换包含"三体"的书籍
   EPUB_BACKUP=on cc 三体      # 转换前备份原文件
   EPUB_IMG=off cc 三体        # 画册模式，跳过图片压缩
   EPUB_BASE_DIR=/sdcard/cc cc 三体  # 指定其他目录
EOF
}

# --- 主程序 ---
main() {
  case "$1" in
    --doctor) cc_doctor; exit 0 ;;
    --list)
      echo "Downloads 目录下的 EPUB 文件："
      find "$BASE_DIR" -maxdepth 1 -type f -iname "*.epub" -exec basename {} \; | nl
      exit 0
      ;;
    --version)
      echo "cc-epub $CC_VERSION (Kindle 深度适配版)"
      exit 0
      ;;
    -h|--help) usage; exit 0 ;;
    "") usage; exit 1 ;;
  esac

  log "正在查找书籍: $1"
  local filename
  filename=$(find_book "$1") || exit 1

  local epub_path="$BASE_DIR/$filename"
  local book_name="${filename%.epub}"
  local out_dir="$OUT_BASE"
  local output_path="$out_dir/${book_name}-cc.epub"

  # --- 备份原文件 ---
  if [[ "${EPUB_BACKUP:-off}" == "on" ]]; then
    log "正在备份原文件..."
    if cp "$epub_path" "${epub_path}.bak"; then
      ok "已备份至 ${epub_path}.bak"
    else
      warn "备份失败，继续执行..."
    fi
  fi

  mkdir -p "$out_dir" || { err "无法创建输出目录: $out_dir"; }

  TMP_DIR=$(mktemp -d) || { err "无法创建临时目录"; }

  log "正在解包: $filename"
  rm -rf "$TMP_DIR"/*
  if ! unzip -q "$epub_path" -d "$TMP_DIR"; then
    err "解包失败！文件可能已损坏或不是有效的 EPUB 格式。"
  fi

  # --- 步骤1：繁简转换 ---
  log "1. 正在进行繁简转换 (tw2sp)..."
  local converted_count=0
  while IFS= read -r -d '' file; do
    if opencc -c tw2sp -i "$file" -o "$file.tmp"; then
      mv "$file.tmp" "$file"
      ((converted_count++)) || true
    else
      rm -f "$file.tmp"
    fi
  done < <(find "$TMP_DIR" -type f \( -name "*.html" -o -name "*.htm" -o -name "*.xhtml" -o -name "*.ncx" -o -name "*.opf" \) -print0)

  if (( converted_count == 0 )); then
    warn "未找到需要转换的文本文件，可能已是简体。"
  fi

  # --- 步骤2：术语补丁（港台特有词汇二次替换） ---
  log "2. 正在应用术语补丁（港台词汇修正）..."
  find "$TMP_DIR" -type f \( -name "*.html" -o -name "*.htm" -o -name "*.xhtml" -o -name "*.ncx" -o -name "*.opf" \) -exec sed -i \
    -e 's/计画/计划/g' \
    -e 's/網路/网络/g' \
    -e 's/网路/网络/g' \
    -e 's/軟體/软件/g' \
    -e 's/软体/软件/g' \
    -e 's/程式/程序/g' \
    -e 's/程式碼/程序代码/g' \
    -e 's/列印/打印/g' \
    -e 's/列印機/打印机/g' \
    -e 's/位元組/字节/g' \
    -e 's/位元组/字节/g' \
    -e 's/位元/比特/g' \
    -e 's/位元速率/比特率/g' \
    -e 's/行銷/营销/g' \
    -e 's/行销/营销/g' \
    -e 's/網誌/博客/g' \
    -e 's/网志/博客/g' \
    -e 's/部落格/博客/g' \
    -e 's/連線/连接/g' \
    -e 's/连线/连接/g' \
    -e 's/伺服器/服务器/g' \
    -e 's/資訊/信息/g' \
    -e 's/资讯/信息/g' \
    -e 's/硬碟/硬盘/g' \
    -e 's/記憶體/内存/g' \
    -e 's/记忆体/内存/g' \
    -e 's/螢幕/屏幕/g' \
    -e 's/萤幕/屏幕/g' \
    -e 's/滑鼠/鼠标/g' \
    -e 's/光碟/光盘/g' \
    -e 's/光碟機/光驱/g' \
    -e 's/滑鼠墊/鼠标垫/g' \
    -e 's/滑鼠鍵盤/鼠标键盘/g' \
    -e 's/觸控/触控/g' \
    -e 's/觸控屏/触摸屏/g' \
    -e 's/觸控筆/触控笔/g' \
    -e 's/鍵盤/键盘/g' \
    -e 's/鍵帽/键帽/g' \
    -e 's/鍵入/键入/g' \
    {} \; 2>/dev/null || true

  # --- 步骤3：标点符号清洗（繁体标点 → 简体标点） ---
  log "3. 正在清洗标点符号（繁体标点修正）..."
  find "$TMP_DIR" -type f \( -name "*.html" -o -name "*.htm" -o -name "*.xhtml" -o -name "*.ncx" -o -name "*.opf" \) -exec sed -i \
    -e 's/「/"/g' \
    -e 's/」/"/g' \
    -e "s/『/'/g" \
    -e "s/』/'/g" \
    -e 's/【/[/g' \
    -e 's/】/]/g' \
    -e 's/（/(/g' \
    -e 's/）/)/g' \
    -e 's/〔/[/g' \
    -e 's/〕/]/g' \
    -e 's/〈/</g' \
    -e 's/〉/>/g' \
    -e 's/《/</g' \
    -e 's/》/>/g' \
    -e 's/．/./g' \
    -e 's/，/,/g' \
    -e 's/。/./g' \
    -e 's/？/?/g' \
    -e 's/！/!/g' \
    -e 's/：/:/g' \
    -e 's/；/;/g' \
    {} \; 2>/dev/null || true

  # --- 步骤4：竖排转横排（CSS 文件） ---
  log "4. 正在处理竖排转横排（CSS）..."
  find "$TMP_DIR" -type f -name "*.css" -exec sed -i \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-rl[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-rl[[:space:]]*!important/writing-mode: horizontal-tb !important/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-lr[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-lr[[:space:]]*!important/writing-mode: horizontal-tb !important/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*sideways-rl[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*sideways-lr[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/-epub-writing-mode[[:space:]]*:[[:space:]]*vertical-rl[[:space:]]*;/-epub-writing-mode: horizontal-tb;/g' \
    -e 's/-epub-writing-mode[[:space:]]*:[[:space:]]*vertical-lr[[:space:]]*;/-epub-writing-mode: horizontal-tb;/g' \
    {} \; 2>/dev/null || true

  # --- 步骤5：竖排转横排（HTML/XHTML 内联样式） ---
  log "5. 正在处理竖排转横排（HTML 内联样式）..."
  find "$TMP_DIR" -type f \( -name "*.html" -o -name "*.htm" -o -name "*.xhtml" \) -exec sed -i \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-rl[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-rl[[:space:]]*!important/writing-mode: horizontal-tb !important/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-lr[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*vertical-lr[[:space:]]*!important/writing-mode: horizontal-tb !important/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*sideways-rl[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    -e 's/writing-mode[[:space:]]*:[[:space:]]*sideways-lr[[:space:]]*;/writing-mode: horizontal-tb;/g' \
    {} \; 2>/dev/null || true

  # --- 步骤6：清理残留竖排标记 ---
  log "6. 正在清理残留竖排标记..."
  find "$TMP_DIR" -type f \( -name "*.css" -o -name "*.html" -o -name "*.htm" -o -name "*.xhtml" \) -exec sed -i \
    -e '/writing-mode/d' \
    -e '/-epub-writing-mode/d' \
    -e '/text-orientation/d' \
    {} \; 2>/dev/null || true

  # --- 步骤7：字体统一化 ---
  log "7. 正在统一字体（替换繁体专用字体为 serif）..."

  # 7a. CSS 文件中的 font-family
  find "$TMP_DIR" -type f -name "*.css" -exec sed -i -E \
    -e 's/font-family[[:space:]]*:[[:space:]]*"[^"]*(MingLiu|PMingLiu|標楷體|新細明體|細明體|DFKaiShu|BiauKai|PMingLiU|Microsoft JhengHei|Microsoft YaHei|SimSun|SimHei|Noto Sans CJK SC|Noto Serif CJK SC|WenQuanYi Zen Hei|WenQuanYi Micro Hei|Source Han Sans|Source Han Serif|Hiragino Sans GB|PingFang SC|Apple LiGothic|Apple MyungJo|KaiTi|FangSong|SimSun-ExtB|SimHei-ExtB|AR PL UKai|AR PL UMing)[^"]*"/font-family: serif/g' \
    -e "s/font-family[[:space:]]*:[[:space:]]*'[^']*(MingLiu|PMingLiu|標楷體|新細明體|細明體|DFKaiShu|BiauKai|PMingLiU|Microsoft JhengHei|Microsoft YaHei|SimSun|SimHei|Noto Sans CJK SC|Noto Serif CJK SC|WenQuanYi Zen Hei|WenQuanYi Micro Hei|Source Han Sans|Source Han Serif|Hiragino Sans GB|PingFang SC|Apple LiGothic|Apple MyungJo|KaiTi|FangSong|SimSun-ExtB|SimHei-ExtB|AR PL UKai|AR PL UMing)[^']*'/font-family: serif/g" \
    {} \; 2>/dev/null || true

  # 7b. HTML/XHTML 内联样式中的 font-family
  find "$TMP_DIR" -type f \( -name "*.html" -o -name "*.htm" -o -name "*.xhtml" \) -exec sed -i -E \
    -e 's/style="([^"]*)font-family[[:space:]]*:[[:space:]]*"[^"]*(MingLiu|PMingLiu|標楷體|新細明體|細明體|DFKaiShu|BiauKai|PMingLiU|Microsoft JhengHei|Microsoft YaHei|SimSun|SimHei|Noto Sans CJK SC|Noto Serif CJK SC|WenQuanYi Zen Hei|WenQuanYi Micro Hei|Source Han Sans|Source Han Serif|Hiragino Sans GB|PingFang SC|Apple LiGothic|Apple MyungJo|KaiTi|FangSong|SimSun-ExtB|SimHei-ExtB|AR PL UKai|AR PL UMing)[^"]*"/style="\1font-family: serif;"/g' \
    -e "s/style='([^']*)font-family[[:space:]]*:[[:space:]]*'[^']*(MingLiu|PMingLiu|標楷體|新細明體|細明體|DFKaiShu|BiauKai|PMingLiU|Microsoft JhengHei|Microsoft YaHei|SimSun|SimHei|Noto Sans CJK SC|Noto Serif CJK SC|WenQuanYi Zen Hei|WenQuanYi Micro Hei|Source Han Sans|Source Han Serif|Hiragino Sans GB|PingFang SC|Apple LiGothic|Apple MyungJo|KaiTi|FangSong|SimSun-ExtB|SimHei-ExtB|AR PL UKai|AR PL UMing)[^']*'/style='\\1font-family: serif;'/g" \
    {} \; 2>/dev/null || true

  # 7c. HTML 标签中独立的 font-family 属性
  find "$TMP_DIR" -type f \( -name "*.html" -o -name "*.htm" -o -name "*.xhtml" \) -exec sed -i -E \
    -e 's/font-family[[:space:]]*=[[:space:]]*"[^"]*(MingLiu|PMingLiu|標楷體|新細明體|細明體|DFKaiShu|BiauKai|PMingLiU|Microsoft JhengHei|Microsoft YaHei|SimSun|SimHei|Noto Sans CJK SC|Noto Serif CJK SC|WenQuanYi Zen Hei|WenQuanYi Micro Hei|Source Han Sans|Source Han Serif|Hiragino Sans GB|PingFang SC|Apple LiGothic|Apple MyungJo|KaiTi|FangSong|SimSun-ExtB|SimHei-ExtB|AR PL UKai|AR PL UMing)[^"]*"/font-family="serif"/g' \
    -e "s/font-family[[:space:]]*=[[:space:]]*'[^']*(MingLiu|PMingLiu|標楷體|新細明體|細明體|DFKaiShu|BiauKai|PMingLiU|Microsoft JhengHei|Microsoft YaHei|SimSun|SimHei|Noto Sans CJK SC|Noto Serif CJK SC|WenQuanYi Zen Hei|WenQuanYi Micro Hei|Source Han Sans|Source Han Serif|Hiragino Sans GB|PingFang SC|Apple LiGothic|Apple MyungJo|KaiTi|FangSong|SimSun-ExtB|SimHei-ExtB|AR PL UKai|AR PL UMing)[^']*'/font-family='serif'/g" \
    {} \; 2>/dev/null || true

  # --- 步骤8：Kindle 深度清洗（关键修复：防止 Kindle 强制转 PDF） ---
  log "8. 正在执行 Kindle 防 PDF 化清洗..."
  # 亚马逊 KindleGen 引擎遇到 position:absolute/fixed、float、display:flex 等
  # 复杂 CSS 属性时会放弃重排，直接将整页渲染为图片（即 PDF 模式）。
  # 本步骤强制移除这些"危险"属性，确保 Kindle 识别为流式排版书籍。
  find "$TMP_DIR" -type f \( -name "*.css" -o -name "*.html" -o -name "*.xhtml" \) -exec sed -i -E \
    -e 's/position[[:space:]]*:[[:space:]]*(absolute|fixed)[[:space:]]*;?/position: static;/g' \
    -e 's/float[[:space:]]*:[[:space:]]*(left|right)[[:space:]]*;?/float: none;/g' \
    -e 's/display[[:space:]]*:[[:space:]]*flex[[:space:]]*;?/display: block;/g' \
    {} \; 2>/dev/null || true
  ok "Kindle 清洗完成（已移除 position:absolute/fixed、float、display:flex）"

  # --- 步骤9：图片压缩（可选） ---
  if [[ "${EPUB_IMG:-on}" != "off" ]]; then
    log "9. 正在压缩图片以减小体积..."
    if command -v mogrify &>/dev/null; then
      local img_count=0
      while IFS= read -r -d '' img; do
        mogrify -strip -quality 85 -resize "1500x1500>" "$img" 2>/dev/null || true
        ((img_count++)) || true
      done < <(find "$TMP_DIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) -print0)
      ok "图片压缩完成（共处理 $img_count 张）"
    else
      warn "未安装 imagemagick，跳过图片压缩（安装: pkg install imagemagick）"
    fi
  else
    log "9. 已跳过图片压缩（画册模式）"
  fi

  # --- 重新打包 EPUB ---
  log "正在重新打包 EPUB..."

  # 确保 mimetype 文件存在
  if [[ ! -f "$TMP_DIR/mimetype" ]]; then
    echo "application/epub+zip" > "$TMP_DIR/mimetype"
  fi

  # 打包：mimetype 必须第一个且无压缩
  (
    cd "$TMP_DIR" && \
    zip -0Xq "$output_path" mimetype && \
    zip -Xr9Dq "$output_path" . -x mimetype
  ) || { err "打包失败！"; }

  ok "转换完成！共处理 $converted_count 个文本文件。"
  echo "输出路径: $output_path"
  command -v termux-toast &>/dev/null && termux-toast "转换完成: ${book_name}-cc.epub"
}

main "$@"
