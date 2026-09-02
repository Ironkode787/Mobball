class_name ToyLib
extends RefCounted
## The generated toys (specs/meshes.md): glTF scenes built by tools/meshgen and imported from
## assets/meshes/. A piece asks for its toy by id, binds its code-driven materials onto the
## nodes the mesh contract names (Lamp*, Art*) and keeps its primitive look as the fallback
## when the toy is missing — a missing mesh logs once and never crashes.

const DIR := "res://assets/meshes/"

static var _scenes: Dictionary = {}
static var _missing: Dictionary = {}


static func path_for(id: StringName) -> String:
	return DIR + String(id) + ".glb"


static func has(id: StringName) -> bool:
	return _scene(id) != null


## A fresh instance of the toy, or null (logged once) when it is not built or fails to load.
static func instance(id: StringName) -> Node3D:
	var ps := _scene(id)
	if ps == null:
		return null
	var node := ps.instantiate()
	if node is Node3D:
		node.name = String(id).to_pascal_case()
		return node as Node3D
	node.free()
	return null


## Set `material` as the override of every MeshInstance3D under `root` whose name starts
## with `prefix`. Returns how many it bound so a piece can assert its contract.
static func bind(root: Node, prefix: String, material: Material) -> int:
	var n := 0
	for mi in meshes(root):
		if mi.name.begins_with(prefix):
			mi.material_override = material
			n += 1
	return n


static func find(root: Node, name: String) -> Node3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node != root and node.name == name and node is Node3D:
			return node as Node3D
		stack.append_array(node.get_children())
	return null


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			out.append(node as MeshInstance3D)
		stack.append_array(node.get_children())
	return out


static func _scene(id: StringName) -> PackedScene:
	if _scenes.has(id):
		return _scenes[id]
	var path := path_for(id)
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path) as PackedScene
	if ps == null and not _missing.has(id):
		_missing[id] = true
		push_warning("ToyLib: no mesh for '%s' (%s); using the primitive look" % [id, path])
	_scenes[id] = ps
	return ps
