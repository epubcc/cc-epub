#!/data/data/com.termux/files/usr/bin/bash
# install.sh —— cc-epub v2.4 一键安装 + 自动更新检查
set -e

echo "=========================================="
echo " cc-epub 安装向导 (Termux / Linux / macOS)"
echo "=========================================="

# 0. 自动更新检查（每次运行：有更新则 git pull 后重启）
auto_update() {
    if [ -d .git ] && command -v git >/dev/null 2>&1; then
        echo "[0/7] 检查更新..."
        git fetch --quiet 2>/dev/null || return 0
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse '@{u}' 2>/dev/null || git rev-parse origin/main 2>/dev/null || true)
        if [ -n "$REMOTE" ] && [ "$LOCAL" != "$REMOTE" ]; then
            echo "  → 发现新版本，正在更新..."
            git pull --ff-only 2>/dev/null || git reset --hard "$REMOTE"
            echo "  → 更新完成，重新执行安装脚本"
            exec bash "$0" "$@"
        fi
        echo "  → 已是最新版本"
    fi
}
auto_update "$@"

# 1. 更新软件源索引（解决 "Unable to locate" 的根本原因）
echo ""
echo "[1/7] 更新软件源索引..."
if command -v pkg >/dev/null 2>&1; then
    pkg update -y || true
elif command -v apt >/dev/null 2>&1; then
    sudo apt update -y || true
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf makecache || true
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy || true
elif command -v brew >/dev/null 2>&1; then
    brew update || true
fi

# 2. 安装系统依赖（失败不退出，交给 install_opencc.py 降级）
echo ""
echo "[2/7] 安装系统依赖..."
if command -v pkg >/dev/null 2>&1; then
    pkg install -y python opencc git unzip || true
elif command -v apt >/dev/null 2>&1; then
    sudo apt install -y python3 opencc opencc-data libopencc-dev git unzip || true
elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3 opencc git unzip || true
elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm python opencc git unzip || true
elif command -v brew >/dev/null 2>&1; then
    brew install python opencc git unzip || true
fi

# 3. 可靠安装 opencc（核心修复：含降级 pip 方案）
echo ""
echo "[3/7] 确保 opencc 可用..."
python3 install_opencc.py

# 4. Python 依赖
echo ""
echo "[4/7] 安装 Python 依赖..."
pip install --upgrade pip
pip install opencc-python-reimplemented

# 5. 输出目录
echo ""
echo "[5/7] 创建输出目录..."
mkdir -p "$HOME/Download/E-book"

# 6. cc 别名
echo ""
echo "[6/7] 配置 'cc' 别名..."
SCRIPT="$(pwd)/cc_epub.py"
ALIAS="alias cc=\"python3 $SCRIPT\""
SHELL_RC=""
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$rc" ] && SHELL_RC="$rc" && break
done
SHELL_RC="${SHELL_RC:-$HOME/.bashrc}"
if ! grep -q "cc_epub.py" "$SHELL_RC" 2>/dev/null; then
    printf "\n# cc-epub\nalias cc=\"python3 %s/cc_epub.py\"\n" "$(pwd)" >> "$SHELL_RC"
fi
echo "  别名已写入 $SHELL_RC"
echo "  重新打开终端 或执行: source $SHELL_RC"

echo ""
echo "=========================================="
echo " 安装完成！建议运行自检："
echo "   python3 verify_note.py"
echo "   bash run_tests.sh"
echo "=========================================="
