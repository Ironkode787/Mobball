#!/usr/bin/env bash
# Render-cost probe under software GL: boots the game at phone resolution and prints frame
# time and draw statistics (tests/probe_perf.gd). Absolute numbers are llvmpipe's; compare
# runs against each other.   tools/perf.sh [WxH]
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"
RES="${1:-1080x1920}"
xvfb-run -a -s "-screen 0 1200x2000x24" "$GODOT" --path . --rendering-driver opengl3 --resolution "$RES" --disable-vsync \
	res://tests/probe_perf.tscn 2>&1 | grep -E "^perf:|SCRIPT ERROR"
