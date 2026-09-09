# cc-epub — 港台繁体 EPUB 转简体横排工具

> 针对 **Kindle Paperwhite Signature Edition（第 12 代）** + **Send to Kindle** 的繁→简 EPUB 自动化转换方案。
>
> 运行环境：**OPPO Find X8s** + **Termux 0.119.0-beta.3**（F-Droid 2.0-rc1 下载）

---

## 📌 功能特性

- **繁 → 简**：使用 OpenCC 1.4.2（`libopencc` + `opencc-tools`），支持港澳台用词差异
- **横排**：自动将竖排（`writing-mode: vertical-*`）改写为横排，并调整标点位置
- **完美保留**：原始排版、插图、目录结构、CSS 样式、字体设置、章节分隔完整保留
- **字体统一**：清除 EPUB 内嵌的特殊繁中字体，改为调用 **Kindle 自带字体**（避免白页/渲染失败）
- **自动输出**：文件名追加 `-简中`，自动存入 `~/storage/downloads/E-book/`
- **命令格式**：`cc 书名`（一键完成全部流程）

---

## ⚠️ 兼容说明（Kindle 原生 EPUB）

- Send to Kindle 推送时，**会自动将 EPUB 转换为 KFX 格式**再推送到设备。
- 若原 EPUB **排版复杂**（特殊繁中字体、复杂 CSS、大量内嵌图），转换可能失败 → 正文白页或文件过大卡顿。
- 本工具通过**清除特殊字体、规范化 CSS、统一编码**来最大化 KFX 转换成功率。

---

## 🚀 快速开始

### 1. 环境搭建（Termux）

依次复制粘贴以下命令：

```bash
# ① 更新仓库并安装依赖
pkg update -y && pkg upgrade -y
pkg install -y libopencc opencc-tools zip unzip python

# ② 授予存储权限（必须，否则无法读写 Download/E-book）
termux-setup-storage

# ③ 创建输出目录
mkdir -p ~/storage/downloads/E-book
```

### 2. 部署脚本

```bash
# ① 克隆仓库
cd ~
git clone https://github.com/epubcc/cc-epub.git

# ② 赋予执行权限
chmod +x ~/cc-epub/scripts/*.sh

# ③ 运行安装脚本（自动配置 PATH、命令别名、字体规范）
~/cc-epub/scripts/install.sh
```

### 3. 使用

将繁体 EPUB 放入 `~/storage/downloads/`（Downloads 目录），然后：

```bash
cc 书名           # 书名不含 .epub 后缀，如：cc 我的第一本书
cc 书名 --keep-font  # 保留原字体（不推荐，可能白页）
```

转换完成后，简体横排文件位于：`~/storage/downloads/E-book/书名-简中.epub`

再通过 **Send to Kindle 网页版** 上传推送即可。

---

## 📁 项目结构

```
cc-epub/
├── README.md              # 本文件
├── LICENSE                # MIT 开源协议
├── .gitignore
├── scripts/
│   ├── install.sh         # 一键部署脚本（配置 PATH + 别名 + 字体）
│   ├── cc.sh              # 核心命令：`cc 书名`
│   ├── convert.py         # Python 转换主逻辑（繁简/横排/字体/清理）
│   └── uninstall.sh       # 卸载清理脚本
├── config/
│   ├── opencc-chain.json  # OpenCC 转换链配置（tw → s / hk → s）
│   └── kindle-css.css     # Kindle 兼容的标准化 CSS 模板
└── examples/
    └── usage.md           # 完整使用示例与 FAQ
```

---

## 🔧 技术细节

| 项目 | 说明 |
|------|------|
| 繁简转换 | OpenCC `t2s.json`（台湾/香港 → 大陆简体） |
| 横排处理 | 解析 CSS `writing-mode`，改写为 `horizontal-tb`，调整标点 |
| 字体处理 | 移除 `@font-face` 内嵌繁中字体，改用 `font-family: serif`（Kindle 自带） |
| 编码规范 | 统一 UTF-8 无 BOM，确保 KFX 转换稳定 |
| 文件校验 | 转换前后校验 EPUB 完整性（ZIP 结构 + OPF 声明） |

---

## 📄 License

MIT © 2026 epubcc
