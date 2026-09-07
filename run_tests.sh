#!/usr/bin/env bash
# run_tests.sh —— cc-epub v2.6 端到端测试
# 每个阶段独立报告，最终汇总（不再因 set -e 中途退出而难以定位）。
set +e
cd "$(dirname "$0")"
export HOME="/root"
export TMP="$(mktemp -d)"
mkdir -p "$HOME/Download/E-book"
rm -rf "$HOME/Download/E-book"/* /tmp/_cc_check /tmp/_cc_s2t /tmp/_cc_s2t_check
: "${PYTHON_BIN:=python3}"
PASS=0; FAIL=0
ok()   { echo -e "  \033[0;32m✅ $*\033[0m"; PASS=$((PASS+1)); }
bad()  { echo -e "  \033[0;31m❌ $*\033[0m"; FAIL=$((FAIL+1)); }

# ---------- 准备测试源 ----------
$PYTHON_BIN - <<'PY'
import os, zipfile
from pathlib import Path
tmp = Path(os.environ["TMP"]) / "book"
oebps = tmp / "OEBPS"
css = oebps / "css"; fonts = oebps / "fonts"; img = oebps / "images"
for d in (css, fonts, img): d.mkdir(parents=True, exist_ok=True)
(css/"style.css").write_text(
    '@font-face{font-family:MingLiu;src:url(../fonts/MingLiu.ttf)}\n'
    'body{font-family:MingLiu;writing-mode:vertical-rl;}\n', encoding="utf-8")
(fonts/"MingLiu.ttf").write_bytes(b"\x00\x01 fake")
(img/"cover.png").write_bytes(b"\x89PNG")
(oebps/"chapter1.xhtml").write_text(
    '<?xml version="1.0"?>\n'
    '<html xmlns="http://www.w3.org/1999/xhtml">'
    '<head><link rel="stylesheet" href="css/style.css"/></head>'
    '<body><h1>第一章 這是一個繁體中文測試</h1>'
    '<p>包含軟體、資料、滑鼠、程式設計。</p></body></html>', encoding="utf-8")
(oebps/"content.opf").write_text(
    '<?xml version="1.0"?>\n'
    '<package xmlns="http://www.idpf.org/2007/opf" version="2.0">'
    '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>港台小說</dc:title><dc:language>zh-TW</dc:language>'
    '</metadata><manifest>'
    '<item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="css" href="css/style.css" media-type="text/css"/>'
    '</manifest><spine><itemref idref="c1"/></spine></package>', encoding="utf-8")
src = os.path.join(os.environ["HOME"], "Download", "港台小說.epub")
with zipfile.ZipFile(src, "w") as z:
    z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
    for f in sorted(tmp.rglob("*")):
        if f.is_file(): z.write(f, f.relative_to(tmp).as_posix())
print("测试源已生成:", src)
PY

echo ""
echo "=== [A] 核心命令: cc 書名 ==="
$PYTHON_BIN cc_epub.py 港台小說 --out "$HOME/Download/E-book"
ls -la "$HOME/Download/E-book/"

echo ""
echo "=== [B] 校验产物合规性 ===="
$PYTHON_BIN - <<'PY'
import os, zipfile, sys
from pathlib import Path
out = next(Path(os.environ["HOME"]).joinpath("Download","E-book").glob("*.epub"))
print("产物:", out.name)
assert out.name.endswith(".simplified.epub"), "命名错误"
with zipfile.ZipFile(out) as z:
    assert z.namelist()[0] == "mimetype", "mimetype 非首个"
    assert z.getinfo("mimetype").compress_type == zipfile.ZIP_STORED, "mimetype 未 STORE"
    z.extractall("/tmp/_cc_check")
base = Path("/tmp/_cc_check")
css = (base/"OEBPS"/"css"/"style.css")
assert css.exists(), f"style.css 不存在，实际结构: {[str(p.relative_to(base)) for p in base.rglob('*') if p.is_file()]}"
css_text = css.read_text(encoding="utf-8")
text = (base/"OEBPS"/"chapter1.xhtml").read_text(encoding="utf-8")
opf = (base/"OEBPS"/"content.opf").read_text(encoding="utf-8")
assert "@font-face" not in css_text, "font-face 未清"
assert not (base/"OEBPS"/"fonts").exists(), "fonts 未删"
assert "horizontal-tb" in css_text, "缺 horizontal-tb"
assert ("text-indent:2em" in css_text or "text-indent: 2em" in css_text), "缺 text-indent"
assert "软件" in text and "数据" in text and "鼠标" in text, f"用词失败: {text}"
assert "编程" in text, f"程式設計→编程 失败: {text}"
assert "<dc:language>zh-CN</dc:language>" in opf, "language 未更新"
print("✅ [B] 结构 / 防白页 / 横排缩进 / 用词 / 元数据 均正确")
PY
[ $? -eq 0 ] && ok "[B] 产物合规" || bad "[B] 产物合规"

echo ""
echo "=== [C] 反向 --s2t 用词 ===="
$PYTHON_BIN - <<'PY'
import os, zipfile
from pathlib import Path
tmp = Path("/tmp/_cc_s2t"); 
if tmp.exists(): 
    import shutil; shutil.rmtree(tmp)
tmp.mkdir()
b = tmp/"OEBPS"; b.mkdir()
(b/"c.xhtml").write_text('<?xml version="1.0"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><link rel="stylesheet" href="style.css"/></head><body><p>这是简体，包含软件、数据。</p></body></html>', encoding="utf-8")
(b/"style.css").write_text("body{}\n", encoding="utf-8")
(b/"content.opf").write_text('<?xml version="1.0"?>\n<package xmlns="http://www.idpf.org/2007/opf" version="2.0"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>简体书</dc:title><dc:language>zh-CN</dc:language></metadata><manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>', encoding="utf-8")
src = os.path.join(os.environ["HOME"],"Download","简体书.epub")
with zipfile.ZipFile(src,"w") as z:
    z.writestr("mimetype", b"application/epub+zip", zipfile.ZIP_STORED)
    for f in sorted(tmp.rglob("*")):
        if f.is_file(): z.write(f, f.relative_to(tmp).as_posix())
print("简体源已生成")
PY
$PYTHON_BIN cc_epub.py 简体书 --s2t --out "$HOME/Download/E-book"
$PYTHON_BIN - <<'PY'
import os, zipfile
from pathlib import Path
out = next((Path(os.environ["HOME"])/"Download"/"E-book").glob("简体书*.epub"))
with zipfile.ZipFile(out) as z: z.extractall("/tmp/_cc_s2t_check")
t = (Path("/tmp/_cc_s2t_check")/"OEBPS"/"c.xhtml").read_text(encoding="utf-8")
opf = (Path("/tmp/_cc_s2t_check")/"OEBPS"/"content.opf").read_text(encoding="utf-8")
assert "軟體" in t, f"--s2t 用词失败: {t}"
assert "<dc:language>zh-TW</dc:language>" in opf, f"language 未回 zh-TW: {opf}"
print("✅ [C] --s2t 用词 软件→軟體 + language→zh-TW 正确")
PY
[ $? -eq 0 ] && ok "[C] --s2t 反向" || bad "[C] --s2t 反向"

echo ""
echo "=== [D] install_opencc.py 降级方案自检 ==="
$PYTHON_BIN -c "from opencc import OpenCC; print('✅ [D] Python 绑定可用:', OpenCC('tw2sp').convert('包含軟體'))"
[ $? -eq 0 ] && ok "[D] OpenCC 绑定" || bad "[D] OpenCC 绑定"

echo ""
echo "=========================================="
echo -e " 汇总: ✅ $PASS 通过 / ❌ $FAIL 失败"
echo "=========================================="
exit $FAIL
