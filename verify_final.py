#!/usr/bin/env python3
"""最终验收：严格核对上传清单 + 真实端到端跑测 (cc-epub v2.6)"""
import os, sys, zipfile, shutil, tempfile, re

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# ===== 1. 严格白名单 =====
REQUIRED = [
    ".gitignore", "README.md",
    "cc_epub.py", "install.sh", "install_opencc.py",
    "verify_note.py", "verify_final.py",
    "run_all.sh", "run_tests.sh", "test_install.sh",
    "test_pkgname_contract.py", "test_fix_termux_pkg_names.sh",
    "test_opencc_fallback.py", "test_termux_libopencc.py",
]
FORBIDDEN = ["__pycache__", ".git", "demo.py", "lint_args.py"]

print("=" * 60)
print("【检查 1】文件清单严格核对")
print("=" * 60)
actual = set(os.listdir(HERE))
missing = [f for f in REQUIRED if f not in actual]
extra = sorted(actual - set(REQUIRED))
# 禁止的是「目录」(.git/) 与「目录前缀」(__pycache__/)，不误伤文件 .gitignore
forbidden_found = [f for f in actual
                   if f in (".git", "__pycache__") or f.startswith("__pycache__")]
for f in REQUIRED:
    print(f"  {'✅' if f in actual else '❌ 缺失'} {f}")
print(f"\n缺失: {missing if missing else '无'}")
print(f"多余（不应上传）: {extra if extra else '无'}")
print(f"禁止项: {forbidden_found if forbidden_found else '无'}")

# ===== 2. 静态核对 cc_epub.py 关键实现 =====
print("\n" + "=" * 60)
print("【检查 2】关键实现静态核对")
print("=" * 60)
cc_src = open(os.path.join(HERE, "cc_epub.py"), encoding="utf-8").read()
ins_src = open(os.path.join(HERE, "install.sh"), encoding="utf-8").read()
checks = [
    ("包名防御 libopencc / fix_termux (install.sh)", "libopencc" in ins_src or "fix_termux" in ins_src),
    ("_normalize_config 防 .json.json", "_normalize_config" in cc_src),
    ("output_path 用 CONFIGS 查目标语言(修后缀)", "CONFIGS" in cc_src and ".traditional.epub" in cc_src),
    ("防白页 清 @font-face", "@font-face" in cc_src and ("sub" in cc_src or "delete" in cc_src or "remove" in cc_src)),
    ("横排 horizontal-tb", "horizontal-tb" in cc_src),
    ("首行缩进 text-indent", "text-indent" in cc_src),
    ("mimetype ZIP_STORED 合规", "ZIP_STORED" in cc_src),
    ("dc:language 元数据", "dc:language" in cc_src),
]
static_ok = 0
for name, ok in checks:
    print(f"  {'✅' if ok else '❌'} {name}")
    static_ok += ok
print(f"静态核对: {static_ok}/{len(checks)}")

# ===== 3. 真实端到端跑测 =====
print("\n" + "=" * 60)
print("【检查 3】真实端到端转换 (真实 opencc)")
print("=" * 60)
score = 0
try:
    from cc_epub import process_epub
    HAVE = True
except Exception as e:
    print(f"  ⚠️ 导入失败: {e}")
    HAVE = False

if HAVE:
    tmp = tempfile.mkdtemp()
    epub_in = os.path.join(tmp, "in.epub")
    z = zipfile.ZipFile(epub_in, "w", zipfile.ZIP_STORED)
    z.writestr("mimetype", "application/epub+zip")
    z.writestr("OEBPS/content.xhtml",
               '<html><head><style>@font-face{font-family:MingLiu}</style></head>'
               '<body>這是一個繁體測試，包含軟體、資料、滑鼠、程式設計。</body></html>')
    z.writestr("OEBPS/style.css", "@font-face{font-family:MingLiu}\nbody{font-family:MingLiu}")
    z.writestr("OEBPS/fonts/MingLiu.ttf", b"\x00")
    z.close()

    # 3a 繁→简 tw2sp
    out_s = os.path.join(tmp, "out.simplified.epub")
    process_epub(epub_in, out_s, "tw2sp", do_css=True)
    cs = zipfile.ZipFile(out_s).read("OEBPS/content.xhtml").decode("utf-8")
    ss = zipfile.ZipFile(out_s).read("OEBPS/style.css").decode("utf-8")
    for trad, simp in [("軟體", "软件"), ("資料", "数据"), ("滑鼠", "鼠标"), ("程式設計", "编程")]:
        ok = (trad not in cs) and (simp in cs)
        print(f"  {'✅' if ok else '❌'} 繁→简: {trad} → {simp}")
        score += ok
    ok = "@font-face" not in ss
    print(f"  {'✅' if ok else '❌'} 防白页: style.css 清除 @font-face")
    score += ok
    ok = ("horizontal-tb" in ss) and ("text-indent" in ss)
    print(f"  {'✅' if ok else '❌'} CSS: 横排 + 首行缩进")
    score += ok
    ok = zipfile.ZipFile(out_s).namelist()[0] == "mimetype"
    print(f"  {'✅' if ok else '❌'} EPUB 合规: mimetype 首个")
    score += ok
    ok = out_s.endswith(".simplified.epub")
    print(f"  {'✅' if ok else '❌'} 后缀(tw2sp): .simplified.epub")
    score += ok

    # 3b 简→繁 s2twp
    out_t = os.path.join(tmp, "out.traditional.epub")
    process_epub(epub_in, out_t, "s2twp", do_css=True)
    ct = zipfile.ZipFile(out_t).read("OEBPS/content.xhtml").decode("utf-8")
    ok = ("軟體" in ct) and ("软件" not in ct)
    print(f"  {'✅' if ok else '❌'} 简→繁(s2twp): 软件 → 軟體")
    score += ok
    ok = out_t.endswith(".traditional.epub")
    print(f"  {'✅' if ok else '❌'} 后缀(s2twp): .traditional.epub")
    score += ok

    shutil.rmtree(tmp)

print(f"\n{'=' * 60}")
print(f"端到端得分: {score} / 10")
print(f"文件清单: {'✅ 通过' if not missing else '❌ 有缺失'}")
print(f"静态核对: {static_ok}/{len(checks)}")
print("=" * 60)
sys.exit(0 if (not missing and static_ok == len(checks) and score == 10) else 1)
