class_name RouletteWheel
extends Node3D
## The Club's roulette: a bowl the ball rolls into, a ring of eight pockets turning under it.
## Slow enough and close enough to a pocket, the ball drops in, is held a beat and thrown
## back out. Three pockets are the house's; Influence buys them back one at a time.

signal landed(pocket: int, house: bool)
signal thrown(pocket: int)

const POCKETS := 8
const HOUSE_POCKETS: PackedInt32Array = [0, 3, 6]
const HOUSE_GIVE_ORDER: PackedInt32Array = [6, 3, 0]
const PLAYER_POCKETS_BASE := 5
const RADIUS := 0.32
const WALL_THICK := 0.05
const POCKET_RING := 0.19
const POCKET_R := 0.085
const GRAB := 0.11
const SPIN := 0.9
const HOLD := 1.2
const CAPTURE_SPEED := 9.0
const EJECT_SPEED := 11.0
const EJECT_DIR := Vector2(0.72, 0.69)      ## out of the bowl's open side, down the deck
const COOLDOWN := 0.55
const FORCE_AFTER := 3.0

@export var id: StringName = &"roulette_wheel"

var angle: float = 0.0
var base_height: float = 0.0
var _present: bool = true
var _ball: Ball = null
var _bowl: StaticBody3D = null
var _held: bool = false
var _pocket: int = 0
var _hold_t: float = 0.0
var _cool: float = 0.0
var _inside_t: float = 0.0
var _flash: float = 0.0
var _last_pocket: int = -1
var _player_pockets: int = PLAYER_POCKETS_BASE
var _wheel: Node3D = null
var _pocket_lamps: Array[StandardMaterial3D] = []


func configure(p_id: StringName, at: Vector2, p_base: float) -> void:
	id = p_id
	base_height = p_base
	position = Layout.p3(at, p_base)


func _ready() -> void:
	_bowl = WallBuilder.make_body("Bowl")
	add_child(_bowl)
	var walls := WallBuilder.new(_bowl, Layout.GUIDE_HEIGHT, 0.0)
	# the upper half is the bowl's back wall (up-field); the open side faces the deck below
	walls.arc(Vector2.ZERO, RADIUS, 180.0, 360.0, 22, WALL_THICK)
	walls.build_mesh(MaterialLib.shared().brass_dark(), MaterialLib.shared().brass())
	_build_look()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_wheel = Node3D.new()
	_wheel.name = "Wheel"
	add_child(_wheel)
	var disc := CylinderMesh.new()
	disc.top_radius = RADIUS - WALL_THICK
	disc.bottom_radius = RADIUS - WALL_THICK
	disc.height = 0.02
	disc.radial_segments = 40
	var dm := MeshInstance3D.new()
	dm.mesh = disc
	dm.material_override = lib.plastic(Color("2A1E30"), 0.4)
	dm.position.y = 0.01
	_wheel.add_child(dm)
	for i in range(POCKETS):
		var a := float(i) * TAU / float(POCKETS)
		var lamp := lib.lamp(Feel.COL_DIRTY if is_house(i) else Feel.COL_BRASS)
		_pocket_lamps.append(lamp)
		var pocket := CylinderMesh.new()
		pocket.top_radius = POCKET_R
		pocket.bottom_radius = POCKET_R * 0.8
		pocket.height = 0.03
		pocket.radial_segments = 16
		var pm := MeshInstance3D.new()
		pm.mesh = pocket
		pm.material_override = lamp
		pm.position = Vector3(cos(a) * POCKET_RING, 0.03, sin(a) * POCKET_RING)
		_wheel.add_child(pm)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.06
	hub.bottom_radius = 0.08
	hub.height = 0.12
	var hm := MeshInstance3D.new()
	hm.mesh = hub
	hm.material_override = lib.brass()
	hm.position.y = 0.06
	_wheel.add_child(hm)


func set_ball(b: Ball) -> void:
	if _held and b != _ball:
		_held = false
	_ball = b


func holds_ball() -> bool:
	return _held and _ball != null and is_instance_valid(_ball)


func pocket_count() -> int:
	return POCKETS


static func is_house(pocket: int) -> bool:
	return HOUSE_POCKETS.has(pocket)


func refresh_pockets() -> void:
	var n := PLAYER_POCKETS_BASE
	if Game != null and Game.stats != null and Game.stats.has_method("casino_player_pockets"):
		n = int(Game.stats.call("casino_player_pockets"))
	_player_pockets = clampi(n, 1, POCKETS - 1)


func player_pockets() -> int:
	return _player_pockets


func house_pocket_count() -> int:
	return POCKETS - _player_pockets


func is_house_now(pocket: int) -> bool:
	var keep := clampi(house_pocket_count(), 0, HOUSE_POCKETS.size())
	for i in range(HOUSE_GIVE_ORDER.size()):
		if HOUSE_GIVE_ORDER[i] != pocket:
			continue
		return i >= HOUSE_GIVE_ORDER.size() - keep
	return false


func pocket_angle(i: int) -> float:
	return angle + float(i) * TAU / float(POCKETS)


## Table-space centre of pocket i (on the deck's floor).
func pocket_position(i: int) -> Vector3:
	var a := pocket_angle(i)
	return position + Vector3(cos(a), 0.0, sin(a)) * POCKET_RING


func rest_position() -> Vector3:
	return position + Vector3(0.0, Feel.BALL_RADIUS, RADIUS - WALL_THICK * 0.5 - Feel.BALL_RADIUS)


func last_pocket() -> int:
	return _last_pocket


func _physics_process(delta: float) -> void:
	if not _present:
		return
	angle = wrapf(angle + SPIN * delta, 0.0, TAU)
	refresh_pockets()
	_cool = maxf(_cool - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)
	if _ball == null or not is_instance_valid(_ball):
		_held = false
		_inside_t = 0.0
		return
	if _held:
		_hold_t += delta
		BallHold.steer(_ball, pocket_position(_pocket) + Vector3(0.0, Feel.BALL_RADIUS - 0.03, 0.0), delta)
		if _hold_t >= HOLD:
			_throw()
		return
	if BallHold.is_held(_ball):
		_inside_t = 0.0
		return
	var p := _ball.table_position()
	if absf(p.y - base_height - Feel.BALL_RADIUS) > 0.3:
		_inside_t = 0.0
		return
	var d := Vector2(p.x, p.z).distance_to(Layout.plan(position))
	if d > RADIUS - WALL_THICK * 0.5:
		_inside_t = 0.0
		return
	_inside_t += delta
	if _cool > 0.0:
		return
	var forced := _inside_t >= FORCE_AFTER
	if not forced and _ball.speed() > CAPTURE_SPEED:
		return
	var best := -1
	var best_d := INF
	for i in range(POCKETS):
		var pp := pocket_position(i)
		var pd := Vector2(p.x, p.z).distance_to(Vector2(pp.x, pp.z))
		if pd < best_d:
			best_d = pd
			best = i
	if best < 0:
		return
	if best_d > GRAB and not forced:
		return
	_take(best)


func _take(pocket: int) -> void:
	_held = true
	_pocket = pocket
	_last_pocket = pocket
	_hold_t = 0.0
	_inside_t = 0.0
	_flash = 1.0
	BallHold.take(_ball)
	AudioDirector.play(&"coin_drop")
	TableScore.earn(TableScore.GROUP_CASINO, TableScore.CASINO_POCKET, id, _ball)
	landed.emit(pocket, is_house_now(pocket))


func _throw() -> void:
	_held = false
	_cool = COOLDOWN
	var a := pocket_angle(_pocket)
	var tangential := Vector2(-sin(a), cos(a))
	var dir := (EJECT_DIR + tangential * 0.18).normalized()
	var at := pocket_position(_pocket) + Vector3(0.0, Feel.BALL_RADIUS + 0.02, 0.0)
	BallHold.release(_ball, at, Vector3(dir.x, 0.0, dir.y) * EJECT_SPEED)
	AudioDirector.play(&"kickback")
	thrown.emit(_pocket)


func _process(delta: float) -> void:
	if _wheel != null:
		_wheel.rotation.y = -angle
	for i in range(_pocket_lamps.size()):
		var lamp := _pocket_lamps[i]
		var house := is_house_now(i)
		lamp.emission = Feel.COL_DIRTY if house else Feel.COL_BRASS
		var wanted := 0.4 if _present else 0.0
		if _held and i == _pocket:
			wanted = 3.0
		lamp.emission_energy_multiplier = lerpf(lamp.emission_energy_multiplier, wanted, 1.0 - exp(-10.0 * delta))


func set_hardware_active(active: bool) -> void:
	if _present == active:
		return
	_present = active
	visible = active
	_bowl.collision_layer = Feel.LAYER_WALLS if active else 0
	_inside_t = 0.0
	if not active and _held:
		_held = false
		BallHold.release(_ball, position + Vector3(0.0, Feel.BALL_RADIUS, RADIUS + 0.3), Vector3.ZERO)


func is_hardware_active() -> bool:
	return _present


func visual_state() -> int:
	if not _present or _cool > 0.0:
		return TableVisualState.VisualState.DISABLED
	if _held or _inside_t > 0.0:
		return TableVisualState.VisualState.ACTIVE
	if _flash > 0.0:
		return TableVisualState.VisualState.COMPLETED
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"cooldown": _cool > 0.0, &"held": _held, &"flash": _flash > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
