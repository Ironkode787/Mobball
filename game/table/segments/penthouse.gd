class_name Penthouse
extends Node3D
## THE PENTHOUSE (R6, docs/19 §3.3): the glass room on the roof of Lucky's Tower. When the roof
## is lit, Lucky's lift keeps going past the Alley door and seats the ball at the Commission
## table (the Sit-Down). While the Commission is in session the Five Families wait at five shots
## round the board; take a family's shot and its chair falls (`chair_taken`), take all five in
## one session and the room is yours (`chairs_completed`).
##
## The room moves no ball itself: the tower's lift does, and the table forwards the ride here.

signal chair_taken(index: int)
signal chairs_completed()
signal sitdown_entered()
signal penthouse_entered(speed: float)
signal penthouse_returned()
signal session_changed(active: bool)

const ID_PENTHOUSE := &"penthouse"
const ID_CHAIRS := &"commission_chairs"
const ID_SITDOWN := &"sitdown_saucer"
const ID_STAIRS := &"penthouse_stairs"

const CHAIRS := 5
## The Five Families and the shot each one sits at (docs/19 §3.3).
const CHAIR_SHOTS: Array[StringName] = [&"getaway", &"staircase", &"nonnas", &"fat_tonys", &"truck_route"]
const FAMILY_NAMES: PackedStringArray = ["MORETTI", "VALLONE", "DeLUCA", "FERRANTE", "GALLO"]
const SESSION_SECONDS := 45.0
const ROOM_H := 0.60                      ## the roof slab, on top of the ground floor
const ROOM_TOP_H := 1.30
## Kept for the flow's sockets: the Commission table sits on the roof.
const TABLE_AT := Vector2(1.235, -3.45)

var session_left: float = 0.0
var roof_lit: bool = false

var _present: bool = false
var _taken: Array[bool] = [false, false, false, false, false]
var _ball: Ball = null
var _look: Node3D = null
var _chair_lamps: Array[StandardMaterial3D] = []
var _roof_lamp: StandardMaterial3D = null


func _ready() -> void:
	_build_look()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var r := Layout.TOWER_RECT
	var cx := r.position.x + r.size.x * 0.5
	var cz := r.position.y + r.size.y * 0.5
	# the glass box
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.55, 0.62, 0.9, 0.22)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic_specular = 0.9
	var box := BoxMesh.new()
	box.size = Vector3(r.size.x - 0.04, ROOM_TOP_H - ROOM_H, r.size.y - 0.04)
	var gm := MeshInstance3D.new()
	gm.mesh = box
	gm.material_override = glass
	gm.position = Vector3(cx, (ROOM_H + ROOM_TOP_H) * 0.5, cz)
	gm.name = "Glass"
	gm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_look.add_child(gm)
	# the roof slab and the brass frame
	var frame := MeshLib.begin()
	MeshLib.box(frame, Vector3(cx, ROOM_H + 0.015, cz), Vector3(r.size.x, 0.03, r.size.y))
	MeshLib.box(frame, Vector3(cx, ROOM_TOP_H, cz), Vector3(r.size.x - 0.02, 0.025, r.size.y - 0.02))
	var fm := MeshInstance3D.new()
	fm.mesh = MeshLib.finish(frame, lib.brass_dark())
	fm.name = "Frame"
	_look.add_child(fm)
	# the long table and the five chairs round it, each with its family's lamp
	var tbl := BoxMesh.new()
	tbl.size = Vector3(0.30, 0.03, 0.12)
	var tm := MeshInstance3D.new()
	tm.mesh = tbl
	tm.material_override = lib.wood()
	tm.position = Vector3(cx + 0.04, ROOM_H + 0.12, cz)
	tm.name = "Table"
	_look.add_child(tm)
	for i in range(CHAIRS):
		var lamp := lib.lamp(Color(0.72, 0.52, 1.0))
		var seat := BoxMesh.new()
		seat.size = Vector3(0.05, 0.08, 0.05)
		var sm := MeshInstance3D.new()
		sm.mesh = seat
		sm.material_override = lamp
		var along := (float(i) - 2.0) * 0.07
		var side := -1.0 if i % 2 == 0 else 1.0
		sm.position = Vector3(cx + 0.04 + along, ROOM_H + 0.07, cz + side * 0.10)
		sm.name = "Chair%d" % (i + 1)
		_look.add_child(sm)
		_chair_lamps.append(lamp)
	_roof_lamp = lib.lamp(Color(0.72, 0.52, 1.0))
	var sign := Label3D.new()
	sign.text = "PENTHOUSE"
	sign.font_size = 48
	sign.pixel_size = 0.0019
	sign.modulate = Color(0.8, 0.65, 1.0)
	sign.position = Vector3(cx, ROOM_TOP_H + 0.06, r.position.y + r.size.y)
	sign.rotation.x = deg_to_rad(-55.0)
	sign.name = "Sign"
	_look.add_child(sign)


## The lift delivered a ball to the roof.
func on_seated(b: Ball) -> void:
	if not _present:
		return
	_ball = b
	roof_lit = false
	TableScore.earn(TableScore.GROUP_PENTHOUSE, TableScore.PENTHOUSE_CHAIR * 0.5, &"sitdown_saucer", b)
	penthouse_entered.emit(0.0)
	sitdown_entered.emit()
	start_session()


func on_left(_b: Ball) -> void:
	_ball = null
	penthouse_returned.emit()


func start_session() -> void:
	session_left = SESSION_SECONDS
	for i in range(CHAIRS):
		_taken[i] = false
	session_changed.emit(true)


func session_active() -> bool:
	return session_left > 0.0


## The table reports every major shot; a family whose chair is up at that shot falls.
func on_shot(shot: StringName, b: Ball) -> void:
	if not _present or not session_active():
		return
	var i := CHAIR_SHOTS.find(shot)
	if i < 0 or _taken[i]:
		return
	_taken[i] = true
	AudioDirector.play(&"drop_clack")
	TableScore.earn(TableScore.GROUP_PENTHOUSE, TableScore.PENTHOUSE_CHAIR, StringName("commission_chair_%d" % (i + 1)), b)
	chair_taken.emit(i)
	if _taken.count(true) >= CHAIRS:
		session_left = 0.0
		chairs_completed.emit()
		session_changed.emit(false)


## Which shots still have a family waiting (for the arrows).
func waiting_shots() -> Array[StringName]:
	var out: Array[StringName] = []
	if not session_active():
		return out
	for i in range(CHAIRS):
		if not _taken[i]:
			out.append(CHAIR_SHOTS[i])
	return out


func chairs_standing() -> int:
	return _taken.count(false) if session_active() else CHAIRS


func set_ball(b: Ball) -> void:
	_ball = b


func pieces() -> Array[Dictionary]:
	return []


func bounds() -> AABB:
	var r := Layout.TOWER_RECT
	return AABB(Vector3(r.position.x, ROOM_H, r.position.y), Vector3(r.size.x, ROOM_TOP_H - ROOM_H, r.size.y))


func holds_ball() -> bool:
	return false


func search_exempt(_b: Ball) -> bool:
	return false


func _process(delta: float) -> void:
	if session_left > 0.0:
		session_left = maxf(session_left - delta, 0.0)
		if session_left <= 0.0:
			session_changed.emit(false)
	var t := Time.get_ticks_msec() * 0.001
	for i in range(_chair_lamps.size()):
		var e := 0.08
		if session_active():
			e = 0.4 if _taken[i] else (2.2 if fmod(t * 2.5 + float(i) * 0.2, 1.0) < 0.55 else 0.6)
		elif roof_lit:
			e = 1.2 if fmod(t * 1.2, 1.0) < 0.5 else 0.3
		_chair_lamps[i].emission_energy_multiplier = e


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if not active:
		session_left = 0.0
		roof_lit = false


func is_hardware_active() -> bool:
	return _present
