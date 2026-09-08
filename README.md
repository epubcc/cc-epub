# cc-epub — EPUB 繁转简 + 排版标准化（Termux 原生版）

> 将繁体中文 EPUB 书籍自动转换为简体中文，并统一排版格式，专为墨水屏阅读器优化。

## 功能特性

- **繁转简**：基于 OpenCC 将繁体中文自动转换为简体中文
- **排版标准化**：统一段落缩进、标题样式、行高，适配墨水屏阅读
- **广告清理**：移除嵌入广告文本、水印、冗余内联样式（text-align、writing-mode 等）
- **编码修复**：自动检测并处理文件编码问题
- **安全保障**：自动备份原文件、膨胀检测自动回滚、临时文件隔离
- **纯 Termux 原生**：无需 Docker/proot 容器，全部依赖 Termux 原生包

## 依赖

| 包名 | 用途 |
|------|------|
| opencc-tools | 繁转简引擎（提供 opencc 命令） |
| libopencc | OpenCC 运行时库 |
| unzip / zip | EPUB 解包与打包 |
| sed / grep / find | 文本处理与文件查找 |
| perl | 高级文本处理 fallback |
| coreutils | wc / head / tail 等基础工具 |

## 快速开始

### 第一步：环境搭建

在 Termux 中运行一键安装脚本：

```bash
bash setup_termux.sh
```

该脚本会自动安装所有依赖并验证安装状态。

### 第二步：使用 conv.sh

```bash
# 赋予执行权限
chmod +x conv.sh

# 转换单本书
./conv.sh 书名.epub

# 指定绝对路径
./conv.sh /sdcard/Download/书名.epub
```

转换后的文件会保存到 `E-book/` 目录下，原文件自动备份。

### 批量转换

```bash
# 先获取唤醒锁，防止息屏断连
termux-wake-lock

# 批量转换
for f in *.epub; do ./conv.sh "$f"; done

# 完成后释放唤醒锁
termux-wake-unlock
```

## 目录结构

```
cc-epub/
├── conv.sh          # 主转换脚本
├── setup_termux.sh  # 一键环境搭建脚本
├── README.md        # 项目说明
├── LICENSE          # MIT 许可证
└── .gitignore       # Git 忽略规则
```

## 输出效果

- 繁体中文 → 简体中文
- 统一段落首行缩进两字符
- 标题居中、加粗、层级分明
- 移除广告水印和冗余样式
- 输出文件通常比原文件小 10%-30%

## 注意事项

- 本工具仅处理 EPUB 格式，不支持 MOBI/AZW3
- 精装版（漫画、图文混排）不建议使用，可能影响排版
- 大文件批量转换前建议先运行 `termux-wake-lock`
- 转换失败会自动回滚到原始文件，不会损坏原书

## 系统要求

- Termux（Android）
- 或任何安装了上述依赖的 Linux 环境

## 许可证

MIT License — 详见 [LICENSE](LICENSE)
