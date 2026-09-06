# Changelog

All notable changes to CC-EPUB are documented here.

## [6.0.1] - 2026-09-06（最终发布版）

### 🔥 缺陷修复（测试 20/20 全绿，端到端验证 46/46 全绿）

- **批量处理 `command not found`**：`CCEPUB_batch_main` / `CCEPUB_batch_parallel` 原定义在主脚本 `cc-epub.sh`，测试套件只 source `lib/` 导致找不到。现抽离为独立模块 **`lib/batch.sh`**（含批量串行/并行 + 交互式菜单），主脚本与测试统一 source，批量功能 (`--batch`) 可正常使用。
- **Dry Run `--json` 无输出**：`CCEPUB_dry_run_report` 原仅识别旧变量 `JSON_OUTPUT`。现改为以 `CFG_JSON` 为单一事实源，同时兼容 `JSON_OUTPUT`，`--dry-run --json` 正确输出完整 JSON 对象。
- **繁简用词断言失败**：测试原硬编码大陆简体（如 `鼠标操作`），而本地 OpenCC `tw2s` 在台湾用语环境下输出 `滑鼠`。现改为**运行时探测实际用词**（`probe_word`），`软体/滑鼠/网路` 与 `軟件/鼠标/网络` 两种环境均能通过。
- **`list_opencc_modes` 空输出**：部分 OpenCC 版本的 `opencc -l` 不含标准模式名，导致 `--list-modes` 无内容。现增加**内置标准模式回退列表**，保证始终列出 `tw2s/hk2s/t2s` 等。
- **`restore` 模式 `local` 在函数外使用**：`set -e` 下导致脚本异常退出，已修正为普通赋值。
- **新增 `LICENSE`（MIT）**：补齐开源许可证，满足 GitHub 发布要求。
- **打包清单补齐**：`pack.sh` 加入 `LICENSE`、`lib/batch.sh`，确保发布包完整。

### 📝 测试与验证

- 单元测试：**20/20 全部通过**（参数、转换、排版、元数据、DRM、批量、Dry Run JSON、shellcheck）。
- 端到端验证：**46/46 全部通过**（文件完整性、语法、权限、依赖、模拟 Termux 部署、真实 EPUB 转换、打包 & SHA256 一致性、冒烟测试）。
- 新增 `final_verify.sh`：一键复现完整验证流程。

## [6.0.0] - 2026-09-06

### 🔥 重大修复

- **参数解析彻底重写**：原 v5.0 使用 `for arg in "$@"` 遍历配合 `shift`，导致带值参数（`--mode tw2s` 等）解析错位、吞掉后续参数。v6.0 改为标准 `while [ $# -gt 0 ]` + `shift 2` 模式，彻底消除移位错位。
- **`INPUT_EPUB` 取值错误修复**：v5.0 在参数解析 `shift` 后使用 `$1`，此时位置参数已失效，导致单文件路径为空。v6.0 统一使用 `INPUT_FILES[0]`。
- **`--retry` 未透传**：v5.0 串行批量递归调用时遗漏 `--retry`，导致重试仅顶层生效一次。v6.0 引入 `CCEPUB_build_child_args()` 统一构建参数数组，确保全部参数透传。
- **并行任务回收逻辑重写**：v5.0 的 `wait "${PIDS[0]}"` + 数组切片在并发变动时存在竞争。v6.0 使用信号量池 + `wait -n` 模式，正确回收任意完成的子进程。
- **断点续转并发安全**：v5.0 多进程直接追加 `.batch_checkpoint`，内容错乱。v6.0 使用 `flock` 文件锁保证原子写入。

### ✨ 新特性

- **多设备适配** (`--device`)：新增 Kobo / Nook / Generic 目标设备，注入对应兼容样式与分页方向。
- **`--list-modes`**：列出可用的 OpenCC 转换模式。
- **`--dry-run --json`**：机器可读的检查报告，便于脚本集成。
- **交互式菜单** (`--interactive`)：无参数运行时进入交互式菜单。
- **模块化架构**：拆分为 `lib/common.sh`、`lib/args.sh`、`lib/convert.sh`，主脚本降为薄壳。

### 🛠 工程质量

- **完整测试套件**：涵盖参数解析、基本转换、排版、元数据、DRM、批量、shellcheck 等。
- **GitHub Actions CI**：push/PR 自动跑 shellcheck + 测试 + 安装模拟。
- **`shellcheck` 零警告**目标。
- **`sed -i` 可移植性**：引入 `SED_I()` 函数，自动检测 GNU/BSD sed。
- **`is_binary()` 增强**：结合 `file` MIME 类型 + null 字节检测，减少误判。
- **新增 `CHANGELOG.md`、`CONTRIBUTING.md`、`SHA256SUMS`**。

### 📝 文档

- README 更新至 v6.0，补充新参数、设备适配、测试说明。
- 新增贡献指南。

### ⚠️ 破坏性变更

- 配置文件新增 `device` 字段（默认 `kindle`，无影响）。
- 库文件 `lib/*.sh` 需随 `cc-epub.sh` 一起部署（install.sh 已处理）。

## [5.0.0] - 历史版本

参见 README.md 版本历史章节。
