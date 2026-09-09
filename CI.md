# CI 集成说明（GitHub Actions）

每次 `push` / `pull_request` 到 `main` / `master` 会自动跑：

1. **语法检查** — `compileall` 全量编译
2. **项目结构校验** — 确认 `converter.py / install.sh / test_converter.py` 齐全
3. **单元测试** — `test_converter.py`
4. **审计套件** — `audit.py`（若存在）
5. **端到端转换** — 在 `/tmp` 构造一个真实的 **繁体 + `vertical-rl`** EPUB，跑 `converter.py`，然后**直接读输出文件**断言：
   - `矽二極體 → 硅二极管`（词汇级繁转简）
   - `vertical-rl → horizontal-tb`（横排）
   - `mimetype` 为 zip 第一条（EPUB 规范）
6. **产物上传** — `run_check_result.json` 等（失败时也保留）
7. **绿灯门禁** — 若存在 `*_result.json`，其 `verdict` 必须为 green，否则 fail

在 **Python 3.9 / 3.11 / 3.12** 三个版本上并行跑。

## 工作流文件

`.github/workflows/check.yml`

## 本地预验证（无需 GitHub）

```bash
# 校验 workflow YAML 结构完整
python3 validate_workflow.py

# 完整模拟 CI 的端到端步骤（在 /tmp 真实转换）
python3 simulate_ci.py
```

这两个脚本覆盖了 CI 的全部关键逻辑，**本地通过 ≈ CI 会绿**。

## 接入步骤

1. 把本项目推到 GitHub 仓库 `epubcc/cc-epub`
2. GitHub 会自动识别 `.github/workflows/check.yml`
3. 此后每次 push / PR 自动触发
4. 在仓库 **Actions** 页查看结果

> 无需任何 secret / 第三方 service，纯 `actions/checkout@v4` + `setup-python@v5`。

## 设计原则

- **宁可 FAIL 也不假绿**：E2E 是真实解压读文件，不是 mock
- **多版本矩阵**：防止 Python 版本相关退化
- **产物保留**：`upload-artifact` 即使失败也上传，便于排查
- **fail-fast: false**：一个 Python 版本挂了不影响看其他的
