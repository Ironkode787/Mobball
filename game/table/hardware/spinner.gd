class_name Spinner
extends Node3D
## The numbers wheel: a bicycle wheel across the lane. The ball passing under it spins the
## blade; each half-turn is a tick of dirty money and one more number on your ticket.

signal spun(total: int)

const SPEED_PER_UNIT := 1.6      ## rad/s of blade per u/s of ball
const MIN_KICK := 6.0
const MAX_SPEED := 42.0
const FRICTION := 9.0

@export var id: StringName = &"spinner_numbers"

var lane_width: float = Layout.LANE_WIDTH_L
var spins_total: int = 0
var _present: bool = true
var _angle: float = 0.0
var _vel: float = 0.0
var _segment: int = 0
var _ball: Ball = null
var _area: Area3D = null
var _blade: Node3D = null


func configure(p_id: StringName, center: Vector2, p_lane_width: float) -> void:
	id = p_id
	position = Layout.p3(center)
	lane_width = p_lane_width


func _ready() -> void:
	_area = Area3D.new()
	_area.name = "Sensor"
	_area.collision_layer = Feel.LAYER_ZONES
	_area.collision_mask = Feel.LAYER_BALL
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(lane_width, 0.5, 0.16)
	cs.shape = box
	cs.position.y = 0.25
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_ball_entered)
	_area.body_exited.connect(_on_ball_exited)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var w := lane_width
	var axle_h := 0.40
	var st := MeshLib.begin()
	MeshLib.tube(st, PackedVector3Array([Vector3(-w * 0.5, axle_h, 0.0), Vector3(w * 0.5, axle_h, 0.0)]), 0.012, 6)
	MeshLib.post(st, Vector2(-w * 0.5 - 0.02, 0.0), 0.03, axle_h + 0.05, 0.0, 8)
	MeshLib.post(st, Vector2(w * 0.5 + 0.02, 0.0), 0.03, axle_h + 0.05, 0.0, 8)
	var frame := MeshInstance3D.new()
	frame.mesh = MeshLib.finish(st, lib.chrome_dark())
	frame.name = "Axle"
	add_child(frame)
	_blade = Node3D.new()
	_blade.name = "Blade"
	_blade.position.y = axle_h
	add_child(_blade)
	var radius := (w - 0.06) * 0.5
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"prop.bicycle_spinner", null, false)
	var mi := MeshInstance3D.new()
	if tex != null:
		# the wheel art is a top-down disc on ink: print it on a round blade, both faces
		var st_wheel := MeshLib.begin()
		MeshLib.disc(st_wheel, Vector3.ZERO, radius, 32, true)
		MeshLib.disc(st_wheel, Vector3.ZERO, radius, 32, false)
		mi.mesh = MeshLib.finish(st_wheel, lib.decal(tex, true))
		mi.rotation.x = PI * 0.5
	else:
		var plate := BoxMesh.new()
		plate.size = Vector3(radius * 2.0, radius * 1.4, 0.012)
		mi.mesh = plate
		mi.material_override = lib.brass_dark()
	_blade.add_child(mi)


func _on_ball_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	_ball = ball
	var v := ball.local_velocity()
	var dir := -1.0 if v.z < 0.0 else 1.0
	var kick := maxf(ball.speed() * SPEED_PER_UNIT, MIN_KICK)
	_vel = clampf(_vel * 0.35 + dir * kick, -MAX_SPEED, MAX_SPEED)


func _on_ball_exited(body: Node3D) -> void:
	if body == _ball:
		_ball = null


func _physics_process(delta: float) -> void:
	if not _present or is_zero_approx(_vel):
		return
	_angle += _vel * delta
	_vel = move_toward(_vel, 0.0, FRICTION * delta)
	var seg := int(floor(_angle / PI))
	while seg != _segment:
		_segment += 1 if seg > _segment else -1
		_score()


func _process(_delta: float) -> void:
	if _blade != null:
		_blade.rotation.x = _angle


func _score() -> void:
	spins_total += 1
	AudioDirector.play(&"spinner_tick")
	TableScore.earn(TableScore.GROUP_SPINNER, TableScore.SPINNER_SEGMENT, id, _ball)
	spun.emit(spins_total)


## Spin the blade by hand — the growth sim uses this instead of aiming a ball down a lane.
func kick(speed: float) -> void:
	_vel = clampf(speed, -MAX_SPEED, MAX_SPEED)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	if _area == null:
		return
	_area.collision_layer = Feel.LAYER_ZONES if _present else 0
	_area.collision_mask = Feel.LAYER_BALL if _present else 0


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif absf(_vel) > 0.1:
		state = TableVisualState.VisualState.ACTIVE
	return TableVisualState.state_token(state, {&"moving": absf(_vel) > 0.1})
