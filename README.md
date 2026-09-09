# cc-epub — 港台繁体 EPUB 转换工具

Termux 端的 EPUB 繁简转换 + 排版重置工具，专为港台竖排 EPUB 优化，兼容 Kindle KFX 格式。

> **输出文件名**：`书名-简中.epub`（书名取自 EPUB 内部 OPF `<dc:title>`，自动繁转简）

---

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| **繁体→简体** | OpenCC `tw2sp.json`（含台湾短语/词汇转换），正文/书名/作者/目录/元数据全覆盖 |
| **竖排→横排** | 自动修正 `writing-mode`、`<body>`/`<html>` 内联样式、OPF 阅读方向 |
| **首行缩进 2em** | 严格处理顺序：**清除段首全角空格 → 检测方向 → 竖转横 → 确认 2em**，杜绝 4em 叠加 |
| **标点规范化** | 「」→""、『』→''、﹐→，、﹒→。、破折号/省略号/间隔号统一 |
| **字体统一** | 清除 `@font-face` 与所有 `font-family`，调用 Kindle 自带字体 |
| **字号统一** | 清除所有 `font-size`，统一 `1em`，Kindle 内可自由调节 |
| **保留排版** | 插图、目录、章节结构、CSS 完整保留，仅清除与排版冲突的项 |

## 🎯 解决的核心痛点

港台繁体竖排书转简体后，**首行缩进变成 4em**（视觉四个字符宽度），成因：
1. 竖排转横排时 CSS 清理不彻底
2. CSS 追加逻辑与残留值叠加
3. 全角空格残留 + 清除逻辑顺序问题
4. 角标/符号影响

**本工具处理顺序**（关键）：先清段首全角空格 → 再检测方向 → 竖转横 → 最后用 `!important` 强制 2em，从根源避免叠加。

## 📦 依赖

| 包 | 用途 |
|----|------|
| `python` | 运行脚本 |
| `libopencc` + `opencc-tools` | **OpenCC 核心库与命令行**（Termux 无 "Open CC" 包，务必用这两个） |
| `beautifulsoup4` | HTML 解析 |
| `zip` / `unzip` | EPUB 解压打包 |

## 🚀 快速开始

详见 **[QUICKSTART.md](QUICKSTART.md)**（可复制粘贴的一键/手动命令）。

```bash
# 一键部署
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"

# 使用
cc 原子习惯.epub
# → ~/storage/shared/Download/E-book/原子习惯：细微改变带来巨大成效-简中.epub
```

## 📝 用法

```
cc <书名.epub>               输出: 书名-简中.epub（书名取自 OPF <dc:title>）
cc <书本路径>
cc -o <输出.epub> <输入.epub>   指定输出路径
```

## 🔧 配置

- 香港繁体书籍：把 `cc.py` 里 `OPENCC_CONFIG = "tw2sp.json"` 改为 `hk2sp.json`
- 输出目录：`OUT_DIR`，默认 `~/storage/shared/Download/E-book`

## ⚠️ 兼容性

- 支持标准 EPUB 2.0/3.0
- 对 **DRM 加密**的 EPUB 无效
- 通过 Send to Kindle 推送自动转 KFX；Kindle PWSE 第12代文件大小限制 **≤ 200 MB**
- 极少数排版极端复杂的 EPUB 可能转换失败（白页），可提 Issue

## 📄 License

MIT
