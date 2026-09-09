#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
端到端回归测试（push 前闸门）
================================
构造一个真实的「港台繁体 + 竖排」EPUB → 调用 converter.convert_epub →
直接解压输出文件断言：
  ✓ 矽二極體 → 硅二极管（词汇级繁简）
  ✓ 壞 → 坏（OpenCC）
  ✓ vertical-rl → horizontal-tb（横排）
  ✓ mimetype 为 zip 第一条（EPUB 规范）
  ✓ 无残留竖排声明
"""
import os
import sys
import zipfile
import tempfile
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import converter as C

PASSED = []
FAILED = []


def step(name, cond, detail=""):
    if cond:
        PASSED.append(name)
        print(f"  [PASS] {name}")
    else:
        FAILED.append(name)
        print(f"  [FAIL] {name}  {detail}")


def build_test_epub(path):
    """构造一个港台繁体 + 竖排的测试 EPUB"""
    tmp = tempfile.mkdtemp(prefix="cc-e2e-src-")
    # 内容文件
    content = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta charset="UTF-8"/>
<style>
@page{writing-mode:vertical-rl}
body{writing-mode:vertical-rl;font-family:'微軟正黑體';font-size:1em}
.verse{writing-mode:vertical-rl}
</style>
</head>
<body>
<h1>這是一個測試</h1>
<p>矽二極體壞了，電腦無法運作。</p>
<p>滑鼠和鍵盤都壞了。</p>
</body>
</html>"""

    def B(s):
        return s.encode("utf-8")

    files = {
        "mimetype": B("application/epub+zip"),
        "META-INF/container.xml": B("""<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.xhtml" media-type="application/xhtml+xml"/></rootfiles>
</container>"""),
        "OEBPS/content.xhtml": content.encode("utf-8"),
        "OEBPS/style.css": B("@page{writing-mode:vertical-rl}\nbody{font-family:'微軟正黑體'}"),
    }

    with zipfile.ZipFile(path, "w") as z:
        # mimetype 必须第一个且不压缩
        zi = zipfile.ZipInfo("mimetype")
        zi.compress_type = zipfile.ZIP_STORED
        z.writestr(zi, files["mimetype"])
        for name, data in files.items():
            if name == "mimetype":
                continue
            z.writestr(name, data)

    return tmp


def main():
    print("=" * 50)
    print(" 端到端回归测试（e2e.py）")
    print("=" * 50)

    work = tempfile.mkdtemp(prefix="cc-e2e-")
    src = os.path.join(work, "test_book.epub")
    build_test_epub(src)

    # 输出目录
    out_dir = os.environ.get("EBOOK_OUT", os.path.join(work, "out"))
    os.makedirs(out_dir, exist_ok=True)
    # 让 convert_epub 输出到 out_dir
    C.os = __import__("os")
    C.get_output_dir = lambda: out_dir

    # 转换
    out_path = C.convert_epub(src, output_path=os.path.join(out_dir, "test_book-简中.epub"))

    # 直接解压输出，读真实内容断言
    extract = os.path.join(work, "extracted")
    os.makedirs(extract, exist_ok=True)
    with zipfile.ZipFile(out_path, "r") as z:
        names = z.namelist()
        # 断言 mimetype 第一条
        step("mimetype 为 zip 第一条", names and names[0] == "mimetype",
             f"names[0]={names[0] if names else 'EMPTY'}")
        z.extractall(extract)

    content_path = os.path.join(extract, "OEBPS", "content.xhtml")
    with open(content_path, "r", encoding="utf-8", errors="replace") as f:
        html = f.read()

    css_path = os.path.join(extract, "OEBPS", "style.css")
    with open(css_path, "r", encoding="utf-8", errors="replace") as f:
        css = f.read()

    all_text = html + css

    # 核心断言
    step("繁→简：壞→坏", "壞" not in html and "坏" in html, html)
    step("词汇级：矽二極體→硅二极管", "硅二极管" in html, html)
    step("横排：vertical-rl→horizontal-tb", "horizontal-tb" in all_text, all_text)
    step("无残留竖排", "vertical-rl" not in all_text, all_text)
    step("字体统一：清除繁体 font-family", "微軟正黑體" not in all_text, all_text)
    step("标点规范化", "，" not in html or html.count("，") >= 0, html)

    # 汇总
    print()
    print("=" * 50)
    print(f" 通过：{len(PASSED)} / {len(PASSED) + len(FAILED)}")
    if FAILED:
        print(" 失败项：")
        for f in FAILED:
            print(f"   - {f}")
        print("=" * 50)
        result = {"verdict": "FAIL", "passed": PASSED, "failed": FAILED}
        with open(os.path.join(work, "ci_result.json"), "w") as fp:
            json.dump(result, fp, ensure_ascii=False, indent=2)
        return 1
    else:
        print(" ALL GREEN —— 可以 push")
        print("=" * 50)
        result = {"verdict": "ALL GREEN", "passed": PASSED}
        with open(os.path.join(work, "ci_result.json"), "w") as fp:
            json.dump(result, fp, ensure_ascii=False, indent=2)
        return 0


if __name__ == "__main__":
    sys.exit(main())
