#!/usr/bin/env bash
# THE ship gate: full check, release audit, then the credential-gated Play beta AAB.
# A red gate aborts the ship. Born after a `check.sh | grep && build` chain measured
# grep's exit code instead of the gate's and shipped a red tree.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/test_release_scripts.sh
bash tools/check.sh --full
"${GODOT:-/workspace/tools/godot/godot}" --headless --path . --script tests/release_probe.gd
mkdir -p build/release/device_probe
SHOT_DIR="$PWD/build/release/device_probe" \
KINGPIN_SAFE_INSETS="44,96,72,54" KINGPIN_CORNER_GUARD="56" \
	xvfb-run -a -s "-screen 0 486x864x24" \
	"${GODOT:-/workspace/tools/godot/godot}" --path . --resolution 486x864 \
	res://tests/device_probe.tscn
bash tools/build_beta.sh
VERSION_NAME="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot | head -1)"
bash tools/probe_android_package.sh "build/release/kingpin-$VERSION_NAME.aab"
echo "BETA SHIP OK"
