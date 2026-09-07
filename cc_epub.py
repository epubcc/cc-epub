#!/usr/bin/env python3
"""
cc_epub.py —— EPUB 中文简繁转换 (cc-epub v2.6)
用法:
    cc 書名                    # 自动在 ~/Download 查找 書名*.epub, 繁(tw2sp)->简
    cc /path/to/book.epub      # 指定文件
    cc 書名 --s2t               # 简->繁 (含用词 s2twp)
    cc 書名 --direction s2hk    # 指定 opencc 配置
    cc ~/books/ -r              # 批量递归
    cc 書名 --out DIR           # 输出目录
    cc 書名 --backup            # 转换前备份原文件
    cc 書名 --no-css            # 跳过 CSS 注入
    cc 書名 -v / -q             # 日志级别
"""
import argparse, os, re, shutil, sys, zipfile
from pathlib import Path

__version__ = "2.6"

HOME = os.environ.get("HOME", "")
DOWNLOAD = os.environ.get("DOWNLOAD", os.path.join(HOME, "Download"))
DEFAULT_OUT = os.environ.get("CC_EPUB_OUT", os.path.join(DOWNLOAD, "E-book"))

TEXT_EXTS = {".xhtml", ".html", ".htm", ".xml", ".opf", ".ncx", ".txt", ".css"}

CONFIGS = {
    "tw2sp": ("t2s", "zh-CN"),
    "t2s":   ("t2s", "zh-CN"),
    "s2t":   ("s2t", "zh-TW"),
    "s2tw":  ("s2t", "zh-TW"),
    "s2twp": ("s2t", "zh-TW"),
    "s2hk":  ("s2t", "zh-TW"),
    "t2tw":  ("s2t", "zh-TW"),
    "t2hk":  ("s2t", "zh-TW"),
}

VERBOSE = 1
def log(msg, level=1):
    if level <= VERBOSE:
        print(msg, flush=True)

_CONVERTER = None
def _normalize_config(config):
    """归一化 OpenCC 配置名：允许 'tw2sp' 或 'tw2sp.json'，统一去后缀。"""
    name = (config or "").strip().lower()
    if name.endswith(".json"):
        name = name[:-len(".json")]
    return name


def get_converter(config):
    global _CONVERTER
    try:
        from opencc import OpenCC
    except ImportError:
        sys.exit("❌ 未安装 opencc-python-reimplemented，请运行 install.sh 或 pip install opencc-python-reimplemented")
    name = _normalize_config(config)
    if _CONVERTER is None or _CONVERTER[0] != name:
        try:
            _CONVERTER = (name, OpenCC(name))
        except Exception as e:
            sys.exit(f"❌ 无法加载 OpenCC 配置 '{name}'：{e}\n    请确认 opencc-python-reimplemented 已正确安装")
    return _CONVERTER[1]


def read_epub(path):
    files, order = {}, []
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        if "mimetype" in names:
            order.append("mimetype")
            files["mimetype"] = z.read("mimetype")
        for n in names:
            if n == "mimetype" or n.endswith("/") or n == "":
                continue
            order.append(n)
            files[n] = z.read(n)
    return files, order


def write_epub(path, files, order):
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        if "mimetype" in files:
            z.writestr(zipfile.ZipInfo("mimetype"), files["mimetype"], zipfile.ZIP_STORED)
        for n in order:
            if n == "mimetype" or n not in files:
                continue
            z.writestr(n, files[n])


def is_text(name):
    return Path(name).suffix.lower() in TEXT_EXTS


HORIZONTAL_CSS = (
    "\n/* cc-epub: 横排 + 首行缩进 (防白页) */\n"
    "body, * { writing-mode: horizontal-tb !important; "
    "text-indent: 2em !important; font-family: sans-serif !important; }\n"
)

def inject_css(css_text):
    css = re.sub(r"@font-face\s*\{[^}]*\}", "", css_text, flags=re.S)
    css = re.sub(r"font-family\s*:\s*['\"]?[\w\- ]+['\"]?;",
                 "font-family: sans-serif;", css)
    if "horizontal-tb" not in css:
        css += HORIZONTAL_CSS
    return css


def process_css_files(files, convert):
    css_names = [n for n in files if n.lower().endswith("style.css")]
    if not css_names:
        css_names = [n for n in files if n.lower().endswith(".css")]
    for name in css_names:
        orig = files[name].decode("utf-8", "ignore")
        files[name] = inject_css(orig).encode("utf-8")


def remove_fonts(files):
    for n in [n for n in files if re.match(r".*/fonts?/.*", n, re.I) and not n.endswith("/")]:
        del files[n]


def update_language(opf_text, lang):
    if "<dc:language>" in opf_text:
        return re.sub(r"<dc:language>[^<]+</dc:language>",
                      f"<dc:language>{lang}</dc:language>", opf_text, count=1)
    return opf_text


def convert_tree(files, config):
    _, target_lang = CONFIGS.get(config, ("t2s", "zh-CN"))
    convert = get_converter(config).convert
    new = {}
    for name, data in files.items():
        if is_text(name):
            try:
                text = data.decode("utf-8")
            except UnicodeDecodeError:
                new[name] = data
                continue
            if name.lower().endswith(".opf"):
                text = update_language(text, target_lang)
            text = convert(text)
            new[name] = text.encode("utf-8")
        else:
            new[name] = data
    return new


def process_epub(src, dst, config, do_css=True):
    files, order = read_epub(src)
    if do_css:
        remove_fonts(files)
    files = convert_tree(files, config)
    if do_css:
        process_css_files(files, get_converter(config).convert)
    write_epub(dst, files, order)


def find_source(name_or_path):
    p = Path(name_or_path).expanduser()
    if p.is_file():
        return str(p)
    if p.is_dir():
        return None
    cand = Path(DOWNLOAD)
    if not cand.is_dir():
        return None
    exact = cand / f"{name_or_path}.epub"
    if exact.is_file():
        return str(exact)
    matches = sorted([f for f in cand.glob(f"{name_or_path}*.epub")
                      if not f.name.endswith(".bak.epub")])
    return str(matches[0]) if matches else None


def output_path(src_path, out_dir, direction):
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    stem = Path(src_path).stem
    # 依据目标语言决定后缀：转繁(s2t/s2tw/s2twp/s2hk 等)→.traditional.epub，转简→.simplified.epub
    target_lang = CONFIGS.get(direction, ("t2s", "zh-CN"))[1]
    suffix = ".traditional.epub" if target_lang == "zh-TW" else ".simplified.epub"
    return str(Path(out_dir) / f"{stem}{suffix}")


def process_one(src, out_dir, config, backup=False, do_css=True):
    src = os.path.abspath(src)
    if not os.path.isfile(src):
        raise FileNotFoundError(f"找不到输入文件: {src}")
    if backup:
        bak = src + ".bak.epub"
        if not os.path.exists(bak):
            shutil.copy2(src, bak)
            log(f"  [备份] {bak}", 1)
    dst = output_path(src, out_dir, config)
    log(f"  转换: {src}", 1)
    log(f"  输出: {dst}", 1)
    process_epub(src, dst, config, do_css=do_css)
    return dst


def collect_epubs(folder):
    return sorted([str(f) for f in Path(folder).rglob("*.epub")
                   if not f.name.endswith(".bak.epub")])


def main(argv=None):
    global VERBOSE
    p = argparse.ArgumentParser(prog="cc", description="EPUB 中文简繁转换 (港台繁体->简体)")
    p.add_argument("source", nargs="?", help="书名(自动在 Download 查找) 或 文件路径 或 文件夹(-r)")
    p.add_argument("--direction", default="tw2sp", choices=list(CONFIGS.keys()),
                   help="OpenCC 配置 (默认 tw2sp: 港台繁体->简体)")
    p.add_argument("--s2t", action="store_true", help="简->繁 (等同 --direction s2twp)")
    p.add_argument("--out", default=DEFAULT_OUT, help=f"输出目录 (默认 {DEFAULT_OUT})")
    p.add_argument("-r", "--recursive", action="store_true", help="批量处理文件夹")
    p.add_argument("--backup", action="store_true", help="转换前备份原文件(.bak.epub)")
    p.add_argument("--no-css", action="store_true", help="跳过 CSS 注入/防白页")
    p.add_argument("-v", "--verbose", action="count", default=1)
    p.add_argument("-q", "--quiet", action="store_true")
    p.add_argument("--version", action="version", version=f"cc-epub {__version__}")
    args = p.parse_args(argv)

    VERBOSE = 0 if args.quiet else args.verbose

    if not args.source:
        p.error("请提供 书名 / 文件路径 / 文件夹(需 -r)")

    config = "s2twp" if args.s2t else args.direction
    do_css = not args.no_css

    if args.recursive or os.path.isdir(args.source):
        folder = args.source if os.path.isdir(args.source) else DOWNLOAD
        files = collect_epubs(folder)
        if not files:
            sys.exit(f"❌ 在 {folder} 未找到 .epub 文件")
        log(f"批量处理 {len(files)} 个文件:", 1)
        for f in files:
            try:
                d = process_one(f, args.out, config, backup=args.backup, do_css=do_css)
                log(f"  ✅ {d}", 1)
            except Exception as e:
                log(f"  ❌ {f}: {e}", 0)
        return 0

    src = find_source(args.source)
    if not src:
        sys.exit(f"❌ 找不到输入: {args.source}\n"
                 f"   请在 {DOWNLOAD} 放置 .epub，或使用完整路径")
    dst = process_one(src, args.out, config, backup=args.backup, do_css=do_css)
    print(f"✅ 完成: {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
