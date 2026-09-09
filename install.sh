#!/usr/bin/env bash
# cc-epub 一键部署脚本 v2
# 用法: bash install.sh
# 用户名: epubcc | 仓库名: cc-epub

set -e

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[*]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo "  cc-epub 部署开始"
echo "━━━━━━━━━━━━━━━━━━━━━━━"

# 环境检测
if [ -d "/data/data/com.termux" ]; then
    ENV_NAME="Termux"
elif [ "$(uname)" = "Darwin" ]; then
    ENV_NAME="macOS"
else
    ENV_NAME="Linux"
fi
info "检测到运行环境: $ENV_NAME"

# 1. 更新软件包
info "[1/5] 更新软件包列表..."
if [ "$ENV_NAME" = "Termux" ]; then
    pkg update -y >/dev/null 2>&1 || true
elif command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y >/dev/null 2>&1 || true
fi

# 2. 安装系统依赖
info "[2/5] 安装依赖 (python, git, zip, unzip, libopencc, opencc-tools)..."
if [ "$ENV_NAME" = "Termux" ]; then
    pkg install -y python git zip unzip libopencc opencc-tools
elif [ "$ENV_NAME" = "macOS" ]; then
    command -v brew >/dev/null 2>&1 && brew install python git opencc
else
    sudo apt-get install -y python3 git zip unzip libopencc-dev 2>/dev/null || \
    warn "请手动安装 libopencc / opencc"
fi

# 3. 安装 Python 库
info "[3/5] 安装 Python 库 (beautifulsoup4)..."
PIP_URL="--index-url https://pypi.tuna.tsinghua.edu.cn/simple"
python -m pip install $PIP_URL beautifulsoup4 2>/dev/null || \
    python -m pip install beautifulsoup4

# 4. 配置 cc 快捷命令（三保险：PATH + alias + wrapper）
info "[4/5] 配置 cc 快捷命令..."
mkdir -p "$HOME/bin"

for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$rc" ] || continue
    grep -qF 'export PATH="$HOME/bin:$PATH"' "$rc" 2>/dev/null || \
        echo 'export PATH="$HOME/bin:$PATH"' >> "$rc"
    grep -qF "alias cc=" "$rc" 2>/dev/null || \
        echo "alias cc='python \$HOME/cc-epub/cc.py'" >> "$rc"
done
export PATH="$HOME/bin:$PATH"

# wrapper script（优先级最高，覆盖系统 cc / clang）
cat > "$HOME/bin/cc" << 'WRAPPER'
#!/bin/bash
# 自动定位 cc.py（支持 git clone 到 ~/cc-epub 或当前目录）
for p in "$HOME/cc-epub/cc.py" "$(dirname "$(readlink -f "$0")")/cc.py" "./cc.py"; do
    [ -f "$p" ] && exec python "$p" "$@"
done
echo "[-] 找不到 cc.py，请确认已克隆仓库: git clone https://github.com/epubcc/cc-epub.git ~/cc-epub"
exit 1
WRAPPER
chmod +x "$HOME/bin/cc"

# 5. 校验 opencc 配置
info "[5/5] 校验 OpenCC 配置..."
if command -v opencc >/dev/null 2>&1; then
    if [ -f "$(pkg-config --variable=datadir opencc 2>/dev/null)/tw2sp.json" ] || \
       opencc -c tw2sp.json -i /dev/null -o /dev/null 2>/dev/null; then
        info "tw2sp.json 配置可用"
    else
        warn "未找到 tw2sp.json，执行: pkg reinstall opencc-tools"
    fi
else
    warn "opencc 命令不可用，请确认 libopencc + opencc-tools 已安装"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}✅ 部署完成！${NC}"
echo ""
echo "使用方法:"
echo "  cc 书名.epub"
echo "  cc ~/storage/shared/Download/原子习惯.epub"
echo ""
echo "输出: ~/storage/shared/Download/E-book/书名-简中.epub"
echo ""
echo "💡 若提示 'command not found'，请运行: source ~/.bashrc  或重启 Termux"
echo "━━━━━━━━━━━━━━━━━━━━━━━"
