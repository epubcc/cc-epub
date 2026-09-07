#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cc-epub：港台繁体 EPUB → 简体 + 横排 + 首行缩进（适配 Kindle）。

用法：python cc_epub.py <input.epub> [-c tw2sp] [-o output.epub] [--no-check]
依赖：opencc (pip install opencc-python-reimplemented)
默认输出：Download/E-book/书名-cc.epub
"""
import argparse, os, re, sys, zipfile
from typing import Optional

try:
    import opencc
except ImportError:
    print("[FATAL] 未安装 opencc：pip install opencc-python-reimplemented", file=sys.stderr)
    sys.exit(127)

TEXT_EXT = (".xhtml", ".html", ".htm", ".xml", ".opf", ".ncx", ".txt")
CONTENT_EXT = (".xhtml", ".html", ".htm")
DEFAULT_OUT_DIR = os.path.join("Download", "E-book")
INJECT_CSS = ('<style class="cc-epub">body{writing-mode:horizontal-tb!important}'
             'p{text-indent:2em!important}</style>')

log = lambda m: print(f"  [cc-epub] {m}")


def detect_encoding(raw: bytes) -> str:
    """自动探测文本编码：UTF-8 → GB18030 → Big5，失败回退 UTF-8。"""
    for enc in ("utf-8", "utf-8-sig", "gb18030", "big5"):
        try:
            raw.decode(enc)
            return enc
        except UnicodeDecodeError:
            continue
    return "utf-8"


def inject_style(text: str, css: str) -> str:
    """将横排+缩进 CSS 注入 <head>；无 head 时前置。"""
    low = text.lower()
    if "</head>" in low:
        return text.replace("</head>", f"{css}</head>", 1)
    if "<head" in low:
        return re.sub(r"(<head[^>]*>)", r"\1" + css, text, 1, re.IGNORECASE)
    return css + "\n" + text


def update_language(opf: str, lang: str) -> str:
    """更新 OPF 元数据 dc:language（兼容 dc: 命名空间）。"""
    if re.search(r"<dc:language[^>]*>[^<]+</dc:language>", opf, re.IGNORECASE):
        return re.sub(r"(<dc:language[^>]*>)[^<]+(</dc:language>)",
                      rf"\g<1>{lang}\2", opf, 1, re.IGNORECASE)
    return opf


def resolve_output(input_path: str, output_arg: Optional[str]) -> str:
    """解析输出路径：默认 Download/E-book/书名-cc.epub。"""
    base = os.path.splitext(os.path.basename(input_path))[0]
    if output_arg:
        if os.path.isdir(output_arg) or output_arg.endswith(os.sep):
            return os.path.join(output_arg, f"{base}-cc.epub")
        if os.path.splitext(output_arg)[1].lower() == ".epub":
            return output_arg
        return os.path.join(output_arg, f"{base}-cc.epub")
    return os.path.join(DEFAULT_OUT_DIR, f"{base}-cc.epub")


def self_check(path: str) -> bool:
    """校验 EPUB 规范性：mimetype 首个未压缩 + CSS 注入 + 语言元数据。"""
    ok = True
    with zipfile.ZipFile(path, "r") as z:
        names = z.namelist()
        first = names[0].lower() if names else ""
        if first == "mimetype" and z.infolist()[0].compress_type == zipfile.ZIP_STORED:
            log("[CHECK] ✅ mimetype 为首个未压缩条目")
        else:
            log("[CHECK] ❌ mimetype 位置/压缩方式不合规")
            ok = False
        css_ok = lang_ok = False
        for n in names:
            low = n.lower()
            if low.endswith(CONTENT_EXT):
                t = z.read(n).decode("utf-8", errors="ignore")
                if "cc-epub" in t and "horizontal-tb" in t:
                    css_ok = True
            elif low.endswith(".opf"):
                opf = z.read(n).decode("utf-8", errors="ignore")
                if re.search(r"<dc:language[^>]*>zh-CN</dc:language>", opf, re.IGNORECASE):
                    lang_ok = True
        log("[CHECK] ✅ 排版 CSS 已注入" if css_ok else "[CHECK] ⚠️  未检测到注入 CSS")
        log("[CHECK] ✅ 语言元数据 → zh-CN" if lang_ok else "[CHECK] ⚠️  未更新语言元数据")
    return ok


def process_epub(input_path: str, output_path: str, config: str, lang: str) -> bool:
    """核心流程：读取 → 繁简转换 → 注入排版 → 写回（保证 mimetype 规范）。"""
    if not os.path.isfile(input_path):
        log(f"输入文件不存在：{input_path}")
        return False

    converter = opencc.OpenCC(config)
    log(f"OpenCC 配置：{config}  输入：{input_path}")

    with zipfile.ZipFile(input_path, "r") as zin:
        entries = {i.filename: (i, zin.read(i.filename)) for i in zin.infolist()}

    # mimetype 必须首个且未压缩
    mime_entry = None
    for name, (info, data) in entries.items():
        if name.lower() == "mimetype":
            info.compress_type = zipfile.ZIP_STORED
            mime_entry = (name, info, data)
            break

    text_count = 0
    css_done = opf_done = False
    for name, (info, data) in entries.items():
        if name.lower() == "mimetype" or not name.lower().endswith(TEXT_EXT):
            continue
        enc = detect_encoding(data)
        try:
            text = data.decode(enc)
        except UnicodeDecodeError:
            log(f"解码失败，跳过：{name}")
            continue
        text = converter.convert(text)
        text_count += 1
        low = name.lower()
        if low.endswith(CONTENT_EXT) and not css_done:
            text = inject_style(text, INJECT_CSS)
            css_done = True
            log(f"已注入排版 CSS：{name}")
        elif low.endswith(".opf") and not opf_done:
            text = update_language(text, lang)
            opf_done = True
            log(f"已更新语言元数据 → {lang}")
        entries[name] = (info, text.encode("utf-8"))

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zout:
        if mime_entry:
            n, info, data = mime_entry
            zout.writestr(info, data)
        for name, (info, data) in entries.items():
            if name.lower() == "mimetype":
                continue
            zout.writestr(info, data)

    log(f"共处理 {text_count} 个文本条目 → {output_path}")
    return True


def main() -> int:
    p = argparse.ArgumentParser(description="EPUB 港台繁体 → 简体 + 横排 + 首行缩进（适配 Kindle）")
    p.add_argument("input", help="输入 EPUB 文件")
    p.add_argument("-o", "--output", help="输出路径（文件或目录），默认 Download/E-book/书名-cc.epub")
    p.add_argument("-c", "--config", default="tw2sp", help="OpenCC 配置 (默认 tw2sp；港版可用 hk2s)")
    p.add_argument("-l", "--lang", default="zh-CN", help="输出元数据语言 (默认 zh-CN)")
    p.add_argument("--no-check", action="store_true", help="跳过自检")
    args = p.parse_args()

    output = resolve_output(args.input, args.output)
    print("=" * 56)
    print("cc-epub —— 港台繁体 EPUB 转换工具")
    print("=" * 56)

    if not process_epub(args.input, output, args.config, args.lang):
        print("[FATAL] 转换失败。", file=sys.stderr)
        return 1

    if not args.no_check:
        print("\n[自检]")
        self_check(output)

    print(f"\n完成 ✅  {os.path.getsize(output) / 1024:.1f} KB")
    print("提示：Send to Kindle 推送（单文件 ≤ 200MB）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
