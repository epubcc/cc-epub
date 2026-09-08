# cc-epub

一个在 Termux 环境下运行的 EPUB 电子书处理工具，专为港台繁体中文电子书转换为简体横排而设计。

## ✨ 功能特性

- **清除全角空格**：自动清除港台EPUB段落前的全角空格（`　`），避免与缩进叠加
- **竖排标点转换**：自动将竖排专用标点（`︑︒︓︔︕︖` 等）转换为横排标点（`、。：；！？` 等）
- **排版方向检测**：自动检测原书是否为竖排，仅对竖排书籍进行转换，横排书籍保持不变
- **竖排转横排**：智能转换 CSS `writing-mode` 属性及内联样式
- **繁简转换**：基于 OpenCC 引擎，将繁体中文精准转换为简体中文
- **智能首行缩进**：使用 Python + BeautifulSoup 分析 HTML 结构，自动为正文段落添加 `2em` 首行缩进，同时排除诗歌、引文、图片等特殊情况
- **字体统一**：统一替换为 `serif` 字体族，移除内嵌字体文件，确保 Kindle 兼容性
- **元数据修正**：自动将 OPF 中的语言标签修正为 `zh-CN`
- **自动归档**：输出文件自动保存至 `~/storage/downloads/E-book/`

## 📋 系统要求

- Android 设备 + Termux
- 存储访问权限（`termux-setup-storage`）

## 🚀 快速部署

在 Termux 中执行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/deploy.sh -o ~/deploy.sh
bash ~/deploy.sh
```

部署完成后，**重启 Termux** 使 `cc` 命令生效。

## 💡 使用方法

```bash
cc 书名.epub
```

处理后的文件将保存在：`~/storage/downloads/E-book/书名_简中.epub`

## 🔧 工作流程

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 解压 | 将 EPUB 解压到临时目录 |
| 2 | 清除全角空格 | 清除段落前的全角空格 |
| 3 | 标点转换 | 竖排标点 → 横排标点 |
| 4 | 方向检测 | 检测是否为竖排 |
| 5 | 排版处理 | 竖排转横排 + 统一字体 + 移除内嵌字体 |
| 6 | 繁简转换 | OpenCC t2s 转换 |
| 7 | 智能排版 | Python 智能首行缩进 2em |
| 8 | 打包输出 | 重新打包 EPUB，保存至下载目录 |

## 📖 Kindle 兼容性说明

本工具针对 Kindle Send to Kindle（网页版）进行了优化：

- 移除所有内嵌字体（`.ttf`/`.otf`/`.woff`），使用 Kindle 原生衬线体
- 简化 CSS 样式，避免复杂选择器导致 KFX 转换失败
- 输出文件建议控制在 200MB 以内

## 📄 许可证

MIT License
