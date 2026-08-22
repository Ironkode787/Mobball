#!/usr/bin/env bash
# Project gate: import + headless tests + boot smoke + sim scenarios. All work must pass this.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"

echo "== import =="
IMPORT_OUT="$("$GODOT" --headless --path . --import 2>&1)"
if echo "$IMPORT_OUT" | grep -E "SCRIPT ERROR|Parse Error|ERROR: Failed" >/dev/null; then
	echo "$IMPORT_OUT" | grep -E "SCRIPT ERROR|Parse Error|ERROR" | head -40
	echo "IMPORT FAILED"
	exit 1
fi
echo "import ok"

echo "== tests =="
timeout 120 "$GODOT" --headless --path . --script tests/run_tests.gd
TEST_RC=$?
if [ $TEST_RC -ne 0 ]; then
	echo "TESTS FAILED (rc=$TEST_RC)"
	exit $TEST_RC
fi

echo "== boot smoke (600 frames) =="
BOOT_OUT="$(timeout 120 "$GODOT" --headless --path . --quit-after 600 2>&1)"
BOOT_RC=$?
if [ $BOOT_RC -ne 0 ] || echo "$BOOT_OUT" | grep -E "SCRIPT ERROR" >/dev/null; then
	echo "$BOOT_OUT" | tail -40
	echo "BOOT SMOKE FAILED (rc=$BOOT_RC)"
	exit 1
fi
echo "boot ok"

# Physics/gameplay scenario sims: each scene must run its scripted scenario headless and
# quit itself with exit code 0 on success, non-zero on failure (they print their own report).
for SIM in tests/sim/*.tscn; do
	[ -e "$SIM" ] || continue
	echo "== sim: $SIM =="
	SIM_OUT="$(timeout 300 "$GODOT" --headless --path . "res://$SIM" 2>&1)"
	SIM_RC=$?
	echo "$SIM_OUT" | tail -20
	if [ $SIM_RC -ne 0 ] || echo "$SIM_OUT" | grep -E "SCRIPT ERROR" >/dev/null; then
		echo "SIM FAILED: $SIM (rc=$SIM_RC)"
		exit 1
	fi
done

echo "ALL CHECKS PASSED"
