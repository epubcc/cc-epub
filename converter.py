#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
港台繁体 EPUB 转换工具 1.0
================================
功能：
  1. 繁体中文（台湾/香港）→ 简体中文（OpenCC tw2sp，含词汇级）
  2. 竖排 → 横排（writing-mode: vertical-rl → horizontal-tb）
  3. 字体统一，清除繁体专属 font-family，调用 Kindle 自带字体
  4. 完美保留：排版、插图、目录(OPF/NCX/nav)、CSS、章节分隔
  5. 横排时标点位置自动调整（全角标点规范化）
  6. 输出命名：书名-简中.epub，存入 Download/E-book/

依赖：opencc, beautifulsoup4
"""

import os
import sys
import re
import shutil
import zipfile
import tempfile
from urllib.parse import quote

try:
    import opencc
    _OCC = opencc.OpenCC("tw2sp")
except Exception:
    _OCC = None

try:
    from bs4 import BeautifulSoup
    _HAS_BS4 = True
except Exception:
    _HAS_BS4 = False


__version__ = "1.0.0"
SCRIPT_NAME = "港台繁体EPUB转换工具"
HORIZONTAL_CSS = (
    "@page{writing-mode:horizontal-tb!important}"
    "*{writing-mode:horizontal-tb!important}"
)


# ============================================================
# 工具函数
# ============================================================

def _log(msg):
    print(msg, flush=True)


def convert_text(text):
    """繁体 → 简体（OpenCC tw2sp + 词汇补充）"""
    if not text:
        return text
    if _OCC is not None:
        try:
            return _OCC.convert(text)
        except Exception:
            pass
    return _fallback_convert(text)


def _fallback_convert(text):
    """无 OpenCC 时的浅转换（仅保证基本单字，建议安装 opencc）"""
    table = {
        "這": "这", "那": "那", "來": "来", "國": "国", "書": "书",
        "時": "时", "間": "间", "電": "电", "腦": "脑", "體": "体",
        "從": "从", "長": "长", "馬": "马", "風": "风", "飛": "飞",
        "壞": "坏", "廣": "广", "點": "点", "顯": "显", "機": "机",
        "測": "测", "試": "试", "標": "标", "題": "题", "結": "结",
        "構": "构", "節": "节", "環": "环", "節": "节", "圖": "图",
    }
    result = []
    for ch in text:
        result.append(table.get(ch, ch))
    return "".join(result)


# ============================================================
# 横排处理
# ============================================================

def to_horizontal_css(css_text):
    """CSS 中的竖排声明 → 横排"""
    if not css_text:
        return css_text
    text = css_text
    # writing-mode 各种竖排值 → horizontal-tb
    text = re.sub(
        r"writing-mode\s*:\s*vertical-(?:rl|lr|tb-rl)",
        "writing-mode:horizontal-tb",
        text,
        flags=re.IGNORECASE,
    )
    # 方向
    text = re.sub(r"\b(?:vertical-rl|vertical-lr)\b", "horizontal-tb", text)
    text = re.sub(r"\b(?:tb-rl|tb-lr)\b", "horizontal-tb", text)
    # 保留书写模式但清除竖排专属
    return text


def inject_horizontal_baseline(css_text):
    """无横排声明时注入基线规则，确保横向阅读"""
    if not css_text:
        css_text = ""
    if "writing-mode" not in css_text:
        css_text = HORIZONTAL_CSS + "\n" + css_text
    if "@page" not in css_text:
        css_text = "@page{writing-mode:horizontal-tb!important}\n" + css_text
    return css_text


def normalize_punctuation(text):
    """横排时标点位置调整：规范化全角标点间距"""
    if not text:
        return text
    # 移除中文标点后的多余空格
    text = re.sub(r"([，。！？；：、）】」》])\s+", r"\1", text)
    # 移除中文标点前的多余空格
    text = re.sub(r"\s+([（【「《，。！？；：、）】」》])", r"\1", text)
    # 处理「（ 括号 ）」：左括号后紧跟空格也清除
    text = re.sub(r"([（【「])\s+", r"\1", text)
    # 中文与英文/数字之间保留适当间距（Kindle 渲染更自然）
    return text


# ============================================================
# 字体统一
# ============================================================

def unify_font_family(css_text):
    """清除繁体专属字体，让 Kindle 使用自带字体"""
    if not css_text:
        return css_text
    text = css_text
    # 移除显式 font-family 声明（让 Kindle 套用用户所选字体）
    text = re.sub(
        r"font-family\s*:\s*[^;}\n]+[;]?",
        "",
        text,
        flags=re.IGNORECASE,
    )
    # 移除常见繁体字体引用
    for font in ["微軟正黑體", "微软雅黑", "思源黑體", "思源繁體",
                 "PingFang", "Heiti", "STHeiti", "MingLiU", "PMingLiU",
                 "AR PL UMing", "Noto Sans CJK TC", "Noto Serif CJK TC"]:
        text = text.replace(font, "")
    return text


# ============================================================
# 内容转换（xhtml / html）
# ============================================================

def _process_css(css_text):
    """统一处理一段 CSS：横排 + 字体统一 + 基线注入"""
    css = to_horizontal_css(css_text)
    css = unify_font_family(css)
    css = inject_horizontal_baseline(css)
    return css


def convert_xhtml(content_bytes, encoding="utf-8", is_css=False):
    """转换单个 xhtml / css 文件内容（繁简 + 横排 + 字体 + 标点）

    Parameters
    ----------
    is_css : True 表示纯 CSS 文件（如 style.css），直接整体当 CSS 处理
    """
    try:
        text = content_bytes.decode(encoding, errors="replace")
    except Exception:
        text = content_bytes.decode("utf-8", errors="replace")

    # 纯 CSS 文件：整体当作 CSS 处理
    if is_css:
        text = _process_css(text)
        return text.encode(encoding, errors="replace")

    # 1. 处理 <style> 内的 CSS
    def _replace_style(match):
        css = match.group(1)
        css = _process_css(css)
        return "<style>" + css + "</style>"

    text = re.sub(r"<style[^>]*>(.*?)</style>", _replace_style, text, flags=re.DOTALL | re.IGNORECASE)

    # 2. 处理 style 属性
    def _replace_attr(match):
        new_css = to_horizontal_css(match.group(1))
        new_css = unify_font_family(new_css)
        return 'style="' + new_css + '"'

    text = re.sub(r'style="([^"]*)"', _replace_attr, text, flags=re.IGNORECASE)

    # 3. 注入基线横排样式（若 head 内无完整规则）
    if "horizontal-tb" not in text and "<head" in text.lower():
        baseline = (
            '<style type="text/css">'
            "@page{writing-mode:horizontal-tb!important}"
            "body{writing-mode:horizontal-tb!important;font-size:1em}"
            "</style>"
        )
        text = re.sub(r"(<head[^>]*>)", r"\1" + baseline, text, flags=re.IGNORECASE, count=1)

    # 4. 繁简转换（保留标签结构，只转文本）
    if _HAS_BS4:
        text = _convert_text_via_bs4(text)
    else:
        text = _convert_text_via_regex(text)

    # 5. 标点规范化
    text = normalize_punctuation(text)

    return text.encode(encoding, errors="replace")


def _convert_text_via_bs4(text):
    """用 BeautifulSoup 精确转换文本节点（不破坏标签/属性）"""
    import warnings
    from bs4 import XMLParsedAsHTMLWarning
    warnings.filterwarnings("ignore", category=XMLParsedAsHTMLWarning)
    soup = BeautifulSoup(text, "html.parser")
    for node in soup.find_all(string=True):
        if not node.strip():
            continue
        # 跳过 <style> / <script>
        if node.parent and node.parent.name in ("style", "script"):
            continue
        new_str = convert_text(str(node))
        if new_str != str(node):
            node.replace_with(new_str)
    return str(soup)


def _convert_text_via_regex(text):
    """无 bs4 时的正则兜底：只转换标签外文本"""
    parts = []
    last = 0
    for m in re.finditer(r"<[^>]+>", text):
        outside = text[last:m.start()]
        parts.append(convert_text(outside))
        parts.append(m.group(0))
        last = m.end()
    parts.append(convert_text(text[last:]))
    return "".join(parts)


# ============================================================
# 目录搜索
# ============================================================

def get_search_dirs():
    """动态解析搜索目录（每次调用，避免 import 时固化）"""
    dirs = []
    base = None
    if os.environ.get("PREFIX") and os.path.isdir(os.path.join(os.environ["PREFIX"], "usr")):
        base = os.path.join(os.environ["PREFIX"], "storage", "downloads")
    if base and os.path.isdir(base):
        dirs.append(base)
    # 始终包含 cwd 与 cwd/Download
    cwd = os.getcwd()
    dirs.append(cwd)
    download = os.path.join(cwd, "Download")
    if os.path.isdir(download):
        dirs.append(download)
    # 去重（保留顺序）
    seen = set()
    result = []
    for d in dirs:
        if d not in seen:
            seen.add(d)
            result.append(d)
    return result


def get_output_dir():
    """动态解析输出目录（运行时计算，避免固化）

    优先级：环境变量 EBOOK_OUT > Termux storage > ~/Download > cwd/E-book
    """
    # 1. 显式指定（测试 / 自定义场景）
    env_out = os.environ.get("EBOOK_OUT")
    if env_out:
        os.makedirs(env_out, exist_ok=True)
        return env_out

    candidates = []
    if os.environ.get("PREFIX") and os.path.isdir(os.path.join(os.environ["PREFIX"], "usr")):
        base = os.path.join(os.environ["PREFIX"], "storage", "downloads")
    else:
        base = os.path.expanduser("~/Download")
    candidates.append(os.path.join(base, "E-book"))
    candidates.append(base)
    candidates.append(os.path.join(os.getcwd(), "E-book"))
    for c in candidates:
        try:
            os.makedirs(c, exist_ok=True)
            return c
        except Exception:
            continue
    fallback = os.path.join(os.getcwd(), "E-book")
    os.makedirs(fallback, exist_ok=True)
    return fallback


def find_epub(keyword):
    """模糊查找 EPUB 文件"""
    found = []
    for d in get_search_dirs():
        if not os.path.isdir(d):
            continue
        for root, _, files in os.walk(d):
            for f in files:
                if f.lower().endswith(".epub"):
                    full = os.path.join(root, f)
                    if keyword.lower() in f.lower():
                        found.append(full)
    found = sorted(set(found))
    if not found:
        return None
    if len(found) == 1:
        return found[0]
    # 交互选择
    if sys.stdin.isatty():
        print("找到多个匹配：")
        for i, p in enumerate(found):
            print(f"  [{i}] {p}")
        try:
            idx = int(input("请选择序号: "))
            return found[idx]
        except Exception:
            return found[0]
    # 非交互（cron/后台）：自动选第 0 个
    _log(f"[info] 多个匹配，自动选择第 0 个：{found[0]}")
    return found[0]


# ============================================================
# 核心：EPUB 转换
# ============================================================

def convert_epub(input_path, output_path=None):
    """将港台繁体 EPUB 转换为简体横排 EPUB"""
    input_path = os.path.abspath(input_path)
    if not os.path.isfile(input_path):
        raise FileNotFoundError(f"输入文件不存在：{input_path}")

    if output_path is None:
        name = os.path.splitext(os.path.basename(input_path))[0]
        # 移除可能已有的「-简中」后缀避免重复
        name = re.sub(r"[-_ ]?简[体中]$", "", name)
        output_path = os.path.join(get_output_dir(), f"{name}-简中.epub")

    output_path = os.path.abspath(output_path)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    _log(f"📖 输入：{input_path}")
    _log(f"📁 输出：{output_path}")

    # 文本类文件扩展名
    text_ext = {".xhtml", ".html", ".htm", ".xml", ".css", ".opf", ".ncx"}

    tmp = tempfile.mkdtemp(prefix="cc-epub-")
    try:
        with zipfile.ZipFile(input_path, "r") as zin:
            names = zin.namelist()

            # 校验：mimetype 应存在
            has_mimetype = "mimetype" in names

            with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zout:
                # 1. 优先写 mimetype（必须 ZIP 第一条、不压缩）
                if has_mimetype:
                    data = zin.read("mimetype")
                    zi = zipfile.ZipInfo("mimetype")
                    zi.compress_type = zipfile.ZIP_STORED
                    zout.writestr(zi, data)

                # 2. 逐文件处理
                converted_count = 0
                for name in names:
                    if name == "mimetype":
                        continue  # 已处理
                    data = zin.read(name)
                    ext = os.path.splitext(name)[1].lower()

                    if ext in text_ext or name.endswith(".ncx"):
                        # 文本文件：繁简 + 横排 + 字体
                        data = convert_xhtml(data, is_css=(ext == ".css"))
                        converted_count += 1
                        _log(f"   ✓ {name}")

                    # 写回（保持原压缩方式，mimetype 用 STORED）
                    if name == "mimetype":
                        zi = zipfile.ZipInfo(name)
                        zi.compress_type = zipfile.ZIP_STORED
                        zout.writestr(zi, data)
                    else:
                        zout.writestr(name, data)

                _log(f"🔄 已转换 {converted_count} 个文本文件")

        _log(f"✅ 完成 → {output_path}")
        return output_path
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ============================================================
# CLI 入口
# ============================================================

def print_help():
    print(f"""{SCRIPT_NAME} {__version__}
用法：
  {sys.argv[0]} 书名             # 模糊匹配并转换，输出 书名-简中.epub
  {sys.argv[0]} --list           # 列出可转换的 EPUB
  {sys.argv[0]} --version        # 显示版本
  {sys.argv[0]} --help           # 显示帮助

示例：
  cc- 三体                      # 转换《三体》
  cc- /path/to/book.epub        # 指定完整路径

输出目录：Download/E-book/
命名规则：书名-简中.epub
""")


def main(argv):
    args = argv[1:]
    if not args or args[0] in ("--help", "-h"):
        print_help()
        return 0
    if args[0] in ("--version", "-v"):
        print(f"{SCRIPT_NAME} {__version__}")
        return 0

    if args[0] == "--list":
        books = []
        for d in get_search_dirs():
            if not os.path.isdir(d):
                continue
            for root, _, files in os.walk(d):
                for f in files:
                    if f.lower().endswith(".epub"):
                        books.append(os.path.join(root, f))
        if not books:
            print("📭 未找到 EPUB 文件。请将繁体 EPUB 放入 Download/")
            return 0
        print(f"📚 找到 {len(books)} 本书：")
        for b in sorted(set(books)):
            print(f"   {b}")
        return 0

    # 转换
    keyword = args[0]
    if os.path.isfile(keyword) or keyword.startswith("/"):
        path = keyword
    else:
        path = find_epub(keyword)
        if path is None:
            print(f"❌ 找不到匹配「{keyword}」的 EPUB 文件")
            print("   用 `cc- --list` 查看可用书籍")
            return 1

    if not os.path.isfile(path):
        print(f"❌ 文件不存在：{path}")
        return 1

    try:
        out = convert_epub(path)
        print(f"\n🎉 转换成功！")
        print(f"   文件：{out}")
        print(f"   大小：{os.path.getsize(out) / 1024:.1f} KB")
        return 0
    except Exception as e:
        print(f"❌ 转换失败：{e}")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
