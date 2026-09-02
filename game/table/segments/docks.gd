class_name Docks
extends Node3D
## THE DOCKS (R5): a walled yard low on the left behind a one-way gate off the left orbit
## lane. Three container stacks on a raked deck, a gantry crane that swings the ball toward
## the harbour, the pier you can fall off, and the cargo scoop: a kicker at the yard's foot
## that fires the ball up a wireform over the yard's roof and back into the left lane.

signal docks_entered()
signal stack_cleared(stack: int)
signal containers_state(cleared_stacks: Array)
signal crane_telegraph()
signal crane_pulled()
signal cargo_shipped(speed: float)
signal pier_fall(ball: Ball)

const ID_DOCKS := &"docks"
const ID_CONTAINERS := &"containers"
const ID_CRANE := &"crane"
const ID_CARGO_RAMP := &"cargo_ramp"

const WALL_THICK := 0.07
const ROOF_FROM := Vector2(-2.15, 0.0)
const ROOF_TO := Vector2(-1.35, 0.15)
const RIGHT_FROM := Vector2(-1.35, 0.15)
const RIGHT_TO := Vector2(-1.35, 1.95)
## The bed of the yard is a beam that falls away to the right, so whatever rolls down the yard
## ends in the cargo scoop at its low end.
const BED_FROM := Vector2(-1.35, 2.07)
const BED_TO := Vector2(-2.16, 1.93)
## The quay is a one-way flap: the kickback throws an outlane ball up into the yard through
## it, and nothing in the yard rolls back down onto the flippers that way.
const QUAY_FROM := Vector2(-2.52, 1.86)
const QUAY_TO := Vector2(-2.16, 1.93)
const BLADE_FROM := Vector2(-2.52, -0.02)
const BLADE_TO := Vector2(-2.2, 0.0)
const CRATES_ORIGIN := Vector2(-2.28, 0.55)
## Off the end of the pier: a hole in the yard floor by the water, and the ball is gone.
const WATER_AT := Vector2(-2.40, 1.62)
const WATER_SIZE := Vector2(0.22, 0.28)
const GANTRY_FROM := Vector2(-2.38, 0.32)
const GANTRY_TO := Vector2(-1.45, 0.42)
const SCOOP_AT := Vector2(-1.52, 1.76)
const SCOOP_R := 0.16
const CARGO_KICK := 19.0
## The wireform starts a ball's height above the yard floor so the bed runs under its mouth;
## the scoop lifts the ball into it. It soars over the crane's gantry (and over the Club's
## return wireform, which crosses the yard low) before dropping into the left lane.
const CARGO_PATH: PackedVector3Array = [
	Vector3(-1.52, 0.34, 1.76), Vector3(-1.46, 0.50, 1.35), Vector3(-1.42, 0.78, 0.90),
	Vector3(-1.50, 1.08, 0.45), Vector3(-1.75, 1.16, 0.00), Vector3(-2.08, 1.08, -0.50),
	Vector3(-2.32, 0.86, -1.00), Vector3(-2.38, 0.60, -1.30), Vector3(-2.36, 0.46, -1.48),
]
const COL_RUST := Color("A9552E")
const COL_WATER := Color("173A4A")

var containers: ContainerStacks = null
var crane: CraneMagnet = null
var cargo_ramp: RampLane = null
var gate: OneWayGate = null
var quay_gate: OneWayGate = null
var scoop: Area3D = null

var _present: bool = false
var _shell: WallPiece = null
var _ball: Ball = null
var _was_outside: bool = true
var _scoop_ball: Ball = null
var _scoop_t: float = -1.0
var _scoop_cooldown: float = 0.0
var _look: Node3D = null


func _ready() -> void:
	_build_shell()
	_build_gate()
	_build_containers()
	_build_crane()
	_build_cargo()
	_build_look()


func _build_shell() -> void:
	_shell = WallPiece.new(Layout.GUIDE_HEIGHT, 0.0, MaterialLib.shared().plastic(Color("5A4636"), 0.6))
	_shell.name = "DocksShell"
	add_child(_shell)
	_shell.bar(ROOF_FROM, ROOF_TO, WALL_THICK)
	_shell.bar(RIGHT_FROM, RIGHT_TO, WALL_THICK)
	_shell.bar(BED_FROM, BED_TO, WALL_THICK)
	# a gangway just inside the gate slides an arriving ball off the left wall toward the scoop,
	# and a bollard rail above the water does the same for anything rolling down the wall: only
	# the crane puts a ball in the harbour
	_shell.bar(Vector2(-2.51, 0.14), Vector2(-2.20, 0.60), Layout.GUIDE_THICK)
	_shell.bar(Vector2(-2.52, 1.24), Vector2(-2.28, 1.50), Layout.GUIDE_THICK)


func _build_gate() -> void:
	gate = OneWayGate.new()
	gate.name = "DockGate"
	gate.configure(&"dock_gate", BLADE_FROM, BLADE_TO, 0.04, Vector2(0.0, -1.0))
	add_child(gate)
	quay_gate = OneWayGate.new()
	quay_gate.name = "QuayGate"
	quay_gate.configure(&"quay_gate", QUAY_FROM, QUAY_TO, 0.04, Vector2(0.0, 1.0))
	add_child(quay_gate)


func _build_containers() -> void:
	containers = ContainerStacks.new()
	containers.name = "Containers"
	containers.configure(ID_CONTAINERS, CRATES_ORIGIN)
	add_child(containers)
	containers.stack_cleared.connect(func(s: int) -> void: stack_cleared.emit(s))
	containers.state_changed.connect(func(cleared: Array) -> void: containers_state.emit(cleared))


func _build_crane() -> void:
	crane = CraneMagnet.new()
	crane.name = "Crane"
	crane.configure(ID_CRANE, GANTRY_FROM, GANTRY_TO, yard_rect(), WATER_AT)
	add_child(crane)
	crane.telegraph_started.connect(func() -> void: crane_telegraph.emit())
	crane.pulled.connect(func(_b: Ball) -> void: crane_pulled.emit())


func _build_cargo() -> void:
	cargo_ramp = RampLane.new()
	cargo_ramp.name = "CargoRamp"
	cargo_ramp.entry_speed = 0.0
	cargo_ramp.entry_size = Vector2(0.4, 0.3)
	cargo_ramp.flare_width = 0.40
	cargo_ramp.color = COL_RUST.lightened(0.2)
	cargo_ramp.configure(ID_CARGO_RAMP, CARGO_PATH)
	add_child(cargo_ramp)
	cargo_ramp.crested.connect(_on_cargo_crested)
	scoop = Area3D.new()
	scoop.name = "CargoScoop"
	scoop.collision_layer = Feel.LAYER_ZONES
	scoop.collision_mask = Feel.LAYER_BALL
	scoop.monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = SCOOP_R
	cyl.height = 0.2                 # stays under the wireform floor: a fired ball never re-trips it
	cs.shape = cyl
	scoop.position = Layout.p3(SCOOP_AT, 0.1)
	scoop.add_child(cs)
	add_child(scoop)
	scoop.body_entered.connect(_on_scoop_entered)


## The water is a hole in the yard floor; a ball drops in when its centre crosses the edge, so
## the test is on the ball's centre, not on its rim brushing the hole (an Area3D would fire on
## the rim). A ball the kickback throws up through the quay crosses the hole in a few
## milliseconds and clears it; a ball rolling or dragged down onto the pier drops in.
const PIER_CLEAR_SPEED := 8.0


func _pier_rect() -> Rect2:
	var size := WATER_SIZE - Vector2(0.06, 0.06)
	return Rect2(WATER_AT - size * 0.5, size)


func _check_pier(b: Ball) -> void:
	var p := b.table_position()
	if p.y > 0.5 or not _pier_rect().has_point(Vector2(p.x, p.z)):
		return
	if b.local_velocity().z < -PIER_CLEAR_SPEED:
		return
	pier_fall.emit(b)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var water := PlaneMesh.new()
	water.size = WATER_SIZE * 1.1
	var wm := MeshInstance3D.new()
	wm.mesh = water
	wm.material_override = lib.water()
	wm.position = Layout.p3(WATER_AT, 0.003)
	_look.add_child(wm)
	var pier_edge := MeshLib.begin()
	MeshLib.prism(pier_edge, PackedVector2Array([
		WATER_AT + Vector2(WATER_SIZE.x * 0.5, -WATER_SIZE.y * 0.5), WATER_AT + Vector2(WATER_SIZE.x * 0.5 + 0.06, -WATER_SIZE.y * 0.5),
		WATER_AT + Vector2(WATER_SIZE.x * 0.5 + 0.06, WATER_SIZE.y * 0.5), WATER_AT + Vector2(WATER_SIZE.x * 0.5, WATER_SIZE.y * 0.5),
	]), 0.03, 0.0)
	var pe := MeshInstance3D.new()
	pe.mesh = MeshLib.finish(pier_edge, lib.wood())
	_look.add_child(pe)
	# quay boards
	var st := MeshLib.begin()
	var n := 6
	for i in range(n):
		var a := QUAY_FROM.lerp(QUAY_TO, float(i) / float(n))
		var b := QUAY_FROM.lerp(QUAY_TO, float(i + 1) / float(n) - 0.02)
		MeshLib.prism(st, PackedVector2Array([a + Vector2(0, -0.14), b + Vector2(0, -0.14), b, a]), 0.015, 0.0)
	var qm := MeshInstance3D.new()
	qm.mesh = MeshLib.finish(st, lib.wood())
	_look.add_child(qm)
	# a scoop hood over the cargo kicker
	var hood := BoxMesh.new()
	hood.size = Vector3(0.36, 0.22, 0.2)
	var hm := MeshInstance3D.new()
	hm.mesh = hood
	hm.material_override = lib.plastic(COL_RUST, 0.6)
	hm.position = Layout.p3(SCOOP_AT + Vector2(0.0, 0.14), 0.30)
	_look.add_child(hm)
	var sign := TextMesh.new()
	sign.text = "THE DOCKS"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 44
	sign.pixel_size = 0.0055
	sign.depth = 0.02
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = lib.neon(Feel.COL_NEON_TEAL, 2.4)
	sm.position = Layout.p3(GANTRY_FROM.lerp(GANTRY_TO, 0.5), 1.15)
	_look.add_child(sm)


func set_ball(b: Ball) -> void:
	_ball = b
	if b == null or not is_instance_valid(b):
		_was_outside = true
	if _scoop_ball != b:
		_scoop_ball = null
		_scoop_t = -1.0
	for holder: Node in [cargo_ramp, crane, gate, quay_gate]:
		if holder != null:
			holder.call(&"set_ball", b)


func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_CONTAINERS], "node": containers},
		{"ids": [ID_CRANE], "node": crane},
		{"ids": [ID_CARGO_RAMP], "node": cargo_ramp},
	]


func bounds() -> AABB:
	return AABB(Vector3(-2.6, -0.1, -0.1), Vector3(1.3, 1.2, 2.3))


func yard_rect() -> Rect2:
	return Rect2(Vector2(-2.52, ROOF_FROM.y), Vector2(RIGHT_TO.x + 2.52, BED_TO.y - ROOF_FROM.y))


func holds_ball() -> bool:
	return (cargo_ramp != null and cargo_ramp.riding()) or _scoop_ball != null


func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	return BallHold.is_held(ball) and holds_ball()


func _physics_process(delta: float) -> void:
	if not _present:
		return
	_scoop_cooldown = maxf(0.0, _scoop_cooldown - delta)
	if _scoop_ball != null:
		if not is_instance_valid(_scoop_ball):
			_scoop_ball = null
		else:
			_scoop_t += delta
			BallHold.steer(_scoop_ball, Layout.p3(SCOOP_AT, Feel.BALL_RADIUS - 0.02), delta)
			if _scoop_t >= 0.55:
				_fire_scoop()
	if _ball == null or not is_instance_valid(_ball):
		return
	var p := _ball.table_position()
	var inside := p.y < 0.5 and yard_rect().has_point(Vector2(p.x, p.z))
	if inside and _was_outside:
		AudioDirector.play(&"wall_tap")
		docks_entered.emit()
	_was_outside = not inside
	if inside:
		_check_pier(_ball)


func _on_scoop_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present or _scoop_ball != null or _scoop_cooldown > 0.0:
		return
	var b := body as Ball
	if BallHold.is_held(b):
		return
	_scoop_ball = b
	_scoop_t = 0.0
	BallHold.take(b)
	AudioDirector.play(&"safe_open")
	TableScore.hit(&"cargo_scoop", b)


func _fire_scoop() -> void:
	var b := _scoop_ball
	_scoop_ball = null
	_scoop_t = -1.0
	if b == null or not is_instance_valid(b):
		return
	var dir := (CARGO_PATH[1] - CARGO_PATH[0]).normalized()
	_scoop_cooldown = 1.0
	BallHold.release(b, CARGO_PATH[0] + Vector3(0.0, Feel.BALL_RADIUS + 0.01, 0.0), dir * CARGO_KICK)
	AudioDirector.play(&"kickback")


func _on_cargo_crested(speed: float) -> void:
	AudioDirector.play(&"orbit_whoosh")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, ID_CARGO_RAMP, _ball, speed)
	cargo_shipped.emit(speed)




func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_was_outside = true
	for piece: Node in [_shell, gate, quay_gate]:
		if piece != null:
			Dormant.apply(piece, active)
	if scoop != null:
		scoop.collision_layer = Feel.LAYER_ZONES if active else 0
		scoop.collision_mask = Feel.LAYER_BALL if active else 0
	if not active:
		_release_everything()


func is_hardware_active() -> bool:
	return _present


func _release_everything() -> void:
	if _scoop_ball != null and is_instance_valid(_scoop_ball):
		BallHold.release(_scoop_ball, Layout.p3(SCOOP_AT, Feel.BALL_RADIUS), Vector3.ZERO)
	_scoop_ball = null
	_scoop_t = -1.0
	if cargo_ramp != null:
		cargo_ramp.set_hardware_active(false)
	if crane != null:
		crane.set_active(false)
