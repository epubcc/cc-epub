#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
港台繁体 EPUB 转换工具 v3.0
功能：繁体→简体 | 竖排→横排 | 首行缩进 2em | 清理全角空格 | 标点规范化 |
      字体统一 | 字号统一 | 保留插图/目录/章节结构
输出：~/storage/shared/Download/E-book/书名-简中.epub （书名取自 OPF <dc:title>）

处理顺序（需求⑦，杜绝 4em 痛点⑧）：
  清除段首全角空格 → 检测排版方向 → 竖排转横排 → 确认 2em
"""

import os
import re
import sys
import zipfile
import shutil
import subprocess
import tempfile
from bs4 import BeautifulSoup
from pathlib import Path

__version__ = "3.0.0"

# OpenCC 配置：台湾繁体→简体（含短语），香港书籍改为 hk2sp.json
OPENCC_CONFIG = "tw2sp.json"

# 输出目录（Termux 存储路径）
OUT_DIR = str(Path.home() / "storage" / "shared" / "Download" / "E-book")


# ---------------------------------------------------------------------- 依赖
def check_dependencies():
    """检查依赖，缺失时尝试自动安装"""
    try:
        import bs4  # noqa: F401
    except ImportError:
        print("[-] 缺少依赖库 beautifulsoup4，正在尝试自动安装...")
        subprocess.run([sys.executable, "-m", "pip", "install", "beautifulsoup4"])
        try:
            import bs4  # noqa: F401
            print("[+] 依赖安装完成。")
        except ImportError:
            print("[-] 自动安装失败，请手动运行: pip install beautifulsoup4")
            sys.exit(1)


# ------------------------------------------------------------------- 繁简转换
def convert_text(text):
    """单段繁转简 + 标点规范化（无论是否安装 opencc，标点都规范化）"""
    if not text or not text.strip():
        return text
    converted = text
    try:
        result = subprocess.run(
            ["opencc", "-c", "t2s.json"],
            input=text, capture_output=True, text=True, encoding="utf-8",
        )
        if result.returncode == 0 and result.stdout:
            converted = result.stdout
    except FileNotFoundError:
        pass
    except Exception:
        pass
    return normalize_punctuation(converted)


def batch_convert_t2s(texts):
    """批量繁转简：合并后一次性调用 opencc，大幅提升性能"""
    if not texts:
        return []

    separator = "\n\x00\n"
    combined = separator.join(texts)

    tmp = tempfile.gettempdir()
    tmp_in, tmp_out = os.path.join(tmp, "cc_in.txt"), os.path.join(tmp, "cc_out.txt")

    try:
        with open(tmp_in, "w", encoding="utf-8") as f:
            f.write(combined)
        result = subprocess.run(
            ["opencc", "-i", tmp_in, "-o", tmp_out, "-c", OPENCC_CONFIG],
            capture_output=True, text=True,
        )
        if result.returncode == 0 and os.path.exists(tmp_out):
            with open(tmp_out, "r", encoding="utf-8") as f:
                converted = f.read()
            return [normalize_punctuation(t) for t in converted.split(separator)]
        print("  [!] opencc 批量转换失败，逐段降级处理")
        return [convert_text(t) for t in texts]
    except Exception as e:
        print(f"  [!] 批量繁转简异常: {e}，逐段降级处理")
        return [convert_text(t) for t in texts]
    finally:
        for f in (tmp_in, tmp_out):
            if os.path.exists(f):
                os.remove(f)


# ------------------------------------------------------------- 标点规范化
def normalize_punctuation(text):
    """将港台标点符号规范化为大陆标准"""
    if not text:
        return text

    # 直角引号 → 弯引号（先外后内）
    text = text.replace("\u300c", "\u201c").replace("\u300d", "\u201d")  # 「」
    text = text.replace("\u300e", "\u2018").replace("\u300f", "\u2019")  # 『』

    # 港台小逗号 ﹐ → ， / 小句号 ﹒ → 。（需求⑧：原脚本漏了这两条）
    text = text.replace("\ufe50", "\uff0c")
    text = text.replace("\ufe51", "\u3002")
    text = text.replace("\uff64", "\uff0c")

    # 特殊逗号句号
    text = text.replace("\ufe44", "\uff0c").replace("\ufe45", "\u3002")

    # 破折号
    text = re.sub(r"[—─━–\-]+", "\u2014\u2014", text)

    # 省略号：ASCII 连续点 ".../...." 规范化为单个 …（U+2026）；
    # 已有的单个 … 保持不动，不做翻倍，避免污染正文。
    text = re.sub(r"\.{3,}", "\u2026", text)

    # 间隔号 ． → ·
    text = text.replace("\uff0e", "\u00b7")

    # 特殊括号
    text = text.replace("\ufe5d", "(").replace("\ufe5e", ")")
    text = text.replace("\ufe59", "(").replace("\ufe5a", ")")

    return text


# ------------------------------------------------------------------ CSS 清洗
_CSS_DECL_RE = re.compile(r"(?i)(margin-left|padding-left)\s*:\s*[^;]+;?")
_CSS_PROP_RE = re.compile(r"(?i)font-(?:family|size)\s*:\s*[^;]+;?")


def clean_css_file(css_content):
    """清洗外部 CSS：移除竖排/@font-face/字体/字号，清理空规则块"""
    css = re.sub(r"@font-face\s*\{[^}]*\}", "", css_content, flags=re.IGNORECASE)
    css = _CSS_DECL_RE.sub("", css)          # margin-left/padding-left（段首缩进相关）
    css = re.sub(r"(?i)writing-mode\s*:\s*vertical-rl\s*;?", "", css)
    css = re.sub(r"(?i)text-orientation\s*:\s*[^;}]*;?", "", css)
    css = re.sub(r"(?i)direction\s*:\s*rtl\s*;?", "", css)
    css = _CSS_PROP_RE.sub("", css)          # font-family / font-size
    css = re.sub(r"(?i)font\s*:\s*[^;}]*;?", "", css)
    css = re.sub(r"[^{}]*\{\s*\}", "", css)  # 移除因删除产生的空规则块
    css = re.sub(r"\n{3,}", "\n\n", css).strip()
    css += "\n"

    css += "\n/* --- Auto-injected by cc.py --- */\n"
    css += "p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }\n"
    css += "body { writing-mode: horizontal-tb !important; font-family: serif !important; font-size: 1em !important; line-height: 1.5 !important; }\n"
    css += "* { font-family: inherit !important; font-size: inherit !important; }\n"
    return css


# --------------------------------------------------------------- HTML 清洗
def _strip_leading_fullwidth_spaces(text):
    """仅清除「段首」全角/排版空格，保留段落中间的空格（需求②：保留排版）"""
    return re.sub(r"^[\u3000\u2000-\u200b\ufeff&emsp;]+", "", text)


def clean_html_content(html_content):
    """清洗 HTML：繁简 + 标点 + 清空格 + 清除竖排 + 统一缩进"""
    # ★ 保护 <style>/<script> 内容：破折号/引号规范化不能破坏 CSS/JS。
    #   先将这两类标签的内部文本替换为占位符，清洗结束再还原。
    style_blocks = []

    def _protect(m):
        style_blocks.append(m.group(1))
        return f"<{m.group('tag')}::{len(style_blocks) - 1}::</{m.group('tag')}>"

    html_content = re.sub(
        r"<(?P<tag>style|script)\b[^>]*>(?P<content>.*?)</(?P=tag)>",
        _protect, html_content, flags=re.DOTALL | re.IGNORECASE,
    )

    soup = BeautifulSoup(html_content, "html.parser")

    # ① 繁简转换（仅含汉字的文本节点）
    text_nodes = [
        e for e in soup.find_all(string=True)
        if e.strip() and re.search(r"[\u4e00-\u9fff]", str(e))
    ]
    if text_nodes:
        orig = [str(n) for n in text_nodes]
        converted = batch_convert_t2s(orig)
        for node, cv in zip(text_nodes, converted):
            if cv != str(node):
                node.replace_with(cv)

    # ② 清除「段首」全角/排版空格（需求⑦流程第一步）
    for element in soup.find_all(string=True):
        if element.strip():
            new = _strip_leading_fullwidth_spaces(str(element))
            if new != str(element):
                element.replace_with(new)

    # ③ 清除 <p> 行内 style/class（统一由注入 CSS 控制）
    for p in soup.find_all("p"):
        if p.has_attr("style"):
            del p["style"]
        if p.has_attr("class"):
            del p["class"]

    # ④ 清除其他标签的 font-family / font-size 内联样式
    for tag in soup.find_all(True):
        if tag.has_attr("style"):
            style = _CSS_PROP_RE.sub("", tag["style"])
            if style.strip():
                tag["style"] = style
            else:
                del tag["style"]

    # ⑤ 修正 html/body 的 writing-mode（需求⑦：检测方向 → 竖转横）
    for tag in soup.find_all(["html", "body"]):
        if tag.has_attr("style"):
            s = re.sub(r"writing-mode\s*:\s*vertical-rl",
                       "writing-mode: horizontal-tb", tag["style"], flags=re.IGNORECASE)
            s = re.sub(r"direction\s*:\s*rtl", "direction: ltr", s, flags=re.IGNORECASE)
            tag["style"] = s

    # ⑥ 清洗 <style> 内嵌 CSS：移除竖排/字体/字号/@font-face，
    #    仅保留安全的排版声明（margin/padding/line-height/text-align/color/background）。
    #    逐条删除而非整块清空，避免残留破碎 CSS（如 `p{` `body{}`）。
    _UNSAFE_DECL = re.compile(
        r"(?i)(?:@font-face\s*\{[^}]*\}|"
        r"writing-mode\s*:\s*[^;}]*;?|"
        r"text-orientation\s*:\s*[^;}]*;?|"
        r"direction\s*:\s*[^;}]*;?|"
        r"font-(?:family|size|weight|style|variant)\s*:\s*[^;}]*;?|"
        r"font\s*:\s*[^;}]*;?)"
    )
    for style_tag in soup.find_all("style"):
        if not style_tag.string:
            continue
        cleaned = style_tag.string
        # 先移除 @font-face 整块
        cleaned = re.sub(r"@font-face\s*\{[^}]*\}", "", cleaned, flags=re.IGNORECASE)
        # 循环删除不安全的单个声明，直到无残留
        while _UNSAFE_DECL.search(cleaned):
            cleaned = _UNSAFE_DECL.sub("", cleaned)
        # 清理因删除产生的空规则块 `p{}` `body { }`
        cleaned = re.sub(r"[^{}]*\{\s*\}", "", cleaned)
        # 合并多余空白
        cleaned = re.sub(r"\n{3,}", "\n\n", cleaned).strip()
        if cleaned:
            style_tag.string = cleaned
        else:
            style_tag.decompose()  # 完全清空则移除该 <style> 标签

    # ⑦ 注入强制覆盖 CSS（确保 2em，杜绝 4em 叠加，需求⑧）
    force_css = """<style type="text/css">
/* --- Auto-injected by cc.py --- */
p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; text-align: justify; }
p.p, p.indent, p.no-indent, p.first, p.text { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }
body { writing-mode: horizontal-tb !important; direction: ltr !important; font-family: serif !important; font-size: 1em !important; line-height: 1.5 !important; }
html { writing-mode: horizontal-tb !important; font-family: serif !important; }
* { font-family: inherit !important; font-size: inherit !important; }
</style>"""
    injected = BeautifulSoup(force_css, "html.parser")
    if soup.head:
        soup.head.insert(0, injected)
    else:
        head = soup.new_tag("head")
        head.insert(0, injected)
        soup.insert(0, head)

    result = str(soup)
    # ★ 还原被保护的 <style>/<script> 原始内容
    def _restore(m):
        idx = int(m.group(1))
        return style_blocks[idx]
    result = re.sub(r"::(\d+)::", _restore, result)
    return result


# ------------------------------------------------------------------ OPF 处理
def process_opf(opf_content):
    """处理 OPF：修正阅读方向 + 元数据繁转简"""
    opf = re.sub(
        r'page-progression-direction\s*=\s*["\']rtl["\']',
        'page-progression-direction="ltr"',
        opf_content,
    )

    def _cv(match):
        return (match.group(1) + convert_text(match.group(2)) + match.group(3)
                if re.search(r"[\u4e00-\u9fff]", match.group(2)) else match.group(0))

    for tag in ["title", "creator", "publisher", "description", "subject"]:
        opf = re.sub(
            rf"(<dc:{tag}[^>]*>)(.*?)(</dc:{tag}>)", _cv, opf, flags=re.DOTALL,
        )

    def _meta(match):
        full, val = match.group(0), match.group(1)
        return full.replace(val, convert_text(val)) if re.search(r"[\u4e00-\u9fff]", val) else full

    opf = re.sub(r'content="([^"]+)"', _meta, opf)
    return opf


def process_ncx(ncx_content):
    """处理 NCX 目录：繁转简标题"""
    def _cv(match):
        return (match.group(1) + convert_text(match.group(2)) + match.group(3)
                if re.search(r"[\u4e00-\u9fff]", match.group(2)) else match.group(0))
    return re.sub(r"(<text[^>]*>)(.*?)(</text>)", _cv, ncx_content, flags=re.DOTALL)


def _safe_read_write(filepath, process_fn):
    """统一读改写：跳过二进制文件（图片等），保留插图"""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, ValueError):
        return False
    cleaned = process_fn(content)
    if cleaned != content:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(cleaned)
    return True


def _get_book_title(temp_dir):
    """从 OPF 的 <dc:title> 取书名（繁→简后），失败回退 None"""
    for root, _, files in os.walk(temp_dir):
        for file in files:
            if file.endswith(".opf"):
                try:
                    with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                        content = f.read()
                except UnicodeDecodeError:
                    continue
                m = re.search(r"<dc:title[^>]*>(.*?)</dc:title>", content, re.DOTALL)
                if m:
                    title = re.sub(r"<[^>]+>", "", m.group(1)).strip()
                    if title:
                        title = convert_text(title)
                        title = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", title)
                        return title
    return None


# ------------------------------------------------------------------ 主流程
def process_epub(input_file, output_override=None):
    """处理 EPUB 主流程"""
    if not os.path.isfile(input_file):
        print(f"[-] 找不到文件: {input_file}")
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    basename = os.path.splitext(os.path.basename(input_file))[0]

    tmp_dir = tempfile.mkdtemp()
    stats = {"html": 0, "css": 0, "opf": 0, "ncx": 0}

    try:
        with zipfile.ZipFile(input_file, "r") as z:
            z.extractall(tmp_dir)

        for root, _, files in os.walk(tmp_dir):
            for file in files:
                path = os.path.join(root, file)
                if file.endswith((".html", ".xhtml", ".htm")):
                    if _safe_read_write(path, clean_html_content):
                        stats["html"] += 1
                elif file.endswith(".css"):
                    if _safe_read_write(path, clean_css_file):
                        stats["css"] += 1
                elif file.endswith(".opf"):
                    if _safe_read_write(path, process_opf):
                        stats["opf"] += 1
                elif file.endswith(".ncx"):
                    if _safe_read_write(path, process_ncx):
                        stats["ncx"] += 1
                # 其余文件（图片/字体等）原样保留 → 插图/结构完整

        print(f"  [*] 处理统计: HTML {stats['html']}, CSS {stats['css']}, "
              f"OPF {stats['opf']}, NCX {stats['ncx']}")

        # ★ 输出文件名：优先「OPF 书名-简中.epub」
        book_title = _get_book_title(tmp_dir)
        if output_override:
            output_file = output_override
        elif book_title:
            output_file = os.path.join(OUT_DIR, f"{book_title}-简中.epub")
        else:
            output_file = os.path.join(OUT_DIR, f"{basename}-简中.epub")

        # 重新打包（mimetype 无压缩且位于首位，符合 EPUB 规范，需求⑨防白页）
        with zipfile.ZipFile(output_file, "w") as z:
            mt = os.path.join(tmp_dir, "mimetype")
            if os.path.exists(mt):
                z.write(mt, "mimetype", compress_type=zipfile.ZIP_STORED)
            for root, _, files in os.walk(tmp_dir):
                for file in files:
                    if file == "mimetype":
                        continue
                    fp = os.path.join(root, file)
                    arc = os.path.relpath(fp, tmp_dir)
                    z.write(fp, arc, compress_type=zipfile.ZIP_DEFLATED)

        print(f"[+] 转换成功！文件已保存至: {output_file}")

    except Exception as e:
        print(f"[-] 转换过程中出现错误: {e}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def main():
    check_dependencies()

    if len(sys.argv) < 2 or sys.argv[1] in ("--help", "-h", "help"):
        print("港台繁体 EPUB 转换工具 v" + __version__)
        print("用法: cc <书名.epub>           输出: 书名-简中.epub（书名取自 OPF）")
        print("      cc <书本路径>")
        print("      cc -o <输出.epub> <输入.epub>")
        print("")
        print("输出位置: ~/storage/shared/Download/E-book/书名-简中.epub")
        sys.exit(0)

    output = None
    args = sys.argv[1:]
    if args[0] == "-o" and len(args) >= 3:
        output = args[1]
        input_file = args[2]
    else:
        input_file = args[0]

    process_epub(input_file, output_override=output)


if __name__ == "__main__":
    main()
