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
## M2 — THE CLUB (docs/02 §2 R4). The deck's hardware reports through the table so the flow
## lane has one thing to talk to; see game/table/segments/club_deck.gd for what each means.
signal staircase_climbed(speed: float)
signal roulette_landed(pocket: int, house: bool)
signal reels_state(cleared_columns: Array)
signal high_roller_held(steps: int)
signal backroom_entered()
## The ball left the deck via the return lane and is back on the main field — flow closes
## a "deck visit" (slots Jackpot window) on this instead of polling ball height.
signal deck_returned()
## The coils went hunting for a stuck ball. Diagnostic more than gameplay, but the sims
## assert on it and a rash of them in telemetry means new geometry has a trap in it.
signal ball_searched(at: Vector2)
## M2 — THE COMMISSION (specs/m2-content.md §5). Boss hardware is never bought: like the
## raid's cop targets it is built dormant and only a live fight stands it up. `kind` is
## &"sedan" &"truck" &"goon" or &"door"; the flow lane's BossFight owns what each one means.
signal boss_hit(kind: StringName, hits_left: int, speed: float)
signal boss_shrugged(kind: StringName, speed: float)
signal boss_down(kind: StringName)
## M3 — THE DOCKS (docs/02 §2 R5). See game/table/segments/docks.gd for the shot layout;
## the smuggling runs that read these are FLOW-3's.
signal docks_entered()
signal container_stack_cleared(stack: int)
signal containers_state(cleared_stacks: Array)
signal crane_telegraph()
signal crane_pulled()
## The cargo ramp put a ball back on the main field. Same role as `deck_returned` upstairs.
signal cargo_shipped(speed: float)
## M3 — THE PENTHOUSE (docs/02 §2 R6). Geometry, switches and signals only in TABLE-3.
signal chair_taken(index: int)
signal chairs_completed()
signal sitdown_entered()
signal penthouse_entered(speed: float)
signal penthouse_returned()

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

# ---------------------------------------------------------------- the Truck Route (M3)
## The right-hand loop (docs/02 §2 R5). It cannot be a mirror of the getaway: the shooter
## lane's divider owns the right-hand wall from y=430 down, so there is no channel to run
## and no arc to build. What there IS is the corridor outside the payphones — the same lane
## the Club's staircase hangs off — and the arch above it, so the Truck Route is the *upper*
## half of an orbit: enter low in the corridor, still be in it at the top of the arch.
##
## Deliberately gates only, no new geometry. A guide down that corridor would narrow the
## plunge path, and the plunge is a tuned M0 number.
const ORBIT_R_ENTRY_AT := Vector2(893.0, 1052.0)
const ORBIT_R_ENTRY_SIZE := Vector2(74.0, 56.0)
const ORBIT_R_EXIT_DEG := -60.0

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
## The lower-left cop stood at x=400 until M3 put the Docks yard there; it now stands just
## outside the yard's wall, close enough that nothing can wedge between the two.
const COP_AT: Array = [
	Vector2(320.0, 980.0), Vector2(760.0, 950.0),
	Vector2(470.0, 1296.0), Vector2(660.0, 1290.0),
]
## Steep enough that the ball outruns rubber friction (0.30) on the way down their backs.
const COP_RAKE: PackedFloat32Array = [22.0, -22.0, 22.0, -22.0]
const KICKBACK_AT := Vector2(95.0, 1520.0)
const KICKBACK_SIZE := Vector2(86.0, 56.0)
const MAGNET_AT := Vector2(490.0, 1810.0)

# ---------------------------------------------------------------- the Commission
## Sammy's sedan crosses the waist on a rail between the bumper nest and the block: high
## enough that a bumper cannot shield it, low enough to be reachable off either bat.
const SEDAN_RAIL_Y := 920.0
const SEDAN_RAIL_FROM_X := 270.0
const SEDAN_RAIL_TO_X := 700.0
const SEDAN_PARK := Vector2(490.0, 940.0)
const SEDAN_LENGTH := 150.0
const SEDAN_THICK := 46.0
## Three goons standing in front of the cans. Raked like the cops so nothing sits on them.
const GOON_AT: Array = [Vector2(300.0, 760.0), Vector2(680.0, 760.0), Vector2(490.0, 930.0)]
const GOON_RAKE: PackedFloat32Array = [18.0, -18.0, -18.0]
## The meat truck rides the getaway channel itself: it is 56 px across in a 108 px lane, so
## while it is up there the orbit is the Butcher's, not yours.
const TRUCK_RADIUS := 457.8
const TRUCK_FROM_DEG := -166.0
const TRUCK_TO_DEG := -114.0
const TRUCK_ARC_STEPS := 14
const TRUCK_PARK := Vector2(490.0, 1180.0)
const TRUCK_LENGTH := 130.0
const TRUCK_THICK := 56.0
## The truck's back door: two rows of three, the back row standing behind the front row's
## gaps so every panel is reachable without the front row having to drop.
const DOOR_FRONT_Y := 1330.0
const DOOR_BACK_Y := 1232.0
const DOOR_FRONT_X: PackedFloat32Array = [330.0, 490.0, 650.0]
const DOOR_BACK_X: PackedFloat32Array = [410.0, 570.0, 730.0]
const DOOR_RAKE := 12.0
## The Butcher's cold-storage readout, drawn inside the arch where nothing else lives.
const BOSS_METER_AT := Vector2(540.0, 300.0)
const BOSS_METER_SIZE := Vector2(420.0, 30.0)

## The rubber band is meant to be reliable-but-uncontrollable, not broken: below ~0.90 the
## ball never clears the shooter lane on this geometry, so a bare alley would earn nothing
## at all. One power, and it always feeds the playfield.
const PLUNGER_FIXED_POWER := 0.92

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
var orbit_right: OrbitLane = null
var kickback: Kickback = null
var magnet: DrainMagnet = null
var bribe_target: StandupTarget = null
var storefronts: Array[Storefront] = []
var rollovers: Array[Rollover] = []
var cop_targets: Array[StandupTarget] = []
var raid_active: bool = false
## THE COMMISSION. Built with everything else, dormant until a fight stands it up.
var boss_sedan: BossTarget = null
var boss_truck: BossTarget = null
var boss_goons: Array[StandupTarget] = []
var boss_door: TargetBank = null
var boss_active: bool = false
## The upper deck. Always built, dormant until `club_deck` is owned — same rule as every
## other piece of furniture on this table.
var club: ClubDeck = null
## M3's two new rooms, same rule again: built with the table, dormant until they are bought.
var docks: Docks = null
var penthouse: Penthouse = null
## The crew with the hammers (docs/02 §0). Cosmetic; see hardware/build_in.gd.
var construction: BuildIn = null

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
var _boss_meter_text: String = ""
var _boss_meter_fill: float = 0.0
var _built_once: Dictionary = {}             ## node -> true: already stood up at least once
var _first_refresh: bool = true              ## boot: the table loads its save, it is not built


# ================================================================ TableSegment =====


func segment_id() -> StringName:
	return &"table_main"


## Grows with the empire: once the Club is built the table is ~2.8 screens tall, and the
## camera reads its clamp straight off this (game/core/camera_rig.gd).
func bounds() -> Rect2:
	var r := Rect2(Vector2(PLAY_LEFT, 0.0), Vector2(LANE_RIGHT - PLAY_LEFT, PLAY_BOTTOM))
	if club != null and club.is_hardware_active():
		r = r.merge(club.bounds())
	if penthouse != null and penthouse.is_hardware_active():
		r = r.merge(penthouse.bounds())
	if docks != null and docks.is_hardware_active():
		r = r.merge(docks.bounds())
	return r


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
		&"club_deck":
			return Vector2(ClubDeck.DECK_LEFT, ClubDeck.DECK_BOTTOM)
		&"stair_mouth":
			return ClubDeck.STAIR_MOUTH
		# Left half of the sky. M2 kept it empty for these two; M3 filled it.
		&"sky_left":
			return Vector2(PLAY_LEFT, ClubDeck.DECK_BOTTOM)
		&"docks":
			return Docks.QUAY_FROM
		&"dock_mouth":
			return Vector2(Docks.LEFT_TOP_FROM.x, (Docks.MOUTH_TOP + Docks.MOUTH_BOTTOM) * 0.5)
		&"penthouse":
			return Penthouse.FLOOR_APEX
		&"penthouse_mouth":
			return Penthouse.STAIR_MOUTH
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
	_build_bosses()
	_build_club()
	_build_docks()
	_build_penthouse()
	_build_drain()
	_build_plunger()
	_build_construction()
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

	# THE TRUCK ROUTE (M3). Two gates on the corridor outside the payphones and the top of
	# the arch — no new walls, see ORBIT_R_ENTRY_AT.
	orbit_right = OrbitLane.new()
	orbit_right.name = "OrbitRight"
	add_child(orbit_right)
	orbit_right.configure(&"orbit_right", ORBIT_R_ENTRY_AT, ORBIT_R_ENTRY_SIZE,
			_polar(ORBIT_EXIT_RADIUS, ORBIT_R_EXIT_DEG), 34.0)
	orbit_right.orbit_completed.connect(func() -> void: orbit_completed.emit())
	_register([&"orbit_right"], orbit_right)


## THE COMMISSION (specs/m2-content.md §5). Sammy's sedan and his three goons, the Butcher's
## refrigerated truck and its back door. None of it is registered as a piece of furniture:
## boss hardware is not for sale, it stands dormant until a fight asks for it, exactly like
## the raid's cops.
func _build_bosses() -> void:
	boss_sedan = BossTarget.new()
	boss_sedan.name = "BossSedan"
	boss_sedan.kind = &"sedan"
	boss_sedan.color = Feel.COL_INK.lightened(0.16)
	add_child(boss_sedan)
	boss_sedan.size_to(SEDAN_LENGTH, SEDAN_THICK)
	boss_sedan.set_path(PackedVector2Array([
		Vector2(SEDAN_RAIL_FROM_X, SEDAN_RAIL_Y), Vector2(SEDAN_RAIL_TO_X, SEDAN_RAIL_Y),
	]))
	_wire_boss_target(boss_sedan)

	boss_truck = BossTarget.new()
	boss_truck.name = "BossTruck"
	boss_truck.kind = &"truck"
	boss_truck.color = Feel.COL_NEWSPRINT.darkened(0.18)
	add_child(boss_truck)
	boss_truck.size_to(TRUCK_LENGTH, TRUCK_THICK)
	boss_truck.set_path(_truck_path())
	_wire_boss_target(boss_truck)

	for i in range(GOON_AT.size()):
		var g := StandupTarget.new()
		g.name = "Goon%d" % (i + 1)
		g.configure(StringName("boss_goon_%d" % (i + 1)), GOON_AT[i], Vector2.DOWN, TARGET_LENGTH)
		g.rotation += deg_to_rad(GOON_RAKE[i])
		add_child(g)
		g.struck.connect(_on_goon_struck)
		boss_goons.append(g)
		g.set_hardware_active(false)

	boss_door = TargetBank.new()
	boss_door.name = "BossDoor"
	boss_door.id = &"boss_door"
	boss_door.reset_seconds = 1.2
	add_child(boss_door)
	for row in range(2):
		var ys := DOOR_FRONT_Y if row == 0 else DOOR_BACK_Y
		var xs := DOOR_FRONT_X if row == 0 else DOOR_BACK_X
		for i in range(xs.size()):
			var t := StandupTarget.new()
			t.name = "Door%d%d" % [row + 1, i + 1]
			t.configure(StringName("boss_door_%d%d" % [row + 1, i + 1]),
					Vector2(xs[i], ys), Vector2.DOWN, TARGET_LENGTH)
			t.rotation += deg_to_rad(DOOR_RAKE if i % 2 == 0 else -DOOR_RAKE)
			boss_door.add_target(t)
	boss_door.group = &"other"
	boss_door.target_value = 0.0
	boss_door.complete_value = 0.0
	boss_door.bank_completed.connect(func() -> void: boss_down.emit(&"door"))
	boss_door.target_struck.connect(func(_index: int) -> void:
		boss_hit.emit(&"door", boss_door.targets().size() - boss_door.marked_count(), 0.0))
	boss_door.set_hardware_active(false)


func _wire_boss_target(t: BossTarget) -> void:
	t.set_hardware_active(false)
	t.struck.connect(func(kind: StringName, left: int, speed: float) -> void:
		boss_hit.emit(kind, left, speed))
	t.shrugged.connect(func(kind: StringName, speed: float) -> void:
		boss_shrugged.emit(kind, speed))
	t.broken.connect(func(kind: StringName) -> void: boss_down.emit(kind))


## The truck's beat: the getaway channel itself, sampled so the body lies along the arc.
func _truck_path() -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(TRUCK_ARC_STEPS + 1):
		var deg := lerpf(TRUCK_FROM_DEG, TRUCK_TO_DEG, float(i) / float(TRUCK_ARC_STEPS))
		pts.append(_polar(TRUCK_RADIUS, deg))
	return pts


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


## THE CLUB (specs/m2-empire.md TABLE-2). The deck is one node in negative-y space; it owns
## its own geometry and its own toys, and everything it does that the session cares about is
## re-emitted here so `game/flow` has a single table surface to bind to.
func _build_club() -> void:
	club = ClubDeck.new()
	club.name = "ClubDeck"
	add_child(club)
	club.bind_flippers(flipper_left, flipper_right)
	club.staircase_climbed.connect(func(s: float) -> void: staircase_climbed.emit(s))
	club.roulette_landed.connect(func(p: int, h: bool) -> void: roulette_landed.emit(p, h))
	club.reels_state.connect(func(cols: Array) -> void: reels_state.emit(cols))
	club.high_roller_held.connect(func(steps: int) -> void: high_roller_held.emit(steps))
	club.backroom_entered.connect(func() -> void: backroom_entered.emit())
	club.returned_home.connect(func(_at: Vector2) -> void: deck_returned.emit())
	_register([ClubDeck.ID_DECK], club)
	for piece: Dictionary in club.pieces():
		_register(piece["ids"], piece["node"], ClubDeck.ID_DECK)


## THE DOCKS (specs/m3-fall-rise.md TABLE-3). Same division as the Club: the yard owns its
## own geometry and toys, the table re-emits what the session cares about — and the pier is
## routed straight into the drain path, because a fall there costs a ball.
func _build_docks() -> void:
	docks = Docks.new()
	docks.name = "Docks"
	add_child(docks)
	docks.docks_entered.connect(func() -> void: docks_entered.emit())
	docks.stack_cleared.connect(func(s: int) -> void: container_stack_cleared.emit(s))
	docks.containers_state.connect(func(c: Array) -> void: containers_state.emit(c))
	docks.crane_telegraph.connect(func() -> void: crane_telegraph.emit())
	docks.crane_pulled.connect(func() -> void: crane_pulled.emit())
	docks.cargo_shipped.connect(func(s: float) -> void: cargo_shipped.emit(s))
	docks.pier_fall.connect(func(b: Ball) -> void: _lose_ball(b, &"pier_splash"))
	_register([Docks.ID_DOCKS], docks)
	for piece: Dictionary in docks.pieces():
		_register(piece["ids"], piece["node"], Docks.ID_DOCKS)


## THE PENTHOUSE (specs/m3-fall-rise.md TABLE-3). Registered under the Club, because the only
## way into the room is a wireform off the deck's own orbit — see `hardware_unlocked`.
func _build_penthouse() -> void:
	penthouse = Penthouse.new()
	penthouse.name = "Penthouse"
	add_child(penthouse)
	penthouse.chair_taken.connect(func(i: int) -> void: chair_taken.emit(i))
	penthouse.chairs_completed.connect(func() -> void: chairs_completed.emit())
	penthouse.sitdown_entered.connect(func() -> void: sitdown_entered.emit())
	penthouse.penthouse_entered.connect(func(s: float) -> void: penthouse_entered.emit(s))
	penthouse.penthouse_returned.connect(func() -> void: penthouse_returned.emit())
	_register([Penthouse.ID_PENTHOUSE], penthouse, ClubDeck.ID_DECK)
	for piece: Dictionary in penthouse.pieces():
		_register(piece["ids"], piece["node"], Penthouse.ID_PENTHOUSE)


## The crew with the hammers. Added last so it draws over everything it is building, and
## switched off entirely under a headless display so no sim's timing rides on an animation.
func _build_construction() -> void:
	construction = BuildIn.new()
	construction.name = "Construction"
	construction.enabled = DisplayServer.get_name() != "headless" \
			and OS.get_environment("KINGPIN_NO_BUILD_ANIM") != "1"
	add_child(construction)


## The storm grate. The Docks' pier is the same event by a different door: it reports through
## `Docks.pier_fall` into the same `_lose_ball`, so falling off the pier costs a ball in
## exactly the way draining does — one ball_lost, one Events.ball_drained, one respawn.
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
	area.body_entered.connect(func(body: Node2D) -> void: _on_drain_entered(body))


func _build_plunger() -> void:
	plunger = BandedPlunger.new()
	plunger.name = "Plunger"
	plunger.lane_rect = lane_rect()
	plunger.fixed_power = PLUNGER_FIXED_POWER
	add_child(plunger)


# ================================================================= unlocking =====


## `needs` is an id that must *also* be owned for the piece to be on the table: the Club's
## toys are bought one at a time but none of them exists without the deck under them.
func _register(ids: Array, node: Node, needs: StringName = &"") -> void:
	var typed: Array[StringName] = []
	for id: Variant in ids:
		typed.append(StringName(id))
	_pieces.append({"ids": typed, "node": node, "needs": needs})


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


## Should this registered piece be standing on the table right now? One owned id out of the
## piece's set is enough; its `needs` id (if any) is not optional, and `needs` chains — the
## Penthouse needs the Club, and a chair needs the Penthouse, so a chair needs both.
func _needs_met(id: StringName, depth: int = 0) -> bool:
	if id == &"" or depth > 4:
		return true
	if not hardware_unlocked(id):
		return false
	for piece: Dictionary in _pieces:
		var ids: Array[StringName] = piece["ids"]
		if ids.has(id):
			return _needs_met(StringName(piece.get("needs", &"")), depth + 1)
	return true


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


func hardware_piece_active(piece: Dictionary) -> bool:
	if not _needs_met(StringName(piece.get("needs", &""))):
		return false
	for id: StringName in piece["ids"]:
		if hardware_unlocked(id):
			return true
	return false


## Dev/sim door into the owned set, the same one `KINGPIN_TABLE_HARDWARE` opens: force these
## ids on without a Ledger. The Club's nodes are M2 content and have no upgrade entries yet,
## so the sims stage the deck through here.
func force_hardware(ids: Array, on: bool = true) -> void:
	for id: Variant in ids:
		if on:
			_forced[StringName(id)] = true
		else:
			_forced.erase(StringName(id))
	refresh_hardware()


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
		var node: Node2D = piece["node"]
		var live := hardware_piece_active(piece)
		Dormant.apply(node, live)
		# dormant → active is a *purchase*: send the crew in rather than popping it on. The
		# first pass of a session is the table loading its own save, not a purchase.
		if live == _built_once.has(node):
			continue
		if live:
			_built_once[node] = true
			if construction != null and not _first_refresh:
				construction.start(node)
		else:
			_built_once.erase(node)
			if construction != null:
				construction.cancel(node)
			node.modulate.a = 1.0
	_first_refresh = false
	if club != null:
		club.set_flippers_live(hardware_unlocked(ClubDeck.ID_DECK)
				and hardware_unlocked(ClubDeck.ID_FLIPPERS))
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


# ========================================================== the Commission =====
##
## Same division of labour as the raid: the fight (game/flow/bosses/) owns the phases, the
## clock and the money; the table owns the hardware and stands it up when asked.


## Everything down, meter blank. Called when a fight starts and when it ends.
func clear_boss() -> void:
	boss_active = false
	for t: BossTarget in [boss_sedan, boss_truck]:
		if t != null:
			t.set_hardware_active(false)
			t.arm(0)
	set_boss_goons(false)
	set_boss_door(false)
	set_boss_meter("", 0.0)
	queue_redraw()


## Stand up (or take down) one of the boss vehicles.
##   mode &"off" — gone.  &"run" — riding its rail/arc.  &"park" — stopped at its mark.
## `hits` is how many panels are left in it; `speed_gate` is the Butcher's orbit-pace rule.
func set_boss_target(kind: StringName, mode: StringName, hits: int = 0,
		speed_gate: float = 0.0) -> void:
	var t: BossTarget = boss_sedan if kind == &"sedan" else boss_truck
	if t == null:
		return
	if mode == &"off":
		t.set_hardware_active(false)
		t.arm(0)
		return
	boss_active = true
	t.arm(hits, speed_gate)
	if mode == &"park":
		t.park_at(SEDAN_PARK if kind == &"sedan" else TRUCK_PARK)
	else:
		t.set_path(PackedVector2Array([
			Vector2(SEDAN_RAIL_FROM_X, SEDAN_RAIL_Y), Vector2(SEDAN_RAIL_TO_X, SEDAN_RAIL_Y),
		]) if kind == &"sedan" else _truck_path())
		t.set_moving(true)
	t.set_hardware_active(true)
	queue_redraw()


## Sammy's three goons: while any of them is standing his crew is holding the cans shut.
func set_boss_goons(on: bool) -> void:
	if on:
		boss_active = true
	for g in boss_goons:
		g.set_marked(false)
		g.set_hardware_active(on)
	queue_redraw()


func boss_goons_standing() -> int:
	var n := 0
	for g in boss_goons:
		if g.visible and not g.marked:
			n += 1
	return n


func set_boss_door(on: bool) -> void:
	if boss_door == null:
		return
	if on:
		boss_active = true
	boss_door.set_hardware_active(on)
	queue_redraw()


func boss_door_panels_left() -> int:
	if boss_door == null:
		return 0
	return boss_door.targets().size() - boss_door.marked_count()


## The Butcher's cold-storage readout: what the armored cans are holding, as a bar the player
## can watch fill. `fill` is 0..1; an empty label takes the meter off the table.
func set_boss_meter(text: String, fill: float) -> void:
	if _boss_meter_text == text and is_equal_approx(_boss_meter_fill, fill):
		return
	_boss_meter_text = text
	_boss_meter_fill = clampf(fill, 0.0, 1.0)
	queue_redraw()


## A goon is not a payout: Sammy's crew is scenery with a switch on it, and the fight decides
## what a downed goon means.
func _on_goon_struck(target: StandupTarget, _ball_hit: Ball) -> void:
	if target.marked:
		return
	target.set_marked(true)
	AudioDirector.play(&"drop_clack")
	boss_hit.emit(&"goon", boss_goons_standing(), 0.0)
	if boss_goons_standing() <= 0:
		boss_down.emit(&"goon")


## Work one storefront till without a ball (Manny, specs/m2-content.md §2). Returns the id it
## collected, or &"" if no shutters were open. The flow lane owns the clock.
func auto_collect_one() -> StringName:
	for s in storefronts:
		if s.visible and s.is_open():
			if s.collect_now(ball).is_positive():
				return s.id
	return &""


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


## How many storefront banks are currently armed — the Collection Round trigger reads
## this instead of poking each storefront's state (flow-lane request, M2).
func storefronts_armed_count() -> int:
	var n := 0
	for s in storefronts:
		if s.state_name() == &"armed":
			n += 1
	return n


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
	Balls.register(b)
	AudioDirector.play(&"ball_spawn")
	Events.ball_spawned.emit(b)
	ball_spawned.emit(b)
	return b


## Multiball service (specs/ball-registry.md): an ADDITIONAL live ball, released at a
## given point (default: the back-room area feeds Family Meeting from the deck). The
## primary `ball` ref and its bindings are untouched — extras exist only in the registry.
func spawn_extra_ball(at: Vector2 = Vector2.ZERO) -> Ball:
	var b: Ball = BALL_SCENE.instantiate()
	b.name = "BallExtra%d" % balls_served
	b.position = spawn_point() if at == Vector2.ZERO else at
	add_child(b)
	balls_served += 1
	Balls.register(b)
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
	if club != null:
		club.set_ball(ball)
	if docks != null:
		docks.set_ball(ball)
	if penthouse != null:
		penthouse.set_ball(ball)


func _on_drain_entered(body: Node2D, sound: StringName = &"drain") -> void:
	if not (body is Ball):
		return
	_lose_ball(body as Ball, sound)


## One ball, gone. Every way of losing a ball on this machine funnels through here so the
## flow lane only ever sees one shape of loss, whichever hole it went down.
func _lose_ball(lost: Ball, sound: StringName = &"drain") -> void:
	if lost == null or not is_instance_valid(lost):
		return
	if not Balls.live().has(lost):
		return                     # already counted: two zones can overlap for a tick
	var was_primary := lost == ball
	if was_primary:
		# Multiball: the lowest surviving extra becomes the new primary so the flipper/
		# plunger/magnet bindings stay on a live ball. The lost ball is still registered
		# here, so pick the survivor by hand rather than via Balls.primary().
		ball = null
		for b in Balls.live():
			if b != lost and (ball == null or b.global_position.y > ball.global_position.y):
				ball = b
		_bind_ball()
	Balls.unregister(lost)
	lost.queue_free()
	AudioDirector.play(sound)
	Events.ball_drained.emit(lost)
	ball_lost.emit(lost)
	if auto_respawn and ball == null:
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
	# Upstairs has its own legitimate resting places — a mini-bat cradle, a saucer mid-hold,
	# a pocket riding the wheel round, a Sit-Down mid-negotiation, a crate on the hoist — and
	# none of them wants a coil under it.
	if club != null and club.search_exempt(ball):
		_still_for = 0.0
		return
	if penthouse != null and penthouse.search_exempt(ball):
		_still_for = 0.0
		return
	if docks != null and docks.search_exempt(ball):
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


## The Butcher's cold storage, painted on the felt inside the arch: a frost bar with the
## banked total over it. Nothing else lives up there, so the readout never covers a shot.
func _draw_boss_meter() -> void:
	if _boss_meter_text.is_empty():
		return
	var r := Rect2(BOSS_METER_AT - BOSS_METER_SIZE * 0.5, BOSS_METER_SIZE)
	draw_rect(r, Feel.COL_INK.lightened(0.10))
	draw_rect(Rect2(r.position, Vector2(r.size.x * _boss_meter_fill, r.size.y)),
			ClubDeck.COL_VIOLET.lerp(Feel.COL_CLEAN, 0.35))
	draw_rect(r, Feel.COL_BRASS.darkened(0.3), false, 3.0)
	var font := ThemeDB.fallback_font
	if font != null:
		# Unclipped on purpose: a truncated total ("$1.2" for $1.29M) is worse than a label that
		# runs a little wide on the felt.
		draw_string(font, BOSS_METER_AT + Vector2(-BOSS_METER_SIZE.x * 0.5, -22.0),
				_boss_meter_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Feel.COL_NEWSPRINT)


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

	_draw_boss_meter()

	# the drain is a storm grate lit from below, not a hole (docs/02 §4)
	draw_line(Vector2(PLAY_LEFT, DRAIN_Y), Vector2(PLAY_RIGHT, DRAIN_Y),
			Feel.COL_DIRTY.darkened(0.35), 3.0)
	for i in range(9):
		var gx := lerpf(PLAY_LEFT + 40.0, PLAY_RIGHT - 40.0, float(i) / 8.0)
		draw_line(Vector2(gx, DRAIN_Y + 3.0), Vector2(gx, PLAY_BOTTOM - 4.0),
				Feel.COL_DIRTY.darkened(0.55), 3.0)
