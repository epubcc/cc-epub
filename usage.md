# 使用示例 & FAQ

## 基础用法

```bash
# 将「我的第一本书.epub」转换为简体横排
cc 我的第一本书

# 保留原字体的转换（不推荐，Kindle 可能白页）
cc 我的第一本书 --keep-font

# 指定自定义输出目录
cc 我的第一本书 --output /sdcard/Books
```

## 完整流程

```bash
# ① 首次部署（仅需一次）
termux-setup-storage
cd ~ && git clone https://github.com/epubcc/cc-epub.git
~/cc-epub/scripts/install.sh
source ~/.bashrc

# ② 将繁体 EPUB 文件放入 Downloads（通过数据线/网盘/蓝牙等）

# ③ 转换（书名不含 .epub 后缀）
cc 某本繁体小说

# ④ 转换完成后，文件位于：
#    ~/storage/downloads/E-book/某本繁体小说-简中.epub

# ⑤ 打开 Send to Kindle 网页版 → 上传该 .epub → 推送至 Kindle
```

## FAQ

### Q1：为什么转换后 Kindle 上还是白页？
- 原 EPUB 可能使用了 **DRM 加密**，请先去除 DRM
- 图片过大可能导致 KFX 转换失败，可尝试压缩图片后重试

### Q2：文件超过 200MB 怎么办？
- Send to Kindle 网页版限制 200MB
- 可通过压缩图片、移除多余字体文件来瘦身

### Q3：横排后标点位置不对？
- 本工具已自动处理 `writing-mode` 和 `text-orientation`
- 如仍有问题，可在 `config/kindle-css.css` 中追加针对性规则

### Q4：如何确认是台湾版还是香港版？
- 工具自动检测：文件名/内容含 `hk` → 使用 `hk2s.json`
- 其余默认 `t2s.json`（兼容台湾/香港通用）
- 可手动指定：修改 `convert.py` 中的 `detect_opencc_config()` 返回值

### Q5：转换后目录（NCX/Nav）是否正常？
- 是的，`convert.py` 只转换文本内容，目录结构和文件路径保持不变
- 章节标题的繁→简转换会自动反映到目录中

## 命令速查

| 命令 | 说明 |
|------|------|
| `cc 书名` | 标准转换（简体 + 横排 + 字体统一） |
| `cc 书名 --keep-font` | 保留原字体 |
| `cc -h` | 显示帮助 |
| `~/cc-epub/scripts/uninstall.sh` | 卸载 |
