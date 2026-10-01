#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-godot}"

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  if command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN=godot4
  else
    echo "Godot executable not found. Set GODOT_BIN=/path/to/godot or add godot/godot4 to PATH." >&2
    exit 1
  fi
fi

echo "[1/3] Git whitespace check"
git diff --check

echo "[2/3] Godot headless project/editor validation"
"$GODOT_BIN" --headless --path "$ROOT" --editor --quit

echo "[3/3] JSON validation"
python3 - <<'PY'
import json
from pathlib import Path

for path in Path("design").rglob("*.json"):
    json.loads(path.read_text(encoding="utf-8"))
    print(f"OK {path}")
PY

echo "Verification passed."
