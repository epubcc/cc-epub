# cc-epub v3.15.0

港台繁体 EPUB → Kindle 简中横排转换工具（Kindle PW12 / Send to Kindle）

## 特性

- **并行转换** — 后台多进程 OpenCC，速度提升 2-4x
- **文件锁** — flock / PID fallback 防并发冲突（已修复锁安全）
- **EPUB 预检** — mimetype + container.xml 合法性校验
- **智能封面** — 解析 OPF manifest 定位封面
- **自洁** — 自动清理 24h+ 残留临时目录
- **断点续传** — `--resume` 跳过已完成的文件
- **图片占比提示** — 图片 >70% 时给出优化建议
- **版本检查** — 每周一次 GitHub 版本检查，`--update` 自动备份
- **Termux 原生** — 不依赖 grep -P / realpath，shebang 便携

## 快速开始

