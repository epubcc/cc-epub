# cc-epub —— 港台繁体 EPUB → 简体一键转换

把港台繁体中文 EPUB 转换成简体（含地区用词：軟體→软件、資料→数据、滑鼠→鼠标），
并自动处理排版：**横排 + 首行缩进 + 防白页**，输出合规 EPUB，可直接上传
**Send to Kindle 网页版**推送到 **Kindle Paperwhite 第 12 代**阅读。

> 🎯 核心命令：`cc 書名`  ——  繁体 → 简体，一行搞定。

---

## ✨ 功能

- **繁简转换**：基于 [OpenCC](https://github.com/BYVoid/OpenCC)，用词级准确
  - 默认 `tw2sp`（台湾繁体含惯用词 → 大陆简体）
  - 支持 `s2t / s2tw / s2hk / t2s` 等全部 OpenCC 配置
- **排版处理（防白页）**：
  - 注入横排 `writing-mode: horizontal-tb`
  - 首行缩进 `text-indent: 2em`
  - 删除嵌入字体 `fonts/` 目录 + 清除 `@font-face` + 字体回退 `sans-serif`
- **EPUB 合规**：`mimetype` 为首个条目且 `ZIP_STORED` 未压缩（Kindle 可识别的关键）
- **自动更新**：`bash install.sh` 自动 `git pull` 检查更新
- **批量 / 备份 / 日志 / 推送**等完整 CLI

---

## 📦 环境搭建（Termux on Android）

> ⚠️ **重要**：Termux 官方仓库**没有叫 `opencc` 的包**，正确包名是 **`libopencc`**（最新 1.4.2）+ **`opencc-tools`**（提供 CLI）。
> 所以 `pkg install opencc` **必然报 `Unable to locate package opencc`** —— 这是本工具 `install.sh` / `install_opencc.py` 已自动处理的关键点。

**v2.6 防御加固**：`install.sh` 内置 `fix_termux_pkg_names()` —— 即便未来有人误写裸包名 `opencc`，
Termux 分支也会**自动改写为 `libopencc`** 并打印警告，从根源杜绝该报错。此契约由 `test_pkgname_contract.py` 锁定回归测试。

### 第一步：安装 Termux（用 F-Droid，别用 Google Play）

1. 浏览器打开 **https://f-droid.org** → 安装 F-Droid
2. F-Droid 里搜 **Termux** → 安装官方版 `com.termux`
3. 首次启动等待初始化 1-2 分钟

### 第二步：换清华源（国内必做）

```bash
termux-change-repo   # 选 "Mirrors in Chinese Mainland → 清华 TUNA"
```

### 第三步：从 GitHub 克隆

```bash
termux-setup-storage
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub
```

### 第四步：一键安装

```bash
bash install.sh
source ~/.bashrc
```

`install.sh` 会自动完成：
1. **检查更新**（git fetch，有新版自动 pull）
2. 更新软件源（`pkg update -y`）
3. **安装 `libopencc` + `opencc-tools`**（Termux 正确包名）
4. 安装 Python 绑定 `opencc-python-reimplemented`（兜底）
5. 建 `~/Download/E-book` 输出目录 + 设 `cc` 别名
6. 跑 `verify_note.py` 自检（23 项）

> 💡 **关于 "Unable to locate package opencc"**：
> 若系统包失败，`install_opencc.py` 会自动降级到 `pip install opencc-python-reimplemented`。
> cc-epub 用的是 Python 绑定，自带字典，**不强制依赖系统 opencc CLI**。

### 第五步：验证

```bash
python3 verify_note.py   # → 23/23 通过 ✅
```

---

## 🚀 使用

```bash
cc 書名                    # 自动在 ~/Download 找 書名*.epub → 繁→简
cc /sdcard/books/ -r       # 批量递归
cc 書名 --s2t              # 反向：简 → 繁（含用词 软件→軟體）
cc 書名 --backup -v        # 备份原文件 + 详细日志
cc 書名 --push xxx@kindle.com   # 推送（需配 SMTP 环境变量）
```

输出统一在 `~/Download/E-book/書名.simplified.epub` ✅

之后上传 **Send to Kindle 网页版**（国行走 **amazon.co.jp**）→ 自动转 KFX → Kindle 阅读 📖

**升级**：`bash install.sh`（自动 `git pull`，有新版本则拉取）

---

## 📁 文件清单

| 文件 | 作用 |
|------|------|
| `cc_epub.py` | 主脚本（`cc 書名`） |
| `install.sh` | 一键安装 + 自动 git pull 更新 |
| `install_opencc.py` | 诊断/兜底安装（解决 libopencc 包名问题）|
| `verify_note.py` | 23 项便签需求验收 |
| `run_tests.sh` | 端到端测试 |
| `test_install.sh` | install.sh 专项测试 |
| `test_termux_libopencc.py` | ★ Termux `libopencc` 包名验证 |
| `test_opencc_fallback.py` | 降级方案验证 |
| `test_pkgname_contract.py` | **包名契约回归测试（锁定不得用裸 `opencc`）** |
| `test_fix_termux_pkg_names.sh` | `fix_termux_pkg_names` 防御函数单测 |
| `README.md` | 本文档 |

---

## 🔗 完整工具链

```
港台繁体 EPUB
  → ① cc_epub.py（OpenCC 繁简 + 防白页 + 横排 + 缩进）
  → ② Send to Kindle 网页版（EPUB → KFX，国行走 amazon.co.jp）
  → ③ Kindle Paperwhite 第 12 代 阅读 📖
```

---

## 📄 License

GPL-3.0（与上游 OpenCC 一致）
