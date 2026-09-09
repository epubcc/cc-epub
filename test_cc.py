#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""cc.py 单元测试 + 真实 EPUB 端到端转换验证（unittest 框架）。

运行: python test_cc.py [-v]
只需标准库 + beautifulsoup4；无 opencc 时自动降级（不影响核心断言）。
"""
import os, re, sys, zipfile, tempfile, shutil, subprocess, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import cc  # noqa: E402


def make_real_epub(dest_dir):
    """构造一个港台繁体 + 竖排 + 复杂 CSS 的真实 EPUB，返回 (src_epub, opf_title)"""
    book = os.path.join(dest_dir, "book")
    os.makedirs(os.path.join(book, "OEBPS", "css"))

    with open(os.path.join(book, "mimetype"), "w", encoding="utf-8") as f:
        f.write("application/epub+zip")

    opf = ('<?xml version="1.0" encoding="UTF-8"?>\n'
           '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">\n'
           '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
           '<dc:title>原子習慣：細微改變帶來巨大成效</dc:title>\n'
           '<dc:creator>James Clear</dc:creator>\n'
           '<guide><reference type="toc" title="目錄" href="toc.ncx"/></guide>\n'
           '</metadata>\n<manifest>\n'
           '<item id="html" href="ch1.html" media-type="application/xhtml+xml"/>\n'
           '<item id="css" href="css/style.css" media-type="text/css"/>\n'
           '<item id="img" href="img.png" media-type="image/png"/>\n'
           '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n'
           '</manifest>\n<spine toc="ncx"><itemref idref="html"/></spine>\n</package>')
    with open(os.path.join(book, "OEBPS", "content.opf"), "w", encoding="utf-8") as f:
        f.write(opf)

    css = ('@font-face { font-family: "MingLiU"; src: url(font.ttf); }\n'
           'body { writing-mode: vertical-rl; font-family: "微軟正黑體"; font-size: 18px; }\n'
           'p { margin-left: 2em; text-indent: 4em; font-size: 1.1em; }\n'
           '.indent { text-indent: 4em; }')
    with open(os.path.join(book, "OEBPS", "css", "style.css"), "w", encoding="utf-8") as f:
        f.write(css)

    html = ('<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" style="writing-mode:vertical-rl">\n'
            '<head><title>原子習慣</title>\n<style type="text/css">\n'
            'p { text-indent: 4em; font-family: MingLiU; writing-mode: vertical-rl; }\n'
            'body { font-family: "微軟正黑體"; }\n</style>\n</head>\n<body>\n'
            '<h1>第一章　習慣的驚人力量</h1>\n'
            '<p>\u3000\u3000「習慣是改變命運的關鍵。」這是書中的核心觀點﹐作者強調﹒</p>\n'
            '<p>\u3000\u3000『每天進步百分之一』，一年後將會脫胎換骨\u2014\u2014真的嗎？</p>\n'
            '<p>行內 中間 空格 應 保留。</p>\n'
            '<p class="indent">第二個段落﹐延續前文。</p>\n'
            '</body>\n</html>')
    with open(os.path.join(book, "OEBPS", "ch1.html"), "w", encoding="utf-8") as f:
        f.write(html)

    ncx = ('<?xml version="1.0" encoding="UTF-8"?>\n<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/">'
           '<head/><docTitle><text>原子習慣</text></docTitle>\n<navMap>\n'
           '<navPoint id="p1"><navLabel><text>第一章　習慣</text></navLabel>'
           '<content src="ch1.html"/></navPoint>\n</navMap>\n</ncx>')
    with open(os.path.join(book, "OEBPS", "toc.ncx"), "w", encoding="utf-8") as f:
        f.write(ncx)

    with open(os.path.join(book, "OEBPS", "img.png"), "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + b"\x00" * 20)

    src_epub = os.path.join(dest_dir, "原子習慣.epub")
    with zipfile.ZipFile(src_epub, "w") as z:
        mt = os.path.join(book, "mimetype")
        z.write(mt, "mimetype", compress_type=zipfile.ZIP_STORED)
        for root, _, files in os.walk(book):
            for fn in files:
                fp = os.path.join(root, fn)
                z.write(fp, os.path.relpath(fp, book), compress_type=zipfile.ZIP_DEFLATED)
    return src_epub


class PunctuationTests(unittest.TestCase):
    def test_corner_quotes(self):
        self.assertEqual(cc.normalize_punctuation("\u300c\u300d"), "\u201c\u201d")
        self.assertEqual(cc.normalize_punctuation("\u300e\u300f"), "\u2018\u2019")

    def test_hk_tw_small_marks(self):
        self.assertEqual(cc.normalize_punctuation("\ufe50"), "\uff0c")  # ﹐→，
        self.assertEqual(cc.normalize_punctuation("\ufe51"), "\u3002")  # ﹒→。
        self.assertEqual(cc.normalize_punctuation("\uff64"), "\uff0c")
        self.assertEqual(cc.normalize_punctuation("\uff0e"), "\u00b7")  # ．→·

    def test_ellipsis_no_duplication(self):
        # ★ 关键：单个 … 不能翻倍成 ……
        self.assertEqual(cc.normalize_punctuation("\u2026"), "\u2026")
        self.assertEqual(cc.normalize_punctuation("\u2026\u2026"), "\u2026\u2026")
        self.assertEqual(cc.normalize_punctuation("....."), "\u2026\u2026")

    def test_dash(self):
        self.assertIn("——", cc.normalize_punctuation("—–-"))
        self.assertIn("——", cc.normalize_punctuation("真的嗎——是的"))


class CSSTests(unittest.TestCase):
    def test_css_dash_protected(self):
        # ★ 核心回归：CSS 属性名里的 - 不能被当成破折号破坏
        out = cc.clean_css_file("p { font-family: serif; margin-left: 2em; text-indent: 4em; }")
        self.assertIn("font-family", out)          # 注入的覆盖规则保留了属性名
        self.assertNotIn("font——family", out)       # 未被破折号破坏
        self.assertNotIn("margin-left", out)         # 原 CSS 的缩进声明已清除
        self.assertNotIn("4em", out)                # ★ 原 text-indent:4em 已清除（防叠加）
        self.assertIn("text-indent: 2em !important", out)  # 注入的 2em 覆盖

    def test_css_remove_fontface_and_vertical(self):
        out = cc.clean_css_file('@font-face{x} p{writing-mode:vertical-rl;font-size:12px}')
        self.assertNotIn("@font-face", out)
        self.assertNotIn("vertical-rl", out)
        # 原 CSS 的 font-size:12px 应被清除（注入规则自带的 font-size:1em 属正常覆盖）
        self.assertNotIn("12px", out)


class EndToEndTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workdir = tempfile.mkdtemp()
        # 注入 fake `opencc` 命令（模拟 Termux opencc-tools），让繁→简结果确定。
        # 支持 `-i IN -o OUT`（文件模式）与 stdin/stdout，与生产 opencc 行为一致。
        fake = os.path.join(cls.workdir, "bin")
        os.makedirs(fake)
        with open(os.path.join(fake, "opencc"), "w", encoding="utf-8") as f:
            f.write('#!/usr/bin/env python3\n')
            f.write('import sys, importlib.util, os\n')
            f.write('spec = importlib.util.spec_from_file_location("cc", %r)\n' % os.path.join(HERE, "cc.py"))
            f.write('m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n')
            f.write('args = sys.argv[1:]\n')
            f.write('inp, out = None, None\n')
            f.write('if "-i" in args: inp = args[args.index("-i") + 1]\n')
            f.write('if "-o" in args: out = args[args.index("-o") + 1]\n')
            f.write('data = open(inp, encoding="utf-8").read() if inp else sys.stdin.read()\n')
            f.write('result = m._fallback_t2s(data)\n')
            f.write('if out: open(out, "w", encoding="utf-8").write(result)\n')
            f.write('else: sys.stdout.write(result)\n')
        os.chmod(os.path.join(fake, "opencc"), 0o755)
        cls._orig_path = os.environ.get("PATH", "")
        os.environ["PATH"] = fake + os.pathsep + cls._orig_path

        cls.src_epub = make_real_epub(cls.workdir)
        cls.out_dir = os.path.join(cls.workdir, "out")
        os.makedirs(cls.out_dir)
        cls._orig_out = cc.OUT_DIR
        cc.OUT_DIR = cls.out_dir
        cc.process_epub(cls.src_epub)
        outputs = [f for f in os.listdir(cls.out_dir) if f.endswith(".epub")]
        cls.outputs = outputs
        cls.out_epub = os.path.join(cls.out_dir, outputs[0]) if outputs else None
        # 解压
        cls.unzipped = os.path.join(cls.workdir, "unz")
        os.makedirs(cls.unzipped)
        with zipfile.ZipFile(cls.out_epub) as z:
            z.extractall(cls.unzipped)
        oebps = os.path.join(cls.unzipped, "OEBPS")

        def rd(rel):
            with open(os.path.join(oebps, rel), "r", encoding="utf-8") as f:
                return f.read()
        cls.html = rd("ch1.html")
        cls.css = rd(os.path.join("css", "style.css"))
        cls.opf = rd("content.opf")
        cls.ncx = rd("toc.ncx")

    @classmethod
    def tearDownClass(cls):
        cc.OUT_DIR = cls._orig_out
        shutil.rmtree(cls.workdir, ignore_errors=True)

    # --- 命名（需求⑧）---
    def test_naming_is_title_based(self):
        self.assertEqual(len(self.outputs), 1, f"应输出1个文件，实际{self.outputs}")
        self.assertEqual(self.outputs[0], "原子习惯：细微改变带来巨大成效-简中.epub")

    # --- 横排 + 2em + 无 4em（痛点⑧）---
    def test_horizontal_and_2em(self):
        self.assertIn("horizontal-tb", self.html)
        self.assertIn("text-indent: 2em !important", self.html)

    def test_no_4em_residue(self):
        # ★ 痛点⑧核心：不得残留 4em（含被破折号破坏的 4——em）
        self.assertNotIn("4em", self.html)
        self.assertNotIn("4——em", self.html)

    def test_no_double_dash_in_css(self):
        # CSS 连字符保护：text-indent / font-family 等不得被拆坏
        self.assertNotIn("text——indent", self.html)
        self.assertNotIn("font——family", self.html)
        self.assertNotIn("vertical——rl", self.html)

    # --- 段首空格清除 + 中间空格保留（需求②）---
    def test_leading_space_cleared(self):
        self.assertNotIn("\u3000\u3000", self.html)

    def test_middle_spaces_preserved(self):
        # 段中间的空格应保留（行内/行间排版）；断言用"转换后"的实际文本
        self.assertTrue(
            "行内 中間 空格" in self.html or "行内 中间 空格" in self.html
            or "行內 中間 空格" in self.html,
            msg="中间空格未保留，实际段落片段: " + self.html[-400:],
        )

    # --- 繁简 / 标点 ---
    def test_traditional_to_simplified(self):
        # 无 opencc 时由 _fallback_t2s 兜底；有 opencc 时精确转换
        self.assertNotIn("習慣", self.html)
        self.assertIn("习惯", self.html)

    def test_corner_quotes_converted(self):
        self.assertNotIn("\u300c", self.html)
        self.assertIn("\u201c", self.html)

    def test_small_comma_converted(self):
        self.assertNotIn("\ufe50", self.html)

    # --- style 内嵌清洗 ---
    def test_inline_style_cleaned(self):
        self.assertNotIn("@font-face", self.html)
        self.assertNotIn("vertical-rl", self.html)

    def test_p_inline_style_removed(self):
        body = self.html.split("<body>")[-1]
        self.assertNotIn("<p style=", body)
        self.assertNotIn("<p class=", body)

    # --- 保留插图/目录结构 ---
    def test_image_preserved(self):
        img = os.path.join(self.unzipped, "OEBPS", "img.png")
        self.assertTrue(os.path.exists(img))
        with open(img, "rb") as f:
            self.assertTrue(f.read().startswith(b"\x89PNG"))

    def test_ncx_structure_preserved(self):
        self.assertIn("<navPoint", self.ncx)

    # --- OPF / NCX 繁转简 ---
    def test_opf_title_simplified(self):
        self.assertNotIn("原子習慣", self.opf)
        self.assertIn("原子习惯", self.opf)

    def test_opf_progression_ltr(self):
        self.assertIn('page-progression-direction="ltr"', self.opf)

    def test_ncx_simplified(self):
        self.assertNotIn("習慣", self.ncx)
        self.assertIn("习惯", self.ncx)

    # --- EPUB 规范（需求⑨防白页）---
    def test_mimetype_first_and_stored(self):
        with zipfile.ZipFile(self.out_epub) as z:
            self.assertEqual(z.namelist()[0], "mimetype")
            self.assertEqual(z.getinfo("mimetype").compress_type, zipfile.ZIP_STORED)
            self.assertEqual(z.read("mimetype").decode(), "application/epub+zip")


class CommandFormatTests(unittest.TestCase):
    """需求⑤：命令格式 `cc 书名`。验证 CLI 可调起完整流程。"""

    def test_cc_help(self):
        r = subprocess.run([sys.executable, os.path.join(HERE, "cc.py"), "--help"],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertIn("cc", r.stdout)

    def test_cc_run_with_path(self):
        # 需求⑤：命令格式 `cc <文件路径>`。验证 CLI 能跑起完整流程、产出"*简中.epub"。
        workdir = tempfile.mkdtemp()
        # 为子进程注入 fake opencc（与 setUpClass 同源）
        fake = os.path.join(workdir, "bin")
        os.makedirs(fake)
        with open(os.path.join(fake, "opencc"), "w", encoding="utf-8") as f:
            f.write('#!/usr/bin/env python3\n')
            f.write('import sys, importlib.util, os\n')
            f.write('spec = importlib.util.spec_from_file_location("cc", %r)\n' % os.path.join(HERE, "cc.py"))
            f.write('m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n')
            f.write('args = sys.argv[1:]\n')
            f.write('inp, out = None, None\n')
            f.write('if "-i" in args: inp = args[args.index("-i") + 1]\n')
            f.write('if "-o" in args: out = args[args.index("-o") + 1]\n')
            f.write('data = open(inp, encoding="utf-8").read() if inp else sys.stdin.read()\n')
            f.write('result = m._fallback_t2s(data)\n')
            f.write('if out: open(out, "w", encoding="utf-8").write(result)\n')
            f.write('else: sys.stdout.write(result)\n')
        os.chmod(os.path.join(fake, "opencc"), 0o755)
        env = os.environ.copy()
        env["PATH"] = fake + os.pathsep + env.get("PATH", "")

        src = make_real_epub(workdir)
        out = os.path.join(workdir, "result")
        os.makedirs(out)
        script = (f"import cc,sys; "
                  f"cc.OUT_DIR={out!r}; "
                  f"cc.main([{src!r}])")
        r = subprocess.run([sys.executable, "-c", script],
                           capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0,
                         msg=(r.stderr[-500:] or r.stdout[-500:]))
        self.assertTrue(any(f.endswith("-简中.epub") for f in os.listdir(out)),
                        msg=f"输出目录: {os.listdir(out)}; stdout={r.stdout[-300:]}")
        shutil.rmtree(workdir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
