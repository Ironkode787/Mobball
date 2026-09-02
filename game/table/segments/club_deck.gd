class_name ClubDeck
extends Node3D
## THE CLUB (R4): an upper playfield in the top-right corner of the machine, DECK_HEIGHT above
## the felt, reached by the Staircase ramp. Roulette bowl, three slot reels, the High Roller
## and back-room saucers, a pair of mini flippers, and a chute between them that drops the
## ball into the return wireform down the right side to the right inlane.
##
## Everything here is in table space; the deck's own floor is a real slab.

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

const DECK_H := 0.90
const DECK_LEFT := 0.55
const DECK_RIGHT := 2.20
const DECK_TOP := -5.25
const DECK_BOTTOM := -3.35
const WALL_THICK := 0.06
const WALL_HEIGHT := 0.34
const WHEEL_AT := Vector2(1.60, -4.50)
const REELS_AT := Vector2(1.90, -5.00)
const BACKROOM_AT := Vector2(1.15, -3.98)
const HIGH_ROLLER_AT := Vector2(0.75, -4.05)
const SAUCER_R := 0.15
const HIGH_ROLLER_STEPS: PackedFloat32Array = [1.0, 2.0, 3.0, 5.0]
const FLIPPER_PIVOT_L := Vector2(1.10, -3.62)
const FLIPPER_PIVOT_R := Vector2(1.70, -3.62)
const FLIPPER_SCALE := 0.5
## The chute at the deck's bottom-left corner where the return wireform begins; the left
## mini flipper guards it like an outlane and the bottom wall rakes toward it.
const CHUTE_LEFT := 0.60
const CHUTE_RIGHT := 0.95
const STAIR_ENTRY_SPEED := 4.0
## Down the corridor between the left lane guide and the Block, over the docks' yard, into
## the left inlane — the Staircase owns the right side of the machine.
const RETURN_PATH: PackedVector3Array = [
	Vector3(0.76, 0.87, -3.34), Vector3(0.35, 0.74, -3.36), Vector3(-0.25, 0.64, -3.34),
	Vector3(-0.90, 0.60, -3.15), Vector3(-1.40, 0.57, -2.65), Vector3(-1.78, 0.56, -2.00),
	Vector3(-1.86, 0.56, -1.20), Vector3(-1.86, 0.56, -0.20), Vector3(-1.86, 0.56, 0.80),
	Vector3(-1.90, 0.52, 1.60), Vector3(-1.95, 0.42, 2.45),
]
## The Penthouse stairs leave the deck at its top-left corner (penthouse.gd owns the ramp).
const PENTHOUSE_MOUTH := Vector2(0.82, -4.98)
const COL_VIOLET := Color("8C4DFF")
const COL_NEON_ROSE := Color("FF2E63")

var roulette: RouletteWheel = null
var reels: SlotReels = null
var high_roller: HoldSaucer = null
var backroom: HoldSaucer = null
var staircase: RampLane = null
var return_lane: RampLane = null
var flipper_left: Flipper = null
var flipper_right: Flipper = null

var _present: bool = false
var _flippers_live: bool = false
var _floor: StaticBody3D = null
var _shell: WallPiece = null
var _main_left: Flipper = null
var _main_right: Flipper = null
var _ball: Ball = null
var _look: Node3D = null


func _ready() -> void:
	_build_floor()
	_build_shell()
	_build_toys()
	_build_flippers()
	_build_ramps()
	_build_look()


func _build_floor() -> void:
	_floor = WallBuilder.make_body("DeckFloor", Feel.LAYER_WALLS,
			Feel.make_material(Feel.FELT_FRICTION, Feel.FELT_BOUNCE))
	add_child(_floor)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var w := DECK_RIGHT - DECK_LEFT
	var d := DECK_BOTTOM - DECK_TOP
	box.size = Vector3(w, 0.12, d)
	cs.shape = box
	cs.position = Vector3((DECK_LEFT + DECK_RIGHT) * 0.5, DECK_H - 0.06, (DECK_TOP + DECK_BOTTOM) * 0.5)
	_floor.add_child(cs)
	var lib := MaterialLib.shared()
	var felt := lib.carpet(Color("6E5AA8").lerp(Color.WHITE, 0.35))
	var st := MeshLib.begin()
	MeshLib.box(st, Vector3((DECK_LEFT + DECK_RIGHT) * 0.5, DECK_H - 0.06, (DECK_TOP + DECK_BOTTOM) * 0.5),
			Vector3(w, 0.12, d), 0.5)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, felt)
	mi.name = "Slab"
	_floor.add_child(mi)
	# posts holding the storey up along its front edge
	var posts := MeshLib.begin()
	for i in range(4):
		var x := lerpf(DECK_LEFT, DECK_RIGHT, (float(i) + 0.5) / 4.0)
		MeshLib.post(posts, Vector2(x, DECK_BOTTOM - 0.04), 0.035, DECK_H - 0.12, 0.0, 10)
	var pm := MeshInstance3D.new()
	pm.mesh = MeshLib.finish(posts, lib.brass_dark())
	pm.name = "Posts"
	_floor.add_child(pm)


func _build_shell() -> void:
	_shell = WallPiece.new(WALL_HEIGHT, DECK_H, MaterialLib.shared().brass_dark(), MaterialLib.shared().brass())
	_shell.name = "DeckShell"
	add_child(_shell)
	var t := WALL_THICK
	# left wall
	# the left and back walls stop short of the top-left corner: the Penthouse stairs leave
	# through it, diagonally, and their flared mouth seals the gap
	_shell.bar(Vector2(DECK_LEFT, DECK_BOTTOM - 0.12), Vector2(DECK_LEFT, -4.95), t)
	# top wall, open at the left where the Penthouse stairs leave the deck
	_shell.bar(Vector2(1.00, DECK_TOP), Vector2(DECK_RIGHT, DECK_TOP), t)
	# right wall, open where the Staircase arrives (z -4.55 .. -3.95)
	_shell.bar(Vector2(DECK_RIGHT, DECK_TOP), Vector2(DECK_RIGHT, -4.55), t)
	_shell.bar(Vector2(DECK_RIGHT, -3.95), Vector2(DECK_RIGHT, DECK_BOTTOM), t)
	# bottom wall: raked toward the chute at the bottom-left corner
	_shell.bar(Vector2(DECK_RIGHT, DECK_BOTTOM - 0.14), Vector2(CHUTE_RIGHT, DECK_BOTTOM), t)
	# inlane sweep to the right mini flipper
	_shell.bar(Vector2(DECK_RIGHT - 0.03, -3.95), Vector2(FLIPPER_PIVOT_R.x + 0.02, FLIPPER_PIVOT_R.y - 0.02), 0.04)


func _build_toys() -> void:
	roulette = RouletteWheel.new()
	roulette.name = "Roulette"
	roulette.configure(ID_ROULETTE, WHEEL_AT, DECK_H)
	add_child(roulette)
	roulette.landed.connect(func(pocket: int, house: bool) -> void: roulette_landed.emit(pocket, house))

	reels = SlotReels.new()
	reels.name = "SlotReels"
	reels.configure(ID_REELS, REELS_AT, DECK_H)
	add_child(reels)
	reels.state_changed.connect(func(cols: Array) -> void: reels_state.emit(cols))

	high_roller = HoldSaucer.new()
	high_roller.name = "HighRoller"
	high_roller.steps = HIGH_ROLLER_STEPS
	high_roller.eject_speed = 9.0
	high_roller.eject_heat = 1.5
	high_roller.configure(ID_HIGH_ROLLER, HIGH_ROLLER_AT, SAUCER_R, Vector2(0.80, 0.60), DECK_H)
	add_child(high_roller)
	high_roller.ejected.connect(func(steps: int) -> void: high_roller_held.emit(steps))

	backroom = HoldSaucer.new()
	backroom.name = "Backroom"
	backroom.hold_seconds = 0.8
	backroom.eject_speed = 6.0
	backroom.configure(ID_BACKROOM, BACKROOM_AT, SAUCER_R, Vector2(0.18, -1.0), DECK_H)
	add_child(backroom)
	backroom.captured.connect(func() -> void: backroom_entered.emit())


func _build_flippers() -> void:
	flipper_left = _make_flipper(&"left", FLIPPER_PIVOT_L, "ClubFlipperLeft")
	flipper_right = _make_flipper(&"right", FLIPPER_PIVOT_R, "ClubFlipperRight")


func _make_flipper(side: StringName, at: Vector2, node_name: String) -> Flipper:
	var f := Flipper.new()
	f.side = side
	f.size_scale = FLIPPER_SCALE
	f.name = node_name
	f.position = Layout.p3(at, DECK_H)
	add_child(f)
	return f


func _build_ramps() -> void:
	staircase = RampLane.new()
	staircase.name = "Staircase"
	staircase.entry_speed = STAIR_ENTRY_SPEED
	staircase.entry_size = Layout.STAIR_MOUTH_SIZE
	staircase.color = Feel.COL_NEON_ROSE.darkened(0.15)
	staircase.configure(ID_STAIRCASE, Layout.STAIR_PATH)
	add_child(staircase)
	staircase.crested.connect(_on_staircase_crested)

	return_lane = RampLane.new()
	return_lane.name = "ReturnLane"
	return_lane.entry_speed = -100000.0
	return_lane.entry_size = Vector2(CHUTE_RIGHT - CHUTE_LEFT + 0.1, 0.3)
	return_lane.color = COL_VIOLET.lightened(0.2)
	return_lane.configure(&"club_return", RETURN_PATH)
	add_child(return_lane)
	return_lane.crested.connect(_on_returned)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var sign := TextMesh.new()
	sign.text = "THE CLUB"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 64
	sign.pixel_size = 0.0065
	sign.depth = 0.03
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = lib.neon(COL_NEON_ROSE, 2.6)
	sm.position = Vector3((DECK_LEFT + DECK_RIGHT) * 0.5, DECK_H + 0.62, DECK_TOP + 0.05)
	_look.add_child(sm)
	var light := OmniLight3D.new()
	light.light_color = COL_NEON_ROSE
	light.light_energy = 1.2
	light.omni_range = 2.6
	light.shadow_enabled = false
	light.position = Vector3((DECK_LEFT + DECK_RIGHT) * 0.5, DECK_H + 0.9, DECK_TOP + 0.6)
	_look.add_child(light)


func bind_flippers(left: Flipper, right: Flipper) -> void:
	_main_left = left
	_main_right = right


func set_ball(b: Ball) -> void:
	_ball = b
	for holder: Node in [roulette, high_roller, backroom, staircase, return_lane]:
		if holder != null:
			holder.call(&"set_ball", b)


func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_ROULETTE], "node": roulette},
		{"ids": [ID_REELS], "node": reels},
		{"ids": [ID_HIGH_ROLLER], "node": high_roller},
		{"ids": [ID_BACKROOM], "node": backroom},
		{"ids": [ID_STAIRCASE], "node": staircase},
		{"ids": [ID_FLIPPERS], "node": flipper_left},
		{"ids": [ID_FLIPPERS], "node": flipper_right},
	]


func bounds() -> AABB:
	return AABB(Vector3(DECK_LEFT, DECK_H - 0.15, DECK_TOP), Vector3(DECK_RIGHT - DECK_LEFT, 1.0, DECK_BOTTOM - DECK_TOP))


func deck_rect() -> Rect2:
	return Rect2(Vector2(DECK_LEFT, DECK_TOP), Vector2(DECK_RIGHT - DECK_LEFT, DECK_BOTTOM - DECK_TOP))


func on_deck(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	var p := ball.table_position()
	return p.y > DECK_H - 0.1 and deck_rect().has_point(Vector2(p.x, p.z))


func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	if BallHold.is_held(ball):
		return true
	var p := ball.table_position()
	return on_deck(ball) and p.z > FLIPPER_PIVOT_L.y - 0.4


func holds_ball() -> bool:
	for holder: Node in [roulette, high_roller, backroom]:
		if holder != null and bool(holder.call(&"holds_ball")):
			return true
	return (staircase != null and staircase.riding()) or (return_lane != null and return_lane.riding())


func _physics_process(_delta: float) -> void:
	if not _flippers_live:
		return
	if _main_left != null and flipper_left != null:
		flipper_left.set_pressed(_main_left.is_held())
	if _main_right != null and flipper_right != null:
		flipper_right.set_pressed(_main_right.is_held())


func _on_staircase_crested(speed: float) -> void:
	AudioDirector.play(&"staircase_crest")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, ID_STAIRCASE, _ball, speed)
	staircase_climbed.emit(speed)


func _on_returned(_speed: float) -> void:
	AudioDirector.play(&"wall_tap")
	returned_home.emit(Layout.plan(RETURN_PATH[RETURN_PATH.size() - 1]))


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if _floor != null:
		_floor.collision_layer = Feel.LAYER_WALLS if active else 0
	for piece: Node in [_shell, return_lane]:
		if piece != null:
			Dormant.apply(piece, active)
	if not active:
		_flippers_live = false
		_release_everything()


func is_hardware_active() -> bool:
	return _present


func set_flippers_live(live: bool) -> void:
	_flippers_live = live and _present
	if not _flippers_live and flipper_left != null and flipper_right != null:
		flipper_left.set_pressed(false)
		flipper_right.set_pressed(false)


func _release_everything() -> void:
	var was_holding := holds_ball()
	for holder: Node in [roulette, high_roller, backroom, staircase, return_lane]:
		if holder != null and holder.has_method(&"set_hardware_active"):
			holder.call(&"set_hardware_active", false)
	if was_holding and _ball != null and is_instance_valid(_ball):
		BallHold.release(_ball, RETURN_PATH[RETURN_PATH.size() - 1] + Vector3(0, Feel.BALL_RADIUS, 0), Vector3.ZERO)
