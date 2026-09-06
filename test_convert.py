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
        z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
            '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="content.xhtml"/></rootfiles></container>')
        z.writestr("content.xhtml",
            '<?xml version="1.0" encoding="UTF-8"?>'
            '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>\u6e2c\u8a66</title>'
            '<style>p{color:red; display:none; position:absolute; float:left}</style></head><body>'
            '<h1>\u9019\u662f\u4e00\u500b\u7e41\u9ad4\u4e2d\u6587\u6e2c\u8bd5</h1>'
            '<p>\u9f20\u6a19\u548c\u8edf\u4ef6\uff0c\u767c\u5c55\u820e\u9aed\u578b\u3002</p>'
            '<p>\u7b2c\u4e8c\u7ae0\u5185\u5bb9\u3002</p></body></html>')
        z.writestr("style.css", "p { line-height: 1.6; }")
    print(f"[TEST] 构建样本：{SAMPLE}")


def build_sample_gbk():
    """构造一个 GBK 编码的测试 EPUB（验证编码容错）。"""
    sample_gbk = os.path.join(HERE, "sample_gbk.epub")
    with zipfile.ZipFile(sample_gbk, "w") as z:
        z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
            '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="content.xhtml"/></rootfiles></container>')
        gbk_content = '<?xml version="1.0" encoding="GBK"?>'                       '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>\u6e2c\u8a66</title></head>'                       '<body><p>\u9019\u662f\u4e00\u500b\u6e2c\u8bd5\u3002</p></body></html>'.encode('gbk', errors='replace')
        z.writestr("content.xhtml", gbk_content)
    print(f"[TEST] 构建 GBK 样本：{sample_gbk}")
    return sample_gbk


def build_sample_kindle():
    """构造一个包含 Kindle 不友好 CSS 的测试 EPUB。"""
    sample_kindle = os.path.join(HERE, "sample_kindle.epub")
    kindle_css = """
    @font-face {
        font-family: 'CustomFont';
        src: url('fonts/custom.woff2') format('woff2');
    }
    body { font-family: 'CustomFont', serif; }
    .hidden { display: none; }
    .float-box { position: absolute; top: 0; left: 0; }
    .pull-left { float: left; }
    p { line-height: 1.6; }
    """
    kindle_html = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<html xmlns="http://www.w3.org/1999/xhtml">\n'
        '<head><title>Kindle\u6e2c\u8bd5</title>\n'
        '<style>' + kindle_css + '</style>\n'
        '</head>\n'
        '<body>\n'
        '<h1>Kindle\u517c\u5bb9\u6027\u6e2c\u8bd5</h1>\n'
        '<p class="hidden">\u8fd9\u6bb5\u5e94\u8be5\u88ab\u9690\u85cf</p>\n'
        '<p class="float-box">\u6d6e\u52a8\u6846</p>\n'
        '<p>\u6b63\u5e38\u6bb5\u843d\u5185\u5bb9\u3002</p>\n'
        '</body>\n'
        '</html>'
    )

    opf_content = (
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">\n'
        '  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">\n'
        '    <dc:identifier id="uid">test-001</dc:identifier>\n'
        '    <dc:language>ja</dc:language>\n'
        '    <dc:title>Kindle\u6e2c\u8bd5</dc:title>\n'
        '  </metadata>\n'
        '  <manifest>\n'
        '    <item id="content" href="content.xhtml" media-type="application/xhtml+xml"/>\n'
        '  </manifest>\n'
        '  <spine><itemref idref="content"/></spine>\n'
        '</package>'
    )

    with zipfile.ZipFile(sample_kindle, "w") as z:
        z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml",
            '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
            '<rootfiles><rootfile full-path="content.opf"/></rootfiles></container>')
        z.writestr("content.xhtml", kindle_html.encode("utf-8"))
        z.writestr("content.opf", opf_content.encode("utf-8"))
    print(f"[TEST] 构建 Kindle 兼容性样本：{sample_kindle}")
    return sample_kindle


def main():
    passed = 0
    failed = 0

    # --- 测试 1：基本繁→简 + 横排 + 首行缩进 ---
    print("\n" + "=" * 50)
    print("测试 1：基本繁→简 + 横排 + 首行缩进")
    print("=" * 50)
    build_sample()
    process_epub(SAMPLE, OUT, config="t2s", add_css=True)

    try:
        with zipfile.ZipFile(OUT, "r") as z:
            names = z.namelist()
            print("\n[CHECK] 条目列表：", names)

            assert names[0] == "mimetype", "mimetype 必须是首个条目"
            assert z.getinfo("mimetype").compress_type == zipfile.ZIP_STORED, "mimetype 必须未压缩"
            print("[OK] mimetype 合规（首个 + 未压缩）")

            xhtml = z.read("content.xhtml").decode("utf-8")
            assert "\u9019\u662f\u4e00\u500b" not in xhtml, "应已转换繁体"
            assert "writing-mode: horizontal-tb" in xhtml, "应注入横排 CSS"
            assert "text-indent: 2em" in xhtml, "应注入首行缩进"
            print("[OK] 繁→简转换 + 横排 + 首行缩进 均已注入")

            css = z.read("style.css").decode("utf-8")
            assert "writing-mode" in css, "CSS 文件应被注入"
            print("[OK] style.css 已注入排版规则")

            assert "display: none" not in xhtml, "display:none 应被清理"
            assert "position: absolute" not in xhtml, "position:absolute 应被清理"
            assert "float: left" not in xhtml, "float:left 应被清理"
            print("[OK] Kindle 不友好 CSS 已清理（display:none / position:absolute / float）")

        passed += 1
    except AssertionError as e:
        print(f"[FAIL] {e}")
        failed += 1

    # --- 测试 2：编码容错（GBK 文件） ---
    print("\n" + "=" * 50)
    print("测试 2：编码容错（GBK 文件）")
    print("=" * 50)
    gbk_sample = build_sample_gbk()
    gbk_out = os.path.join(HERE, "sample_gbk-cc.epub")
    try:
        process_epub(gbk_sample, gbk_out, config="t2s", add_css=True)
        print("[OK] GBK 文件未崩溃，编码容错通过")
        passed += 1
    except UnicodeDecodeError as e:
        print(f"[FAIL] GBK 文件解码失败：{e}")
        failed += 1
    except Exception as e:
        print(f"[FAIL] GBK 文件处理异常：{e}")
        failed += 1

    # --- 测试 3：覆盖保护 ---
    print("\n" + "=" * 50)
    print("测试 3：覆盖保护（输出文件已存在时提示）")
    print("=" * 50)
    process_epub(SAMPLE, OUT, config="t2s", add_css=True)
    import io
    old_stdin = sys.stdin
    sys.stdin = io.StringIO("n\n")
    try:
        captured = False
        old_exit = sys.exit
        def mock_exit(code=0):
            nonlocal captured
            if code != 0:
                captured = True
        sys.exit = mock_exit
        process_epub(SAMPLE, OUT, config="t2s", add_css=True)
        sys.exit = old_exit
        if captured:
            print("[OK] 覆盖保护生效（输入 'n' 时取消操作）")
            passed += 1
        else:
            print("[WARN] 覆盖保护未生效（可能未正确检测已存在文件）")
            failed += 1
    except Exception as e:
        sys.exit = old_exit
        print(f"[WARN] 覆盖保护测试异常：{e}")
        failed += 1
    finally:
        sys.stdin = old_stdin

    # --- 测试 4：Kindle 兼容性 ---
    print("\n" + "=" * 50)
    print("测试 4：Kindle 兼容性（字体移除 / CSS 清理 / 语言代码修正）")
    print("=" * 50)
    kindle_sample = build_sample_kindle()
    kindle_out = os.path.join(HERE, "sample_kindle-cc.epub")
    try:
        process_epub(kindle_sample, kindle_out, config="t2s", add_css=True)
        with zipfile.ZipFile(kindle_out, "r") as z:
            xhtml = z.read("content.xhtml").decode("utf-8")
            opf = z.read("content.opf").decode("utf-8")

            assert "@font-face" not in xhtml, "@font-face 应被移除"
            print("[OK] @font-face 字体声明已移除")

            assert "display: none" not in xhtml, "display:none 应被清理"
            print("[OK] display:none 已清理")

            assert "position: absolute" not in xhtml, "position:absolute 应被清理"
            print("[OK] position:absolute 已清理")

            assert "float: left" not in xhtml, "float:left 应被清理"
            print("[OK] float:left 已清理")

            assert "zh-CN" in opf, "OPF 语言代码应设为 zh-CN"
            print("[OK] OPF 语言代码已设为 zh-CN")

            assert 'encoding="UTF-8"' in xhtml or 'encoding="utf-8"' in xhtml, "应声明 UTF-8 编码"
            print("[OK] XHTML 编码声明为 UTF-8")

        passed += 1
    except AssertionError as e:
        print(f"[FAIL] {e}")
        failed += 1
    except Exception as e:
        print(f"[FAIL] 处理异常：{e}")
        failed += 1

    # --- 总结 ---
    print("\n" + "=" * 50)
    print(f"测试结果：{passed} 通过，{failed} 失败")
    if failed == 0:
        print("[ALL PASSED] 全部测试通过！")
    else:
        print("[SOME FAILED] 有部分测试失败，请检查。")
    print("=" * 50)


if __name__ == "__main__":
    main()
