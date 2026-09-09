#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""单元测试：覆盖核心转换函数（不依赖完整 EPUB 流程）"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import converter as C


class TestConvertText(unittest.TestCase):
    def test_basic(self):
        self.assertIn("测试", C.convert_text("測試"))
        self.assertIn("电脑", C.convert_text("電腦"))
        self.assertIn("体", C.convert_text("體"))

    def test_vocab(self):
        # 词汇级转换
        out = C.convert_text("矽二極體")
        self.assertIn("硅", out)

    def test_empty(self):
        self.assertEqual(C.convert_text(""), "")
        self.assertIsNone(C.convert_text(None))


class TestHorizontal(unittest.TestCase):
    def test_css_vertical_to_horizontal(self):
        css = "body{writing-mode:vertical-rl;font-size:1em}"
        out = C.to_horizontal_css(css)
        self.assertIn("horizontal-tb", out)
        self.assertNotIn("vertical-rl", out)

    def test_inject_baseline(self):
        out = C.inject_horizontal_baseline("p{margin:1em}")
        self.assertIn("horizontal-tb", out)
        self.assertIn("@page", out)

    def test_unify_font(self):
        css = "body{font-family:'微軟正黑體',sans-serif}"
        out = C.unify_font_family(css)
        self.assertNotIn("font-family", out)


class TestPunctuation(unittest.TestCase):
    def test_normalize(self):
        self.assertEqual(C.normalize_punctuation("你好， 世界。"), "你好，世界。")
        self.assertEqual(C.normalize_punctuation("（ 括号 ）"), "（括号）")
        self.assertEqual(C.normalize_punctuation("， ，"), "，，")


class TestOutputDir(unittest.TestCase):
    def test_dynamic(self):
        # 输出目录应为动态解析（非固化）
        d = C.get_output_dir()
        self.assertTrue(os.path.isdir(d) or d.endswith("E-book"))
        # 多次调用返回一致
        d2 = C.get_output_dir()
        self.assertEqual(d, d2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
