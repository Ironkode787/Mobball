#!/usr/bin/env bash
# Fast failure-injection checks for shell gates that cannot live inside the Godot suite.
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_TMP="$(mktemp -d)"
cleanup() {
	case "$TEST_TMP" in
		"${TMPDIR:-/tmp}"/*) rm -rf -- "$TEST_TMP" ;;
	esac
}
trap cleanup EXIT

cat > "$TEST_TMP/failing-godot" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
chmod +x "$TEST_TMP/failing-godot"
set +e
GODOT="$TEST_TMP/failing-godot" bash tools/check.sh > "$TEST_TMP/import.log" 2>&1
IMPORT_GATE_RC=$?
set -e
[ $IMPORT_GATE_RC -ne 0 ] || { echo "Import gate accepted a nonzero Godot exit" >&2; exit 1; }
grep -F 'IMPORT FAILED (rc=23)' "$TEST_TMP/import.log" >/dev/null || {
	echo "Import gate did not preserve the failing exit code" >&2
	exit 1
}

grep -F -- '--untracked-files=all' tools/build_beta.sh >/dev/null
grep -F -- "dump manifest --bundle" tools/build_beta.sh >/dev/null
grep -F -- "version/name)\" = \"\$VERSION_NAME" tools/build_beta.sh >/dev/null

echo "RELEASE SCRIPT TESTS OK"
