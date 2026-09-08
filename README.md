# cc-epub

**EPUB 竖排转横排 + 繁体转简体 一键转换工具**

专为 Termux 环境设计，支持港台竖排 EPUB 书籍一键转换为横排简体中文版本，完美解决首行缩进叠加、全角空格残留、竖排 CSS 兼容等问题。

---

## 功能特性

- **竖排转横排**：自动检测并修改 CSS 中的 `writing-mode` 属性，将竖排（`vertical-rl`）强制转为横排（`horizontal-tb`）
- **繁转简**：调用 OpenCC 将繁体中文（含台湾繁体）转换为简体中文
- **全角空格清洗**：清除段落首尾的全角空格（`\u3000`）和半角空格，避免与 CSS `text-indent` 叠加导致 4em 缩进
- **CSS 暴力覆盖**：在每个 HTML 文件的 `<head>` 中注入带 `!important` 的 CSS，彻底根除缩进叠加问题
- **阅读方向修正**：自动修改 OPF 文件中的 `page-progression-direction`，将 `rtl` 修正为 `ltr`
- **KFX 兼容**：去除可能导致 Kindle 渲染白页的复杂 CSS3 属性，统一使用基础样式
- **依赖自动检测**：运行前自动检查并安装 `beautifulsoup4` 依赖

---

## 环境要求

- **系统**：Termux（Android）
- **依赖**：Python 3、opencc-tools、zip/unzip、libxslt

---

## 快速开始

### 1. 一键部署

将 `cc.py` 和 `install.sh` 放在同一目录下，在 Termux 中运行：

```bash
bash install.sh
```

脚本将自动完成以下操作：

1. 更新 Termux 包列表并安装 `python`、`opencc-tools`、`zip`、`unzip`、`libxslt`
2. 安装 Python 库 `beautifulsoup4` 和 `lxml`
3. 将 `cc.py` 复制到 Termux 全局可执行路径，配置 `cc` 快捷命令

### 2. 使用转换

部署完成后，在 Termux 中运行以下命令即可转换：

```bash
cc 书名.epub
```

或指定完整路径：

```bash
python cc.py /sdcard/Download/射雕英雄传.epub
```

### 3. 查看输出

转换后的文件将自动保存至：

```
/storage/emulated/0/Download/E-book/
```

文件名为：`书名-简中.epub`

---

## 文件说明

| 文件 | 说明 |
|------|------|
| `cc.py` | 核心转换脚本，支持竖排转横排、繁转简、CSS 重置 |
| `install.sh` | Termux 一键部署脚本，自动安装依赖并配置命令 |

---

## 进阶用法

### 批量转换

将多个 EPUB 文件放在同一目录下，使用循环批量处理：

```bash
for f in *.epub; do
    cc "$f"
done
```

### 手动运行（不部署）

如果不希望配置全局命令，可以直接运行：

```bash
python cc.py 书名.epub
```

---

## 注意事项

1. **文件路径**：Termux 访问手机存储需要通过 `termux-setup-storage` 授权
2. **依赖安装**：如果自动安装 `beautifulsoup4` 失败，请手动运行 `pip install beautifulsoup4`
3. **OpenCC 配置**：确保 Termux 中已安装 `opencc-tools` 包，且 `t2s.json` 或 `tw2s.json` 配置文件可用
4. **EPUB 兼容性**：本工具适用于标准 EPUB 3.0 格式的书籍，部分非标准 EPUB 可能无法完美处理
5. **Kindle 转换**：转换后的 EPUB 可通过 "Send to Kindle" 服务上传至 Kindle，建议在使用 Kindle Previewer 二次检查排版效果

---

## 故障排除

### 提示 `command not found: cc`

重启 Termux 或运行 `source ~/.bashrc` 重新加载配置。

### 提示 `opencc: command not found`

运行 `pkg install opencc-tools` 安装 OpenCC 工具。

### 转换后排版仍有问题

部分出版社的 EPUB 可能包含非标准的 CSS 或嵌套结构，建议手动检查转换后的 HTML 文件，确认 CSS 是否正确注入。

### 繁转简结果不准确

OpenCC 的 `tw2s` 配置针对台湾繁体优化。如果遇到特定词汇转换不准确的情况，可以尝试使用 `t2s` 配置（通用繁体转简体）。

---

## 技术实现

### 处理流程

1. **解压** EPUB（本质是 ZIP 压缩包）
2. **文本清洗**：遍历所有 HTML 文件中的 `<p>`、`<div>`、`<td>` 标签，清除首尾全角/半角空格
3. **繁转简**：将清洗后的文本通过临时文件传递给 `opencc` 命令行工具进行转换
4. **CSS 注入**：在每个 HTML 文件的 `<head>` 中注入带 `!important` 的横排 CSS，强制覆盖原有样式
5. **OPF 修正**：修改阅读方向为 `ltr`（从左到右）
6. **重新打包**：按照 EPUB 规范重新打包（`mimetype` 文件必须第一个写入且不使用压缩）

### 解决的核心问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 首行缩进变成 4em | CSS `text-indent: 2em` + 2个全角空格叠加 | 先清空格，再注入 `!important` CSS 强制覆盖 |
| 竖排 CSS 残留 | `writing-mode: vertical-rl` 未替换 | 全局替换为 `horizontal-tb` |
| Kindle KFX 白页 | 复杂 CSS3 属性不被 KFX 支持 | 统一使用基础 CSS 属性，去除复杂样式 |
| 繁转简污染标签 | 对 HTML 标签属性进行了转换 | 仅在 BeautifulSoup DOM 树的文本节点上操作 |

---

## 许可证

MIT License
