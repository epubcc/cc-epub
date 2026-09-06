#!/usr/bin/env bash
# pack.sh —— 将 cc-epub 项目打包为 cc-epub.zip
# 用法: bash pack.sh
set -euo pipefail

cd "$(dirname "$0")"

# ===== 配置 =====
ARCHIVE="cc-epub.zip"
PREFIX="cc-epub"          # 打包后的顶层目录名
CHECKSUM="SHA256SUMS"

# ===== 声明要打包的文件清单（相对于项目根）=====
INCLUDE=(
    "cc-epub.sh"
    "install.sh"
    "LICENSE"
    "README.md"
    "CHANGELOG.md"
    "CONTRIBUTING.md"
    "GUIDE.md"
    "pack.sh"
    "lib/common.sh"
    "lib/args.sh"
    "lib/convert.sh"
    "lib/batch.sh"
    "tests/run_tests.sh"
    ".github/workflows/test.yml"
    "scripts/gen_sha256.sh"
)

# ===== 自动扫描子目录（tests/fixtures 等）=====
scan_dirs=("tests/fixtures" "tests")
for d in "${scan_dirs[@]}"; do
    if [ -d "$d" ]; then
        while IFS= read -r -d '' f; do
            INCLUDE+=("$f")
        done < <(find "$d" -type f -print0)
    fi
done

# ===== 清理旧产物 =====
rm -f "$ARCHIVE" "$CHECKSUM"

# ===== 构建临时舞台目录（保证标准顶层目录结构）=====
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$PREFIX"

for rel in "${INCLUDE[@]}"; do
    if [ ! -f "$rel" ]; then
        echo "  [WARN] 缺失: $rel （跳过）"
        continue
    fi
    dest="$STAGE/$PREFIX/$rel"
    mkdir -p "$(dirname "$dest")"
    cp "$rel" "$dest"
done

# ===== 压缩（排除自身的循环依赖）=====
(
    cd "$STAGE"
    # 不把旧的 SHA256SUMS / zip 打进包内
    find "$PREFIX" -name "$CHECKSUM" -delete 2>/dev/null || true
    zip -rq "$ARCHIVE" "$PREFIX"
    mv "$ARCHIVE" "$OLDPWD/$ARCHIVE"
)

# ===== 校验信息 =====
echo ""
echo "===== 打包完成 ====="
SIZE=$(stat -c%s "$ARCHIVE" 2>/dev/null || stat -f%z "$ARCHIVE")
COUNT=$(unzip -l "$ARCHIVE" | grep -c "$PREFIX/")
echo "归档: $(realpath "$ARCHIVE")"
echo "文件数: $COUNT"
echo "体积: $((SIZE / 1024)) KB"

# SHA256
SUM=$(sha256sum "$ARCHIVE" | awk '{print $1}')
echo "SHA256: $SUM"

# 结构完整性
echo ""
echo "===== 结构检查 ====="
unzip -t "$ARCHIVE" | tail -n 2

# 列出顶层内容
echo ""
echo "===== 顶层目录 ====="
unzip -l "$ARCHIVE" | grep "$PREFIX/" | grep -v "$PREFIX/tests/fixtures" | head -30

# 同步 SHA256SUMS（供发布校验）
{
    echo "$SUM  $ARCHIVE"
} > "$CHECKSUM"
echo ""
echo "已写入 $CHECKSUM"

# ===== Termux 传输提示 =====
cat <<'EOF'

===== 使用提示（Termux）=====
  将 cc-epub.zip 传到手机后:
    unzip cc-epub.zip
    cd cc-epub
    bash install.sh
  或直接分享: termux-open cc-epub.zip
EOF
