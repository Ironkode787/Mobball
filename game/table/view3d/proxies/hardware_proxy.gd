class_name HardwareProxy3D
extends Node3D
## One piece of 2D hardware, mirrored into the 3D scene. Proxies never touch the physics
## node they read: they place meshes where the sim says the piece is and light them the way
## the piece's `visual_state()` says it should look. The base class handles what every proxy
## shares — following the source's transform, the storey it stands on, and whether it is
## present at all (hidden or dormant hardware simply has no body in the room).

var source: Node2D = null
var view: Node = null            ## TableView3D
var lib: View3DMaterials = null
var follow_transform: bool = true
var _ancestors: Array[CanvasItem] = []


func setup(p_source: Node2D, p_view: Node) -> void:
	source = p_source
	view = p_view
	lib = p_view.get("lib")
	_ancestors.clear()
	var n: Node = source
	var table: Node = p_view.get("table")
	while n != null and n != table:
		if n is CanvasItem:
			_ancestors.append(n as CanvasItem)
		n = n.get_parent()
	name = "P_" + source.name
	build()
	sync(0.0)


func alive() -> bool:
	return source != null and is_instance_valid(source) and source.is_inside_tree()


## Hidden or dormant hardware is not in the room. Reads the 2D node's own `visible` flag
## chain (never `is_visible_in_tree`, because the 2D table itself is hidden behind us).
func source_active() -> bool:
	for c in _ancestors:
		if not is_instance_valid(c) or not c.visible:
			return false
	if source.has_method(&"is_hardware_active") and not bool(source.call(&"is_hardware_active")):
		return false
	return true


func floor_height() -> float:
	return TableSpace.floor_height(source.global_position)


## Build meshes once. Subclasses override.
func build() -> void:
	pass


## Per-frame: follow and restyle. Subclasses call super then read their state.
func sync(_delta: float) -> void:
	var active := source_active()
	visible = active
	if active and follow_transform:
		follow()


func follow(lift: float = 0.0) -> void:
	var xf := source_transform()
	position = TableSpace.to3(xf.origin, TableSpace.floor_height(xf.origin) + lift)
	rotation = Vector3(0.0, TableSpace.yaw(xf.get_rotation()), 0.0)


## The transform the player sees this frame: interpolated when the engine offers it (physics
## interpolation is on project-wide), the raw physics transform otherwise.
func source_transform() -> Transform2D:
	if source.has_method(&"get_global_transform_interpolated"):
		return source.call(&"get_global_transform_interpolated")
	return source.global_transform


func source_origin() -> Vector2:
	return source_transform().origin


## The presentation token every piece publishes (TableVisualState.state_token).
func token() -> Dictionary:
	if source.has_method(&"visual_token"):
		var t: Variant = source.call(&"visual_token")
		if t is Dictionary:
			return t
	if source.has_method(&"visual_state"):
		var s: Variant = source.call(&"visual_state")
		if s is Dictionary:
			return s
	return {}


func state_name(tok: Dictionary) -> StringName:
	return StringName(str(tok.get("state", "idle")))


func has_mod(tok: Dictionary, m: StringName) -> bool:
	var mods: Variant = tok.get("modifiers", {})
	return mods is Dictionary and bool((mods as Dictionary).get(m, false))


func mesh_node(mesh: Mesh, material: Material = null, p_name: String = "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if material != null:
		mi.material_override = material
	mi.name = p_name
	add_child(mi)
	return mi


## Smoothly drive a lamp material's emission toward `wanted`.
static func drive_lamp(mat: StandardMaterial3D, wanted: float, delta: float, speed: float = 10.0) -> void:
	if mat == null:
		return
	var e := mat.emission_energy_multiplier
	if delta <= 0.0:
		mat.emission_energy_multiplier = wanted
	else:
		mat.emission_energy_multiplier = lerpf(e, wanted, 1.0 - exp(-speed * delta))


## Read a private-by-convention field off the 2D node without the proxy owning its API.
func peek(field: StringName, fallback: Variant) -> Variant:
	var v: Variant = source.get(field)
	return fallback if v == null else v
