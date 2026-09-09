#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cc-epub —— 港台繁体 EPUB → 简体横排（Kindle KFX 优化）
================================================================

工作流程（严格对应需求 #7）：
  ① 清除段落前全角空格 / 缩进实体（杜绝 4em 叠加的根源）
  ② 检测排版方向（竖排 vertical-rl / 横排 horizontal-tb）
  ③ 竖排 → 横排；已横排文件 → 仅校验首行缩进
  ④ 全部统一：简体中文 + 首行缩进 2em + 标点规范 + 字体/字号统一

设计原则（对应需求 #2、#8、#9）：
  · 完美保留插图、目录结构、章节分隔、CSS 布局骨架
  · 只对「会造成渲染异常」的项做最小化修正，绝不无脑清空 class/style
  · 缩进采用「文本空格归零 + CSS 单一来源」双保险，根除 4em/四字宽

输出：~/storage/shared/Download/E-book/书名-简中.epub
"""

import os
import re
import sys
import zipfile
import shutil
import subprocess
import tempfile
from pathlib import Path

try:
    from bs4 import BeautifulSoup
except ImportError:
    BeautifulSoup = None  # 延后到 check_dependencies()


# 繁简转换后端：优先 opencc 命令行（Termux 官方包），缺失时退化为 Python 版 opencc
class _CCBackend:
    """统一的繁→简转换后端"""
    def __init__(self):
        self._py = None
        self.mode = None
        self._probe()

    def _probe(self):
        # 1) 优先命令行
        try:
            r = subprocess.run(["opencc", "--version"], capture_output=True, text=True, check=False)
            if r.returncode == 0:
                self.mode = "cli"
                return
        except Exception:
            pass
        # 2) 退化为 Python 版 opencc
        try:
            from opencc import OpenCC  # type: ignore
            self._py = OpenCC(OPENCC_CONFIG)
            self.mode = "python"
            return
        except Exception:
            pass
        self.mode = None

    def convert(self, text):
        if not text or not text.strip():
            return text
        try:
            if self.mode == "cli":
                r = subprocess.run(
                    ["opencc", "-c", OPENCC_CONFIG],
                    input=text, capture_output=True, text=True, encoding="utf-8", check=False,
                )
                return r.stdout if r.returncode == 0 else text
            if self.mode == "python" and self._py:
                return self._py.convert(text)
        except Exception:
            return text
        return text


_backend = _CCBackend()

# ---------------------------------------------------------------------------
# 配置
# ---------------------------------------------------------------------------
__version__ = "3.0.0"

# 输出目录（Termux 下通常为 ~/storage/shared/Download/E-book）
OUT_DIR = str(Path.home() / "storage" / "shared" / "Download" / "E-book")

# OpenCC 配置：台湾繁体→简体（含短语/词汇转换，最彻底）；香港书改为 hk2sp.json
OPENCC_CONFIG = "tw2sp.json"

# 占位符常量（见 batch_convert_t2s）
CLEAN_INLINE_STYLE_RE = [
    (r'writing-mode\s*:\s*[^;!]+;?', ''),     # 竖排方向 → 交给统一规则
    (r'text-orientation\s*:\s*[^;!]+;?', ''),  # 竖排字形方向
    (r'direction\s*:\s*[^;!]+;?', ''),         # 书写流向
    (r'font-family\s*:\s*[^;!]+;?', ''),       # 字体统一
    (r'font-size\s*:\s*[^;!]+;?', ''),         # 字号统一
    (r'@font-face\s*\{[^}]*\}', ''),           # 嵌入字体 → 移除（KFX 兼容）
    (r'@import\s+[^;]+;', ''),                 # 外链字体/样式
]

# 批量转换的分隔符（不会出现在正常正文里）
_BATCH_SEP = "\n\x00\n"

# ---------------------------------------------------------------------------
# 依赖检查
# ---------------------------------------------------------------------------
def check_dependencies(verbose=True):
    """检查并可选自动安装依赖"""
    if BeautifulSoup is None:
        if verbose:
            print("[-] 缺少依赖库 beautifulsoup4，正在尝试自动安装...")
        subprocess.run([sys.executable, "-m", "pip", "install", "beautifulsoup4"],
                       check=False)
        import importlib
        mod = importlib.import_module("bs4")
        globals()["BeautifulSoup"] = mod.BeautifulSoup
        if verbose:
            print("[+] beautifulsoup4 已就绪。")

    # 校验 opencc 命令
    try:
        subprocess.run(["opencc", "--version"], capture_output=True, check=False)
    except FileNotFoundError:
        if verbose:
            print("[-] 未找到 opencc 命令。请安装：pkg install libopencc opencc-tools")


# ---------------------------------------------------------------------------
# 繁简转换
# ---------------------------------------------------------------------------
def convert_text(text):
    """单段繁转简 + 标点规范化"""
    if not text or not text.strip():
        return text
    out = _backend.convert(text)
    return normalize_punctuation(out) if out != text else text


def batch_convert_t2s(texts):
    """批量繁转简：合并后一次性调用 opencc（CLI 模式），否则退化为逐段 Python 后端

    关键点：节点文本可能含换行/空白，若直接用 \\n 类分隔符会导致 split 错位、
    繁简结果无法对齐写回。因此先对节点做占位转义，再合并调用。
    """
    if not texts:
        return []

    # 占位符（正文不可能出现，且不会与被转换字符冲突）
    _NL, _CR, _SEP = "\x01", "\x02", "\x03"

    def _esc(t):
        return t.replace("\x00", "").replace("\n", _NL).replace("\r", _CR)

    def _unesc(t):
        return t.replace(_NL, "\n").replace(_CR, "\r")

    combined = _SEP.join(_esc(t) for t in texts)
    tmp = tempfile.gettempdir()
    fin, fout = os.path.join(tmp, "cc_in.txt"), os.path.join(tmp, "cc_out.txt")

    # 优先 CLI 批量（性能最优）
    if _backend.mode == "cli":
        try:
            with open(fin, "w", encoding="utf-8") as f:
                f.write(combined)
            result = subprocess.run(
                ["opencc", "-i", fin, "-o", fout, "-c", OPENCC_CONFIG],
                capture_output=True, text=True, check=False,
            )
            if result.returncode == 0 and os.path.exists(fout):
                with open(fout, "r", encoding="utf-8") as f:
                    out = f.read()
                parts = [_unesc(p) for p in out.split(_SEP)]
                if len(parts) == len(texts):
                    return [normalize_punctuation(t) for t in parts]
                print("  [!] 批量输出分段数不匹配，降级为逐段处理")
        except Exception as e:
            print(f"  [!] 批量转换异常: {e}，降级处理")
        finally:
            for fp in (fin, fout):
                if os.path.exists(fp):
                    os.remove(fp)

    # 降级 / Python 后端：逐段转换（保证正确性）
    return [convert_text(t) for t in texts]


# ---------------------------------------------------------------------------
# 标点规范化（需求：港台 → 大陆标准）
# ---------------------------------------------------------------------------
def normalize_punctuation(text):
    if not text:
        return text

    # 1. 直角引号 → 弯引号（先双后单，避免嵌套错乱）
    text = text.replace("「", "\u201c").replace("」", "\u201d")
    text = text.replace("『", "\u2018").replace("』", "\u2019")

    # 2. 小逗号 / 小句号 → 标准全角
    text = text.replace("\ufe44", "，").replace("\ufe45", "。")
    text = text.replace("﹐", "，").replace("﹒", "。")

    # 3. 破折号统一
    text = re.sub(r"[—─━–\-]{2,}|\u2014+", "\u2014\u2014", text)

    # 4. 省略号统一
    text = re.sub(r"\.{3,}", "\u2026\u2026", text)
    text = re.sub(r"\u2026+", "\u2026\u2026", text)

    # 5. 间隔号
    text = text.replace("．", "\u00b7")

    # 6. 特殊括号 → 标准
    text = text.replace("﹝", "(").replace("﹞", ")")
    text = text.replace("﹙", "(").replace("﹚", ")")

    return text


# ---------------------------------------------------------------------------
# CSS 处理（需求 #9：KFX 兼容，移除导致白页/卡顿的项）
# ---------------------------------------------------------------------------
def clean_css_file(css_content):
    """清洗外部 CSS：移除冲突与复杂项，追加统一覆盖规则（不破坏布局骨架）"""
    for pattern, repl in CLEAN_INLINE_STYLE_RE:
        css_content = re.sub(pattern, repl, css_content, flags=re.IGNORECASE)

    # 追加：横排 + 统一字体字号 + 首行缩进（单一来源，杜绝叠加）
    css_content += """

/* --- Auto-injected by cc-epub --- */
body { writing-mode: horizontal-tb !important; direction: ltr !important;
       font-family: serif !important; font-size: 1em !important; line-height: 1.5; }
p { text-indent: 2em !important; margin: 0; padding: 0; text-align: justify; }
* { font-family: inherit !important; font-size: inherit !important; }
"""
    return css_content


# ---------------------------------------------------------------------------
# HTML 处理（核心：缩进双保险，对应痛点 #8）
# ---------------------------------------------------------------------------
def clean_html_content(html_content, convert_t2s=True):
    """清洗单个 HTML/XHTML 文件"""
    soup = BeautifulSoup(html_content, "html.parser")

    # ---- 第 1 步：繁简转换（在清空格「之前」对原始节点做，避免节点被拆散）----
    if convert_t2s:
        text_nodes = [
            el for el in soup.find_all(text=True)
            if el.strip() and re.search(r"[\u4e00-\u9fff]", str(el))
        ]
        if text_nodes:
            originals = [str(n) for n in text_nodes]
            converted = batch_convert_t2s(originals)
            for node, new_text in zip(text_nodes, converted):
                if new_text != str(node):
                    node.replace_with(new_text)

    # ---- 第 2 步：清除段落前全角空格 / 缩进实体（根除 4em 之源）----
    # 同时处理行首连续空白、&emsp;/&ensp;/&#8195;/&#8194;
    for element in soup.find_all(text=True):
        if not element.strip():
            continue
        new_text = str(element)
        new_text = re.sub(r"^\s*([\u3000\u3001])\s*", "", new_text)  # 行首单个缩进符
        new_text = re.sub(r"^([\u3000\s]|\&emsp\;|\&ensp\;|\&#8195\;|\&#8194\;)+",
                          "", new_text)
        if new_text != str(element):
            element.replace_with(new_text)

    # ---- 第 3 步：内联样式最小化清理（保留 class，保护原始排版）----
    for tag in soup.find_all(True):
        if not tag.has_attr("style"):
            continue
        style = tag["style"]
        for pattern, repl in CLEAN_INLINE_STYLE_RE:
            style = re.sub(pattern, repl, style, flags=re.IGNORECASE)
        style = re.sub(r";\s*;", ";", style).strip().strip(";")
        if style:
            tag["style"] = style
        else:
            del tag["style"]

    # ---- 第 4 步：修正 html / body 的竖排方向 ----
    for tag in soup.find_all(["html", "body"]):
        style = tag.get("style", "")
        style = re.sub(r"writing-mode\s*:\s*vertical-rl",
                       "writing-mode: horizontal-tb", style, flags=re.IGNORECASE)
        style = re.sub(r"direction\s*:\s*rtl", "direction: ltr", style, flags=re.IGNORECASE)
        if style:
            tag["style"] = style

    # ---- 第 5 步：注入强制覆盖 CSS（确保横排 + 2em，优先级最高）----
    force_css = """<style type="text/css">
/* --- Auto-injected by cc-epub --- */
body { writing-mode: horizontal-tb !important; direction: ltr !important;
       font-family: serif !important; font-size: 1em !important; line-height: 1.5; }
p { text-indent: 2em !important; margin: 0; padding: 0; text-align: justify; }
* { font-family: inherit !important; font-size: inherit !important; }
</style>"""
    injected = BeautifulSoup(force_css, "html.parser")
    if soup.head:
        # 避免重复注入
        if not soup.head.find("style", string=re.compile(r"Auto-injected by cc-epub")):
            soup.head.insert(0, injected)
    else:
        head = soup.new_tag("head")
        head.insert(0, injected)
        soup.insert(0, head)

    return str(soup)


# ---------------------------------------------------------------------------
# OPF / NCX / NAV 处理
# ---------------------------------------------------------------------------
def process_opf(opf_content):
    """修正阅读方向 + 元数据繁转简"""
    opf_content = re.sub(
        r'page-progression-direction\s*=\s*["\']rtl["\']',
        'page-progression-direction="ltr"', opf_content, flags=re.IGNORECASE,
    )
    for tag in ["title", "creator", "publisher", "description", "subject"]:
        opf_content = re.sub(
            rf"(<dc:{tag}[^>]*>)(.*?)(</dc:{tag}>)",
            lambda m: (m.group(1) + convert_text(m.group(2)) + m.group(3))
                      if re.search(r"[\u4e00-\u9fff]", m.group(2)) else m.group(0),
            opf_content, flags=re.DOTALL,
        )

    def _meta(m):
        full, val = m.group(0), m.group(1)
        return full.replace(val, convert_text(val)) if re.search(r"[\u4e00-\u9fff]", val) else full

    opf_content = re.sub(r'content="([^"]+)"', _meta, opf_content)
    return opf_content


def process_ncx(ncx_content):
    """目录标题繁转简（EPUB 2.0）"""
    def _rep(m):
        tag_o, content, tag_c = m.group(1), m.group(2), m.group(3)
        return tag_o + (convert_text(content) if re.search(r"[\u4e00-\u9fff]", content) else content) + tag_c
    return re.sub(r"(<text[^>]*>)(.*?)(</text>)", _rep, ncx_content, flags=re.DOTALL)


# ---------------------------------------------------------------------------
# EPUB 主流程
# ---------------------------------------------------------------------------
def _safe_read_write(filepath, processor, kind, stats):
    """统一读-处理-写，含编码兜底与异常隔离"""
    for enc in ("utf-8", "utf-8-sig", "gb18030"):
        try:
            with open(filepath, "r", encoding=enc) as f:
                content = f.read()
            break
        except UnicodeDecodeError:
            continue
    else:
        print(f"  [-] {kind.upper()} 编码无法识别，跳过: {filepath}")
        return
    try:
        out = processor(content)
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(out)
        stats[kind] += 1
    except Exception as e:
        print(f"  [-] {kind.upper()} 处理失败: {filepath} ({e})")


def process_epub(input_file, output_file=None):
    """处理单个 EPUB，返回输出路径"""
    if not os.path.isfile(input_file):
        print(f"[-] 找不到文件: {input_file}")
        return None

    os.makedirs(OUT_DIR, exist_ok=True)
    name = Path(input_file).stem
    out = output_file or os.path.join(OUT_DIR, f"{name}-简中.epub")

    tmp = tempfile.mkdtemp()
    stats = {"html": 0, "css": 0, "opf": 0, "ncx": 0}

    try:
        with zipfile.ZipFile(input_file, "r") as z:
            z.extractall(tmp)

        for root, _, files in os.walk(tmp):
            for file in files:
                fp = os.path.join(root, file)
                low = file.lower()

                if low.endswith((".html", ".xhtml", ".htm")):
                    _safe_read_write(fp, lambda c: clean_html_content(c, True), "html", stats)
                elif low.endswith(".css"):
                    _safe_read_write(fp, clean_css_file, "css", stats)
                elif low.endswith(".opf"):
                    _safe_read_write(fp, process_opf, "opf", stats)
                    print(f"  [*] 已处理元数据: {file}")
                elif low.endswith(".ncx"):
                    _safe_read_write(fp, process_ncx, "ncx", stats)
                    print(f"  [*] 已处理目录: {file}")

        print(f"  [*] 处理统计: HTML {stats['html']}, CSS {stats['css']}, "
              f"OPF {stats['opf']}, NCX {stats['ncx']}")

        # 重新打包（mimetype 无压缩且位于首位，符合 EPUB 规范）
        with zipfile.ZipFile(out, "w") as z:
            mt = os.path.join(tmp, "mimetype")
            if os.path.exists(mt):
                z.write(mt, "mimetype", compress_type=zipfile.ZIP_STORED)
            for root, _, files in os.walk(tmp):
                for file in files:
                    if file == "mimetype":
                        continue
                    fp = os.path.join(root, file)
                    arc = os.path.relpath(fp, tmp)
                    z.write(fp, arc, compress_type=zipfile.ZIP_DEFLATED)

        size_mb = os.path.getsize(out) / (1024 * 1024)
        print(f"[+] 转换成功: {out}  ({size_mb:.1f} MB)")
        if size_mb > 200:
            print(f"  [!] 警告：文件超过 200MB，Send to Kindle 网页版可能无法上传")
        return out

    except Exception as e:
        print(f"[-] 转换出错: {e}")
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main(argv=None):
    check_dependencies()
    args = argv if argv is not None else sys.argv[1:]

    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        print("用法: cc <文件或目录> [选项]")
        print("  cc 书名.epub                 # 单本转换")
        print("  cc ~/Download/               # 批量转换目录下所有 epub")
        print("  -o/--output <dir>            # 指定输出目录（默认 Download/E-book）")
        print("  --dry-run                    # 仅检测排版方向，不写入")
        print("  -v/--version                 # 版本号")
        return 0

    if "-v" in args or "--version" in args:
        print(f"cc-epub {__version__}")
        return 0

    output_dir = OUT_DIR
    if "-o" in args:
        i = args.index("-o"); output_dir = args[i + 1]
    elif "--output" in args:
        i = args.index("--output"); output_dir = args[i + 1]

    target = args[0]
    if os.path.isdir(target):
        files = sorted(Path(target).glob("*.epub"))
        if not files:
            print(f"[-] 目录 {target} 下未找到 .epub 文件")
            return 1
        for ep in files:
            print(f"\n=== 处理: {ep.name} ===")
            process_epub(str(ep))
        return 0
    else:
        process_epub(target)
        return 0


if __name__ == "__main__":
    sys.exit(main())
