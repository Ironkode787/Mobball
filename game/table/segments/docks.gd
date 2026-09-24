class_name Docks
extends Node3D
## PIER 9 (R5, docs/19 §3.4): the container yard in the top-right corner, outside the arch.
## While the pier is lit, the crane's magnet takes a ball off the top of the Truck Route, swings
## it over the wall and loads its cargo into the next container, then drops it back onto the
## ring road to finish the lap. Three loaded containers are a shipment (SmugglingRun); the flow
## empties the yard when the run ships or lapses (`reset_pier`).

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

const STACKS := 3
const CATCH_DEG := 318.0
const DROP_DEG := 296.0
const CATCH_R := 0.20
const HOOK_H := 0.82
const LOAD_SECONDS := 0.55
const RIDE_SPEED := 3.4
const DROP_SPEED := 8.0
const COOLDOWN := 1.2
const LANE_EYE_Z := -1.30                   ## up the right lane, above its throat
const TRUCK_WINDOW := 3.0                   ## s from the lane to the crane for a Truck Route ball
const TOWER_AT := Vector2(2.45, -5.26)
const TOWER_H := 1.05
const CONTAINER_AT: Array = [Vector2(2.02, -5.19), Vector2(2.31, -5.19), Vector2(2.34, -4.92)]
const CONTAINER_SIZE := Vector3(0.25, 0.13, 0.13)
const CONTAINER_COLORS: Array[Color] = [Color("A9552E"), Color("2E6F74"), Color("8A7A2E")]
## The flow's socket for the cargo it releases (the Smuggling multiball): the drop point.
const CRATES_ORIGIN := Vector2(0.81, -4.85)

enum Phase { IDLE, LIFT, SWING, LOAD, BACK, LOWER }

var containers: Docks = null
var crane: Node3D = null
var lit: bool = true

var _present: bool = false
var _ball: Ball = null
var _loaded: Array[int] = []
var _phase: Phase = Phase.IDLE
var _ride: PathRide = null
var _t: float = 0.0
var _cool: float = 0.0
var _sensor: Area3D = null
var _lane_eye: Area3D = null
var _up_lane: Dictionary = {}               ## ball instance id -> when it was seen going up the lane
var _clock: float = 0.0
var _boom: Node3D = null
var _trolley: Node3D = null
var _magnet_lamp: StandardMaterial3D = null
var _container_lamps: Array[StandardMaterial3D] = []
var _arrow_lamp: StandardMaterial3D = null
var _look: Node3D = null
var _hook: Vector3 = Vector3.ZERO


func _ready() -> void:
	containers = self
	_build_sensor()
	_build_look()


static func catch_point() -> Vector2:
	return Layout.channel_mid(CATCH_DEG)


static func drop_point() -> Vector2:
	return Layout.channel_mid(DROP_DEG)


func _build_sensor() -> void:
	# the pier's own eye in the right lane: a ball seen going up it is a Truck Route ball, so
	# the crane knows one without the Truck Route's switches (a later buy) and never takes a
	# freshly plunged ball entering the ring through the launch flaps
	_lane_eye = Area3D.new()
	_lane_eye.name = "LaneEye"
	_lane_eye.collision_layer = Feel.LAYER_ZONES
	_lane_eye.collision_mask = Feel.LAYER_BALL
	_lane_eye.monitorable = false
	var eye := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(Layout.LANE_WIDTH_L, 0.4, 0.2)
	eye.shape = box
	eye.position = Layout.p3(Vector2(Layout.LANE_R_X, LANE_EYE_Z), 0.2)
	_lane_eye.add_child(eye)
	add_child(_lane_eye)
	_lane_eye.body_entered.connect(_on_lane_eye)
	_sensor = Area3D.new()
	_sensor.name = "CraneSensor"
	_sensor.collision_layer = Feel.LAYER_ZONES
	_sensor.collision_mask = Feel.LAYER_BALL
	_sensor.monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = CATCH_R
	cyl.height = 0.4
	cs.shape = cyl
	cs.position = Layout.p3(catch_point(), 0.2)
	_sensor.add_child(cs)
	add_child(_sensor)
	_sensor.body_entered.connect(_on_sensor)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	# the quay: a concrete slab in the corner behind the arch
	var quay := MeshLib.begin()
	var poly := PackedVector2Array([Vector2(1.78, -5.40), Vector2(2.60, -5.40), Vector2(2.60, -3.80)])
	for i in range(9):
		var x := lerpf(2.60, 1.78, float(i) / 8.0)
		poly.append(Vector2(x, Layout.ARCH_CENTER.y - sqrt(maxf(Layout.ARCH_RADIUS * Layout.ARCH_RADIUS - x * x, 0.0)) - 0.07))
	MeshLib.prism(quay, poly, 0.04, 0.0)
	var qm := MeshInstance3D.new()
	qm.mesh = MeshLib.finish(quay, lib.plastic(Color("3B3A36"), 0.9))
	qm.name = "Quay"
	_look.add_child(qm)
	for i in range(STACKS):
		var c: Vector2 = CONTAINER_AT[i]
		var box := BoxMesh.new()
		box.size = CONTAINER_SIZE
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = lib.plastic(CONTAINER_COLORS[i], 0.7)
		mi.position = Layout.p3(c, 0.04 + CONTAINER_SIZE.y * 0.5)
		mi.rotation.y = deg_to_rad(8.0 * float(i - 1))
		mi.name = "Container%d" % (i + 1)
		_look.add_child(mi)
		var lamp := lib.lamp(Feel.COL_DIRTY)
		var door := BoxMesh.new()
		door.size = Vector3(0.012, CONTAINER_SIZE.y * 0.8, CONTAINER_SIZE.z * 0.8)
		var dm := MeshInstance3D.new()
		dm.mesh = door
		dm.material_override = lamp
		dm.position = Vector3(-CONTAINER_SIZE.x * 0.5 - 0.004, 0.0, 0.0)
		mi.add_child(dm)
		_container_lamps.append(lamp)
	# the crane: a lattice tower with a boom that swings and a trolley that runs out along it
	# the lattice mast and jib (tools/meshgen: pier_crane, pier_boom); a post and a bar are the
	# fallback
	var mast := ToyLib.instance(&"pier_crane")
	if mast != null:
		mast.position = Layout.p3(TOWER_AT, 0.0)
		_look.add_child(mast)
	else:
		var tower := MeshLib.begin()
		MeshLib.post(tower, TOWER_AT, 0.05, TOWER_H, 0.0, 8)
		var tm := MeshInstance3D.new()
		tm.mesh = MeshLib.finish(tower, lib.plastic(Color("C9A227"), 0.5))
		tm.name = "Tower"
		_look.add_child(tm)
	crane = Node3D.new()
	crane.name = "Crane"
	crane.position = Layout.p3(TOWER_AT, TOWER_H)
	_look.add_child(crane)
	_boom = Node3D.new()
	_boom.name = "Boom"
	crane.add_child(_boom)
	var jib := ToyLib.instance(&"pier_boom")
	if jib != null:
		_boom.add_child(jib)
	else:
		var boom_mesh := BoxMesh.new()
		boom_mesh.size = Vector3(0.05, 0.05, 1.55)
		var bm := MeshInstance3D.new()
		bm.mesh = boom_mesh
		bm.material_override = lib.plastic(Color("C9A227"), 0.5)
		bm.position = Vector3(0.0, 0.0, 0.62)
		_boom.add_child(bm)
	_trolley = Node3D.new()
	_trolley.name = "Trolley"
	_boom.add_child(_trolley)
	var cable := CylinderMesh.new()
	cable.top_radius = 0.006
	cable.bottom_radius = 0.006
	cable.height = 0.2
	var cm := MeshInstance3D.new()
	cm.mesh = cable
	cm.material_override = lib.steel()
	cm.position.y = -0.1
	cm.name = "Cable"
	_trolley.add_child(cm)
	_magnet_lamp = lib.lamp(Feel.COL_DIRTY)
	var mag := CylinderMesh.new()
	mag.top_radius = 0.09
	mag.bottom_radius = 0.09
	mag.height = 0.04
	var mm := MeshInstance3D.new()
	mm.mesh = mag
	mm.material_override = _magnet_lamp
	mm.position.y = -0.2
	mm.name = "Magnet"
	_trolley.add_child(mm)
	_hook = Layout.p3(catch_point(), HOOK_H)
	_aim_crane(_hook, 0.0)
	# the arrow on the ring road that says the pier is taking loads
	_arrow_lamp = lib.lamp(Color(1.0, 0.45, 0.2))
	var st := MeshLib.begin()
	var p := catch_point()
	var dir := (Layout.channel_mid(CATCH_DEG - 6.0) - p).normalized()
	var side := Vector2(-dir.y, dir.x)
	var tip := p + dir * 0.12
	var a := p - dir * 0.06 + side * 0.07
	var b := p - dir * 0.06 - side * 0.07
	st.set_normal(Vector3.UP)
	st.add_vertex(Vector3(tip.x, 0.004, tip.y))
	st.add_vertex(Vector3(b.x, 0.004, b.y))
	st.add_vertex(Vector3(a.x, 0.004, a.y))
	var am := MeshInstance3D.new()
	am.mesh = MeshLib.finish(st, _arrow_lamp)
	am.name = "PierArrow"
	am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_look.add_child(am)
	var sign := Label3D.new()
	sign.text = "PIER 9"
	sign.font_size = 56
	sign.pixel_size = 0.0022
	sign.modulate = Color(0.45, 0.95, 0.9)
	sign.position = Vector3(2.16, 0.36, -4.72)
	sign.rotation.x = deg_to_rad(-60.0)
	sign.rotation.y = deg_to_rad(28.0)
	sign.name = "Sign"
	_look.add_child(sign)


## Point the boom at a table-space hook position (the magnet hangs `drop` below the boom).
func _aim_crane(hook: Vector3, drop: float) -> void:
	if crane == null:
		return
	var local := hook - crane.position
	var flat := Vector2(local.x, local.z)
	_boom.rotation.y = atan2(flat.x, flat.y)
	_trolley.position = Vector3(0.0, 0.0, flat.length())
	var cable := _trolley.get_node_or_null("Cable") as MeshInstance3D
	var magnet := _trolley.get_node_or_null("Magnet") as MeshInstance3D
	var hang := maxf(-local.y + drop, 0.08)
	if cable != null:
		(cable.mesh as CylinderMesh).height = hang
		cable.position.y = -hang * 0.5
	if magnet != null:
		magnet.position.y = -hang


func set_ball(b: Ball) -> void:
	_ball = b


func pieces() -> Array[Dictionary]:
	return []


func bounds() -> AABB:
	return AABB(Vector3(1.7, 0.0, -5.4), Vector3(0.9, TOWER_H, 1.6))


func yard_rect() -> Rect2:
	return Rect2(Vector2(1.78, -5.4), Vector2(0.82, 1.6))


func holds_ball() -> bool:
	return _phase != Phase.IDLE


func search_exempt(b: Ball) -> bool:
	return _phase != Phase.IDLE and _ride != null and b == _ride.ball


func cleared_stacks() -> Array:
	return _loaded.duplicate()


func loaded_count() -> int:
	return _loaded.size()


func set_lit(on: bool) -> void:
	lit = on


## The run shipped or lapsed: the crane empties the yard.
func reset_pier() -> void:
	_loaded.clear()
	containers_state.emit(cleared_stacks())


## Getting the load to the truck: the flow reports a Getaway during a live run through here so
## the yard owns every one of its own signals.
func ship_to_truck(speed: float) -> void:
	cargo_shipped.emit(speed)


func _on_sensor(body: Node3D) -> void:
	if not _present or not lit or _phase != Phase.IDLE or _cool > 0.0 or not (body is Ball):
		return
	var b := body as Ball
	if BallHold.is_held(b) or _loaded.size() >= STACKS:
		return
	var seen: float = _up_lane.get(b.get_instance_id(), -1000.0)
	if _clock - seen > TRUCK_WINDOW:
		return
	crane_telegraph.emit()
	AudioDirector.play(&"crane_telegraph")
	var catch3 := Layout.p3(catch_point(), Feel.BALL_RADIUS)
	_ride = PathRide.start(b, PackedVector3Array([b.table_position(), catch3 + Vector3(0.0, HOOK_H - 0.2, 0.0)]), RIDE_SPEED)
	_phase = Phase.LIFT
	_t = 0.0
	docks_entered.emit()


func _on_lane_eye(body: Node3D) -> void:
	if not (body is Ball) or (body as Ball).local_velocity().z >= 0.0:
		return
	for id: int in _up_lane.keys():
		if _clock - float(_up_lane[id]) > TRUCK_WINDOW:
			_up_lane.erase(id)
	_up_lane[body.get_instance_id()] = _clock


func _physics_process(delta: float) -> void:
	_clock += delta
	_cool = maxf(_cool - delta, 0.0)
	if _phase == Phase.IDLE or _ride == null:
		return
	if _ride.ball == null or not is_instance_valid(_ride.ball):
		_phase = Phase.IDLE
		_ride = null
		return
	_t += delta
	_ride.step(delta)
	_hook = _ride.ball.table_position() + Vector3(0.0, Feel.BALL_RADIUS + 0.02, 0.0)
	if not _ride.done():
		return
	var b := _ride.ball
	match _phase:
		Phase.LIFT:
			crane_pulled.emit()
			var slot: Vector2 = CONTAINER_AT[_loaded.size()]
			var over := Layout.p3(slot, HOOK_H - 0.2)
			_ride = PathRide.start(b, PackedVector3Array([b.table_position(), over,
					Layout.p3(slot, 0.04 + CONTAINER_SIZE.y + Feel.BALL_RADIUS)]), RIDE_SPEED)
			_phase = Phase.SWING
		Phase.SWING:
			_phase = Phase.LOAD
			_t = 0.0
			var stack := _loaded.size()
			_loaded.append(stack)
			AudioDirector.play(&"container_break")
			TableScore.earn(TableScore.GROUP_SMUGGLING, TableScore.SMUGGLING_CONTAINER, StringName("containers_%d" % (stack + 1)), b)
			stack_cleared.emit(stack)
			containers_state.emit(cleared_stacks())
			_ride = PathRide.start(b, PackedVector3Array([b.table_position(), b.table_position()]), 1.0)
		Phase.LOAD:
			if _t < LOAD_SECONDS:
				return
			var drop := Layout.p3(drop_point(), 0.0)
			_ride = PathRide.start(b, PackedVector3Array([b.table_position(),
					b.table_position() + Vector3(0.0, 0.18, 0.0), Vector3(drop.x, HOOK_H - 0.2, drop.z),
					Vector3(drop.x, Feel.BALL_RADIUS + 0.03, drop.z)]), RIDE_SPEED * 1.2)
			_phase = Phase.BACK
		Phase.BACK:
			var a := deg_to_rad(DROP_DEG)
			var tangent := Vector3(sin(a), 0.0, -cos(a))
			_ride.release(tangent * DROP_SPEED)
			_ride = null
			_phase = Phase.IDLE
			_cool = COOLDOWN
			AudioDirector.play(&"kickback")


func _process(delta: float) -> void:
	if not _present:
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in range(_container_lamps.size()):
		var on := _loaded.has(i)
		_container_lamps[i].emission_energy_multiplier = 2.2 if on else 0.08
	if _arrow_lamp != null:
		var avail := lit and _loaded.size() < STACKS and _cool <= 0.0
		_arrow_lamp.emission_energy_multiplier = (1.8 if fmod(t * 2.0, 1.0) < 0.5 else 0.3) if avail else 0.0
	if _magnet_lamp != null:
		_magnet_lamp.emission_energy_multiplier = lerpf(_magnet_lamp.emission_energy_multiplier,
				2.5 if _phase != Phase.IDLE else 0.1, 1.0 - exp(-10.0 * delta))
	if _phase == Phase.IDLE:
		_hook = _hook.lerp(Layout.p3(catch_point(), HOOK_H), 1.0 - exp(-3.0 * delta))
	_aim_crane(_hook, 0.0)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for area: Area3D in [_sensor, _lane_eye]:
		if area != null:
			area.collision_layer = Feel.LAYER_ZONES if active else 0
			area.collision_mask = Feel.LAYER_BALL if active else 0
	if not active:
		_up_lane.clear()
		_release_everything()


func is_hardware_active() -> bool:
	return _present


func _release_everything() -> void:
	if _ride != null and _ride.ball != null and is_instance_valid(_ride.ball):
		var drop := Layout.p3(drop_point(), Feel.BALL_RADIUS + 0.03)
		BallHold.release(_ride.ball, drop, Vector3.ZERO)
	_ride = null
	_phase = Phase.IDLE
