class_name Storefront
extends Node3D
## A protection racket as pinball hardware (docs/19 §3.1): a shop on its own island with a
## three-bank of drops across its doorway. Knock the bank down and the doorway is open: roll
## through the shop and out of the back door into the plaza behind (and on up into the Alley),
## collecting minutes of that racket's idle income on the way through.
##
## Before the racket is bought the shop is boarded up: a shutter across the doorway, a dark
## sign, and the island still stands as part of the board's shape.
##
## Built in table space from the island's outline: front-left, front-right, back-right,
## back-left.

signal collected(id: StringName, amount: BigMoney)
signal washed(id: StringName)
signal door_opened(id: StringName)
signal door_closed(id: StringName)

enum State { ARMED, OPEN, COOLDOWN }

const TARGETS := 3
const JAMB_THICK := 0.06
const JAMB_HEIGHT := 0.34
const LINTEL_Y := 0.42
const WASH_COOLDOWN := 1.6
const NEON := {
	&"storefront_laundromat": Color("2EE6D6"),
	&"storefront_pizzeria": Color("FF2E63"),
	&"storefront_pawn": Color("FFC341"),
}

@export var id: StringName = &"storefront"

var open_seconds: float = 8.0
var rearm_seconds: float = 12.0
var sign_text: StringName = &"SHOP"
var bank_enabled: bool = true
var wash_enabled: bool = false
var outline: PackedVector2Array = PackedVector2Array()

var _targets: Array[DropTarget] = []
var _door: Area3D = null
var _shutter: StaticBody3D = null
var _jambs: WallPiece = null
var _state: State = State.ARMED
var _timer: float = 0.0
var _wash_cool: float = 0.0
var _present: bool = true
var _glow: float = 0.0
var _door_lamp: StandardMaterial3D = null
var _neon: StandardMaterial3D = null
var _shutter_mesh: MeshInstance3D = null
var _inside: Area3D = null
var _still: float = 0.0
var _back_gate: OneWayGate = null


func configure(p_id: StringName, p_outline: PackedVector2Array, p_sign: StringName) -> void:
	id = p_id
	outline = p_outline
	sign_text = p_sign


func front_from() -> Vector2:
	return outline[0]


func front_to() -> Vector2:
	return outline[1]


## Unit vector out of the doorway toward the player.
func facing() -> Vector2:
	var along := (outline[1] - outline[0]).normalized()
	var n := Vector2(-along.y, along.x)
	var inward := ((outline[2] + outline[3]) * 0.5 - (outline[0] + outline[1]) * 0.5)
	return -n if n.dot(inward) > 0.0 else n


func centre() -> Vector2:
	return (outline[0] + outline[1] + outline[2] + outline[3]) * 0.25


## Unit vector along the back door, back-left to back-right.
func back_direction() -> Vector2:
	return (outline[2] - outline[3]).normalized()


## Unit normal of the back door pointing into the shop.
func back_inward() -> Vector2:
	var along := back_direction()
	var n := Vector2(-along.y, along.x)
	return n if n.dot(facing()) > 0.0 else -n


func _ready() -> void:
	var lib := MaterialLib.shared()
	var a := outline[0]
	var b := outline[1]
	var along := (b - a).normalized()
	var span := a.distance_to(b)
	var face := facing()
	# the jambs: the island's side walls, from the doorway to the back door
	_jambs = WallPiece.new(JAMB_HEIGHT, 0.0, lib.brass_dark(), lib.brass())
	_jambs.name = "Jambs"
	add_child(_jambs)
	_jambs.bar(outline[0], outline[3], JAMB_THICK)
	_jambs.bar(outline[1], outline[2], JAMB_THICK)
	# the bank across the doorway
	var inner := span - JAMB_THICK * 2.0
	var pitch := inner / float(TARGETS)
	for i in range(TARGETS):
		var t := DropTarget.new()
		t.name = "Target%d" % (i + 1)
		var c := a + along * (JAMB_THICK + pitch * (float(i) + 0.5))
		t.configure(StringName("%s_t%d" % [id, i + 1]), c, face, pitch - 0.012)
		t.thickness = 0.05
		add_child(t)
		t.dropped.connect(_on_target_dropped)
		_targets.append(t)
	# the shutter while the racket is not ours
	_shutter = WallBuilder.make_body("Shutter", Feel.LAYER_WALLS)
	add_child(_shutter)
	var sw := WallBuilder.new(_shutter, JAMB_HEIGHT)
	sw.bar(a + along * JAMB_THICK, b - along * JAMB_THICK, 0.05)
	var mid := (a + b) * 0.5 - face * 0.03
	_shutter_mesh = MeshInstance3D.new()
	_shutter_mesh.material_override = lib.chrome_dark()
	_shutter_mesh.name = "ShutterLook"
	_shutter.add_child(_shutter_mesh)
	_orient_box(_shutter_mesh, mid, along, inner, JAMB_HEIGHT, 0.04, JAMB_HEIGHT * 0.5)
	# the back door: the collection happens on the way out. The back need not run parallel to
	# the front, so everything on it is laid along its own edge.
	var back_along := back_direction()
	var back_in := back_inward()
	_door = Area3D.new()
	_door.name = "Door"
	_door.collision_layer = Feel.LAYER_ZONES
	_door.collision_mask = Feel.LAYER_BALL
	_door.monitorable = false
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var back_mid := (outline[2] + outline[3]) * 0.5
	var back_span := outline[2].distance_to(outline[3])
	box.size = Vector3(back_span - JAMB_THICK * 2.0, 0.5, 0.10)
	cs.shape = box
	cs.position = Vector3(back_mid.x, 0.25, back_mid.y) + Vector3(back_in.x, 0.0, back_in.y) * 0.08
	cs.rotation.y = Layout.yaw_facing(back_in)
	_door.add_child(cs)
	add_child(_door)
	_door.body_entered.connect(_on_door_entered)
	# the back door swings one way: out into the plaza
	_back_gate = OneWayGate.new()
	_back_gate.name = "BackDoor"
	_back_gate.configure(StringName(String(id) + "_back_door"), outline[3] + back_along * JAMB_THICK + back_in * 0.02,
			outline[2] - back_along * JAMB_THICK + back_in * 0.02, 0.03, back_in)
	# the shop is shallower than a ball is wide: a ball on its floor is always within a ball of
	# the door, so the door has to open on a hair
	_back_gate.hold_band = 0.02
	_back_gate.clear_band = Feel.BALL_RADIUS
	add_child(_back_gate)
	# the shop floor: a ball that stops in here is walked out of the back door
	_inside = Area3D.new()
	_inside.name = "Inside"
	_inside.collision_layer = Feel.LAYER_ZONES
	_inside.collision_mask = Feel.LAYER_BALL
	_inside.monitorable = false
	var ics := CollisionShape3D.new()
	var prism := ConvexPolygonShape3D.new()
	var corners := PackedVector3Array()
	for q in outline:
		corners.append(Vector3(q.x, 0.0, q.y))
		corners.append(Vector3(q.x, 0.5, q.y))
	prism.points = corners
	ics.shape = prism
	_inside.add_child(ics)
	add_child(_inside)
	_build_look(a, b, along, face, span)
	apply_build()


## Lay a unit box mesh along `along` centred on `mid`.
static func _orient_box(mi: MeshInstance3D, mid: Vector2, along: Vector2, length: float, height: float,
		depth: float, y: float) -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(length, height, depth)
	mi.mesh = bm
	mi.position = Vector3(mid.x, y, mid.y)
	mi.rotation.y = -atan2(along.y, along.x)


func _build_look(a: Vector2, b: Vector2, along: Vector2, face: Vector2, span: float) -> void:
	var lib := MaterialLib.shared()
	var neon_col: Color = NEON.get(id, Color("FF2E63"))
	# the floor of the shop: a lit threshold that says the door is open
	_door_lamp = lib.lamp(neon_col.lerp(Color.WHITE, 0.25))
	var floor_mi := MeshInstance3D.new()
	var fst := MeshLib.begin()
	MeshLib.prism(fst, outline, 0.006)
	floor_mi.mesh = MeshLib.finish(fst)
	floor_mi.material_override = _door_lamp
	floor_mi.name = "Threshold"
	floor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mi)
	# the lintel over the doorway and the shop sign on it, facing the flippers
	var lintel := MeshInstance3D.new()
	var mid := (a + b) * 0.5 - face * 0.04
	_orient_box(lintel, mid, along, span + 0.04, 0.10, 0.08, LINTEL_Y + 0.05)
	lintel.material_override = lib.wood()
	lintel.name = "Lintel"
	add_child(lintel)
	var back_lintel := MeshInstance3D.new()
	var back_mid := (outline[2] + outline[3]) * 0.5
	_orient_box(back_lintel, back_mid, back_direction(), outline[2].distance_to(outline[3]) + 0.04, 0.10, 0.06,
			LINTEL_Y + 0.05)
	back_lintel.material_override = lib.wood()
	back_lintel.name = "BackLintel"
	add_child(back_lintel)
	var roof := MeshInstance3D.new()
	var rst := MeshLib.begin()
	var eave: Array[PackedVector2Array] = Geometry2D.offset_polygon(outline, 0.01, Geometry2D.JOIN_MITER)
	MeshLib.prism(rst, eave[0] if not eave.is_empty() else outline, 0.03, LINTEL_Y + 0.10, true)
	roof.mesh = MeshLib.finish(rst)
	roof.material_override = lib.brass_dark()
	roof.name = "Roof"
	add_child(roof)
	var sign := TextMesh.new()
	sign.text = String(sign_text)
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 48
	sign.pixel_size = 0.0036
	sign.depth = 0.02
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_neon = lib.neon(neon_col, 2.6).duplicate() as StandardMaterial3D
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = _neon
	var front_mid := (a + b) * 0.5 + face * 0.01
	sm.position = Vector3(front_mid.x, LINTEL_Y + 0.22, front_mid.y)
	sm.rotation = Vector3(deg_to_rad(-38.0), Layout.yaw_facing(face), 0.0)
	sm.name = "Neon"
	add_child(sm)


func apply_build() -> void:
	var live := _present and bank_enabled
	for t in _targets:
		t.set_hardware_active(live)
	Dormant.set_collision(_shutter, _present and not bank_enabled)
	_shutter.visible = _present and not bank_enabled
	if not bank_enabled:
		_state = State.ARMED
		_timer = -1.0
	_apply_door()


func is_open() -> bool:
	return _state == State.OPEN


func state_name() -> StringName:
	match _state:
		State.OPEN:
			return &"open"
		State.COOLDOWN:
			return &"cooldown"
		_:
			return &"armed"


func down_count() -> int:
	var n := 0
	for t in _targets:
		if t.down:
			n += 1
	return n


func targets() -> Array[DropTarget]:
	return _targets


func _on_target_dropped(t: DropTarget) -> void:
	if not _present or not bank_enabled:
		return
	TableScore.earn_quiet(TableScore.GROUP_STOREFRONTS, TableScore.WIRE_TARGET * 0.5, t.id)
	if _state != State.ARMED or down_count() < _targets.size():
		return
	_state = State.OPEN
	_timer = open_seconds
	_glow = 1.0
	_apply_door()
	AudioDirector.play(&"drop_bank_down")
	TableScore.hit(StringName(String(id) + "_complete"), null)
	door_opened.emit(id)


func _on_door_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	if wash_enabled and _wash_cool <= 0.0:
		_wash_cool = WASH_COOLDOWN
		AudioDirector.play(&"laundromat_wash")
		TableScore.hit(&"laundromat_loop", ball)
		washed.emit(id)
	collect_now(ball)


func collect_now(ball: Node3D = null) -> BigMoney:
	if not _present or not bank_enabled or _state != State.OPEN:
		return BigMoney.zero()
	var amount := TableScore.storefront_collect_value(id)
	AudioDirector.play(&"storefront_collect")
	var paid := TableScore.earn_big(TableScore.GROUP_STOREFRONTS, amount,
			StringName(String(id) + "_collect"), ball)
	Events.storefront_collected.emit(id)
	collected.emit(id, amount)
	_state = State.COOLDOWN
	_timer = rearm_seconds
	_glow = 1.0
	_apply_door()
	return paid


func _close(quiet: bool = false) -> void:
	_state = State.ARMED
	_timer = -1.0
	_raise_all()
	_apply_door()
	if not quiet:
		AudioDirector.play(&"drop_bank_reset")
	door_closed.emit(id)


func _raise_all() -> void:
	for t in _targets:
		t.raise()


func _physics_process(delta: float) -> void:
	_wash_cool = maxf(_wash_cool - delta, 0.0)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.5, 0.0)
	_walk_out(delta)
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _ball_inside() != null:
		_timer = 0.5
		return
	_timer = -1.0
	match _state:
		State.OPEN, State.COOLDOWN:
			# a door left open or a cash-out done: the bank comes back up for another round
			_close()


func _ball_inside() -> Ball:
	if _inside == null:
		return null
	for body in _inside.get_overlapping_bodies():
		if body is Ball and not BallHold.is_held(body as Ball) \
				and Geometry2D.is_point_in_polygon(Layout.plan((body as Ball).table_position()), outline):
			return body as Ball
	return null


## A ball asleep on the shop floor goes out of the back door, into the plaza.
func _walk_out(delta: float) -> void:
	var b := _ball_inside()
	if b == null or b.speed() > Feel.HARDWARE_STALL_SPEED:
		_still = 0.0
		return
	_still += delta
	if _still < 0.4:
		return
	_still = 0.0
	var back := ((outline[2] + outline[3]) * 0.5 - (outline[0] + outline[1]) * 0.5).normalized()
	b.set_velocity(Vector3(back.x, 0.0, back.y) * 4.0)


func _process(delta: float) -> void:
	if _door_lamp != null:
		var wanted := 0.05
		if is_open():
			wanted = 1.6 + _glow + (0.8 if fmod(Time.get_ticks_msec() * 0.004, 1.0) < 0.5 else 0.0)
		elif bank_enabled and _state == State.ARMED:
			wanted = 0.12 + 0.25 * float(down_count())
		_door_lamp.emission_energy_multiplier = lerpf(_door_lamp.emission_energy_multiplier, wanted,
				1.0 - exp(-10.0 * delta))
	if _neon != null:
		var e := 0.12
		if bank_enabled:
			e = 0.9 if _state == State.COOLDOWN else 2.4
			e *= 0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.021 + float(get_instance_id() % 97))
		_neon.emission_energy_multiplier = e


func _apply_door() -> void:
	if _door == null:
		return
	var live := _present and bank_enabled and (_state == State.OPEN or wash_enabled)
	_door.collision_layer = Feel.LAYER_ZONES if live else 0
	_door.collision_mask = Feel.LAYER_BALL if live else 0


func set_ball(b: Ball) -> void:
	if _back_gate != null:
		_back_gate.set_ball(b)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	Dormant.set_collision(_jambs, active)
	if _back_gate != null:
		Dormant.apply(_back_gate, active)
	if _inside != null:
		_inside.collision_mask = Feel.LAYER_BALL if active else 0
	apply_build()


func is_hardware_active() -> bool:
	return _present


func visual_state() -> int:
	if not _present or not bank_enabled:
		return TableVisualState.VisualState.DISABLED
	match _state:
		State.OPEN:
			return TableVisualState.VisualState.ACTIVE
		State.COOLDOWN:
			return TableVisualState.VisualState.DISABLED
		_:
			return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"cooldown": _state == State.COOLDOWN, &"pulse": _glow > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
