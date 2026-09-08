#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
EPUB 竖排转横排 + 繁转简 转换工具
适用于 Termux 环境，支持港台竖排 EPUB 一键转为横排简体中文版。

用法: python cc.py <书名.epub>
输出: 同目录下生成 <书名>-简中.epub
"""
import os
import sys
import re
import zipfile
import shutil
import subprocess
import tempfile
from bs4 import BeautifulSoup

# 配置输出目录
OUT_DIR = "/storage/emulated/0/Download/E-book"


def check_dependencies():
    """检查并自动安装 Python 依赖"""
    try:
        import bs4
    except ImportError:
        print("[-] 缺少依赖库 beautifulsoup4，正在尝试自动安装...")
        subprocess.run([sys.executable, "-m", "pip", "install", "beautifulsoup4"])
        try:
            import bs4
            print("[+] 依赖安装完成。")
        except ImportError:
            print("[-] 自动安装失败，请手动运行: pip install beautifulsoup4")
            sys.exit(1)


def clean_spaces_and_convert(filepath):
    """清理全角空格并调用 opencc 繁转简"""
    with open(filepath, 'r', encoding='utf-8') as f:
        soup = BeautifulSoup(f, 'lxml-xml')

    # 1. 清除段落首尾的全角/半角空格
    for p in soup.find_all(['p', 'div', 'td']):
        if p.string:
            # 去除行首的全角空格(\u3000)和半角空格
            p.string = re.sub(r'^[ \u3000]+', '', p.string)
            # 去除行尾的空格
            p.string = re.sub(r'[\u3000 ]+$', '', p.string)

    # 将清理后的 HTML 写回临时文件
    temp_html = filepath + '.tmp'
    with open(temp_html, 'w', encoding='utf-8') as f:
        f.write(str(soup))

    # 2. 调用 opencc-tools 进行繁体转简体 (tw2s: 台湾繁体转简体)
    subprocess.run(
        ['opencc', '-i', temp_html, '-o', filepath, '-c', 'tw2s'],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    os.remove(temp_html)


def fix_css_and_orientation(filepath):
    """修改 HTML：注入横排 CSS，暴力覆盖缩进样式"""
    with open(filepath, 'r', encoding='utf-8') as f:
        soup = BeautifulSoup(f, 'lxml-xml')

    if not soup.head:
        return

    # 注入暴力覆盖的 CSS，解决首行缩进叠加、KFX 兼容性问题
    style_tag = soup.new_tag('style')
    style_tag.string = """
    body {
        writing-mode: horizontal-tb !important;
        -epub-writing-mode: horizontal-tb !important;
        -webkit-writing-mode: horizontal-tb !important;
        text-align: justify;
    }
    p, div, td {
        text-indent: 2em !important;
        margin: 0 !important;
        padding: 0 !important;
        line-height: 1.5 !important;
    }
    """
    soup.head.append(style_tag)

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(str(soup))


def fix_opf(filepath):
    """修正 OPF 文件中的阅读方向 (rtl -> ltr)"""
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # 将从右向左(rtl)改为从左向右(ltr)
    content = re.sub(
        r'page-progression-direction\s*=\s*["\']rtl["\']',
        'page-progression-direction="ltr"',
        content
    )

    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)


def process_epub(input_file):
    """处理 EPUB 的主流程"""
    if not os.path.isfile(input_file):
        print(f"[-] 找不到文件: {input_file}")
        return

    # 确定输出路径
    os.makedirs(OUT_DIR, exist_ok=True)
    filename, ext = os.path.splitext(os.path.basename(input_file))
    output_file = os.path.join(OUT_DIR, f"{filename}-简中.epub")

    # 创建临时目录
    temp_dir = tempfile.mkdtemp()

    try:
        # 解压 EPUB
        print("[*] 正在解压 EPUB...")
        with zipfile.ZipFile(input_file, 'r') as z:
            z.extractall(temp_dir)

        # 遍历所有 HTML/XHTML 文件进行处理
        print("[*] 正在清洗文本、繁转简、重置排版...")
        for root, _, files in os.walk(temp_dir):
            for file in files:
                if file.endswith(('.html', '.xhtml', '.htm')):
                    filepath = os.path.join(root, file)
                    clean_spaces_and_convert(filepath)
                    fix_css_and_orientation(filepath)
                elif file.endswith('.opf'):
                    fix_opf(os.path.join(root, file))

        # 重新打包 EPUB (mimetype 必须第一个打包且不压缩)
        print("[*] 正在重新打包 EPUB...")
        with zipfile.ZipFile(output_file, 'w', zipfile.ZIP_DEFLATED) as z:
            mimetype_path = os.path.join(temp_dir, 'mimetype')
            if os.path.exists(mimetype_path):
                z.write(mimetype_path, 'mimetype', compress_type=zipfile.ZIP_STORED)

            for root, _, files in os.walk(temp_dir):
                for file in files:
                    if file == 'mimetype':
                        continue
                    filepath = os.path.join(root, file)
                    arcname = os.path.relpath(filepath, temp_dir)
                    z.write(filepath, arcname)

        print(f"[+] 转换成功！文件已保存至: {output_file}")

    except Exception as e:
        print(f"[-] 转换过程中出现错误: {e}")
    finally:
        shutil.rmtree(temp_dir)


if __name__ == "__main__":
    check_dependencies()
    if len(sys.argv) < 2:
        print("用法: python cc.py <书名.epub>")
        print("示例: python cc.py 射雕英雄传.epub")
        print("输出文件将保存至: /storage/emulated/0/Download/E-book/")
    else:
        process_epub(sys.argv[1])
