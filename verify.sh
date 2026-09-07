#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"

echo "========================================================"
echo "  最终查验：语法检查 + 测试 + 端到端演示"
echo "========================================================"

# 0. 静态扫描（re.sub 参数顺序反模式；脚本可选）
echo ""
echo "[0/4] 静态扫描（re.* 参数顺序）..."
if [ -f lint_args.py ]; then
    python3 lint_args.py
else
    echo "  （跳过：lint_args.py 未包含在精简包中）"
fi

# 1. 语法检查（compileall）
echo ""
echo "[1/4] Python 语法检查（compileall）..."
python3 -m compileall -q cc_epub.py test_cc_epub.py && echo "  ✅ 语法 OK"

# 2. py_compile 单独确认
echo ""
echo "[2/4] py_compile 单独确认..."
python3 -m py_compile cc_epub.py && echo "  ✅ cc_epub.py 编译通过"

# 3. 依赖检查（opencc 是否可用）
echo ""
echo "[3/4] 依赖检查（opencc）..."
python3 -c "import opencc; print('  ✅ opencc', opencc.__version__ if hasattr(opencc,'__version__') else '已安装')" \
  || (echo "  ⚠️  未安装 opencc（Termux 需: pkg install opencc && pip install opencc-python-reimplemented）"; exit 0)

# 4. 运行测试 + 端到端
echo ""
echo "[4/4] 运行测试套件 + 端到端演示..."
python3 test_cc_epub.py

echo ""
echo "========================================================"
echo "  附加：运行 demo.py 演示转换效果"
echo "========================================================"
if [ -f demo.py ]; then
    python3 demo.py
else
    echo "  （跳过：demo.py 未包含在精简包中）"
fi
