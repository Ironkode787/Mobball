#!/usr/bin/env bash
# Generate the table's meshes: blender -b runs tools/meshgen/build_all.py, which builds every
# toy from code and exports assets/meshes/<id>.glb plus a preview PNG per mesh.
#   bash tools/meshgen/build.sh            # everything
#   bash tools/meshgen/build.sh sedan van  # a subset
set -euo pipefail
cd "$(dirname "$0")/../.."
BLENDER="${BLENDER:-/workspace/tools/blender/blender}"
"$BLENDER" -b --factory-startup --python tools/meshgen/build_all.py -- "$@" 2>&1 | grep -v -E "^ALSA|^Blender quit" || true
