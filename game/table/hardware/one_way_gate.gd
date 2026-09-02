class_name OneWayGate
extends Node3D
## A hinged wire gate across a lane: it swings open for a ball coming from `pass_from` and
## is a wall to one coming back. The blade is a real collider toggled by which side the
## ball is on, so nothing can be half-open on top of the ball.

signal opened()
signal closed()

const LATCH_BAND := 0.22
const HOLD_BAND := 0.16

@export var id: StringName = &"one_way_gate"

var from_point: Vector2 = Vector2.ZERO
var to_point: Vector2 = Vector2.ZERO
var thickness: float = 0.05
var pass_from: Vector2 = Vector2(0.0, 1.0)
var base_height: float = 0.0

var _body: StaticBody3D = null
var _present: bool = true
var _open: bool = false
var _ball: Ball = null
var _axis: Vector2 = Vector2.RIGHT
var _normal: Vector2 = Vector2(0.0, 1.0)
var _centre: Vector2 = Vector2.ZERO
var _half_span: float = 0.0
var _flap: Node3D = null
var _swing_sign: float = 1.0
var _angle: float = 0.0


func configure(p_id: StringName, from: Vector2, to: Vector2, p_thickness: float,
		p_pass_from: Vector2, p_base: float = 0.0) -> void:
	id = p_id
	from_point = from
	to_point = to
	thickness = p_thickness
	pass_from = p_pass_from.normalized()
	base_height = p_base
	_axis = (to - from).normalized()
	_normal = Vector2(-_axis.y, _axis.x)
	if _normal.dot(pass_from) < 0.0:
		_normal = -_normal
	_centre = (from + to) * 0.5
	_half_span = from.distance_to(to) * 0.5


func _ready() -> void:
	_body = WallBuilder.make_body("Blade", Feel.LAYER_WALLS, Feel.make_material(Feel.WALL_FRICTION, 0.12))
	add_child(_body)
	var walls := WallBuilder.new(_body, Layout.GUIDE_HEIGHT, base_height)
	walls.bar(from_point, to_point, thickness)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var a := Layout.p3(from_point, base_height)
	var b := Layout.p3(to_point, base_height)
	var top := Layout.GUIDE_HEIGHT
	var st := MeshLib.begin()
	MeshLib.tube(st, PackedVector3Array([a + Vector3(0, top, 0), b + Vector3(0, top, 0)]), 0.012, 6)
	MeshLib.post(st, from_point, 0.028, top + 0.04, base_height, 8)
	MeshLib.post(st, to_point, 0.028, top + 0.04, base_height, 8)
	var frame := MeshInstance3D.new()
	frame.mesh = MeshLib.finish(st, lib.chrome_dark())
	frame.name = "Frame"
	add_child(frame)
	_flap = Node3D.new()
	_flap.name = "Flap"
	_flap.position = (a + b) * 0.5 + Vector3(0.0, top, 0.0)
	var axis := b - a
	var len_m := axis.length()
	var yaw := atan2(-axis.z, axis.x)
	_flap.rotation.y = yaw
	add_child(_flap)
	var st2 := MeshLib.begin()
	var n := maxi(int(len_m / 0.09), 2)
	for i in range(n):
		var x := lerpf(-len_m * 0.5 + 0.03, len_m * 0.5 - 0.03, float(i) / float(n - 1))
		MeshLib.tube(st2, PackedVector3Array([Vector3(x, 0.0, 0.0), Vector3(x, -(top - 0.05), 0.0)]), 0.009, 5)
	MeshLib.tube(st2, PackedVector3Array([Vector3(-len_m * 0.5 + 0.03, -(top - 0.05), 0.0),
			Vector3(len_m * 0.5 - 0.03, -(top - 0.05), 0.0)]), 0.009, 5)
	var fm := MeshInstance3D.new()
	fm.mesh = MeshLib.finish(st2, lib.steel())
	_flap.add_child(fm)
	var pass3 := Vector3(pass_from.x, 0.0, pass_from.y)
	var local_pass := Basis(Vector3.UP, -yaw) * pass3
	_swing_sign = -1.0 if local_pass.z < 0.0 else 1.0


func set_ball(b: Ball) -> void:
	_ball = b


func is_open() -> bool:
	return _open


func side_of(p: Vector2) -> float:
	return (p - _centre).dot(_normal)


func _physics_process(_delta: float) -> void:
	if not _present or _ball == null or not is_instance_valid(_ball):
		return
	var p := Layout.plan(_ball.table_position())
	if absf((p - _centre).dot(_axis)) > _half_span + LATCH_BAND:
		return
	var d := side_of(p)
	if absf(d) < HOLD_BAND:
		return
	var want_open := d > 0.0
	if want_open == _open:
		return
	_open = want_open
	_apply_collision()
	if _open:
		opened.emit()
	else:
		closed.emit()


func _process(delta: float) -> void:
	if _flap == null:
		return
	var wanted := deg_to_rad(62.0) * _swing_sign if _open else 0.0
	_angle = lerpf(_angle, wanted, 1.0 - exp(-12.0 * delta))
	_flap.rotation.x = _angle


func _apply_collision() -> void:
	if _body == null:
		return
	_body.collision_layer = 0 if (_open or not _present) else Feel.LAYER_WALLS


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if not active:
		_open = false
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _open:
		state = TableVisualState.VisualState.ARMED
	return TableVisualState.state_token(state)


func visual_token() -> Dictionary:
	return visual_state()
