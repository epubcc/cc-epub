# cc-epub

**Termux 一键部署 · 港台 EPUB 繁转简 · 竖排转横排 · Kindle 深度适配**

一个运行在 Android Termux 环境下的 Shell 脚本工具，旨在解决港台 EPUB 电子书在 Kindle 或普通阅读器上阅读体验不佳的问题（繁体、竖排、字体错乱、标点混用）。

## 核心功能

- **繁简转换**：基于 OpenCC (tw2sp)，将台湾/香港繁体中文转换为简体中文
- **术语补丁**：自动修正港台特有词汇（计画→计划、网路→网络、软体→软件、程式→程序、列印→打印、位元组→字节、行销→营销、网志/部落格→博客、连线→连接、伺服器→服务器、资讯→信息、硬碟→硬盘、记忆体→内存、萤幕→屏幕、滑鼠→鼠标、光碟→光盘等）
- **标点符号清洗**：自动将繁体标点（「」『』、全形逗号句号等）转换为简体标点（""''、半形逗号句号等）
- **竖排转横排**：自动识别并修改 CSS 及 HTML 内联样式，将 `vertical-rl`、`vertical-lr`、`sideways-rl` 等竖排模式强制转换为 `horizontal-tb`
- **字体统一化**：自动替换 MingLiu、PMingLiu、標楷體、新細明體、DFKaiShu、BiauKai 等繁体专用字体为通用 serif，同时处理 CSS 文件和 HTML 内联样式中的 `font-family` 声明
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
| `cc --help` | 查看帮助信息 |

**示例：**

```bash
cc 三体
# 如果找到多个文件，会提示输入编号选择

EPUB_BACKUP=on cc 三体
# 转换前自动备份原文件

EPUB_IMG=off cc 三体
# 画册模式，跳过图片压缩
```

## 环境变量

| 变量 | 说明 |
| :--- | :--- |
| `EPUB_BACKUP=on` | 转换前备份原文件（生成 .bak 副本） |
| `EPUB_IMG=off` | 跳过图片压缩（适用于画册/漫画类 EPUB） |

## 依赖说明

| 依赖 | 用途 | 是否必需 |
| :--- | :--- | :--- |
| `unzip` / `zip` | EPUB 解包与打包 | 必需 |
| `opencc-tools` | 繁简转换引擎（提供 opencc 命令） | 必需 |
| `imagemagick` | 图片压缩优化 | 可选（未安装时自动跳过） |

## 转换流程

脚本执行时按以下顺序处理（共 8 步）：

| 步骤 | 处理内容 | 说明 |
| :--- | :--- | :--- |
| 1 | 繁简转换 | opencc tw2sp 核心转换 |
| 2 | 术语补丁 | 港台特有词汇二次修正 |
| 3 | 标点符号清洗 | 繁体标点→简体标点 |
| 4 | 竖排转横排（CSS） | 处理 CSS 文件中的竖排模式 |
| 5 | 竖排转横排（HTML） | 处理 HTML 内联样式中的竖排模式 |
| 6 | 清理残留竖排标记 | 删除 writing-mode / text-orientation 残留 |
| 7 | 字体统一化 | 替换繁体专用字体（CSS + HTML 内联样式） |
| 8 | 图片压缩 | 压缩图片减小体积（可选） |

## 文件结构

- `install.sh` — 安装脚本，负责配置源、安装依赖、写入主程序
- `cc.sh` — 核心转换逻辑（解压、转换、排版修复、重打包）
- `README.md` — 项目说明文档

## 注意事项

1. **存储权限**：首次运行 Termux 请务必执行 `termux-setup-storage` 并允许存储权限
2. **输出目录**：转换后的文件将保存在 `~/storage/downloads/E-book/` 目录下
3. **备份机制**：脚本不会修改原文件，而是生成 `-cc.epub` 后缀的新文件；开启 `EPUB_BACKUP=on` 后还会生成 `.bak` 备份
4. **Kindle 兼容**：输出标准 EPUB 格式，修复字体引用，防止 Kindle 排版错乱。推送至 Kindle 后自动转为 KFX 格式

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
apt update
apt install -y unzip zip opencc-tools imagemagick

# 3. 配置别名
echo 'alias cc="cd ~/storage/downloads && ~/cc.sh"' >> ~/.bashrc
source ~/.bashrc
```

## 贡献

欢迎提交 Issue 和 Pull Request！

## 许可

MIT License
