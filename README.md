# cc-epub

**EPUB 繁简通 Pro** — 在 Termux 上运行的 EPUB 繁体中文转简体中文工具，支持排版标准化与 Kindle 优化。

## 功能特性

- **繁简转换**：基于 [OpenCC](https://github.com/BYVoid/OpenCC) 实现高质量的繁体转简体
- **竖排转横排**：自动检测并转换 CSS/HTML 中的竖排排版属性
- **智能缩进**：利用 BeautifulSoup 分析文本结构，自动为正文段落添加首行缩进
- **字体统一**：统一字体为衬线体（serif），兼容 Kindle 渲染
- **排版标准化**：自动注入标准 CSS（行高、对齐、标题样式等）
- **Kindle 优化**：删除内嵌字体、修正语言标签、标准打包
- **全角空格清理**：清除段落首行的全角空格和 HTML 实体空格

## 环境要求

- **系统**：Android + Termux
- **依赖**：`opencc`、`unzip`、`zip`、`python3`、`beautifulsoup4`、`lxml`

## 快速部署

### 方式一：一键部署（推荐）

```bash
# 1. 下载部署脚本
wget https://raw.githubusercontent.com/epubcc/cc-epub/main/deploy.sh

# 2. 运行部署
bash deploy.sh
```

部署完成后，`deploy.sh` 会自动：
- 检查并安装所需依赖
- 将 `conv.sh` 写入 `~/conv.sh`
- 添加 `alias cc='~/conv.sh'` 到 `.bashrc`

### 方式二：手动部署

```bash
# 1. 下载 conv.sh
wget https://raw.githubusercontent.com/epubcc/cc-epub/main/conv.sh

# 2. 移动到主目录并赋予执行权限
mv conv.sh ~/conv.sh
chmod +x ~/conv.sh

# 3. 添加别名
echo "alias cc='~/conv.sh'" >> ~/.bashrc
source ~/.bashrc
```

## 使用方法

```bash
# 基本用法
cc 书名.epub

# 使用相对路径（默认在 Download 目录）
cc 三体.epub

# 使用绝对路径
cc /sdcard/Download/书名.epub

# 使用 ~ 路径
cc ~/Download/书名.epub
```

处理完成后，转换后的文件会自动保存到 `~/storage/downloads/E-book/` 目录，文件名为 `原文件名-简中.epub`。

## 推送至 Kindle

转换完成后，可通过以下方式推送到 Kindle：

1. **Send to Kindle 网页版**：访问 [amazon.com/sendtokindle](https://www.amazon.com/sendtokindle)，上传生成的 `.epub` 文件
2. **邮箱推送**：将文件作为附件发送到你的 Kindle 邮箱地址

## 依赖安装（如自动安装失败）

```bash
pkg update && pkg upgrade -y
pkg install opencc unzip zip python3 -y
pip install beautifulsoup4 lxml
```

## 文件说明

| 文件 | 说明 |
|------|------|
| `conv.sh` | 核心转换脚本，执行繁简转换、排版标准化、打包 |
| `deploy.sh` | 一键部署脚本，自动配置环境和别名 |
| `README.md` | 项目说明文档 |

## 技术栈

- **Shell**：Bash（文件操作、流程控制）
- **Python**：BeautifulSoup（HTML 结构分析、智能缩进）
- **外部工具**：OpenCC（繁简转换）、zip/unzip（打包）

## 开源许可

本项目基于 [OpenCC](https://github.com/BYVoid/OpenCC) 构建，遵循 Apache 2.0 许可证。

## 注意事项

1. **签名一致性**：Termux 主应用与插件必须来自同一渠道（F-Droid 或 GitHub）
2. **后台保活**：Android 系统锁屏后可能杀掉后台进程，需执行 `termux-wake-lock` 并关闭电池优化
3. **文件大小**：Send to Kindle 单文件上限 200MB，过大的 EPUB 需先压缩图片
4. **EPUB 兼容性**：部分复杂 EPUB（如含大量内嵌字体、特殊 CSS 属性）可能需要手动处理
