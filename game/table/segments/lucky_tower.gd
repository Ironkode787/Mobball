class_name LuckyTower
extends Node3D
## LUCKY'S TOWER (docs/20 §3.2), the signature mechanism, in the middle of the Street. A ball
## that reaches the laundromat's front is taken by the washer and tumbles behind its porthole for
## the length of the wash cycle, then the glass service lift takes it down to the basement, which
## runs under the plaza to the Alley: the ball comes up out of the Alley's manhole among the
## cans. With the Penthouse owned and the Sit-Down lit, the lift goes up first, seats the ball at
## the Commission table for a beat, and brings it back down.
##
## The ball is out of physics while it rides (BallHold) and is handed back at the manhole with
## a real velocity; physics owns it again from there.

signal entered(ball: Ball)                ## the scoop took a ball (jobs accept here)
signal washed(ball: Ball)                 ## a wash cycle finished (laundromat_pass)
signal top_floor_reached(ball: Ball)      ## the lift delivered the ball to the Penthouse
signal top_floor_left(ball: Ball)
signal released(ball: Ball)

const ID_LAUNDROMAT := &"laundromat_loop"
const ID_PENTHOUSE := &"penthouse"
const DRUM_R := 0.12                      ## radius the ball tumbles round inside the drum
const LIFT_SPEED := 1.6                   ## u/s up the shaft
const TOP_FLOOR_H := 1.20
const SIT_SECONDS := 2.4
## The drop from the lift into the basement, and the beat under the plaza before the manhole.
const SINK_SECONDS := 0.30
const UNDER_SECONDS := 0.35
## Up out of the Alley's manhole, a random way (seeded, so a sim replays exactly), at the
## Sewer's pace: whichever way, a can is in reach.
const POP_SPEED := 4.5
## A ball the washer cannot take (the lift is busy) comes straight back off the door.
const REFUSE_SPEED := 6.0

enum Phase { IDLE, DRUM, TO_LIFT, UP, SEATED, DOWN, OUT }

var wash_seconds: float = 1.8
var penthouse_open: bool = false          ## the Penthouse is owned
var sitdown_lit: bool = false             ## the flow lit the top floor for this ride
var open: bool = true                     ## Coin-Op Washer owned: the scoop takes balls

var _ball: Ball = null
var _phase: Phase = Phase.IDLE
var _t: float = 0.0
var _scoop: Area3D = null
var _cool: float = 0.0
var _lib: MaterialLib = null
var _porthole: StandardMaterial3D = null
var _sign: StandardMaterial3D = null
var _floor_lamps: Array[StandardMaterial3D] = []
var _lift_car: Node3D = null
var _drum: Node3D = null
var _riders: Array[Ball] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0x1ACC5
	_lib = MaterialLib.shared()
	_build_body()
	_build_scoop()
	_build_look()


## The washer is set in the front wall, its porthole facing the flippers.
func drum_center() -> Vector3:
	var r := Layout.TOWER_RECT
	return Vector3(r.position.x + r.size.x * 0.5, 0.26, r.position.y + r.size.y - 0.02)


## The lift runs up the back of the tower, beside the back door.
func lift_bottom() -> Vector3:
	var r := Layout.TOWER_RECT
	return Vector3(r.position.x + r.size.x * 0.5, 0.20, r.position.y + 0.10)


## Where the ball comes back into play: the Alley's manhole.
func door_point() -> Vector3:
	return Layout.p3(Layout.MANHOLE_AT[2], Feel.BALL_RADIUS + 0.02)


## The tower's footprint: the front rectangle and the ridge its back rises to.
static func footprint() -> PackedVector2Array:
	var r := Layout.TOWER_RECT
	var x0 := r.position.x
	var x1 := r.position.x + r.size.x
	var z0 := r.position.y
	var z1 := r.position.y + r.size.y
	return PackedVector2Array([Vector2(x0, z1), Vector2(x1, z1), Vector2(x1, z0), Layout.TOWER_RIDGE,
			Vector2(x0, z0)])


func _build_body() -> void:
	var body := WallBuilder.make_body("TowerWalls")
	add_child(body)
	var walls := WallBuilder.new(body, Layout.WALL_HEIGHT)
	var f := footprint()
	walls.chain(PackedVector2Array([f[0], f[1], f[2], f[3], f[4], f[0]]), 0.06)
	walls.build_mesh(_lib.wood_dark(), _lib.brass())


## The front door: a ball that comes within a hair of the laundromat's front is the washer's.
func _build_scoop() -> void:
	_scoop = Area3D.new()
	_scoop.name = "Scoop"
	_scoop.collision_layer = Feel.LAYER_ZONES
	_scoop.collision_mask = Feel.LAYER_BALL
	_scoop.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Layout.SCOOP_SIZE.x, 0.4, Layout.SCOOP_SIZE.y)
	cs.shape = box
	cs.position = Layout.p3(Layout.SCOOP_AT, 0.2)
	_scoop.add_child(cs)
	add_child(_scoop)
	_scoop.body_entered.connect(_on_scoop)


func _build_look() -> void:
	var r := Layout.TOWER_RECT
	var x0 := r.position.x
	var z0 := r.position.y
	var w := r.size.x
	var d := r.size.y
	# ground floor: LUCKY'S laundromat in brick with the washer's porthole in its front
	var st := MeshLib.begin()
	MeshLib.prism(st, footprint(), 0.60)
	var ground := MeshInstance3D.new()
	ground.mesh = MeshLib.finish(st, _lib.wood())
	ground.name = "GroundFloor"
	add_child(ground)
	# the drum: a steel ring round a tilted porthole, the ball tumbles behind it
	_drum = Node3D.new()
	_drum.name = "Drum"
	_drum.position = drum_center()
	_drum.rotation.x = deg_to_rad(-55.0)
	add_child(_drum)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.16
	ring.outer_radius = 0.2
	ring.rings = 24
	ring.ring_segments = 8
	var rm := MeshInstance3D.new()
	rm.mesh = ring
	rm.material_override = _lib.steel()
	rm.rotation.x = PI * 0.5
	_drum.add_child(rm)
	_porthole = _lib.lamp(Color(0.18, 0.9, 0.84))
	_porthole.albedo_color = Color(0.1, 0.25, 0.28, 0.55)
	_porthole.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var disc := CylinderMesh.new()
	disc.top_radius = 0.165
	disc.bottom_radius = 0.165
	disc.height = 0.01
	var dm := MeshInstance3D.new()
	dm.mesh = disc
	dm.material_override = _porthole
	dm.rotation.x = PI * 0.5
	dm.position.z = 0.02
	_drum.add_child(dm)
	# the glass lift shaft and its car
	var lb := lift_bottom()
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.18, TOP_FLOOR_H + 0.25, 0.18)
	var sm := MeshInstance3D.new()
	sm.mesh = shaft
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.7, 0.9, 1.0, 0.18)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	sm.material_override = glass
	sm.position = Vector3(lb.x, (TOP_FLOOR_H + 0.25) * 0.5, lb.z)
	sm.name = "LiftShaft"
	add_child(sm)
	_lift_car = MeshInstance3D.new()
	var car := BoxMesh.new()
	car.size = Vector3(0.17, 0.03, 0.17)
	(_lift_car as MeshInstance3D).mesh = car
	(_lift_car as MeshInstance3D).material_override = _lib.brass()
	_lift_car.position = Vector3(lb.x, 0.06, lb.z)
	_lift_car.name = "LiftCar"
	add_child(_lift_car)
	# the neon sign and the brass floor dial
	_sign = _lib.lamp(Color(0.18, 0.9, 0.84))
	var sign := Label3D.new()
	sign.text = "LUCKY'S"
	sign.font_size = 72
	sign.pixel_size = 0.0022
	sign.outline_size = 0
	sign.modulate = Color(0.55, 1.0, 0.95)
	sign.position = Vector3(x0 + w * 0.5, 0.66, z0 + d + 0.01)
	sign.rotation.x = deg_to_rad(-60.0)
	sign.name = "Sign"
	add_child(sign)
	for i in range(3):
		var lamp := _lib.lamp(Color(1.0, 0.8, 0.45))
		lamp.emission_energy_multiplier = 0.1
		var dot := SphereMesh.new()
		dot.radius = 0.025
		dot.height = 0.05
		var mi := MeshInstance3D.new()
		mi.mesh = dot
		mi.material_override = lamp
		mi.position = Vector3(lb.x - 0.2 + 0.07 * float(i), 0.55, z0 + d + 0.02)
		mi.name = "FloorLamp%d" % i
		add_child(mi)
		_floor_lamps.append(lamp)


func set_open(on: bool) -> void:
	open = on


func is_busy() -> bool:
	return _phase != Phase.IDLE


func rider() -> Ball:
	return _ball if _phase != Phase.IDLE else null


func _on_scoop(body: Node3D) -> void:
	if not open or not (body is Ball) or _cool > 0.0 or not visible:
		return
	var b := body as Ball
	if BallHold.is_held(b):
		return
	if _phase != Phase.IDLE:
		# the lift is busy with another guy: this one comes straight back off the door
		b.set_velocity(Vector3(0.0, 0.0, REFUSE_SPEED))
		return
	_ball = b
	BallHold.take(b)
	_phase = Phase.DRUM
	_t = 0.0
	AudioDirector.play(&"safe_open")
	AudioDirector.play(&"laundromat_wash")
	TableScore.hit(&"laundromat_loop", b)
	entered.emit(b)


func _physics_process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if _phase == Phase.IDLE:
		return
	if _ball == null or not is_instance_valid(_ball):
		_phase = Phase.IDLE
		return
	_t += delta
	match _phase:
		Phase.DRUM:
			var c := drum_center()
			var a := _t * 11.0
			var tumble := Vector3(cos(a) * DRUM_R, sin(a) * DRUM_R * 0.8, 0.0).rotated(Vector3.RIGHT, deg_to_rad(-55.0))
			BallHold.steer(_ball, c + tumble, delta)
			if _t >= wash_seconds:
				_phase = Phase.TO_LIFT
				_t = 0.0
				AudioDirector.play(&"cash_tick")
				washed.emit(_ball)
		Phase.TO_LIFT:
			var lb := lift_bottom() + Vector3(0.0, 0.12, 0.0)
			BallHold.steer(_ball, lb, delta)
			if _ball.table_position().distance_to(lb) < 0.03 or _t > 0.6:
				_t = 0.0
				if penthouse_open and sitdown_lit:
					_phase = Phase.UP
					AudioDirector.play(&"chime_a")
				else:
					_phase = Phase.OUT
		Phase.UP:
			var p := _ball.table_position()
			var to := Vector3(lift_bottom().x, TOP_FLOOR_H, lift_bottom().z)
			var next := p.move_toward(to, LIFT_SPEED * delta)
			BallHold.steer(_ball, next, delta)
			_lift_car.position.y = next.y - Feel.BALL_RADIUS
			if next.distance_to(to) < 0.01:
				_t = 0.0
				_phase = Phase.SEATED
				sitdown_lit = false
				AudioDirector.play(&"sitdown")
				top_floor_reached.emit(_ball)
		Phase.SEATED:
			BallHold.steer(_ball, Vector3(lift_bottom().x, TOP_FLOOR_H, lift_bottom().z), delta)
			if _t >= SIT_SECONDS:
				_phase = Phase.DOWN
				_t = 0.0
				top_floor_left.emit(_ball)
		Phase.DOWN:
			var p2 := _ball.table_position()
			var to2 := lift_bottom() + Vector3(0.0, 0.12, 0.0)
			var next2 := p2.move_toward(to2, LIFT_SPEED * 1.4 * delta)
			BallHold.steer(_ball, next2, delta)
			_lift_car.position.y = next2.y - Feel.BALL_RADIUS
			if next2.distance_to(to2) < 0.01:
				_phase = Phase.OUT
				_t = 0.0
		Phase.OUT:
			# down the lift shaft into the basement, under the plaza, and up in the Alley
			if _t < SINK_SECONDS:
				var top := lift_bottom() + Vector3(0.0, 0.12, 0.0)
				var bottom := Vector3(top.x, -0.35, top.z)
				BallHold.steer(_ball, top.lerp(bottom, _t / SINK_SECONDS), delta)
				_ball.visible = _ball.table_position().y > 0.0
				return
			if _t < SINK_SECONDS + UNDER_SECONDS:
				return
			var b := _ball
			_phase = Phase.IDLE
			_ball = null
			_cool = 0.4
			b.visible = true
			var a := _rng.randf_range(0.0, TAU)
			BallHold.release(b, door_point(), Vector3(cos(a), 0.0, sin(a)) * POP_SPEED)
			AudioDirector.play(&"kickback")
			released.emit(b)


func _process(delta: float) -> void:
	if _porthole != null:
		var want := 2.4 if _phase == Phase.DRUM else (0.6 if open else 0.05)
		_porthole.emission_energy_multiplier = lerpf(_porthole.emission_energy_multiplier, want, 1.0 - exp(-6.0 * delta))
	if _drum != null and _phase == Phase.DRUM:
		_drum.rotate_object_local(Vector3.FORWARD, delta * 9.0)
	if _lift_car != null and _phase == Phase.IDLE:
		_lift_car.position.y = move_toward(_lift_car.position.y, 0.06, delta * 1.2)
	var level := 0
	if _phase == Phase.UP or _phase == Phase.SEATED or _phase == Phase.DOWN:
		level = 1 if _lift_car.position.y < 0.7 else 2
	for i in range(_floor_lamps.size()):
		_floor_lamps[i].emission_energy_multiplier = 2.0 if i == level else 0.12


func set_hardware_active(active: bool) -> void:
	visible = active
	if not active and _ball != null and is_instance_valid(_ball) and _phase != Phase.IDLE:
		_ball.visible = true
		BallHold.release(_ball, door_point(), Vector3(0.0, 0.0, POP_SPEED))
		_phase = Phase.IDLE
		_ball = null
	if _scoop != null:
		_scoop.collision_layer = Feel.LAYER_ZONES if active else 0
		_scoop.collision_mask = Feel.LAYER_BALL if active else 0


func is_hardware_active() -> bool:
	return visible


func search_exempt(b: Ball) -> bool:
	return b == _ball and _phase != Phase.IDLE
