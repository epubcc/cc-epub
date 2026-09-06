#!/usr/bin/env bash
# ============================================================
# gen_sha256.sh —— 发布前生成 SHA256SUMS（针对打包产物 cc-epub.zip）
# 用法: bash scripts/gen_sha256.sh
# 说明: 先确保已运行 pack.sh 生成 cc-epub.zip，本脚本将
#       其 SHA256 写入 SHA256SUMS，供发布校验使用。
# ============================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

TARGET="cc-epub.zip"
if [[ ! -f "$TARGET" ]]; then
    echo "[ERR ] $TARGET 不存在，请先运行 bash pack.sh 打包"
    exit 1
fi

# 同时记录各核心源文件哈希（便于审计）+ 产物哈希
: > SHA256SUMS
sha256sum "$TARGET" >> SHA256SUMS
for f in cc-epub.sh install.sh lib/common.sh lib/args.sh lib/convert.sh; do
    [[ -f "$f" ]] && sha256sum "$f" >> SHA256SUMS
done

echo "SHA256SUMS 已生成:"
cat SHA256SUMS
