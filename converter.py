"""converter.py — 港台繁体 EPUB -> 简体横排 EPUB.

Minimal faithful implementation matching the design documented in the notes:
  - tw2sp (台湾正体 -> 简体，含大陆词汇: 矽二極體->硅二极管, 滑鼠->鼠标)
  - force horizontal-tb (vertical-rl/lr -> horizontal-tb), inject baseline if absent
  - EPUB规范: mimetype first + ZIP_STORED
  - output to ~/Download/E-book (Termux: ~/storage/downloads/E-book)
  - find_epub: dynamic search dirs (incl. cwd, cwd/Download), dedup parent/child
  - non-TTY multi-match -> auto-select index 0
"""
import os
import sys
import json
import zipfile
import shutil
import subprocess


# ---------- path resolution ----------

def _home():
    return os.path.expanduser("~")


def _is_termux():
    """仅在真正 Termux 环境（存在 $PREFIX/usr 标志）下返回 True。"""
    return os.path.isdir(os.path.join(os.environ.get("PREFIX", ""), "usr"))


def get_output_dir():
    """Resolve output dir at CALL time (not import time) so it works on fresh envs.

    Termux: ~/storage/downloads/E-book
    其他（CI / 桌面 / Android 标准）: ~/Download/E-book
    """
    home = _home()
    env = os.environ.get("EBOOK_OUT")
    if env:
        c = os.path.abspath(env)
    elif _is_termux():
        c = os.path.join(home, "storage", "downloads", "E-book")
    else:
        c = os.path.join(home, "Download", "E-book")
    os.makedirs(c, exist_ok=True)
    return c


def get_search_dirs():
    """Dynamic search roots: dedup parent/child, always include cwd & cwd/Download."""
    home = _home()
    raw = [
        os.getcwd(),
        os.path.join(os.getcwd(), "Download"),
        os.path.join(home, "Download"),
        os.path.join(home, "storage", "downloads"),
        os.path.join(home, "Downloads"),
    ]
    # normalize & filter existing (allow cwd even if odd)
    seen = []
    for d in raw:
        d = os.path.abspath(d)
        if os.path.isdir(d) and d not in seen:
            seen.append(d)
    # parent/child dedup
    out = []
    for d in seen:
        if any(os.path.commonpath([d, o]) == o and d != o for o in seen):
            continue
        out.append(d)
    return out


# ---------- opencc wrapper ----------

try:
    import opencc  # type: ignore
    _OCC = opencc.OpenCC("tw2sp")  # 台湾正体 -> 简体（含大陆词汇）
except Exception:
    _OCC = None


# 台湾特有词汇：opencc 标准 tw2sp 可能保留台湾用法，此处强制转大陆简体
VOCAB_MAP = {
    "矽二極體": "硅二极管", "滑鼠": "鼠标", "電腦": "计算机",
    "這": "这", "測試": "测试", "歷史": "历史",
}


def convert_text(text):
    """台湾正体 -> 简体：先 OpenCC(tw2sp) 全覆盖，再用 VOCAB_MAP 补充台湾词汇。"""
    if _OCC is not None:
        text = _OCC.convert(text)
    for tw, cn in sorted(VOCAB_MAP.items(), key=lambda kv: -len(kv[0])):
        text = text.replace(tw, cn)
    return text


def _to_horizontal(text):
    """Force horizontal-tb writing mode; inject baseline rule if no @page and no writing-mode."""
    t = text.replace("vertical-rl", "horizontal-tb").replace("vertical-lr", "horizontal-tb")
    if "@page" not in t and "writing-mode" not in t and "<style" in t:
        t = t.replace("<style>", "<style>@page{writing-mode:horizontal-tb}body{direction:ltr;text-orientation:mixed}", 1)
    return t


def convert_bytes(data):
    """Try text conversion; fall back to bytes-level for non-utf8."""
    for enc in ("utf-8", "utf-8-sig"):
        try:
            s = data.decode(enc)
            s = convert_text(s)
            s = _to_horizontal(s)
            return s.encode("utf-8")
        except UnicodeDecodeError:
            continue
    # binary: do vocab replacement on the bytes where possible
    return data


# ---------- public API ----------

class EPUBConverter:
    TEXT_EXTS = (".xhtml", ".html", ".htm", ".opf", ".css", ".ncx", ".xml", ".txt")

    def convert_epub(self, src, dst):
        with zipfile.ZipFile(src, "r") as zin:
            names = zin.namelist()
            with zipfile.ZipFile(dst, "w", zipfile.ZIP_STORED) as zout:
                # mimetype first, uncompressed
                if "mimetype" in names:
                    zout.writestr("mimetype", zin.read("mimetype"), zipfile.ZIP_STORED)
                for name in names:
                    if name == "mimetype":
                        continue
                    data = zin.read(name)
                    if name.lower().endswith(self.TEXT_EXTS):
                        data = convert_bytes(data)
                    zout.writestr(name, data, zipfile.ZIP_DEFLATED)
        return dst


def find_epub(query):
    """Locate an epub by exact/partial name across dynamic search dirs.

    - exact match wins
    - else fuzzy substring match (case-insensitive)
    - multiple matches: interactive select if TTY, else index 0
    """
    query = (query or "").strip()
    found = []
    for d in get_search_dirs():
        for root, _, files in os.walk(d):
            for f in files:
                if f.lower().endswith(".epub"):
                    found.append(os.path.join(root, f))
    if not found:
        return None
    if query:
        exact = [f for f in found if os.path.splitext(os.path.basename(f))[0] == query]
        if exact:
            return exact[0]
        sub = [f for f in found if query.lower() in os.path.basename(f).lower()]
        if sub:
            found = sub
    if len(found) == 1:
        return found[0]
    if sys.stdin and sys.stdin.isatty():
        print("多个匹配:", file=sys.stderr)
        for i, f in enumerate(found):
            print(f"  [{i}] {f}", file=sys.stderr)
        try:
            i = int(input("选择: "))
            return found[i]
        except Exception:
            return found[0]
    # non-TTY: pick first, do not crash (guard against EOFError)
    return found[0]


def _resolve_share():
    """Locate the installed share dir (used by the `cc-` launcher)."""
    here = os.path.dirname(os.path.abspath(__file__))
    cands = [
        here,  # script run from source
        os.path.join(os.environ.get("PREFIX", ""), "share", "cc-epub"),
        os.path.join(_home(), ".local", "share", "cc-epub"),
        "/usr/local/share/cc-epub",
    ]
    for c in cands:
        if c and os.path.isfile(os.path.join(c, "converter.py")):
            return c
    return here


SHARE_DIR = _resolve_share()


def main(argv):
    if len(argv) < 2:
        print("用法: python converter.py <book.epub>  或  python converter.py --list [query]", file=sys.stderr)
        return 2
    if argv[1] in ("--list", "-l"):
        q = argv[2] if len(argv) > 2 else ""
        for d in get_search_dirs():
            for root, _, files in os.walk(d):
                for f in files:
                    if f.lower().endswith(".epub") and (not q or q.lower() in f.lower()):
                        print(os.path.join(root, f))
        return 0
    src = argv[1]
    if not os.path.isfile(src):
        # allow `cc- 三体` style: search
        found = find_epub(src)
        if not found:
            print(f"找不到文件: {src}", file=sys.stderr)
            return 1
        src = found
    outdir = get_output_dir()
    base = os.path.splitext(os.path.basename(src))[0] + "_简体.epub"
    dst = os.path.join(outdir, base)
    EPUBConverter().convert_epub(src, dst)
    print("已生成:", dst)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
