class_name HoldSaucer
extends Node3D
## A saucer/scoop: the ball drops in, is held (stepping a multiplier if it has steps), and
## is kicked out along `eject_dir`. Positions are table space; the dish is a real recess so
## the ball visibly settles before the kick.

signal captured()
signal stepped(step: int)
signal ejected(steps: int)

const STEP_SOUNDS: PackedStringArray = ["chime_a", "chime_b", "chime_c"]

@export var id: StringName = &"saucer"

var radius: float = 0.18
var hold_seconds: float = 0.8
var steps: PackedFloat32Array = PackedFloat32Array()
var step_seconds: float = 0.9
var eject_dir: Vector2 = Vector2(0.0, 1.0)
var eject_speed: float = 12.0
var eject_heat: float = 1.5
var cooldown_seconds: float = 0.5
var base_height: float = 0.0

var _present: bool = true
var _ball: Ball = null
var _held: bool = false
var _t: float = 0.0
var _step: int = 0
var _cool: float = 0.0
var _glow: float = 0.0
var _lamp: StandardMaterial3D = null


func configure(p_id: StringName, at: Vector2, p_radius: float, dir: Vector2, p_base: float = 0.0) -> void:
	id = p_id
	base_height = p_base
	position = Layout.p3(at, p_base)
	radius = p_radius
	eject_dir = dir.normalized()


func _ready() -> void:
	var lib := MaterialLib.shared()
	var st := MeshLib.begin()
	MeshLib.ring(st, Vector3.ZERO, radius * 0.30, radius * 1.05, -0.09, 0.0, 26)
	MeshLib.ring(st, Vector3.ZERO, radius * 1.05, radius * 1.22, 0.0, 0.03, 26)
	var dish := MeshInstance3D.new()
	dish.mesh = MeshLib.finish(st, lib.ink())
	dish.name = "Dish"
	add_child(dish)
	_lamp = lib.lamp(Feel.COL_VIOLET.lerp(Color.WHITE, 0.3))
	var st2 := MeshLib.begin()
	MeshLib.disc(st2, Vector3(0.0, -0.085, 0.0), radius * 0.30, 16)
	var lamp := MeshInstance3D.new()
	lamp.mesh = MeshLib.finish(st2, _lamp)
	lamp.name = "Lamp"
	add_child(lamp)


func set_ball(b: Ball) -> void:
	if _held and b != _ball:
		_held = false
	_ball = b


func holds_ball() -> bool:
	return _held and _ball != null and is_instance_valid(_ball)


func step_index() -> int:
	return _step


func multiplier() -> float:
	if steps.is_empty():
		return 1.0
	return steps[clampi(_step, 0, steps.size() - 1)]


func _rest_point() -> Vector3:
	return position + Vector3(0.0, Feel.BALL_RADIUS - 0.05, 0.0)


func _physics_process(delta: float) -> void:
	if not _present:
		return
	_cool = maxf(_cool - delta, 0.0)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.6, 0.0)
	if _ball == null or not is_instance_valid(_ball):
		_held = false
		return
	if _held:
		_hold(delta)
		return
	if _cool > 0.0 or BallHold.is_held(_ball):
		return
	var p := _ball.table_position()
	if absf(p.y - base_height - Feel.BALL_RADIUS) > 0.12:
		return                      # a ball on another storey passing overhead
	if Vector2(p.x, p.z).distance_to(Layout.plan(position)) <= radius - 0.02:
		_take()


func _take() -> void:
	_held = true
	_t = 0.0
	_step = 0
	_glow = 1.0
	BallHold.take(_ball)
	AudioDirector.play(&"safe_open" if steps.is_empty() else &"chime_a")
	TableScore.hit(id, _ball)
	captured.emit()


func _hold(delta: float) -> void:
	_t += delta
	BallHold.steer(_ball, _rest_point(), delta)
	if steps.is_empty():
		if _t >= hold_seconds:
			_eject()
		return
	if _t < step_seconds:
		return
	_t = 0.0
	_step += 1
	_glow = 1.0
	AudioDirector.play(StringName(STEP_SOUNDS[mini(_step - 1, STEP_SOUNDS.size() - 1)]))
	stepped.emit(_step)
	if _step >= steps.size() - 1:
		_eject()


func _eject() -> void:
	var held_steps := _step
	_held = false
	_cool = cooldown_seconds
	_glow = 1.0
	var speed := eject_speed + eject_heat * float(held_steps)
	var at := position + Vector3(0.0, Feel.BALL_RADIUS + 0.02, 0.0)
	BallHold.release(_ball, at, Vector3(eject_dir.x, 0.0, eject_dir.y) * speed)
	AudioDirector.play(&"kickback")
	ejected.emit(held_steps)


func _process(delta: float) -> void:
	if _lamp == null:
		return
	var wanted := 0.4
	if _held:
		wanted = 1.5 + float(_step) * 0.9
	elif _cool > 0.0 or not _present:
		wanted = 0.0
	_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier, wanted + _glow,
			1.0 - exp(-8.0 * delta))


func set_hardware_active(active: bool) -> void:
	if _present == active:
		return
	_present = active
	visible = active
	if not active and _held:
		_held = false
		BallHold.release(_ball, position + Vector3(0.0, Feel.BALL_RADIUS + 0.02, 0.0),
				Vector3(eject_dir.x, 0.0, eject_dir.y) * eject_speed)


func is_hardware_active() -> bool:
	return _present


func visual_state() -> int:
	if not _present or _cool > 0.0:
		return TableVisualState.VisualState.DISABLED
	if _held:
		return TableVisualState.VisualState.ACTIVE
	if _glow > 0.02:
		return TableVisualState.VisualState.COMPLETED
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"cooldown": _cool > 0.0, &"held": _held, &"marked": _step > 0, &"pulse": _glow > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
