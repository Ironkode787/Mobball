class_name ProgressionTable
extends TableSegment
## THE TABLE (specs/m1-hook.md Lane 3). One screen, 1080×1920, built entirely in code so the
## collision geometry and the `_draw()` come from the same numbers and can never drift.
##
## What the player starts with is a *bare alley*: walls, two flippers, a drain, one dented
## trash can, dead sling triangles and short return sweeps, plus a rubber band for a plunger.
## Everything else on this table already exists — it is built, wired and standing there — but
## it is hidden and its collision is switched off until `Game.stats.hardware_unlocked(id)` says
## the Ledger has paid for it. The starter slings are the deliberate exception: Corner Boys
## powers their face sensor, kick, score and figures without changing their physical triangle.
## Buying furniture is the tutorial (docs/02 §2 R0), so the growth has to be physical: a
## dormant piece must not deflect a ball, and a live one must not appear without its geometry.
##
## This is its own machine, not the M0 alley with furniture bolted above it. The base alley
## remains the feel calibration fixture; this table authors a broader, higher control zone,
## a sculpted centre drain and offset city shots around those proven flipper mechanics.
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
## M3 — the Truck Route (docs/02 §2 R5). It also reports through `orbit_completed`, so a
## consumer that just counts loops is unchanged; this one says *which* loop, because the
## right-hand one is a smuggling objective and the getaway is not.
signal truck_route_completed()
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
## M3 — CITY HALL (docs/02 §2 R7). One closed lap of the dome, at the rail speed it closed
## at. The City Hall Circuit is a *chain* of four shots (orbit → staircase → penthouse gate →
## dome loop) and the chain is the flow lane's to count: the table reports each shot once and
## never decides what a sequence of them means.
signal dome_loop_completed(speed: float)
## M3 — the Mystery Briefcase. The table drops the token, watches it, and says which way it
## went; what is inside it (and the odds on it) is FLOW-3's.
signal briefcase_collected()
signal briefcase_expired()

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

# ---------------------------------------------------------------- the new control zone
## The bats sit a full 85 px above the alley pair. Their 430 px pivot spread and 1.08-scale
## bodies give the centre grate an 81 px mouth while opening a lower mini-field beneath them.
const FLIPPER_PIVOT_L := Vector2(275.0, 1615.0)
const FLIPPER_PIVOT_R := Vector2(705.0, 1615.0)
const FLIPPER_SCALE := 1.08
## Taller slings create a proper lower-field arena. The lane guides sweep into the pivots,
## making two long, satisfying return feeds instead of short vertical gutters.
const OUTLANE_X := 143.0
const OUTLANE_TOP := 1360.0
const OUTLANE_BOTTOM := 1510.0
const INLANE_END := Vector2(273.0, 1595.0)
const SLING_OUTER_TOP := Vector2(230.0, 1435.0)
const SLING_OUTER_BOTTOM := Vector2(230.0, 1475.0)
const SLING_INNER := Vector2(375.0, 1540.0)
const MIRROR_X := 490.0
const DRAIN_Y := 1880.0
const DRAIN_HEIGHT := 24.0
const CENTRE_DRAIN_AT := Vector2(490.0, 1810.0)
const CENTRE_DRAIN_SIZE := Vector2(190.0, 64.0)
const OUTLANE_DRAIN_Y := 1545.0

# ---------------------------------------------------------------- the numbers lane / orbit
## A broad avenue down the left wall. The old 90 px gutter read like plumbing; this one is a
## committed orbit with enough daylight to see the ball accelerate through the spinner.
const LANE_GUIDE_X := 180.0
const LANE_GUIDE_TOP := 486.0
const LANE_GUIDE_BOTTOM := 1180.0
const CHANNEL_WIDTH := 113.0
const ORBIT_ARC_RADIUS := 370.0
const ORBIT_ARC_FROM_DEG := -167.0
## Stops short of the apex on purpose: at the very top the arc's own surface is level enough
## for a ball to sit down on it, and a ball parked on the roof of the orbit ends the night.
const ORBIT_ARC_TO_DEG := -112.0
const SPINNER_AT := Vector2(114.5, 900.0)
const ORBIT_ENTRY_AT := Vector2(114.5, 1120.0)
const ORBIT_ENTRY_SIZE := Vector2(104.0, 56.0)
const ORBIT_EXIT_DEG := -120.0
const ORBIT_EXIT_RADIUS := 436.0

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
## Four splayed rails turn the old comb of parallel posts into a three-way fan. The approach
## pinches toward the inserts, then opens into three visibly different exits under the arch.
const ROLLOVER_POST_FROM: Array = [
	Vector2(260.0, 500.0), Vector2(385.0, 450.0),
	Vector2(525.0, 430.0), Vector2(690.0, 485.0),
]
const ROLLOVER_POST_TO: Array = [
	Vector2(320.0, 630.0), Vector2(420.0, 610.0),
	Vector2(525.0, 590.0), Vector2(650.0, 620.0),
]
const ROLLOVER_AT: Array = [
	Vector2(365.0, 565.0), Vector2(472.0, 560.0), Vector2(585.0, 570.0),
]
const ROLLOVER_POST_THICK := 16.0

# ---------------------------------------------------------------- the alley & the corner
## The cans now own an offset left-side neighborhood. A clean right diagonal stays open for
## aimed Wire and Staircase shots instead of every upper-field device sharing one triangle.
const BUMPER_AT: Array = [
	Vector2(480.0, 700.0), Vector2(300.0, 735.0), Vector2(390.0, 890.0),
]
const BUMPER_SCALE: PackedFloat32Array = [1.14, 0.92, 1.02]
## The payphones make a real diagonal bank whose face looks down the main shooting line.
## Their centres are close enough to deny a ball-sized hiding place between cabinets.
const WIRE_AT: Array = [
	Vector2(750.0, 600.0), Vector2(792.0, 720.0), Vector2(834.0, 840.0),
]
const WIRE_FACE := Vector2(-0.943858, 0.330350)
const WIRE_LENGTHS: PackedFloat32Array = [94.0, 82.0, 70.0]
const TARGET_LENGTH := 76.0

# ---------------------------------------------------------------- the block
const STOREFRONT_AT: Array = [
	Vector2(570.0, 1280.0),      # Lucky's Laundromat: the lower centre anchor
	Vector2(475.0, 1030.0),      # Nonna's Pizzeria: the block's high point
	Vector2(820.0, 1240.0),      # Fat Tony's Pawn: low right
]
## Banks are raked off square so a ball coming down from above sheds sideways into a gap
## instead of parking on 148 px of flat drop-target roof.
const STOREFRONT_RAKE: PackedFloat32Array = [18.0, -12.0, -18.0]
const STOREFRONT_IDS: Array[StringName] = [
	&"storefront_laundromat", &"storefront_pizzeria", &"storefront_pawn",
]
const STOREFRONT_SIGNS: Array[StringName] = [&"LUCKY'S", &"NONNA'S", &"FAT TONY'S"]

# ---------------------------------------------------------------- extras
## The donut shop stands square to the field, not raked across it: a bar angled into the
## right-hand wall is a corner, and a soak found the ball asleep in it for forty seconds.
## Vertical faces have no roof to sit on.
const BRIBE_AT := Vector2(870.0, 540.0)
const BRIBE_FACE := Vector2(-0.98, 0.20)
## Raid officers occupy four different intersections in the new crooked street plan. The
## fourth closes the southern briefcase court while leaving a fair drop elsewhere.
const COP_AT: Array = [
	Vector2(270.0, 1010.0), Vector2(860.0, 1000.0),
	Vector2(350.0, 1180.0), Vector2(540.0, 1370.0),
]
## Steep enough that the ball outruns rubber friction (0.30) on the way down their backs.
const COP_RAKE: PackedFloat32Array = [22.0, -22.0, 22.0, -22.0]
const KICKBACK_AT := Vector2(96.0, 1455.0)
const KICKBACK_SIZE := Vector2(86.0, 56.0)
const MAGNET_AT := Vector2(490.0, 1755.0)

# ---------------------------------------------------------------- the federal raid (M3)
## The Director's coil (docs/05 §9 phase 3). It sits a third of the way up the field rather
## than at the grate: the Captain drags you *into* the drain, the Bureau drags you *off* the
## block, and a player has to read which of the two is winding up. Two tells at once is not
## difficulty, so the table keeps their telegraphs apart in code — see `_keep_magnets_apart`.
const DIRECTOR_AT := Vector2(535.0, 1430.0)
## Room the two coils must leave each other: a full telegraph plus a beat to read it in.
const MAGNET_MIN_GAP := DrainMagnet.TELEGRAPH + 0.5
## How dirty the felt goes. The M1 raid's 0.12 is a shipped, tuned number and stays exactly
## what it was; the federal stages are denser passes of the same ink.
const RAID_TINT := 0.12
const FEDERAL_TINT: PackedFloat32Array = [0.0, 0.16, 0.20, 0.25]

# ---------------------------------------------------------------- the briefcase (M3)
## Where a case may be put down. Three spots on the main field, each of them more than a ball
## diameter clear of every collider that is bolted down (asserted in tests/sim/dome_sim.gd) —
## because a token that lands half inside a payphone reads as a bug even though it has no
## collision of its own. The first two are also clear of the raid's cops; the third is the
## roomiest spot on the table and the cops stand right next to it.
const BRIEFCASE_SPOTS: Array = [
	Vector2(700.0, 870.0),       # the court below the diagonal Wire
	Vector2(700.0, 1000.0),      # the court above the stepped Block
	Vector2(520.0, 1450.0),      # southern court; the fourth raid cop closes it
]
## Centre-to-centre room a piece of *transient* hardware has to leave a spot before the case
## will be dropped on it. The fixed furniture is already accounted for in the spots.
const BRIEFCASE_CLEAR := 100.0
const BRIEFCASE_CLEAR_VEHICLE := 170.0

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

## The starter rubber band is reliable-but-coarse, not broken: below ~0.90 the ball never
## clears the shooter lane on this geometry. Three safe powers let a new player choose a
## broad pull without pretending the rubber band is a precision plunger. `A Real Plunger`
## replaces these bands with the inherited continuous charge and detents.
const PLUNGER_STARTER_POWERS := [0.90, 0.95, 1.00]
const PLUNGER_STARTER_DEFAULT_BAND := 1
## Legacy fixture alias: old growth probes read this as the desktop/default middle band. The
## live starter plunger is no longer fixed; touch pulls select all three values above.
const PLUNGER_FIXED_POWER := 0.95

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
## THE FEDERAL RAID (docs/05 §9). 0 off · 1 street sweep · 2 wiretap · 3 the Director.
## Independent of `raid_active`: either switch can put the cops out, and the hardware is a
## function of both, so a local raid during a federal one is not a double toggle.
var federal_phase: int = 0
## The Bureau's second coil, and the vans. Built with everything else, dormant until a phase
## asks for them — the same rule the raid's cops live under.
var director: DrainMagnet = null
var vans: FederalVans = null
## The bagman's token. Never bought, never scored: `spawn_briefcase` puts it down.
var briefcase: Briefcase = null
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
## The crown (R7). One golden rail in the sky above the lot — see segments/city_hall.gd.
var city_hall: CityHall = null
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
var _case_rng := RandomNumberGenerator.new()
var _boss_meter_text: String = ""
var _boss_meter_fill: float = 0.0
var _built_once: Dictionary = {}             ## node -> true: already stood up at least once
var _first_refresh: bool = true              ## boot: the table loads its save, it is not built
var _show_clock: float = 0.0                  ## slow cabinet bulbs; cosmetic only
var _show_redraw: float = 0.0


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
	if city_hall != null and city_hall.is_hardware_active():
		r = r.merge(city_hall.bounds())
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
			return Vector2(Docks.LEFT_LOW_FROM.x, (Docks.MOUTH_TOP + Docks.MOUTH_BOTTOM) * 0.5)
		&"penthouse":
			return Penthouse.FLOOR_APEX
		&"penthouse_mouth":
			return Penthouse.STAIR_MOUTH
		# The last of the sky (R7). Everything above the Club's ceiling is the dome's.
		&"city_hall":
			return CityHall.DOME_CENTER
		&"dome_mouth":
			return CityHall.MOUTH_AT
	return Vector2.ZERO


# ===================================================================== build =====


func _ready() -> void:
	_arch_radius = ARCH_CENTER.distance_to(ARCH_A)
	_search_rng.seed = 0x5EA12C4          # seeded: a sim rerun searches the same way
	_case_rng.seed = 0xB1EFCA5E           # ditto: the bagman uses the same doors twice
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
	_build_city_hall()
	_build_drain()
	_build_plunger()
	_build_construction()
	Events.upgrade_purchased.connect(_on_upgrade_purchased)
	# A restored save recomputes Stats AFTER this _ready has already run — the boot signal
	# is what puts a returning player's bought hardware back on the field.
	Events.session_booted.connect(refresh_hardware)
	refresh_hardware()
	queue_redraw()


## Dev affordance for screenshots and one-off experiments, never used by the game:
##   KINGPIN_TABLE_DEBUG=1                        every piece on
##   KINGPIN_TABLE_HARDWARE=rollovers,wire_bank   just these, on top of what Stats says
func _read_env_hook() -> void:
	if not ReleaseChannel.allow_development_hooks():
		return
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

	# The short return sweep is battered furniture on the starter table. Guard Rails adds the
	# long vertical outlane guard above it; buying the upgrade therefore extends this return
	# path instead of making the whole inlane geometry materialise from nowhere.
	var returns := WallPiece.new()
	returns.name = "InlaneReturns"
	returns.color = Feel.COL_BRASS.darkened(0.52)
	returns.rim = Feel.COL_INK.darkened(0.12)
	add_child(returns)
	for s in [1.0, -1.0]:
		returns.bar(_mx(OUTLANE_X, s, OUTLANE_BOTTOM),
				_mx(INLANE_END.x, s, INLANE_END.y), GUIDE_THICK)

	# The vertical guard rails are an upgrade (docs/02 §2 R0). They are a separate body so
	# the bare table keeps the short return geometry without getting the outlane wall yet.
	var guides := WallPiece.new()
	guides.name = "InlaneGuides"
	add_child(guides)
	for s in [1.0, -1.0]:
		guides.bar(_mx(OUTLANE_X, s, OUTLANE_TOP), _mx(OUTLANE_X, s, OUTLANE_BOTTOM), GUIDE_THICK)
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
	for i in range(ROLLOVER_POST_FROM.size()):
		posts.bar(ROLLOVER_POST_FROM[i], ROLLOVER_POST_TO[i], ROLLOVER_POST_THICK)
	_register([&"rollovers"], posts)

	for i in range(ROLLOVER_AT.size()):
		var r := Rollover.new()
		r.name = "Rollover%d" % (i + 1)
		r.configure(StringName("rollover_%d" % (i + 1)), i, ROLLOVER_AT[i])
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
		b.size_scale = BUMPER_SCALE[i]
		b.name = "Bumper%d" % (i + 1)
		add_child(b)
		_bumpers.append(b)
		if i > 0:                       # the first dented can is the table you are given
			_register([b.id], b)


func _build_slings() -> void:
	for s in [1.0, -1.0]:
		var sl: Slingshot = SLING_SCENE.instantiate()
		# The triangle is starter-table dead rubber: it is physically present and visible, but
		# Corner Boys are what power its face sensor, kick, score and figure/glow.
		sl.passive_when_inactive = true
		var id := &"sling_l" if s > 0.0 else &"sling_r"
		sl.configure(id,
			_mx(SLING_OUTER_BOTTOM.x, s, SLING_OUTER_BOTTOM.y),
			_mx(SLING_INNER.x, s, SLING_INNER.y),
			_mx(SLING_OUTER_TOP.x, s, SLING_OUTER_TOP.y))
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
	for i in range(WIRE_AT.size()):
		var t := StandupTarget.new()
		t.name = "Payphone%d" % (i + 1)
		t.configure(StringName("wire_%d" % (i + 1)), WIRE_AT[i], WIRE_FACE, WIRE_LENGTHS[i])
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

	# THE FEDERAL RAID (M3). A second coil, two vans and a bagman's token — all of it built
	# with the table and dormant, none of it for sale.
	director = DrainMagnet.new()
	director.name = "DirectorsMagnet"
	director.position = DIRECTOR_AT
	director.drain_point = Vector2(MIRROR_X, DRAIN_Y + 40.0)
	director.self_driven = true         # nobody upstairs schedules this one; it hunts alone
	add_child(director)

	vans = FederalVans.new()
	vans.name = "FederalVans"
	add_child(vans)

	briefcase = Briefcase.new()
	briefcase.name = "Briefcase"
	add_child(briefcase)
	briefcase.collected.connect(_on_briefcase_collected)
	briefcase.expired.connect(func() -> void: briefcase_expired.emit())

	# THE TRUCK ROUTE (M3). Two gates on the corridor outside the payphones and the top of
	# the arch — no new walls, see ORBIT_R_ENTRY_AT.
	orbit_right = OrbitLane.new()
	orbit_right.name = "OrbitRight"
	add_child(orbit_right)
	orbit_right.configure(&"orbit_right", ORBIT_R_ENTRY_AT, ORBIT_R_ENTRY_SIZE,
			_polar(ORBIT_EXIT_RADIUS, ORBIT_R_EXIT_DEG), 34.0)
	orbit_right.orbit_completed.connect(func() -> void:
		orbit_completed.emit()
		truck_route_completed.emit())
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
	flipper_left.size_scale = FLIPPER_SCALE
	flipper_left.name = "FlipperLeft"
	flipper_left.position = FLIPPER_PIVOT_L
	add_child(flipper_left)

	flipper_right = FLIPPER_SCENE.instantiate()
	flipper_right.side = &"right"
	flipper_right.size_scale = FLIPPER_SCALE
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


## CITY HALL (docs/02 §2 R7). One piece of furniture, no sub-hardware: the dome is a rail and
## a painting. It is registered under the Penthouse — which is registered under the Club — so
## the crown cannot arrive before the two floors it stands on, however it is forced on.
func _build_city_hall() -> void:
	city_hall = CityHall.new()
	city_hall.name = "CityHall"
	add_child(city_hall)
	city_hall.loop_completed.connect(func(s: float) -> void: dome_loop_completed.emit(s))
	_register([CityHall.ID_CITY_HALL], city_hall, Penthouse.ID_PENTHOUSE)


## The crew with the hammers. Added last so it draws over everything it is building, and
## switched off entirely under a headless display so no sim's timing rides on an animation.
func _build_construction() -> void:
	construction = BuildIn.new()
	construction.name = "Construction"
	construction.enabled = DisplayServer.get_name() != "headless" \
			and (not ReleaseChannel.allow_development_hooks() \
			or OS.get_environment("KINGPIN_NO_BUILD_ANIM") != "1")
	add_child(construction)


## Three visible exits replace the old invisible full-width line: a centre storm grate below
## the bats and a collection trench at the foot of either outlane. A final thin floor sensor
## remains as cabinet safety, but normal play reaches one of the authored mouths first.
func _build_drain() -> void:
	var area := Area2D.new()
	area.name = "Drain"
	area.collision_layer = Feel.LAYER_ZONES
	area.collision_mask = Feel.LAYER_BALL
	area.monitorable = false

	var centre_shape := CollisionShape2D.new()
	var centre_rect := RectangleShape2D.new()
	centre_rect.size = CENTRE_DRAIN_SIZE
	centre_shape.shape = centre_rect
	centre_shape.position = CENTRE_DRAIN_AT
	area.add_child(centre_shape)

	var left_shape := CollisionShape2D.new()
	var left_rect := RectangleShape2D.new()
	left_rect.size = Vector2(OUTLANE_X - PLAY_LEFT, DRAIN_Y - OUTLANE_DRAIN_Y)
	left_shape.shape = left_rect
	left_shape.position = Vector2((PLAY_LEFT + OUTLANE_X) * 0.5,
			(OUTLANE_DRAIN_Y + DRAIN_Y) * 0.5)
	area.add_child(left_shape)

	var right_shape := CollisionShape2D.new()
	var right_edge := MIRROR_X * 2.0 - OUTLANE_X
	var right_rect := RectangleShape2D.new()
	right_rect.size = Vector2(PLAY_RIGHT - right_edge, DRAIN_Y - OUTLANE_DRAIN_Y)
	right_shape.shape = right_rect
	right_shape.position = Vector2((right_edge + PLAY_RIGHT) * 0.5,
			(OUTLANE_DRAIN_Y + DRAIN_Y) * 0.5)
	area.add_child(right_shape)

	var safety_shape := CollisionShape2D.new()
	var safety_rect := RectangleShape2D.new()
	safety_rect.size = Vector2(PLAY_RIGHT - PLAY_LEFT, DRAIN_HEIGHT)
	safety_shape.shape = safety_rect
	safety_shape.position = Vector2((PLAY_LEFT + PLAY_RIGHT) * 0.5,
			DRAIN_Y + DRAIN_HEIGHT * 0.5)
	area.add_child(safety_shape)
	add_child(area)
	area.body_entered.connect(func(body: Node2D) -> void: _on_drain_entered(body))


func _build_plunger() -> void:
	plunger = BandedPlunger.new()
	plunger.name = "Plunger"
	plunger.lane_rect = lane_rect()
	plunger.starter_powers = PLUNGER_STARTER_POWERS
	plunger.starter_band = PLUNGER_STARTER_DEFAULT_BAND
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
	# Progression slings are visible passive bodies before purchase. Presence here means the
	# upgrade is live/powered, preserving the hardware query contract without hiding the body.
	if id == &"slingshots":
		for sl: Slingshot in _slings:
			if sl.is_powered():
				return true
		return false
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
	_apply_raid_hardware()


## THE FEDERAL RAID (docs/05 §9, R7). Three stages of the same siege, each one adding to the
## last and each one built out of hardware this table already owns:
##
##   0  off
##   1  street sweep — the cops and the Captain's coil, exactly as a local raid, on a
##      dirtier felt
##   2  wiretap — two unmarked vans in the bottom corners with their lights walking up the
##      block. Visual only: no collider arrives with a federal warrant
##   3  the Director — a SECOND coil, a third of the way up the field, alternating with the
##      Captain's so there is never more than one telegraph on the table
##
## Independent of `set_raid_active`: a local raid during a federal one is not a double
## toggle, because the shared hardware is a function of both switches.
func set_federal_raid(phase: int) -> void:
	var want := clampi(phase, 0, 3)
	if federal_phase == want:
		return
	var was := federal_phase
	federal_phase = want
	_apply_raid_hardware()
	vans.set_active(want >= 2)
	if want >= 3:
		if not director.active:
			director.set_active(true)
			# Opposite half of the Captain's cycle to begin with; `_keep_magnets_apart` holds
			# them there for as long as both are running.
			director.reschedule(DrainMagnet.PERIOD * 0.5)
	else:
		director.set_active(false)
	if was == 0 and want > 0:
		AudioDirector.play(&"raid_start")
	queue_redraw()


## Cops and the Captain's coil, from whichever siege wants them.
func _apply_raid_hardware() -> void:
	var on := raid_active or federal_phase >= 1
	for c in cop_targets:
		c.set_hardware_active(on)
		c.set_marked(false)
	magnet.set_active(on)
	if not on:
		set_raid_speed(1.0)          # a siege does not leave its clock behind
	queue_redraw()


## Two coils under one table may never wind up at the same time — a player can read one tell,
## not two, and a double pull is a coin flip rather than a difficulty. Whichever is already
## telegraphing owns the field; the other one's pull is pushed past the end of it.
func _keep_magnets_apart() -> void:
	if director == null or not director.active or not magnet.active:
		return
	var winding := magnet if magnet.is_telegraphing() else director
	var waiting := director if winding == magnet else magnet
	if not winding.is_telegraphing():
		return
	# Half a cycle apart is the aim; when the raid is running at double time that is more
	# room than the cycle has, so take what there is — still a clear tell's worth.
	var gap := minf(MAGNET_MIN_GAP,
			DrainMagnet.PERIOD / maxf(waiting.rate, 0.25) * 0.45)
	if waiting.time_to_pull() < winding.time_to_pull() + gap:
		waiting.reschedule(winding.time_to_pull() + gap)


## Fire the Captain's magnet now (flow drives the schedule; see DrainMagnet.self_driven).
func magnet_pull() -> void:
	magnet.pull(ball)


## Run the raid's hardware at `scale` times its usual pace — the RICO raid's street sweep
## asks for double time (game/flow/rico.gd `SWEEP_SPEED`). The cops are furniture and have no
## clock of their own, so what "faster" means on this table is the coils: the same 1.2 s tell,
## arriving twice as often. Clamped, and 1.0 puts it back.
func set_raid_speed(scale: float) -> void:
	var rate := clampf(scale, 0.25, 4.0)
	if magnet != null:
		magnet.rate = rate
	if director != null:
		director.rate = rate


# ================================================================ the briefcase =====
##
## docs/05 — the Mystery Briefcase. The table owns the token: where it may be put down, how
## long it stands there, and which of the two ways it can end. The flow lane owns everything
## about what is in it.


## Drop a case. `at` = Vector2.ZERO picks one of `BRIEFCASE_SPOTS` at random, skipping any
## the raid's cops or a Commission fight are standing on; an explicit point is taken as
## given. One case at a time — a second call while one is live does nothing, so a caller that
## needs to know should read `briefcase_live()` afterwards.
func spawn_briefcase(at: Vector2 = Vector2.ZERO) -> void:
	if briefcase == null or briefcase.is_live():
		return
	var spot := at
	if spot == Vector2.ZERO:
		var open: Array[Vector2] = []
		for candidate: Vector2 in BRIEFCASE_SPOTS:
			if _spot_open(candidate):
				open.append(candidate)
		if open.is_empty():
			return                  # the waist is full: the bagman waits for a quieter Night
		spot = open[_case_rng.randi_range(0, open.size() - 1)]
	briefcase.drop_at(spot)


func briefcase_live() -> bool:
	return briefcase != null and briefcase.is_live()


func briefcase_at() -> Vector2:
	return briefcase.global_position if briefcase_live() else Vector2.ZERO


## Is this spot clear of everything that comes and goes? The fixed furniture is already
## accounted for in `BRIEFCASE_SPOTS`; what moves is the raid's cops, Sammy's crew and the
## Commission's vehicles — and the ball, which must never have a case land on top of it.
func _spot_open(at: Vector2) -> bool:
	for b in Balls.live():
		if is_instance_valid(b) and b.global_position.distance_to(at) < BRIEFCASE_CLEAR:
			return false
	for t: StandupTarget in cop_targets + boss_goons:
		if t.visible and t.global_position.distance_to(at) < BRIEFCASE_CLEAR:
			return false
	if boss_door != null and boss_door.visible:
		for t: StandupTarget in boss_door.targets():
			if t.visible and t.global_position.distance_to(at) < BRIEFCASE_CLEAR:
				return false
	for v: BossTarget in [boss_sedan, boss_truck]:
		if v != null and v.visible \
				and v.global_position.distance_to(at) < BRIEFCASE_CLEAR_VEHICLE:
			return false
	return true


func _on_briefcase_collected(_ball_hit: Ball) -> void:
	briefcase_collected.emit()


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
	if city_hall != null:
		city_hall.set_ball(ball)


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
	_keep_magnets_apart()


func _process(delta: float) -> void:
	if Presentation.fx != null and Presentation.fx.reduced_flash:
		if _show_clock != 0.0:
			_show_clock = 0.0
			queue_redraw()
		return
	_show_clock += delta
	_show_redraw += delta
	# Twelve redraws a second is enough for incandescent bulbs and keeps the vector table
	# cheap on the Android compatibility renderer.
	if _show_redraw >= 1.0 / 12.0:
		_show_redraw = 0.0
		queue_redraw()


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
	if city_hall != null and city_hall.search_exempt(ball):
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
	var font := Presentation.theme.font_for(&"annotation_bold")
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


## How dirty the felt is right now. A local raid is the M1 number it has always been; a
## federal one is a heavier pass of the same ink, and the two do not stack — the worse siege
## wins, because the felt is a state, not a sum.
func _raid_tint() -> float:
	var federal := FEDERAL_TINT[clampi(federal_phase, 0, FEDERAL_TINT.size() - 1)]
	return maxf(RAID_TINT if raid_active else 0.0, federal)


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
	_draw_cabinet()
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

	var tint := _raid_tint()
	if tint > 0.0:
		draw_colored_polygon(felt, Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g,
				Feel.COL_DIRTY.b, tint))

	_draw_playfield_inlay()
	_draw_backglass()
	_draw_shot_labels()

	draw_rect(Rect2(Vector2(LANE_LEFT, DIVIDER_TOP), Vector2(LANE_RIGHT - LANE_LEFT,
			LANE_FLOOR_Y - DIVIDER_TOP)), Feel.COL_FELT.darkened(0.25))
	for i in range(1, 4):
		var y := LANE_FLOOR_Y - float(i) * 380.0
		draw_line(Vector2(LANE_LEFT + 6.0, y), Vector2(LANE_RIGHT - 6.0, y),
				Feel.COL_BRASS.darkened(0.5), 2.0)

	if _walls != null:
		_walls.draw_into(self, Feel.COL_INK.lightened(0.12), Feel.COL_INK)
		draw_arc(ARCH_CENTER, _arch_radius - OUTER_THICK * 0.48, a0, a1, 56,
				Feel.COL_BRASS.darkened(0.42), 4.0)
		draw_line(ARCH_A + Vector2(OUTER_THICK * 0.48, 0.0),
				Vector2(PLAY_LEFT + OUTER_THICK * 0.48, PLAY_BOTTOM),
				Feel.COL_BRASS.darkened(0.52), 4.0)
		draw_line(ARCH_C - Vector2(OUTER_THICK * 0.48, 0.0),
				Vector2(LANE_RIGHT - OUTER_THICK * 0.48, PLAY_BOTTOM),
				Feel.COL_BRASS.darkened(0.52), 4.0)

	var gate_col := Feel.COL_BRASS if _gate_closed else Feel.COL_BRASS.darkened(0.6)
	draw_line(Vector2(DIVIDER_X, GATE_TOP), Vector2(DIVIDER_X, GATE_BOTTOM), gate_col, 12.0)
	for i in range(6):
		var y := 660.0 + float(i) * 190.0
		var hot := posmod(i - int(floor(_show_clock * 3.0)), 4) == 0
		var lane_col := Feel.COL_BRASS.darkened(0.18 if hot else 0.62)
		draw_polyline(PackedVector2Array([
			Vector2(982.0, y + 18.0), Vector2(996.0, y), Vector2(1010.0, y + 18.0),
		]), lane_col, 3.0)

	_draw_boss_meter()

	# The centre grate is a real, readable target between the bat tips; the two side trenches
	# make the outlanes equally explicit. The cabinet safety switch at DRAIN_Y stays invisible.
	var grate := Rect2(CENTRE_DRAIN_AT - CENTRE_DRAIN_SIZE * 0.5, CENTRE_DRAIN_SIZE)
	draw_rect(grate, Feel.COL_DIRTY.darkened(0.42))
	draw_rect(grate.grow(-5.0), Feel.COL_INK.darkened(0.25), false, 3.0)
	for i in range(7):
		var gx := grate.position.x + 22.0 + float(i) * 24.0
		draw_line(Vector2(gx, grate.position.y + 8.0),
				Vector2(gx, grate.end.y - 8.0), Feel.COL_BRASS.darkened(0.62), 4.0)
	for side in [-1.0, 1.0]:
		var x0 := PLAY_LEFT if side < 0.0 else MIRROR_X * 2.0 - OUTLANE_X
		var x1 := OUTLANE_X if side < 0.0 else PLAY_RIGHT
		draw_rect(Rect2(Vector2(x0, OUTLANE_DRAIN_Y),
				Vector2(x1 - x0, DRAIN_Y - OUTLANE_DRAIN_Y)),
				Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g, Feel.COL_DIRTY.b, 0.42))
		for row in range(4):
			var y := OUTLANE_DRAIN_Y + 34.0 + float(row) * 54.0
			draw_line(Vector2(x0 + 10.0, y), Vector2(x1 - 10.0, y),
					Feel.COL_BRASS.darkened(0.72), 3.0)


## The cabinet is part of the spectacle now, not unclaimed black around a physics field. It
## also stitches the negative-y rooms into one machine when the camera follows a ball up.
func _draw_cabinet() -> void:
	var wood := Color("21150F")
	var wood_dark := Color("0B0908")
	draw_rect(Rect2(-10.0, -1600.0, 1100.0, 3520.0), wood_dark)
	draw_rect(Rect2(2.0, -1580.0, 26.0, 3480.0), wood)
	draw_rect(Rect2(1052.0, -1580.0, 26.0, 3480.0), wood)
	draw_line(Vector2(16.0, -1560.0), Vector2(16.0, 1894.0),
			Feel.COL_BRASS.darkened(0.58), 3.0)
	draw_line(Vector2(1064.0, -1560.0), Vector2(1064.0, 1894.0),
			Feel.COL_BRASS.darkened(0.58), 3.0)

	# A city canyon behind the upper floors. The rooms paint over it, while the gaps retain
	# enough architecture that the full-table view reads as one vertical place.
	for i in range(12):
		var x := 42.0 + float(i) * 86.0
		var h := 190.0 + fmod(float(i) * 113.0, 330.0)
		var top := -30.0 - h
		draw_rect(Rect2(x, top, 58.0, h), Feel.COL_INK.lightened(0.045))
		for row in range(5):
			var wy := top + 28.0 + float(row) * 48.0
			if wy > -28.0:
				break
			var lit := (i * 3 + row) % 4 == 1
			draw_rect(Rect2(x + 15.0, wy, 9.0, 13.0),
					Feel.COL_BRASS.darkened(0.28) if lit else Feel.COL_INK.lightened(0.12))
			draw_rect(Rect2(x + 34.0, wy, 9.0, 13.0),
					Feel.COL_BRASS.darkened(0.45) if lit and row % 2 == 0
					else Feel.COL_INK.lightened(0.10))


## Layered felt, walnut and brass turn the lower third into a cockpit and make the main shots
## legible at a glance. None of this has collision; the authored rails remain the truth.
func _draw_playfield_inlay() -> void:
	# Fifth Street bends through the triangular Block, then forks around the bumper
	# neighborhood. These painted routes agree with the actual new shot entrances.
	var street := PackedVector2Array([
		Vector2(190.0, 1468.0), Vector2(790.0, 1468.0),
		Vector2(735.0, 1260.0), Vector2(690.0, 1130.0),
		Vector2(645.0, 960.0), Vector2(470.0, 940.0),
		Vector2(315.0, 1080.0), Vector2(245.0, 1270.0),
	])
	draw_colored_polygon(street, Color(Feel.COL_INK.r, Feel.COL_INK.g, Feel.COL_INK.b, 0.17))
	draw_polyline(PackedVector2Array([
		Vector2(190.0, 1468.0), Vector2(245.0, 1270.0), Vector2(315.0, 1080.0),
		Vector2(470.0, 940.0), Vector2(645.0, 960.0),
	]), Feel.COL_BRASS.darkened(0.62), 3.0)
	draw_polyline(PackedVector2Array([
		Vector2(790.0, 1468.0), Vector2(735.0, 1260.0), Vector2(690.0, 1130.0),
		Vector2(645.0, 960.0),
	]), Feel.COL_BRASS.darkened(0.62), 3.0)
	for p in [Vector2(322.0, 1305.0), Vector2(480.0, 1115.0),
			Vector2(665.0, 1200.0), Vector2(705.0, 1360.0)]:
		draw_line(p - Vector2(18.0, 5.0), p + Vector2(18.0, 5.0),
				Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g,
				Feel.COL_NEWSPRINT.b, 0.13), 4.0)

	# Split walnut apron wings frame the new centre grate instead of painting a false solid
	# floor beneath it. The open V makes the danger legible from either cradle.
	var apron_left := PackedVector2Array([
		Vector2(62.0, 1690.0), Vector2(205.0, 1570.0), Vector2(432.0, 1760.0),
		Vector2(392.0, 1868.0), Vector2(62.0, 1868.0),
	])
	var apron_right := PackedVector2Array([
		Vector2(918.0, 1690.0), Vector2(775.0, 1570.0), Vector2(548.0, 1760.0),
		Vector2(588.0, 1868.0), Vector2(918.0, 1868.0),
	])
	for wing in [apron_left, apron_right]:
		draw_colored_polygon(wing, Color("241710"))
		draw_polyline(PackedVector2Array([wing[0], wing[1], wing[2], wing[3]]),
				Feel.COL_BRASS.darkened(0.48), 5.0)
	for side in [-1.0, 1.0]:
		draw_line(Vector2(MIRROR_X + side * 82.0, 1792.0),
				Vector2(MIRROR_X + side * 335.0, 1818.0),
				Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.22), 3.0)

	# The offset can neighborhood gets a broken ward boundary that opens toward aimed shots.
	draw_arc(Vector2(385.0, 790.0), 172.0, -2.72, 1.22, 36,
			Feel.COL_BRASS.darkened(0.68), 4.0)
	draw_arc(Vector2(385.0, 790.0), 188.0, -2.60, 1.08, 36,
			Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g,
			Feel.COL_NEWSPRINT.b, 0.10), 2.0)

	# The Family seal fills the intentionally open first-Night midfield without pretending to
	# be a switch. Furniture grows over it as the Block is built.
	var seal_at := Vector2(MIRROR_X, 1350.0)
	var seal := PackedVector2Array([
		seal_at + Vector2(0.0, -92.0), seal_at + Vector2(78.0, -48.0),
		seal_at + Vector2(62.0, 54.0), seal_at + Vector2(0.0, 102.0),
		seal_at + Vector2(-62.0, 54.0), seal_at + Vector2(-78.0, -48.0),
	])
	draw_colored_polygon(seal, Color(Feel.COL_INK.r, Feel.COL_INK.g, Feel.COL_INK.b, 0.18))
	draw_polyline(PackedVector2Array([
		seal[0], seal[1], seal[2], seal[3], seal[4], seal[5], seal[0],
	]), Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.14), 3.0)
	draw_line(seal_at + Vector2(-34.0, -42.0), seal_at + Vector2(-34.0, 50.0),
			Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.15), 8.0)
	draw_line(seal_at + Vector2(-28.0, 8.0), seal_at + Vector2(38.0, -44.0),
			Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.15), 8.0)
	draw_line(seal_at + Vector2(-18.0, 1.0), seal_at + Vector2(40.0, 54.0),
			Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.15), 8.0)

	# Quiet print texture: fixed, deterministic, and subtle enough that the ball stays king.
	for i in range(28):
		var x := 188.0 + fmod(float(i) * 137.0, 670.0)
		var y := 646.0 + fmod(float(i) * 211.0, 820.0)
		draw_circle(Vector2(x, y), 2.0 + float(i % 3),
				Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g,
				Feel.COL_NEWSPRINT.b, 0.035))


## The previously empty arch is the machine's backglass: a pulp title card, a deco fan, and
## incandescent chase bulbs. It is the visual reward visible before any furniture is bought.
func _draw_backglass() -> void:
	var plate := PackedVector2Array([
		Vector2(218.0, 136.0), Vector2(762.0, 136.0),
		Vector2(816.0, 400.0), Vector2(164.0, 400.0),
	])
	draw_colored_polygon(plate, Color("17120F"))
	var backglass := Presentation.art.resolve(&"table.backglass.eastport", null, false)
	if backglass != null:
		draw_texture_rect(backglass, Rect2(Vector2(164.0, 136.0), Vector2(652.0, 264.0)),
				false, Color(1.0, 1.0, 1.0, 0.92))
	draw_polyline(PackedVector2Array([
		Vector2(218.0, 136.0), Vector2(762.0, 136.0),
		Vector2(816.0, 400.0), Vector2(164.0, 400.0), Vector2(218.0, 136.0),
	]), Feel.COL_BRASS.darkened(0.28), 6.0)
	var fan_at := Vector2(MIRROR_X, 392.0)
	for i in range(9):
		var x := lerpf(198.0, 782.0, float(i) / 8.0)
		draw_line(fan_at, Vector2(x, 154.0), Color(Feel.COL_BRASS.r,
				Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.18), 3.0)
	draw_arc(fan_at, 236.0, PI + 0.18, TAU - 0.18, 32,
			Feel.COL_BRASS.darkened(0.55), 3.0)

	var font := Presentation.theme.font_for(&"headline")
	if font != null:
		draw_string(font, Vector2(218.0, 274.0), "K I N G P I N",
				HORIZONTAL_ALIGNMENT_CENTER, 544.0, 54, Feel.COL_BRASS)
		draw_string(font, Vector2(218.0, 322.0), "THE FAMILY RUNS THIS TOWN",
				HORIZONTAL_ALIGNMENT_CENTER, 544.0, 20, Feel.COL_NEWSPRINT.darkened(0.18))
		draw_string(font, Vector2(218.0, 362.0), "FIFTH STREET SOCIAL CLUB",
				HORIZONTAL_ALIGNMENT_CENTER, 544.0, 15, Feel.COL_BRASS.darkened(0.35))

	var chase := int(floor(_show_clock * 5.0))
	for i in range(14):
		var top := i < 7
		var u := float(i % 7) / 6.0
		var p := Vector2(lerpf(234.0, 746.0, u), 142.0 if top else 396.0)
		var hot := posmod(i - chase, 5) == 0
		var col := Feel.COL_NEWSPRINT if hot else Feel.COL_BRASS.darkened(0.58)
		draw_circle(p, 5.0 if hot else 3.5, col)


func _draw_shot_labels() -> void:
	var font := Presentation.theme.font_for(&"annotation_bold")
	if font == null:
		return
	# Labels live in dead felt, never over the switch they describe. Their orientation makes
	# the shot lanes readable from the flippers, where the player's eyes actually are.
	draw_string(font, Vector2(220.0, 982.0), "THE RACKET",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Feel.COL_BRASS.darkened(0.34))
	var any_store := false
	for store: Storefront in storefronts:
		any_store = any_store or store.visible
	if any_store:
		draw_string(font, Vector2(410.0, 1360.0), "—  THE BLOCK  —",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Feel.COL_NEWSPRINT.darkened(0.38))
	draw_string(font, Vector2(306.0, 1518.0), "KEEP IT IN THE FAMILY",
			HORIZONTAL_ALIGNMENT_CENTER, 368.0, 15, Feel.COL_BRASS.darkened(0.48))

	if not rollovers.is_empty() and rollovers[0].visible:
		for i in range(3):
			var at: Vector2 = ROLLOVER_AT[i]
			draw_string(font, at + Vector2(-42.0, -18.0), str(i + 1),
					HORIZONTAL_ALIGNMENT_CENTER, 84.0, 17, Feel.COL_BRASS.darkened(0.45))

	if (spinner != null and spinner.visible) or (orbit != null and orbit.visible):
		draw_set_transform(Vector2(103.0, 1125.0), -PI * 0.5, Vector2.ONE)
		draw_string(font, Vector2.ZERO, "NUMBERS  •  GETAWAY",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Feel.COL_BRASS.darkened(0.42))
	if wire_bank != null and wire_bank.visible:
		draw_set_transform(Vector2(882.0, 900.0), -1.91, Vector2.ONE)
		draw_string(font, Vector2.ZERO, "THE WIRE",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Feel.COL_BRASS.darkened(0.42))
	draw_set_transform(Vector2(1007.0, 1710.0), -PI * 0.5, Vector2.ONE)
	draw_string(font, Vector2.ZERO, "DROP-OFF",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Feel.COL_BRASS.darkened(0.38))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
