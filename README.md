# cc-epub — 港台繁体 EPUB 转简体横排

便签需求：Kindle Paperwhite 阅读，EPUB 繁转简 + 横排；OPPO Find X8s (Termux/F-Droid) 操作；
命令 `cc-书名`，输出 `Download/E-book`；GitHub `epubcc/cc-epub`。

## 功能
- **繁→简**（字符级）+ **台湾词汇→大陆用词**（`矽二極體→硅二极管`、`滑鼠→鼠标`、`電腦→计算机`）
- **强制横排**：`vertical-rl/lr → horizontal-tb`，无声明时自动注入基线规则
- **EPUB 规范**：`mimetype` 首位 + 不压缩
- **输出**：`~/Download/E-book`（Termux：`~/storage/downloads/E-book`）
- **`cc-书名`**：动态搜索目录（含 `cwd`、`cwd/Download`），模糊匹配；多匹配在非 TTY 环境自动选第 0 个

## 部署（Termux / Linux / macOS）
```bash
bash install.sh          # 生成 cc- 命令
cc- 三体                  # 转换
cc- --list                # 列出可用 EPUB
```

## 测试
```bash
python test_converter.py   # 单元测试
python audit.py            # 审计（同 CI 门禁）
python simulate_ci.py      # 本地完整模拟 GitHub Actions
```

## Kindle 兼容性
- **Send to Kindle**（推荐）：简体 EPUB 上传，云端自动推送
- **Calibre 转 AZW3**：USB 直传
- **EPUB 直接**：仅新版 Kindle / KFX 支持，建议上述两方案

## CI
每次 push / PR 自动跑 `.github/workflows/check.yml`（Python 3.9/3.11/3.12 矩阵）：
语法 → 结构 → 单元测试 → audit → **真实 EPUB 端到端**（繁体+竖排 → 读真实输出断言）→ 产物上传 → 绿灯门禁。
详见 [CI.md](CI.md)。
