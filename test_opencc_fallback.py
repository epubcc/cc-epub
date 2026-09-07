"""
模拟「Unable to locate package opencc」场景：系统无 opencc CLI，
验证 install_opencc.py 的降级 pip 方案能否让 cc-epub 正常工作。
"""
import os, subprocess, sys, shutil
from pathlib import Path

print("=" * 56)
print("模拟: 系统里找不到 `opencc` 包 (locate 失败)")
print("=" * 56)

# 确认当前 opencc CLI 是否真的不可用（本环境可能装了，先记录）
cli = shutil.which("opencc")
print(f"\n系统 opencc CLI: {cli or '未安装 (这正是 Termux locate 失败的场景)'}")

# 关键：即使 CLI 不存在，Python 绑定也应能独立工作
print("\n--- 验证 Python 绑定独立性 ---")
r = subprocess.run([sys.executable, "-c",
    "from opencc import OpenCC; "
    "print('CONVERT:', OpenCC('tw2sp.json').convert('這是一個繁體測試，包含軟體'))"],
    capture_output=True, text=True)
print(r.stdout.strip() or r.stderr.strip())
ok = "CONVERT: 这是一个简体测试，包含软件" in r.stdout
print(f"Python 绑定独立可用: {'✅ 是 (无需系统 opencc)' if ok else '❌ 否'}")

# 模拟 pip 降级安装（若未装则装）
print("\n--- 模拟降级: pip install opencc-python-reimplemented ---")
if not ok:
    subprocess.run([sys.executable, "-m", "pip", "install",
                    "opencc-python-reimplemented"], check=False)

# 最终：跑完整的 verify_note 断言
print("\n--- 最终验证: cc_epub 端到端 ---")
here = Path(__file__).parent
res = subprocess.run([sys.executable, str(here / "verify_note.py")],
                     capture_output=True, text=True)
out = res.stdout + res.stderr
print(res.stdout[-1500:] if res.stdout else res.stderr[-1500:])
passed = out.count("✅")
failed = out.count("❌")
print(f"\n汇总: ✅ {passed} / ❌ {failed}")
sys.exit(0 if failed == 0 else 1)
