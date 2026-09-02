class_name Flipper
extends AnimatableBody3D
## A solenoid bat. A kinematic body swept along an authored curve (docs/09 §2: curves, not
## motors) so the feel is designed rather than emergent; Jolt reads the sweep's velocity off
## the transform and hands it to the ball through the solver, so a flip is a real impact.
##
## Local geometry always points along +X; the right bat is the same shape turned around
## (see Feel.flipper_rest_rotation). The striking face is local -Z on the left, +Z on the right.

enum State { REST, RISING, HELD, FALLING }

@export var side: StringName = &"left"
@export var size_scale: float = 1.0

var state: State = State.REST
var progress: float = 0.0
var dead: bool = false
var power_scale: float = 1.0

var _phase_time: float = 0.0
var _fall_from: float = 0.0
var _held: bool = false
var _buffered_at: float = -1000.0
var _ball: Ball = null
var _glow: float = 0.0
var _pivot_stall: float = 0.0
var _rest_rot: float = 0.0
var _strike_sign: float = -1.0
var _clock: float = 0.0
var _present: bool = true
var _jam: float = 0.0
var _telegraph: float = 0.0
var _bat_mesh: MeshInstance3D = null
var _lamp: StandardMaterial3D = null


func _ready() -> void:
	process_physics_priority = 10
	sync_to_physics = true
	collision_layer = Feel.LAYER_FLIPPERS
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.FLIPPER_FRICTION, Feel.FLIPPER_BOUNCE)
	_rest_rot = Feel.flipper_rest_rotation(side)
	_strike_sign = 1.0 if side == &"right" else -1.0
	rotation.y = _rest_rot
	_build_shapes()
	_build_look()


func bat_length() -> float:
	return Feel.FLIPPER_LENGTH * size_scale


func pivot_radius() -> float:
	return Feel.FLIPPER_PIVOT_RADIUS * size_scale


func tip_radius() -> float:
	return Feel.FLIPPER_TIP_RADIUS * size_scale


func _outline(grow: float = 0.0) -> PackedVector2Array:
	return MeshLib.capsule_poly(Vector2.ZERO, Vector2(bat_length(), 0.0),
			pivot_radius() + grow, tip_radius() + grow, 8)


func _build_shapes() -> void:
	var h := Feel.FLIPPER_HEIGHT * clampf(size_scale, 0.6, 1.0)
	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	var pts := PackedVector3Array()
	for p in _outline(0.01):
		pts.append(Vector3(p.x, 0.02, p.y))
		pts.append(Vector3(p.x, 0.02 + h, p.y))
	hull.points = pts
	shape.shape = hull
	shape.name = "Bat"
	add_child(shape)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var h := Feel.FLIPPER_HEIGHT * clampf(size_scale, 0.6, 1.0)
	var st := MeshLib.begin()
	MeshLib.prism(st, _outline(), h * 0.62, 0.03 + h * 0.19, false, 1.0)
	_lamp = lib.lamp(Color(1.0, 0.86, 0.55), 0.3)
	_lamp.albedo_color = Color("E9DFC8")
	_lamp.emission_energy_multiplier = 0.0
	_bat_mesh = MeshInstance3D.new()
	_bat_mesh.mesh = MeshLib.finish(st, _lamp)
	_bat_mesh.name = "BatBody"
	add_child(_bat_mesh)
	var st2 := MeshLib.begin()
	MeshLib.prism(st2, _outline(0.012), h * 0.36, 0.02, false, 1.0)
	var rubber := MeshInstance3D.new()
	rubber.mesh = MeshLib.finish(st2, lib.rubber_red())
	rubber.name = "Rubber"
	add_child(rubber)
	var st3 := MeshLib.begin()
	MeshLib.post(st3, Vector2.ZERO, pivot_radius() * 0.45, h + 0.06, 0.0, 12)
	var cap := MeshInstance3D.new()
	cap.mesh = MeshLib.finish(st3, lib.chrome_dark())
	cap.name = "PivotCap"
	add_child(cap)


func set_ball(b: Ball) -> void:
	_ball = b


func press() -> void:
	if dead or not _present or _jam > 0.0:
		return
	match state:
		State.REST:
			_held = true
			_fire()
		State.FALLING:
			_held = true
			_buffered_at = _clock
		_:
			_held = true


func release() -> void:
	_held = false
	if state == State.RISING or state == State.HELD:
		_begin_fall()


func set_pressed(pressed: bool) -> void:
	if pressed and not _held:
		press()
	elif not pressed and _held:
		release()


func is_held() -> bool:
	return _held


func kill() -> void:
	dead = true
	_held = false
	_buffered_at = -1000.0
	if state == State.RISING or state == State.HELD:
		_begin_fall()


func revive() -> void:
	dead = false
	_jam = 0.0
	_telegraph = 0.0


func jam(seconds: float) -> void:
	if not _present or seconds <= 0.0:
		return
	_jam = maxf(_jam, seconds)
	_telegraph = 0.0
	_held = false
	_buffered_at = -1000.0
	if state == State.RISING or state == State.HELD:
		_begin_fall()


func unjam() -> void:
	_jam = 0.0
	_telegraph = 0.0


func is_jammed() -> bool:
	return _jam > 0.0


func jam_left() -> float:
	return _jam


func telegraph(seconds: float) -> void:
	if not _present or seconds <= 0.0:
		return
	_telegraph = maxf(_telegraph, seconds)


func is_telegraphed() -> bool:
	return _telegraph > 0.0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	collision_layer = Feel.LAYER_FLIPPERS if active else 0
	if active:
		return
	_held = false
	_buffered_at = -1000.0
	state = State.REST
	progress = 0.0
	rotation.y = _rest_rot


func is_hardware_active() -> bool:
	return _present


func visual_state() -> Dictionary:
	var vs := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not _present or dead:
		vs = TableVisualState.VisualState.DISABLED
		if dead:
			mods.append(&"dead")
	elif _jam > 0.0:
		vs = TableVisualState.VisualState.DANGER
		mods.append(&"jam")
	elif _telegraph > 0.0:
		vs = TableVisualState.VisualState.DANGER
		mods.append(&"telegraph")
	elif state != State.REST:
		vs = TableVisualState.VisualState.ACTIVE
		mods.append(&"held" if state == State.HELD else &"pulse")
	return TableVisualState.state_token(vs, mods)


## Plan-space unit normal of the striking face.
func strike_normal() -> Vector2:
	var n := Vector3(0.0, 0.0, _strike_sign).rotated(Vector3.UP, rotation.y)
	return Vector2(n.x, n.z)


## Table-space point a ball rests at when cradled `t` of the way along the bat.
func cradle_point(t: float) -> Vector3:
	var x := bat_length() * clampf(t, 0.0, 1.0)
	var along := Vector3(x, 0.0, 0.0).rotated(Vector3.UP, rotation.y)
	var n := strike_normal() * (_bat_radius(x) + Feel.BALL_RADIUS)
	return position + along + Vector3(n.x, 0.0, n.y) + Vector3(0.0, Feel.BALL_RADIUS, 0.0)


func _bat_radius(local_x: float) -> float:
	var t := clampf(local_x / bat_length(), 0.0, 1.0)
	return lerpf(pivot_radius(), tip_radius(), t)


func _fire() -> void:
	state = State.RISING
	_phase_time = 0.0
	_buffered_at = -1000.0
	_glow = 1.0
	var sitter := _pivot_sitter()
	if sitter != null:
		sitter.kick(_pivot_pop_direction() * Feel.FLIPPER_PIVOT_POP)
	Events.flipper_fired.emit(side)
	AudioDirector.play(&"flipper_up")


func _pivot_sitter() -> Ball:
	var reach := pivot_radius() + Feel.BALL_RADIUS + 0.06
	var candidates: Array[Ball] = Balls.live()
	if candidates.is_empty() and _ball != null and is_instance_valid(_ball):
		candidates = [_ball]
	for b in candidates:
		if b.speed() > Feel.HARDWARE_STALL_SPEED:
			continue
		var rel := b.table_position() - position
		rel.y = 0.0
		if rel.length() <= reach and rel.z * _strike_sign > -0.05:
			return b
	return null


func _pivot_pop_direction() -> Vector3:
	var tip := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, rotation.y)
	var n := strike_normal()
	return (Vector3(n.x, 0.0, n.y) * 0.8 + tip * 0.6).normalized()


func _begin_fall() -> void:
	state = State.FALLING
	_fall_from = progress
	_phase_time = 0.0
	AudioDirector.play(&"flipper_down")


func _physics_process(delta: float) -> void:
	_clock += delta
	if _present and not dead and _pivot_sitter() != null:
		_pivot_stall += delta
		if _pivot_stall >= Feel.FLIPPER_PIVOT_STALL_SECONDS:
			_pivot_stall = 0.0
			var sitter := _pivot_sitter()
			if sitter != null:
				sitter.kick(_pivot_pop_direction() * Feel.FLIPPER_PIVOT_POP)
				AudioDirector.play(&"wall_tap")
	else:
		_pivot_stall = 0.0
	if _jam > 0.0:
		_jam = maxf(_jam - delta, 0.0)
	if _telegraph > 0.0:
		_telegraph = maxf(_telegraph - delta, 0.0)
	_advance(delta)
	rotation.y = FlipperCurve.rotation_for(side, progress)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 5.0, 0.0)


func _process(delta: float) -> void:
	if _lamp == null:
		return
	var wanted := 0.0
	if _jam > 0.0 or _telegraph > 0.0:
		wanted = 0.6 + 0.4 * sin(_clock * 26.0)
		_lamp.emission = Feel.COL_DIRTY
	else:
		_lamp.emission = Color(1.0, 0.86, 0.55)
		wanted = _glow * 0.9
	_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier, wanted,
			1.0 - exp(-14.0 * delta))
	_lamp.albedo_color = Color("6A5A48") if dead else Color("E9DFC8")


func _advance(delta: float) -> void:
	_phase_time += delta
	match state:
		State.RISING:
			progress = FlipperCurve.up_progress(_phase_time)
			if _phase_time >= Feel.FLIPPER_UP_TIME:
				progress = 1.0
				state = State.HELD
				_phase_time = 0.0
				if not _held:
					_begin_fall()
		State.HELD:
			progress = 1.0
		State.FALLING:
			progress = FlipperCurve.down_progress(_phase_time, _fall_from)
			if FlipperCurve.down_remaining(_phase_time, _fall_from) <= 0.0:
				progress = 0.0
				state = State.REST
				_phase_time = 0.0
				_consume_buffer()
		State.REST:
			progress = 0.0


func _consume_buffer() -> void:
	if dead or _jam > 0.0:
		return
	if _held:
		_fire()
		return
	if _clock - _buffered_at <= Feel.INPUT_BUFFER:
		_fire()
	_buffered_at = -1000.0
