#!/usr/bin/env python3
"""
回归测试：Termux 包名契约
============================
用户反馈（事实核查 ✅）：
  1. Termux 官方仓库【没有】叫 "opencc" 的包
  2. 正确包名是 "libopencc"（最新 1.4.2）+ "opencc-tools"（提供 CLI）
  → 因此 `pkg install opencc` 必然报 "Unable to locate package opencc"

本测试锁定契约：install.sh / install_opencc.py 在任何情况下
都【不得】向 Termux 发出裸 "opencc" 包名，必须改用 libopencc。

验证方式：静态扫描脚本源码，断言不含 `pkg install ... opencc`（裸包名）。
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))

# 扫描目标：install.sh 与 install_opencc.py
TARGETS = ["install.sh", "install_opencc.py"]

# Termux 下"错误"的模式：单独出现 opencc 作为 pkg 安装目标
# 允许出现：libopencc、opencc-tools、opencc-python-reimplemented、注释说明、have("opencc")、command -v opencc
BAD_PATTERN = re.compile(r"(?<![-\w])opencc(?![-\w])")  # 裸单词 opencc

# 明确的"正确包名"必须存在
GOOD_LIBOPENCC = "libopencc"
GOOD_OPENCC_TOOLS = "opencc-tools"

def scan(path):
    """返回可能在 Termux 真实执行 `pkg install opencc` 的危险行。
    严格排除：
      - 注释行（以 # 开头）
      - 三引号文档字符串（含说明文字如 `pkg install opencc`）
      - 安全 token（libopencc / opencc-tools / python-reimplemented 等）
    只看真正会执行的安装命令。
    """
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    dangerous = []
    in_docstring = False
    for i, line in enumerate(lines, 1):
        stripped = line.strip()
        # 追踪三引号文档字符串
        if stripped.startswith('"""') or stripped.startswith("'''"):
            in_docstring = not in_docstring
            continue
        if in_docstring:
            continue
        # 跳过整行注释 / 空行
        if not stripped or stripped.startswith("#"):
            continue
        # 去掉行内注释部分（# 之后的内容），避免反引号说明误导
        code = stripped.split("#", 1)[0].strip()
        if not code:
            continue
        # 只关心真正"安装"的执行行
        if "pkg install" not in code and "$@" not in code:
            continue
        # 去掉已知安全的 token，再检查是否残留裸 "opencc"
        tmp = code
        for safe in ["libopencc", "opencc-tools", "opencc-python-reimplemented"]:
            tmp = tmp.replace(safe, "")
        if re.search(r"(?<![-\w])opencc(?![-\w])", tmp):
            dangerous.append((i, stripped))
    return dangerous

def main():
    print("=" * 60)
    print("契约回归测试：Termux 包名 = libopencc (1.4.2)，禁用裸 opencc")
    print("=" * 60)

    all_ok = True
    for fn in TARGETS:
        path = os.path.join(HERE, fn)
        if not os.path.exists(path):
            print(f"\n[SKIP] {fn} 不存在")
            continue
        src = open(path, encoding="utf-8").read()
        print(f"\n--- {fn} ---")

        # 断言 1：必须引用正确包名 libopencc / opencc-tools
        has_lib = GOOD_LIBOPENCC in src
        has_tools = GOOD_OPENCC_TOOLS in src
        print(f"  引用 'libopencc'      : {'✅' if has_lib else '❌'}")
        print(f"  引用 'opencc-tools'   : {'✅' if has_tools else '❌'}")
        if not (has_lib and has_tools):
            all_ok = False

        # 断言 2：扫描是否有"危险的裸 opencc 出现在安装命令中"
        dangerous = scan(path)
        if dangerous:
            print(f"  ❌ 发现 {len(dangerous)} 处可能在 Termux 执行 `pkg install opencc`:")
            for ln, text in dangerous:
                print(f"     第{ln}行: {text}")
            all_ok = False
        else:
            print(f"  ✅ 无裸 'opencc' 包名出现在安装命令中（已防御）")

    # 断言 3：fix_termux_pkg_names 函数存在（install.sh 的防御逻辑）
    install_sh = open(os.path.join(HERE, "install.sh"), encoding="utf-8").read()
    if "fix_termux_pkg_names" in install_sh and "自动改用" in install_sh:
        print("\n✅ install.sh 已含防御函数 fix_termux_pkg_names（裸opencc→libopencc）")
    else:
        print("\n❌ install.sh 缺少防御性包名改写")
        all_ok = False

    print("\n" + "=" * 60)
    if all_ok:
        print("✅ 全部契约通过：Termux 部署不会再触发")
        print("   'Unable to locate package opencc'")
        print("   正确包名：libopencc 1.4.2 + opencc-tools")
        return 0
    else:
        print("❌ 契约未满足，需修正包名逻辑")
        return 1

if __name__ == "__main__":
    sys.exit(main())
