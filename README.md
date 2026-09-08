# cc-epub

一个在 Termux 环境下运行的 EPUB 电子书处理工具，专为中文读者优化。它能一键将繁体竖排的 EPUB 电子书转换为简体横排，并进行智能排版，使其更适合在 Kindle 等设备上阅读。

## ✨ 功能特性

- **繁简转换**：基于强大的 `OpenCC` 引擎，将繁体中文精准转换为简体中文。
- **竖排转横排**：自动检测并转换书籍的 CSS 样式，将传统的竖排（`vertical-rl`）版式改为现代的横排（`horizontal-tb`）。
- **智能排版**：
  - **智能缩进**：使用 Python 脚本分析 HTML 结构，自动为正文段落添加首行缩进，同时避免对诗歌、引文等特殊段落进行错误处理。
  - **样式标准化**：注入一套干净、清晰的 CSS 样式，统一字体、行高和段落间距，提升阅读体验。
- **Kindle 优化**：
  - **字体兼容**：移除 EPUB 内嵌的字体文件，强制使用设备自带的衬线体，避免 Kindle 转换 KFX 格式时出现白页或排版错乱。
  - **元数据修正**：自动将书籍的语言标签从 `zh-Hant` 修正为 `zh-CN`。
- **一键部署**：提供简单的部署脚本，自动安装依赖并配置快捷命令。

## 🚀 快速开始

### 1. 环境准备

确保你已在 Android 设备上安装并配置好 Termux。

### 2. 安装与部署

在 Termux 中执行以下命令，即可自动完成所有安装和配置步骤：

```bash
wget https://raw.githubusercontent.com/epubcc/cc-epub/main/deploy.sh
bash deploy.sh
```

该脚本会自动：

- 安装 `unzip`、`zip`、`opencc`、`python` 等必要依赖
- 下载核心脚本 `conv.sh` 到你的主目录
- 配置 `cc` 命令别名，方便你随时调用

> **注意**：首次运行 `deploy.sh` 后，请重启 Termux 或执行 `source ~/.bashrc` 以使 `cc` 命令生效。

### 3. 使用方法

部署完成后，将你的 EPUB 文件放入手机的"下载"（Downloads）目录，然后在 Termux 中使用 `cc` 命令即可开始处理。

```bash
cc 你的书籍文件名.epub
```

**示例：**

```bash
cc san-ti.epub
```

处理完成的书籍会自动保存到 `~/storage/downloads/E-book/` 目录，文件名会自动添加 `-简中` 后缀。

## 🛠️ 技术栈

- **Bash**：负责整体流程控制、文件解压/打包和系统交互
- **OpenCC**：提供核心的繁体到简体中文转换功能
- **Python (BeautifulSoup4)**：用于精确解析和修改 HTML 内容，实现智能段落缩进等复杂排版逻辑
- **sed / zip / unzip**：用于高效的文本替换和文件处理

## 📄 许可证

本项目基于 Apache License 2.0 许可证开源。详情请参阅 [LICENSE](LICENSE) 文件。
