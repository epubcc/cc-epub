"""Audit suite for cc-epub (kept minimal & self-contained).

Mirrors the gates enforced by .github/workflows/check.yml so that
`python audit.py` locally reproduces what CI asserts.
"""
import os
import sys
import zipfile
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERTER = os.path.join(HERE, "converter.py")


def _run(cmd, cwd=None):
    import subprocess
    return subprocess.run(cmd, capture_output=True, text=True, cwd=cwd)


def test_syntax():
    r = _run([sys.executable, "-m", "compileall", "-q", HERE])
    assert r.returncode == 0, r.stderr
    print("  [OK] syntax (compileall)")


def test_unit():
    r = _run([sys.executable, "test_converter.py"], cwd=HERE)
    assert r.returncode == 0, r.stdout + r.stderr
    print("  [OK] test_converter.py")


def test_e2e():
    """Real EPUB: 繁体 + vertical-rl -> assert 简体 + horizontal-tb + mimetype-first."""
    import subprocess
    work = tempfile.mkdtemp(prefix="audit_")
    os.makedirs(os.path.join(work, "Download"), exist_ok=True)
    src = os.path.join(work, "三体.epub")
    files = {
        "mimetype": b"application/epub+zip",
        "META-INF/container.xml": b"""<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>""",
        "content.opf": b"""<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata><dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">Test</dc:title></metadata><manifest><item id="c" href="content.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>""",
        "content.xhtml": "<!DOCTYPE html><html><head><style>@page{writing-mode:vertical-rl}</style></head><body><p>這是一個測試，矽二極體壞了</p></body></html>".encode("utf-8"),
    }
    with zipfile.ZipFile(src, "w", zipfile.ZIP_STORED) as z:
        z.writestr("mimetype", files["mimetype"], zipfile.ZIP_STORED)
        for name, data in files.items():
            if name == "mimetype":
                continue
            z.writestr(name, data)

    env = os.environ.copy()
    env["HOME"] = work
    env["XDG_DOWNLOAD_DIR"] = os.path.join(work, "Download")
    env.pop("EBOOK_OUT", None)  # 自包含：输出落到 HOME/Download/E-book，与下方查找逻辑一致
    r = subprocess.run([sys.executable, CONVERTER, src], cwd=HERE, env=env, capture_output=True, text=True)
    assert r.returncode == 0, f"converter failed:\n{r.stderr}\n{r.stdout}"

    out = None
    for cand in [os.path.join(work, "Download", "E-book"), os.path.join(work, "E-book")]:
        if os.path.isdir(cand):
            eps = [f for f in os.listdir(cand) if f.endswith(".epub")]
            if eps:
                out = os.path.join(cand, eps[0])
                break
    assert out and os.path.exists(out), "no output epub"

    with zipfile.ZipFile(out) as z:
        assert z.namelist()[0] == "mimetype"
        xhtml = z.read("content.xhtml").decode("utf-8", "replace")
    assert "硅二极管" in xhtml
    assert "horizontal-tb" in xhtml
    assert "vertical-rl" not in xhtml
    assert "這" not in xhtml and "个" in xhtml
    print("  [OK] end-to-end (real EPUB -> 简/horizontal/mimetype-first)")


def main():
    print("audit.py — running gates (same as CI):")
    test_syntax()
    test_unit()
    test_e2e()
    print("\nALL AUDIT GATES PASSED")


if __name__ == "__main__":
    main()
