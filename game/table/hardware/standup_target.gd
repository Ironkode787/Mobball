class_name StandupTarget
extends StaticBody3D
## A standup: a plate on a post whose face is a switch. Banks mark them; a cop or a goon is
## one of these with a police-blue face. A ball asleep against one is thrown off.

signal struck(target: StandupTarget, ball: Ball)

const COOLDOWN := 0.22
const STALL_IMPULSE := 6.0
const STALL_COOLDOWN := 0.6
const PLATE_HEIGHT := 0.42

@export var id: StringName = &"standup"

var marked: bool = false
var length: float = Layout.TARGET_LENGTH
var thickness: float = Layout.TARGET_THICK
var facing: Vector2 = Vector2(0.0, 1.0)
var lamp_color: Color = Color(1.0, 0.86, 0.55)

var _present: bool = true
var _face: Area3D = null
var _ring: Area3D = null
var _cooldown: float = 0.0
var _stall_cool: float = 0.0
var _pulse: float = 0.0
var _inside: Array[Ball] = []
var _lamp: StandardMaterial3D = null


## `center` in plan space; the plate faces along `p_facing` (its +Z).
func configure(p_id: StringName, center: Vector2, p_facing: Vector2, p_length: float = Layout.TARGET_LENGTH) -> void:
	id = p_id
	position = Layout.p3(center)
	facing = p_facing.normalized()
	length = p_length
	rotation.y = Layout.yaw_facing(facing)


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, 0.30)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, PLATE_HEIGHT, thickness)
	shape.shape = box
	shape.position.y = PLATE_HEIGHT * 0.5
	shape.name = "Body"
	add_child(shape)

	_face = _zone("Face", Vector3(length, PLATE_HEIGHT, Feel.BALL_RADIUS * 0.8),
			Vector3(0.0, PLATE_HEIGHT * 0.5, thickness * 0.5 + Feel.BALL_RADIUS * 0.4))
	_face.body_entered.connect(_on_face_entered)
	_ring = _zone("Ring", Vector3(length + Feel.BALL_RADIUS * 2.0, PLATE_HEIGHT,
			thickness + Feel.BALL_RADIUS * 2.0), Vector3(0.0, PLATE_HEIGHT * 0.5, 0.0))
	_ring.body_entered.connect(func(body: Node3D) -> void:
		if body is Ball and not _inside.has(body):
			_inside.append(body as Ball))
	_ring.body_exited.connect(func(body: Node3D) -> void:
		if body is Ball:
			_inside.erase(body as Ball))
	_build_look()
	_apply_collision()


func _zone(p_name: String, size: Vector3, at: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = p_name
	a.collision_layer = Feel.LAYER_ZONES
	a.collision_mask = Feel.LAYER_BALL
	a.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	a.add_child(cs)
	add_child(a)
	return a


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var body := BoxMesh.new()
	body.size = Vector3(length, PLATE_HEIGHT, thickness)
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = lib.ink()
	bm.position.y = PLATE_HEIGHT * 0.5
	bm.name = "Plate"
	add_child(bm)
	_lamp = lib.lamp(lamp_color)
	var face := BoxMesh.new()
	face.size = Vector3(length * 0.78, PLATE_HEIGHT * 0.6, 0.012)
	var fm := MeshInstance3D.new()
	fm.mesh = face
	fm.material_override = _lamp
	fm.position = Vector3(0.0, PLATE_HEIGHT * 0.55, thickness * 0.5 + 0.006)
	fm.name = "Lamp"
	add_child(fm)
	var st := MeshLib.begin()
	MeshLib.post(st, Vector2(0.0, -thickness * 0.5 - 0.03), 0.03, PLATE_HEIGHT * 0.7, 0.0, 8)
	var pm := MeshInstance3D.new()
	pm.mesh = MeshLib.finish(st, lib.chrome_dark())
	pm.name = "Post"
	add_child(pm)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_stall_cool = maxf(_stall_cool - delta, 0.0)
	_pop_stalled()


func _pop_stalled() -> void:
	if not _present or _stall_cool > 0.0 or _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	for b in _inside:
		if BallHold.is_held(b) or b.speed() >= Feel.HARDWARE_STALL_SPEED:
			continue
		_stall_cool = STALL_COOLDOWN
		var away := b.table_position() - position
		away.y = 0.0
		var normal := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, rotation.y)
		var side := 1.0 if away.dot(normal) >= 0.0 else -1.0
		var mixed := normal * side * 1.3 + away.normalized() * 0.7
		b.kick((mixed.normalized() if mixed.length() > 0.001 else Vector3(0, 0, 1)) * STALL_IMPULSE)
		return


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 5.0, 0.0)
	if _lamp == null:
		return
	var wanted := 0.12
	if marked:
		wanted = 0.8
	if String(id).begins_with("cop_"):
		wanted = 2.0
	_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
			wanted + _pulse * 3.0, 1.0 - exp(-16.0 * delta))


func _on_face_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present or _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	_pulse = 1.0
	struck.emit(self, body as Ball)


func set_marked(value: bool) -> void:
	marked = value


func set_lamp_color(c: Color) -> void:
	lamp_color = c
	if _lamp != null:
		_lamp.emission = c
		_lamp.albedo_color = c.darkened(0.55)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_inside.clear()
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _visual_state_id() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if marked:
		return TableVisualState.VisualState.COMPLETED
	if _pulse > 0.0:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.IDLE


func visual_state() -> Dictionary:
	return TableVisualState.state_token(_visual_state_id(), {&"marked": marked, &"pulse": _pulse > 0.0})


func visual_token() -> Dictionary:
	return visual_state()


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	for area: Area3D in [_face, _ring]:
		if area == null:
			continue
		area.collision_layer = Feel.LAYER_ZONES if _present else 0
		area.collision_mask = Feel.LAYER_BALL if _present else 0
