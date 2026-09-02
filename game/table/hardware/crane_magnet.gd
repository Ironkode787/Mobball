class_name CraneMagnet
extends Node3D
## The docks' gantry crane: a trolley that tracks the ball along its rail and, on a period,
## telegraphs then swings the ball out to the harbour. A force, not a collider.

signal telegraph_started()
signal pulled(ball: Ball)

const PERIOD := 7.0
const TELEGRAPH := 1.2
const IMPULSE := 9.0
const TRAVEL_SPEED := 0.9
const HOOK_DROP := 0.35

@export var id: StringName = &"crane"

var active: bool = false
var self_driven: bool = true
var drop_point: Vector2 = Vector2.ZERO
var zone: Rect2 = Rect2()               ## plan-space yard
var rail_from: Vector2 = Vector2.ZERO
var rail_to: Vector2 = Vector2.ZERO
var rail_height: float = 1.0

var _ball: Ball = null
var _phase: float = 0.0
var _telegraphing: bool = false
var _flash: float = 0.0
var _travel: float = 0.0
var _travel_dir: float = 1.0
var _trolley: Node3D = null
var _hook: Node3D = null
var _lamp: StandardMaterial3D = null


func configure(p_id: StringName, from: Vector2, to: Vector2, p_zone: Rect2, p_drop: Vector2) -> void:
	id = p_id
	rail_from = from
	rail_to = to
	zone = p_zone
	drop_point = p_drop


func _ready() -> void:
	var lib := MaterialLib.shared()
	var rust := lib.plastic(Color("A9552E"), 0.65)
	var st := MeshLib.begin()
	var a := Layout.p3(rail_from)
	var b := Layout.p3(rail_to)
	MeshLib.post(st, rail_from, 0.045, rail_height, 0.0, 8)
	MeshLib.post(st, rail_to, 0.045, rail_height, 0.0, 8)
	MeshLib.tube(st, PackedVector3Array([a + Vector3(0, rail_height, 0), b + Vector3(0, rail_height, 0)]), 0.04, 6)
	MeshLib.tube(st, PackedVector3Array([a + Vector3(0, rail_height - 0.16, 0), b + Vector3(0, rail_height - 0.16, 0)]), 0.025, 6)
	var gantry := MeshInstance3D.new()
	gantry.mesh = MeshLib.finish(st, rust)
	gantry.name = "Gantry"
	add_child(gantry)
	_trolley = Node3D.new()
	_trolley.name = "Trolley"
	add_child(_trolley)
	var box := BoxMesh.new()
	box.size = Vector3(0.22, 0.12, 0.18)
	_lamp = lib.lamp(Feel.COL_DIRTY)
	var tm := MeshInstance3D.new()
	tm.mesh = box
	tm.material_override = _lamp
	_trolley.add_child(tm)
	_hook = Node3D.new()
	_hook.name = "Hook"
	_trolley.add_child(_hook)
	var cable := CylinderMesh.new()
	cable.top_radius = 0.008
	cable.bottom_radius = 0.008
	cable.height = HOOK_DROP
	var cm := MeshInstance3D.new()
	cm.mesh = cable
	cm.material_override = lib.steel()
	cm.position.y = -HOOK_DROP * 0.5
	_hook.add_child(cm)
	var magnet := CylinderMesh.new()
	magnet.top_radius = 0.09
	magnet.bottom_radius = 0.11
	magnet.height = 0.07
	var mm := MeshInstance3D.new()
	mm.mesh = magnet
	mm.material_override = lib.chrome_dark()
	mm.position.y = -HOOK_DROP
	_hook.add_child(mm)
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
	return PERIOD - _phase if active else -1.0


func trolley_position() -> Vector2:
	return rail_from.lerp(rail_to, _travel)


func has_target(b: Ball = null) -> bool:
	var target := b if b != null else _ball
	if target == null or not is_instance_valid(target):
		return false
	if BallHold.is_held(target):
		return false
	var p := target.table_position()
	return p.y < 0.5 and zone.has_point(Vector2(p.x, p.z))


func pull(b: Ball = null) -> bool:
	var target := b if b != null else _ball
	if target == null or not has_target(target):
		return false
	var dir := drop_point - Layout.plan(target.table_position())
	if dir.length() < 0.01:
		return false
	dir = dir.normalized()
	target.kick(Vector3(dir.x, 0.0, dir.y) * IMPULSE)
	AudioDirector.play(&"crane_pull")
	_flash = 1.0
	pulled.emit(target)
	return true


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
	if not active:
		return
	_run_gantry(delta)
	_phase += delta
	if not _telegraphing and _phase >= PERIOD - TELEGRAPH:
		_telegraphing = true
		AudioDirector.play(&"crane_telegraph")
		telegraph_started.emit()
	if _phase < PERIOD:
		return
	_phase = 0.0
	_telegraphing = false
	if self_driven:
		pull()


func _run_gantry(delta: float) -> void:
	var span := rail_from.distance_to(rail_to)
	if span < 0.01:
		return
	var want := -1.0
	if has_target():
		var p := Layout.plan(_ball.table_position())
		var along := (p - rail_from).dot((rail_to - rail_from) / span)
		want = clampf(along / span, 0.0, 1.0)
	if want >= 0.0:
		_travel = move_toward(_travel, want, TRAVEL_SPEED * delta / span * 2.0)
	else:
		_travel += _travel_dir * TRAVEL_SPEED * delta / span
		if _travel >= 1.0:
			_travel = 1.0
			_travel_dir = -1.0
		elif _travel <= 0.0:
			_travel = 0.0
			_travel_dir = 1.0


func _process(delta: float) -> void:
	if _trolley != null:
		_trolley.position = Layout.p3(trolley_position(), rail_height - 0.08)
	var warn := 0.0
	if _telegraphing:
		warn = clampf((_phase - (PERIOD - TELEGRAPH)) / TELEGRAPH, 0.0, 1.0)
	if _hook != null:
		_hook.scale.y = 0.4 + 0.6 * maxf(warn, _flash)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				(0.3 if active else 0.0) + warn * 2.5 + _flash * 2.0, 1.0 - exp(-12.0 * delta))


func set_hardware_active(p_active: bool) -> void:
	set_active(p_active)


func is_hardware_active() -> bool:
	return active


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not active:
		state = TableVisualState.VisualState.DISABLED
	elif _telegraphing:
		state = TableVisualState.VisualState.DANGER
		mods.append(&"telegraph")
	elif _flash > 0.02:
		state = TableVisualState.VisualState.COMPLETED
		mods.append(&"pulse")
	elif has_target():
		state = TableVisualState.VisualState.ARMED
	mods.append(&"moving" if _travel > 0.001 and _travel < 0.999 else &"parked")
	return TableVisualState.state_token(state, mods)


func visual_token() -> Dictionary:
	return visual_state()
