#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cc-epub —— EPUB 港台繁体中文书籍转换工具
=================================================
功能：将港台繁体 EPUB 电子书 → 简体 + 横排 + 首行缩进
依赖：opencc (pip) 或系统 opencc；Python 3.10+

用法：
    cc-epub 输入.epub                 # 默认：繁→简，输出到 Download/E-book/
    cc-epub 输入.epub -o 输出.epub     # 指定输出
    cc-epub 输入.epub --config tw2sp   # 台湾惯用词→简（更彻底）
    cc-epub 输入.epub --no-css         # 不注入排版 CSS（仅转换文字）

作者：epubcc  |  仓库：cc-epub
"""
import argparse
import os
import re
import shutil
import sys
import zipfile
from pathlib import Path

try:
    import opencc
except ImportError:
    sys.exit("[FATAL] 未安装 opencc。请运行：pip install opencc")

# ---------- 配置 ----------
DEFAULT_CONFIG = "t2s"      # 通用繁体 → 简体
TEXT_EXTS = {".xhtml", ".html", ".htm", ".xml", ".opf", ".ncx", ".txt"}
CSS_EXTS = {".css"}
MIMETYPE = "mimetype"
MIMETYPE_CONTENT = b"application/epub+zip"

# 横排 + 首行缩进 的 CSS（注入到每个 .css 与 <style>）
INJECT_CSS = """
/* ===== cc-epub: 简体 + 横排 + 首行缩进 ===== */
body, html, *[xml|lang], *[lang] {
    writing-mode: horizontal-tb !important;
    -epub-writing-mode: horizontal-tb !important;
}
p, div.paragraph, .paragraph {
    text-indent: 2em !important;
}
"""

# 需要清理的旧注入标记（幂等处理）
INJECT_MARKER = "/* ===== cc-epub"

# 尝试检测文件编码的备选编码列表（按常见程度排序）
ENCODING_FALLBACKS = ["utf-8", "gbk", "gb2312", "big5", "shift_jis", "euc-jp", "latin-1"]

# ---------- Kindle 兼容性：CSS 清理规则 ----------
# 移除 @font-face 声明（Kindle 不支持嵌入字体，会导致白页）
RE_FONT_FACE = re.compile(
    r'@font-face\s*\{[^}]*\}\s*', re.DOTALL
)
# 移除 display:none（超过 10000 字符的隐藏块会导致 Kindle 转换失败）
RE_DISPLAY_NONE = re.compile(
    r'\{[^}]*display\s*:\s*none[^}]*\}', re.DOTALL
)
# 移除 position:absolute / position:fixed（Kindle 排版引擎不支持）
RE_POSITION_ABS = re.compile(
    r'\{[^}]*position\s*:\s*(?:absolute|fixed)[^}]*\}', re.DOTALL
)
# 移除 float 属性（Kindle 排版引擎对 float 支持不稳定）
RE_FLOAT = re.compile(
    r'\{[^}]*float\s*:\s*(?:left|right|none)[^}]*\}', re.DOTALL
)


def get_converter(config_name: str) -> opencc.OpenCC:
    try:
        return opencc.OpenCC(config_name)
    except Exception as e:
        print(f"[WARN] 配置 '{config_name}' 不可用 ({e})，回退到 '{DEFAULT_CONFIG}'")
        return opencc.OpenCC(DEFAULT_CONFIG)


def detect_encoding(data: bytes) -> str:
    """自动检测文件编码，优先使用 chardet，回退到手动尝试。"""
    try:
        import chardet
        result = chardet.detect(data)
        if result and result.get("confidence", 0) > 0.5:
            return result["encoding"]
    except ImportError:
        pass

    for enc in ENCODING_FALLBACKS:
        try:
            data.decode(enc)
            return enc
        except (UnicodeDecodeError, LookupError):
            continue

    return "latin-1"


def safe_read_text(data: bytes) -> str:
    """安全读取文本数据，自动检测编码。"""
    enc = detect_encoding(data)
    return data.decode(enc, errors="replace")


def clean_css_for_kindle(css_text: str) -> str:
    """清理对 Kindle 不友好的 CSS 规则。"""
    css_text = RE_FONT_FACE.sub("", css_text)
    css_text = RE_DISPLAY_NONE.sub("", css_text)
    css_text = RE_POSITION_ABS.sub("", css_text)
    css_text = RE_FLOAT.sub("", css_text)
    return css_text.strip()


def fix_xhtml_encoding(html_text: str) -> str:
    """确保 XHTML 文件声明 UTF-8 编码（Kindle 要求）。"""
    # 替换各种编码声明为 UTF-8
    html_text = re.sub(
        r'(<\?xml[^>]*encoding\s*=\s*["\x27])([^"\x27]+)(["\x27])',
        r'\1UTF-8\3',
        html_text,
        count=1,
    )
    # 替换 <meta http-equiv="Content-Type" ...> 中的编码
    html_text = re.sub(
        r'<meta\s+http-equiv\s*=\s*["\x27]Content-Type["\x27][^>]*charset\s*=\s*["\x27]?([^"\x27> ]+)',
        r'<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">',
        html_text,
        count=1,
    )
    # 如果没有 meta 标签，在 <head> 后插入
    if '<meta' not in html_text.lower() and '<head>' in html_text.lower():
        html_text = html_text.replace('<head>', '<head><meta charset="UTF-8">', 1)
    return html_text


def fix_opf_language(opf_text: str) -> str:
    """将 OPF 文件中的 <dc:language> 设为 zh-CN（Kindle 兼容）。"""
    # 替换现有的 language 标签
    opf_text = re.sub(
        r'(<dc:language\s*xmlns:dc\s*=\s*["\x27]http://purl.org/dc/elements/1.1/["\x27])>[^<]*(</dc:language>)',
        r'\1>zh-CN\2',
        opf_text,
    )
    # 如果没有 xmlns:dc 属性，尝试更宽松的匹配
    opf_text = re.sub(
        r'<dc:language[^>]*>[^<]*</dc:language>',
        '<dc:language>zh-CN</dc:language>',
        opf_text,
    )
    return opf_text


def convert_text(text: str, converter: opencc.OpenCC) -> str:
    """转换文本，并幂等处理已注入的 CSS 标记。"""
    converted = converter.convert(text)
    return converted


def inject_css(css_text: str) -> str:
    """向 CSS 内容注入横排+缩进规则（幂等），并清理 Kindle 不友好规则。"""
    # 先清理 Kindle 不友好的 CSS
    cleaned = clean_css_for_kindle(css_text)
    # 移除旧的 cc-epub 注入标记
    cleaned = re.sub(
        r"/\* ===== cc-epub.*?(?=\*/)\\*/", "", cleaned, flags=re.DOTALL
    ).strip()
    return INJECT_CSS.strip() + "\n" + cleaned


def inject_html_css(html_text: str, converter: opencc.OpenCC) -> str:
    """在 HTML 的 <head> 中注入 <style>，幂等。"""
    # 先清理 Kindle 不友好的 CSS（<style> 块内的规则）
    html_text = clean_css_for_kindle(html_text)
    # 确保 UTF-8 编码声明
    html_text = fix_xhtml_encoding(html_text)
    # 转换文字
    html_text = converter.convert(html_text)
    # 移除旧的注入
    html_text = re.sub(
        r"<style[^>]*>/\* ===== cc-epub.*?</style>", "", html_text, flags=re.DOTALL
    )
    style_block = f"<style>{INJECT_CSS.strip()}</style>"
    if "<head>" in html_text:
        html_text = html_text.replace("<head>", "<head>" + style_block, 1)
    else:
        html_text = style_block + html_text
    return html_text


def process_epub(in_path: str, out_path: str, config: str, add_css: bool):
    converter = get_converter(config)
    in_path = os.path.abspath(in_path)
    out_path = os.path.abspath(out_path)

    if not os.path.isfile(in_path):
        sys.exit(f"[FATAL] 输入文件不存在：{in_path}")

    # 输出文件已存在时提示用户确认覆盖
    if os.path.exists(out_path):
        try:
            overwrite = input(
                f"[WARN] 输出文件 {out_path} 已存在，是否覆盖？(y/N): "
            ).strip().lower()
        except (EOFError, KeyboardInterrupt):
            overwrite = "n"
        if overwrite != "y":
            print("[INFO] 已取消操作。")
            sys.exit(0)
        os.remove(out_path)

    print(f"[INFO] 输入：{in_path}")
    print(f"[INFO] 配置：{config}  |  注入CSS：{add_css}")
    print(f"[INFO] 输出：{out_path}")

    # 读取原 EPUB 所有条目（保留压缩信息）
    with zipfile.ZipFile(in_path, "r") as zin:
        infos = zin.infolist()
        has_mimetype = any(i.filename == MIMETYPE for i in infos)

    with zipfile.ZipFile(in_path, "r") as zin, \
         zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED) as zout:

        # 1) 先写 mimetype（必须第一个、未压缩）
        if has_mimetype:
            zout.writestr(MIMETYPE, MIMETYPE_CONTENT, zipfile.ZIP_STORED)

        converted_count = 0
        for info in infos:
            name = info.filename
            if name == MIMETYPE:
                continue  # 已处理
            data = zin.read(name)

            # 仅处理文本类文件
            ext = Path(name).suffix.lower()
            if add_css and ext in CSS_EXTS:
                text = safe_read_text(data)
                data = inject_css(text).encode("utf-8")
                converted_count += 1
            elif add_css and ext in TEXT_EXTS and name.lower().endswith(
                (".xhtml", ".html", ".htm")
            ):
                text = safe_read_text(data)
                data = inject_html_css(text, converter).encode("utf-8")
                converted_count += 1
            elif ext in TEXT_EXTS:
                text = safe_read_text(data)
                # OPF 文件特殊处理：修正语言代码
                if name.endswith(".opf"):
                    text = fix_opf_language(text)
                data = convert_text(text, converter).encode("utf-8")
                converted_count += 1
            # 其他（图片等二进制）原样复制

            # 保留原压缩方式
            if info.compress_type == zipfile.ZIP_STORED:
                zout.writestr(info, data, zipfile.ZIP_STORED)
            else:
                zout.writestr(info, data)

    size_mb = os.path.getsize(out_path) / 1024 / 1024
    print(f"[DONE] 完成！共转换 {converted_count} 个文本文件，大小：{size_mb:.2f} MB")
    if size_mb > 200:
        print("[WARN] 超过 Send to Kindle 单文件 200MB 限制，建议拆分！")
    print("[NEXT] 可上传至 GitHub epubcc/cc-epub，或用 Send to Kindle 推送")


def default_output(in_path: str) -> str:
    """Download/E-book/书名-cc.epub"""
    p = Path(in_path)
    download_dir = Path(os.path.expanduser("~")) / "Download" / "E-book"
    download_dir.mkdir(parents=True, exist_ok=True)
    return str(download_dir / f"{p.stem}-cc.epub")


def main():
    parser = argparse.ArgumentParser(
        description="EPUB 港台繁体 → 简体 + 横排 + 首行缩进 (cc-epub)"
    )
    parser.add_argument("input", help="输入 EPUB 文件")
    parser.add_argument("-o", "--output", help="输出路径（默认 Download/E-book/书名-cc.epub）")
    parser.add_argument(
        "-c", "--config",
        default=DEFAULT_CONFIG,
        help="OpenCC 配置 (默认 t2s；台湾惯用词用 tw2sp)",
    )
    parser.add_argument("--no-css", action="store_true", help="不注入横排/缩进 CSS")
    args = parser.parse_args()

    out = args.output or default_output(args.input)
    process_epub(args.input, out, args.config, add_css=not args.no_css)


if __name__ == "__main__":
    main()
