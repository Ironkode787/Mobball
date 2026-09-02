#!/usr/bin/env bash
# Start Blender with the MCP for Blender addon listening (default port 9876) so the
# `blender` MCP server in .mcp.json can reach it. Headless machines get a virtual display:
# the addon needs Blender's UI event loop to run commands on the main thread.
#   tools/blender/serve.sh            # foreground, Ctrl-C to stop
#   BLENDER_MCP_PORT=9877 tools/blender/serve.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
BLENDER="${BLENDER:-/workspace/tools/blender/blender}"
if [ -n "${DISPLAY:-}" ]; then
	exec "$BLENDER" --python tools/blender/enable_mcp.py "$@"
fi
exec xvfb-run -a -s "-screen 0 1280x800x24" "$BLENDER" --python tools/blender/enable_mcp.py "$@"
