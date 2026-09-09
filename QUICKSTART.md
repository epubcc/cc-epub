# 快速部署命令（复制粘贴用）

> 以下命令可直接在 Termux 中一行行粘贴。完整说明见 [README.md](./README.md)。

## 一键部署（推荐）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"
```

## 手动部署（分步）

```bash
# 1. 换国内镜像源（避免下载极慢）
termux-change-repo
#   选 "Mirrors in Chinese Mainland" → "Tsinghua"

# 2. 更新 + 授权存储
pkg update && pkg upgrade -y
termux-setup-storage

# 3. 安装系统依赖（注意包名：libopencc + opencc-tools）
pkg install -y python git zip unzip libopencc opencc-tools

# 4. 安装 Python 库（清华 PyPI 镜像）
pip install --index-url https://pypi.tuna.tsinghua.edu.cn/simple beautifulsoup4

# 5. 克隆 + 部署
git clone https://github.com/epubcc/cc-epub.git ~/cc-epub
cd ~/cc-epub && bash install.sh

# 6. 防息屏被杀
termux-wake-lock
```

## 日常使用

```bash
cc 书名.epub                 # 单本转换
cc ~/Download/ --batch       # 批量
cc 书名.epub --dry-run       # 仅检测排版方向
```

## 验证

```bash
type cc && cc --version && opencc --version
```
