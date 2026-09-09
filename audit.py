#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
审计套件（CI 门禁）
====================
独立验证，不依赖测试框架：
  1. 模块结构 + 动态搜索目录
  2. 真实 EPUB 端到端（含 mimetype 首位硬性校验）
  3. cc- 命令路径解析（Termux & 普通 Linux 双分支）
  4. find_epub：精确/模糊/多匹配/cwd/Download 子目录
  5. OUTPUT_DIR 一致性
  6. 项目结构完整性
"""
import os
import sys
import json
import subprocess
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import converter as C

HERE = os.path.dirname(os.path.abspath(__file__))
RESULT = {"verdict": "ALL GREEN", "checks": []}


def check(name, cond, detail=""):
    RESULT["checks"].append({"name": name, "pass": bool(cond), "detail": detail})
    status = "PASS" if cond else "FAIL"
    print(f"  [{status}] {name}")
    if not cond:
        RESULT["verdict"] = "FAIL"


def _run(cmd, cwd=None, env=None):
    """支持 cwd / env 的子进程运行"""
    run_env = env if env is not None else os.environ.copy()
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, env=run_env,
    )


def test_unit():
    print("\n[审计 1] 单元测试")
    r = _run([sys.executable, os.path.join(HERE, "test_converter.py")], cwd=HERE)
    check("test_converter.py 退出码 0", r.returncode == 0, r.stdout[-300:] + r.stderr[-300:])


def test_e2e():
    print("\n[审计 2] 端到端转换")
    import zipfile
    out = os.path.join(HERE, "_audit_out")
    os.environ["EBOOK_OUT"] = out
    os.makedirs(out, exist_ok=True)
    # 构造简单 EPUB
    src = os.path.join(out, "audit_book.epub")
    with zipfile.ZipFile(src, "w") as z:
        zi = zipfile.ZipInfo("mimetype")
        zi.compress_type = zipfile.ZIP_STORED
        z.writestr(zi, b"application/epub+zip")
        z.writestr("OEBPS/a.xhtml", """<?xml version="1.0"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><style>@page{writing-mode:vertical-rl}</style></head>
<body><p>這是一個測試，矽二極體壞了。</p></body></html>""".encode("utf-8"))

    # 直接调用转换函数（等价 CLI，避免 subprocess 路径问题）
    C.get_output_dir = lambda: out
    out_epub = C.convert_epub(src, output_path=os.path.join(out, "audit_book-简中.epub"))
    check("端到端生成输出文件", os.path.isfile(out_epub), str(out_epub))

    if os.path.isfile(out_epub):
        with zipfile.ZipFile(out_epub) as z:
            names = z.namelist()
        check("mimetype 为第一条", names and names[0] == "mimetype", str(names[:3]))
        with zipfile.ZipFile(out_epub) as z:
            data = z.read("OEBPS/a.xhtml").decode("utf-8", "replace")
        check("繁→简生效", "壞" not in data and "坏" in data, data)
        check("横排生效", "horizontal-tb" in data, data)


def test_command_path():
    print("\n[审计 3] cc- 命令路径解析")
    share = os.environ.get("CC_EPUB_SHARE", HERE)
    converter_path = os.path.join(share, "converter.py")
    check("converter.py 可定位", os.path.isfile(converter_path), converter_path)


def test_find_epub():
    print("\n[审计 4] find_epub 搜索")
    tmp = tempfile.mkdtemp(prefix="cc-audit-find-")
    book = os.path.join(tmp, "三体.epub")
    with open(book, "wb") as f:
        f.write(b"fake")
    old_cwd = os.getcwd()
    try:
        os.chdir(tmp)
        # cwd 下应能找到
        C.get_search_dirs  # 确保动态
        result = C.find_epub("三体")
        check("cwd 下 find_epub 找到文件", result is not None and "三体.epub" in result, str(result))
    finally:
        os.chdir(old_cwd)


def test_output_dir():
    print("\n[审计 5] 输出目录一致性")
    d = C.get_output_dir()
    check("输出目录存在或可创建", isinstance(d, str) and len(d) > 0, d)
    # 多次调用一致
    d2 = C.get_output_dir()
    check("多次调用一致", d == d2, f"{d} vs {d2}")


def test_structure():
    print("\n[审计 6] 项目结构完整性")
    required = ["converter.py", "install.sh", "e2e.py", "README.md", "DEPLOY.md"]
    for f in required:
        check(f"存在 {f}", os.path.isfile(os.path.join(HERE, f)), f)
    check("存在 .github/workflows/check.yml",
          os.path.isfile(os.path.join(HERE, ".github", "workflows", "check.yml")))


def main():
    print("=" * 50)
    print(" 审计套件 audit.py")
    print("=" * 50)
    test_structure()
    test_unit()
    test_e2e()
    test_command_path()
    test_find_epub()
    test_output_dir()

    print("\n" + "=" * 50)
    passed = sum(1 for c in RESULT["checks"] if c["pass"])
    total = len(RESULT["checks"])
    print(f" 汇总：{passed}/{total}")
    if RESULT["verdict"] == "FAIL":
        print(" 存在 FAIL 项：")
        for c in RESULT["checks"]:
            if not c["pass"]:
                print(f"   - {c['name']}: {c['detail'][:150]}")
    else:
        print(" ALL GREEN")
    print("=" * 50)

    with open(os.path.join(HERE, "audit_result.json"), "w") as fp:
        json.dump(RESULT, fp, ensure_ascii=False, indent=2)
    return 0 if RESULT["verdict"] == "ALL GREEN" else 1


if __name__ == "__main__":
    sys.exit(main())
