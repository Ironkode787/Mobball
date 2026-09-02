class_name Kickback
extends Area3D
## The boys on the corner: a kicker in the outlane that throws a lost ball back up the field,
## once, then needs a minute to reload.

signal fired()

@export var id: StringName = &"kickback_left"

var cooldown_seconds: float = 60.0
var impulse: float = Feel.KICKBACK_IMPULSE
var direction: Vector2 = Vector2(0.15, -1.0).normalized()
var _present: bool = true
var _cool: float = 0.0
var _flash: float = 0.0
var _size: Vector2 = Layout.KICKBACK_SIZE
var _lamp: StandardMaterial3D = null


func configure(p_id: StringName, at: Vector2, size: Vector2, dir: Vector2) -> void:
	id = p_id
	position = Layout.p3(at)
	_size = size
	direction = dir.normalized()


func _ready() -> void:
	collision_layer = Feel.LAYER_ZONES
	collision_mask = Feel.LAYER_BALL
	monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x, 0.5, _size.y)
	cs.shape = box
	cs.position.y = 0.25
	add_child(cs)
	body_entered.connect(_on_ball_entered)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var post := BoxMesh.new()
	post.size = Vector3(_size.x * 0.5, 0.32, 0.10)
	var pm := MeshInstance3D.new()
	pm.mesh = post
	pm.material_override = lib.chrome_dark()
	pm.position = Vector3(0.0, 0.16, _size.y * 0.5 + 0.04)
	pm.name = "Kicker"
	add_child(pm)
	_lamp = lib.lamp(Color(1.0, 0.72, 0.30))
	var insert := BoxMesh.new()
	insert.size = Vector3(_size.x * 0.6, 0.012, _size.y * 0.5)
	var im := MeshInstance3D.new()
	im.mesh = insert
	im.material_override = _lamp
	im.position.y = 0.006
	im.name = "Insert"
	add_child(im)


func ready_to_fire() -> bool:
	return _present and _cool <= 0.0


func cooldown_left() -> float:
	return maxf(_cool, 0.0)


func _physics_process(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(_cool - delta, 0.0)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				(1.3 if ready_to_fire() else 0.05) + _flash * 3.0, 1.0 - exp(-10.0 * delta))


func _on_ball_entered(body: Node3D) -> void:
	if not (body is Ball) or not ready_to_fire():
		return
	var ball := body as Ball
	_cool = cooldown_seconds
	_flash = 1.0
	ball.set_velocity(Vector3.ZERO)
	ball.kick(Vector3(direction.x, 0.0, direction.y) * impulse)
	AudioDirector.play(&"kickback")
	TableScore.hit(id, ball, impulse)
	fired.emit()


func recharge() -> void:
	_cool = 0.0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_ZONES if _present else 0
	collision_mask = Feel.LAYER_BALL if _present else 0


func visual_state() -> int:
	if not _present or not ready_to_fire():
		return TableVisualState.VisualState.DISABLED
	if _flash > 0.02:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"cooldown": not ready_to_fire(), &"pulse": _flash > 0.02, &"flash": _flash > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
