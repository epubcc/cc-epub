# cc-epub 部署指南（Termux / 通用）

> 目标设备：**OPPO Find X8s**（或任意 Android 7.0+ 手机）
> 环境：**Termux**（F-Droid 版，**不要从 Google Play 安装**——已停更会报错）
> 功能：港台繁体 EPUB → **简体 + 横排 + 首行缩进** → Kindle Paperwhite 12

---

## 一、依赖清单（完整拆解）

### 1. 系统级依赖（Termux `pkg` 安装）

| 包名 | 作用 | 必需 |
|------|------|------|
| **`python`** | Python 3.10+ 运行时，执行 `convert.py` | ✅ 必需 |
| **`opencc`** | OpenCC **命令行工具 + 词典数据**（`t2s.json` 等配置文件） | ✅ 必需 |
| **`libopencc`** | OpenCC 的共享库，Python 绑定 `import opencc` 依赖它 | ✅ 必需 |
| `git` | 克隆仓库 / 后续更新 | ✅ 推荐 |
| `unzip` / `zip` | EPUB 本质是 ZIP 格式，部分工具需要 | ✅ 推荐 |
| `clang` | C 编译器，极少数 pip 包编译备用 | ⚠️ 可选（装了更稳） |

> 💡 **为什么同时装 `opencc` 和 `libopencc`？**
> Python 的 `opencc` 包只是薄绑定，底层调用系统的 OpenCC 词典与库。只装 pip 包而缺系统词典，运行会报「config not found」。所以务必 `pkg install opencc libopencc`。

### 2. Python 依赖（`pip`）

写在 `requirements.txt` 里：

```
opencc>=0.1.9
chardet>=5.0
```

- **`opencc`**：Python 绑定，调用转换功能
- **`chardet`**：自动检测 EPUB 文件编码（GBK / Big5 / Shift_JIS 等），避免旧书解码失败

除此之外**全部使用 Python 标准库**（`zipfile`、`re`、`os`、`shutil`、`argparse`、`pathlib`、`sys`）——无需 NumPy、lxml 等重型依赖，这也是脚本在手机上跑得快的原因。

### 3. 外部依赖（你要准备的素材）

- 一本**无 DRM 的繁体 EPUB**（港台书籍；若是扫描版/图片内文字则无法转换，需先 OCR）
- 一部 **Kindle + 亚马逊账号**（推送用）

---

## 二、完整操作步骤

### 第 0 步：安装 Termux（⚠️ 关键前置）

**不要从 Google Play 装**（2022 年 11 月起停更，会导致仓库损坏）。

✅ 正确做法：**通过 F-Droid 安装**

1. 手机浏览器打开 **https://f-droid.org** → 下载 F-Droid APK
2. 安装 F-Droid → 允许「安装未知来源应用」
3. 打开 F-Droid → 搜索 **Termux** → 安装官方 `Termux:Termux`
4. 首次启动会初始化基础系统（等几十秒）

> 也可从 GitHub Releases 直下 APK：现代手机选 `_arm64-v8a.apk`。
> **F-Droid 与 GitHub 版签名不同，二选一，不要混用。**

---

### 第 1 步：把项目弄到手机上（二选一）

**方式 A：git 克隆（推荐，便于后续 `git pull` 更新）**

```bash
pkg install -y git
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub
```

**方式 B：手动传文件**

1. 电脑把 `cc-epub` 整个文件夹放进手机 **Download/E-book/**
2. Termux 里：
```bash
cd /sdcard/Download/E-book/cc-epub
```

> 若用电脑生成的 `cc-epub.zip`，先把 zip 传到手机 Download，再用：
> `cp /sdcard/Download/cc-epub.zip . && unzip cc-epub.zip && cd cc-epub`

---

### 第 2 步：运行一键部署脚本

```bash
bash install-termux.sh
```

脚本会自动完成以下 **8 件事**（对应脚本里的 `[1/8]`~`[8/8]`）：

```
[1/8] 配置软件源       → 切清华 TUNA 镜像（国内加速）
[2/8] 更新 Termux 包   → pkg update && pkg upgrade
[3/8] 装系统依赖       → python + opencc + libopencc + git + unzip + zip
[4/8] 授权存储         → termux-setup-storage（弹出系统授权框，点允许）
[5/8] 装 Python 依赖   → pip install -r requirements.txt
[6/8] 创建别名 'cc'    → 写入 ~/.bashrc 与 ~/.zshrc
[7/8] 运行自检         → python test_convert.py
[8/8] 安装 chardet     → 提升编码兼容性（可选）
```

**看到末尾 `🎉 部署完成！` + 测试全绿即成功。**

> 若 `[4/8]` 提示 `/sdcard/Download 暂不可见`：到系统弹窗点「允许」，然后**重新运行一次**脚本即可。

---

### 第 3 步：让别名 `cc` 生效

新开一个 Termux 会话，或手动：
```bash
source ~/.bashrc
```

验证：
```bash
which cc   # 或 type cc，应显示指向 convert.py 的 alias
```

---

### （可选）使用 Python 虚拟环境

如果你希望保持 Termux 全局环境干净，可以使用虚拟环境：

```bash
# 在项目目录中创建虚拟环境
python -m venv .venv
source .venv/bin/activate

# 安装依赖到虚拟环境
pip install -r requirements.txt

# 使用虚拟环境中的 Python 运行脚本
.venv/bin/python convert.py 某书.epub

# 注意：别名 'cc' 指向全局 python，若要用别名需指向虚拟环境
# 修改 ~/.bashrc 中的 cc 别名：
# alias cc='python "$HOME/path/to/cc-epub/convert.py"'
```

---

## 三、日常使用

### 基本转换（便签里的核心命令）

```bash
cc /sdcard/Download/E-book/某书.epub
# ✅ 输出：/sdcard/Download/E-book/某书-cc.epub
```

### 常用选项

```bash
cc 某书.epub --config tw2sp     # 台湾惯用词→简（軟體→软件 更彻底）
cc 某书.epub --config t2s       # 通用繁体→简（默认）
cc 某书.epub -o /自定义/路径.epub  # 指定输出位置
cc 某书.epub --no-css           # 只转文字，不注入横排/缩进 CSS
```

### 批量转换整个文件夹

```bash
for f in /sdcard/Download/E-book/*.epub; do
  cc "$f"
done
```

### 台湾繁体 vs 通用繁体的选择

| 场景 | 用哪个 config |
|------|---------------|
| 港台书籍，**只要简体字** | `t2s`（默认，够用） |
| 港台书籍，**还要惯用词转换**（軟體→软件、滑鼠→鼠标） | `tw2sp` |
| 繁体（含异体、旧字形）→ 规范繁体 | `s2t` |

---

## 四、推送到 Kindle（Send to Kindle）

1. 打开 **Send to Kindle** 网页版：
   - 国行账号 → **https://www.amazon.co.jp/sendtokindle**
   - 国际账号 → https://www.amazon.com/sendtokindle
2. 登录你的亚马逊账号
3. 上传 `某书-cc.epub` → 服务端**自动转 KF8/AZW3** → Wi-Fi 推送到 Kindle
4. Kindle Paperwhite 12 代连 Wi-Fi 即可接收

> ⚠️ **限制提醒**：
> - 单文件 **≤ 200MB**（超大会被拒；脚本对超 200MB 文件会 WARN）
> - EPUB 会被**云端转成原生格式**——若想完全本地控制排版，可先经 **Calibre** 转 AZW3 再推
> - 仅支持**无 DRM** 的个人文档

---

## 五、Kindle 兼容性说明

本项目已自动处理以下 Kindle 常见问题：

| 问题 | 处理方式 |
|------|----------|
| 特殊繁体字体导致白页 | 自动移除 `@font-face` 嵌入字体声明 |
| 复杂 CSS 导致转换崩溃 | 清理 `display:none`、`position:absolute`、`float` 等规则 |
| 编码非 UTF-8 导致乱码 | 自动检测编码（UTF-8/GBK/Big5），统一转为 UTF-8 |
| 语言代码错误 | OPF 文件中 `<dc:language>` 自动设为 `zh-CN` |
| 文件过大被拒 | 超过 200MB 时自动 WARN 提醒拆分 |

---

## 六、故障排查

| 现象 | 原因 | 解决 |
|------|------|------|
| `command not found: cc` | 别名未生效 | `source ~/.bashrc` 或新开会话 |
| `[FATAL] 未安装 opencc` | pip 包装了但缺系统词典 | `pkg install -y opencc libopencc` |
| `config not found` / `t2s.json` 找不到 | 系统 `opencc` 未装 | 同上 |
| `No module named 'opencc'` | pip 依赖没装上 | `pip install -r requirements.txt` |
| `/sdcard/Download 不可见` | 存储权限未授予 | 系统弹窗点允许，重跑脚本 |
| 转换后 EPUB 打不开 | `mimetype` 不合规 | 用本项目脚本（已正确处理），**不要**用网上随手脚本 |
| 中文乱码 / 转换中断 | EPUB 编码非 UTF-8（如 GBK/Big5） | 已安装 `chardet` 后自动检测；若仍失败，用 Calibre 转码为 UTF-8 后再处理 |
| 下载慢 / 连不上 | 默认源在国外 | 脚本已自动切 TUNA；若手动装，运行 `termux-change-repo` 选清华 |

---

## 七、更新项目

```bash
cd cc-epub
git pull            # 拉取最新
bash install-termux.sh   # 重新跑一遍（幂等，可重复执行）
```

---

## 附：极简速查卡（5 分钟上手）

```bash
# 装 Termux（F-Droid）→ 克隆 → 部署 → 转换 → 推送
pkg install -y git
git clone https://github.com/epubcc/cc-epub && cd cc-epub
bash install-termux.sh
source ~/.bashrc

cc /sdcard/Download/E-book/某书.epub
# → 上传 某书-cc.epub 到 Send to Kindle，完事 📖
```

详细原理见 `README.md`，自动化（GitHub Actions）见 `.github/workflows/convert.yml`。
