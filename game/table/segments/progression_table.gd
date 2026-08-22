class_name ProgressionTable
extends TableSegment
## THE TABLE (specs/m1-hook.md Lane 3). One screen, 1080×1920, built entirely in code so the
## collision geometry and the `_draw()` come from the same numbers and can never drift.
##
## What the player starts with is a *bare alley*: walls, two flippers, a drain, one dented
## trash can and a rubber band for a plunger. Everything else on this table already exists —
## it is built, wired and standing there — but it is hidden and its collision is switched
## off until `Game.stats.hardware_unlocked(id)` says the Ledger has paid for it. Buying
## furniture is the tutorial (docs/02 §2 R0), so the growth has to be physical: a dormant
## piece must not deflect a ball, and a live one must not appear without its geometry.
##
## The lower third is inherited from the M0 alley and is not up for renegotiation: flipper
## pivots, slingshot rake, the divider fix and the raked inlane floors are all tuned numbers
## (see segments/alley_debug.gd's header for why each one is what it is). Everything M1 adds
## lives in the top two thirds.
##
## Zones, bottom to top (docs/02 §0):
##   THE ALLEY   flippers, slings, one to three trash cans, the storm-grate drain
##   THE BLOCK   three storefront drop banks across the waist, cop targets for raids
##   THE CORNER  The Wire's three payphones on the right, the numbers lane down the left
##   THE ARCH    three top lanes, the getaway orbit, the beat cop's donut shop

signal ball_spawned(ball: Ball)
signal ball_lost(ball: Ball)
## Lucky's door took a pass: the flow lane converts dirty → clean (specs/m1-hook.md Lane 1).
signal laundromat_pass()
## The beat cop took the envelope. Flow owns the cost and calls `Game.heat.bribe()`.
signal bribe_offered()
signal orbit_completed()
signal rollover_rolled(index: int, was_lit: bool)
signal storefront_collected(id: StringName, amount: BigMoney)
## The coils went hunting for a stuck ball. Diagnostic more than gameplay, but the sims
## assert on it and a rash of them in telemetry means new geometry has a trap in it.
signal ball_searched(at: Vector2)

const BALL_SCENE := preload("res://game/core/ball.tscn")
const FLIPPER_SCENE := preload("res://game/table/hardware/flipper.tscn")
const BUMPER_SCENE := preload("res://game/table/hardware/bumper.tscn")
const SLING_SCENE := preload("res://game/table/hardware/slingshot.tscn")

# ---------------------------------------------------------------- frame (M0, verbatim)
const PLAY_LEFT := 40.0
const PLAY_RIGHT := 933.0
const PLAY_BOTTOM := 1894.0
const ARCH_A := Vector2(40.0, 460.0)
const ARCH_B := Vector2(490.0, 60.0)
const ARCH_C := Vector2(1040.0, 460.0)
## Circumcentre of ARCH_A/B/C — tests/test_table_geometry.gd holds it to the formula.
const ARCH_CENTER := Vector2(540.0, 569.375)
const OUTER_THICK := 36.0
const GUIDE_THICK := 18.0

const DIVIDER_X := 943.0
const DIVIDER_THICK := 20.0
const DIVIDER_TOP := 430.0
const DIVIDER_BOTTOM := 1845.0
const LANE_FLOOR_Y := 1858.0
const LANE_LEFT := 953.0
const LANE_RIGHT := 1040.0
const GATE_TOP := 258.0
const GATE_BOTTOM := 418.0

# ---------------------------------------------------------------- lower third (sacred)
const FLIPPER_PIVOT_L := Vector2(293.0, 1700.0)
const FLIPPER_PIVOT_R := Vector2(687.0, 1700.0)
const OUTLANE_X := 150.0
const OUTLANE_TOP := 1440.0
const OUTLANE_BOTTOM := 1580.0
const INLANE_END := Vector2(296.0, 1668.0)
const SLING_CORNER := Vector2(256.0, 1494.0)
const SLING_TOP := Vector2(368.0, 1430.0)
const SLING_BOTTOM := Vector2(256.0, 1560.0)
const MIRROR_X := 490.0
const DRAIN_Y := 1880.0
const DRAIN_HEIGHT := 24.0

# ---------------------------------------------------------------- the numbers lane / orbit
## A 90 px channel down the left wall. The spinner lives in it (R1); the getaway loop (R3)
## extends it around the arch, which is why one guide serves both and either owner builds it.
const LANE_GUIDE_X := 157.0
const LANE_GUIDE_TOP := 486.0
const LANE_GUIDE_BOTTOM := 1180.0
const CHANNEL_WIDTH := 90.0
const ORBIT_ARC_RADIUS := 394.8
const ORBIT_ARC_FROM_DEG := -167.64
## Stops short of the apex on purpose: at the very top the arc's own surface is level enough
## for a ball to sit down on it, and a ball parked on the roof of the orbit ends the night.
const ORBIT_ARC_TO_DEG := -112.0
const SPINNER_AT := Vector2(103.0, 900.0)
const ORBIT_ENTRY_AT := Vector2(103.0, 1120.0)
const ORBIT_ENTRY_SIZE := Vector2(86.0, 56.0)
const ORBIT_EXIT_DEG := -120.0
const ORBIT_EXIT_RADIUS := 449.0

# ---------------------------------------------------------------- the top lanes
const ROLLOVER_POST_X: PackedFloat32Array = [290.0, 420.0, 550.0, 680.0]
const ROLLOVER_POST_TOP := 470.0
const ROLLOVER_POST_BOTTOM := 610.0
const ROLLOVER_POST_THICK := 16.0
const ROLLOVER_SENSOR_Y := 590.0

# ---------------------------------------------------------------- the alley & the corner
const BUMPER_AT: Array = [Vector2(490.0, 700.0), Vector2(370.0, 830.0), Vector2(610.0, 830.0)]
const WIRE_X := 845.0
const WIRE_Y: PackedFloat32Array = [620.0, 730.0, 840.0]
const TARGET_LENGTH := 76.0

# ---------------------------------------------------------------- the block
const STOREFRONT_AT: Array = [
	Vector2(368.0, 1120.0),      # Lucky's Laundromat
	Vector2(600.0, 1010.0),      # Nonna's Pizzeria
	Vector2(838.0, 1120.0),      # Fat Tony's Pawn
]
## Banks are raked off square so a ball coming down from above sheds sideways into a gap
## instead of parking on 148 px of flat drop-target roof.
const STOREFRONT_RAKE: PackedFloat32Array = [14.0, 14.0, -14.0]
const STOREFRONT_IDS: Array[StringName] = [
	&"storefront_laundromat", &"storefront_pizzeria", &"storefront_pawn",
]
const STOREFRONT_SIGNS: Array[StringName] = [&"LUCKY'S", &"NONNA'S", &"FAT TONY'S"]

# ---------------------------------------------------------------- extras
## The donut shop stands square to the field, not raked across it: a bar angled into the
## right-hand wall is a corner, and a soak found the ball asleep in it for forty seconds.
## Vertical faces have no roof to sit on.
const BRIBE_AT := Vector2(770.0, 470.0)
const BRIBE_FACE := Vector2(-1.0, 0.0)
const COP_AT: Array = [
	Vector2(320.0, 980.0), Vector2(760.0, 950.0),
	Vector2(400.0, 1290.0), Vector2(660.0, 1290.0),
]
## Steep enough that the ball outruns rubber friction (0.30) on the way down their backs.
const COP_RAKE: PackedFloat32Array = [22.0, -22.0, 22.0, -22.0]
const KICKBACK_AT := Vector2(95.0, 1520.0)
const KICKBACK_SIZE := Vector2(86.0, 56.0)
const MAGNET_AT := Vector2(490.0, 1810.0)

const PLUNGER_FIXED_POWER := 0.75

# ---------------------------------------------------------------- ball search
## Real machines hunt for a lost ball, and this one has to as well. The playfield grows new
## geometry at every rank, and top-down gravity gives a vertical target's rounded cap a
## perfect balance point: a seeded soak found the ball asleep on top of a payphone for
## seventy seconds with nothing to push it either way. Rather than chase every such point
## through the geometry forever, anything motionless above the flippers gets a coil pulse.
const BALL_SEARCH_DELAY := 5.0
const BALL_SEARCH_REPEAT := 2.5
const BALL_SEARCH_SPEED := 40.0
const BALL_SEARCH_IMPULSE := 950.0
## Below this line resting is legitimate — cradled on a bat, dawdling down an inlane, or
## sitting on live hardware that pops itself loose (see Bumper/Slingshot stall handling).
const BALL_SEARCH_FLOOR := 1560.0

# ---------------------------------------------------------------- state
## Flow reads this to know the table pays through `Game.earn_switch` itself and must not be
## double-scored from `Events.scored` (game/flow/night.gd `_needs_score_bridge`).
var pays_through_game: bool = true
## Bypass every unlock check — the debug table and the feel sims run with the lot switched on.
var debug_all_hardware: bool = false

var flipper_left: Flipper = null
var flipper_right: Flipper = null
var plunger: BandedPlunger = null
var ball: Ball = null
var auto_respawn: bool = true
var balls_served: int = 0

var spinner: Spinner = null
var wire_bank: TargetBank = null
var orbit: OrbitLane = null
var kickback: Kickback = null
var magnet: DrainMagnet = null
var bribe_target: StandupTarget = null
var storefronts: Array[Storefront] = []
var rollovers: Array[Rollover] = []
var cop_targets: Array[StandupTarget] = []
var raid_active: bool = false

var _walls: WallBuilder = null
var _gate: StaticBody2D = null
var _gate_closed: bool = true
var _from_lane: bool = false
var _respawn_in: float = -1.0
var _arch_radius: float = 0.0
var _bumpers: Array[Bumper] = []
var _slings: Array[Slingshot] = []
var _pieces: Array[Dictionary] = []          ## { ids: Array[StringName], node: Node }
var _forced: Dictionary = {}                 ## dev env hook: ids forced unlocked
var _lit_lane: int = -1
var _still_for: float = 0.0
var _search_rng := RandomNumberGenerator.new()


# ================================================================ TableSegment =====


func segment_id() -> StringName:
	return &"table_main"


func bounds() -> Rect2:
	return Rect2(Vector2(PLAY_LEFT, 0.0), Vector2(LANE_RIGHT - PLAY_LEFT, PLAY_BOTTOM))


func spawn_point() -> Vector2:
	return Vector2((LANE_LEFT + LANE_RIGHT) * 0.5,
			LANE_FLOOR_Y - OUTER_THICK * 0.5 - Feel.BALL_RADIUS - 4.0)


func lane_rect() -> Rect2:
	return Rect2(Vector2(LANE_LEFT - 6.0, 240.0), Vector2(LANE_RIGHT - LANE_LEFT + 12.0, 1620.0))


func socket(id: StringName) -> Vector2:
	match id:
		&"arch_top":
			return ARCH_CENTER - Vector2(0.0, _arch_radius)
		&"left_channel":
			return Vector2(LANE_GUIDE_X - CHANNEL_WIDTH * 0.5, LANE_GUIDE_TOP)
		&"midfield":
			return Vector2(MIRROR_X, 1010.0)
		&"drain":
			return Vector2(MIRROR_X, DRAIN_Y)
	return Vector2.ZERO


# ===================================================================== build =====


func _ready() -> void:
	_arch_radius = ARCH_CENTER.distance_to(ARCH_A)
	_search_rng.seed = 0x5EA12C4          # seeded: a sim rerun searches the same way
	_read_env_hook()
	_build_walls()
	_build_gate()
	_build_left_channel()
	_build_top_lanes()
	_build_bumpers()
	_build_slings()
	_build_wire()
	_build_storefronts()
	_build_extras()
	_build_flippers()
	_build_drain()
	_build_plunger()
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	refresh_hardware()
	queue_redraw()


## Dev affordance for screenshots and one-off experiments, never used by the game:
##   KINGPIN_TABLE_DEBUG=1                        every piece on
##   KINGPIN_TABLE_HARDWARE=rollovers,wire_bank   just these, on top of what Stats says
func _read_env_hook() -> void:
	if OS.get_environment("KINGPIN_TABLE_DEBUG") == "1":
		debug_all_hardware = true
	var forced := OS.get_environment("KINGPIN_TABLE_HARDWARE")
	for id in forced.split(",", false):
		_forced[StringName(id.strip_edges())] = true


func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = Feel.LAYER_WALLS
	body.collision_mask = 0
	body.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, Feel.WALL_BOUNCE)
	add_child(body)
	_walls = WallBuilder.new(body)

	var off := OUTER_THICK * 0.5
	var a0 := arch_angle(ARCH_A)
	var a1 := arch_angle(ARCH_C)
	var r_out := _arch_radius + off
	var arch_start := ARCH_CENTER + Vector2(cos(a0), sin(a0)) * r_out
	var arch_end := ARCH_CENTER + Vector2(cos(a1), sin(a1)) * r_out

	_walls.arc(ARCH_CENTER, r_out, a0, a1, 56, OUTER_THICK)
	_walls.bar(Vector2(PLAY_LEFT - off, PLAY_BOTTOM + off), arch_start, OUTER_THICK)
	_walls.bar(Vector2(LANE_RIGHT + off, PLAY_BOTTOM + off), arch_end, OUTER_THICK)
	_walls.bar(Vector2(PLAY_LEFT - off, PLAY_BOTTOM + off),
			Vector2(PLAY_RIGHT, PLAY_BOTTOM + off), OUTER_THICK)
	_walls.bar(Vector2(DIVIDER_X, LANE_FLOOR_Y),
			Vector2(LANE_RIGHT + off, LANE_FLOOR_Y), OUTER_THICK)
	_walls.bar(Vector2(DIVIDER_X, DIVIDER_TOP), Vector2(DIVIDER_X, DIVIDER_BOTTOM), DIVIDER_THICK)

	# The guard rails are an upgrade (docs/02 §2 R0: "no inlane guides"), so they are a
	# separate switchable body — the bare table really is bare down there.
	var guides := WallPiece.new()
	guides.name = "InlaneGuides"
	add_child(guides)
	for s in [1.0, -1.0]:
		guides.bar(_mx(OUTLANE_X, s, OUTLANE_TOP), _mx(OUTLANE_X, s, OUTLANE_BOTTOM), GUIDE_THICK)
		guides.bar(_mx(OUTLANE_X, s, OUTLANE_BOTTOM),
				_mx(INLANE_END.x, s, INLANE_END.y), GUIDE_THICK)
	_register([&"inlane_guides"], guides)


func _build_gate() -> void:
	_gate = StaticBody2D.new()
	_gate.name = "OneWayGate"
	_gate.collision_layer = Feel.LAYER_WALLS
	_gate.collision_mask = 0
	_gate.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.1)
	add_child(_gate)
	var b := WallBuilder.new(_gate)
	b.bar(Vector2(DIVIDER_X, GATE_TOP), Vector2(DIVIDER_X, GATE_BOTTOM), 12.0)


func _build_left_channel() -> void:
	var guide := WallPiece.new()
	guide.name = "NumbersLaneGuide"
	add_child(guide)
	guide.bar(Vector2(LANE_GUIDE_X, LANE_GUIDE_TOP), Vector2(LANE_GUIDE_X, LANE_GUIDE_BOTTOM),
			GUIDE_THICK)
	_register([&"spinner_numbers", &"orbit_left"], guide)

	var arc := WallPiece.new()
	arc.name = "GetawayArc"
	add_child(arc)
	arc.arc(ARCH_CENTER, ORBIT_ARC_RADIUS, deg_to_rad(ORBIT_ARC_FROM_DEG),
			deg_to_rad(ORBIT_ARC_TO_DEG), 40, GUIDE_THICK)
	_register([&"orbit_left"], arc)

	spinner = Spinner.new()
	spinner.name = "Spinner"
	spinner.configure(&"spinner_numbers", SPINNER_AT, CHANNEL_WIDTH)
	add_child(spinner)
	_register([&"spinner_numbers"], spinner)

	orbit = OrbitLane.new()
	orbit.name = "OrbitLeft"
	add_child(orbit)
	orbit.configure(&"orbit_left", ORBIT_ENTRY_AT, ORBIT_ENTRY_SIZE,
			_polar(ORBIT_EXIT_RADIUS, ORBIT_EXIT_DEG), 34.0)
	orbit.orbit_completed.connect(func() -> void: orbit_completed.emit())
	_register([&"orbit_left"], orbit)


func _build_top_lanes() -> void:
	var posts := WallPiece.new()
	posts.name = "TopLanePosts"
	add_child(posts)
	for x in ROLLOVER_POST_X:
		posts.bar(Vector2(x, ROLLOVER_POST_TOP), Vector2(x, ROLLOVER_POST_BOTTOM),
				ROLLOVER_POST_THICK)
	_register([&"rollovers"], posts)

	for i in range(ROLLOVER_POST_X.size() - 1):
		var r := Rollover.new()
		r.name = "Rollover%d" % (i + 1)
		var cx := (ROLLOVER_POST_X[i] + ROLLOVER_POST_X[i + 1]) * 0.5
		r.configure(StringName("rollover_%d" % (i + 1)), i, Vector2(cx, ROLLOVER_SENSOR_Y))
		add_child(r)
		r.rolled.connect(_on_rollover)
		rollovers.append(r)
		_register([&"rollovers"], r)


func _build_bumpers() -> void:
	for i in range(BUMPER_AT.size()):
		var b: Bumper = BUMPER_SCENE.instantiate()
		b.id = StringName("bumper_%d" % (i + 1))
		b.group = TableScore.GROUP_BUMPERS
		b.value = int(TableScore.BUMPER)
		b.position = BUMPER_AT[i]
		b.name = "Bumper%d" % (i + 1)
		add_child(b)
		_bumpers.append(b)
		if i > 0:                       # the first dented can is the table you are given
			_register([b.id], b)


func _build_slings() -> void:
	for s in [1.0, -1.0]:
		var sl: Slingshot = SLING_SCENE.instantiate()
		var id := &"sling_l" if s > 0.0 else &"sling_r"
		sl.configure(id,
			_mx(SLING_CORNER.x, s, SLING_CORNER.y),
			_mx(SLING_TOP.x, s, SLING_TOP.y),
			_mx(SLING_BOTTOM.x, s, SLING_BOTTOM.y))
		sl.group = TableScore.GROUP_SLINGS
		sl.value = int(TableScore.SLING)
		sl.name = "SlingL" if s > 0.0 else "SlingR"
		add_child(sl)
		_slings.append(sl)
		_register([&"slingshots"], sl)


func _build_wire() -> void:
	wire_bank = TargetBank.new()
	wire_bank.name = "WireBank"
	wire_bank.id = &"wire_bank"
	add_child(wire_bank)
	for i in range(WIRE_Y.size()):
		var t := StandupTarget.new()
		t.name = "Payphone%d" % (i + 1)
		t.configure(StringName("wire_%d" % (i + 1)), Vector2(WIRE_X, WIRE_Y[i]),
				Vector2.LEFT, TARGET_LENGTH)
		wire_bank.add_target(t)
	_register([&"wire_bank"], wire_bank)


func _build_storefronts() -> void:
	for i in range(STOREFRONT_AT.size()):
		var s := Storefront.new()
		s.name = "Storefront%d" % (i + 1)
		s.configure(STOREFRONT_IDS[i], STOREFRONT_AT[i], Vector2.DOWN, STOREFRONT_RAKE[i],
				STOREFRONT_SIGNS[i])
		add_child(s)
		s.collected.connect(_on_storefront_collected)
		s.washed.connect(_on_laundromat_wash)
		storefronts.append(s)
		# Lucky's is two upgrades in one shell: the wash loop (R2) and the bank (R3).
		if STOREFRONT_IDS[i] == &"storefront_laundromat":
			_register([&"storefront_laundromat", &"laundromat_loop"], s)
		else:
			_register([STOREFRONT_IDS[i]], s)


func _build_extras() -> void:
	bribe_target = StandupTarget.new()
	bribe_target.name = "BribeTarget"
	bribe_target.configure(&"bribe_target", BRIBE_AT, BRIBE_FACE, 80.0)
	add_child(bribe_target)
	bribe_target.struck.connect(_on_bribe_struck)
	_register([&"bribe_target"], bribe_target)

	for i in range(COP_AT.size()):
		var c := StandupTarget.new()
		c.name = "Cop%d" % (i + 1)
		c.configure(StringName("cop_%d" % (i + 1)), COP_AT[i], Vector2.DOWN, TARGET_LENGTH)
		c.rotation += deg_to_rad(COP_RAKE[i])
		add_child(c)
		c.struck.connect(_on_cop_struck)
		cop_targets.append(c)
		c.set_hardware_active(false)          # raid-only: never part of the owned set

	kickback = Kickback.new()
	kickback.name = "KickbackLeft"
	kickback.configure(&"kickback_left", KICKBACK_AT, KICKBACK_SIZE, Vector2(0.20, -1.0))
	add_child(kickback)
	_register([&"kickback_left"], kickback)

	magnet = DrainMagnet.new()
	magnet.name = "CaptainsMagnet"
	magnet.position = MAGNET_AT
	magnet.drain_point = Vector2(MIRROR_X, DRAIN_Y + 40.0)
	add_child(magnet)


func _build_flippers() -> void:
	flipper_left = FLIPPER_SCENE.instantiate()
	flipper_left.side = &"left"
	flipper_left.name = "FlipperLeft"
	flipper_left.position = FLIPPER_PIVOT_L
	add_child(flipper_left)

	flipper_right = FLIPPER_SCENE.instantiate()
	flipper_right.side = &"right"
	flipper_right.name = "FlipperRight"
	flipper_right.position = FLIPPER_PIVOT_R
	add_child(flipper_right)


func _build_drain() -> void:
	var area := Area2D.new()
	area.name = "Drain"
	area.collision_layer = Feel.LAYER_ZONES
	area.collision_mask = Feel.LAYER_BALL
	area.monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PLAY_RIGHT - PLAY_LEFT, DRAIN_HEIGHT)
	cs.shape = rect
	cs.position = Vector2((PLAY_LEFT + PLAY_RIGHT) * 0.5, DRAIN_Y + DRAIN_HEIGHT * 0.5)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_drain_entered)


func _build_plunger() -> void:
	plunger = BandedPlunger.new()
	plunger.name = "Plunger"
	plunger.lane_rect = lane_rect()
	plunger.fixed_power = PLUNGER_FIXED_POWER
	add_child(plunger)


# ================================================================= unlocking =====


func _register(ids: Array, node: Node) -> void:
	var typed: Array[StringName] = []
	for id: Variant in ids:
		typed.append(StringName(id))
	_pieces.append({"ids": typed, "node": node})


## Is this hardware id paid for? `debug_all_hardware` is the M0/feel-sim bypass.
func hardware_unlocked(id: StringName) -> bool:
	if debug_all_hardware:
		return true
	if _forced.has(id):
		return true
	if Game == null or Game.stats == null:
		return false
	# The donut shop is only worth standing there if the envelope can actually be passed
	# (specs/m1-hook.md Lane 3): Stats answers that as a flag, not as hardware.
	if id == &"bribe_target":
		return Game.stats.hardware_unlocked(id) or Game.stats.bribe_unlocked()
	return Game.stats.hardware_unlocked(id)


## Is every piece registered under this id on the playfield right now? "Every", because a
## couple of pieces answer to two owners (the left channel guide serves the numbers lane and
## the getaway loop), and owning one of those does not put the other one on the table.
func hardware_present(id: StringName) -> bool:
	var found := false
	for piece: Dictionary in _pieces:
		var ids: Array[StringName] = piece["ids"]
		if not ids.has(id):
			continue
		found = true
		if not (piece["node"] as Node2D).visible:
			return false
	return found


## Every switchable piece, as `{ ids: Array[StringName], node: Node }` — the growth sim walks
## this to prove that "hidden" and "no collision" never come apart.
func hardware_pieces() -> Array[Dictionary]:
	return _pieces.duplicate()


func hardware_node(id: StringName) -> Node:
	for piece: Dictionary in _pieces:
		var ids: Array[StringName] = piece["ids"]
		if ids.has(id):
			return piece["node"]
	return null


func hardware_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for piece: Dictionary in _pieces:
		for id: StringName in piece["ids"]:
			if not out.has(id):
				out.append(id)
	return out


## Re-read the owned set and show/hide everything accordingly. Cheap enough to call on any
## purchase, and idempotent, which is what makes save-loading a non-event.
func refresh_hardware() -> void:
	for piece: Dictionary in _pieces:
		var active := false
		for id: StringName in piece["ids"]:
			if hardware_unlocked(id):
				active = true
				break
		Dormant.apply(piece["node"], active)
	for s in storefronts:
		s.bank_enabled = hardware_unlocked(s.id)
		s.wash_enabled = s.id == &"storefront_laundromat" and hardware_unlocked(&"laundromat_loop")
		s.apply_build()
	var power := 1.0
	if Game != null and Game.stats != null:
		power = Game.stats.flipper_power()
	for f: Flipper in [flipper_left, flipper_right]:
		if f != null:
			f.power_scale = power
	if plunger != null:
		plunger.bands_enabled = debug_all_hardware \
				or (Game != null and Game.stats != null and Game.stats.flag(&"plunger_bands"))
	queue_redraw()


func _on_upgrade_purchased(_id: String, _level: int) -> void:
	refresh_hardware()


# ============================================================== flow surface =====


## Light one of the three top lanes for the skill shot; -1 (or out of range) lights none.
func set_lit_rollover(index: int) -> void:
	_lit_lane = index
	for i in range(rollovers.size()):
		rollovers[i].set_lit(i == index)


func lit_rollover() -> int:
	return _lit_lane


func rollover_count() -> int:
	return rollovers.size()


## RAID (specs/m1-hook.md Lane 1): four cops come out around the lanes and the Captain's
## magnet starts telegraphing pulls at the drain. Flow owns the clock and the pull itself
## (RaidMode); this owns the hardware and the warning.
func set_raid_active(active: bool) -> void:
	if raid_active == active:
		return
	raid_active = active
	for c in cop_targets:
		c.set_hardware_active(active)
		c.set_marked(false)
	magnet.set_active(active)
	queue_redraw()


## Fire the Captain's magnet now (flow drives the schedule; see DrainMagnet.self_driven).
func magnet_pull() -> void:
	magnet.pull(ball)


## Is any storefront ready to be worked? The flow lane gates the passive wash on it.
func storefront_armed() -> bool:
	var any := false
	for s in storefronts:
		if not s.visible:
			continue
		any = true
		if s.state_name() != &"cooldown":
			return true
	return not any


func spinner_spins() -> int:
	return spinner.spins_total if spinner != null else 0


func _on_rollover(index: int, was_lit: bool) -> void:
	rollover_rolled.emit(index, was_lit)


func _on_storefront_collected(id: StringName, amount: BigMoney) -> void:
	storefront_collected.emit(id, amount)


func _on_laundromat_wash(_id: StringName) -> void:
	laundromat_pass.emit()


func _on_bribe_struck(target: StandupTarget, ball_hit: Ball) -> void:
	TableScore.hit(target.id, ball_hit)
	bribe_offered.emit()


func _on_cop_struck(target: StandupTarget, ball_hit: Ball) -> void:
	if target.marked:
		return
	target.set_marked(true)
	TableScore.earn(TableScore.GROUP_BUMPERS, TableScore.BUMPER * 5.0, target.id, ball_hit)


# ============================================================== ball service =====


func spawn_ball() -> Ball:
	despawn_ball()
	_respawn_in = -1.0
	var b: Ball = BALL_SCENE.instantiate()
	b.name = "Ball"
	b.position = spawn_point()
	add_child(b)
	ball = b
	balls_served += 1
	_from_lane = true
	_bind_ball()
	AudioDirector.play(&"ball_spawn")
	Events.ball_spawned.emit(b)
	ball_spawned.emit(b)
	return b


func despawn_ball() -> void:
	_respawn_in = -1.0
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	ball = null
	_bind_ball()


func _bind_ball() -> void:
	if flipper_left != null:
		flipper_left.set_ball(ball)
	if flipper_right != null:
		flipper_right.set_ball(ball)
	if plunger != null:
		plunger.set_ball(ball)
	if magnet != null:
		magnet.set_ball(ball)


func _on_drain_entered(body: Node2D) -> void:
	if not (body is Ball) or body != ball:
		return
	var lost: Ball = body
	ball = null
	_bind_ball()
	lost.queue_free()
	AudioDirector.play(&"drain")
	Events.ball_drained.emit(lost)
	ball_lost.emit(lost)
	if auto_respawn:
		_respawn_in = Feel.RESPAWN_DELAY


func _physics_process(delta: float) -> void:
	if _respawn_in > 0.0:
		if not auto_respawn:
			_respawn_in = -1.0
		else:
			_respawn_in -= delta
			if _respawn_in <= 0.0:
				_respawn_in = -1.0
				spawn_ball()
	_update_gate()
	_ball_search(delta)


## Pulse the coils under a ball that has stopped somewhere it has no business stopping.
func _ball_search(delta: float) -> void:
	if ball == null or not is_instance_valid(ball):
		_still_for = 0.0
		return
	var p := ball.global_position
	if ball.speed() > BALL_SEARCH_SPEED or p.y > BALL_SEARCH_FLOOR or lane_rect().has_point(p):
		_still_for = 0.0
		return
	_still_for += delta
	if _still_for < BALL_SEARCH_DELAY:
		return
	_still_for = BALL_SEARCH_DELAY - BALL_SEARCH_REPEAT
	var dir := Vector2(_search_rng.randf_range(-0.55, 0.55), -1.0).normalized()
	ball.kick(dir * BALL_SEARCH_IMPULSE)
	AudioDirector.play(&"kickback")
	ball_searched.emit(p)


## One-way gate: the arch dumps the ball leftward into the playfield and it must never get
## back into the shooter lane. Latched on where the ball came from, and only ever toggled
## while the ball is clear of the blade so the flap can't materialise inside it.
func _update_gate() -> void:
	if _gate == null:
		return
	var want_closed := true
	if ball != null and is_instance_valid(ball):
		var p := ball.global_position
		if p.x > LANE_RIGHT - 55.0:
			_from_lane = true
		elif p.x < DIVIDER_X - 53.0:
			_from_lane = false
		var in_window := p.x > DIVIDER_X - 63.0 and p.y > GATE_TOP - 52.0 and p.y < GATE_BOTTOM + 62.0
		want_closed = not (_from_lane and in_window)
		if want_closed and absf(p.x - DIVIDER_X) < 50.0:
			want_closed = _gate_closed        # hold: never close on top of the ball
	if want_closed == _gate_closed:
		return
	_gate_closed = want_closed
	_gate.collision_layer = Feel.LAYER_WALLS if want_closed else 0
	queue_redraw()
	if not want_closed:
		AudioDirector.play(&"wall_tap")


# =================================================================== geometry =====


func _mx(x: float, s: float, y: float) -> Vector2:
	return Vector2(x if s > 0.0 else MIRROR_X * 2.0 - x, y)


func _polar(radius: float, degrees: float) -> Vector2:
	var a := deg_to_rad(degrees)
	return ARCH_CENTER + Vector2(cos(a), sin(a)) * radius


func arch_angle(p: Vector2) -> float:
	return (p - ARCH_CENTER).angle()


static func circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.0001:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2(
		(a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
	)


# ==================================================================== drawing =====


func _draw() -> void:
	var a0 := arch_angle(ARCH_A)
	var a1 := arch_angle(ARCH_C)
	var felt := PackedVector2Array()
	felt.append(Vector2(PLAY_LEFT, PLAY_BOTTOM))
	felt.append(ARCH_A)
	for i in range(41):
		var ang := lerpf(a0, a1, float(i) / 40.0)
		felt.append(ARCH_CENTER + Vector2(cos(ang), sin(ang)) * _arch_radius)
	felt.append(Vector2(LANE_RIGHT, PLAY_BOTTOM))
	draw_colored_polygon(felt, Feel.COL_FELT)

	if raid_active:
		draw_colored_polygon(felt, Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g,
				Feel.COL_DIRTY.b, 0.12))

	draw_rect(Rect2(Vector2(LANE_LEFT, DIVIDER_TOP), Vector2(LANE_RIGHT - LANE_LEFT,
			LANE_FLOOR_Y - DIVIDER_TOP)), Feel.COL_FELT.darkened(0.25))
	for i in range(1, 4):
		var y := LANE_FLOOR_Y - float(i) * 380.0
		draw_line(Vector2(LANE_LEFT + 6.0, y), Vector2(LANE_RIGHT - 6.0, y),
				Feel.COL_BRASS.darkened(0.5), 2.0)

	if _walls != null:
		_walls.draw_into(self, Feel.COL_INK.lightened(0.12), Feel.COL_INK)

	var gate_col := Feel.COL_BRASS if _gate_closed else Feel.COL_BRASS.darkened(0.6)
	draw_line(Vector2(DIVIDER_X, GATE_TOP), Vector2(DIVIDER_X, GATE_BOTTOM), gate_col, 12.0)

	# the drain is a storm grate lit from below, not a hole (docs/02 §4)
	draw_line(Vector2(PLAY_LEFT, DRAIN_Y), Vector2(PLAY_RIGHT, DRAIN_Y),
			Feel.COL_DIRTY.darkened(0.35), 3.0)
	for i in range(9):
		var gx := lerpf(PLAY_LEFT + 40.0, PLAY_RIGHT - 40.0, float(i) / 8.0)
		draw_line(Vector2(gx, DRAIN_Y + 3.0), Vector2(gx, PLAY_BOTTOM - 4.0),
				Feel.COL_DIRTY.darkened(0.55), 3.0)
