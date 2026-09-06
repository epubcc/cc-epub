# cc-epub —— EPUB 港台繁体中文书籍转换

将**港台繁体 EPUB 电子书**一键转换为 **简体 + 横排 + 首行缩进**，适配 **Kindle Paperwhite（第12代）** 阅读。

> 设备链路：**OPPO Find X8s** → **Termux** → **OpenCC** → `cc-epub` → **Send to Kindle** → Kindle

## 📦 依赖（极简）

**系统包（Termux `pkg`）**：`python` + `opencc` + `libopencc` + `git`

**Python 包（`pip`）**：`opencc` + `chardet`（见 `requirements.txt`）

**其余**：全部用 Python 标准库（`zipfile`/`re`/`shutil`/`argparse`/`pathlib`），无重依赖。

| 依赖 | 类型 | 用途 |
|------|------|------|
| `python` | Termux pkg | Python 3.10+ 运行时 |
| `opencc` + `libopencc` | Termux pkg | OpenCC 词典与库（**必需**，pip 绑定依赖它） |
| `git` | Termux pkg | 克隆仓库 / 后续更新 |
| `opencc`（pip） | Python 包 | `import opencc` 调用转换 |
| `chardet`（pip） | Python 包 | 自动检测 EPUB 文件编码（GBK/Big5 等） |

> 📖 **完整部署步骤、依赖详解、排错**：见 **[SETUP.md](SETUP.md)** —— 从「刚安装 Termux」到跑通 `cc 某书.epub` 的保姆级教程。

## ✨ 功能

- ✅ **繁体 → 简体**（基于 OpenCC，默认 `t2s`；台湾惯用词用 `--config tw2sp`）
- ✅ **强制横排**（`writing-mode: horizontal-tb`）
- ✅ **首行缩进 2 字符**（`text-indent: 2em`）
- ✅ **Kindle 兼容性优化**：
  - 移除 `@font-face` 嵌入字体声明（防止 Kindle 白页）
  - 清理 `display:none`、`position:absolute`、`float` 等复杂 CSS（防止 Kindle 转换引擎崩溃）
  - 统一确保所有 XHTML 文件声明 UTF-8 编码
  - OPF 文件中 `<dc:language>` 自动设为 `zh-CN`
- ✅ **编码自动检测**：支持 UTF-8 / GBK / Big5 / Shift_JIS 等编码的 EPUB 文件
- ✅ **覆盖保护**：输出文件已存在时提示确认，防止误覆盖
- ✅ **保留 EPUB 合法结构**（`mimetype` 为首个未压缩条目，阅读器兼容）
- ✅ **幂等**：可重复运行，不会重复注入 CSS
- ✅ **自动更新输出路径**：`Download/E-book/书名-cc.epub`

## 📦 安装（Termux / 任意 Linux / macOS）

### 方式一：一键部署（推荐）

```bash
# Termux 一键部署（自动换源、装依赖、建别名、自检）
bash install-termux.sh
source ~/.bashrc
```

### 方式二：手动安装

```bash
# 1. 安装系统依赖
pkg install -y python opencc libopencc git

# 2. 克隆仓库
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub

# 3. 安装 Python 依赖
pip install -r requirements.txt

# 4. （可选）创建虚拟环境
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 🚀 用法

### 基本转换

```bash
# 便签中的核心命令：cc 书名
cc /sdcard/Download/E-book/某书.epub
# → 输出：/sdcard/Download/E-book/某书-cc.epub
```

### 常用选项

```bash
# 台湾惯用词更彻底（軟體→软件 等）
cc 某书.epub --config tw2sp

# 指定输出路径
cc 某书.epub -o 自定义路径.epub

# 只转文字，不注入横排/缩进 CSS
cc 某书.epub --no-css

# 等价完整命令
python convert.py 某书.epub -o Download/E-book/某书-cc.epub --config t2s
```

### 批量转换整个文件夹

```bash
for f in /sdcard/Download/E-book/*.epub; do
  cc "$f"
done
```

### 台湾繁体 vs 通用繁体的选择

| 场景 | 用哪个 config |
|------|---------------|
| 港台书籍，**只要简体字** | `t2s`（默认，够用） |
| 港台书籍，**还要惯用词转换**（軟體→软件、滑鼠→鼠标） | `tw2sp` |
| 繁体（含异体、旧字形）→ 规范繁体 | `s2t` |

## 🔗 推送至 Kindle

转换完成后，通过 **Send to Kindle** 网页版推送：

- 单文件 **≤ 200MB**（超大会在脚本中 WARN 提醒拆分）
- EPUB 经 Send to Kindle 自动转为 Kindle 原生格式
- 国行用户走 **amazon.co.jp** 站点

## 🤖 GitHub Actions 自动化

把 `.epub` 放到 `input/` 目录并 push → 自动转换 → 在 Actions **产物**里下载 `-cc.epub`。

## 🧪 本地测试

```bash
python test_convert.py
```

## 📄 License

MIT
