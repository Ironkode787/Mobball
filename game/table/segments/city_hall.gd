class_name CityHall
extends Node3D
## CITY HALL (R7): the crown. A golden wireform loop that leaves the Penthouse stairs' landing,
## climbs over the back of the machine in a full ring above the Penthouse and comes down
## beside the Sit-Down. The stairs' exit feeds it: only a ball that arrives with pace makes
## the climb — the dome is a speed gate first and a shot second.

signal dome_loop_completed(speed: float)

const ID_CITY_HALL := &"city_hall"
const ID_LOOP := &"dome_loop"

const MOUTH_AT := Vector2(-1.75, -4.90)
const MOUTH_SIZE := Vector2(0.36, 0.3)
const ENTRY_SPEED := 7.5
## A wireform ring round the Penthouse: the mouth faces the stairs' exit at the back, the
## rail climbs out over the left wall, sweeps round the outside of the room, comes back in
## over the front wall and lands on the floor at the right, short of the stairs' landing.
const LOOP_PATH: PackedVector3Array = [
	Vector3(-1.75, 0.90, -4.90), Vector3(-2.00, 0.98, -4.86), Vector3(-2.22, 1.12, -4.78),
	Vector3(-2.42, 1.22, -4.62), Vector3(-2.56, 1.28, -4.38), Vector3(-2.60, 1.31, -4.06),
	Vector3(-2.48, 1.30, -3.78), Vector3(-2.20, 1.28, -3.66), Vector3(-1.80, 1.25, -3.68),
	Vector3(-1.40, 1.21, -3.86), Vector3(-1.04, 1.12, -3.90), Vector3(-0.84, 1.00, -3.98),
	Vector3(-0.75, 0.92, -4.06),
]
const DOME_AT := Vector2(-1.5, -5.62)
const DOME_R := 0.45
const COL_LEAF := Color("E8C64A")

var loop: RampLane = null

var _present: bool = false
var _ball: Ball = null
var _lapped: bool = false
var _look: Node3D = null


func _ready() -> void:
	loop = RampLane.new()
	loop.name = "DomeLoop"
	loop.entry_speed = ENTRY_SPEED
	loop.entry_size = MOUTH_SIZE
	loop.flare_width = 0.56
	loop.color = COL_LEAF
	loop.configure(ID_LOOP, LOOP_PATH)
	add_child(loop)
	loop.crested.connect(_on_crested)
	_build_look()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var c := Layout.p3(DOME_AT, Penthouse.ROOM_H)
	var st := MeshLib.begin()
	MeshLib.post(st, DOME_AT, DOME_R * 1.3, 0.08, c.y, 36)
	var steps := MeshInstance3D.new()
	steps.mesh = MeshLib.finish(st, lib.paper())
	_look.add_child(steps)
	var drum := CylinderMesh.new()
	drum.top_radius = DOME_R
	drum.bottom_radius = DOME_R
	drum.height = 0.9
	drum.radial_segments = 36
	var dm := MeshInstance3D.new()
	dm.mesh = drum
	dm.material_override = lib.paper()
	dm.position = c + Vector3(0.0, 0.08 + 0.45, 0.0)
	_look.add_child(dm)
	var cols := MeshLib.begin()
	for i in range(10):
		var a := TAU * float(i) / 10.0
		MeshLib.post(cols, DOME_AT + Vector2(cos(a), sin(a)) * DOME_R * 1.1, 0.04, 0.85, c.y + 0.08, 8)
	var cm := MeshInstance3D.new()
	cm.mesh = MeshLib.finish(cols, lib.paper())
	_look.add_child(cm)
	var dome := SphereMesh.new()
	dome.radius = DOME_R * 0.96
	dome.height = DOME_R * 0.96
	dome.is_hemisphere = true
	dome.radial_segments = 36
	dome.rings = 14
	var dome_mi := MeshInstance3D.new()
	dome_mi.mesh = dome
	dome_mi.material_override = lib.brass()
	dome_mi.position = c + Vector3(0.0, 0.98, 0.0)
	_look.add_child(dome_mi)
	var finial := CylinderMesh.new()
	finial.top_radius = 0.0
	finial.bottom_radius = 0.06
	finial.height = 0.4
	var fm := MeshInstance3D.new()
	fm.mesh = finial
	fm.material_override = lib.brass()
	fm.position = c + Vector3(0.0, 0.98 + DOME_R * 0.96 + 0.18, 0.0)
	_look.add_child(fm)
	var sign := TextMesh.new()
	sign.text = "CITY HALL"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 60
	sign.pixel_size = 0.0055
	sign.depth = 0.03
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = lib.neon(COL_LEAF, 2.2)
	sm.position = c + Vector3(0.0, 0.55, DOME_R + 0.04)
	_look.add_child(sm)


func set_ball(b: Ball) -> void:
	_ball = b
	if loop != null:
		loop.set_ball(b)


func bounds() -> AABB:
	return AABB(Vector3(-2.6, 0.8, -5.75), Vector3(2.1, 1.4, 2.1))


func build_box() -> AABB:
	return bounds()


func holds_ball() -> bool:
	return loop != null and loop.riding()


func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	return BallHold.is_held(ball) and holds_ball()


func _on_crested(speed: float) -> void:
	_lapped = true
	AudioDirector.play(&"orbit_whoosh")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.DOME_LOOP, ID_LOOP, _ball, speed)
	dome_loop_completed.emit(speed)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if loop != null:
		loop.set_hardware_active(active)


func is_hardware_active() -> bool:
	return _present
