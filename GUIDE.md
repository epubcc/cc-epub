# CC-EPUB 实战落地指南

> 针对 **OPPO Find X8s + Termux + Kindle Paperwhite 第12代 + Send to Kindle** 的完整部署与使用方案。
> 配套项目：`https://github.com/epubcc/cc-epub`

---

## 一、环境与需求清单（对照便签 1-9）

| 便签要点 | 本项目对应方案 |
| :--- | :--- |
| ① 安卓手机 OPPO Find X8s | 通过 **Termux**（F-Droid 版）提供 Linux 环境，ColorOS 无需 root |
| ② Kindle Paperwhite 第12代 | 输出做 **Kindle 深度优化**（移除内嵌字体、强制 ltr、清理冲突 CSS） |
| ③ 港台繁体 EPUB → 简体横排 | OpenCC `tw2s` / `hk2s`，自动竖排转横排 + 首行缩进 |
| ④ Send to Kindle 网页版（限 200MB） | 智能图片压缩（>150MB 自动压缩），确保单文件 < 200MB |
| ⑤ Termux 依赖：unzip/zip/OpenCC | `install.sh` 一键安装全部依赖并配置清华镜像源 |
| ⑥ 转换命令 `cc 书名` | 支持自定义短命令别名（见下文 §四） |
| ⑦ 输出路径 `Download/E-book` | 默认输出到此目录，产物命名 `书名-cc.epub` |
| ⑧ 复杂排版导致转换失败 | 已内置兼容性优化；失败时自动降级用 Calibre 预处理 |
| ⑨ GitHub 部署 `epubcc/cc-epub` | 项目即为此仓库，支持 `curl | bash` 一键安装 |

---

## 二、安装步骤（OPPO Find X8s 实测）

### 1. 安装 Termux
从 **F-Droid** 下载安装 Termux（Google Play 版已停维护，ColorOS 可直接安装 F-Droid 的 APK）。

### 2. 一键部署
打开 Termux，粘贴执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/epubcc/cc-epub/main/install.sh)
```

脚本会自动完成：
- 请求存储权限（`termux-setup-storage`，授权后可在 `文件管理器/Download/E-book` 看到产物）
- 配置清华大学 TUNA 镜像源（国内网络友好）
- 安装 `unzip`、`zip`、`opencc`、`python3`、`imagemagick`
- 下载主脚本并配置 `cc-epub` 全局命令
- SHA256 校验脚本完整性

### 3. 验证
```bash
cc-epub --help
opencc --version
```

---

## 三、核心用法

### 基本转换（对应便签 ③⑦）
将繁体 EPUB 放入 `Download/`，在 Termux 中执行：

```bash
cc-epub /sdcard/Download/三体.epub
# 产物：Download/E-book/三体-cc.epub
```

### 设置短命令 `cc`（对应便签 ⑥）
在 `~/.bashrc` 或 `~/.zshrc` 中添加别名：

```bash
echo "alias cc='cc-epub'" >> ~/.bashrc
source ~/.bashrc
# 之后即可：cc 三体.epub
```

### 香港繁体书籍
```bash
cc-epub /sdcard/Download/明報版三體.epub --mode hk2s
```

### 针对 Kindle Paperwhite 优化（对应便签 ②）
默认即开启 Kindle 优化（`--kindle-opt`），无需额外参数。如需显式指定设备：

```bash
cc-epub /sdcard/Download/書.epub --device kindle
```

### 控制文件体积 < 200MB（对应便签 ④）
```bash
# 默认：超过 150MB 自动压缩图片
cc-epub /sdcard/Download/大書.epub

# 图片过多的书可关闭压缩后手动处理
cc-epub /sdcard/Download/大書.epub --no-compress
```

---

## 四、推送到 Kindle（对应便签 ④）

1. 电脑/手机浏览器访问 **[sendto.kindle.com](https://sendto.kindle.com)**，登录亚马逊账号。
2. 将 `Download/E-book/书名-cc.epub` 拖拽上传。
3. Kindle Paperwhite 第12代连接 Wi-Fi 同步即可看到新书。

> ⚠️ **硬性限制**：单文件 **< 200MB**，源文件必须 **DRM-Free**，编码为 **UTF-8**。

---

## 五、复杂排版失败处理（对应便签 ⑧）

若遇到复杂排版导致转换/推送失败：

```bash
# 1. 先用 --dry-run 检查文件结构
cc-epub /sdcard/Download/問題書.epub --dry-run

# 2. 开启详细日志定位问题
cc-epub /sdcard/Download/問題書.epub --verbose --log /sdcard/Download/convert.log

# 3. 重建目录
cc-epub /sdcard/Download/問題書.epub --toc

# 4. 仍失败则用 Calibre 预处理：EPUB → EPUB 清理格式后再转换
```

---

## 六、批量处理（对应便签 ⑤⑨）

```bash
# 整个书库一键转换（3 个并行任务）
cc-epub --batch /sdcard/Download/書庫 --parallel 3

# 中断后断点续转
cc-epub --batch /sdcard/Download/書庫 --resume

# 跳过已转换文件
cc-epub --batch /sdcard/Download/書庫 --skip-existing
```

---

## 七、GitHub 部署（对应便签 ⑨）

仓库地址：`https://github.com/epubcc/cc-epub`

```bash
git clone https://github.com/epubcc/cc-epub.git
cd cc-epub
bash install.sh          # 本地安装
bash pack.sh             # 打包发布（生成 cc-epub.zip）
```

---

## 八、快速排查

| 现象 | 解决方案 |
| :--- | :--- |
| 找不到命令 | 重新运行 `bash install.sh`，确认 `$PREFIX/bin` 在 PATH |
| 推送后白页 | 用 Calibre 做 "EPUB→EPUB" 预处理清理格式 |
| 文件 > 200MB | 启用图片压缩，或手动降低图片质量 |
| 中文乱码 | 源文件为 Big5 时用 `--encoding big5` |
| 封面仍是繁体 | 检查 `content.opf` 元数据是否转换 |

---

## 许可证
MIT License
