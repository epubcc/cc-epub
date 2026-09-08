#!/usr/bin/env python3
# -*- coding: utf-8 -*-
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
    """检查依赖"""
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

def normalize_punctuation(text):
    """将港台标点符号规范化为大陆标准"""
    if not text:
        return text

    # 1. 直角引号 → 弯引号（先外后内）
    text = text.replace('「', '"').replace('」', '"')
    text = text.replace('『', "'").replace('』', "'")

    # 2. 特殊逗号句号 → 标准全角逗号句号
    text = text.replace('\ufe44', '，')
    text = text.replace('\ufe45', '。')

    # 3. 破折号规范化：各种dash类字符统一为 ——
    text = re.sub(r'[—─━–]+', '——', text)

    # 4. 省略号规范化：三个及以上英文点 → ……，单个 … → ……
    text = re.sub(r'\.{3,}', '……', text)
    text = re.sub(r'…+', '……', text)

    # 5. 间隔号规范化
    text = text.replace('．', '·')

    # 6. 特殊括号 → 标准括号
    text = text.replace('﹝', '(').replace('﹞', ')')
    text = text.replace('﹙', '(').replace('﹚', ')')

    return text

def batch_convert_t2s(texts):
    """批量繁转简：将所有文本合并后一次性调用opencc，大幅提升性能"""
    if not texts:
        return []

    # 用特殊分隔符合并所有文本
    separator = '\n\x00\n'
    combined = separator.join(texts)

    temp_dir = tempfile.gettempdir()
    temp_in = os.path.join(temp_dir, "cc_batch_in.txt")
    temp_out = os.path.join(temp_dir, "cc_batch_out.txt")

    try:
        with open(temp_in, 'w', encoding='utf-8') as f:
            f.write(combined)

        result = subprocess.run(
            ['opencc', '-i', temp_in, '-o', temp_out, '-c', 'tw2sp.json'],
            capture_output=True, text=True
        )

        if result.returncode == 0 and os.path.exists(temp_out):
            with open(temp_out, 'r', encoding='utf-8') as f:
                converted_combined = f.read()
            # 拆分回各个文本
            converted_texts = converted_combined.split(separator)
            # 对每段进行标点规范化
            return [normalize_punctuation(t) for t in converted_texts]
        else:
            print(f"  [!] opencc 批量转换失败，逐段降级处理")
            return [normalize_punctuation(t) for t in texts]
    except Exception as e:
        print(f"  [!] 批量繁转简异常: {e}，逐段降级处理")
        return [convert_single_t2s(t) for t in texts]
    finally:
        for f in [temp_in, temp_out]:
            if os.path.exists(f):
                os.remove(f)

def convert_single_t2s(text):
    """单段繁转简（降级方案）"""
    if not text or not re.search(r'[\u4e00-\u9fff\u3000-\u303f\uff00-\uffef]', text):
        return text

    temp_dir = tempfile.gettempdir()
    temp_in = os.path.join(temp_dir, "cc_in.txt")
    temp_out = os.path.join(temp_dir, "cc_out.txt")

    try:
        with open(temp_in, 'w', encoding='utf-8') as f:
            f.write(text)

        result = subprocess.run(
            ['opencc', '-i', temp_in, '-o', temp_out, '-c', 'tw2sp.json'],
            capture_output=True, text=True
        )

        if result.returncode == 0 and os.path.exists(temp_out):
            with open(temp_out, 'r', encoding='utf-8') as f:
                converted = f.read()
            return normalize_punctuation(converted)
        else:
            return text
    except Exception as e:
        print(f"  [!] 繁转简异常: {e}")
        return text
    finally:
        for f in [temp_in, temp_out]:
            if os.path.exists(f):
                os.remove(f)

def clean_css_file(css_content):
    """清洗外部CSS文件"""
    css_content = re.sub(r'@font-face\s*\{[^}]+\}', '', css_content, flags=re.IGNORECASE)
    css_content = re.sub(r'(?i)(margin-left|padding-left)\s*:\s*[^;]+;', '', css_content)
    css_content = re.sub(r'(?i)writing-mode\s*:\s*vertical-rl\s*;?', '', css_content)
    css_content = re.sub(r'(?i)text-orientation\s*:\s*[^;]+;', '', css_content)
    css_content = re.sub(r'(?i)font-family\s*:\s*[^;]+;', '', css_content)
    css_content = re.sub(r'(?i)font-size\s*:\s*[^;]+;', '', css_content)
    css_content = re.sub(r'(?i)font\s*:\s*[^;]+;', '', css_content)
    css_content += '\n\n/* --- Auto-injected by cc.py --- */\n'
    css_content += 'p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }\n'
    css_content += 'body { writing-mode: horizontal-tb !important; font-family: serif !important; font-size: 1em !important; }\n'
    css_content += '* { font-family: inherit !important; font-size: inherit !important; }\n'
    return css_content

def clean_html_content(html_content, convert_t2s=True):
    """清洗HTML内容"""
    soup = BeautifulSoup(html_content, 'html.parser')

    if convert_t2s:
        text_nodes = []
        for element in soup.find_all(text=True):
            if element.strip() and re.search(r'[\u4e00-\u9fff]', str(element)):
                text_nodes.append(element)

        if text_nodes:
            original_texts = [str(node) for node in text_nodes]
            converted_texts = batch_convert_t2s(original_texts)

            for node, converted in zip(text_nodes, converted_texts):
                if converted != str(node):
                    node.replace_with(converted)

    for element in soup.find_all(text=True):
        if element.strip():
            new_text = str(element)
            new_text = re.sub(r'^[\u3000\s]+', '', new_text)
            new_text = re.sub(r'^(&emsp;|&ensp;|&#8195;|&#8194;)+', '', new_text)
            if new_text != str(element):
                element.replace_with(new_text)

    for p in soup.find_all('p'):
        if p.has_attr('style'):
            del p['style']
        if p.has_attr('class'):
            del p['class']

    for tag in soup.find_all(True):
        if tag.has_attr('style'):
            style = tag['style']
            style = re.sub(r'(?i)font-family\s*:\s*[^;]+;?', '', style)
            style = re.sub(r'(?i)font-size\s*:\s*[^;]+;?', '', style)
            if not style.strip():
                del tag['style']
            else:
                tag['style'] = style

    for tag in soup.find_all(['html', 'body']):
        if tag.has_attr('style'):
            style = tag['style']
            style = re.sub(r'writing-mode\s*:\s*vertical-rl', 'writing-mode: horizontal-tb', style, flags=re.IGNORECASE)
            style = re.sub(r'direction\s*:\s*rtl', 'direction: ltr', style, flags=re.IGNORECASE)
            tag['style'] = style

    force_css = """<style type=\"text/css\">
/* --- Auto-injected by cc.py --- */
p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; text-align: justify; }
p.p { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }
p.indent, p.no-indent, p.first, p.text { text-indent: 2em !important; margin: 0 !important; padding: 0 !important; }
body { writing-mode: horizontal-tb !important; direction: ltr !important; font-family: serif !important; font-size: 1em !important; }
html { writing-mode: horizontal-tb !important; font-family: serif !important; }
* { font-family: inherit !important; font-size: inherit !important; }
</style>"""
    if soup.head:
        soup.head.insert(0, BeautifulSoup(force_css, 'html.parser'))
    else:
        head_tag = soup.new_tag('head')
        head_tag.insert(0, BeautifulSoup(force_css, 'html.parser'))
        if len(soup.contents) > 0:
            soup.insert(0, head_tag)

    return str(soup)

def process_opf(opf_content):
    """处理OPF文件：修正阅读方向 + 繁转简元数据"""
    opf_content = re.sub(
        r'page-progression-direction\s*=\s*["\']rtl["\']',
        'page-progression-direction="ltr"',
        opf_content
    )

    for tag_name in ['title', 'creator', 'publisher', 'description', 'subject']:
        pattern = rf'(<dc:{tag_name}[^>]*>)(.*?)(</dc:{tag_name}>)'
        opf_content = re.sub(
            pattern,
            lambda m: m.group(1) + convert_single_t2s(m.group(2)) + m.group(3)
                      if re.search(r'[\u4e00-\u9fff]', m.group(2)) else m.group(0),
            opf_content,
            flags=re.DOTALL
        )

    def convert_meta_content(match):
        full = match.group(0)
        content_val = match.group(1)
        if re.search(r'[\u4e00-\u9fff]', content_val):
            converted = convert_single_t2s(content_val)
            full = full.replace(content_val, converted)
        return full

    opf_content = re.sub(r'content="([^"]+)"', convert_meta_content, opf_content)

    return opf_content

def process_ncx(ncx_content):
    """处理NCX目录文件：繁转简目录标题"""
    def replace_text_content(match):
        tag_open = match.group(1)
        content = match.group(2)
        tag_close = match.group(3)
        if re.search(r'[\u4e00-\u9fff]', content):
            content = convert_single_t2s(content)
        return tag_open + content + tag_close

    ncx_content = re.sub(r'(<text[^>]*>)(.*?)(</text>)', replace_text_content, ncx_content, flags=re.DOTALL)

    return ncx_content

def process_epub(input_file):
    """处理EPUB的主流程"""
    if not os.path.isfile(input_file):
        print(f"[-] 找不到文件: {input_file}")
        return

    os.makedirs(OUT_DIR, exist_ok=True)
    filename, ext = os.path.splitext(os.path.basename(input_file))
    output_file = os.path.join(OUT_DIR, f"{filename}-简中.epub")

    temp_dir = tempfile.mkdtemp()

    try:
        with zipfile.ZipFile(input_file, 'r') as z:
            z.extractall(temp_dir)

        file_count = {'html': 0, 'css': 0, 'opf': 0, 'ncx': 0}

        for root, _, files in os.walk(temp_dir):
            for file in files:
                filepath = os.path.join(root, file)

                if file.endswith(('.html', '.xhtml', '.htm')):
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        cleaned = clean_html_content(content, convert_t2s=True)
                        with open(filepath, 'w', encoding='utf-8') as f:
                            f.write(cleaned)
                        file_count['html'] += 1
                    except Exception as e:
                        print(f"  [-] HTML处理失败: {filepath} ({e})")

                elif file.endswith('.css'):
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        cleaned = clean_css_file(content)
                        with open(filepath, 'w', encoding='utf-8') as f:
                            f.write(cleaned)
                        file_count['css'] += 1
                    except Exception as e:
                        print(f"  [-] CSS处理失败: {filepath} ({e})")

                elif file.endswith('.opf'):
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        processed = process_opf(content)
                        with open(filepath, 'w', encoding='utf-8') as f:
                            f.write(processed)
                        file_count['opf'] += 1
                        print(f"  [*] 已处理元数据: {file}")
                    except Exception as e:
                        print(f"  [-] OPF处理失败: {filepath} ({e})")

                elif file.endswith('.ncx'):
                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        processed = process_ncx(content)
                        with open(filepath, 'w', encoding='utf-8') as f:
                            f.write(processed)
                        file_count['ncx'] += 1
                        print(f"  [*] 已处理目录: {file}")
                    except Exception as e:
                        print(f"  [-] NCX处理失败: {filepath} ({e})")

        print(f"  [*] 处理统计: HTML {file_count['html']}个, CSS {file_count['css']}个, OPF {file_count['opf']}个, NCX {file_count['ncx']}个")

        with zipfile.ZipFile(output_file, 'w') as z:
            mimetype_path = os.path.join(temp_dir, 'mimetype')
            if os.path.exists(mimetype_path):
                z.write(mimetype_path, 'mimetype', compress_type=zipfile.ZIP_STORED)
            for root, _, files in os.walk(temp_dir):
                for file in files:
                    if file == 'mimetype':
                        continue
                    filepath = os.path.join(root, file)
                    arcname = os.path.relpath(filepath, temp_dir)
                    z.write(filepath, arcname, compress_type=zipfile.ZIP_DEFLATED)

        print(f"[+] 转换成功！文件已保存至: {output_file}")

    except Exception as e:
        print(f"[-] 转换过程中出现错误: {e}")
    finally:
        shutil.rmtree(temp_dir)

if __name__ == "__main__":
    check_dependencies()
    if len(sys.argv) < 2:
        print("用法: cc <书名.epub> 或 cc <书本路径>")
    else:
        process_epub(sys.argv[1])
