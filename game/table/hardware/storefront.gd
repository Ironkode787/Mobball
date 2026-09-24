class_name Storefront
extends Node3D
## A protection racket as pinball hardware (docs/20 §3.3): a shop on its own island with a
## three-bank of drops across its front. Knock all three down and the shop pays up on the
## spot — minutes of that racket's idle income — then the bank rests a few seconds, lit PAID,
## and stands up again.
##
## Before the racket is bought the shop is boarded up: a shutter across the front, a dark sign,
## and the island still stands as part of the board's shape.
##
## Built in table space from the island's outline: front-left, front-right, back-right,
## back-left. The island is solid; the drops stand in front of a backstop, so a ball that finds
## the bank already down meets the shop's front instead of rolling in.

signal collected(id: StringName, amount: BigMoney)
signal washed(id: StringName)
## The bank went down (the shop pays) and, `rearm_seconds` later, came back up.
signal door_opened(id: StringName)
signal door_closed(id: StringName)

enum State { ARMED, COOLDOWN }

const TARGETS := 3
const WALL_THICK := 0.05
const WALL_HEIGHT := 0.34
const LINTEL_Y := 0.42
const NEON := {
	&"storefront_laundromat": Color("2EE6D6"),
	&"storefront_pizzeria": Color("FF2E63"),
	&"storefront_pawn": Color("FFC341"),
}

@export var id: StringName = &"storefront"

## Kept for the balance model's reading of the shop (game/sim/sim_table.gd).
var open_seconds: float = 0.0
var rearm_seconds: float = 4.0
var sign_text: StringName = &"SHOP"
var bank_enabled: bool = true
var wash_enabled: bool = false
var outline: PackedVector2Array = PackedVector2Array()

var _targets: Array[DropTarget] = []
var _shutter: StaticBody3D = null
var _walls: WallPiece = null
var _state: State = State.ARMED
var _timer: float = -1.0
var _present: bool = true
var _glow: float = 0.0
var _front_lamp: StandardMaterial3D = null
var _neon: StandardMaterial3D = null
var _paid_sign: MeshInstance3D = null
## Set while the crew knocks a bank down by hand, so the last drop does not pay a second time.
var _forcing: bool = false


func configure(p_id: StringName, p_outline: PackedVector2Array, p_sign: StringName) -> void:
	id = p_id
	outline = p_outline
	sign_text = p_sign


func front_from() -> Vector2:
	return outline[0]


func front_to() -> Vector2:
	return outline[1]


## Unit vector out of the shop's front toward the player.
func facing() -> Vector2:
	var along := (outline[1] - outline[0]).normalized()
	var n := Vector2(-along.y, along.x)
	var inward := ((outline[2] + outline[3]) * 0.5 - (outline[0] + outline[1]) * 0.5)
	return -n if n.dot(inward) > 0.0 else n


func centre() -> Vector2:
	return (outline[0] + outline[1] + outline[2] + outline[3]) * 0.25


func _ready() -> void:
	var lib := MaterialLib.shared()
	var a := outline[0]
	var b := outline[1]
	var along := (b - a).normalized()
	var span := a.distance_to(b)
	var face := facing()
	# the island: solid on every side, the front closed by a backstop behind the drops
	_walls = WallPiece.new(WALL_HEIGHT, 0.0, lib.wood_dark(), lib.brass())
	_walls.name = "Island"
	add_child(_walls)
	_walls.chain(PackedVector2Array([outline[1], outline[2], outline[3], outline[0]]), WALL_THICK)
	var back := face * -(DropTarget.new().thickness + WALL_THICK) * 0.5
	_walls.bar(a + back, b + back, WALL_THICK)
	# the bank across the front
	var pitch := (span - WALL_THICK) / float(TARGETS)
	for i in range(TARGETS):
		var t := DropTarget.new()
		t.name = "Target%d" % (i + 1)
		var c := a + along * (WALL_THICK * 0.5 + pitch * (float(i) + 0.5))
		t.configure(StringName("%s_t%d" % [id, i + 1]), c, face, pitch - 0.012)
		t.thickness = 0.05
		add_child(t)
		t.dropped.connect(_on_target_dropped)
		_targets.append(t)
	# the shutter while the racket is not ours
	_shutter = WallBuilder.make_body("Shutter", Feel.LAYER_WALLS)
	add_child(_shutter)
	var sw := WallBuilder.new(_shutter, WALL_HEIGHT)
	sw.bar(a + face * 0.04, b + face * 0.04, 0.05)
	var sm := MeshInstance3D.new()
	sm.material_override = lib.chrome_dark()
	sm.name = "ShutterLook"
	_shutter.add_child(sm)
	_orient_box(sm, (a + b) * 0.5 + face * 0.04, along, span, WALL_HEIGHT, 0.04, WALL_HEIGHT * 0.5)
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
	# a lit strip along the foot of the bank: how many drops are down, and PAID
	_front_lamp = lib.lamp(neon_col.lerp(Color.WHITE, 0.25))
	var strip := MeshInstance3D.new()
	var fst := MeshLib.begin()
	var out := face * 0.10
	MeshLib.prism(fst, PackedVector2Array([a + out, b + out, b + face * 0.03, a + face * 0.03]), 0.006)
	strip.mesh = MeshLib.finish(fst)
	strip.material_override = _front_lamp
	strip.name = "Threshold"
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(strip)
	# the lintel over the front and the shop sign on it, facing the flippers
	var lintel := MeshInstance3D.new()
	_orient_box(lintel, (a + b) * 0.5 - face * 0.04, along, span + 0.04, 0.10, 0.08, LINTEL_Y + 0.05)
	lintel.material_override = lib.wood()
	lintel.name = "Lintel"
	add_child(lintel)
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
	sign.pixel_size = 0.0040
	sign.depth = 0.02
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_neon = lib.neon(neon_col, 2.6).duplicate() as StandardMaterial3D
	var nm := MeshInstance3D.new()
	nm.mesh = sign
	nm.material_override = _neon
	var front_mid := (a + b) * 0.5 + face * 0.01
	nm.position = Vector3(front_mid.x, LINTEL_Y + 0.22, front_mid.y)
	nm.rotation = Vector3(deg_to_rad(-38.0), Layout.yaw_facing(face), 0.0)
	nm.name = "Neon"
	add_child(nm)
	# PAID: lit on the lintel while the bank rests
	var paid := TextMesh.new()
	paid.text = "PAID"
	paid.font = sign.font
	paid.font_size = 40
	paid.pixel_size = 0.0036
	paid.depth = 0.01
	paid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var pm := MeshInstance3D.new()
	pm.mesh = paid
	pm.material_override = lib.neon(Feel.COL_CLEAN, 2.4)
	pm.position = Vector3(front_mid.x, LINTEL_Y + 0.06, front_mid.y) + Vector3(face.x, 0.0, face.y) * 0.02
	pm.rotation = Vector3(deg_to_rad(-38.0), Layout.yaw_facing(face), 0.0)
	pm.name = "Paid"
	pm.visible = false
	add_child(pm)
	_paid_sign = pm


func apply_build() -> void:
	var live := _present and bank_enabled
	for t in _targets:
		t.set_hardware_active(live)
	Dormant.set_collision(_shutter, _present and not bank_enabled)
	_shutter.visible = _present and not bank_enabled
	if not bank_enabled:
		_state = State.ARMED
		_timer = -1.0


## Kept for the flow's readers: the bank never waits open for a ball any more.
func is_open() -> bool:
	return false


## &"armed" (the bank is standing and pays when it is down), &"cooldown" (it just paid) or
## &"shut" (the shop is boarded up, or not on the table).
func state_name() -> StringName:
	if not _present or not bank_enabled:
		return &"shut"
	return &"cooldown" if _state == State.COOLDOWN else &"armed"


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
	_glow = 0.6
	if _forcing or _state != State.ARMED or down_count() < _targets.size():
		return
	AudioDirector.play(&"drop_bank_down")
	TableScore.hit(StringName(String(id) + "_complete"), null)
	_pay(null)


## The shop pays now: the flow's crew (Manny) collects a standing bank by knocking it down
## himself. Nothing if the shop is shut or has just paid.
func collect_now(ball: Node3D = null) -> BigMoney:
	if not _present or not bank_enabled or _state != State.ARMED:
		return BigMoney.zero()
	_forcing = true
	for t in _targets:
		t.drop(ball as Ball)
	_forcing = false
	AudioDirector.play(&"drop_bank_down")
	return _pay(ball)


func _pay(ball: Node3D) -> BigMoney:
	var amount := TableScore.storefront_collect_value(id)
	AudioDirector.play(&"storefront_collect")
	var paid := TableScore.earn_big(TableScore.GROUP_STOREFRONTS, amount,
			StringName(String(id) + "_collect"), ball)
	_state = State.COOLDOWN
	_timer = rearm_seconds
	_glow = 1.0
	door_opened.emit(id)
	Events.storefront_collected.emit(id)
	collected.emit(id, amount)
	return paid


## The bank stands up again now instead of resting out its time.
func rearm() -> void:
	if _state == State.COOLDOWN:
		_close(true)


func _close(quiet: bool = false) -> void:
	_state = State.ARMED
	_timer = -1.0
	for t in _targets:
		t.raise()
	if not quiet:
		AudioDirector.play(&"drop_bank_reset")
	door_closed.emit(id)


func _physics_process(delta: float) -> void:
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.5, 0.0)
	if _timer < 0.0:
		return
	_timer -= delta
	if _timer <= 0.0 and _state == State.COOLDOWN:
		_close()


func _process(delta: float) -> void:
	var paid := _present and bank_enabled and _state == State.COOLDOWN
	if _front_lamp != null:
		var wanted := 0.05
		if paid:
			wanted = 1.6 + (0.8 if fmod(Time.get_ticks_msec() * 0.004, 1.0) < 0.5 else 0.0)
		elif _present and bank_enabled:
			wanted = 0.25 + 0.45 * float(down_count()) + _glow
		_front_lamp.emission_energy_multiplier = lerpf(_front_lamp.emission_energy_multiplier, wanted,
				1.0 - exp(-10.0 * delta))
	if _paid_sign != null:
		_paid_sign.visible = paid
	if _neon != null:
		var e := 0.12
		if bank_enabled:
			e = 0.9 if _state == State.COOLDOWN else 2.4
			e *= 0.94 + 0.06 * sin(Time.get_ticks_msec() * 0.021 + float(get_instance_id() % 97))
		_neon.emission_energy_multiplier = e


func set_ball(_b: Ball) -> void:
	pass


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	Dormant.set_collision(_walls, active)
	apply_build()


func is_hardware_active() -> bool:
	return _present


func visual_state() -> int:
	if not _present or not bank_enabled:
		return TableVisualState.VisualState.DISABLED
	if _state == State.COOLDOWN:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"cooldown": _state == State.COOLDOWN, &"pulse": _glow > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
