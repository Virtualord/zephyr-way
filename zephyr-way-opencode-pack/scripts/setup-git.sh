#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

git config core.hooksPath .githooks
git config init.defaultBranch main

echo "Git hooks configured: .githooks"
echo "Default initial branch configured locally as: main"
echo "Next: git status"
