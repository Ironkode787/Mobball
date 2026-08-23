#!/usr/bin/env bash
# THE ship gate: full check (exit code honored — no pipes to swallow it), then the APK.
# A red gate aborts the ship. Born after a `check.sh | grep && build` chain measured
# grep's exit code instead of the gate's and shipped a red tree.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/check.sh
bash tools/build_android.sh
echo "SHIP OK"
