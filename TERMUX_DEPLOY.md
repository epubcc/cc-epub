# cc-epub · Termux 部署与使用指南

本文面向**刚全新安装 Termux** 的用户，从零开始把 `cc-epub` 跑通：安装 Termux → 配置环境 → 安装依赖 → 运行转换 → 推送 Kindle。

> 测试环境：Termux 最新版（F-Droid 渠道）、Android 7.0+。全流程已验证逻辑正确性。

---

## 一、整体流程概览

```
[1] 安装 Termux（F-Droid，别用 Play 版）
[2] 首次启动，完成基础环境初始化
[3] 授权存储权限 + 换国内软件源
[4] 获取 cc-epub 项目（下载 / git clone）
[5] 运行 install-termux.sh 一键装依赖
[6] 用 'cc' 命令转换 EPUB
[7] Send to Kindle 推送 → Kindle Paperwhite 阅读
```

---

## 二、依赖清单

### 2.1 系统级依赖（Termux 包管理器 `pkg` 安装）

| 包名 | 作用 | 必需 |
|------|------|------|
| `python` | Python 3 解释器（脚本运行环境） | ✅ 必需 |
| `opencc` | **OpenCC 命令行 + 共享库**（转换引擎核心）| ✅ 必需 |
| `clang` / `libc++` | 部分 Python 包编译时需要 | ⚠️ 可选（一般已随 python 带） |
| `git` | 克隆/更新项目 | 推荐 |

> 💡 **关键**：`opencc` 走 Termux 的 `pkg` 安装，比 `pip install opencc` 从源码编译**快得多、稳得多**，且自动带词库（`/data/data/com.termux/files/usr/share/opencc/`）。

### 2.2 Python 依赖（`pip` 安装）

| 包名 | 作用 |
|------|------|
| `opencc` (PyPI) | Python 绑定，调用系统 OpenCC 库 |

> 说明：`convert.py` 只用到了 Python 标准库（`zipfile`、`re`、`argparse` 等）+ `opencc` 绑定，**无需 ebooklib、lxml 等重依赖**，安装极快。

### 2.3 完整依赖文件 `requirements.txt`

```
opencc>=1.1.0
```

---

## 三、详细操作步骤

### Step 1｜安装 Termux（⚠️ 重要）

> **必须从 F-Droid 或 GitHub 下载，不要从 Google Play 安装！**

Play 版自 2022-11 起已停止更新，会导致包管理器异常。

- F-Droid 地址：https://f-droid.org/en/packages/com.termux/
- 或 GitHub Releases：https://github.com/termux/termux-app/releases/latest
  - 现代手机选 `_arm64-v8a.apk`

安装后打开，允许"通知"、"存储"等权限。

### Step 2｜首次启动初始化

打开 Termux，会自动部署基础系统（约 10-30 秒）。部署完成后看到 `$` 提示符。

### Step 3｜更新源 + 换国内镜像（强烈推荐）

```bash
pkg update && pkg upgrade -y
termux-change-repo        # 选择 "Mirrors in Chinese Mainland"，如清华 TUNA
```

### Step 4｜授权存储权限

```bash
termux-setup-storage      # 弹出授权框，允许 → 生成 ~/storage/ 软链接
ls ~/storage/downloads/   # 验证能访问 /sdcard/Download/
```

> 之后手机的 `Download/E-book/` 对应 Termux 里的 `~/storage/downloads/E-book/`。

### Step 5｜获取 cc-epub 项目

**方式 A：git clone（推荐，便于更新）**

```bash
pkg install -y git
cd ~
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub
```

**方式 B：手动上传**

把 `cc-epub` 整个文件夹放到手机的 `Download/` 下，然后在 Termux 里：

```bash
cp -r ~/storage/downloads/cc-epub ~/
cd ~/cc-epub
```

### Step 6｜运行一键安装脚本

```bash
bash install-termux.sh
source ~/.bashrc     # 激活 'cc' 别名
```

脚本会自动完成：

1. `pkg update`
2. `pkg install -y python opencc git`（装系统依赖）
3. `pip install -r requirements.txt`（装 Python 依赖）
4. 在 `~/.bashrc` 追加 `alias cc='python ~/cc-epub/convert.py'`
5. 验证 `opencc` 可用

看到 `✅ 安装完成` + `✅ OpenCC 可用` 即成功。

### Step 7｜测试转换

用项目自带的测试脚本验证：

```bash
cd ~/cc-epub
python test_convert.py
```

预期输出：

```
[OK] mimetype 合规（首个 + 未压缩）
[OK] 繁→简转换
[OK] 横排 writing-mode 注入
[OK] 首行缩进 text-indent 注入
[ALL PASSED]
```

---

## 四、日常使用（转换 EPUB）

### 4.1 基本命令

```bash
# 方式 1：用 'cc' 别名（安装脚本已配置）
cc ~/storage/downloads/E-book/某书.epub

# 方式 2：直接调脚本
python ~/cc-epub/convert.py 某书.epub -o 某书-cc.epub
```

### 4.2 默认行为

- **输入**：`~/storage/downloads/E-book/某书.epub`（繁体）
- **输出**：同目录 `某书-cc.epub`（简体 + 横排 + 首行缩进）
- **转换规则**：默认 `t2s`（繁→简通用）

### 4.3 常用参数

```bash
cc 某书.epub                       # 繁→简（默认 t2s）
cc 某书.epub --config tw2sp        # 台湾正体→简（含軟體→软件惯用词）
cc 某书.epub --config s2t          # 反向：简→繁
cc 某书.epub -o /自定义/路径.epub   # 指定输出
cc 某书.epub --no-css             # 只转文字，不注入排版 CSS
```

> 📖 转换规则说明见前文 OpenCC 章节（`s2t / t2s / s2tw / s2hk / tw2sp`）。

### 4.4 批量转换整个文件夹

```bash
cd ~/cc-epub
for f in ~/storage/downloads/E-book/*.epub; do
  cc "$f"
done
```

---

## 五、输出 → 推送 Kindle

1. 转换完成后，`-cc.epub` 文件落在 `Download/E-book/`
2. 手机打开 **Send to Kindle**（国行用 amazon.co.jp）
3. 上传该 `.epub` → 自动转 KF8 → Wi-Fi 推送到 **Kindle Paperwhite 第12代**
4. ⚠️ **单文件 ≤ 200MB**（`cc` 命令超大会自动 WARN）

详见：`README.md` 的「Kindle 推送」章节。

---

## 六、常见问题排查

| 问题 | 原因 | 解决 |
|------|------|------|
| `command not found: cc` | 别名未生效 | `source ~/.bashrc` |
| `No module named 'opencc'` | pip 包没装 | `pip install -r requirements.txt` |
| `opencc: command not found` | 系统 opencc 没装 | `pkg install -y opencc` |
| 无法访问 `/sdcard/` | 未授权存储 | `termux-setup-storage` |
| `Permission denied` 写文件 | 存储权限 | 确认上一步，输出到 `~/storage/` 下 |
| 转换后中文乱码 | EPUB 内文本非 UTF-8 | 罕见，脚本会原样保留此类文件 |
| 图片内繁体字未转换 | 扫描版（图片）| 需先 OCR，OpenCC 只处理文本 |

---

## 七、卸载 / 重装

```bash
# 移除别名
sed -i '/cc-epub/d' ~/.bashrc
# 删除项目
rm -rf ~/cc-epub
# 如需彻底清理依赖
pkg uninstall -y python opencc
```

---

## 附：最小手动安装（不用 install-termux.sh）

若想看清每一步，可手动执行脚本里的等价命令：

```bash
pkg update && pkg upgrade -y
pkg install -y python opencc git
pip install opencc
echo "alias cc='python ~/cc-epub/convert.py'" >> ~/.bashrc
source ~/.bashrc
```

---

至此，全新 Termux → 依赖装齐 → `cc` 命令可用 → 转换 → 推送 Kindle 的完整链路打通 ✅
