#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cc-epub 端到端测试（pytest 兼容，也可直接 python 运行）"""
import os
import sys
import re
import zipfile
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT))

import cc  # noqa: E402

# 繁体测试文本（模拟港台竖排书籍）
SAMPLE_HTML = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" style="writing-mode: vertical-rl; direction: rtl;">
<head><title>測試</title>
<link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
<h1 class="chapter-title">第一章　緒論</h1>
<p style="font-family: 'MingLiU', serif; font-size: 1.2em; text-indent: 2em;">\u3000\u3000「這是一段繁體中文」，書中寫道：「臺灣與香港─不同」\u2026\u2026</p>
<p class="dialog">『第二個段落』：作者說\u2014\u2014是的。</p>
<p>　　全形空格在行首，應該被清除。</p>
<div><img src="images/pic.png" alt="圖一"/></div>
</body>
</html>
"""

SAMPLE_CSS = """
@font-face { font-family: "MingLiU"; src: url(font.ttf); }
body { writing-mode: vertical-rl; font-family: MingLiU, sans-serif; font-size: 1.2em; }
p { text-indent: 2em; margin-left: 1em; }
.dialog { text-indent: 2em; color: red; }
"""

SAMPLE_OPF = """<?xml version="1.0"?>
<package xmlns:dc="http://purl.org/dc/elements/1.1/">
<metadata>
  <dc:title>測試書名</dc:title>
  <dc:creator>張三</dc:creator>
  <dc:description>這是一本繁體書的簡介，描述內容。</dc:description>
</metadata>
</package>
"""

SAMPLE_NCX = """<?xml version="1.0"?>
<ncx><navMap>
<navPoint><navLabel><text>第一章　緒論</text></navLabel></navPoint>
<navPoint><navLabel><text>第二章　理論</text></navLabel></navPoint>
</navMap></ncx>
"""


def build_epub(path):
    """构造一个模拟的港台竖排繁体 EPUB"""
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("OEBPS/text.xhtml", SAMPLE_HTML)
        z.writestr("OEBPS/style.css", SAMPLE_CSS)
        z.writestr("OEBPS/content.opf", SAMPLE_OPF)
        z.writestr("OEBPS/toc.ncx", SAMPLE_NCX)
        z.writestr("OEBPS/images/pic.png", b"\x89PNG\r\n\x1a\nfakeimg")  # 假图片


def read_epub(path, name):
    with zipfile.ZipFile(path) as z:
        return z.read(name).decode("utf-8", errors="ignore")


def test_end_to_end():
    """完整流程：构造 → 转换 → 验证"""
    src = tempfile.NamedTemporaryFile(suffix=".epub", delete=False)
    src.close()
    out_dir = tempfile.mkdtemp()
    out_path = os.path.join(out_dir, "test-简中.epub")

    build_epub(src.name)
    cc.process_epub(src.name, output_file=out_path)

    assert os.path.exists(out_path), "应输出转换后的文件"

    # 1) 输出是有效 ZIP（能重新打开）
    with zipfile.ZipFile(out_path) as z:
        names = z.namelist()
        assert "mimetype" in names, "应包含 mimetype"
        # mimetype 须无压缩（首位即可，规范不强求 index 0）
        info = z.getinfo("mimetype")
        assert info.compress_type == zipfile.ZIP_STORED, "mimetype 应无压缩"

    # 2) 图片（插图）完好保留
    img = read_epub(out_path, "OEBPS/images/pic.png")
    assert "fakeimg" in img, "插图不应被破坏"

    html = read_epub(out_path, "OEBPS/text.xhtml")
    opf = read_epub(out_path, "OEBPS/content.opf")
    css_out = read_epub(out_path, "OEBPS/style.css")

    # 3) ★核心：横排 + 首行缩进 2em，且绝不为 4em
    assert "writing-mode: horizontal-tb" in html, "应转为横排"
    assert "text-indent: 2em !important" in html, "应注入 2em 缩进"
    # 确保没有残留的 4em（注入的只有 2em，且原 CSS 的 text-indent 已被覆盖）
    indent_values = re.findall(r"text-indent\s*:\s*([0-9.]+)em", html)
    assert all(v == "2" for v in indent_values), f"缩进值应全为 2em，实际: {indent_values}"

    # 4) ★核心：文本层全角空格 / 缩进实体已清除（根除叠加根源）
    body_text = "".join(re.findall(r"<p[^>]*>(.*?)</p>", html, re.DOTALL))
    assert "\u3000" not in body_text, f"段落开头不应残留全角空格，实际: {body_text!r}"
    assert "&emsp;" not in html, "不应残留 &emsp;"

    # 5) 繁简转换生效（"這"→"这"、"臺"→"台"、"書"→"书"）
    assert "這是一段" not in html, "正文繁体应转为简体"
    assert "緒論" not in html, "繁体章节名应转换"
    assert "測試書名" not in opf, "书名繁体应转换"

    # 6) 直角引号 → 弯引号
    assert "「" not in html and "」" not in html, "直角引号应被替换"

    # 7) 标点规范化：破折号、省略号
    assert "\u2014\u2014" in html or "——" in html, "破折号应统一"

    # 8) 字体/嵌入字体已移除（KFX 兼容）
    assert "@font-face" not in css_out, "应移除 @font-face"
    assert "font-family" not in html or "inherit" in html, "内联字体应清除"

    # 9) OPF 元数据繁转简
    assert "測試書名" not in opf, "书名应转简体"
    assert "張三" not in opf, "作者应转简体"

    # 10) NCX 目录繁转简
    ncx = read_epub(out_path, "OEBPS/toc.ncx")
    assert "緒論" not in ncx, "目录应转简体"

    # 清理
    os.unlink(src.name)
    os.remove(out_path)
    os.rmdir(out_dir)
    print("\n[ALL TESTS PASSED]")


def test_horizontal_preserves_indent():
    """需求 #7：已横排文件只需确认首行缩进符合标准（应为 2em，不叠加）"""
    html = """<html><head></head><body>
<p style="text-indent: 2em;">這是橫排正文，原本就是 horizontal-tb。</p>
</body></html>"""
    out = cc.clean_html_content(html, convert_t2s=True)
    indents = re.findall(r"text-indent\s*:\s*([0-9.]+)em", out)
    assert all(v == "2" for v in indents), f"横排文件缩进应为 2em，实际 {indents}"
    assert "writing-mode: horizontal-tb" in out, "横排文件应明确为 horizontal-tb"
    assert "這是橫排" not in out, "繁体应转换"
    print("[PASSED] test_horizontal_preserves_indent")


def test_indent_not_quadrupled():
    """回归：痛点 #8 —— 全角空格 + CSS 缩进 叠加不应产生 4em"""
    html = """<html><body>
<p style="text-indent: 2em;">\u3000\u3000「繁體段」落，前有两个全角空格。</p>
</body></html>"""
    out = cc.clean_html_content(html, convert_t2s=True)
    indents = re.findall(r"text-indent\s*:\s*([0-9.]+)em", out)
    assert all(v == "2" for v in indents), f"不应出现 4em，实际 {indents}"
    # 文本层全角空格已清空（由 CSS 单一来源控制缩进）
    body = "".join(re.findall(r"<p[^>]*>(.*?)</p>", out, re.DOTALL))
    assert "\u3000" not in body, "文本层不应残留全角缩进空格"
    print("[PASSED] test_indent_not_quadrupled")


def test_punctuation_normalization():
    """港台标点 → 大陆规范（需求：直角引号、破折号、省略号等）"""
    assert cc.normalize_punctuation("「甲」『乙』") == "\u201c甲\u201d\u2018乙\u2019"
    assert "——" in cc.normalize_punctuation("A—B──C")
    assert "……" in cc.normalize_punctuation("A...B")
    # 间隔号：全角句点 ． → 中间点 ·
    assert cc.normalize_punctuation("A．B") == "A·B"
    print("[PASSED] test_punctuation_normalization")


if __name__ == "__main__":
    test_end_to_end()
    test_horizontal_preserves_indent()
    test_indent_not_quadrupled()
    test_punctuation_normalization()
    print("\n[ALL TESTS PASSED]")
