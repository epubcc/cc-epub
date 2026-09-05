# cc-epub v2.0

**Termux 一键部署 · 港台 EPUB 繁转简 · 竖排转横排 · Kindle 深度适配**

一个运行在 Android Termux 环境下的 Shell 脚本工具，旨在解决港台 EPUB 电子书在 Kindle 或普通阅读器上阅读体验不佳的问题（繁体、竖排、字体错乱、标点混用、Kindle 强制转 PDF）。

## 核心功能

- **繁简转换**：基于 OpenCC (tw2sp)，将台湾/香港繁体中文转换为简体中文
- **术语补丁**：自动修正港台特有词汇（计画→计划、網路→网络、软体→软件、程式→程序、列印→打印、位元組→字节、行销→营销、網誌/部落格→博客、連線→连接、伺服器→服务器、資訊→信息、硬碟→硬盘、記憶体→内存、螢幕→屏幕、滑鼠→鼠标、光碟→光盘、觸控→触控、鍵盤→键盘等）
- **标点符号清洗**：自动将繁体标点（「」『』、全形逗号句号等）转换为简体标点（""''、半形逗号句号等）
- **竖排转横排**：自动识别并修改 CSS 及 HTML 内联样式，将 `vertical-rl`、`vertical-lr`、`sideways-rl` 等竖排模式强制转换为 `horizontal-tb`
- **字体统一化**：自动替换 MingLiu、PMingLiu、標楷體、新細明體、DFKaiShu、BiauKai 等繁体专用字体为通用 serif，同时处理 CSS 文件和 HTML 内联样式中的 `font-family` 声明
- **Kindle 防 PDF 化清洗**：自动移除 `position: absolute/fixed`、`float`、`display: flex` 等会导致 Kindle 服务器（KindleGen）放弃重排并强制转为 PDF 的 CSS 属性，确保输出标准流式排版 EPUB
- **图片压缩**：自动压缩图片（需安装 imagemagick），解决 Kindle 翻页卡顿问题
- **智能查找**：支持模糊匹配文件名，自动列出候选项供选择
- **转换前备份**：通过环境变量 `EPUB_BACKUP=on` 一键开启原文件备份
- **零依赖部署**：无需 Root，无需 Python 环境（纯 Shell 实现），Termux 一键安装

## 快速开始

在 Termux 中执行以下命令一键安装：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"
```

安装完成后，重启 Termux 或执行 `source ~/.bashrc`。

## 使用指南

确保你的 EPUB 文件已放入手机的 **Downloads** 目录。

| 命令 | 说明 |
| :--- | :--- |
| `cc 书名` | 自动查找并转换（支持模糊搜索） |
| `cc --list` | 列出 Downloads 目录下所有可转换的 EPUB |
| `cc --doctor` | 检查运行环境依赖是否完整 |
| `cc --version` | 显示版本号 |
| `cc --help` | 查看帮助信息 |

**示例：**

```bash
cc 三体
# 如果找到多个文件，会提示输入编号选择

EPUB_BACKUP=on cc 三体
# 转换前自动备份原文件

EPUB_IMG=off cc 三体
# 画册模式，跳过图片压缩

EPUB_BASE_DIR=/sdcard/cc cc 三体
# 指定其他目录作为书籍来源
```

## 环境变量

| 变量 | 说明 |
| :--- | :--- |
| `EPUB_BACKUP=on` | 转换前备份原文件（生成 .bak 副本） |
| `EPUB_IMG=off` | 跳过图片压缩（适用于画册/漫画类 EPUB） |
| `EPUB_BASE_DIR` | 自定义下载目录（默认: ~/storage/downloads） |

## 依赖说明

| 依赖 | 用途 | 是否必需 |
| :--- | :--- | :--- |
| `unzip` / `zip` | EPUB 解包与打包 | 必需 |
| `opencc-tools` | 繁简转换引擎（提供 opencc 命令） | 必需 |
| `imagemagick` | 图片压缩优化 | 可选（未安装时自动跳过） |

> **注意**：Termux 中繁简转换的包名为 `opencc-tools`（不是 `opencc`）。

## 转换流程

脚本执行时按以下顺序处理（共 9 步）：

| 步骤 | 处理内容 | 说明 |
| :--- | :--- | :--- |
| 1 | 繁简转换 | opencc tw2sp 核心转换 |
| 2 | 术语补丁 | 港台特有词汇二次修正 |
| 3 | 标点符号清洗 | 繁体标点→简体标点 |
| 4 | 竖排转横排（CSS） | 处理 CSS 文件中的竖排模式 |
| 5 | 竖排转横排（HTML） | 处理 HTML 内联样式中的竖排模式 |
| 6 | 清理残留竖排标记 | 删除 writing-mode / text-orientation 残留 |
| 7 | 字体统一化 | 替换繁体专用字体（CSS + HTML 内联样式） |
| 8 | **Kindle 深度清洗** | 移除导致 PDF 化的 CSS 属性（position:absolute/fixed, float, display:flex） |
| 9 | 图片压缩 | 压缩图片减小体积（可选） |

## 为什么 Kindle 会变 PDF？

亚马逊的转换引擎（KindleGen）非常老旧。如果 EPUB 中包含复杂的 CSS 定位（如 `position: absolute`）、浮动（`float`）或弹性布局（`display: flex`），引擎会认为无法进行文字重排，从而直接将每一页渲染成图片（即 PDF 模式）。

本脚本通过**步骤 8（Kindle 深度清洗）**，在打包前强制移除这些"危险"样式，确保 Kindle 将其识别为标准的流式排版书籍。

## 文件结构

- `install.sh` — 安装脚本，负责配置源、安装依赖、写入主程序
- `cc.sh` — 核心转换逻辑（解压、转换、排版修复、Kindle 清洗、重打包）
- `README.md` — 项目说明文档

## 注意事项

1. **存储权限**：首次运行 Termux 请务必执行 `termux-setup-storage` 并允许存储权限
2. **输出目录**：转换后的文件将保存在 `~/storage/downloads/E-book/` 目录下
3. **备份机制**：脚本不会修改原文件，而是生成 `-cc.epub` 后缀的新文件；开启 `EPUB_BACKUP=on` 后还会生成 `.bak` 备份
4. **Kindle 兼容**：输出标准 EPUB 格式，内置 Kindle 防 PDF 化清洗。推送至 Kindle 后应正常显示为可重排电子书
5. **文件名空格**：如果文件名中包含空格，请用引号包裹：`cc "my book.epub"`

## 故障排查

### `cc: command not found`

```bash
# 方法1：刷新配置
source ~/.bashrc

# 方法2：手动定义函数（推荐，支持环境变量传递）
cc() { cd ~/storage/downloads 2>/dev/null && "$HOME/.epub_cc/cc.sh" "$@"; }

# 方法3：直接执行
$HOME/.epub_cc/cc.sh 书名
```

### `opencc: command not found`

```bash
# opencc 命令由 opencc-tools 包提供，不是 opencc
pkg install opencc-tools
```

### 转换后 Kindle 仍然变 PDF

```bash
# 方法1：确认步骤8已执行（输出中应看到 "Kindle 清洗完成"）
# 方法2：用 USB 直接传输到 Kindle 的 documents 文件夹（绕过亚马逊服务器）
# 方法3：通过 Calibre 中转转换（Calibre → 转换 → AZW3/KFX）
```

### 解包失败

```bash
# 可能是文件已损坏或不是有效的 EPUB 格式
# 尝试用 Calibre 修复文件后重新转换
```

### 图片压缩失败

```bash
# 确保已安装 imagemagick
pkg install imagemagick
# 或者使用画册模式跳过压缩
EPUB_IMG=off cc 书名
```

## 安装与部署

### 方式一：一键安装（推荐）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"
```

### 方式二：手动安装

```bash
# 1. 下载脚本
curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/cc.sh -o cc.sh
chmod +x cc.sh

# 2. 安装依赖（注意包名为 opencc-tools，不是 opencc）
pkg update
pkg install -y unzip zip opencc-tools imagemagick

# 3. 配置函数（推荐用函数，支持环境变量传递）
echo 'cc() { cd ~/storage/downloads 2>/dev/null && "$HOME/.epub_cc/cc.sh" "$@"; }' >> ~/.bashrc
source ~/.bashrc
```

## 更新日志

### v2.0（当前版本）

- 新增 Kindle 深度清洗（步骤8），自动移除 position:absolute/fixed、float、display:flex 等 CSS 属性
- 新增 `--version` 选项
- 新增 `EPUB_BASE_DIR` 环境变量，支持自定义书籍目录
- 安装脚本改用函数替代 alias，正确支持环境变量传递（如 `EPUB_BACKUP=on cc 书名`）
- 术语补丁去重，统一处理
- 标点清洗去重，覆盖更多繁体标点符号
- 字体统一化增强，覆盖 CSS、HTML 内联样式、HTML 属性三种场景
- 所有 `sed` 命令添加 `|| true` 防误退出
- 使用 `set -euo pipefail` 强化错误处理
- 使用 `nullglob` 避免无匹配文件时报错

### v1.0

- 初始版本，支持繁简转换、竖排转横排、图片压缩

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可

MIT License
