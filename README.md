# cc-epub v3.0

**Termux 一键部署 · 港台 EPUB 繁转简 · 竖排转横排 · Kindle 深度适配**

一个运行在 Android Termux 环境下的 Shell 脚本工具，旨在解决港台 EPUB 电子书在 Kindle 或普通阅读器上阅读体验不佳的问题（繁体、竖排、字体错乱、标点混用、Kindle 强制转 PDF、字体声明拒绝发送）。

## 核心功能

- **繁简转换**：基于 OpenCC (tw2sp)，将台湾/香港繁体中文转换为简体中文
- **术语补丁**：自动修正港台特有词汇（计画→计划、網路→网络、软体→软件、程式→程序、列印→打印、位元組→字节、行销→营销、網誌/部落格→博客、連線→连接、伺服器→服务器、資訊→信息、硬碟→硬盘、記憶体→内存、螢幕→屏幕、滑鼠→鼠标、光碟→光盘、觸控→触控、鍵盤→键盘等）
- **标点符号清洗**：自动将繁体标点（「」『』、全形逗号句号等）转换为简体标点（""''、半形逗号句号等）
- **竖排转横排**：自动识别并修改 CSS 及 HTML 内联样式，将 `vertical-rl`、`vertical-lr`、`sideways-rl` 等竖排模式强制转换为 `horizontal-tb`
- **字体统一化**：自动替换 MingLiu、PMingLiu、標楷體、新細明體、DFKaiShu、BiauKai 等繁体专用字体为通用 serif，同时处理 CSS 文件和 HTML 内联样式中的 `font-family` 声明
- **Kindle 防 PDF 化清洗**：自动移除 `position: absolute/fixed`、`float`、`display: flex` 等会导致 Kindle 服务器（KindleGen）放弃重排并强制转为 PDF 的 CSS 属性，确保输出标准流式排版 EPUB
- **@font-face 字体声明清除**（v3.0 新增）：自动清除 CSS 中的 `@font-face` 声明块，防止亚马逊引擎因解析字体失败而拒绝发送或降级为 PDF
- **内嵌字体文件删除**（v3.0 新增）：自动删除 EPUB 中的 `.ttf`、`.otf`、`.woff`、`.woff2` 字体文件，彻底消除字体兼容性风险
- **OPF 固定布局声明清除**（v3.0 新增）：移除 `rendition:layout`、`rendition:spread`、`rendition:orientation` 等元数据，防止亚马逊判定为固定排版并降级为 PDF
- **display:none 隐藏内容清除**（v3.0 新增）：移除 CSS 中的 `display:none` 声明，防止 Amazon 因隐藏内容超限（>10000字符）而降级转换
- **data-amznremoved 属性清除**（v3.0 新增）：清理 XHTML/HTML 中的 `data-amznremoved` 残留属性
- **body id 属性清理**（v3.0 新增）：移除 `<body>` 标签上的 `id` 属性，避免部分阅读器解析异常
- **OPF language 元数据修复**（v3.0 新增）：确保 `dc:language` 正确设置为 `zh`
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

脚本执行时按以下顺序处理（共 16 步）：

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
| 9 | **@font-face 清除** | 清除 CSS 中的字体声明块（防止 Kindle 拒绝发送/转 PDF） |
| 10 | **字体文件删除** | 删除 .ttf/.otf/.woff/.woff2 内嵌字体文件 |
| 11 | **OPF 固定布局清除** | 移除 rendition:layout 等固定排版声明 |
| 12 | **display:none 清除** | 移除隐藏内容声明（防止 Amazon 降级转换） |
| 13 | **data-amznremoved 清除** | 清理 XHTML/HTML 残留属性 |
| 14 | **body id 清理** | 移除 body 标签 id 属性 |
| 15 | **OPF language 修复** | 确保 dc:language 正确设置为 zh |
| 16 | 图片压缩 | 压缩图片减小体积（可选） |

## 为什么 Kindle 会变 PDF？

亚马逊的转换引擎（KindleGen）非常老旧。如果 EPUB 中包含以下任一情况，引擎会认为无法进行文字重排，从而直接将每一页渲染成图片（即 PDF 模式）或直接拒绝发送：

1. **复杂 CSS 定位**：`position: absolute`、`position: fixed`、`float`、`display: flex`
2. **@font-face 字体声明**：指向系统字体或外部链接的字体声明，引擎解析失败
3. **内嵌字体文件**：.ttf/.otf/.woff 等字体文件兼容性差
4. **固定布局声明**：OPF 中的 `rendition:layout pre-paginated` 元数据
5. **大量隐藏内容**：`display:none` 隐藏的字符超过 10000 个

本脚本通过 **步骤 8-15（共 8 项 Kindle 深度清洗）**，在打包前逐一清除上述所有"危险"元素，确保 Kindle 将其识别为标准的流式排版书籍，彻底杜绝转 PDF 或发送失败的问题。

## 文件结构

- `install.sh` — 安装脚本，负责配置源、安装依赖、写入主程序
- `cc.sh` — 核心转换逻辑（16 步深度处理流程）
- `README.md` — 项目说明文档

## 注意事项

1. **存储权限**：首次运行 Termux 请务必执行 `termux-setup-storage` 并允许存储权限
2. **输出目录**：转换后的文件将保存在 `~/storage/downloads/E-book/` 目录下
3. **备份机制**：脚本不会修改原文件，而是生成 `-cc.epub` 后缀的新文件；开启 `EPUB_BACKUP=on` 后还会生成 `.bak` 备份
4. **Kindle 兼容**：输出标准 EPUB 格式，内置 16 步深度清洗（含 @font-face 清除、字体文件删除、OPF 固定布局清除等）。推送至 Kindle 后应正常显示为可重排电子书
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

### 转换后 Kindle 仍然变 PDF 或发送失败

```bash
# 方法1：确认步骤 9-15 均已执行（输出中应看到对应完成信息）
# 方法2：确认推送方式为 Send to Kindle 网页版或邮箱推送，不要 USB 直拷
# 方法3：用 Calibre 中转转换（Calibre → 转换 → AZW3/KFX）
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

### v3.0（当前版本）

- **新增** @font-face 字体声明清除（步骤 9），使用 perl 跨行正则精确切除整个代码块
- **新增** 内嵌字体文件删除（步骤 10），自动移除 .ttf/.otf/.woff/.woff2 文件
- **新增** OPF 固定布局声明清除（步骤 11），移除 rendition:layout/spread/orientation
- **新增** display:none 隐藏内容清除（步骤 12），防止 Amazon 因隐藏内容超限降级
- **新增** data-amznremoved 属性清除（步骤 13）
- **新增** body id 属性清理（步骤 14）
- **新增** OPF language 元数据修复（步骤 15），确保 dc:language 为 zh
- 转换流程从 9 步扩展为 16 步，全面覆盖 Kindle 兼容性风险点
- 打包验证增强：输出时自动显示文件大小，便于排查异常
- 安装脚本步骤提示从 6 步更新为 7 步（新增字体文件清理步骤说明）

### v2.0

- 新增 Kindle 深度清洗（步骤 8），自动移除 position:absolute/fixed、float、display:flex 等 CSS 属性
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
