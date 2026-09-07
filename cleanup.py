#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""清理运行/测试产生的临时文件，保留交付源码。"""
import os, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
KEEP = {"cc_epub.py", "test_cc_epub.py", "lint_args.py", "demo.py",
        "verify.sh", "README.md", "cleanup.py"}

for name in os.listdir(HERE):
    if name in KEEP:
        continue
    path = os.path.join(HERE, name)
    if os.path.isdir(path):
        shutil.rmtree(path)
    elif os.path.isfile(path):
        os.remove(path)
print("已清理临时文件，保留交付源码：")
for n in sorted(KEEP):
    print("  " + n)
