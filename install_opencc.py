#!/usr/bin/env python3
"""
install_opencc.py —— 诊断「Unable to locate package opencc」并可靠安装。

为什么会出现 "Unable to locate package opencc"？
  ★) 【最常见】Termux 官方仓库根本没有叫「opencc」的包！
       正确包名是「libopencc」(最新 1.4.2) + 「opencc-tools」(提供 CLI)
       -> 所以 `pkg install opencc` 必然报 "Unable to locate package opencc"
  1) 软件源索引未更新       -> 必须先 update
  2) 包名因发行版而异       -> Debian: libopencc-dev, Fedora: opencc, Arch: opencc
  3) 该源根本没收录          -> 降级到 pip 绑定（一定可用）

结论先行：cc-epub 用 Python 绑定「opencc-python-reimplemented」，
  该绑定自带字典数据，运行时【不强制】依赖系统 opencc CLI。
  策略：系统包优先（规范/性能），pip 保底（一定可用）。
"""
import shutil, subprocess, sys

# 复用 cc_epub 的归一化逻辑，避免配置名写法不一致（如 tw2sp vs tw2sp.json）
try:
    from cc_epub import _normalize_config
except ImportError:
    def _normalize_config(name):
        name = (name or "").strip().lower()
        if name.endswith(".json"):
            name = name[:-len(".json")]
        return name


def run(cmd, check=False):
    print(f"$ {cmd}")
    r = subprocess.run(cmd, shell=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"命令失败: {cmd}")
    return r.returncode == 0


def have(cmd):
    return shutil.which(cmd) is not None


def test_convert():
    """真正的可用性标准：字典能否转换。"""
    try:
        from opencc import OpenCC
        cfg = _normalize_config("tw2sp")   # -> "tw2sp"（不再拼成 tw2sp.json.json）
        out = OpenCC(cfg).convert("這是一個繁體測試，包含軟體")
        ok = "软件" in out
        print(f"    自检: {out}  -> {'OK ✅' if ok else '字典缺失 ❌'}")
        return ok
    except Exception as e:
        print(f"    自检失败: {e}")
        return False

def try_system(name, install_cmd, update_cmd=None):
    print(f"\n==> 尝试系统包管理器: {name}")
    if update_cmd:
        run(update_cmd, check=False)
    if run(install_cmd) and test_convert():
        return True
    return False

def pip_install():
    print("\n==> [降级] pip 安装 opencc-python-reimplemented")
    run("pip install --upgrade pip", check=False)
    return run("pip install opencc-python-reimplemented")

def main():
    print("=" * 56)
    print("诊断: Unable to locate package opencc  →  可靠安装方案")
    print("=" * 56)

    if have("opencc") and test_convert():
        print("\n✅ opencc 已就绪，无需安装。")
        return 0

    attempts = []
    if have("pkg"):
        # ★ Termux 正确包名: libopencc (1.4.2) + opencc-tools (CLI)
        #   `pkg install opencc` 必然失败，必须用 libopencc
        attempts.append(("Termux pkg",
                         "pkg update -y && pkg install -y libopencc opencc-tools",
                         "pkg update -y"))
    if have("apt"):
        attempts.append(("Debian/Ubuntu apt",
                         "sudo apt update -y && sudo apt install -y libopencc-dev opencc opencc-data",
                         "sudo apt update -y"))
    if have("dnf"):
        attempts.append(("Fedora dnf", "sudo dnf makecache && sudo dnf install -y opencc", "sudo dnf makecache"))
    if have("pacman"):
        attempts.append(("Arch pacman", "sudo pacman -Sy && sudo pacman -S --noconfirm opencc", "sudo pacman -Sy"))
    if sys.platform == "darwin" and have("brew"):
        attempts.append(("macOS brew", "brew update && brew install opencc", "brew update"))

    for name, install_cmd, update_cmd in attempts:
        if try_system(name, install_cmd, update_cmd) and test_convert():
            print(f"\n✅ 通过 {name} 安装成功。")
            return 0

    print("\n⚠️  系统包不可用或字典缺失，进入 pip 保底流程。")
    if pip_install() and test_convert():
        print("\n✅ pip 方案成功。cc-epub 可正常工作"
              "（即使系统无 `opencc` CLI，Python 绑定已含字典）。")
        return 0

    print("\n❌ 全部失败。排查：")
    print("   1) 换国内源: termux-change-repo / apt 清华源")
    print("   2) 手动更新索引: pkg update / apt update")
    print("   3) 搜索正确包名: pkg search opencc / apt-cache search opencc")
    return 1

if __name__ == "__main__":
    sys.exit(main())
