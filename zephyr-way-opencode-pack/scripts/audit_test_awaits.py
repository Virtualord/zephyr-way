#!/usr/bin/env python3
"""Audit the test suites for the bug that silently dropped assertions.

A helper that contains `await` but is called without one suspends at that point and
returns immediately. Every statement after the await in that function never runs, and
the suite reports a pass -- a suite that quietly stops checking is indistinguishable
from one that passes. scene_test.gd had exactly this and it cost three assertions.

Prints any such call site. Exit 1 if any are found.
"""
import re
import sys
from pathlib import Path

FUNC = re.compile(r'^func (\w+)\([^)]*\)[^\n]*:\n((?:^(?:[ \t]+[^\n]*)?\n)*)', re.M)
AWAIT = re.compile(r'^[ \t]+await ', re.M)
CALL = re.compile(r'^[ \t]+(\w+)\(', re.M)

problems = []
for path in sorted(Path('tests').glob('*.gd')):
    src = path.read_text(encoding='utf-8')
    bodies = {name: body for name, body in FUNC.findall(src)}
    coroutines = {n for n, b in bodies.items() if AWAIT.search(b)}
    for lineno, line in enumerate(src.splitlines(), 1):
        m = CALL.match(line)
        if not m:
            continue
        name = m.group(1)
        if name in coroutines and not line.lstrip().startswith('await '):
            problems.append(f"{path}:{lineno}: {name}() contains await but is called without one")

for p in problems:
    print(p)

if problems:
    print(f"\n{len(problems)} un-awaited coroutine call(s). "
          f"Assertions after each await are not running.")
    sys.exit(1)
print("no un-awaited coroutine calls")
