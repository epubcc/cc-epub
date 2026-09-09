# 部署指南 · 港台繁体 EPUB 转换工具 1.0

本文档提供从零搭建、安装依赖、部署的完整流程。**每一步都是独立命令块，逐块复制粘贴即可。**

---

## 第 1 步 · 安装 Termux

1. 打开 **F-Droid 2.0-rc1**
2. 搜索 **Termux**，安装 **0.119.0-beta.3**
3. 首次打开，允许**存储权限**

> ⚠️ 不要用 Google Play 版 Termux（已停维护，兼容性差）

---

## 第 2 步 · 初始化环境

```bash
termux-change-repo
pkg update -y && pkg upgrade -y
pkg install -y python git unzip zip libopencc opencc-tools
```

> `libopencc` + `opencc-tools` 是繁→简引擎的系统级 C++ 库，必须装。

---

## 第 3 步 · 授权存储

```bash
termux-setup-storage
```

> 弹出授权框 → **允许**。授权后 `~/storage/downloads` 映射到手机 `Download/`。

验证：
```bash
ls ~/storage/downloads
```
> 能看到手机 Download/ 里的文件即成功。

---

## 第 4 步 · 安装依赖（关键）

### 4.1 系统包（Termux 官方仓库）

```bash
pkg install -y libopencc opencc-tools
```

> 📌 Termux 官方仓库**没有名为 `opencc` 的包**，正确包名是：
> - **`libopencc`**：OpenCC 核心 C++ 库
> - **`opencc-tools`**：命令行工具（含词典）

### 4.2 Python 包（PyPI）

```bash
pip install opencc beautifulsoup4
```

> - **`opencc`**：Python 绑定，`converter.py` 通过 `import opencc` 调用
> - **`beautifulsoup4`**：解析 xhtml，处理章节内容与标点

### 4.3 验证（看到 `测试` 即成功，唯一判定标准）

```bash
python3 -c "import opencc, bs4; print(opencc.OpenCC('tw2sp').convert('測試'))"
```

> 期望输出：`测试`
>
> 若报错，见文末「故障排查」。

---

## 第 5 步 · 获取代码

**方式 A：从 GitHub 克隆（推荐）**
```bash
cd ~
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub
```

**方式 B：手动上传**
1. 把本仓库所有文件（含 `.github/` 目录）打包为 zip
2. 传到手机 Download/
3. 在 Termux 中：
```bash
cd ~
mkdir -p cc-epub && cd cc-epub
unzip ~/storage/downloads/cc-epub.zip
```

---

## 第 6 步 · 执行部署

```bash
bash install.sh
```

`install.sh` 会自动：
1. 检测并补装 `libopencc`、`opencc-tools`、`opencc`、`beautifulsoup4`
2. 授权存储（`termux-setup-storage`）
3. 创建 `cc-` 命令到 PATH（`$PREFIX/bin/cc-`）
4. 创建输出目录 `Download/E-book/`
5. 运行自检（转换一个测试样本，确认 `壞→坏` 生效）

> 看到 `✅ 部署完成` + `✅ opencc 工作正常` 即成功。

---

## 第 7 步 · 确认目录结构

```bash
ls -la ~/storage/downloads
ls -la ~/storage/downloads/E-book
which cc-
```

> 期望：`E-book/` 目录已存在，`cc-` 命令路径已加入 PATH。

---

## 第 8 步 · 跑端到端测试

```bash
python3 e2e.py
```

> 期望最后一行：`ALL GREEN —— 可以 push`
>
> 若失败，把完整报错发回排查。

---

## 第 9 步 · 日常使用

```bash
# 1. 把港台繁体 EPUB 放进 Download/
#    例如：Download/三体.epub

# 2. 列出可转换的书
cc- --list

# 3. 转换（支持模糊匹配）
cc- 三体
#    或完整文件名
cc- 三体.epub
```

**输出**：
```
📖 找到：三体.epub
🔄 繁→简：矽二極體 → 硅二极管 ...
📐 横排处理：vertical-rl → horizontal-tb
✅ 完成 → /storage/emulated/0/Download/E-book/三体-简中.epub
```

**输出文件**：`Download/E-book/书名-简中.epub`

---

## 第 10 步 · 传到 Kindle

### 方式 A：Send to Kindle 网页版（推荐）
1. 打开 [https://www.amazon.com/sendtokindle](https://www.amazon.com/sendtokindle)
2. 登录你的亚马逊账号（与 Kindle 同账号）
3. 上传 `书名-简中.epub`
4. 选择目标设备 → 推送

> ⚠️ 单文件 **≤ 200 MB**。服务端自动转为 **KFX** 格式下发。

### 方式 B：Calibre 转 AZW3（兼容性兜底）
若 Send to Kindle 后**白页**，说明原 EPUB 排版复杂：
```bash
# 电脑端 Calibre：EPUB → AZW3 → USB 直传
```
> AZW3 是 Kindle 原生格式，复杂排版兼容性最好。

---

## 🔧 常见问题速查

| 问题 | 解决办法 |
|---|---|
| `cc-: command not found` | `source ~/.bashrc` 或重开 Termux |
| `ImportError: No module named opencc` | `pip install opencc` |
| `OSError: libopencc.so ... not found` | `pkg install libopencc` |
| `壞` 未转成 `坏` | OpenCC 未生效，重跑第 4 步验证 |
| `~/storage/downloads` 为空 | 重跑 `termux-setup-storage` 并重新授权 |
| 转换后白页 | 改用 Calibre 转 AZW3（第 10 步方式 B） |
| 文件 > 200 MB | 压缩图片后重试，或用 Calibre |

---

## 📋 版本信息

| 组件 | 版本 |
|---|---|
| Termux | 0.119.0-beta.3（F-Droid 2.0-rc1） |
| OpenCC | 1.4.2 |
| Python | 3.x |
| 繁简配置 | `tw2sp`（台湾繁体 → 大陆简体 + 词汇） |
