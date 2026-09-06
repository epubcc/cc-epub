# CC-EPUB

在 Android 手机的 Termux 环境中，一键将港台繁体 EPUB 电子书转换为**简体中文 + 横排 + 首行缩进**的标准格式，并针对 **Kindle** 阅读进行了深度优化。

**版本**: v6.0 | **许可证**: MIT

## 功能特性

- **精准繁简转换**：基于 OpenCC 词库，智能处理"軟體→软件"、"滑鼠→鼠标"等地区用语差异，支持台湾（tw2s）、香港（hk2s）、通用（t2s）三种转换模式。
- **竖排转横排**：自动识别并清除 `writing-mode: vertical-rl` 等竖排样式，统一改为横排。
- **自动首行缩进**：为没有缩进的段落自动注入 `text-indent: 2em` 样式，符合中文阅读习惯。
- **Kindle 深度优化**：移除内嵌字体、强制 ltr 翻页、清理冲突 CSS、修复 NCX 导航。
- **多设备支持（v6.0）**：新增 `--device` 参数，支持 Kobo / Nook 等设备专属优化。
- **智能图片压缩**：书籍体积超过 150MB 时自动压缩内嵌图片。
- **一键部署**：提供自动化安装脚本，轻松配置 Termux 环境。
- **批量 / 并行处理**：一次命令处理整个目录，支持多任务并发。
- **断点续转**：批量中途中断后可从断点继续，不重复处理已完成文件。
- **Dry Run / 调试 / 静默模式**：`--dry-run`（支持 `--json`）、`--verbose`、`--quiet`。
- **DRM 检测、备份恢复、日志记录、目录重建、预设配置、SHA256 校验**。

## 技术原理

```
EPUB(ZIP)
  └─ 解压
      └─ 遍历所有文本文件 (xhtml, html, opf, ncx, css)
          ├─ 跳过二进制文件（图片、字体等）
          ├─ 编码转换（可选，处理非 UTF8 文件）
          ├─ OpenCC (tw2s/hk2s/t2s) 进行繁简转换
          ├─ Python 脚本精准修改 CSS：横排 + 首行缩进 + 设备兼容
          ├─ 修复 OPF 元数据 (dc:language -> zh-CN)
          └─ 修复 NCX 导航目录
      └─ 重新打包 (确保 mimetype 文件首位无压缩)
          └─ 生成简体横排 EPUB
```

## 快速开始

### 1. 安装 Termux

请务必从 **F-Droid** 商店下载安装 Termux，Google Play 版本已停止维护。

### 2. 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)
```

### 3. 验证安装

```bash
cc-epub --help
opencc --version
```

## 依赖与运行环境

### Termux 必需依赖

| 包名（Termux） | 命令 | 用途 | 必需 |
|---|---|---|---|
| `libopencc` | `opencc` | 繁简转换核心（**注意包名是 libopencc，不是 opencc**） | ✅ |
| `unzip` / `zip` | `unzip`, `zip` | EPUB 解包/打包（EPUB 本质是 ZIP） | ✅ |
| `python` | `python3` | CSS/HTML 排版调整脚本 | ✅ |
| `git` | `git` | 可选，用于克隆仓库 | ⭕ |
| `imagemagick` | `magick` | 可选，仅 >150MB 大书压缩图片时使用 | ⭕ |

### 一键安装依赖

```bash
pkg update -y && pkg upgrade -y
pkg install -y unzip zip libopencc python3 imagemagick git curl
```

### 完整搭建步骤（首次使用）

```bash
# 1. 从 F-Droid 安装 Termux（勿用 Play 版，已停更且存储权限有坑）
# 2. 授权访问手机存储（必须，否则 Download/ 不可见）
termux-setup-storage

# 3. 安装依赖（见上）
pkg install -y unzip zip libopencc python3 imagemagick git curl

# 4. （推荐）克隆仓库后本地安装，或一键在线安装
bash <(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)

# 5. 验证
cc-epub --help

# 6. 转换单本书
cc-epub /sdcard/Download/三体.epub
# 产物默认输出到 ~/storage/downloads/E-book/三体-cc.epub
```

> **关键提醒**：`termux-setup-storage` 只需运行一次，之后 `~/storage/downloads/` 即映射到手机「Download」。
> 若文件放其它位置，可用 `termux-open 三体-cc.epub` 直接分享到微信或文件管理器。

### 发送到 Kindle

- 网页端 [sendto.kindle.com](https://sendto.kindle.com)：单文件上限 **200MB**，EPUB 在支持格式内 ✅
- 转换后文件名形如 `三体-cc.epub`（原始名 + `-cc` 后缀），直接拖入即可。

## 使用方法

### 基本用法

```bash
# 基本转换（台湾繁体→简体，默认）
cc-epub /sdcard/Download/三体.epub

# 香港繁体→简体
cc-epub /sdcard/Download/明報版三體.epub --mode hk2s

# 指定输出设备（Kobo / Nook / Kindle）
cc-epub /sdcard/Download/三体.epub --device kobo

# 批量并行处理
cc-epub --batch /sdcard/Download/書庫 --parallel 3

# 断点续转
cc-epub --batch /sdcard/Download/書庫 --resume

# 仅检查（JSON 输出）
cc-epub /sdcard/Download/三体.epub --dry-run --json
```

更多参数见 `cc-epub --help`。

## 项目结构

```
cc-epub/
├── cc-epub.sh            # 主转换脚本（入口）
├── install.sh            # 一键安装/管理脚本
├── pack.sh               # 打包脚本（生成 cc-epub.zip）
├── final_verify.sh       # 最终端到端验证脚本
├── lib/                  # 模块化库
│   ├── common.sh         #   颜色/日志/工具函数/OpenCC 检测
│   ├── args.sh           #   参数解析
│   ├── convert.sh        #   核心单文件转换 + Dry Run (JSON)
│   └── batch.sh          #   批量/并行处理 + 交互式菜单
├── tests/                # 测试套件（20 项，全部通过）
├── scripts/              # 辅助脚本（SHA256 生成）
├── .github/workflows/    # CI 配置（test.yml）
├── LICENSE               # MIT 许可证（发布必需）
├── README.md / GUIDE.md  # 说明文档
├── CHANGELOG.md
├── CONTRIBUTING.md
└── SHA256SUMS
```

## 推送到 Kindle

1. 访问 [sendto.kindle.com](https://sendto.kindle.com)，登录亚马逊账号。
2. 上传转换生成的 `-cc.epub` 文件。
3. Kindle 连接 Wi-Fi 同步即可。

> 注意：源文件须为 **DRM-Free**；单文件建议 **< 200MB**；源文件编码为 **UTF-8**。

## 许可证

MIT License

## 致谢

- [OpenCC](https://github.com/BYVoid/OpenCC) — 开放中文转换
- [Termux](https://termux.com/) — Android 终端模拟器
