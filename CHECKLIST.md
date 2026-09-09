# 发布前检查清单

## GitHub 仓库设置
- [ ] 创建仓库：`https://github.com/epubcc/cc-epub`
- [ ] 分支：main（默认）
- [ ] License：MIT（已包含）
- [ ] Description：`港台繁体 EPUB → 简体横排，Kindle 优化 | Termux + OpenCC`
- [ ] Topics：`epub`, `opencc`, `kindle`, `traditional-to-simplified`, `termux`, `chinese`

## 上传文件清单
- [ ] README.md
- [ ] LICENSE
- [ ] .gitignore
- [ ] .github/workflows/ci.yml
- [ ] scripts/install.sh
- [ ] scripts/cc.sh
- [ ] scripts/convert.py
- [ ] scripts/uninstall.sh
- [ ] config/opencc-chain.json
- [ ] config/kindle-css.css
- [ ] examples/usage.md

## 首次推送命令
```bash
cd cc-epub
git init
git add .
git commit -m "feat: initial release v1.0"
git branch -M main
git remote add origin https://github.com/epubcc/cc-epub.git
git push -u origin main
```
