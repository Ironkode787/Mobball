class_name BuildIn
extends Node3D
## The crew putting a purchase up during The Count: scaffolding rises around the new piece,
## a tarp drops, the piece lifts into place, hammer glints tick along the frame. Presentation
## only — the piece is fully live the moment it is bought; this just makes it *arrive*.

const DURATION := 1.4
const SCAFFOLD_PAD := 0.12

var enabled: bool = true
var _jobs: Array[Dictionary] = []          ## { node, box: AABB, t, rig: Node3D, base_y }
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0xB011D


func start(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not enabled or (Presentation.fx != null and Presentation.fx.reduced_motion):
		return
	cancel(node)
	var box := approx_box(node)
	if box.size.x <= 0.0 or box.size.z <= 0.0:
		return
	var rig := _make_rig(box.grow(SCAFFOLD_PAD))
	add_child(rig)
	_jobs.append({"node": node, "box": box, "t": 0.0, "rig": rig, "base_y": node.position.y})
	node.position.y = float(node.position.y) - 0.6
	AudioDirector.play(&"stamp_thunk")


func cancel(node: Node3D) -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		if _jobs[i]["node"] == node:
			_finish_job(_jobs[i])
			_jobs.remove_at(i)


func building() -> int:
	return _jobs.size()


func is_building(node: Node3D) -> bool:
	for job: Dictionary in _jobs:
		if job["node"] == node:
			return true
	return false


func finish_all() -> void:
	for job: Dictionary in _jobs:
		_finish_job(job)
	_jobs.clear()


func _finish_job(job: Dictionary) -> void:
	var node: Node3D = job["node"]
	if is_instance_valid(node):
		node.position.y = float(job["base_y"])
	var rig: Node3D = job["rig"]
	if is_instance_valid(rig):
		rig.queue_free()


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.ACTIVE if not _jobs.is_empty() \
			else TableVisualState.VisualState.IDLE
	return TableVisualState.state_token(state, {&"moving": not _jobs.is_empty()})


func visual_token() -> Dictionary:
	return visual_state()


func _process(delta: float) -> void:
	if _jobs.is_empty():
		return
	for i in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[i]
		var node: Node3D = job["node"]
		if not is_instance_valid(node):
			var rig: Node3D = job["rig"]
			if is_instance_valid(rig):
				rig.queue_free()
			_jobs.remove_at(i)
			continue
		job["t"] = float(job["t"]) + delta
		var f := clampf(float(job["t"]) / DURATION, 0.0, 1.0)
		node.position.y = float(job["base_y"]) - 0.6 * (1.0 - ease(f, 0.4))
		var rig: Node3D = job["rig"]
		if is_instance_valid(rig):
			rig.scale.y = maxf(0.05, 1.0 - ease(maxf(f - 0.55, 0.0) / 0.45, 2.0))
			var tarp := rig.get_node_or_null("Tarp") as Node3D
			if tarp != null:
				tarp.scale.y = maxf(0.02, 1.0 - ease(clampf(f / 0.7, 0.0, 1.0), 0.6))
		_jobs[i] = job
		if f >= 1.0:
			_finish_job(job)
			_jobs.remove_at(i)


func _make_rig(box: AABB) -> Node3D:
	var lib := MaterialLib.shared()
	var rig := Node3D.new()
	rig.name = "Scaffold"
	var h := maxf(box.size.y, 0.4) + 0.3
	var st := MeshLib.begin()
	for sx in [box.position.x, box.end.x]:
		for sz in [box.position.z, box.end.z]:
			MeshLib.post(st, Vector2(sx, sz), 0.02, h, box.position.y, 6)
	for y in [box.position.y + h * 0.5, box.position.y + h]:
		MeshLib.tube(st, PackedVector3Array([
			Vector3(box.position.x, y, box.position.z), Vector3(box.end.x, y, box.position.z),
			Vector3(box.end.x, y, box.end.z), Vector3(box.position.x, y, box.end.z),
			Vector3(box.position.x, y, box.position.z),
		]), 0.012, 5)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, lib.plastic(Color("A9552E"), 0.7))
	rig.add_child(mi)
	var tarp := BoxMesh.new()
	tarp.size = Vector3(box.size.x + 0.02, h * 0.9, box.size.z + 0.02)
	var tm := MeshInstance3D.new()
	tm.mesh = tarp
	tm.material_override = lib.plastic(Color("7A6A2A"), 0.9)
	tm.position = box.get_center() + Vector3(0.0, h * 0.45 - box.size.y * 0.5, 0.0)
	tm.name = "Tarp"
	rig.add_child(tm)
	return rig


static func approx_box(node: Node3D) -> AABB:
	if node.has_method(&"build_box"):
		var named: Variant = node.call(&"build_box")
		if named is AABB and (named as AABB).size.x > 0.0:
			return named
	var out := AABB()
	var any := false
	for shape: CollisionShape3D in _collision_shapes(node):
		if shape.shape == null:
			continue
		var local := shape.shape.get_debug_mesh().get_aabb() if false else _shape_aabb(shape.shape)
		var box := shape.global_transform * local
		var parent := node.get_parent() as Node3D
		if parent != null:
			box = parent.global_transform.affine_inverse() * box
		out = box if not any else out.merge(box)
		any = true
	if not any:
		return AABB(node.position - Vector3(0.3, 0.0, 0.3), Vector3(0.6, 0.4, 0.6))
	return out


static func _shape_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var s := (shape as BoxShape3D).size
		return AABB(-s * 0.5, s)
	if shape is CylinderShape3D:
		var c := shape as CylinderShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points
		if pts.is_empty():
			return AABB()
		var box := AABB(pts[0], Vector3.ZERO)
		for p in pts:
			box = box.expand(p)
		return box
	return AABB(Vector3(-0.2, 0.0, -0.2), Vector3(0.4, 0.4, 0.4))


static func _collision_shapes(node: Node) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	if node is CollisionShape3D:
		out.append(node as CollisionShape3D)
	for child in node.get_children():
		out.append_array(_collision_shapes(child))
	return out
