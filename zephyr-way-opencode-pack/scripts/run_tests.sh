#!/bin/sh
# Run every headless check suite and report a combined result.
#
# Each suite is a separate Godot process because each one quits the engine
# itself. Any failing suite fails the run.
#
# Usage: ./scripts/run_tests.sh
#        GODOT_BIN=/path/to/godot ./scripts/run_tests.sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  if command -v godot4 >/dev/null 2>&1; then
    GODOT_BIN=godot4
  else
    echo "Godot executable not found. Set GODOT_BIN=/path/to/godot." >&2
    exit 1
  fi
fi

SUITES="tests/procedural_test.gd
tests/input_map_test.gd
tests/flight_model_test.gd
tests/flight_regression_test.gd
tests/recorder_test.gd
tests/scene_test.gd"

LOG="${TMPDIR:-/tmp}/zephyr-way-tests.$$.log"
FAILED=""

cleanup() {
  rm -f "$LOG"
}
trap cleanup EXIT INT TERM

for suite in $SUITES; do
  echo "--- $suite"

  # Godot leaks a handful of RIDs when a suite quits mid-frame. That noise is
  # stripped from the display, but the suite's own exit code is what decides
  # pass or fail.
  status=0
  "$GODOT_BIN" --headless --path "$ROOT" --script "res://$suite" >"$LOG" 2>&1 || status=$?

  grep -vE 'ObjectDB instances were leaked|RID allocations of type|PagedAllocator|instance_notify_deleted|^\s+at: ' "$LOG" || true

  if [ "$status" -ne 0 ]; then
    echo "  (suite exited with status $status)"
    FAILED="$FAILED $suite"
  fi
done

if [ -n "$FAILED" ]; then
  echo
  echo "FAILED:$FAILED"
  exit 1
fi

echo
echo "All test suites passed."