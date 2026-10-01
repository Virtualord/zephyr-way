#!/bin/sh
# Full verification for Zephyr Way.
#
#   1. Git whitespace
#   2. Design JSON validity
#   3. Godot editor/headless project validation
#   4. Headless test suites
#
# Step 3 needs care: `godot --editor --quit` exits 0 even when scripts fail to
# parse, so its output is captured and inspected instead of trusting the exit
# code. See NOTES.md for the full list of ignored messages.
#
# Usage: ./scripts/verify.sh
#        GODOT_BIN=/path/to/godot ./scripts/verify.sh

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

LOG="${TMPDIR:-/tmp}/zephyr-way-verify.$$.log"
cleanup() {
  rm -f "$LOG"
}
trap cleanup EXIT INT TERM

echo "[1/4] Git whitespace check"
git diff --check

echo "[2/4] Design JSON validation"
python3 - <<'PY'
import json
from pathlib import Path

failed = False
for path in sorted(Path("design").rglob("*.json")):
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        print(f"INVALID {path}: {exc}")
        failed = True
    else:
        print(f"OK {path}")
raise SystemExit(1 if failed else 0)
PY

echo "[3/4] Godot headless project/editor validation"
status=0
"$GODOT_BIN" --headless --path "$ROOT" --editor --quit >"$LOG" 2>&1 || status=$?

# Parse and compile errors are the real signal. The engine also reports leak
# warnings at exit, which say nothing about correctness here.
if grep -qE 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|ERROR: Failed' "$LOG"; then
  echo "Godot reported script errors:"
  grep -E 'SCRIPT ERROR|Parse Error|Compile Error|Failed to load script|ERROR: Failed|^\s+at:' "$LOG" || true
  exit 1
fi

if [ "$status" -ne 0 ]; then
  echo "Godot exited with status $status"
  tail -40 "$LOG"
  exit 1
fi
echo "OK project validation"

echo "[4/4] Headless test suites"
GODOT_BIN="$GODOT_BIN" ./scripts/run_tests.sh

echo
echo "Verification passed."