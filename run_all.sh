#!/usr/bin/env bash
# v2.6 完整回归测试入口
set +e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
PY="${PYTHON_BIN:-python3}"

echo "================================================"
echo "  cc-epub v2.6 — 完整回归测试"
echo "================================================"
echo ""

TOTAL=0; PASS=0

run() {
    local name="$1"; shift
    TOTAL=$((TOTAL+1))
    echo "────────────────────────────────────────"
    echo "[$TOTAL] $name"
    echo "────────────────────────────────────────"
    if "$@" >/dev/null 2>&1; then
        echo "  ✅ PASS"
        PASS=$((PASS+1))
    else
        echo "  ❌ FAIL (输出见下)"
        "$@" 2>&1 | tail -15 | sed 's/^/    /'
    fi
}

run "便签需求验收 (verify_note.py)"        $PY verify_note.py
run "端到端测试 (run_tests.sh)"           bash run_tests.sh
run "install.sh 集成测试 (test_install.sh)" bash test_install.sh
run "OpenCC 降级方案 (test_opencc_fallback.py)" $PY test_opencc_fallback.py
run "Termux libopencc 包名验证"            $PY test_termux_libopencc.py

echo ""
echo "================================================"
echo "  汇总: ✅ $PASS / $TOTAL 通过"
echo "================================================"
[ "$PASS" -eq "$TOTAL" ]
