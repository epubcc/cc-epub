#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cc-epub / convert.py
港台繁体 EPUB → 简体横排，完美保留排版、插图、目录、CSS

功能：
  1. 繁简转换（OpenCC：tw/hk → s）
  2. 竖排 → 横排（writing-mode 改写 + 标点调整）
  3. 字体统一（清除内嵌繁中字体 → Kindle 自带字体）
  4. 保留插图、目录、CSS、章节分隔
  5. 编码规范化（UTF-8 无 BOM）
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

NS_MAP = {
    "opf": "http://www.idpf.org/2007/opf",
    "dc": "http://purl.org/dc/elements/1.1/",
    "container": "urn:oasis:names:tc:opendocument:xmlns:container",
    "epub": "http://www.idpf.org/2007/opf",
}

for prefix, uri in NS_MAP.items():
    ET.register_namespace(prefix, uri)


# ============================================================
# 工具函数
# ============================================================

def run_opencc(text: str, config_name: str = "t2s.json") -> str:
    """调用 opencc 命令行进行繁→简转换"""
    result = subprocess.run(
        ["opencc", "-c", config_name],
        input=text,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"  ⚠ OpenCC 警告：{result.stderr.strip()}")
        return text
    return result.stdout


def detect_opencc_config(opf_path: str, manifest_items: list) -> str:
    """
    根据 EPUB 元数据/内容检测地区，选择转换配置：
    - t2s.json：台湾/通用繁体 → 简体
    - hk2s.json：香港 → 简体（若存在）
    """
    # 检查是否有 hk 标记
    for item in manifest_items:
        if "hk" in item.lower() or "hongkong" in item.lower():
            if Path("/data/data/com.termux/files/usr/share/opencc/hk2s.json").exists():
                return "hk2s.json"
    return "t2s.json"


# ============================================================
# CSS 处理
# ============================================================

def normalize_css(css_text: str, keep_font: bool = False) -> str:
    """
    规范化 CSS：
    - 竖排 → 横排
    - 标点调整
    - 字体统一（除非 keep_font=True）
    """
    # 1. 竖排 → 横排
    css_text = re.sub(
        r"writing-mode\s*:\s*vertical-(?:rl|lr|tb)\s*;?",
        "writing-mode: horizontal-tb;",
        css_text,
        flags=re.IGNORECASE,
    )
    css_text = re.sub(
        r"writing-mode\s*:\s*tb-(?:rl|lr)\s*;?",
        "writing-mode: horizontal-tb;",
        css_text,
        flags=re.IGNORECASE,
    )

    # 2. 方向属性
    css_text = re.sub(r"\bvertical\b", "horizontal", css_text, flags=re.IGNORECASE)

    # 3. 移除竖排相关的 text-orientation（避免横排时字符旋转）
    css_text = re.sub(
        r"text-orientation\s*:\s*[^;]+;?",
        "",
        css_text,
        flags=re.IGNORECASE,
    )

    # 4. 标点调整：确保横排标点正常
    if "text-align" not in css_text.lower():
        css_text += "\ntext-align: justify;"

    # 5. 字体处理
    if not keep_font:
        # 移除 @font-face 定义（内嵌繁中字体）
        css_text = re.sub(
            r"@font-face\s*\{[^}]*\}",
            "",
            css_text,
            flags=re.DOTALL,
        )
        # 将 font-family 统一为 Kindle 自带字体
        css_text = re.sub(
            r'font-family\s*:\s*[^;"]+;?',
            'font-family: serif;',
            css_text,
            flags=re.IGNORECASE,
        )

    # 6. 确保 UTF-8 声明
    if "@charset" not in css_text.lower():
        css_text = "@charset \"UTF-8\";\n" + css_text

    return css_text


# ============================================================
# HTML / XHTML 处理
# ============================================================

def process_html(html_text: str, opencc_config: str, keep_font: bool = False) -> str:
    """
    处理 HTML/XHTML 内容：
    - 繁→简转换（保留标签结构）
    - CSS 内联样式横排处理
    - style 标签内的 CSS 处理
    """
    # 1. 提取并处理 <style> 标签内的 CSS
    def replace_style_block(match):
        css = match.group(1)
        css = normalize_css(css, keep_font)
        return f"<style>{css}</style>"

    html_text = re.sub(
        r"<style[^>]*>(.*?)</style>",
        replace_style_block,
        html_text,
        flags=re.DOTALL | re.IGNORECASE,
    )

    # 2. 处理内联 style 属性中的竖排
    def replace_inline_style(match):
        style = match.group(1)
        style = re.sub(
            r"writing-mode\s*:\s*vertical-[^;]+;?",
            "writing-mode: horizontal-tb;",
            style,
            flags=re.IGNORECASE,
        )
        style = re.sub(r"\bvertical\b", "horizontal", style, flags=re.IGNORECASE)
        style = re.sub(r"text-orientation\s*:\s*[^;]+;?", "", style, flags=re.IGNORECASE)
        if not keep_font:
            style = re.sub(
                r'font-family\s*:\s*[^;"]+;?',
                'font-family: serif;',
                style,
                flags=re.IGNORECASE,
            )
        return f' style="{style}"'

    html_text = re.sub(
        r' style="([^"]*)"',
        replace_inline_style,
        html_text,
        flags=re.IGNORECASE,
    )

    # 3. 对 <body> 内的文本做繁→简转换（保留标签）
    body_pattern = re.compile(r"(<body[^>]*>)(.*?)(</body>)", re.DOTALL | re.IGNORECASE)

    def convert_body_content(match):
        prefix = match.group(1)
        body_content = match.group(2)
        suffix = match.group(3)

        # 按标签分割，只转换文本节点
        parts = re.split(r"(<[^>]+>)", body_content)
        converted_parts = []
        for part in parts:
            if part.startswith("<") and part.endswith(">"):
                # 这是标签，原样保留
                converted_parts.append(part)
            elif part.strip():
                # 这是文本内容，做繁简转换
                converted_parts.append(run_opencc(part, opencc_config))
            else:
                converted_parts.append(part)
        return prefix + "".join(converted_parts) + suffix

    html_text = body_pattern.sub(convert_body_content, html_text)

    # 4. 确保 <meta charset> 为 UTF-8
    if "charset" not in html_text.lower():
        html_text = re.sub(
            r"<head[^>]*>",
            lambda m: m.group(0) + '\n<meta charset="utf-8">',
            html_text,
            count=1,
            flags=re.IGNORECASE,
        )
    else:
        html_text = re.sub(
            r'charset\s*=\s*["\']?[^"\' >]+["\']?',
            'charset="utf-8"',
            html_text,
            flags=re.IGNORECASE,
        )

    return html_text


# ============================================================
# OPF 处理
# ============================================================

def process_opf(opf_text: str, opencc_config: str) -> str:
    """处理 OPF 元数据（书名、作者等繁→简）"""
    # 转换 dc:title, dc:creator, dc:description 等元数据
    def convert_meta(match):
        tag = match.group(1)
        content = match.group(2)
        attrs = match.group(3) or ""
        converted = run_opencc(content, opencc_config)
        return f"<{tag}{attrs}>{converted}</{tag.split()[0]}>"

    opf_text = re.sub(
        r"<dc:(title|creator|description|publisher|subject)>([^<]+)(</dc:\1>)?",
        lambda m: f"<dc:{m.group(1)}>{run_opencc(m.group(2), opencc_config)}</dc:{m.group(1)}>",
        opf_text,
        flags=re.IGNORECASE,
    )
    return opf_text


# ============================================================
# 主流程
# ============================================================

def convert_epub(args):
    input_path = Path(args.input)
    output_dir = Path(args.output)
    book_name = args.book_name

    if not input_path.exists():
        print(f"❌ 输入文件不存在：{input_path}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{book_name}-简中.epub"

    print(f"  📦 解包 EPUB...")
    work_dir = Path(tempfile.mkdtemp(prefix="cc_epub_"))

    try:
        # 1. 解压 EPUB
        with zipfile.ZipFile(input_path, "r") as zf:
            zf.extractall(work_dir)

        # 2. 解析 container.xml 找到 OPF
        container_path = work_dir / "META-INF" / "container.xml"
        if not container_path.exists():
            raise RuntimeError("无效的 EPUB：缺少 META-INF/container.xml")

        tree = ET.parse(container_path)
        root = tree.getroot()
        ns = {"c": NS_MAP["container"]}
        opf_rel_path = root.find(".//c:rootfile", ns).get("full-path")
        opf_path = work_dir / opf_rel_path
        opf_dir = opf_path.parent

        # 3. 读取 OPF，获取 manifest 文件列表
        opf_tree = ET.parse(opf_path)
        opf_root = opf_tree.getroot()
        manifest_ns = {"m": NS_MAP["opf"]}
        manifest_items = []
        for item in opf_root.findall(".//m:manifest/m:item", manifest_ns):
            href = item.get("href")
            media_type = item.get("media-type", "")
            if href:
                manifest_items.append(href)

        # 4. 检测地区，选择 OpenCC 配置
        opencc_config = detect_opencc_config(str(opf_path), manifest_items)
        print(f"  🔄 OpenCC 配置：{opencc_config}")

        # 5. 转换 OPF 元数据
        print(f"  📝 转换元数据...")
        opf_text = opf_path.read_text(encoding="utf-8", errors="replace")
        opf_text = process_opf(opf_text, opencc_config)
        opf_path.write_text(opf_text, encoding="utf-8")

        # 6. 遍历所有 content 文件，转换 HTML/XHTML/CSS
        converted_count = 0
        for item_href in manifest_items:
            item_path = (opf_dir / item_href).resolve()
            if not item_path.exists():
                continue

            rel_suffix = item_path.suffix.lower()
            if rel_suffix in (".html", ".xhtml", ".htm"):
                print(f"    → {item_href}")
                text = item_path.read_text(encoding="utf-8", errors="replace")
                text = process_html(text, opencc_config, args.keep_font)
                item_path.write_text(text, encoding="utf-8")
                converted_count += 1

            elif rel_suffix == ".css":
                text = item_path.read_text(encoding="utf-8", errors="replace")
                text = normalize_css(text, args.keep_font)
                item_path.write_text(text, encoding="utf-8")

        print(f"  ✓ 已转换 {converted_count} 个内容文件")

        # 7. 注入 Kindle 兼容 CSS（追加到第一个 CSS 文件或创建新文件）
        kindle_css_path = Path(args.config) / "kindle-css.css"
        if kindle_css_path.exists():
            kindle_css = kindle_css_path.read_text(encoding="utf-8")
            # 找到第一个 CSS，追加 Kindle 兼容规则
            for item_href in manifest_items:
                item_path = (opf_dir / item_href).resolve()
                if item_path.exists() and item_path.suffix.lower() == ".css":
                    with open(item_path, "a", encoding="utf-8") as f:
                        f.write("\n\n/* Kindle 兼容规范化 */\n")
                        f.write(kindle_css)
                    print(f"  ✓ 已注入 Kindle 兼容 CSS")
                    break

        # 8. 重新打包 EPUB（保留 ZIP 结构，mimetype 无压缩放首位）
        print(f"  📦 重新打包 EPUB...")
        repack_epub(work_dir, output_path)

        # 9. 校验输出
        if output_path.exists() and output_path.stat().st_size > 1000:
            size_mb = output_path.stat().st_size / (1024 * 1024)
            print(f"  ✓ 输出文件：{output_path}")
            print(f"  ✓ 文件大小：{size_mb:.2f} MB")
            if size_mb > 200:
                print(f"  ⚠️  警告：文件超过 200MB，Send to Kindle 可能无法上传！")
        else:
            print(f"  ❌ 输出文件异常，请检查日志")
            sys.exit(1)

    finally:
        shutil.rmtree(work_dir, ignore_errors=True)


def repack_epub(work_dir: Path, output_path: Path):
    """重新打包 EPUB，确保 mimetype 文件无压缩且在首位"""
    if output_path.exists():
        output_path.unlink()

    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        # 1. 先写入 mimetype（无压缩，必须在首位）
        mimetype_path = work_dir / "mimetype"
        if mimetype_path.exists():
            with open(mimetype_path, "rb") as f:
                zf.writestr("mimetype", f.read(), zipfile.ZIP_STORED)

        # 2. 写入其余所有文件
        for root, dirs, files in os.walk(work_dir):
            # 跳过 mimetype（已处理）
            dirs.sort()
            for fname in sorted(files):
                fpath = Path(root) / fname
                arcname = fpath.relative_to(work_dir).as_posix()
                if arcname == "mimetype":
                    continue
                zf.write(fpath, arcname)


def main():
    parser = argparse.ArgumentParser(
        description="港台繁体 EPUB → 简体横排转换工具"
    )
    parser.add_argument("--input", required=True, help="源 EPUB 文件路径")
    parser.add_argument("--output", required=True, help="输出目录")
    parser.add_argument("--book-name", required=True, help="书名（不含扩展名）")
    parser.add_argument("--keep-font", default="false", help="保留原字体（默认 false）")
    parser.add_argument("--config", default="", help="配置目录路径")

    args = parser.parse_args()
    args.keep_font = args.keep_font.lower() == "true"

    print("=" * 50)
    print("  cc-epub 转换器 v1.0")
    print("  繁体 → 简体 | 竖排 → 横排 | Kindle 优化")
    print("=" * 50)
    print("")

    convert_epub(args)

    print("")
    print("=" * 50)
    print("  ✅ 全部完成！")
    print("=" * 50)


if __name__ == "__main__":
    main()
