# cc-epub —— EPUB 港台繁体中文书籍转换

将**港台繁体 EPUB 电子书**一键转换为 **简体 + 横排 + 首行缩进**，适配 **Kindle Paperwhite（第12代）** 阅读。

> 设备链路：**OPPO Find X8s** → **Termux** → **OpenCC** → `cc-epub` → **Send to Kindle** → Kindle

## ✨ 功能

- ✅ **繁体 → 简体**（基于 OpenCC，默认 `t2s`；台湾惯用词用 `--config tw2sp`）
- ✅ **强制横排**（`writing-mode: horizontal-tb`）
- ✅ **首行缩进 2 字符**（`text-indent: 2em`）
- ✅ **保留 EPUB 合法结构**（`mimetype` 为首个未压缩条目，阅读器兼容）
- ✅ **自动更新输出路径**：`Download/E-book/书名-cc.epub`
- ✅ **幂等**：可重复运行，不会重复注入 CSS

## 📦 安装（Termux / 任意 Linux / macOS）

```bash
# Termux 一键部署（推荐）
bash install-termux.sh

# 或手动
pip install -r requirements.txt   # 需先 pkg install python opencc
```

## 🚀 用法

```bash
# 便签中的核心命令：cc 书名
cc /sdcard/Download/E-book/某书.epub
# → 输出：/sdcard/Download/E-book/某书-cc.epub

# 等价完整命令
python convert.py 某书.epub -o Download/E-book/某书-cc.epub --config t2s

# 台湾惯用词更彻底（軟體→软件 等）
python convert.py 某书.epub --config tw2sp
```

## 🔗 推送至 Kindle

转换完成后，通过 **Send to Kindle** 网页版推送：
- 单文件 **≤ 200MB**（超大会在脚本中 WARN 提醒拆分）
- EPUB 经 Send to Kindle 自动转为 Kindle 原生格式
- 国行用户走 **amazon.co.jp** 站点

## 🤖 GitHub Actions 自动化

把 `.epub` 放到 `input/` 目录并 push → 自动转换 → 在 Actions **产物**里下载 `-cc.epub`。

## 🧪 本地测试

```bash
python test_convert.py
```

## 📄 License

MIT
