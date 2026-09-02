# Runs inside Blender (tools/blender/serve.sh): registers the MCP for Blender addon that sits
# next to this file and starts its socket server so `uvx blender-mcp` (see .mcp.json) can
# drive this Blender instance.
import os
import sys

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import blender_mcp_addon  # noqa: E402

port = int(os.environ.get("BLENDER_MCP_PORT", "9876"))
blender_mcp_addon.register()
# register() auto-starts a server on the scene's default port; move it if another was asked
server = getattr(bpy.types, "blendermcp_server", None)
if server is not None and server.running and server.port != port:
    server.stop()
    server = None
if server is None or not server.running:
    bpy.context.scene.blendermcp_port = port
    bpy.types.blendermcp_server = blender_mcp_addon.BlenderMCPServer(port=port)
    bpy.types.blendermcp_server.start()
print(f"KINGPIN: MCP for Blender listening on localhost:{bpy.types.blendermcp_server.port}", flush=True)
