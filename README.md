# cc-epub —— 港台繁体 EPUB 转换工具（最终版）

将**港台繁体中文 EPUB** 一键转换为 **简体 + 横排 + 首行缩进**，适配 **Kindle Paperwhite 第12代**。
底层基于 **OpenCC**（`tw2sp`：台湾正体含惯用词 → 简体，也覆盖港版）。

## ✅ 查验状态

- 静态扫描：无 `re.*` 参数顺序问题
- 语法检查：`compileall` + `py_compile` 均通过
- 测试：**21/21 通过**（含真实端到端演示）
- 端到端：`軟體 滑鼠 這是一個測試` → `软件 鼠标 这是一个测试` ✅
- 安装脚本：`test_install.py` **8/8 通过**（覆盖式安装幂等、语法错误在覆盖前被拒绝、alias 幂等、源不存在报错）✅

## 🚀 Termux 完整操作步骤

### 第一步：安装 Termux
从 **F-Droid** 安装 Termux（**不要从 Google Play 装**，已停更会报错）。
启动后授予存储权限：

```bash
termux-setup-storage   # 允许访问手机存储（/sdcard）
```

### 第二步：安装依赖

```bash
pkg update && pkg upgrade -y
pkg install -y python opencc git
pip install opencc-python-reimplemented   # 若 import opencc 报错再装
```

> `opencc` 走 Termux 系统包（`pkg install opencc`）比 pip 编译更快。

### 第三步：覆盖式安装脚本（★推荐用 install.sh）

> **目标**：把 `cc_epub.py` 装到 `~/bin/` 并实现"**覆盖式升级**"——
> 后续脚本更新时，只需把新版本 `cc_epub.py` 丢到 Download，再跑一次 install.sh 即可覆盖，无需手动 mv/cp/chmod。

把 `cc_epub.py` 和 `install.sh` 传到 `~/storage/shared/Download/`，然后：

```bash
cd ~/storage/shared/Download

# ★一行完成：强制覆盖安装 + 语法自检 + 自动加 cc 别名
bash install.sh cc_epub.py
```

`install.sh` 会自动做 5 件事：
1. 校验源脚本存在、`python` 可用
2. **先语法自检** → 通过才覆盖（坏版本**不会**覆盖掉好版本）
3. `mkdir -p ~/bin` + `cp -f` **强制覆盖**已有脚本 + `chmod +x`
4. 覆盖前给旧版打 `.bak`（成功后自动删除）
5. 幂等追加 `alias cc=...`（**重复执行不会重复添加**）

**升级脚本时**就这样：

```bash
# 把新 cc_epub.py 传到 Download 后，再跑一次即可
bash install.sh cc_epub.py
```

<details><summary>不想用 install.sh？手动覆盖版（等价命令）</summary>

```bash
mkdir -p ~/bin
cp -f ~/storage/shared/Download/cc_epub.py ~/bin/cc_epub.py   # -f = 强制覆盖
chmod +x ~/bin/cc_epub.py
echo 'alias cc="python ~/bin/cc_epub.py"' >> ~/.bashrc       # 首次才需要
```
</details>

### 第四步：执行转换（对齐便签的 `cc 书名`）

```bash
cd ~/storage/shared/Download/E-book

cc 香港書籍.epub              # 默认 tw2sp → 香港書籍-cc.epub
cc 香港書籍.epub -c hk2s      # 港版源文件可用此
cc 香港書籍.epub -o /tmp/out.epub  # 自定义输出
```

> 装好后直接用 `cc`（别名），无需再敲 `python ~/bin/...`。
> 输出默认落在 `Download/E-book/书名-cc.epub`，运行完会打印自检 ✅。

### 第五步（可选）：新开会话验证

别名写入 `~/.bashrc`，**新开一个 Termux 会话**即生效（或 `source ~/.bashrc`）。

```bash
cc --help   # 能看到用法即安装成功
```

### 第六步：推送到 Kindle

打开 **Send to Kindle**（网页/App/邮箱）上传 `书名-cc.epub`。
⚠️ 单文件 **≤ 200MB**；超大漫画/扫描版建议先拆分。

## 📋 参数说明

| 参数 | 说明 | 默认 |
|------|------|------|
| `input` | 输入 EPUB（必填）| — |
| `-o / --output` | 输出路径（文件或目录）| `Download/E-book/书名-cc.epub` |
| `-c / --config` | OpenCC 配置 | `tw2sp`（港版可用 `hk2s`）|
| `-l / --lang` | 输出元数据语言 | `zh-CN` |
| `--no-check` | 跳过自检 | 关 |

## ⚠️ 注意事项

1. **扫描页/图片内文字**：OpenCC 无法识别，需先 OCR
2. **200MB 限制**：Send to Kindle 单文件上限
3. **`tw2sp` vs `t2s`**：目标含"大陆用词"务必用 `tw2sp`（軟體→软件）
4. 输出 EPUB 已规范（`mimetype` 首个未压缩 + 横排 CSS + 语言元数据），Send to Kindle 转 KFX 排版更稳

## 🔗 相关链接

- OpenCC：https://github.com/BYVoid/OpenCC
- Termux：https://f-droid.org/en/packages/com.termux/
- Send to Kindle：https://www.amazon.co.jp/sendtokindle
