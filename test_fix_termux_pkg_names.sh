#!/bin/bash
# 单测：fix_termux_pkg_names（从 install.sh 提取逻辑验证）
# 验证：Termux 下裸 "opencc" 被改写为 "libopencc"，其他包名不受影响

fix_termux_pkg_names() {
    local out=""
    for pkg in "$@"; do
        if [ "$PKG" = "termux" ] && [ "$pkg" = "opencc" ]; then
            echo "WARN: Termux 无 'opencc' 包，自动改用 'libopencc'" >&2
            out="$out libopencc"
        else
            out="$out $pkg"
        fi
    done
    echo "${out# }"
}

echo "=== 测试 1：Termux 下误传裸 opencc → 应改写为 libopencc ==="
PKG=termux
result=$(fix_termux_pkg_names python git unzip opencc opencc-tools 2>/dev/null)
echo "结果: $result"
[ "$result" = "python git unzip libopencc opencc-tools" ] && echo "✅ PASS" || { echo "❌ FAIL"; exit 1; }

echo
echo "=== 测试 2：正确包名 libopencc 应保持不变 ==="
result=$(fix_termux_pkg_names python libopencc opencc-tools 2>/dev/null)
echo "结果: $result"
[ "$result" = "python libopencc opencc-tools" ] && echo "✅ PASS" || { echo "❌ FAIL"; exit 1; }

echo
echo "=== 测试 3：非 Termux（apt）下 opencc 保持原样（由 apt 分支处理）==="
PKG=apt
result=$(fix_termux_pkg_names opencc libopencc-dev 2>/dev/null)
echo "结果: $result"
[ "$result" = "opencc libopencc-dev" ] && echo "✅ PASS" || { echo "❌ FAIL"; exit 1; }

echo
echo "✅ fix_termux_pkg_names 防御逻辑全部通过"
