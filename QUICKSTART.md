# QUICKSTART — 可复制粘贴的快速部署指南

> 设备：OPPO Find X8s · Termux 0.118.3（F-Droid 2.0-rc1 安装）· 目标：Kindle PWSE 第12代
> 命令格式：`cc 书名.epub` → 输出 `书名-简中.epub`（书名取自 EPUB 内 OPF 元数据）

---

## 一、一键部署（推荐）

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)"
```

## 二、手动部署（分步，可复制粘贴）

```bash
# 1. 更新软件包列表
pkg update -y && pkg upgrade -y

# 2. ★换国内镜像源（强烈推荐，否则下载极慢）
termux-change-repo
#   弹出界面选 "Mirrors in Chinese Mainland" → "Tsinghua"

# 3. 换源后再更新一次
pkg update -y

# 4. 授予存储权限（访问手机 Download 目录）
termux-setup-storage
#   弹出对话框点"允许"，之后出现 ~/storage/shared -> /storage/emulated/0

# 5. 安装系统依赖
#   ★ Termux 官方仓库没有名为 "Open CC" 的包，正确包名是下面两个：
pkg install -y python git zip unzip libopencc opencc-tools

# 6. 安装 Python 库（用清华源加速）
pip install --index-url https://pypi.tuna.tsinghua.edu.cn/simple beautifulsoup4

# 7. 克隆仓库
git clone https://github.com/epubcc/cc-epub.git ~/cc-epub
cd ~/cc-epub

# 8. 运行部署脚本（配置 cc 快捷命令 + PATH）
bash install.sh

# 9. 防止息屏被杀进程（大文件转换时建议开启）
termux-wake-lock

# 10. 验证
source ~/.bashrc          # 让 cc 命令生效
type cc                    # 应显示指向 ~/bin/cc
cc --help
```

## 三、使用

```bash
# 单本转换（输出：~/storage/shared/Download/E-book/书名-简中.epub）
cc 原子习惯.epub
cc ~/storage/shared/Download/原子习惯.epub

# 指定输出路径
cc -o ~/storage/shared/Download/原子习惯-简中.epub 原子习惯.epub

# 批量转换整个目录
for f in ~/storage/shared/Download/*.epub; do cc "$f"; done
```

> **关于文件名**：`书名-简中.epub` 中的"书名"取自 EPUB 内部 OPF 文件的 `<dc:title>`（会自动繁转简）。
> 例：OPF 书名为 `原子習慣：細微改變帶來巨大成效` → 输出 `原子习惯：细微改变带来巨大成效-简中.epub`。
> 若 OPF 中无书名，则回退为输入文件名。

## 四、输出位置

```
~/storage/shared/Download/E-book/书名-简中.epub
# 真实路径：/storage/emulated/0/Download/E-book/书名-简中.epub
```

Send to Kindle 网页版推送，**文件大小 ≤ 200 MB**。正常 EPUB 会被自动转为 KFX 格式推送到 Kindle。

## 五、常见问题速查

| 现象 | 处理 |
|------|------|
| `command not found: cc` | `source ~/.bashrc` 或重启 Termux |
| `cc` 指向编译器（clang） | `which cc` 应显示 `~/bin/cc`，确保 `~/bin` 在 PATH 最前 |
| `opencc` 命令找不到 | 确认装了 `libopencc` + `opencc-tools` 两个包 |
| `tw2sp.json` 未找到 | `pkg reinstall opencc-tools` |
| 找不到 `storage` 目录 | 执行 `termux-setup-storage` 并点"允许" |
| `pip install` 超时 | 加 `--index-url https://pypi.tuna.tsinghua.edu.cn/simple` |
| 香港繁体书籍 | 把 `cc.py` 里 `OPENCC_CONFIG = "tw2sp.json"` 改为 `hk2sp.json` |
| 转换后白页/排版异常 | 原书 CSS 过于复杂，属极少数情况，可提 Issue |

## 六、卸载

```bash
rm -rf ~/cc-epub ~/bin/cc ~/storage/shared/Download/E-book
```
