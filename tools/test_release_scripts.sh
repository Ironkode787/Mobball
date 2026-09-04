#!/usr/bin/env bash
# Fast failure-injection checks for shell gates that cannot live inside the Godot suite.
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_TMP="$(mktemp -d)"
cleanup() {
	rm -f -- "$TEST_TMP"/*
	rmdir -- "$TEST_TMP"
}
trap cleanup EXIT

cat > "$TEST_TMP/fake-godot" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GATE_TRACE"
case "$*" in
	*--import*)
		[ "$GATE_CASE" != import_exit ] || exit 23 ;;
	*--script*)
		case "$GATE_CASE" in
			test_exit) exit 7 ;;
			script_error) echo 'SCRIPT ERROR: deliberate runtime failure' ;;
			physics_error) echo 'ERROR: Failed to apply central impulse without a physics space' ;;
			shutdown) echo 'ERROR: 2 resources still in use at exit (run with --verbose for details).' ;;
		esac ;;
	*--quit-after*)
		[ "$GATE_CASE" != boot_error ] || echo 'ERROR: Failed to load a scene resource' ;;
	*res://tests/sim/*)
		[ "$GATE_CASE" != sim_error ] || echo 'SCRIPT ERROR: deliberate simulation failure' ;;
esac
exit 0
EOF
chmod +x "$TEST_TMP/fake-godot"

for CASE in import_exit test_exit script_error physics_error boot_error sim_error; do
	if GATE_CASE="$CASE" GATE_TRACE="$TEST_TMP/trace" GODOT="$TEST_TMP/fake-godot" \
			bash tools/check.sh --full > "$TEST_TMP/$CASE.log" 2>&1; then
		echo "Check gate accepted $CASE" >&2
		exit 1
	fi
done
grep -F 'IMPORT FAILED (rc=23)' "$TEST_TMP/import_exit.log" >/dev/null

: > "$TEST_TMP/trace"
GATE_CASE=shutdown GATE_TRACE="$TEST_TMP/trace" GODOT="$TEST_TMP/fake-godot" \
	bash tools/check.sh > "$TEST_TMP/routine.log" 2>&1 || { cat "$TEST_TMP/routine.log"; exit 1; }
if grep -F 'res://tests/sim/' "$TEST_TMP/trace" >/dev/null; then
	echo "Routine checks unexpectedly ran simulations" >&2
	exit 1
fi
GATE_CASE=shutdown GATE_TRACE="$TEST_TMP/trace" GODOT="$TEST_TMP/fake-godot" \
	bash tools/check.sh --full > "$TEST_TMP/full.log" 2>&1 || { cat "$TEST_TMP/full.log"; exit 1; }
grep -F 'res://tests/sim/' "$TEST_TMP/trace" >/dev/null
if bash tools/check.sh --unknown > "$TEST_TMP/invalid.log" 2>&1; then
	echo "Check gate accepted an unknown option" >&2
	exit 1
fi

echo "CHECK SCRIPT TESTS OK"
