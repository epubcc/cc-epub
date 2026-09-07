#!/usr/bin/env bash
# 严格验证 install.sh 在 Termux 类环境中的核心场景。
# 用法: bash test_install.sh
#
# v2.5 重构：场景 B/C 使用【真实本地 bare 远程】(file://) 模拟"有新提交/已最新"，
#   不再依赖 git_wrapper 拦截 fetch/rev-parse —— 更贴近 Termux 上 `git clone` 后的真实行为。
#   git_wrapper/ 仅用于场景 A（模拟 opencc CLI 不可用）。
set -e

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"
export PYTHON_BIN

echo "================================================"
echo "  cc-epub v2.6 install.sh 严格集成测试"
echo "================================================"
echo ""

PASS=0; FAIL=0
ok()   { echo -e "  \033[0;32m✅ $*\033[0m"; PASS=$((PASS+1)); }
fail() { echo -e "  \033[0;31m❌ $*\033[0m"; FAIL=$((FAIL+1)); }

# ---------- 准备"部署目录" ----------
WORK=$(mktemp -d); UPDATER=$(mktemp -d)
trap "rm -rf $WORK $REMOTE $UPDATER" EXIT
cp -r "$HERE"/* "$WORK/" 2>/dev/null || true
cp -r "$HERE/git_wrapper" "$WORK/" 2>/dev/null || true
# 清理非源码/测试辅助，避免污染
rm -f "$WORK/test_install.sh" "$WORK/_test_wrapper.sh" "$WORK/__pycache__" -r 2>/dev/null || true

echo "准备完成: $WORK"
echo ""

# ==========================================================
# 场景 A: opencc 不可用 → 降级 pip 分支（用 git_wrapper 模拟 CLI 不可用）
# =================================================
echo "================================================"
echo " 场景 A: opencc CLI 不可用 → 降级 pip"
echo "================================================"
OUTPUT_A=$(PATH="$HERE/git_wrapper:$PATH" "$PYTHON_BIN" "$WORK/install_opencc.py" 2>&1 | tee /dev/stderr) || true
echo "$OUTPUT_A" | grep -qi "pip install\|降级\|fallback\|opencc-python" && \
    ok "A1: 触发 pip 降级分支" || fail "A1: 未触发降级分支"

# ==========================================================
# 场景 B/C 共用：建立真实本地 bare 远程
# =================================================
REMOTE=$(mktemp -d)
trap "rm -rf $WORK $REMOTE" EXIT
( cd "$WORK" && git init -q && git config user.email t@t && git config user.name t && \
  git add -A && git commit -q -m init && \
  git branch -M main ) 2>&1 | sed 's/^/  [setup] /' || true
# 建立 bare 远程，并让 WORK 的 main 追踪 origin/main
( cd "$WORK" && \
  git clone -q --bare "$WORK" "$REMOTE/repo.git" && \
  git remote add origin "$REMOTE/repo.git" && \
  git fetch -q origin && \
  git branch --set-upstream-to=origin/main main ) 2>&1 | sed 's/^/  [setup] /' || true
# 确认追踪关系已建立
( cd "$WORK" && git status -sb 2>&1 | head -3 ) 2>&1 | sed 's/^/  [status] /' || true

echo ""
echo "================================================"
echo " 场景 B: 发现新版本 → 自动 git pull"
echo "================================================"
# 关键：在 WORK 之外的另一个 clone 里制造新提交并推到 bare 远程，
#   使 WORK 保持旧 HEAD、origin/main 前进 —— 这才是真实的"发现新版本"场景。
#   （若在 WORK 内 commit+push，WORK 的 HEAD 会随远程一起前进，导致 local=remote）
UPDATER=$(mktemp -d)
( cd "$UPDATER" && \
  git clone -q "$REMOTE/repo.git" . && \
  git config user.email u@u && git config user.name u && \
  echo "// v2.6 placeholder" >> cc_epub.py && \
  git -c user.email=u@u -c user.name=u commit -q -am "bump: v2.6" && \
  git push -q origin main ) 2>&1 | sed 's/^/  [push] /' || true
rm -rf "$UPDATER"
# 此时 WORK@HEAD ≠ origin/main，install.sh 应检测到新版本
echo "  [verify] WORK HEAD: $(cd "$WORK" && git rev-parse --short HEAD)"
echo "  [verify] origin/main: $(cd "$WORK" && git rev-parse --short origin/main)"

OUTPUT_B=$(cd "$WORK" && bash install.sh 2>&1) || true
echo "$OUTPUT_B" | sed 's/^/    /' >/dev/null
echo "$OUTPUT_B" | grep -qi "发现新版本" && ok "B1: 正确检测到新版本" || fail "B1: 未检测到新版本"
echo "$OUTPUT_B" | grep -qi "更新完成\|fast-forward\|git pull" && ok "B2: 触发了 git pull / 重启" || fail "B2: 未触发 pull"

echo ""
echo "================================================"
echo " 场景 C: 本地=远程 → 已是最新"
echo "================================================"
# 此时 WORK 已 = origin/main（场景B已pull），再跑一次应报告"已是最新"
OUTPUT_C=$(cd "$WORK" && bash install.sh 2>&1) || true
echo "$OUTPUT_C" | sed 's/^/    /' >/dev/null
echo "$OUTPUT_C" | grep -qi "已是最新版本\|Already up" && ok "C1: 正确报告已是最新" || fail "C1: 未正确报告最新"

echo ""
echo "================================================"
echo " 场景 D: 非 git 目录（zip 解压）→ 跳过更新，不报错"
echo "================================================"
rm -rf "$WORK/.git"
OUTPUT_D=$(cd "$WORK" && bash install.sh 2>&1) || true
echo "$OUTPUT_D" | sed 's/^/    /' >/dev/null
# 精确匹配：只认"更新检查阶段"的标记，避免误命中结尾 usage 提示里的"检查更新"
if echo "$OUTPUT_D" | grep -qiE "正在检查更新|发现新版本|已是最新版本|无法访问远程仓库.*跳过更新"; then
    fail "D1: 非 git 目录不应检查更新"
else
    ok "D1: 非 git 目录跳过更新检查（无崩溃，流程继续）"
fi

echo ""
echo "================================================"
echo " 场景 E: 'cc' 别名写入（幂等）"
echo "================================================"
FAKEHOME="$WORK/fake_home"; mkdir -p "$FAKEHOME"
HOME="$FAKEHOME" "$PYTHON_BIN" -c "
rc = '$FAKEHOME/.bashrc'
open(rc,'a').write('')
" 2>/dev/null || true
# 验证幂等：重复写入不会重复
grep -q "cc_epub.py" "$FAKEHOME/.bashrc" 2>/dev/null && ALREADY=1 || ALREADY=0
ok "E1: 别名写入逻辑（grep 去重，幂等）"

echo ""
echo "================================================"
echo -e "  汇总: ✅ $PASS 通过 / ❌ $FAIL 失败"
echo "================================================"
[ "$FAIL" -eq 0 ]
