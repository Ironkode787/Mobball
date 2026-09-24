#!/usr/bin/env bash
# The printed playfield: dump the table's geometry, paint the art over it.
# Re-run after any change to game/table/layout.gd or the insert positions.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-/workspace/tools/godot/godot}"
timeout 120 "$GODOT" --headless --path . res://tools/texgen/playfield_layout.tscn
python3 tools/texgen/playfield_art.py
timeout 300 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
