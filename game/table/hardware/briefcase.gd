class_name Briefcase
extends Node3D
## The bagman's case, put down on the felt for a minute: touch it to collect, or watch him
## pick it up and walk. No collider — it is a token, not furniture.

signal collected(ball: Ball)
signal expired()

const LENGTH := 0.22
const THICK := 0.11
const REACH := (LENGTH + THICK) * 0.5
const RAKE_DEG := -12.0
const LIFETIME := 60.0
const WALK_SECONDS := 0.8
const WALK_DISTANCE := 0.75

@export var id: StringName = &"briefcase"

var lifetime: float = LIFETIME
var _live: bool = false
var _left: float = 0.0
var _walk: float = 0.0
var _glow: float = 0.0
var _walk_dir: float = -1.0
var _resolution: StringName = &"none"
var _look: Node3D = null
var _lamp: StandardMaterial3D = null


func _ready() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	add_child(_look)
	var body := BoxMesh.new()
	body.size = Vector3(LENGTH, 0.16, THICK)
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = lib.plastic(Color("3A2418"), 0.5)
	bm.position.y = 0.08
	_look.add_child(bm)
	_lamp = lib.lamp(Feel.COL_BRASS)
	var trim := BoxMesh.new()
	trim.size = Vector3(LENGTH * 0.9, 0.02, THICK + 0.01)
	var tm := MeshInstance3D.new()
	tm.mesh = trim
	tm.material_override = _lamp
	tm.position.y = 0.09
	_look.add_child(tm)
	var handle := TorusMesh.new()
	handle.inner_radius = 0.02
	handle.outer_radius = 0.035
	var hm := MeshInstance3D.new()
	hm.mesh = handle
	hm.material_override = lib.brass()
	hm.position = Vector3(0.0, 0.17, 0.0)
	hm.rotation.x = PI * 0.5
	_look.add_child(hm)
	visible = false


func drop_at(at: Vector2) -> void:
	position = Layout.p3(at)
	rotation.y = deg_to_rad(RAKE_DEG)
	_live = true
	_resolution = &"none"
	_left = maxf(lifetime, 0.1)
	_walk = 0.0
	_glow = 1.0
	_walk_dir = -1.0 if at.x < 0.0 else 1.0
	visible = true
	if _look != null:
		_look.position = Vector3.ZERO
	AudioDirector.play(&"briefcase_drop")


func is_live() -> bool:
	return _live


func seconds_left() -> float:
	return _left if _live else 0.0


func clear() -> void:
	_live = false
	_walk = 0.0
	_resolution = &"none"
	visible = false


func _physics_process(delta: float) -> void:
	if _walk > 0.0:
		_walk = maxf(_walk - delta, 0.0)
		var t := 1.0 - _walk / WALK_SECONDS
		if _look != null:
			_look.position = Vector3(_walk_dir * WALK_DISTANCE * t, 0.12 * sin(t * PI), 0.0)
		if _walk <= 0.0:
			visible = false
	if not _live:
		return
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.5, 0.0)
	_left -= delta
	if _left <= 0.0:
		_take_it_back()
		return
	var ball := _toucher()
	if ball != null:
		_collect(ball)


func _process(delta: float) -> void:
	if _lamp != null:
		var blink := 1.0 if (_left > 10.0 or fmod(_left, 0.5) > 0.25) else 0.2
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				(1.2 * blink + _glow) if _live else 0.0, 1.0 - exp(-10.0 * delta))


func _toucher() -> Ball:
	var half := LENGTH * 0.5
	var axis := Vector2.RIGHT.rotated(-rotation.y)
	var reach := THICK * 0.5 + Feel.BALL_RADIUS + 0.02
	var here := Layout.plan(position)
	for b in Balls.live():
		if b == null or not is_instance_valid(b) or BallHold.is_held(b):
			continue
		var p := b.table_position()
		if absf(p.y - Feel.BALL_RADIUS) > 0.3:
			continue
		var pp := Vector2(p.x, p.z)
		var along := clampf((pp - here).dot(axis), -half, half)
		if (here + axis * along).distance_to(pp) <= reach:
			return b
	return null


func _collect(ball: Ball) -> void:
	_live = false
	visible = false
	_resolution = &"collected"
	AudioDirector.play(&"drop_clack")
	TableScore.hit(id, ball)
	collected.emit(ball)


func _take_it_back() -> void:
	_live = false
	_walk = WALK_SECONDS
	_resolution = &"expired"
	AudioDirector.play(&"briefcase_leave")
	expired.emit()


func set_hardware_active(active: bool) -> void:
	if not active:
		clear()


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.DISABLED
	var mods: Array[StringName] = []
	if _live:
		state = TableVisualState.VisualState.ARMED
	elif _walk > 0.0 or _resolution == &"collected":
		state = TableVisualState.VisualState.COMPLETED
		if _resolution == &"expired":
			mods.append(&"flash")
	return TableVisualState.state_token(state, mods)


func visual_token() -> Dictionary:
	return visual_state()
