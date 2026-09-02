extends RefCounted
## The generated toys (specs/meshes.md): every tier-1 mesh is built, loads, and carries the
## nodes its piece binds to.

const CONTRACT := {
	&"bumper_can": ["Body", "Skirt", "Lid", "ArtLid", "LampBand"],
	&"container": ["Body", "LampStripe"],
	&"sedan": ["Body", "Chrome", "Wheels", "LampRoof"],
	&"truck": ["Body", "Chrome", "Wheels", "LampRoof"],
	&"van": ["Body", "Wheels", "LampBar"],
	&"slot_machine": ["Cabinet", "Marquee", "Lever", "LampMarquee"],
	&"payphone": ["Body", "Chrome", "LampFace"],
	&"pizza_sign": ["Pole", "Spin"],
	&"washing_machine": ["Body", "Door"],
	&"safe": ["Body", "Dial", "Handle"],
}


func run(t: TestCtx) -> void:
	for id: StringName in CONTRACT.keys():
		t.ok(ToyLib.has(id), "%s is built and imports" % id)
		var toy := ToyLib.instance(id)
		if toy == null:
			continue
		for node_name: String in CONTRACT[id]:
			t.ok(ToyLib.find(toy, node_name) != null, "%s carries %s" % [id, node_name])
		var lamps := ToyLib.bind(toy, "Lamp", StandardMaterial3D.new())
		var wants_lamp := false
		for node_name: String in CONTRACT[id]:
			if node_name.begins_with("Lamp"):
				wants_lamp = true
		t.ok(lamps >= 1 or not wants_lamp, "%s binds its lamp" % id)
		var tris := 0
		for mi in ToyLib.meshes(toy):
			if mi.mesh != null:
				for s in range(mi.mesh.get_surface_count()):
					tris += mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX].size() / 3
		t.ok(tris > 0 and tris <= 3000, "%s is within budget (%d tris)" % [id, tris])
		toy.free()
	t.ok(ToyLib.instance(&"no_such_toy") == null, "a missing toy is null, not a crash")
