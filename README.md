# 港台繁体 EPUB 转换工具 1.0

將港台繁體中文 EPUB 轉換為 **橫排 + 簡體中文**，保留原始排版、插圖、目錄、CSS 樣式，輸出可直接用 **Send to Kindle** 推送的 EPUB（服務端轉 KFX）。

> 繁体转简体由 [OpenCC](https://github.com/BYVoid/OpenCC) 驱动，标点、词汇级转换一次到位。

---

## 📖 需求概览

| 项目 | 说明 |
|---|---|
| **阅读设备** | Kindle Paperwhite Signature Edition（第 12 代） |
| **传书方式** | Send to Kindle 网页版（单文件 ≤ 200 MB） |
| **转换目标** | 横排 + 简体中文，保留排版 / 插图 / 目录 / CSS / 字体设置 / 章节分隔 |
| **标点处理** | 横排时标点位置自动调整（全角标点规范化） |
| **字体** | 全书文字字体统一，可调用 Kindle 自带字体 |
| **操作设备** | OPPO Find X8s |
| **运行平台** | Termux（F-Droid 2.0-rc1 下载，版本 0.119.0-beta.3） |

### Kindle 兼容性说明 ⚠️

Kindle 原生对 EPUB 兼容性有限。Send to Kindle 推送时，**服务端会自动将 EPUB 转为 KFX 格式**再下发到设备：

- ✅ **正常情况**：合规 EPUB → KFX → 推送成功，正文正常渲染
- ❌ **失败情况**：原 EPUB 排版过于复杂（特殊繁体字体、复杂 CSS、大量内嵌图），转换可能**失败导致白页**，或**文件过大导致卡顿**

本工具通过以下手段**最大化兼容性**：
1. 清理冗余 / 冲突 CSS，统一为横向阅读基线样式
2. 移除绑定到特定繁体字体（如「思源繁體」「微軟正黑」）的 `font-family`，让 Kindle 使用自带字体
3. 压缩图片为 EPUB3 兼容格式，避免超大内嵌图
4. 保留完整 OPF / NCX / nav 目录结构，符合 EPUB 规范

> 💡 若某本书转换后仍白页，建议改用 **Calibre 转 AZW3** 后 USB 直传。

---

## 🚀 快速开始

```bash
# 1. 获取代码
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub

# 2. 部署（自动安装依赖 + 自检）
bash install.sh

# 3. 使用：把繁体 EPUB 放进 Download/，然后
cc- --list          # 列出可转换的书
cc- 三体            # 转换《三体》，输出 三体-简中.epub
```

---

## 📝 命令格式

```bash
cc- 书名             # 模糊匹配并转换，输出 书名-简中.epub
cc- --list           # 列出 Download/ 下所有可转换的 EPUB
cc- --version        # 显示版本
```

**示例**：
```bash
$ cc- 三体
[1/4] 找到：三体.epub
[2/4] 繁→简：矽二極體 → 硅二极管
[3/4] 横排处理：vertical-rl → horizontal-tb
[4/4] 完成 → /storage/emulated/0/Download/E-book/三体-简中.epub
```

---

## 📁 输出规则

| 项目 | 规则 |
|---|---|
| **文件命名** | `书名-简中.epub`（如 `三体-简中.epub`） |
| **输出目录** | `Download/E-book/`（已自动创建） |
| **输入目录** | `Download/`（递归搜索，含子目录） |

---

## 🔧 技术原理

1. **繁→简**：OpenCC `tw2sp`（台湾繁体 → 大陆简体，含词汇级转换）
2. **横排**：将 CSS / xhtml 中的 `writing-mode: vertical-rl` 替换为 `horizontal-tb`，无声明时注入基线横排规则
3. **字体统一**：清除 `font-family` 中指定的繁体字体，Kindle 自动套用用户所选自带字体
4. **EPUB 规范**：`mimetype` 必须 ZIP 第一条且不压缩（用于校验完整性）
5. **标点调整**：横排时规范化全角标点间距

---

## 📂 项目结构

```
cc-epub/
├── .github/workflows/check.yml   # CI：push 自动跑检查
├── converter.py                    # 核心转换逻辑
├── install.sh                      # 一键部署脚本
├── e2e.py                          # 端到端回归测试（push 前闸门）
├── audit.py                        # CI 门禁套件
├── test_converter.py               # 单元测试
├── cc-                             # 命令入口（install.sh 生成）
├── DEPLOY.md                       # 详细部署文档
├── README.md                       # 本文件
└── LICENSE                         # MIT 协议
```

---

## 🤝 贡献

Issues 和 PR 欢迎。提交前请先跑 `python3 e2e.py`，看到 `ALL GREEN` 再提交。

## 📄 License

MIT © epubcc
