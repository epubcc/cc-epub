#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
港台繁体 EPUB 转换工具 v3.0
功能：繁体→简体 | 竖排→横排 | 首行缩进 2em | 清理全角空格 | 标点规范化 |
      字体统一 | 字号统一 | 保留插图/目录/章节结构
输出：~/storage/shared/Download/E-book/书名-简中.epub （书名取自 OPF <dc:title>）

处理顺序（需求⑦，杜绝 4em 痛点⑧）：
  清除段首全角空格 → 检测排版方向 → 竖排转横排 → 确认 2em
"""

import os
import re
import sys
import zipfile
import shutil
import subprocess
import tempfile
from bs4 import BeautifulSoup
from pathlib import Path

__version__ = "3.0.0"

# OpenCC 配置：台湾繁体→简体（含短语），香港书籍改为 hk2sp.json
OPENCC_CONFIG = "tw2sp.json"


# 无 opencc 时的基础繁→简兜底映射（一对一高频字，确保命名/元数据可读；
# 精确转换仍需 Termux 的 opencc-tools，见 install.sh / README）
_FALLBACK_T2S = {
    "習": "习", "慣": "惯", "轉": "转", "換": "换", "書": "书", "關": "关",
    "鍵": "键", "點": "点", "觀": "观", "強": "强", "調": "调", "進": "进",
    "步": "步", "脫": "脱", "胎": "胎", "換": "换", "骨": "骨", "來": "来",
    "這": "这", "讀": "读", "者": "者", "認": "认", "為": "为", "僅": "仅",
    "結": "结", "構": "构", "驗": "验", "證": "证", "命": "命", "橫": "横",
    "豎": "竖", "排": "排", "縮": "缩", "進": "进", "空": "空", "保": "保",
    "留": "留", "排": "排", "完": "完", "美": "美", "目": "目", "錄": "录",
    "章": "章", "節": "节", "體": "体", "設": "设", "置": "置", "分": "分",
    "離": "离", "調": "调", "用": "用", "自": "自", "帶": "带", "國": "国",
    "長": "长", "標": "标", "準": "准", "級": "级", "別": "别", "複": "复",
    "雜": "杂", "內": "内", "嵌": "嵌", "圖": "图", "片": "片", "導": "导",
    "致": "致", "正": "正", "文": "文", "無": "无", "法": "法", "渲": "渲",
    "染": "染", "白": "白", "頁": "页", "過": "过", "設": "设", "備": "备",
    "卡": "卡", "頓": "顿", "正": "正", "常": "常", "能": "能", "被": "被",
    "格": "格", "推": "推", "送": "送", "兼": "兼", "容": "容", "性": "性",
    "限": "限", "網": "网", "頁": "页", "版": "版", "大": "大", "小": "小",
    "不": "不", "得": "得", "超": "超", "若": "若", "文": "文", "件": "件",
    "使": "使", "用": "用", "了": "了", "特": "特", "殊": "殊", "的": "的",
    "中": "中", "字": "字", "號": "号", "樣": "样", "環": "环", "節": "节",
    "細": "细", "微": "微", "改": "改", "變": "变", "帶": "带", "成": "成",
    "效": "效", "個": "个", "作": "作", "家": "家", "著": "著", "作": "作",
    "權": "权", "出": "出", "版": "版", "社": "社", "年": "年", "月": "月",
    "日": "日", "時": "时", "分": "分", "秒": "秒", "週": "周", "幾": "几",
    "歲": "岁", "號": "号", "總": "总", "結": "结", "議": "议", "論": "论",
    "話": "话", "語": "语", "詞": "词", "試": "试", "運": "运", "輸": "输",
    "連": "连", "續": "续", "斷": "断", "專": "专", "業": "业", "歷": "历",
    "程": "程", "義": "义", "藝": "艺", "術": "术", "實": "实", "驗": "验",
    "開": "开", "關": "关", "閉": "闭", "電": "电", "腦": "脑", "軟": "软",
    "硬": "硬", "體": "体", "數": "数", "據": "据", "庫": "库", "類": "类",
    "質": "质", "量": "量", "選": "选", "擇": "择", "項": "项", "規": "规",
    "則": "则", "參": "参", "數": "数", "值": "值", "傳": "传", "統": "统",
    "現": "现", "狀": "状", "維": "维", "護": "护", "擴": "扩", "充": "充",
    "支": "支", "持": "持", "簡": "简", "繁": "繁", "轉": "转", "換": "换",
    # 高频差异字补充（避免兜底映射缺字）
    "間": "间", "對": "对", "從": "从", "處": "处", "務": "务",
    "動": "动", "勞": "劳", "勢": "势", "區": "区", "醫": "医",
    "縣": "县", "團": "团", "廣": "广", "應": "应", "張": "张",
    "歸": "归", "斷": "断", "專": "专", "傳": "传", "統": "统",
    "訓": "训", "詢": "询", "記": "记", "計": "计", "許": "许",
    "論": "论", "訪": "访", "訴": "诉", "診": "诊", "證": "证",
    "識": "识", "議": "议", "讓": "让", "邊": "边", "還": "还",
    "遠": "远", "達": "达", "運": "运", "遊": "游", "遲": "迟",
    "郵": "邮", "鄉": "乡", "銀": "银", "錢": "钱", "針": "针",
    "鎖": "锁", "門": "门", "開": "开", "關": "关", "閉": "闭",
    "問": "问", "聞": "闻", "閱": "阅", "陽": "阳", "陰": "阴",
    "階": "阶", "際": "际", "雙": "双", "黨": "党", "變": "变",
}


def _fallback_t2s(text):
    """无 opencc 时的基础繁→简字符映射（兜底，不追求 100% 准确）"""
    return "".join(_FALLBACK_T2S.get(ch, ch) for ch in text)

# 输出目录（Termux 存储路径）
OUT_DIR = str(Path.home() / "storage" / "shared" / "Download" / "E-book")


# ---------------------------------------------------------------------- 依赖
def check_dependencies():
    """检查依赖，缺失时尝试自动安装"""
    try:
        import bs4  # noqa: F401
    except ImportError:
        print("[-] 缺少依赖库 beautifulsoup4，正在尝试自动安装...")
        subprocess.run([sys.executable, "-m", "pip", "install", "beautifulsoup4"])
        try:
            import bs4  # noqa: F401
            print("[+] 依赖安装完成。")
        except ImportError:
            print("[-] 自动安装失败，请手动运行: pip install beautifulsoup4")
            sys.exit(1)


# ------------------------------------------------------------------- 繁简转换
def convert_text(text):
    """单段繁转简 + 标点规范化（无论是否安装 opencc，标点都规范化）"""
    if not text or not text.strip():
        return text
    converted = text
    try:
        result = subprocess.run(
            ["opencc", "-c", OPENCC_CONFIG],
            input=text, capture_output=True, text=True, encoding="utf-8",
        )
        if result.returncode == 0 and result.stdout:
            converted = result.stdout
    except FileNotFoundError:
        # 无 opencc（如开发环境），退化为基础字符映射 + 标点规范化
        converted = _fallback_t2s(text)
    except Exception:
        converted = _fallback_t2s(text)
    return normalize_punctuation(converted)


def batch_convert_t2s(texts):
    """批量繁转简：合并后一次性调用 opencc，大幅提升性能"""
    if not texts:
        return []

    separator = "\n\x00\n"
    combined = separator.join(texts)

    tmp = tempfile.gettempdir()
    tmp_in, tmp_out = os.path.join(tmp, "cc_in.txt"), os.path.join(tmp, "cc_out.txt")

    try:
        with open(tmp_in, "w", encoding="utf-8") as f:
            f.write(combined)
        result = subprocess.run(
            ["opencc", "-i", tmp_in, "-o", tmp_out, "-c", OPENCC_CONFIG],
            capture_output=True, text=True,
        )
        if result.returncode == 0 and os.path.exists(tmp_out):
            with open(tmp_out, "r", encoding="utf-8") as f:
                converted = f.read()
            return [normalize_punctuation(t) for t in converted.split(separator)]
        print("  [!] opencc 批量转换失败，逐段降级处理")
        return [convert_text(t) for t in texts]
    except Exception as e:
        print(f"  [!] 批量繁转简异常: {e}，逐段降级处理")
        return [convert_text(t) for t in texts]
    finally:
        for f in (tmp_in, tmp_out):
            if os.path.exists(f):
                os.remove(f)


# ------------------------------------------------------------- 标点规范化
def normalize_punctuation(text, *, protect_dashes=False):
    """将港台标点符号规范化为大陆标准。

    protect_dashes=True 时跳过破折号/省略号处理，用于清洗 <style>/<script>
    内的文本节点，避免把 CSS 属性/值里的连字符 "-" 误当破折号破坏语法
    （如 font-family → font——family）。
    """
    if not text:
        return text

    # 直角引号 → 弯引号（先外后内）
    text = text.replace("\u300c", "\u201c").replace("\u300d", "\u201d")  # 「」
    text = text.replace("\u300e", "\u2018").replace("\u300f", "\u2019")  # 『』

    # 港台小逗号 ﹐ → ， / 小句号 ﹒ → 。（需求⑧：原脚本漏了这两条）
    text = text.replace("\ufe50", "\uff0c")
    text = text.replace("\ufe51", "\u3002")
    text = text.replace("\uff64", "\uff0c")

    # 特殊逗号句号
    text = text.replace("\ufe44", "\uff0c").replace("\ufe45", "\u3002")

    if not protect_dashes:
        # 破折号：仅处理「含双字节破折号或 2 个及以上连字符」的情况
        text = re.sub(r"[—─━]{1,}", "\u2014\u2014", text)
        text = re.sub(r"(?:^|[^A-Za-z0-9_\-])(?:-{2,})(?=[^A-Za-z0-9_\-]|$)", "\u2014\u2014", text)

        # 省略号：把"多个"合并为两个（……）；单个 …… 保持不变，不翻倍
        text = re.sub(r"\u2026{3,}", "\u2026\u2026", text)
        text = re.sub(r"\.{3,}", "\u2026\u2026", text)

    # 间隔号 ． → ·
    text = text.replace("\uff0e", "\u00b7")

    # 特殊括号
    text = text.replace("\ufe5d", "(").replace("\ufe5e", ")")
    text = text.replace("\ufe59", "(").replace("\ufe5a", ")")

    return text


# ------------------------------------------------------------------ CSS 清洗
_CSS_DECL_RE = re.compile(r"(?i)(margin-left|padding-left|text-indent)\s*:\s*[^;]+;?")
_CSS_PROP_RE = re.compile(r"(?i)font-(?:family|size)\s*:\s*[^;]+;?")


def clean_css_file(css_content):
    """清洗外部 CSS：移除竖排/字体/字号，追加覆盖规则"""
    css = re.sub(r"@font-face\s*\{[^}]*\}", "", css_content, flags=re.IGNORECASE)
    css = _CSS_DECL_RE.sub("", css)
    css = re.sub(r"(?i)writing-mode\s*:\s*vertical-rl\s*;?", "", css)
    css = re.sub(r"(?i)text-orientation\s*:\s*[^;]+;?", "", css)
    css = _CSS_PROP_RE.sub("", css)
    css = re.sub(r"(?i)font\s*:\s*[^;]+;?", "", css)

    css += "\n\n/* --- Auto-injected by cc.py --- */\n"
    css += "p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }\n"
    css += "body { writing-mode: horizontal-tb !important; font-family: serif !important; font-size: 1em !important; line-height: 1.5 !important; }\n"
    css += "* { font-family: inherit !important; font-size: inherit !important; }\n"
    return css


# --------------------------------------------------------------- HTML 清洗
def _strip_leading_fullwidth_spaces(text):
    """仅清除「段首」全角/排版空格，保留段落中间的空格（需求②：保留排版）"""
    return re.sub(r"^[\u3000\u2000-\u200b\ufeff&emsp;]+", "", text)


def _is_inside_css_or_script(node):
    """判断文本节点是否位于 <style> 或 <script> 内（含自身即为该标签）"""
    for parent in node.parents:
        if getattr(parent, "name", None) in ("style", "script"):
            return True
    return False


def clean_html_content(html_content):
    """清洗 HTML：繁简 + 标点 + 清空格 + 清除竖排 + 统一缩进。

    关键：<style>/<script> 内的文本节点只做「CSS 结构清洗」，绝不跑
    繁简转换 / 标点规范化，否则会把 CSS 连字符 "-" 误当破折号破坏语法
    （如 font-family → font——family），导致 4em 残留、CSS 失效。
    """
    soup = BeautifulSoup(html_content, "html.parser")

    # 收集所有文本节点，分成"正文"与"style/script 内"两类
    def _body_nodes():
        return [n for n in soup.find_all(string=True)
                if n.strip() and not _is_inside_css_or_script(n)]

    # ① 繁简转换（仅正文、仅含汉字的节点）
    text_nodes = [n for n in _body_nodes() if re.search(r"[\u4e00-\u9fff]", str(n))]
    if text_nodes:
        orig = [str(n) for n in text_nodes]
        converted = batch_convert_t2s(orig)
        for node, cv in zip(text_nodes, converted):
            if cv != str(node):
                node.replace_with(cv)

    # ①-b 正文节点的标点规范化（<style>/<script> 内跳过，保护 CSS）
    # 注意：每步都重新收集节点，因为 replace_with 会让旧节点脱离树
    for node in _body_nodes():
        new = normalize_punctuation(str(node))
        if new != str(node):
            node.replace_with(new)

    # ② 清除「段首」全角/排版空格（需求⑦流程第一步；CSS 内不处理）
    for node in _body_nodes():
        if node.strip():
            new = _strip_leading_fullwidth_spaces(str(node))
            if new != str(node):
                node.replace_with(new)

    # ③ 清除 <p> 行内 style/class（统一由注入 CSS 控制）
    for p in soup.find_all("p"):
        if p.has_attr("style"):
            del p["style"]
        if p.has_attr("class"):
            del p["class"]

    # ④ 清除其他标签的 font-family / font-size 内联样式
    for tag in soup.find_all(True):
        if tag.has_attr("style"):
            style = _CSS_PROP_RE.sub("", tag["style"])
            if style.strip():
                tag["style"] = style
            else:
                del tag["style"]

    # ⑤ 修正 html/body 的 writing-mode（需求⑦：检测方向 → 竖转横）
    for tag in soup.find_all(["html", "body"]):
        if tag.has_attr("style"):
            s = re.sub(r"writing-mode\s*:\s*vertical-rl",
                       "writing-mode: horizontal-tb", tag["style"], flags=re.IGNORECASE)
            s = re.sub(r"direction\s*:\s*rtl", "direction: ltr", s, flags=re.IGNORECASE)
            tag["style"] = s

    # ⑥ 清洗 <style>/<script> 内嵌 CSS（仅结构清洗，不动标点/繁简）
    for style_tag in soup.find_all(["style", "script"]):
        if not style_tag.string:
            continue
        cleaned = style_tag.string
        cleaned = re.sub(r"@font-face\s*\{[^}]*\}", "", cleaned, flags=re.IGNORECASE)
        cleaned = _CSS_DECL_RE.sub("", cleaned)
        cleaned = re.sub(r"(?i)writing-mode\s*:\s*vertical-rl\s*;?", "", cleaned)
        cleaned = re.sub(r"(?i)text-orientation\s*:\s*[^;]+;?", "", cleaned)
        cleaned = _CSS_PROP_RE.sub("", cleaned)
        cleaned = re.sub(r"(?i)font\s*:\s*[^;]+;?", "", cleaned)
        # 移除被清空后残留的空规则块，避免破碎 CSS
        cleaned = re.sub(r"\{\s*\}", "", cleaned)
        cleaned = normalize_punctuation(cleaned, protect_dashes=True)
        if not cleaned.strip():
            style_tag.decompose()
        else:
            style_tag.string = cleaned

    # ⑦ 注入强制覆盖 CSS（确保 2em，杜绝 4em 叠加，需求⑧）
    force_css = """<style type="text/css">
/* --- Auto-injected by cc.py --- */
p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; text-align: justify; }
p.p, p.indent, p.no-indent, p.first, p.text { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }
body { writing-mode: horizontal-tb !important; direction: ltr !important; font-family: serif !important; font-size: 1em !important; line-height: 1.5 !important; }
html { writing-mode: horizontal-tb !important; font-family: serif !important; }
* { font-family: inherit !important; font-size: inherit !important; }
</style>"""
    injected = BeautifulSoup(force_css, "html.parser")
    if soup.head:
        soup.head.insert(0, injected)
    else:
        head = soup.new_tag("head")
        head.insert(0, injected)
        soup.insert(0, head)

    return str(soup)


# ------------------------------------------------------------------ OPF 处理
def process_opf(opf_content):
    """处理 OPF：修正阅读方向 + 元数据繁转简。

    需求⑦：检测排版方向。竖排书常带 page-progression-direction="rtl"，
    统一改为 ltr；若原 OPF 没有该属性，则在 <package> 开始标签内补一个，
    确保横排语义明确。
    """
    opf = opf_content
    if 'page-progression-direction' in opf:
        # 已有：rtl/auto/... → ltr
        opf = re.sub(
            r'(page-progression-direction\s*=\s*["\'])(?!ltr)[^"\']*(["\'])',
            r'\gltr\2', opf, flags=re.IGNORECASE,
        )
    else:
        # 无该属性：在 <package ...> 的开始标签内、结束 > 前插入
        def _insert(m):
            head, close = m.group(1), m.group(2)
            # 避免重复（head 可能已含 xmlns 等），直接追加在 > 前
            return head.rstrip() + ' page-progression-direction="ltr"' + close
        new_opf, n = re.subn(r'(<package\b[^>]*?)(>)', _insert, opf, count=1, flags=re.IGNORECASE)
        if n == 1:
            opf = new_opf

    def _cv(match):
        return (match.group(1) + convert_text(match.group(2)) + match.group(3)
                if re.search(r"[\u4e00-\u9fff]", match.group(2)) else match.group(0))

    for tag in ["title", "creator", "publisher", "description", "subject"]:
        opf = re.sub(
            rf"(<dc:{tag}[^>]*>)(.*?)(</dc:{tag}>)", _cv, opf, flags=re.DOTALL,
        )

    def _meta(match):
        full, val = match.group(0), match.group(1)
        return full.replace(val, convert_text(val)) if re.search(r"[\u4e00-\u9fff]", val) else full

    opf = re.sub(r'content="([^"]+)"', _meta, opf)
    return opf


def process_ncx(ncx_content):
    """处理 NCX 目录：繁转简标题"""
    def _cv(match):
        return (match.group(1) + convert_text(match.group(2)) + match.group(3)
                if re.search(r"[\u4e00-\u9fff]", match.group(2)) else match.group(0))
    return re.sub(r"(<text[^>]*>)(.*?)(</text>)", _cv, ncx_content, flags=re.DOTALL)


def _safe_read_write(filepath, process_fn):
    """统一读改写：跳过二进制文件（图片等），保留插图"""
    try:
        with open(filepath, "r", encoding="utf-8") as f:
            content = f.read()
    except (UnicodeDecodeError, ValueError):
        return False
    cleaned = process_fn(content)
    if cleaned != content:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(cleaned)
    return True


def _get_book_title(temp_dir):
    """从 OPF 的 <dc:title> 取书名（繁→简后），失败回退 None"""
    for root, _, files in os.walk(temp_dir):
        for file in files:
            if file.endswith(".opf"):
                try:
                    with open(os.path.join(root, file), "r", encoding="utf-8") as f:
                        content = f.read()
                except UnicodeDecodeError:
                    continue
                m = re.search(r"<dc:title[^>]*>(.*?)</dc:title>", content, re.DOTALL)
                if m:
                    title = re.sub(r"<[^>]+>", "", m.group(1)).strip()
                    if title:
                        title = convert_text(title)
                        title = re.sub(r'[\\/:*?"<>|\x00-\x1f]', "_", title)
                        return title
    return None


# ------------------------------------------------------------------ 主流程
def process_epub(input_file, output_override=None):
    """处理 EPUB 主流程"""
    if not os.path.isfile(input_file):
        print(f"[-] 找不到文件: {input_file}")
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    basename = os.path.splitext(os.path.basename(input_file))[0]

    tmp_dir = tempfile.mkdtemp()
    stats = {"html": 0, "css": 0, "opf": 0, "ncx": 0}

    try:
        with zipfile.ZipFile(input_file, "r") as z:
            z.extractall(tmp_dir)

        for root, _, files in os.walk(tmp_dir):
            for file in files:
                path = os.path.join(root, file)
                if file.endswith((".html", ".xhtml", ".htm")):
                    if _safe_read_write(path, clean_html_content):
                        stats["html"] += 1
                elif file.endswith(".css"):
                    if _safe_read_write(path, clean_css_file):
                        stats["css"] += 1
                elif file.endswith(".opf"):
                    if _safe_read_write(path, process_opf):
                        stats["opf"] += 1
                elif file.endswith(".ncx"):
                    if _safe_read_write(path, process_ncx):
                        stats["ncx"] += 1
                # 其余文件（图片/字体等）原样保留 → 插图/结构完整

        print(f"  [*] 处理统计: HTML {stats['html']}, CSS {stats['css']}, "
              f"OPF {stats['opf']}, NCX {stats['ncx']}")

        # ★ 输出文件名：优先「OPF 书名-简中.epub」
        book_title = _get_book_title(tmp_dir)
        if output_override:
            output_file = output_override
        elif book_title:
            output_file = os.path.join(OUT_DIR, f"{book_title}-简中.epub")
        else:
            output_file = os.path.join(OUT_DIR, f"{basename}-简中.epub")

        # 重新打包（mimetype 无压缩且位于首位，符合 EPUB 规范，需求⑨防白页）
        with zipfile.ZipFile(output_file, "w") as z:
            mt = os.path.join(tmp_dir, "mimetype")
            if os.path.exists(mt):
                z.write(mt, "mimetype", compress_type=zipfile.ZIP_STORED)
            for root, _, files in os.walk(tmp_dir):
                for file in files:
                    if file == "mimetype":
                        continue
                    fp = os.path.join(root, file)
                    arc = os.path.relpath(fp, tmp_dir)
                    z.write(fp, arc, compress_type=zipfile.ZIP_DEFLATED)

        print(f"[+] 转换成功！文件已保存至: {output_file}")

    except Exception as e:
        print(f"[-] 转换过程中出现错误: {e}")
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)


def main(argv=None):
    """命令行入口。argv 为参数列表（不含脚本名），便于测试注入。

    用法:
        cc <书名.epub>           输出: 书名-简中.epub（书名取自 OPF <dc:title>）
        cc <书本路径>
        cc -o <输出.epub> <输入.epub>
    输出位置: ~/storage/shared/Download/E-book/书名-简中.epub
    """
    check_dependencies()

    args = list(sys.argv[1:] if argv is None else argv)

    if len(args) < 1 or args[0] in ("--help", "-h", "help"):
        print("港台繁体 EPUB 转换工具 v" + __version__)
        print("用法: cc <书名.epub>           输出: 书名-简中.epub（书名取自 OPF）")
        print("      cc <书本路径>")
        print("      cc -o <输出.epub> <输入.epub>")
        print("")
        print("输出位置: ~/storage/shared/Download/E-book/书名-简中.epub")
        return

    output = None
    if args[0] == "-o" and len(args) >= 3:
        output = args[1]
        input_file = args[2]
    else:
        input_file = args[0]

    process_epub(input_file, output_override=output)


if __name__ == "__main__":
    main()
