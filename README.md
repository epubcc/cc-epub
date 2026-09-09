# cc-epub · 港台繁体 EPUB → 简体横排（Kindle KFX 优化）

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](./LICENSE)
[![Python 3](https://img.shields.io/badge/python-3.x-blue.svg)](https://www.python.org/)
[![Platform: Termux](https://img.shields.io/badge/platform-Termux%202.0--rc1-brightgreen.svg)](https://f-droid.org/packages/com.termux/)
[![CI](https://github.com/epubcc/cc-epub/workflows/CI/badge.svg)](https://github.com/epubcc/cc-epub/actions)

将港台繁体中文 EPUB 一键转换为 **简体中文 + 横排 + 首行缩进 2em**，专门针对 **Kindle Paperwhite Signature Edition（第 12 代）+ Send to Kindle** 的流程优化：转换后自动推送为 KFX，规避白页 / 卡顿。

---

## ✨ 功能特性

| # | 功能 | 说明 |
|---|------|------|
| 1 | **繁体→简体** | 覆盖正文、书名、作者、出版社、简介、目录标题，使用 `tw2sp.json`（含台湾短语/词汇转换） |
| 2 | **竖排→横排** | 自动检测并修正 `writing-mode`、`direction`、`page-progression-direction` |
| 3 | **首行缩进 2em** | 「文本空格归零 + CSS 单一来源」双保险，**根除 4em / 四字宽叠加**（痛点 #8） |
| 4 | **标点规范化** | 「」→""、『』→''、破折号→——、省略号→……、间隔号．→· |
| 5 | **字体/字号统一** | 移除嵌入字体 `@font-face`，统一 `serif` / `1em`，可调用 Kindle 自带字体、自由调字号 |
| 6 | **KFX 兼容** | 清理复杂 CSS3 / 外链字体，降低 Send to Kindle 转换白页 / 超大文件风险 |
| 7 | **保留原始排版** | 插图、目录结构、章节分隔、CSS 骨架、`<p>` 的 `class` 全部保留，仅最小化修正冲突项 |

### 痛点专项：为什么不会再有 4em 缩进？

港台竖排书常见「全角空格 `\u3000` + CSS `text-indent: 2em`」双重缩进，转横排后叠加成 4em。本工具的处理顺序（严格对应需求 #7）：

```
① 清除段落前全角空格 / &emsp; / &#8195; 等缩进实体（文本层归零）
② 检测排版方向（vertical-rl / horizontal-tb）
③ 竖排 → 横排；已横排 → 仅校验缩进
④ 统一简体 + 2em + 标点规范 + 字体字号统一
```

缩进由注入的 `p { text-indent: 2em !important }` **单一来源**控制，文本层不再贡献宽度，从原理上杜绝叠加。

---

## 🚀 快速开始（Termux，一行命令）

> 操作设备 OPPO Find X8s，软件 Termux 2.0-rc1（F-Droid 下载），转换工具 OpenCC 1.4.2。

### 一键部署（推荐）

在 Termux 中复制粘贴下面**这一行**：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"
```

脚本会自动完成：更新软件源 → 安装系统依赖 → 安装 Python 库 → 克隆仓库 → 配置 `cc` 快捷命令。

### 手动部署（分步，可复制粘贴）

```bash
# ① 更新软件源（强烈建议先换国内镜像：termux-change-repo → 清华源）
pkg update -y && pkg upgrade -y

# ② 授予存储权限（访问手机 Download 目录）
termux-setup-storage

# ③ 安装系统依赖
#    ⚠️ Termux 官方仓库【没有】名为 "Open CC" 的包，正确包名是 libopencc + opencc-tools
pkg install -y python git zip unzip libopencc opencc-tools

# ④ 安装 Python 库
pip install beautifulsoup4

# ⑤ 克隆仓库
git clone https://github.com/epubcc/cc-epub.git ~/cc-epub
cd ~/cc-epub

# ⑥ 运行部署脚本（配置 cc 命令）
bash install.sh

# ⑦ 让 cc 命令在当前会话立即生效
source ~/.bashrc
```

### 使用方法

```bash
# 单本转换（命令格式：cc 书名）
cc 原子習慣.epub

# 指定文件完整路径
cc ~/storage/shared/Download/三體.epub

# 批量转换整个目录
cc ~/storage/shared/Download/
```

**输出情况：**
- 文件自动更名为 `书名-简中.epub`
- 自动保存到 `~/storage/shared/Download/E-book/`
- （手机实际路径：`/storage/emulated/0/Download/E-book/`）

然后通过 **Send to Kindle 网页版** 上传即可（文件 ≤ 200 MB）。

---

## 🔧 命令参数

```
cc <文件或目录> [选项]
  cc 书名.epub                 # 单本转换
  cc ~/Download/               # 批量转换目录下所有 .epub
  -o/--output <dir>            # 指定输出目录（默认 Download/E-book）
  --dry-run                    # 仅检测排版方向，不写入
  -v/--version                 # 显示版本号
  -h/--help                    # 帮助
```

---

## 📁 项目结构

```
cc-epub/
├── cc.py                  # 核心脚本
├── install.sh             # 一键部署脚本
├── tests/
│   └── test_cc.py         # 端到端测试（pytest 兼容）
├── .github/
│   ├── workflows/ci.yml   # GitHub Actions 自动测试
│   ├── ISSUE_TEMPLATE/    # Bug / 功能建议模板
│   └── pull_request_template.md
├── LICENSE                # MIT
├── README.md
└── .gitignore
```

---

## 🧪 测试

本地运行（需先 `pip install beautifulsoup4 opencc`）：

```bash
python tests/test_cc.py
```

CI 会在每次 push / PR 时自动运行 pytest。

---

## ⚙️ 高级配置

### 香港繁体书籍

默认用 `tw2sp.json`（台湾）。香港书打开 `cc.py` 改一行：

```python
OPENCC_CONFIG = "hk2sp.json"   # 台湾书为 tw2sp.json
```

| 配置 | 说明 |
|------|------|
| `tw2sp.json` | 台湾繁体→简体（含短语，**默认**，最彻底） |
| `hk2sp.json` | 香港繁体→简体（含短语） |
| `t2s.json`   | 繁体→简体（逐字，通用） |

### 依赖一览

| 依赖 | 用途 | 安装 |
|------|------|------|
| `python` | 运行脚本 | `pkg install python` |
| `libopencc` + `opencc-tools` | OpenCC 核心 + 命令行 | `pkg install libopencc opencc-tools` |
| `zip` / `unzip` | EPUB 解压打包 | `pkg install zip unzip` |
| `beautifulsoup4` | HTML 解析 | `pip install beautifulsoup4` |

> 脚本启动时会自动检测依赖，缺失 `beautifulsoup4` 会尝试自动安装。

---

## ❓ 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| `cc` 命令被 clang 拦截 | Termux 自带 `cc` 编译器别名 | 已用 `~/bin/cc` wrapper + PATH 前置 + alias 三保险覆盖 |
| `command not found: cc` | 未重载 shell | `source ~/.bashrc` 或重启 Termux |
| `opencc: command not found` | 未装完整 | `pkg install libopencc opencc-tools` |
| 作者/书名仍是繁体 | 旧版未处理 OPF | 已处理 `<dc:*>` 全部元数据 |
| 目录仍是繁体 | 旧版未处理 NCX | 已处理 `.ncx` 的 `<text>` |
| 引号仍是直角「」 | 旧版未规范化 | 已内置 `normalize_punctuation()` |
| 首行缩进 4em / 四字宽 | 全角空格 + CSS 叠加 | 文本层清空格 + `!important` 单一来源 |
| 字体/字号不统一 | 原书嵌入自定义字体 | 清除 `@font-face` + 统一 `serif` / `1em` |
| 转换后白页 / 卡顿 | 复杂排版致 KFX 转换失败 | 清理复杂 CSS3、移除嵌入字体（本工具已处理） |
| 推送失败 / 超过 200MB | Send to Kindle 网页版限制 | 精简图片或分卷；文件需 ≤ 200MB |
| `storage` 目录找不到 | 未授权存储 | `termux-setup-storage` 并点"允许" |
| 息屏后被杀进程 | 安卓清理后台 | `termux-wake-lock` 保活 |

---

## 🔄 工作流程（技术细节）

```
EPUB 解压 → 遍历文件
  ├─ .xhtml/.html/.htm  →  ①繁转简 → ②清全角空格 → ③清冲突内联样式
  │                        → ④修正 html/body 方向 → ⑤注入覆盖 CSS
  ├─ .css                →  移除 @font-face/冲突属性 → 追加统一规则
  ├─ .opf                →  元数据繁转简 + 修正阅读方向
  ├─ .ncx                →  目录标题繁转简
  └─ 重新打包（mimetype 无压缩置顶）
```

**兼容性：** 标准 EPUB 2.0 / 3.0；对 **DRM 加密**的 EPUB 无效；转换后通过 Send to Kindle 自动转 KFX。

---

## 📄 License

MIT License — 详见 [LICENSE](./LICENSE)。
