class_name ClubDeck
extends Node3D
## THE CLUB (R4, docs/19 §3.4): a casino strip on its own raised deck in the upper left, reached
## by the Staircase and left by the cashier lane, the way Space Cadet's launch area works. On
## the deck:
##   * three slot reels on the back wall: a reel's first hit in a visit stops it, and all three
##     stopped inside one visit is the jackpot (`reels_state`)
##   * the roulette saucer at the top of the strip: only a ramp shot with pace reaches it. It
##     takes the ball, the pocket lamps chase and land (`roulette_landed`, honest odds: the house
##     keeps its pockets); with the High Roller Room bought the hold climbs rungs first
##   * the back room by the cashier: the Family Meeting's saucer (`backroom_entered`)
## The deck drains through the cashier into the left wireform and home to the left inlane.

signal roulette_landed(pocket: int, house: bool)
signal reels_state(cleared_columns: Array)
signal high_roller_held(steps: int)
signal backroom_entered()
signal staircase_climbed(speed: float)
signal returned_home(at: Vector2)

const ID_DECK := &"club_deck"
const ID_STAIRCASE := &"staircase_ramp"
const ID_ROULETTE := &"roulette_wheel"
const ID_REELS := &"slot_reels"
const ID_HIGH_ROLLER := &"high_roller_saucer"
const ID_BACKROOM := &"backroom_saucer"
const ID_FLIPPERS := &"club_flippers"

const DECK_H := 0.50
const DECK_FRONT := -2.36
const DECK_LEFT := -2.00
const DECK_RIGHT := -1.30
const DECK_BOTTOM := DECK_FRONT
const DECK_RING_R := 1.84
const WALL_THICK := 0.05
const WALL_HEIGHT := 0.30
const REEL_DEG: PackedFloat32Array = [219.0, 203.0, 187.0]
const REEL_R := 1.75
const ROULETTE_AT := Vector2(-1.47, -3.52)
const BACKROOM_AT := Vector2(-1.80, -2.84)
const SAUCER_R := 0.15
const GATE_Z := -2.74
const GATE_FROM := -1.66
const GATE_TO := -1.30
const CASHIER_FROM := DECK_LEFT
const CASHIER_TO := -1.68
const POCKETS := 8
const HOUSE_GIVE_ORDER: PackedInt32Array = [6, 3, 0]
const PLAYER_POCKETS_BASE := 5
const HIGH_ROLLER_STEPS: PackedFloat32Array = [1.0, 2.0, 3.0, 5.0]
## The flow's socket: the Family Meeting's joiners come in on the deck, below the reels.
const MEETING_AT := Vector2(-1.75, -3.05)
## Straight off the cashier's edge first, so the wireform's walls start clear of the deck and
## of the Staircase's channel beside it.
const RETURN_PATH: PackedVector3Array = [
	Vector3(-1.86, 0.475, -2.38), Vector3(-1.90, 0.465, -2.08), Vector3(-2.04, 0.47, -1.66),
	Vector3(-2.30, 0.51, -1.10), Vector3(-2.32, 0.45, 0.00), Vector3(-2.26, 0.40, 1.20),
	Vector3(-2.10, 0.35, 1.95), Vector3(-1.94, 0.30, 2.35),
]

var reels: Array[StandupTarget] = []
var roulette: HoldSaucer = null
var backroom: HoldSaucer = null
var high_roller: HoldSaucer = null        ## the roulette saucer, when the High Roller Room is owned
var staircase: RampLane = null
var return_lane: RampLane = null
var entry_gate: OneWayGate = null
var high_roller_owned: bool = false

var _present: bool = true
var _floor: StaticBody3D = null
var _shell: WallPiece = null
var _ball: Ball = null
var _reels: Array[int] = []
var _rng := RandomNumberGenerator.new()
var _pocket_lamps: Array[StandardMaterial3D] = []
var _chase_t: float = -1.0
var _landed: int = -1
var _player_pockets: int = PLAYER_POCKETS_BASE
var _look: Node3D = null


func _ready() -> void:
	_rng.seed = 0xC1B
	_build_floor()
	_build_shell()
	_build_toys()
	_build_ramps()


## The deck's outline in plan: the front edge, the right edge up to the ring, the ring back down.
static func outline() -> PackedVector2Array:
	var c := Layout.RING_CENTER
	var top := c.y - sqrt(DECK_RING_R * DECK_RING_R - pow(DECK_RIGHT - c.x, 2.0))
	var pts := PackedVector2Array([Vector2(DECK_LEFT, DECK_FRONT), Vector2(DECK_RIGHT, DECK_FRONT), Vector2(DECK_RIGHT, top)])
	var a0 := fposmod(rad_to_deg(atan2(top - c.y, DECK_RIGHT - c.x)), 360.0)
	var a1 := fposmod(rad_to_deg(atan2(DECK_FRONT - c.y, DECK_LEFT - c.x)), 360.0)
	for i in range(1, 16):
		var a := deg_to_rad(lerpf(a0, a1, float(i) / 16.0))
		pts.append(c + Vector2(cos(a), sin(a)) * DECK_RING_R)
	return pts


static func reel_point(i: int) -> Vector2:
	return Layout.ring_point(REEL_DEG[i], REEL_R)


func _build_floor() -> void:
	var lib := MaterialLib.shared()
	_floor = WallBuilder.make_body("DeckFloor", Feel.LAYER_WALLS, Feel.make_material(Feel.FELT_FRICTION, Feel.FELT_BOUNCE))
	add_child(_floor)
	var poly := outline()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := Geometry2D.triangulate_polygon(poly)
	for k in range(0, tri.size(), 3):
		for j: int in [0, 2, 1]:
			var q := poly[tri[k + j]]
			st.set_uv(Vector2(q.x, q.y))
			st.add_vertex(Vector3(q.x, DECK_H, q.y))
	# the skirt round the whole slab so nothing rolls underneath
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		for q: Vector3 in [Vector3(a.x, 0.0, a.y), Vector3(b.x, DECK_H, b.y), Vector3(b.x, 0.0, b.y),
				Vector3(a.x, 0.0, a.y), Vector3(a.x, DECK_H, a.y), Vector3(b.x, DECK_H, b.y)]:
			st.set_uv(Vector2(q.x + q.z, q.y))
			st.add_vertex(q)
	st.generate_normals()
	var mesh := st.commit()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(mesh.get_faces())
	cs.shape = shape
	_floor.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = lib.carpet(Color("6E5AA8").lerp(Color.BLACK, 0.35))
	mi.name = "Slab"
	_floor.add_child(mi)
	var posts := MeshLib.begin()
	for x: float in [-2.0, -1.66, -1.34]:
		MeshLib.post(posts, Vector2(x, DECK_FRONT + 0.03), 0.03, DECK_H - 0.02, 0.0, 10)
	var pm := MeshInstance3D.new()
	pm.mesh = MeshLib.finish(posts, lib.brass())
	pm.name = "Posts"
	_floor.add_child(pm)


func _build_shell() -> void:
	var lib := MaterialLib.shared()
	_shell = WallPiece.new(WALL_HEIGHT, DECK_H, lib.brass_dark(), lib.brass())
	_shell.name = "DeckShell"
	add_child(_shell)
	var poly := outline()
	# the right edge and the ring edge
	var back := PackedVector2Array()
	for i in range(1, poly.size()):
		back.append(poly[i])
	back.append(Vector2(DECK_LEFT, DECK_FRONT - 0.04))
	_shell.chain(back, WALL_THICK)
	# the front is the cashier on the left of the Staircase's channel: whatever rolls down the
	# deck goes home through it
	entry_gate = OneWayGate.new()
	entry_gate.name = "EntryGate"
	entry_gate.configure(&"club_entry_gate", Vector2(GATE_FROM, GATE_Z), Vector2(GATE_TO, GATE_Z), 0.04, Vector2(0.0, 1.0), DECK_H)
	add_child(entry_gate)


func _build_toys() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	for i in range(REEL_DEG.size()):
		var t := StandupTarget.new()
		t.name = "Reel%d" % (i + 1)
		t.lamp_color = Color(0.78, 0.55, 1.0)
		var at := reel_point(i)
		var inward := (Layout.RING_CENTER - at).normalized()
		t.configure(StringName("slot_reel_%d" % (i + 1)), at, inward, 0.20)
		t.position.y = DECK_H
		add_child(t)
		t.struck.connect(_on_reel.bind(i))
		reels.append(t)
	roulette = HoldSaucer.new()
	roulette.name = "Roulette"
	roulette.configure(ID_ROULETTE, ROULETTE_AT, SAUCER_R, Vector2(-0.35, 1.0), DECK_H)
	roulette.hold_seconds = 1.3
	roulette.eject_speed = 6.0
	add_child(roulette)
	roulette.captured.connect(_on_roulette_captured)
	roulette.ejected.connect(func(steps: int) -> void:
		if high_roller_owned:
			high_roller_held.emit(steps))
	high_roller = roulette
	for i in range(POCKETS):
		var a := float(i) * TAU / float(POCKETS)
		var lamp := lib.lamp(Feel.COL_BRASS)
		var dot := CylinderMesh.new()
		dot.top_radius = 0.026
		dot.bottom_radius = 0.026
		dot.height = 0.01
		var mi := MeshInstance3D.new()
		mi.mesh = dot
		mi.material_override = lamp
		mi.position = Layout.p3(ROULETTE_AT + Vector2(cos(a), sin(a)) * (SAUCER_R + 0.07), DECK_H + 0.006)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_look.add_child(mi)
		_pocket_lamps.append(lamp)
	backroom = HoldSaucer.new()
	backroom.name = "BackRoom"
	backroom.configure(ID_BACKROOM, BACKROOM_AT, SAUCER_R, Vector2(0.15, 1.0), DECK_H)
	backroom.hold_seconds = 0.9
	backroom.eject_speed = 4.0
	add_child(backroom)
	backroom.captured.connect(func() -> void: backroom_entered.emit())
	var sign := Label3D.new()
	sign.text = "THE CLUB"
	sign.font_size = 60
	sign.pixel_size = 0.0022
	sign.modulate = Color(0.8, 0.62, 1.0)
	sign.position = Vector3(-1.62, DECK_H + 0.36, -3.95)
	sign.rotation.x = deg_to_rad(-60.0)
	sign.name = "Sign"
	_look.add_child(sign)


func _build_ramps() -> void:
	staircase = RampLane.new()
	staircase.name = "Staircase"
	staircase.configure(ID_STAIRCASE, Layout.STAIR_PATH)
	staircase.flare_width = Layout.STAIR_FLARE
	staircase.entry_speed = 4.0
	staircase.skirt = true
	add_child(staircase)
	staircase.crested.connect(func(speed: float) -> void:
		_reels.clear()
		TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, &"staircase_ramp", _ball, speed)
		staircase_climbed.emit(speed))
	return_lane = RampLane.new()
	return_lane.name = "CashierReturn"
	return_lane.configure(&"club_return", RETURN_PATH)
	return_lane.entry_speed = -10000.0
	return_lane.wall_height = 0.30
	add_child(return_lane)
	return_lane.crested.connect(func(_s: float) -> void:
		returned_home.emit(Layout.plan(RETURN_PATH[RETURN_PATH.size() - 1])))


func _on_reel(_target: StandupTarget, b: Ball, index: int) -> void:
	TableScore.earn(TableScore.GROUP_CASINO, TableScore.CASINO_REEL, StringName("slot_reel_%d" % (index + 1)), b)
	if _reels.has(index):
		return
	_reels.append(index)
	_reels.sort()
	reels[index].set_marked(true)
	AudioDirector.play(&"reel_stop")
	reels_state.emit(_reels.duplicate())
	if _reels.size() >= reels.size():
		_reset_reels_later()


func _reset_reels_later() -> void:
	await get_tree().create_timer(1.5).timeout
	_reels.clear()
	for r in reels:
		r.set_marked(false)


func _on_roulette_captured() -> void:
	_refresh_pockets()
	roulette.steps = HIGH_ROLLER_STEPS if high_roller_owned else PackedFloat32Array()
	_chase_t = 0.0
	_landed = _rng.randi_range(0, POCKETS - 1)
	AudioDirector.play(&"wheel_clatter")


func _refresh_pockets() -> void:
	var n := PLAYER_POCKETS_BASE
	if Game != null and Game.stats != null and Game.stats.has_method("casino_player_pockets"):
		n = int(Game.stats.call("casino_player_pockets"))
	_player_pockets = clampi(n, 1, POCKETS - 1)


func is_house(pocket: int) -> bool:
	var keep := clampi(POCKETS - _player_pockets, 0, HOUSE_GIVE_ORDER.size())
	for i in range(HOUSE_GIVE_ORDER.size()):
		if HOUSE_GIVE_ORDER[i] == pocket:
			return i >= HOUSE_GIVE_ORDER.size() - keep
	return false


func _process(delta: float) -> void:
	if _chase_t < 0.0:
		return
	_chase_t += delta
	var lit := int(_chase_t * 18.0) % POCKETS
	if _chase_t >= 0.9:
		lit = _landed if _landed >= 0 else lit
	for i in range(POCKETS):
		_pocket_lamps[i].emission = Feel.COL_DIRTY if is_house(i) else Feel.COL_BRASS
		_pocket_lamps[i].emission_energy_multiplier = 2.4 if i == lit else 0.25
	if _chase_t >= 0.9 and _landed >= 0:
		var p := _landed
		_landed = -1
		AudioDirector.play(&"chip_stack")
		TableScore.earn(TableScore.GROUP_CASINO, TableScore.CASINO_POCKET, StringName("roulette_pocket_%d" % p), _ball)
		roulette_landed.emit(p, is_house(p))
	if _chase_t >= 2.4:
		_chase_t = -1.0
		for l in _pocket_lamps:
			l.emission_energy_multiplier = 0.1


func bind_flippers(_left: Flipper, _right: Flipper) -> void:
	pass


func set_flippers_live(_live: bool) -> void:
	pass


func set_ball(b: Ball) -> void:
	_ball = b
	roulette.set_ball(b)
	backroom.set_ball(b)
	entry_gate.set_ball(b)
	staircase.set_ball(b)
	return_lane.set_ball(b)


func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_STAIRCASE], "node": staircase},
		{"ids": [ID_ROULETTE, ID_HIGH_ROLLER], "node": roulette},
		{"ids": [ID_BACKROOM], "node": backroom},
	]


func deck_rect() -> Rect2:
	return Rect2(Vector2(DECK_LEFT, -4.36), Vector2(DECK_RIGHT - DECK_LEFT, 4.36 + DECK_FRONT))


func on_deck(b: Ball) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	var p := b.table_position()
	return p.y > DECK_H - 0.05 and Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), outline())


func search_exempt(_b: Ball) -> bool:
	return roulette.holds_ball() or backroom.holds_ball()


func holds_ball() -> bool:
	return roulette.holds_ball() or backroom.holds_ball()


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	Dormant.apply(_floor, active)
	Dormant.apply(_shell, active)
	for r in reels:
		r.set_hardware_active(active)
	Dormant.apply(entry_gate, active)
	Dormant.apply(return_lane, active)
	_look.visible = active
	if not active:
		_reels.clear()


func is_hardware_active() -> bool:
	return _present
