class_name DrainMagnet
extends Node3D
## A cop's magnet under the felt: winds up on a period, telegraphs, then yanks the ball toward
## its drain point. The Captain's coil sits over the drain; the Director's sits mid-field.

signal telegraph_started()
signal pulled(ball: Ball)

const PERIOD := 6.0
const TELEGRAPH := 1.2
const IMPULSE := Feel.MAGNET_IMPULSE

var active: bool = false
var self_driven: bool = false
var drain_point: Vector2 = Vector2(0.0, 5.6)
var rate: float = 1.0

var _ball: Ball = null
var _phase: float = 0.0
var _telegraphing: bool = false
var _flash: float = 0.0
var _lamp: StandardMaterial3D = null


func _ready() -> void:
	var lib := MaterialLib.shared()
	_lamp = lib.lamp(Feel.COL_COP)
	var st := MeshLib.begin()
	MeshLib.ring(st, Vector3(0.0, 0.004, 0.0), 0.18, 0.30, 0.0, 0.0, 26)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, _lamp)
	mi.name = "CoilRing"
	add_child(mi)
	visible = false


func set_ball(b: Ball) -> void:
	_ball = b


func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	visible = on
	_phase = 0.0
	_telegraphing = false
	_flash = 0.0


func is_telegraphing() -> bool:
	return _telegraphing


func time_to_pull() -> float:
	return (PERIOD - _phase) / _rate() if active else -1.0


func reschedule(seconds: float) -> void:
	_phase = PERIOD - clampf(seconds * _rate(), 0.0, PERIOD)
	_telegraphing = _phase >= _telegraph_at()


func _rate() -> float:
	return clampf(rate, 0.25, 4.0)


func _telegraph_at() -> float:
	return maxf(PERIOD - TELEGRAPH * _rate(), PERIOD * 0.2)


func pull(b: Ball = null) -> void:
	var target := b if b != null else _ball
	if target == null or not is_instance_valid(target):
		return
	var p := Layout.plan(target.table_position())
	var dir := drain_point - p
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	target.kick(Vector3(dir.x, 0.0, dir.y) * IMPULSE)
	_flash = 1.0
	pulled.emit(target)


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
	if not active:
		return
	_phase += delta * _rate()
	if not _telegraphing and _phase >= _telegraph_at():
		_telegraphing = true
		telegraph_started.emit()
	if _phase < PERIOD:
		return
	_phase = 0.0
	_telegraphing = false
	if self_driven:
		pull()


func _process(delta: float) -> void:
	if _lamp == null:
		return
	var wanted := 0.0
	if active:
		wanted = 0.3
		if _telegraphing:
			wanted = 1.2 + 1.2 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.03))
		wanted += _flash * 3.0
	_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier, wanted, 1.0 - exp(-12.0 * delta))


func visual_state() -> int:
	if not active:
		return TableVisualState.VisualState.DISABLED
	if _telegraphing or _flash > 0.02:
		return TableVisualState.VisualState.DANGER
	return TableVisualState.VisualState.IDLE


func visual_modifiers() -> Dictionary:
	return {&"telegraph": _telegraphing, &"flash": _flash > 0.02, &"raid_phase": active}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
