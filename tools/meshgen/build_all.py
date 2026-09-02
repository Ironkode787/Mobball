"""Build every toy (or the ids given after `--`) and export it. Runs inside Blender:
    blender -b --factory-startup --python tools/meshgen/build_all.py -- [ids...]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
if HERE not in sys.path:
	sys.path.insert(0, HERE)

import common  # noqa: E402
import toys  # noqa: E402

BUDGET = {"default": 1500, "slot_machine": 3000, "washing_machine": 2000}


def main():
	wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
	ids = wanted or list(toys.BUILDERS.keys())
	failed = []
	for mesh_id in ids:
		if mesh_id not in toys.BUILDERS:
			print("meshgen: unknown mesh", mesh_id)
			failed.append(mesh_id)
			continue
		common.reset()
		objects = toys.BUILDERS[mesh_id]()
		tris = common.tri_count(objects)
		budget = BUDGET.get(mesh_id, BUDGET["default"])
		names = ", ".join(o.name for o in objects)
		print("meshgen: %-16s %5d tris  [%s]" % (mesh_id, tris, names), flush=True)
		if tris > budget:
			print("meshgen: %s is over budget (%d > %d)" % (mesh_id, tris, budget))
			failed.append(mesh_id)
		common.export_glb(objects, os.path.join(ROOT, "assets", "meshes", mesh_id + ".glb"))
		common.preview(objects, os.path.join(HERE, "preview", mesh_id + ".png"))
	if failed:
		print("meshgen: FAILED", failed)
		sys.exit(1)
	print("meshgen: done")


main()
