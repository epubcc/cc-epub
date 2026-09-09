# cc-epub

> 港台繁体 EPUB 转换工具：繁→简 · 竖排→横排 · 首行缩进 2em
> 针对 **Kindle Paperwhite Signature Edition（第12代）** + **Send to Kindle（EPUB → KFX）** 优化

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)
[![Python](https://img.shields.io/badge/python-%3E%3D3.8-blue)](./pyproject.toml)
[![Termux](https://img.shields.io/badge/platform-Termux-brightgreen)](https://termux.com)
[![CI](https://github.com/epubcc/cc-epub/actions/workflows/ci.yml/badge.svg)](https://github.com/epubcc/cc-epub/actions)

在 Termux 中将港台繁体、竖排 EPUB 一键转为**简体横排**，并完美保留原始排版、插图、目录结构、章节分隔；统一首行缩进 2em，避免「竖排转横排后缩进变成 4em」的经典痛点。

---

## ✨ 功能特性

| 功能 | 说明 |
|------|------|
| **繁→简** | OpenCC `tw2sp.json`（台湾短语级，最彻底），香港书可切 `hk2sp.json` |
| **竖→横** | 自动检测 `writing-mode: vertical-rl`，强制横排 + 标点位置自适应 |
| **缩进 2em** | 先清除全角空格，再由 CSS 统一 `text-indent: 2em`，**彻底杜绝 4em 叠加** |
| **保留结构** | 插图、目录、章节分隔、CSS 布局完整保留，仅清理与排版冲突项 |
| **KFX 兼容** | 清除自定义字体嵌入 `@font-face`，调用 Kindle 自带字体，避免白页/卡顿 |
| **批量处理** | 支持单本 / 整目录批量 / `--dry-run` 预检测 |

---

## 🚀 一键部署（推荐）

在 Termux 中**复制粘贴一行命令**即可完成环境搭建 + 部署：

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"
```

脚本会自动：换清华镜像源 → 装依赖 → 配 `cc` 快捷命令。

---

## 📋 手动部署（分步，方便对照复制）

> 环境：OPPO Find X8s · F-Droid 2.0-rc1 · Termux 0.118.3

```bash
# 1. 换国内镜像源（强烈推荐，否则下载极慢）
termux-change-repo
#   弹出界面选择 "Mirrors in Chinese Mainland" → "Tsinghua（清华源）"

# 2. 更新软件包
pkg update && pkg upgrade -y

# 3. 授予存储权限（访问手机 Download 目录）
termux-setup-storage
#   弹出对话框点击"允许"

# 4. 安装系统依赖
#   ⚠️ 注意：Termux 官方仓库没有 "opencc" 包，正确包名是 libopencc + opencc-tools
pkg install -y python git zip unzip libopencc opencc-tools

# 5. 安装 Python 库（走清华 PyPI 镜像，避免超时）
pip install --index-url https://pypi.tuna.tsinghua.edu.cn/simple beautifulsoup4

# 6. 克隆仓库
git clone https://github.com/epubcc/cc-epub.git ~/cc-epub
cd ~/cc-epub

# 7. 运行部署脚本
bash install.sh

# 8.（可选）保持后台运行，防止息屏被杀进程
termux-wake-lock
```

### 验证安装

```bash
type cc              # 应显示 ~/bin/cc
cc --version         # 显示 cc-epub v3.0.0
opencc --version     # 显示 OpenCC 版本
```

> 若提示 `command not found: cc`，请重启 Termux 或执行 `source ~/.bashrc`。

---

## 📖 使用方法

```bash
# 单本转换（需求第5、6条：输出 书名-简中.epub）
cc 书名.epub

# 指定自定义输出路径
cc 书名.epub -o ~/Downloads/输出.epub

# 仅检测排版方向（不实际转换，先看是不是竖排）
cc 书名.epub --dry-run

# 批量转换整个目录
cc ~/storage/shared/Download/ --batch
```

### 输出路径

```
~/storage/shared/Download/E-book/书名-简中.epub
```

### 推送到 Kindle

1. 打开 [Send to Kindle 网页版](https://www.amazon.com/sendtokindle)
2. 上传 `*-简中.epub`（**≤ 200 MB**，PWSE 第12代限制）
3. Amazon 自动转为 KFX 格式推送到设备

---

## 🔧 技术实现

### 转换流程（严格按需求第7条）

```
① 清除段落前的全角空格（杜绝 4em 叠加）
        ↓
② 检测排版方向（writing-mode: vertical-rl / -epub-writing-mode）
        ↓
③ 竖排 → 横排（含标点位置自动调整）
        ↓
④ 横排文件 → 确认首行缩进为 2em
        ↓
⑤ 繁体 → 简体（OpenCC，批量合并调用提升性能）
        ↓
⑥ 标点规范化（直角引号、小逗号小句号、破折号、省略号…）
        ↓
⑦ 完美保留：插图 / 目录 / 章节分隔 / CSS 布局
```

### 核心痛点解决

| 痛点 | 原因 | 解决方案 |
|------|------|---------|
| **缩进 4em** | 全角空格 + CSS 缩进叠加 | 先清文本空格，再用 `!important` 覆盖 CSS |
| 字体不统一 | 原书嵌入繁体中文字体 | 清除 `@font-face`，调用 Kindle 自带字体 |
| KFX 白页 | 复杂 CSS3 属性不兼容 | 清理冲突 CSS，统一 `horizontal-tb` |
| 引号仍是直角「」 | 旧版未做标点规范化 | `normalize_punctuation()` 统一处理 |
| 目录/书名仍是繁体 | 旧版未处理 OPF/NCX | 新增 `process_opf()` / `process_ncx()` |

### 标点转换对照表

| 港台原书 | 大陆规范 | 说明 |
|---------|---------|------|
| 「文字」 | "文字" | 直角双引号 → 弯引号 |
| 『文字』 | '文字' | 直角单引号 → 弯引号 |
| ﹐ | ， | **小逗号（已补上，旧版遗漏）** |
| ﹒ | 。 | **小句号（已补上，旧版遗漏）** |
| — 或 ── | —— | 统一双 em dash |
| … 或 ... | …… | 统一双省略号 |
| ． | · | 全角句点 → 中间点 |
| ﹝﹞ ﹙﹚ | () | 特殊括号 → 标准括号 |

---

## 🧪 本地开发 / 测试

```bash
# 安装开发依赖
pip install -e ".[dev]"

# 运行测试套件（30+ 用例，含端到端）
pytest -v

# 生成测试样本 + 手动端到端验证
python make_sample.py
python cc.py sample_vertical.epub -o /tmp/out.epub
```

---

## 🔄 切换繁转简配置

```bash
# 默认台湾繁体（含短语转换，最彻底）
export CC_OPENCC_CONFIG=tw2sp.json

# 香港繁体书籍
export CC_OPENCC_CONFIG=hk2sp.json

# 通用逐字转换（兜底）
export CC_OPENCC_CONFIG=t2s.json
```

---

## ⚠️ 兼容性说明

- ✅ 标准 EPUB 2.0 / 3.0
- ✅ Send to Kindle → KFX（PWSE 第12代，文件 ≤ 200 MB）
- ❌ **DRM 加密的 EPUB 无法处理**（需先去除 DRM）
- 💡 转换失败/白页时：检查是否因大量内嵌图片或超复杂 CSS，可尝试拆分章节

---

## ❓ 故障排除

| 问题 | 解决方案 |
|------|---------|
| `cc` 被 clang 拦截 | `~/bin/cc` wrapper + PATH 前置 + alias 三保险，一般无需手动处理 |
| `command not found: cc` | `source ~/.bashrc` 或重启 Termux |
| `pkg update` 卡住 | 执行 `termux-change-repo` 切换清华源 |
| `pip install` 超时 | 加 `--index-url https://pypi.tuna.tsinghua.edu.cn/simple` |
| 找不到 `storage` 目录 | `termux-setup-storage` 并点"允许" |
| `opencc` 命令找不到 | 确认安装了 `libopencc` + `opencc-tools` 两个包 |
| `tw2sp.json` 未找到 | `pkg reinstall opencc-tools` |
| 转换后缩进仍是 4em | 先跑 `cc xxx --dry-run` 看检测，再提 Issue |
| 推送后白页 | 检查文件是否 > 200MB，或含大量图片/复杂 CSS |

---

## 🤝 贡献

欢迎 Issue / PR！请先阅读 [CONTRIBUTING](./CONTRIBUTING.md)（如有），并遵守 PR 模板的自查清单。

---

## 📄 License

MIT © [epubcc](https://github.com/epubcc)
