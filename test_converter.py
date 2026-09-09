"""Unit tests for converter.py (run directly: python test_converter.py)."""
import os
import sys
import zipfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import converter  # noqa


def assert_eq(actual, expected, msg):
    if actual != expected:
        print(f"  FAIL {msg}: {actual!r} != {expected!r}")
        sys.exit(1)


def test_text_conversion():
    s = converter.convert_text("這是一個測試，矽二極體壞了")
    assert "这是一个测试，硅二极管坏了" in s, s
    print("  [OK] convert_text (繁->简 + 词汇: 矽二極體->硅二极管)")


def test_horizontal():
    css = "@page{writing-mode:vertical-rl}"
    out = converter._to_horizontal(css)
    assert "horizontal-tb" in out and "vertical-rl" not in out, out
    print("  [OK] _to_horizontal (vertical-rl -> horizontal-tb)")


def test_epub_roundtrip():
    work = tempfile.mkdtemp()
    src = os.path.join(work, "in.epub")
    files = {
        "mimetype": b"application/epub+zip",
        "content.opf": b'<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">T</dc:title></metadata><manifest><item id="c" href="a.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>',
        "a.xhtml": "<html><head><style>@page{writing-mode:vertical-rl}</style></head><body><p>這是一個測試，矽二極體壞了</p></body></html>".encode("utf-8"),
    }
    with zipfile.ZipFile(src, "w", zipfile.ZIP_STORED) as z:
        z.writestr("mimetype", files["mimetype"], zipfile.ZIP_STORED)
        for n, d in files.items():
            if n == "mimetype":
                continue
            z.writestr(n, d)

    out = os.path.join(work, "out.epub")
    converter.EPUBConverter().convert_epub(src, out)

    with zipfile.ZipFile(out) as z:
        assert z.namelist()[0] == "mimetype", z.namelist()
        xhtml = z.read("a.xhtml").decode("utf-8")
    assert "硅二极管" in xhtml, xhtml
    assert "horizontal-tb" in xhtml, xhtml
    assert "vertical-rl" not in xhtml, xhtml
    print("  [OK] EPUB roundtrip (mimetype-first + 简 + horizontal)")


def test_output_dir_fresh_env():
    """On a fresh env without ~/Download, output should still land in ~/Download/E-book."""
    import importlib
    saved = {"HOME": os.environ.get("HOME"), "EBOOK_OUT": os.environ.get("EBOOK_OUT")}
    try:
        with tempfile.TemporaryDirectory() as home:
            os.environ["HOME"] = home
            os.environ.pop("EBOOK_OUT", None)  # 隔离：不继承外层 CI 的锁定目录
            sys.modules.pop("converter", None)
            import converter as C
            importlib.reload(C)
            out = C.get_output_dir()
            assert out == os.path.join(home, "Download", "E-book"), out
            assert os.path.isdir(out), out
            print("  [OK] get_output_dir -> ~/Download/E-book (fresh env, no drift)")
    finally:
        for k, v in saved.items():
            if v is not None:
                os.environ[k] = v
            else:
                os.environ.pop(k, None)


if __name__ == "__main__":
    print("test_converter.py:")
    test_text_conversion()
    test_horizontal()
    test_epub_roundtrip()
    test_output_dir_fresh_env()
    print("\n测试通过！转换工具工作正常")
