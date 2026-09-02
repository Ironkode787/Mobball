class_name WallPiece
extends Node3D
## A named lump of wall geometry an upgrade can switch on and off — lane guides, the ring's
## arms, the top-lane posts, a deck's shell. Collision and mesh come from one WallBuilder so
## a dormant piece can never leave a ghost rail behind, nor an invisible wall in front of
## the player.

var body: StaticBody3D = null
var walls: WallBuilder = null
var material: Material = null
var cap_material: Material = null
var _active: bool = true
var _built: bool = false


func _init(height: float = Layout.GUIDE_HEIGHT, base: float = 0.0, p_material: Material = null,
		p_cap: Material = null) -> void:
	body = WallBuilder.make_body("Body")
	add_child(body)
	walls = WallBuilder.new(body, height, base)
	material = p_material if p_material != null else MaterialLib.shared().brass_dark()
	cap_material = p_cap


func _ready() -> void:
	_ensure_mesh()


func _ensure_mesh() -> void:
	if _built or walls.chains.is_empty():
		return
	_built = true
	walls.build_mesh(material, cap_material)


func bar(from: Vector2, to: Vector2, thickness: float, height: float = -1.0) -> void:
	walls.bar(from, to, thickness, height)
	if is_inside_tree():
		_rebuild()


func chain(points: PackedVector2Array, thickness: float, height: float = -1.0) -> void:
	walls.chain(points, thickness, height)
	if is_inside_tree():
		_rebuild()


func arc(center: Vector2, radius: float, from_deg: float, to_deg: float, segments: int,
		thickness: float, height: float = -1.0) -> void:
	walls.arc(center, radius, from_deg, to_deg, segments, thickness, height)
	if is_inside_tree():
		_rebuild()


func post(at: Vector2, radius: float, height: float = -1.0) -> void:
	walls.post(at, radius, height)
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	for child in body.get_children():
		if child is MeshInstance3D:
			child.queue_free()
	_built = false
	_ensure_mesh()


func set_hardware_active(active: bool) -> void:
	_active = active
	visible = active
	body.collision_layer = Feel.LAYER_WALLS if active else 0


func is_hardware_active() -> bool:
	return _active


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE if _active \
			else TableVisualState.VisualState.DISABLED
	return TableVisualState.state_token(state)
