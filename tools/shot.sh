#!/usr/bin/env bash
# Capture a PNG screenshot of a scene under xvfb (software GL).
# Usage: tools/shot.sh [out.png] [res://scene.tscn] [frames]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"
OUT="${1:-/tmp/shot.png}"
SCENE="${2:-}"
FRAMES="${3:-90}"
SHOT_PATH="$OUT" SHOT_SCENE="$SCENE" SHOT_FRAMES="$FRAMES" \
	xvfb-run -a -s "-screen 0 540x960x24" \
	"$GODOT" --path . --rendering-driver opengl3 res://tools/shot_capture.tscn 2>&1 \
	| grep -E "shot:|ERROR" | tail -5
