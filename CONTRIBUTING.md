# Contributing Guide

感谢你对 CC-EPUB 的关注！以下是参与贡献的指南。

## 开发环境

推荐使用 Linux 或 macOS 进行开发，主要依赖：

```bash
sudo apt install opencc unzip zip python3 imagemagick shellcheck
```

## 项目结构

```
cc-epub/
├── cc-epub.sh          # 主入口（薄壳）
├── install.sh          # 安装脚本
├── lib/
│   ├── common.sh       # 颜色、日志、工具函数
│   ├── args.sh         # 参数解析
│   └── convert.sh      # 核心转换逻辑
├── tests/
│   ├── run_tests.sh    # 测试运行器
│   └── fixtures/       # 测试用 EPUB 样本
├── .github/workflows/  # CI 配置
├── README.md
├── CHANGELOG.md
└── CONTRIBUTING.md
```

## 代码规范

1. **ShellCheck 零警告**：提交前务必通过 `shellcheck *.sh lib/*.sh tests/*.sh`。
2. **`set -euo pipefail`**：所有脚本顶部必须包含。
3. **命名约定**：
   - 常量：`UPPER_SNAKE_CASE`
   - 函数：`Verb_first` 或 `CCEPUB_namespace`
   - 局部变量：`local` 声明
4. **可移植性**：
   - 使用 `SED_I()` 替代 `sed -i`
   - 避免 Bash 4+ 专属特性（考虑 macOS 兼容）
5. **日志**：使用 `info/success/warn/error/verbose/step` 函数，不要直接 `echo`。

## 提交规范

使用 [Conventional Commits](https://www.conventionalcommits.org/)：

- `feat:` 新功能
- `fix:` 缺陷修复
- `refactor:` 重构
- `test:` 测试
- `docs:` 文档
- `chore:` 杂项

示例：
```
feat(convert): 新增 Kobo 设备适配
fix(args): 修复 --parallel 参数解析
```

## 测试

**提交前必须运行完整测试套件：**

```bash
bash tests/run_tests.sh
```

新增功能应同步添加测试用例。

## 报告问题

请使用 GitHub Issues，包含：
- 设备型号与 Termux 版本
- CC-EPUB 版本（`cc-epub --help` 首行）
- 完整错误日志（`--verbose` 输出）
- 复现步骤

## 许可证

MIT License。提交即表示同意你的贡献在 MIT 许可证下发布。
