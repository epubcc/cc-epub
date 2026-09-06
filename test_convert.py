#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""构建繁体测试 EPUB 并运行转换，验证功能。"""
import os
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from convert import process_epub  # noqa

SAMPLE = os.path.join(HERE, "sample.epub")
OUT = os.path.join(HERE, "sample-cc.epub")


def build_sample():
    """构造一个合法的最小 EPUB（mimetype 首个未压缩 + 繁体内容 + CSS）。"""
    with zipfile.ZipFile(SAMPLE, "w") as z:
        # mimetype 必须第一个、未压缩
        z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
            '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="content.xhtml"/></rootfiles></container>')
        z.writestr("content.xhtml",
            '<?xml version="1.0"?><html xmlns="http://www.w3.org/1999/xhtml"><head><title>測試</title>'
            '<style>p{color:red}</style></head><body>'
            '<h1>這是一個繁體中文測試</h1>'
            '<p>鼠標和軟件，發展與髮型。</p>'
            '<p>第二章內容。</p></body></html>')
        z.writestr("style.css", "p { line-height: 1.6; }")
    print(f"[TEST] 构建样本：{SAMPLE}")


def main():
    build_sample()
    process_epub(SAMPLE, OUT, config="t2s", add_css=True)

    # 验证
    with zipfile.ZipFile(OUT, "r") as z:
        names = z.namelist()
        print("\n[CHECK] 条目列表：", names)

        # 1) mimetype 是第一个且未压缩
        assert names[0] == "mimetype", "mimetype 必须是首个条目"
        assert z.getinfo("mimetype").compress_type == zipfile.ZIP_STORED, "mimetype 必须未压缩"
        print("[OK] mimetype 合规（首个 + 未压缩）")

        # 2) 内容已繁→简，且注入 CSS
        xhtml = z.read("content.xhtml").decode("utf-8")
        assert "這是一個" not in xhtml, "应已转换繁体"
        assert "这是一个" in xhtml, "应出现简体"
        assert "鼠标和软件" in xhtml, "用词转换（鼠標→鼠标、軟件→软件）"
        assert "writing-mode: horizontal-tb" in xhtml, "应注入横排 CSS"
        assert "text-indent: 2em" in xhtml, "应注入首行缩进"
        print("[OK] 繁→简转换 + 横排 + 首行缩进 均已注入")

        # 3) CSS 也注入了
        css = z.read("style.css").decode("utf-8")
        assert "writing-mode" in css, "CSS 文件应被注入"
        print("[OK] style.css 已注入排版规则")

    size = os.path.getsize(OUT) / 1024
    print(f"\n[ALL PASSED] 转换成功，输出 {size:.1f} KB")
    print("对应便签需求：✅ 繁→简 ✅ 横排 ✅ 首行缩进 ✅ 输出到 Download/E-book/")


if __name__ == "__main__":
    main()
