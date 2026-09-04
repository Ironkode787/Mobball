#!/usr/bin/env bash
# Routine checks: import + tests + boot. --full also runs every gameplay simulation.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"
case "${1:-}" in
	"") FULL=false ;;
	--full) FULL=true ;;
	*) echo "Usage: bash tools/check.sh [--full]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "Usage: bash tools/check.sh [--full]" >&2; exit 2; }

# Godot can log a runtime error and still exit zero. Only known shutdown leak diagnostics
# are excluded; a rejected physics operation, missing resource or script error must fail.
has_runtime_errors() {
	grep -E 'SCRIPT ERROR|Parse Error|^ERROR:' | grep -Ev \
		'^ERROR: ([0-9]+ RID allocations of type .* were leaked at exit\.|[0-9]+ resources still in use at exit( \(run with --verbose for details\))?\.|Pages in use exist at exit in PagedAllocator:)'
}

echo "== import =="
IMPORT_OUT="$(timeout 300 "$GODOT" --headless --path . --import 2>&1)"
IMPORT_RC=$?
if [ $IMPORT_RC -ne 0 ] || has_runtime_errors <<< "$IMPORT_OUT" >/dev/null; then
	echo "$IMPORT_OUT" | grep -E "SCRIPT ERROR|Parse Error|ERROR" | head -40
	echo "IMPORT FAILED (rc=$IMPORT_RC)"
	exit 1
fi
echo "import ok"

echo "== tests =="
TEST_OUT="$(timeout 120 "$GODOT" --headless --path . --script tests/run_tests.gd 2>&1)"
TEST_RC=$?
echo "$TEST_OUT"
if [ $TEST_RC -ne 0 ] || has_runtime_errors <<< "$TEST_OUT" >/dev/null; then
	echo "TESTS FAILED (rc=$TEST_RC)"
	exit 1
fi

echo "== boot smoke (600 frames) =="
BOOT_OUT="$(timeout 120 "$GODOT" --headless --path . --quit-after 600 2>&1)"
BOOT_RC=$?
if [ $BOOT_RC -ne 0 ] || has_runtime_errors <<< "$BOOT_OUT" >/dev/null; then
	echo "$BOOT_OUT" | tail -40
	echo "BOOT SMOKE FAILED (rc=$BOOT_RC)"
	exit 1
fi
echo "boot ok"

if [ "$FULL" = false ]; then
	echo "Routine checks passed. Gameplay simulations were not run; use --full when needed."
	exit 0
fi

# Physics/gameplay scenario sims: each scene must run its scripted scenario headless and
# quit itself with exit code 0 on success, non-zero on failure (they print their own report).
# --fixed-fps steps the engine as fast as it can without real-time pacing (physics stays
# 240 Hz, four ticks a frame), so a sim's outcome depends on ticks, never on the machine.
for SIM in tests/sim/*.tscn; do
	[ -e "$SIM" ] || continue
	echo "== sim: $SIM =="
	SIM_OUT="$(timeout 300 "$GODOT" --headless --fixed-fps 60 --path . "res://$SIM" 2>&1)"
	SIM_RC=$?
	echo "$SIM_OUT" | tail -20
	if [ $SIM_RC -ne 0 ] || has_runtime_errors <<< "$SIM_OUT" >/dev/null; then
		has_runtime_errors <<< "$SIM_OUT"
		echo "SIM FAILED: $SIM (rc=$SIM_RC)"
		exit 1
	fi
done

echo "Full checks passed. See above for skipped checks and shutdown diagnostics."
