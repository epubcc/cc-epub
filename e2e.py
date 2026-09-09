#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
e2e.py —— push 前本地闸门，严格对齐 .github/workflows/check.yml 的步骤。
从"全新解包"出发，真实构造一个繁体+竖排 EPUB，跑 converter，直接读输出文件判定。
任一断言失败立即非零退出，模拟 GitHub runner 的红灯。
"""
import os, sys, subprocess, zipfile, shutil, tempfile, json

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERTER = os.path.join(HERE, "converter.py")
SRC_EPUB = os.path.join(HERE, "_e2e_src.epub")
OUT_DIR = os.path.join(HERE, "_e2e_out")


def _find_output_epub():
    """converter 命名规则：原文件名_简体.epub，放在 EBOOK_OUT 下。"""
    for n in os.listdir(OUT_DIR):
        if n.endswith("_简体.epub"):
            return os.path.join(OUT_DIR, n)
    return None


def build_source_epub():
    """构造一个繁体中文 + CSS 竖排的合法 EPUB。"""
    import io
    buf = io.BytesIO()
    z = zipfile.ZipFile(buf, "w", zipfile.ZIP_STORED)
    z.writestr("mimetype", "application/epub+zip")
    z.writestr("META-INF/container.xml",
        '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>')
    css = """
@page { writing-mode: vertical-rl; }
body { writing-mode: vertical-rl; direction: ltr; }
"""
    html = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html><html xmlns="http://www.w3.org/1999/xhtml"><head><title>三體</title>
<link rel="stylesheet" type="text/css" href="style.css"/></head>
<body><h1>第一章</h1><p>這是一個測試文件，滑鼠裡面的矽二極體壞了。</p></body></html>"""
    opf = """<?xml version="1.0" encoding="utf-8"?>
<package version="3.0" xmlns="http://www.idpf.org/2007/opf"><metadata>
<dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">三體</dc:title></metadata>
<manifest><item id="html" href="content.xhtml" media-type="application/xhtml+xml"/>
<item id="css" href="style.css" media-type="text/css"/></manifest>
<spine><itemref idref="html"/></spine></package>"""
    z.writestr("OEBPS/style.css", css)
    z.writestr("OEBPS/content.xhtml", html)
    z.writestr("OEBPS/content.opf", opf)
    z.close()
    with open(SRC_EPUB, "wb") as f:
        f.write(buf.getvalue())


def step(name):
    def deco(fn):
        def wrap(*a, **k):
            print(f"[e2e] {name} ...", end=" ", flush=True)
            fn(*a, **k)
            print("PASS")
        return wrap
    return deco


@step("1/6 语法编译 (compileall)")
def s1():
    r = subprocess.run([sys.executable, "-m", "compileall", "-q", HERE],
                       capture_output=True, text=True)
    assert r.returncode == 0, f"compile 失败:\n{r.stderr}"


@step("2/6 项目结构完整")
def s2():
    for f in ["converter.py", "audit.py", "test_converter.py",
              "install.sh", "README.md", ".github/workflows/check.yml"]:
        assert os.path.exists(os.path.join(HERE, f)), f"缺失: {f}"


@step("3/6 单元测试 test_converter.py")
def s3():
    r = subprocess.run([sys.executable, os.path.join(HERE, "test_converter.py")],
                       capture_output=True, text=True)
    assert r.returncode == 0, f"单元测试失败:\n{r.stdout}\n{r.stderr}"


@step("4/6 审计套件 audit.py")
def s4():
    r = subprocess.run([sys.executable, os.path.join(HERE, "audit.py")],
                       capture_output=True, text=True)
    assert r.returncode == 0, f"audit 失败:\n{r.stdout}\n{r.stderr}"


@step("5/6 端到端转换 (繁体+竖排 EPUB)")
def s5():
    build_source_epub()
    os.makedirs(os.path.join(HERE, "_e2e_out"), exist_ok=True)
    env = os.environ.copy()
    env["EBOOK_OUT"] = os.path.join(HERE, "_e2e_out")
    r = subprocess.run([sys.executable, CONVERTER, SRC_EPUB],
                       capture_output=True, text=True, env=env)
    assert r.returncode == 0, f"转换失败:\n{r.stdout}\n{r.stderr}"
    out = _find_output_epub()
    assert out, f"EBOOK_OUT 下未找到 *_简体.epub: {OUT_DIR}"
    print(f"\n      输出文件: {os.path.basename(out)}")


@step("6/6 验证真实输出 (绿灯门禁)")
def s6():
    out = _find_output_epub()
    assert out, "未找到输出 epub"
    z = zipfile.ZipFile(out)
    names = z.namelist()
    assert names[0] == "mimetype", f"mimetype 非首位: {names[:3]}"
    body = "\n".join(z.read(n).decode("utf-8", "ignore") for n in names
                     if n.endswith((".xhtml", ".html", ".css", ".opf")))
    checks = {
        "壞→坏 (OpenCC tw2sp 接入)": "坏了" in body and "壞了" not in body,
        "矽二極體→硅二极管 (词汇级)": "硅二极管" in body,
        "vertical-rl→horizontal-tb (横排)": "horizontal-tb" in body,
        "无残留竖排声明": "vertical-rl" not in body and "vertical-lr" not in body,
    }
    print()
    for k, ok in checks.items():
        print(f"      {'✓' if ok else '✗'} {k}")
        assert ok, f"断言失败: {k}"
    report = {"verdict": "ALL_GREEN", "steps": 6, "passed": 6, "checks": checks}
    with open(os.path.join(HERE, "e2e_result.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)


def main():
    for fn in [s1, s2, s3, s4, s5, s6]:
        fn()
    print("\n[e2e] ALL GREEN —— 可以 push")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as e:
        print(f"FAIL\n{e}", file=sys.stderr)
        sys.exit(1)
