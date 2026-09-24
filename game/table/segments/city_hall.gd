class_name CityHall
extends Node3D
## CITY HALL (R7, docs/19 §3.4): the crown in the top-left corner, outside the arch, mirroring
## Pier 9. The dome gate sits on the ring road where the Getaway leaves its lane: a ball that
## arrives at full speed is diverted up over the wall, round the golden dome on its wireform and
## back onto the ring road going the way it was going. It is the hardest shot on the machine.

signal dome_loop_completed(speed: float)

const ID_CITY_HALL := &"city_hall"
const ID_LOOP := &"dome_loop"

const GATE_DEG := 214.0
const GATE_R := 0.20
const DOME_SPEED := 21.0                  ## u/s at the gate: only a full-power Getaway makes it
const DOME_AT := Vector2(-2.20, -4.98)
const DOME_R := 0.26
const LOOP_R := 0.40
const LOOP_H := 0.78
const RIDE_SPEED := 7.0
const EXIT_KEEP := 0.85
const COL_LEAF := Color("E8C64A")

var loop: Node3D = null

var _present: bool = false
var _ride: PathRide = null
var _entry_speed: float = 0.0
var _exit_dir: Vector3 = Vector3.ZERO
var _sensor: Area3D = null
var _gate_lamp: StandardMaterial3D = null
var _dome_lamp: StandardMaterial3D = null
var _cool: float = 0.0
var _flash: float = 0.0


func _ready() -> void:
	_build_look()
	loop = Node3D.new()
	loop.name = "DomeGate"
	add_child(loop)
	_sensor = Area3D.new()
	_sensor.name = "GateSensor"
	_sensor.collision_layer = Feel.LAYER_ZONES
	_sensor.collision_mask = Feel.LAYER_BALL
	_sensor.monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = GATE_R
	cyl.height = 0.4
	cs.shape = cyl
	cs.position = Layout.p3(gate_point(), 0.2)
	_sensor.add_child(cs)
	loop.add_child(_sensor)
	_sensor.body_entered.connect(_on_gate)
	_build_gate_look()


static func gate_point() -> Vector2:
	return Layout.channel_mid(GATE_DEG)


## The wireform: up over the arch, a full lap of the dome, and back down onto the gate.
static func loop_path(from: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array([from])
	var g := gate_point()
	var d := DOME_AT
	var start_a := atan2(g.y - d.y, g.x - d.x)
	pts.append(Vector3(lerpf(g.x, d.x, 0.35), LOOP_H * 0.6, lerpf(g.y, d.y, 0.35)))
	for i in range(1, 25):
		var a := start_a - TAU * float(i) / 24.0
		var h := LOOP_H + 0.08 * sin(PI * float(i) / 24.0)
		pts.append(Vector3(d.x + cos(a) * LOOP_R, h, d.y + sin(a) * LOOP_R))
	pts.append(Vector3(lerpf(g.x, d.x, 0.35), LOOP_H * 0.6, lerpf(g.y, d.y, 0.35)))
	pts.append(Vector3(g.x, Feel.BALL_RADIUS + 0.02, g.y))
	return pts


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var gold := lib.plastic(COL_LEAF, 0.3)
	gold.metallic = 0.9
	# the plaza slab in the corner and the drum the dome sits on
	var st := MeshLib.begin()
	var poly := PackedVector2Array([Vector2(-2.60, -3.80), Vector2(-2.60, -5.40), Vector2(-1.78, -5.40)])
	for i in range(9):
		var x := lerpf(-1.78, -2.60, float(i) / 8.0)
		poly.append(Vector2(x, Layout.ARCH_CENTER.y - sqrt(maxf(Layout.ARCH_RADIUS * Layout.ARCH_RADIUS - x * x, 0.0)) - 0.07))
	MeshLib.prism(st, poly, 0.04, 0.0)
	var sm := MeshInstance3D.new()
	sm.mesh = MeshLib.finish(st, lib.plastic(Color("D8D0BC"), 0.8))
	sm.name = "Plaza"
	add_child(sm)
	_dome_lamp = lib.lamp(COL_LEAF)
	_dome_lamp.albedo_color = COL_LEAF.darkened(0.2)
	_dome_lamp.metallic = 0.85
	_dome_lamp.roughness = 0.3
	# the rotunda (tools/meshgen: city_hall_dome) sits inside the dome loop's clearance; the
	# drum and hemisphere below are its fallback
	var hall := ToyLib.instance(&"city_hall_dome")
	if hall != null:
		hall.position = Layout.p3(DOME_AT, 0.04)
		ToyLib.bind(hall, "Lamp", _dome_lamp)
		add_child(hall)
	else:
		var drum := MeshLib.begin()
		MeshLib.post(drum, DOME_AT, DOME_R, 0.34, 0.04, 20)
		var dm := MeshInstance3D.new()
		dm.mesh = MeshLib.finish(drum, lib.plastic(Color("E9E2CF"), 0.7))
		dm.name = "Drum"
		add_child(dm)
		var dome := SphereMesh.new()
		dome.radius = DOME_R
		dome.height = DOME_R * 2.0
		dome.is_hemisphere = true
		dome.radial_segments = 24
		dome.rings = 8
		var dom := MeshInstance3D.new()
		dom.mesh = dome
		dom.material_override = _dome_lamp
		dom.position = Layout.p3(DOME_AT, 0.38)
		dom.name = "Dome"
		add_child(dom)
	var sign := Label3D.new()
	sign.text = "CITY HALL"
	sign.font_size = 52
	sign.pixel_size = 0.0021
	sign.modulate = Color(1.0, 0.9, 0.55)
	# on the back wall over the rotunda, clear of the Club's sign and the arch rail
	sign.position = Vector3(DOME_AT.x + 0.14, 0.86, DOME_AT.y - 0.33)
	sign.rotation.x = deg_to_rad(-30.0)
	sign.name = "Sign"
	add_child(sign)


func _build_gate_look() -> void:
	var lib := MaterialLib.shared()
	var gold := lib.plastic(COL_LEAF, 0.3)
	gold.metallic = 0.9
	var path := loop_path(Layout.p3(gate_point(), Feel.BALL_RADIUS + 0.02))
	var st := MeshLib.begin()
	for side: float in [-1.0, 1.0]:
		var rail := PackedVector3Array()
		for i in range(path.size()):
			var p := path[i]
			var c := Vector3(DOME_AT.x, p.y, DOME_AT.y)
			var out := (p - c)
			out.y = 0.0
			out = out.normalized() if out.length() > 0.001 else Vector3.RIGHT
			rail.append(p + out * side * (Feel.BALL_RADIUS * 0.8) + Vector3(0.0, -Feel.BALL_RADIUS * 0.7, 0.0))
		MeshLib.tube(st, rail, 0.012, 6)
	var rm := MeshInstance3D.new()
	rm.mesh = MeshLib.finish(st, gold)
	rm.name = "Wireform"
	loop.add_child(rm)
	_gate_lamp = lib.lamp(COL_LEAF)
	var arrow := MeshLib.begin()
	var p0 := gate_point()
	var dir := (Layout.channel_mid(GATE_DEG + 8.0) - p0).normalized()
	var side2 := Vector2(-dir.y, dir.x)
	var tip := p0 - dir * 0.14
	var a := p0 + dir * 0.04 + side2 * 0.07
	var b := p0 + dir * 0.04 - side2 * 0.07
	arrow.set_normal(Vector3.UP)
	arrow.add_vertex(Vector3(tip.x, 0.004, tip.y))
	arrow.add_vertex(Vector3(a.x, 0.004, a.y))
	arrow.add_vertex(Vector3(b.x, 0.004, b.y))
	var am := MeshInstance3D.new()
	am.mesh = MeshLib.finish(arrow, _gate_lamp)
	am.name = "GateArrow"
	am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	loop.add_child(am)


func gate_live() -> bool:
	return _present and loop != null and loop.visible


func _on_gate(body: Node3D) -> void:
	if not gate_live() or _ride != null or _cool > 0.0 or not (body is Ball):
		return
	var b := body as Ball
	if BallHold.is_held(b):
		return
	var v := b.approach_velocity()
	v.y = 0.0
	if v.length() < DOME_SPEED:
		return
	# only a ball running round the ring road the Getaway's way (clockwise, out of the left
	# lane), not one crossing it or coming home the other way
	var g := gate_point()
	var radial := Vector3(g.x - Layout.RING_CENTER.x, 0.0, g.y - Layout.RING_CENTER.y).normalized()
	if absf(v.normalized().dot(radial)) > 0.6:
		return
	var a := deg_to_rad(GATE_DEG)
	var clockwise := Vector3(-sin(a), 0.0, cos(a))
	if v.dot(clockwise) <= 0.0:
		return
	_entry_speed = v.length()
	_exit_dir = v.normalized()
	_ride = PathRide.start(b, loop_path(b.table_position()), RIDE_SPEED)
	AudioDirector.play(&"dome_loop")


func _physics_process(delta: float) -> void:
	_cool = maxf(_cool - delta, 0.0)
	if _ride == null:
		return
	if _ride.ball == null or not is_instance_valid(_ride.ball):
		_ride = null
		return
	_ride.step(delta)
	if not _ride.done():
		return
	var b := _ride.ball
	_ride.release(_exit_dir * _entry_speed * EXIT_KEEP)
	_ride = null
	_cool = 0.8
	_flash = 1.0
	TableScore.earn(TableScore.GROUP_PENTHOUSE, TableScore.DOME_LOOP, &"dome_loop", b, _entry_speed)
	AudioDirector.play(&"knocker")
	dome_loop_completed.emit(_entry_speed)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 0.8, 0.0)
	var t := Time.get_ticks_msec() * 0.001
	if _gate_lamp != null:
		_gate_lamp.emission_energy_multiplier = (1.8 if fmod(t * 1.6, 1.0) < 0.5 else 0.4) if gate_live() else 0.0
	if _dome_lamp != null:
		_dome_lamp.emission_energy_multiplier = 0.25 + _flash * 3.0 + (0.4 if gate_live() else 0.0)


func set_ball(_b: Ball) -> void:
	pass


func holds_ball() -> bool:
	return _ride != null


func search_exempt(b: Ball) -> bool:
	return _ride != null and b == _ride.ball


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if not active and _ride != null:
		_ride.release(Vector3.ZERO)
		_ride = null


func is_hardware_active() -> bool:
	return _present
