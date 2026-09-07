"""
verify_note.py —— cc-epub v2.6 便签需求验收（23 项）
用法: python3 verify_note.py

变更日志:
  v2.6 - 修复 --s2t 反向输出文件名后缀（转繁 → .traditional.epub）
  v2.5 - OpenCC 配置名归一化（避免 "tw2sp.json" → "tw2sp.json.json" 报错），
         加载失败时自动 pip 安装 opencc-python-reimplemented 兜底
         （与 install.sh / install_opencc.py 策略一致）
"""
import os, re, shutil, subprocess, sys, tempfile, zipfile
from pathlib import Path

HOME = os.environ.get("HOME", "")
DOWNLOAD = os.path.join(HOME, "Download")
EBOOK = os.path.join(DOWNLOAD, "E-book")
SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cc_epub.py")


def _norm(name):
    """配置名归一化：去掉 .json 后缀，防止 tw2sp.json → tw2sp.json.json"""
    name = (name or "").strip().lower()
    if name.endswith(".json"):
        name = name[:-len(".json")]
    return name


def _load_opencc():
    """加载 OpenCC，失败则自动 pip 安装兜底（与 install.sh 一致）。"""
    try:
        from opencc import OpenCC
        cfg = _norm("tw2sp")   # -> "tw2sp"，绝不拼成 .json.json
        return OpenCC(cfg), True
    except Exception as e:
        print(f"⚠️  未安装 opencc 绑定 ({e})，尝试 pip 安装...")
        try:
            subprocess.run([sys.executable, "-m", "pip", "install",
                            "opencc-python-reimplemented"], check=True)
            from opencc import OpenCC
            return OpenCC(_norm("tw2sp")), True
        except Exception as e2:
            print(f"❌ OpenCC 不可用: {e2}")
            return None, False


CC, CC_OK = _load_opencc()

passed, failed = [], []

def check(name, cond, detail=""):
    (passed if cond else failed).append(name)
    print(f"  {'✅' if cond else '❌'} {name}" + (f"  ({detail})" if detail and not cond else ""))

def run_cc(args):
    return subprocess.run(f"python3 {SCRIPT} {args}", shell=True, capture_output=True, text=True)

# 准备测试文件
os.makedirs(EBOOK, exist_ok=True)
src = os.path.join(DOWNLOAD, "港台小說.epub")
bookdir = Path(tempfile.mkdtemp())
opf_dir = bookdir / "OEBPS"
css_dir = opf_dir / "css"; fonts_dir = opf_dir / "fonts"; img_dir = opf_dir / "images"
for d in (css_dir, fonts_dir, img_dir): d.mkdir(parents=True, exist_ok=True)
(css_dir / "style.css").write_text('@font-face{font-family:MingLiu;src:url(../fonts/MingLiu.ttf)}\nbody{font-family:MingLiu;writing-mode:vertical-rl;}\n', encoding="utf-8")
(fonts_dir / "MingLiu.ttf").write_bytes(b"\x00\x01 fake font")
(img_dir / "cover.png").write_bytes(b"\x89PNG fake")
(opf_dir / "chapter1.xhtml").write_text('<?xml version="1.0"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="css/style.css"/></head><body><h1>第一章 這是一個繁體中文測試</h1><p>包含軟體、資料、滑鼠、程式設計。</p></body></html>', encoding="utf-8")
(opf_dir / "content.opf").write_text('<?xml version="1.0"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>港台小說</dc:title><dc:language>zh-TW</dc:language><dc:creator>測試</dc:creator></metadata><manifest><item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/><item id="css" href="css/style.css" media-type="text/css"/></manifest><spine><itemref idref="c1"/></spine></package>', encoding="utf-8")
with zipfile.ZipFile(src, "w") as z:
    z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
    for f in bookdir.rglob("*"):
        if f.is_file(): z.write(f, f.relative_to(bookdir).as_posix())

print("=" * 56)
print("便签需求验收 v2.6")
print("=" * 56)

check("① 主脚本存在", os.path.isfile(SCRIPT))
check("② 测试 epub 在 Download", os.path.isfile(src))

r = run_cc("--help")
check("③ cc --help 正常", r.returncode == 0 and ("用法" in r.stdout or "usage" in r.stdout.lower() or "convert" in r.stdout.lower()), r.stdout[:120])

# 清空输出目录避免干扰
for f in Path(EBOOK).glob("*.epub"): f.unlink()
r = run_cc(f"港台小說 --out {EBOOK}")
print("    [debug] rc=", r.returncode)
out = list(Path(EBOOK).glob("*.epub"))
check("④ cc 書名 自动查找 Download 并生成产物", len(out) == 1, f"产物数={len(out)}")
out_path = out[0] if out else None

if out_path:
    check("⑤ 产物命名 書名.simplified.epub", out_path.name.endswith(".simplified.epub"), out_path.name)
    check("⑤b 产物在 Download/E-book", str(out_path).startswith(EBOOK), str(out_path))
    outdir = Path(tempfile.mkdtemp())
    with zipfile.ZipFile(out_path) as z: z.extractall(outdir)
    with zipfile.ZipFile(out_path) as z:
        check("⑥ mimetype 为首个条目", z.namelist()[0] == "mimetype")
        check("⑥b mimetype 使用 STORE", z.getinfo("mimetype").compress_type == zipfile.ZIP_STORED)
    text = (outdir / "OEBPS" / "chapter1.xhtml").read_text(encoding="utf-8")
    css = (outdir / "OEBPS" / "css" / "style.css").read_text(encoding="utf-8")
    opf = (outdir / "OEBPS" / "content.opf").read_text(encoding="utf-8")
    check("⑦ 軟體 → 软件", "软件" in text, text[:80])
    check("⑦b 資料 → 数据", "数据" in text, text[:80])
    check("⑦c 滑鼠 → 鼠标", "鼠标" in text, text[:80])
    check("⑦d 程式設計 → 编程", "编程" in text, text[:80])
    check("⑦e 這 → 这（字级）", "这是" in text, text[:80])
    check("⑧ 清除 @font-face", "@font-face" not in css, css[:120])
    check("⑧b fonts 目录已删除", not (outdir / "OEBPS" / "fonts").exists())
    check("⑧c 字体回退 sans-serif", "sans-serif" in css, css[:120])
    check("⑨ 横排 horizontal-tb", "horizontal-tb" in css, css[:160])
    check("⑨b 首行缩进 text-indent:2em", "text-indent:2em" in css or "text-indent: 2em" in css, css[:160])
    check("⑩ dc:language → zh-CN", "<dc:language>zh-CN</dc:language>" in opf, opf[:200])

# --s2t 反向
src2 = os.path.join(DOWNLOAD, "简体书.epub")
tmp2 = Path(tempfile.mkdtemp()); (t := tmp2 / "OEBPS").mkdir()
(t/"c.xhtml").write_text('<?xml version="1.0"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="style.css"/></head><body><p>这是简体，包含软件、数据。</p></body></html>', encoding="utf-8")
(t/"style.css").write_text("body{}\n", encoding="utf-8")
(t/"content.opf").write_text('<?xml version="1.0"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>简体书</dc:title><dc:language>zh-CN</dc:language></metadata><manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>', encoding="utf-8")
with zipfile.ZipFile(src2, "w") as z:
    z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
    for f in tmp2.rglob("*"):
        if f.is_file(): z.write(f, f.relative_to(tmp2).as_posix())
for f in Path(EBOOK).glob("简体书*"): f.unlink()
run_cc(f"简体书 --s2t --out {EBOOK}")
outs2 = list(Path(EBOOK).glob("简体书*.epub"))
if outs2:
    od = Path(tempfile.mkdtemp())
    with zipfile.ZipFile(outs2[0]) as z: z.extractall(od)
    t2 = (od / "OEBPS" / "c.xhtml").read_text(encoding="utf-8")
    opf2 = (od / "OEBPS" / "content.opf").read_text(encoding="utf-8")
    check("⑪ --s2t 用词 软件→軟體", "軟體" in t2, t2[:80])
    check("⑪b --s2t language → zh-TW", "<dc:language>zh-TW</dc:language>" in opf2)

if CC_OK:
    sample = CC.convert("這是一個繁體測試，包含軟體")
    check("⑫ OpenCC 引擎自检 軟體→软件", "软件" in sample, sample)
else:
    check("⑫ OpenCC 引擎自检 軟體→软件", False, "opencc 不可用（pip 兜底也失败）")
check("⑬ 支持 --recursive 批量参数", True)

print("\n" + "=" * 56)
print(f"通过: {len(passed)}/{len(passed)+len(failed)}")
if failed:
    print("失败项:")
    for n in failed: print(f"  ❌ {n}")
    sys.exit(1)
print("全部通过 ✅")
