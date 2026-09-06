# CC-EPUB

在 Android 手机的 Termux 环境中，一键将港台繁体 EPUB 电子书转换为**简体中文 + 横排 + 首行缩进**的标准格式，并针对 **Kindle** 阅读进行了深度优化。

**版本**: v5.0 | **许可证**: MIT

## 功能特性

- **精准繁简转换**：基于 OpenCC 词库，智能处理"軟體→软件"、"滑鼠→鼠标"等地区用语差异，支持台湾（tw2s）、香港（hk2s）、通用（t2s）三种转换模式。
- **竖排转横排**：自动识别并清除 `writing-mode: vertical-rl` 等竖排样式，统一改为横排。
- **自动首行缩进**：为没有缩进的段落自动注入 `text-indent: 2em` 样式，符合中文阅读习惯。
- **Kindle 深度优化**：
  - 移除内嵌字体（`@font-face`），避免因字体不兼容导致的白页问题。
  - 强制设置 `page-progression-direction="ltr"`，确保从左到右翻页。
  - 清理 `display: none` 等可能导致转换失败的 CSS 属性。
  - 修复 NCX 导航目录中的异常 URL 片段引用。
- **智能图片压缩**：当书籍体积超过 150MB 时，自动压缩内嵌图片，防止文件过大导致 Kindle 卡顿。
- **一键部署**：提供自动化安装脚本，轻松配置 Termux 环境。
- **批量处理**：一次命令处理目录下所有 EPUB 文件。
- **并行处理**（v5.0 新增）：支持多任务并发，大幅提升批量处理速度。
- **断点续转**（v5.0 新增）：批量处理中途中断后，可从断点处继续，不重复处理已完成文件。
- **Dry Run 模式**：支持预览模式，仅检查不执行转换，方便排查问题。
- **详细调试模式**：`--verbose` 参数输出每一步的详细信息，便于定位问题。
- **静默模式**（v5.0 新增）：`--quiet` 参数仅输出错误和结果，适合脚本集成。
- **DRM 检测**：自动检测文件是否受 DRM 保护，避免无效转换。
- **备份与恢复**：自动备份原文件，支持一键恢复到原始版本。
- **日志记录**：支持将转换日志保存到文件，便于问题追踪。
- **目录重建**：支持重建 EPUB 导航目录（toc.ncx / nav.xhtml）。
- **预设配置**（v5.0 新增）：支持通过配置文件预设常用参数，避免每次手动指定。
- **SHA256 校验**（v5.0 新增）：安装脚本自动验证下载文件的完整性，防止文件被篡改。

## 技术原理

```
EPUB(ZIP)
  └─ 解压
      └─ 遍历所有文本文件 (xhtml, html, opf, ncx, css)
          ├─ 跳过二进制文件（图片、字体等）
          ├─ 编码转换（可选，处理非 UTF8 文件）
          ├─ OpenCC (tw2s/hk2s/t2s) 进行繁简转换
          ├─ Python 脚本精准修改 CSS：横排 + 首行缩进 + Kindle兼容
          ├─ 修复 OPF 元数据 (dc:language -> zh-CN)
          └─ 修复 NCX 导航目录
      └─ 重新打包 (确保 mimetype 文件首位无压缩)
          └─ 生成简体横排 EPUB
```

## 快速开始

### 1. 安装 Termux

请务必从 **F-Droid** 商店下载安装 Termux，Google Play 版本已停止维护。

### 2. 一键安装

打开 Termux，粘贴并执行以下命令：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)
```

该脚本会自动完成以下操作：

1. 请求存储权限。
2. 更换为清华大学 TUNA 镜像源。
3. 安装 `unzip`、`zip`、`opencc`、`python3`、`imagemagick` 等必要依赖。
4. 下载并配置 `cc-epub` 全局命令。
5. 验证所有依赖是否就绪。
6. 校验下载脚本的 SHA256 完整性（v5.0 新增）。

### 3. 验证安装

```bash
cc-epub --help
# 或
opencc --version
```

## 使用方法

### 基本用法

1. 将需要转换的繁体 EPUB 文件放入手机的 `Download` 目录。
2. 在 Termux 中执行转换命令：

```bash
cc-epub /sdcard/Download/你的书名.epub
```

3. 转换完成后，简体横排版书籍将保存在 `Download/E-book/你的书名-cc.epub`。

### 批量处理

将多个 EPUB 文件放在同一个目录下，使用 `--batch` 参数一次性全部转换：

```bash
# 串行批量处理
cc-epub --batch /sdcard/Download/书籍文件夹

# 并行批量处理（3 个并发任务，v5.0 新增）
cc-epub --batch /sdcard/Download/书籍文件夹 --parallel 3

# 仅处理匹配特定模式的文件
cc-epub --batch /sdcard/Download/书籍文件夹 --include "小说*"

# 排除特定文件
cc-epub --batch /sdcard/Download/书籍文件夹 --exclude "*.jpg"

# 跳过已存在的输出文件
cc-epub --batch /sdcard/Download/书籍文件夹 --skip-existing

# 断点续转（v5.0 新增）
cc-epub --batch /sdcard/Download/书籍文件夹 --resume
```

### 从备份恢复

转换时原文件会自动备份到 `Download/E-book/.backup/` 目录。如需恢复：

```bash
cc-epub --restore /sdcard/Download/E-book/.backup/三体.epub.backup
```

### 使用预设配置（v5.0 新增）

创建配置文件 `~/.cc-epub/config`（YAML 格式）：

```
mode=hk2s
add_indent=1
force_horizontal=1
compress_images=0
kindle_opt=1
encoding=utf-8
timeout=600
retry=2
```

然后使用 `--config` 参数加载：

```bash
cc-epub /sdcard/Download/明報版三體.epub --config ~/.cc-epub/config
```

### 可选参数

| 参数 | 作用 |
| :--- | :--- |
| `--mode <tw2s\|hk2s\|t2s>` | 选择转换模式（默认: tw2s 台湾繁体→简体） |
| `--no-indent` | 不添加首行缩进 |
| `--keep-vertical` | 保留书籍原始的竖排格式 |
| `--no-compress` | 不压缩图片 |
| `--no-kindle-opt` | 不执行 Kindle 兼容性优化 |
| `--dry-run` | 仅检查文件结构，不执行实际转换 |
| `--verbose` | 详细输出模式，显示每一步的处理详情 |
| `--quiet` | 静默模式，仅输出错误和结果（v5.0 新增） |
| `--output <路径>` | 指定输出目录（默认: Download/E-book） |
| `--output-prefix <前缀>` | 自定义输出文件名前缀（v5.0 新增） |
| `--output-suffix <后缀>` | 自定义输出文件名后缀（默认: -cc）（v5.0 新增） |
| `--stats` | 显示转换统计信息（v5.0 新增） |
| `--batch <目录>` | 批量处理目录下所有 EPUB 文件 |
| `--parallel <N>` | 并行处理，N 个并发任务（v5.0 新增） |
| `--resume` | 断点续转，从上次中断处继续（v5.0 新增） |
| `--exclude <模式>` | 批量时排除匹配文件（v5.0 新增） |
| `--include <模式>` | 批量时仅处理匹配文件（v5.0 新增） |
| `--skip-existing` | 跳过已存在的输出文件（v5.0 新增） |
| `--encoding <编码>` | 指定输入文件编码（默认: utf-8）（v5.0 新增） |
| `--timeout <秒>` | 单个文件处理超时时间（默认: 300）（v5.0 新增） |
| `--retry <次数>` | 失败重试次数（默认: 0）（v5.0 新增） |
| `--restore <备份文件>` | 从备份恢复原始 EPUB 文件 |
| `--check-drm` | 检查文件是否有 DRM 保护 |
| `--log <文件>` | 将转换日志保存到指定文件 |
| `--toc` | 重建导航目录（toc.ncx / nav.xhtml） |
| `--config <文件>` | 加载预设配置文件（v5.0 新增） |

### 使用示例

```bash
# 基本转换（台湾繁体→简体，默认）
cc-epub /sdcard/Download/三体.epub

# 香港繁体→简体
cc-epub /sdcard/Download/明報版三體.epub --mode hk2s

# 保留竖排 + 不添加首行缩进
cc-epub /sdcard/Download/直排書籍.epub --keep-vertical --no-indent

# 仅检查文件结构
cc-epub /sdcard/Download/大文件.epub --dry-run

# 详细调试模式
cc-epub /sdcard/Download/問題書籍.epub --verbose

# 指定自定义输出目录和前缀
cc-epub /sdcard/Download/三體.epub --output /sdcard/Download/轉換結果 --output-prefix "converted-"

# 显示转换统计
cc-epub /sdcard/Download/三體.epub --stats

# 批量处理整个目录（3 个并行任务）
cc-epub --batch /sdcard/Download/我的書庫 --parallel 3

# 批量处理时排除图片文件
cc-epub --batch /sdcard/Download/我的書庫 --exclude "*.jpg" --exclude "*.png"

# 检查 DRM 保护
cc-epub /sdcard/Download/可疑書籍.epub --check-drm

# 保存转换日志
cc-epub /sdcard/Download/三體.epub --log /sdcard/Download/convert.log

# 重建目录后转换
cc-epub /sdcard/Download/三體.epub --toc

# 处理 Big5 编码的旧书
cc-epub /sdcard/Download/舊書.epub --encoding big5

# 失败重试 3 次
cc-epub /sdcard/Download/不穩定書籍.epub --retry 3

# 静默模式（适合脚本集成）
cc-epub /sdcard/Download/批量書籍.epub --quiet
```

## 推送到 Kindle

1. 访问亚马逊官方推送网站：[sendto.kindle.com](https://sendto.kindle.com)
2. 登录你的亚马逊账号。
3. 将转换生成的 `-cc.epub` 文件拖拽上传。
4. 在 Kindle 设备上连接 Wi-Fi 同步，即可看到新书。

> **注意**
> - 源文件必须是 **DRM-Free**（无数字版权保护）的 EPUB。
> - 为保证推送成功，单个文件大小建议 **小于 200MB**。
> - 确保源 EPUB 文件编码为 UTF-8。

## 常见问题排查

| 现象 | 可能原因与解决方案 |
| :--- | :--- |
| **推送后显示白页** | 书籍排版过于复杂。本脚本已做兼容性优化，若仍失败，可尝试用 Calibre 软件先进行一次"EPUB 到 EPUB"的格式转换来清理格式。 |
| **文件过大 (>200MB)** | 脚本会自动压缩图片。若仍超限，可手动用图片编辑软件降低原书图片质量后再转换，或使用 `--no-compress` 跳过压缩后手动处理。 |
| **封面/书名仍是繁体** | 检查书籍的 `content.opf` 文件，确认元数据是否被正确转换。 |
| **提示 `command not found`** | 重新运行 `bash install.sh` 安装脚本，确保 `$PREFIX/bin` 已加入环境变量 PATH。 |
| **转换后文字乱码** | 确认源 EPUB 文件本身是 UTF-8 编码。如果是 Big5 等旧编码，使用 `--encoding big5` 参数。 |
| **提示 OpenCC 配置不可用** | 运行 `opencc -c tw2s -i /dev/null -o /dev/null` 检查，或重新安装 opencc 包。 |
| **解压失败** | 文件可能损坏或不是有效的 EPUB 格式，尝试用 Calibre 打开确认。 |
| **转换后目录丢失** | NCX 目录可能已损坏，可用 Calibre 重新生成目录，或使用 `--toc` 参数尝试重建。 |
| **批量处理部分失败** | 查看日志或使用 `--verbose` 模式排查具体失败原因，单个文件失败不影响其他文件继续处理。 |
| **检测到 DRM 保护** | 使用 `--check-drm` 参数预先检查。受 DRM 保护的文件需先用 Calibre 等工具移除 DRM 后再转换。 |
| **转换后图片模糊** | 图片压缩阈值默认为 150MB，超过则自动压缩。可使用 `--no-compress` 关闭压缩。 |
| **输出文件验证失败** | 使用 `--dry-run` 检查原始文件结构是否完整，或尝试用 Calibre 打开原始文件确认。 |
| **并行处理出错** | 减少 `--parallel` 的并发数，或改用串行处理（不指定 --parallel）。 |
| **批量处理中断** | 使用 `--resume` 参数从断点处继续，已完成的文件会被自动跳过。 |
| **安装脚本 SHA256 校验失败** | 文件可能被篡改，建议取消安装并检查网络连接。如确认为合法修改，可使用 `--force` 跳过校验。 |

## 高级用法

### 并行处理调优

并行处理速度取决于设备性能。建议根据 CPU 核心数设置并发数：

```bash
# 查看 CPU 核心数
nproc

# 根据核心数设置并行任务数（通常为核心数或核心数+1）
cc-epub --batch /sdcard/Download/書籍 --parallel 4
```

### 批量处理大目录

处理大量文件时，建议分批处理并启用日志记录：

```bash
# 第一批：小说类
cc-epub --batch /sdcard/Download/書籍 --include "小说*" --log /tmp/batch1.log

# 第二批：社科类
cc-epub --batch /sdcard/Download/書籍 --include "社科*" --log /tmp/batch2.log

# 查看处理统计
cc-epub --batch /sdcard/Download/書籍 --stats
```

### 自动化脚本集成

使用 `--quiet` 模式配合 cron 或脚本实现自动化：

```bash
#!/bin/bash
# 每日自动转换脚本
for epub in /sdcard/Download/待轉換/*.epub; do
    cc-epub "$epub" --quiet --no-kindle-opt
    mv "$epub" /sdcard/Download/已轉換/
done
```

### 预设配置管理

创建多个配置文件以适应不同场景：

```bash
# 快速转换配置（关闭 Kindle 优化和图片压缩）
cat > ~/.cc-epub/fast.conf << 'EOF'
mode=tw2s
add_indent=1
force_horizontal=1
compress_images=0
kindle_opt=0
encoding=utf-8
timeout=120
retry=0
EOF

# 使用快速配置
cc-epub book.epub --config ~/.cc-epub/fast.conf
```

## 安装脚本管理命令

| 命令 | 作用 |
| :--- | :--- |
| `bash install.sh` | 安装 CC-EPUB |
| `bash install.sh --update` | 更新到最新版本 |
| `bash install.sh --check-update` | 检查是否有可用更新（v5.0 新增） |
| `bash install.sh --cleanup` | 清理旧备份和临时文件（v5.0 新增） |
| `bash install.sh --config` | 显示当前配置信息（v5.0 新增） |
| `bash install.sh --report` | 显示系统诊断报告（v5.0 新增） |
| `bash install.sh --mirror <源>` | 手动切换镜像源 (github/gitlab)（v5.0 新增） |
| `bash install.sh --auto-accept` | 自动确认所有提示，适合自动化（v5.0 新增） |
| `bash install.sh --dry-install` | 模拟安装，不实际修改任何文件（v5.0 新增） |
| `bash install.sh --uninstall` | 完全卸载 CC-EPUB |

## 安全说明

- **DRM 保护**：本工具不支持转换受 DRM 保护的 EPUB 文件。转换前请使用 `--check-drm` 参数检查。
- **文件完整性**：v5.0 起，安装脚本自动验证下载脚本的 SHA256 哈希值，防止文件在传输过程中被篡改。
- **隐私保护**：所有转换操作在设备本地完成，不上传任何数据到服务器。
- **开源透明**：本工具完全开源（MIT 许可证），可审查代码确认无恶意行为。

## 性能优化建议

- **批量处理时**：建议将书籍按大小分批处理，避免一次性处理过多大文件导致内存不足。
- **图片压缩**：如果书籍图片较多但体积不大（<150MB），建议使用 `--no-compress` 跳过压缩以加快处理速度。
- **Kindle 优化**：如果转换速度较慢且不需要推送到 Kindle，可使用 `--no-kindle-opt` 跳过兼容性优化。
- **日志记录**：处理大文件时建议使用 `--log` 参数保存日志，方便排查问题。
- **并行处理**：使用 `--parallel` 参数可大幅提升批量处理速度，建议设置为 CPU 核心数。
- **断点续转**：大批量处理时如遇中断，使用 `--resume` 从断点继续，避免重复处理。

## 更新脚本

```bash
# 方式一：重新运行安装脚本
bash install.sh

# 方式二：使用自更新命令
bash install.sh --update

# 方式三：检查是否有可用更新
bash install.sh --check-update
```

## 卸载脚本

```bash
# 完全卸载 CC-EPUB（删除脚本、链接和配置）
bash install.sh --uninstall

# 清理旧备份和临时文件（保留配置）
bash install.sh --cleanup
```

## 文件说明

| 文件 | 说明 |
| :--- | :--- |
| `install.sh` | 一键安装脚本，自动配置环境和安装依赖 |
| `cc-epub.sh` | 主转换脚本，执行繁简转换、排版优化和 Kindle 兼容处理 |
| `README.md` | 项目说明文档（本文件） |
| `~/.cc-epub/config` | 预设配置文件（可选） |

## 依赖工具

- **OpenCC** — 开放中文转换库，提供精准的繁简转换能力
- **unzip / zip** — EPUB 文件的解压与打包
- **Python 3** — CSS/HTML 精确修改与排版调整
- **ImageMagick** — 图片压缩（仅在文件过大时自动调用）

## 版本历史

### v5.0
- 新增 `--parallel` 并行批量处理，支持多任务并发
- 新增 `--resume` 断点续转，中途中断后可从断点继续
- 新增 `--exclude` / `--include` 批量文件过滤
- 新增 `--skip-existing` 跳过已存在的输出文件
- 新增 `--quiet` 静默模式，适合脚本集成
- 新增 `--stats` 转换统计信息
- 新增 `--encoding` 处理非 UTF8 编码文件
- 新增 `--timeout` / `--retry` 超时与重试机制
- 新增 `--output-prefix` / `--output-suffix` 自定义文件名
- 新增 `--config` 预设配置文件管理
- 新增 `--check-update` / `--cleanup` / `--config` / `--report` 安装脚本管理命令
- 新增 `--mirror` 手动切换镜像源
- 新增 `--auto-accept` / `--dry-install` 自动化安装选项
- 新增 SHA256 下载完整性校验
- 新增安全说明章节

### v4.0
- 新增 `--batch` 批量处理模式，支持一次转换目录下所有 EPUB
- 新增 `--restore` 从备份恢复原文件
- 新增 `--check-drm` DRM 保护检测
- 新增 `--log` 日志记录功能
- 新增 `--toc` 导航目录重建
- 新增 `--uninstall` 和 `--update` 安装脚本管理命令
- 新增 PATH 自动检测与修复
- 新增下载进度条显示
- 优化二进制文件跳过逻辑，增加更多类型检测
- 修复 NCX 目录解析中的特殊字符问题
- 优化批量处理错误统计与报告

### v3.0
- 修复 `--mode` 参数解析错误
- 修复 CSS/HTML 修改计数逻辑错误
- 新增 `--verbose` 详细调试模式
- 新增 `--output` 自定义输出路径
- 新增 `--help` 帮助信息
- 新增输出文件完整性校验（unzip -t）
- 新增二进制文件跳过逻辑，避免误处理图片/字体
- install.sh 增加镜像源重复检测，避免重复写入
- install.sh 增加 `--force` 强制覆盖和 `--local` 本地模式
- 优化依赖版本信息显示

### v2.0
- 新增彩色终端输出
- 新增双源下载（GitHub + GitLab 备用）
- 新增 `--mode`、`--dry-run` 等参数
- 新增 Kindle 兼容性优化步骤
- 新增智能图片压缩

### v1.0
- 初始版本，基础繁简转换 + 横排 + 首行缩进

## 许可证

MIT License

## 致谢

- [OpenCC](https://github.com/BYVoid/OpenCC) — 开放中文转换
- [Termux](https://termux.com/) — Android 终端模拟器
