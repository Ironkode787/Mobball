extends Node2D
## M3 acceptance runner for the TABLE (specs/m3-fall-rise.md TABLE-3).
##
## The M1 growth sim proves the machine is a different table at every rank; the M2 club sim
## proves it has an upstairs. This one proves it has the two rooms M3 adds and that neither of
## them can quietly end a night:
##
##   * the DOCKS are gated — one way in off the numbers lane, and the blade that lets you in
##     still lets a flipped shot up the lane;
##   * the crates pay `smuggling`, the crane warns before it swings, the cargo ramp ships the
##     ball back to midfield, and the pier costs a ball exactly like the storm grate does —
##     with the kickback nowhere near it;
##   * the PENTHOUSE is reachable off the Club's own orbit and never off the staircase, its
##     five chairs switch, the Sit-Down holds for its second, and the way down is a wireform
##     back onto the deck rather than a fall;
##   * the Truck Route is a sequence, not a switch;
##   * the construction animation is a picture only: collision arrives the instant the piece
##     does, and headless runs skip the animation entirely;
##   * the camera reaches the new top of the table and never frames void.
##
## House rules as everywhere else here: physics ticks not wall time, seeded chaos, the real
## `table_main.tscn`, non-zero exit on any failure. The M3 rooms have no Ledger nodes yet
## (game/content is the orchestrator's lane), so they are staged through `force_hardware`.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

## The table's own bounds plus a ball radius of slack; anything outside is an escape.
const BOUND_MIN := Vector2(20.0, -906.0)
const BOUND_MAX := Vector2(1044.0, 1930.0)
const SOAK_SECONDS := 25.0
const SEED := 0x4D334442

const DOCKS_IDS: Array[StringName] = [
	&"docks", &"containers", &"crane", &"cargo_ramp",
]
const CLUB_IDS: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
]
const PENT_IDS: Array[StringName] = [
	&"penthouse", &"commission_chairs", &"sitdown_saucer", &"penthouse_stairs",
]
const ORBIT_R_IDS: Array[StringName] = [&"orbit_right"]

## A Capo's table: everything M1 sells, which is what M3 bolts its rooms onto.
const T3_FIXTURE: Array = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
	"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
	"rackets.the_wire", "influence.beat_cop", "muscle.enforcer_corner",
	"rackets.protection_laundromat", "rackets.protection_pizzeria",
	"rackets.protection_pawn", "rackets.getaway_loop", "muscle.steel_toes",
]

var host: Node2D = null
var table: ProgressionTable = null
var docks: Docks = null
var pent: Penthouse = null
var camera: CameraRig = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

var _earned: Array[Dictionary] = []
var _switches: PackedStringArray = []
var _lost: int = 0
var _entered_docks: int = 0
var _stacks: Array[int] = []
var _telegraphs: int = 0
var _pulls: int = 0
var _shipped: Array[float] = []
var _chairs: Array[int] = []
var _chairs_done: int = 0
var _sitdowns: int = 0
var _pent_in: Array[float] = []
var _pent_out: int = 0
var _orbits: int = 0
var _trucks: int = 0


func _ready() -> void:
	_rng.seed = SEED
	host = Node2D.new()
	host.name = "Host"
	add_child(host)
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	host.add_child(table)
	docks = table.docks
	pent = table.penthouse
	camera = CameraRig.new()
	camera.name = "CameraRig"
	host.add_child(camera)
	table.auto_respawn = false
	table.ball_spawned.connect(func(b: Ball) -> void: camera.set_target(b))

	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		_earned.append({"amount": amount.approx_float(), "group": group}))
	Events.switch_hit.connect(func(id: StringName, _b: Node2D, _s: float) -> void:
		_switches.append(String(id)))
	table.ball_lost.connect(func(_b: Ball) -> void: _lost += 1)
	table.docks_entered.connect(func() -> void: _entered_docks += 1)
	table.container_stack_cleared.connect(func(s: int) -> void: _stacks.append(s))
	table.crane_telegraph.connect(func() -> void: _telegraphs += 1)
	table.crane_pulled.connect(func() -> void: _pulls += 1)
	table.cargo_shipped.connect(func(s: float) -> void: _shipped.append(s))
	table.chair_taken.connect(func(i: int) -> void: _chairs.append(i))
	table.chairs_completed.connect(func() -> void: _chairs_done += 1)
	table.sitdown_entered.connect(func() -> void: _sitdowns += 1)
	table.penthouse_entered.connect(func(s: float) -> void: _pent_in.append(s))
	table.penthouse_returned.connect(func() -> void: _pent_out += 1)
	table.orbit_completed.connect(func() -> void: _orbits += 1)
	table.truck_route_completed.connect(func() -> void: _trucks += 1)
	_run()


# ---------------------------------------------------------------- harness

func ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(Engine.physics_ticks_per_second))))


func step(count: int = 1) -> void:
	for i in range(count):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	await step(ticks(seconds))


func begin(scenario: String) -> void:
	_current = scenario
	_fails = PackedStringArray()


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func near(got: float, want: float, tol: float, msg: String) -> void:
	check(absf(got - want) <= tol, "%s (got %.3f, want %.3f ±%.3f)" % [msg, got, want, tol])


## A gap is a route or a wall, never ball-sized: that is where nights end.
func route_or_wall(gap: float, what: String) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	check(gap >= dia + 20.0 or gap < dia, "%s is %.0f px — ball-sized" % [what, gap])


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if _fails.is_empty() else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


## Untyped `ids` on purpose: concatenating two `Array[StringName]` constants at a call site
## yields a plain Array, and a typed parameter would refuse it.
func use(ids: Array, on: bool = true) -> void:
	Game.stats = FixtureStats.new(T3_FIXTURE)
	table.refresh_hardware()
	table.force_hardware(DOCKS_IDS, false)
	table.force_hardware(CLUB_IDS, false)
	table.force_hardware(PENT_IDS, false)
	table.force_hardware(ORBIT_R_IDS, false)
	if on:
		table.force_hardware(ids, true)
	reset_log()


func reset_log() -> void:
	Game.heat.reset()
	Game.combo.reset()
	_earned.clear()
	_switches = PackedStringArray()
	_stacks.clear()
	_shipped.clear()
	_chairs.clear()
	_pent_in.clear()
	_lost = 0
	_entered_docks = 0
	_telegraphs = 0
	_pulls = 0
	_chairs_done = 0
	_sitdowns = 0
	_pent_out = 0
	_orbits = 0
	_trucks = 0


func hit_switch(id: String) -> bool:
	for s in _switches:
		if s == id:
			return true
	return false


func last_earn_in(group: StringName) -> Dictionary:
	for i in range(_earned.size() - 1, -1, -1):
		if _earned[i]["group"] == group:
			return _earned[i]
	return {}


func earn_count(group: StringName) -> int:
	var n := 0
	for e: Dictionary in _earned:
		if e["group"] == group:
			n += 1
	return n


func drop_at(at: Vector2, velocity: Vector2 = Vector2.ZERO, settle: int = 4) -> Ball:
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	b.place(at)
	if velocity != Vector2.ZERO:
		b.set_velocity(velocity)
	await step(settle)
	return b


## Keep a ball standing exactly where it was put while the clock runs. Used where the thing
## under test is a timer, not a trajectory.
func _hold(b: Ball, at: Vector2, seconds: float) -> void:
	for i in range(ticks(seconds)):
		if b != null and is_instance_valid(b):
			b.place(at)
			b.set_velocity(Vector2.ZERO)
		await step(1)


## Step `seconds`, watching for the two things that end a night quietly.
func watch(seconds: float) -> Dictionary:
	var escapes := 0
	var still := 0
	var still_max := 0
	var still_at := Vector2.ZERO
	var last := Vector2.INF
	var worst := Vector2.ZERO
	for t in range(ticks(seconds)):
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			last = Vector2.INF
			continue
		var p := b.global_position
		if p.x < BOUND_MIN.x or p.x > BOUND_MAX.x or p.y < BOUND_MIN.y or p.y > BOUND_MAX.y:
			escapes += 1
			worst = p
		if last != Vector2.INF and p.distance_to(last) < 0.5 and not BallHold.is_held(b):
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p
	return {
		"escapes": escapes,
		"still": float(still_max) / float(Engine.physics_ticks_per_second),
		"still_at": still_at,
		"worst": worst,
	}


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M3 docks & penthouse sim ==")
	print("physics %d Hz | seed 0x%X | viewport %s"
			% [Engine.physics_ticks_per_second, SEED, str(camera.view_size())])
	await step(4)

	await _s1_dormancy()
	await _s2_docks_geometry()
	await _s3_dock_gate()
	await _s4_containers()
	await _s5_crane()
	await _s6_pier()
	await _s7_cargo_ramp()
	await _s8_penthouse_geometry()
	await _s9_penthouse_stairs()
	await _s10_chairs()
	await _s11_sitdown()
	await _s12_penthouse_return()
	await _s13_truck_route()
	await _s14_construction()
	await _s15_camera()
	await _s16_soak()

	var failed := 0
	for r: Dictionary in _results:
		if not (r["fails"] as PackedStringArray).is_empty():
			failed += 1
	print("---")
	print("scenarios: %d  passed: %d  failed: %d"
			% [_results.size(), _results.size() - failed, failed])
	print("OK" if failed == 0 else "SIM FAILED")
	table.despawn_ball()
	await step(2)
	get_tree().quit(0 if failed == 0 else 1)


## 1 — neither room exists until it is bought, and dormant means gone.
func _s1_dormancy() -> void:
	begin("the Docks and the Penthouse are absent until they are bought")
	use([], false)
	await step(2)
	for id: StringName in DOCKS_IDS + PENT_IDS + ORBIT_R_IDS:
		check(not table.hardware_present(id), "%s is on the table before it is bought" % id)
	check(not docks.is_hardware_active(), "the yard reports itself live")
	check(not pent.is_hardware_active(), "the room reports itself live")
	for piece: Dictionary in table.hardware_pieces():
		var ids: Array[StringName] = piece["ids"]
		if not (DOCKS_IDS.has(ids[0]) or PENT_IDS.has(ids[0])):
			continue
		var node: Node2D = piece["node"]
		check(not node.visible, "%s is visible while dormant" % node.name)
		check(Dormant.is_collision_off(node), "%s is hidden but still collides" % node.name)
	check(Dormant.is_collision_off(docks), "the dormant yard still collides")
	check(Dormant.is_collision_off(pent), "the dormant room still collides")
	near(table.bounds().size.y, ProgressionTable.PLAY_BOTTOM, 0.001,
			"table bounds must not grow before either room")

	# A ball down the numbers lane with no yard built stays in that corridor. At this tier the
	# relocated kickback may save it before it reaches the foot, so downward distance is no
	# longer evidence of dormancy; the entry signal and collision audit above are.
	await drop_at(Vector2(ProgressionTable.SPINNER_AT.x, 1100.0), Vector2(0.0, 900.0))
	await wait(0.45)
	check(_entered_docks == 0, "the yard took a ball before it was built")
	var b := table.ball
	check(b == null or not is_instance_valid(b)
			or b.global_position.x < ProgressionTable.LANE_GUIDE_X,
			"the absent yard displaced the ball out of the numbers corridor")
	table.despawn_ball()
	finish()

	begin("buying the rooms puts them on the table")
	use(DOCKS_IDS)
	await step(2)
	for id: StringName in DOCKS_IDS:
		check(table.hardware_present(id), "%s did not arrive with the yard" % id)
	check(docks.is_hardware_active(), "the yard is not live")

	# the Penthouse hangs off the Club: no deck, no room, however hard you force it
	use(PENT_IDS)
	await step(2)
	check(not table.hardware_present(&"penthouse"),
			"the Penthouse stood up with no Club under it")
	use(CLUB_IDS + PENT_IDS)
	await step(2)
	for id: StringName in PENT_IDS:
		check(table.hardware_present(id), "%s did not arrive with the room" % id)
	check(pent.is_hardware_active(), "the room is not live")
	near(table.bounds().position.y, Penthouse.ROOM_TOP - Penthouse.WALL_THICK * 0.5, 0.001,
			"table bounds grew to the Penthouse ceiling")
	print("        yard %s | room %s" % [str(docks.bounds()), str(pent.bounds())])
	finish()


## 2 — the yard's numbers. Every lane in it is a route or a wall, the rakes all outrun wall
## friction, and the crate deck opens a real hole when a stack goes down.
func _s2_docks_geometry() -> void:
	begin("docks geometry: parallel rakes, no ball-sized gap")
	var dia := Feel.BALL_RADIUS * 2.0
	var rake := tan(deg_to_rad(Docks.RAKE_DEG))
	check(rake > Feel.WALL_FRICTION + 0.05,
			"the yard's rake (%.3f) must outrun wall friction (%.2f)" % [rake, Feel.WALL_FRICTION])
	var roof_slope: float = (Docks.ROOF_TO.y - Docks.ROOF_FROM.y) \
			/ (Docks.ROOF_TO.x - Docks.ROOF_FROM.x)
	var quay_slope: float = (Docks.QUAY_TO.y - Docks.QUAY_FROM.y) \
			/ (Docks.QUAY_TO.x - Docks.QUAY_FROM.x)
	near(roof_slope, rake, 0.02, "the roof carries the yard's rake")
	near(quay_slope, rake, 0.03, "the quay carries the yard's rake")
	var blade_slope: float = (Docks.BLADE_TO.y - Docks.BLADE_FROM.y) \
			/ (Docks.BLADE_TO.x - Docks.BLADE_FROM.x)
	check(blade_slope > rake, "the dock gate (%.3f) must tip harder than the yard" % blade_slope)

	check(Docks.MOUTH_BOTTOM - Docks.MOUTH_TOP >= dia + 20.0,
			"the dock mouth is %.0f px" % (Docks.MOUTH_BOTTOM - Docks.MOUTH_TOP))

	# a crate lid is a wall surface, and it has to shed a ball on its own account
	check(tan(deg_to_rad(ContainerStacks.CRATE_RAKE_DEG)) > Feel.WALL_FRICTION + 0.15,
			"a crate lid is raked only %.0f°" % ContainerStacks.CRATE_RAKE_DEG)

	# headroom over the crate deck and the lane under it, both measured at each end
	var half := (ContainerStacks.CRATE_LENGTH + ContainerStacks.CRATE_THICK) * 0.5
	var deck_half_y := ContainerStacks.half_extent_y()
	for i: int in [0, ContainerStacks.STACKS * ContainerStacks.PER_STACK - 1]:
		var s: int = i / ContainerStacks.PER_STACK
		var c: int = i % ContainerStacks.PER_STACK
		var crate: DropTarget = docks.containers.target_at(s, c)
		var x: float = crate.global_position.x
		var roof_face: float = Docks.ROOF_FROM.y + (x - Docks.ROOF_FROM.x) * roof_slope \
				+ Docks.WALL_THICK * 0.5
		var head: float = (crate.global_position.y - deck_half_y) - roof_face
		route_or_wall(head, "headroom over crate %d" % (i + 1))
		if x <= Docks.QUAY_TO.x:
			var quay_face: float = Docks.QUAY_FROM.y + (x - Docks.QUAY_FROM.x) * quay_slope - 10.0
			var lane: float = quay_face - (crate.global_position.y + deck_half_y)
			route_or_wall(lane, "lane under crate %d" % (i + 1))

	# the standing deck is sealed, and a cleared stack is a route
	var span := half * cos(deg_to_rad(ContainerStacks.CRATE_RAKE_DEG))
	var xs: PackedFloat32Array = []
	for s in range(ContainerStacks.STACKS):
		for c in range(ContainerStacks.PER_STACK):
			xs.append(docks.containers.target_at(s, c).global_position.x)
	for i in range(xs.size() - 1):
		check(xs[i + 1] - xs[i] - span * 2.0 < dia,
				"crates %d/%d leave a %.0f px slot" % [i + 1, i + 2, xs[i + 1] - xs[i] - span * 2.0])
	var wall_l: float = Docks.LEFT_LOW_FROM.x + Docks.GUIDE_THICK * 0.5
	var wall_r: float = Docks.RIGHT_FROM.x - Docks.WALL_THICK * 0.5
	check(xs[0] - span - wall_l < dia, "the deck leaves a slot against the left wall")
	check(wall_r - (xs[xs.size() - 1] + span) < dia, "the deck leaves a slot against the wall")
	for s in range(ContainerStacks.STACKS):
		var lo: float = wall_l if s == 0 else xs[s * 2 - 1] + span
		var hi: float = wall_r if s == ContainerStacks.STACKS - 1 else xs[s * 2 + 2] - span
		check(hi - lo >= dia + 20.0,
				"clearing stack %d opens only %.0f px" % [s + 1, hi - lo])

	# the harbour has to hold a ball, and the pier has to be nowhere near the kickback
	check(Docks.WATER_SIZE.x >= dia and Docks.WATER_SIZE.y >= dia,
			"the harbour (%s) is smaller than a ball" % str(Docks.WATER_SIZE))
	var water := Rect2(Docks.WATER_AT - Docks.WATER_SIZE * 0.5, Docks.WATER_SIZE)
	var kick := Rect2(ProgressionTable.KICKBACK_AT - ProgressionTable.KICKBACK_SIZE * 0.5,
			ProgressionTable.KICKBACK_SIZE)
	check(not water.intersects(kick.grow(Feel.BALL_RADIUS)),
			"the kickback reaches the pier — it must never cover it")
	check(water.position.x > ProgressionTable.OUTLANE_X,
			"the harbour hangs over the left outlane")
	# ...and the yard must leave the slingshot its sky
	check(Docks.BED_FROM.y + Docks.BED_THICK * 0.5 < ProgressionTable.SLING_OUTER_TOP.y - 20.0,
			"the harbour bed sits on the slingshot's tip")
	print("        rake %.3f | mouth %.0f | harbour %s | bed→sling %.0f"
			% [rake, Docks.MOUTH_BOTTOM - Docks.MOUTH_TOP, str(Docks.WATER_SIZE),
			ProgressionTable.SLING_OUTER_TOP.y - Docks.BED_FROM.y])
	finish()


## 3 — the gate. Down the numbers lane goes into the yard; up the numbers lane still works;
## and nothing in the yard climbs back into the lane.
func _s3_dock_gate() -> void:
	begin("the dock gate is one-way off the numbers lane")
	use(DOCKS_IDS)
	await drop_at(Vector2(ProgressionTable.SPINNER_AT.x, 1080.0), Vector2(0.0, 700.0))
	var arrived := false
	for i in range(ticks(2.5)):
		await step(1)
		if _entered_docks > 0:
			arrived = true
			break
	check(arrived, "a ball down the numbers lane never reached the yard")
	var b := table.ball
	if b != null and is_instance_valid(b):
		check(docks.yard_rect().has_point(b.global_position),
				"the ball ended up at %s, outside the yard" % str(b.global_position))
	table.despawn_ball()

	# A flipped shot up the lane passes the blade instead of bouncing off it. Measured over the
	# climb only: what comes *down* the lane afterwards is the yard's, by design.
	reset_log()
	await drop_at(Vector2(103.0, 1400.0), Vector2(0.0, -1800.0))
	var top := INF
	for i in range(ticks(0.45)):
		await step(1)
		var s := table.ball
		if s != null and is_instance_valid(s):
			top = minf(top, s.global_position.y)
	check(top < Docks.BLADE_FROM.y - 120.0,
			"a shot up the numbers lane stopped at y=%.0f — the blade blocked it" % top)
	check(_entered_docks == 0, "a shot up the lane was swallowed by the yard on the way up")
	table.despawn_ball()

	# from inside the yard the blade is solid: whatever squirts back out of the mouth lands on
	# it and is tipped in again, so nothing ever gets up the numbers lane from the yard
	reset_log()
	await drop_at(Vector2(210.0, 1215.0), Vector2(-1100.0, -800.0))
	var highest := INF
	for i in range(ticks(2.0)):
		await step(1)
		var e := table.ball
		if e == null or not is_instance_valid(e):
			break
		if e.global_position.x < Docks.LEFT_LOW_FROM.x:
			highest = minf(highest, e.global_position.y)
	check(highest > Docks.BLADE_FROM.y - 60.0,
			"a ball climbed out of the yard and up the numbers lane to y=%.0f" % highest)
	table.despawn_ball()
	print("        in off the lane, up the lane still clears, no way back up")
	finish()


## 4 — the cargo. Crates pay `smuggling`, a stack is a two-shot sequence, and stacks come
## back on their own clock.
func _s4_containers() -> void:
	begin("containers pay smuggling and reset per stack")
	use(DOCKS_IDS)
	var stacks := docks.containers
	stacks.reset_now()
	await step(2)
	for c in range(ContainerStacks.PER_STACK):
		var t := stacks.target_at(1, c)
		await drop_at(t.to_global(Vector2(0.0, 40.0)))
		await step(3)
	check(stacks.stack_is_clear(1), "the middle stack did not clear (%d down)"
			% stacks.stack_down(1))
	check(not stacks.stack_is_clear(0) and not stacks.stack_is_clear(2),
			"clearing one stack took the others with it")
	check(earn_count(TableScore.GROUP_SMUGGLING) == ContainerStacks.PER_STACK,
			"%d payouts for %d crates"
			% [earn_count(TableScore.GROUP_SMUGGLING), ContainerStacks.PER_STACK])
	var pay := last_earn_in(TableScore.GROUP_SMUGGLING)
	near(float(pay.get("amount", 0.0)), TableScore.SMUGGLING_CONTAINER, 0.001, "a crate pays")
	check(_stacks.size() == 1 and _stacks[0] == 1, "stack_cleared reported %s" % str(_stacks))
	var closes := 0
	for s in _switches:
		if s.begins_with("containers_2"):
			closes += 1
	check(closes == ContainerStacks.PER_STACK,
			"%d switch closures for %d crates" % [closes, ContainerStacks.PER_STACK])

	table.despawn_ball()
	await wait(stacks.reset_seconds * 0.5)
	check(stacks.stack_is_clear(1), "the stack came back up early")
	await wait(stacks.reset_seconds * 0.6 + 0.3)
	check(not stacks.stack_is_clear(1), "the stack never came back up")
	print("        stack 2: %d × $%d, cleared, back up after %.1fs"
			% [ContainerStacks.PER_STACK, int(TableScore.SMUGGLING_CONTAINER),
			stacks.reset_seconds])
	finish()


## 5 — the crane warns before it swings, only reaches inside the yard, and swings toward the
## water rather than anywhere else.
func _s5_crane() -> void:
	begin("crane: 1.2 s telegraph, yard-only reach, pull toward the harbour")
	use(DOCKS_IDS)
	var crane := docks.crane
	check(crane.active, "the crane is not running with the yard built")
	check(not crane.is_telegraphing(), "the crane telegraphed immediately")
	crane.self_driven = false

	# out of the yard is out of reach: no force field on the main playfield
	await drop_at(Vector2(600.0, 1000.0))
	check(not crane.has_target(), "the crane reached a ball on the main field")
	check(not crane.pull(), "the crane pulled a ball that was not in the yard")
	table.despawn_ball()

	# Pinned in place while the hook winds up: this is about the telegraph, and a free ball in
	# the yard would have rolled onto the hoist and left long before the crane was ready.
	var at := Vector2(230.0, 1300.0)
	var b := await drop_at(at)
	check(crane.has_target(), "the crane cannot see a ball standing in its own yard")
	await _hold(b, at, CraneMagnet.PERIOD - CraneMagnet.TELEGRAPH - 0.6)
	check(not crane.is_telegraphing(), "the crane telegraphed too early")
	await _hold(b, at, 0.9)
	check(crane.is_telegraphing(), "no %.1fs telegraph before the swing" % CraneMagnet.TELEGRAPH)
	check(_telegraphs >= 1, "the telegraph was never reported")
	# the trolley parks over the ball it is winding up on
	check(absf(crane.trolley_position().x - at.x) < 60.0,
			"the gantry did not travel to the ball (trolley at %s, ball at %s)"
			% [str(crane.trolley_position()), str(at)])

	b = table.ball
	check(b != null and is_instance_valid(b), "the yard lost the ball while the hook wound up")
	if b == null or not is_instance_valid(b):
		crane.self_driven = true
		finish()
		return
	b.place(at)
	b.set_velocity(Vector2.ZERO)
	await step(1)
	var before := b.linear_velocity
	check(crane.pull(), "the crane refused to swing")
	await step(1)
	var toward := (Docks.WATER_AT - at).normalized()
	check(b.linear_velocity.dot(toward) > before.dot(toward) + 200.0,
			"the swing did not drag the ball toward the harbour")
	check(_pulls >= 1, "the swing was never reported")
	crane.self_driven = true
	table.despawn_ball()
	print("        telegraph %.1fs, trolley tracks the ball, swing is harbour-ward"
			% CraneMagnet.TELEGRAPH)
	finish()


## 6 — the pier. It pinches exactly like the storm grate: one ball_lost, one drain event, and
## no kickback anywhere near it.
func _s6_pier() -> void:
	begin("the pier is a real drain and the kickback never covers it")
	use(DOCKS_IDS)
	table.kickback.recharge()
	var fired := [0]
	var tap := func() -> void: fired[0] += 1
	table.kickback.fired.connect(tap)
	var drained := [0]
	var drain_tap := func(_b: Node2D) -> void: drained[0] += 1
	Events.ball_drained.connect(drain_tap)

	await drop_at(Docks.WATER_AT + Vector2(0.0, -20.0), Vector2(0.0, 300.0))
	var gone := false
	for i in range(ticks(1.5)):
		await step(1)
		if _lost > 0:
			gone = true
			break
	check(gone, "a ball off the pier was not lost")
	check(_lost == 1, "the pier reported %d losses for one ball" % _lost)
	check(int(drained[0]) == 1, "the pier did not emit ball_drained like a drain does")
	check(table.ball == null or not is_instance_valid(table.ball),
			"the ball survived the harbour")
	check(int(fired[0]) == 0, "the kickback fired for a pier fall")
	check(table.kickback.ready_to_fire(), "the pier fall burned the kickback's charge")
	table.kickback.fired.disconnect(tap)
	Events.ball_drained.disconnect(drain_tap)

	# and with the yard unbought, that water is not there to fall into
	use([], false)
	await drop_at(Docks.WATER_AT, Vector2.ZERO)
	await wait(0.4)
	check(_lost == 0, "the dormant pier still swallowed a ball")
	table.despawn_ball()
	print("        one ball_lost + one ball_drained, kickback untouched and still charged")
	finish()


## 7 — the cargo ramp. Roll off the deck with pace and the hoist ships the ball to midfield;
## dribble and the harbour takes it.
func _s7_cargo_ramp() -> void:
	begin("the cargo ramp ships the ball back to midfield")
	use(DOCKS_IDS)
	var ramp := docks.cargo_ramp
	var need := ramp.required_entry_speed()
	check(Docks.CARGO_ENTRY_SPEED > need + 150.0,
			"the hoist's gate (%.0f) must sit clear of the climb it demands (%.0f)"
			% [Docks.CARGO_ENTRY_SPEED, need])

	var tangent := ramp.tangent_at(4.0)
	await drop_at(Docks.CARGO_MOUTH_AT - tangent * 30.0,
			tangent * (Docks.CARGO_ENTRY_SPEED + 260.0))
	var rode := false
	for i in range(ticks(1.0)):
		await step(1)
		if ramp.riding():
			rode = true
			break
	check(rode, "the hoist did not take a %.0f px/s roll"
			% (Docks.CARGO_ENTRY_SPEED + 260.0))
	check(hit_switch("cargo_ramp_entry"), "no cargo_ramp_entry switch")
	var shipped := false
	for i in range(ticks(6.0)):
		await step(1)
		if not _shipped.is_empty():
			shipped = true
			break
	check(shipped, "the load never made it out of the yard")
	var b := table.ball
	check(b != null and is_instance_valid(b), "the ball was lost on the hoist")
	if b != null and is_instance_valid(b):
		check(b.collision_layer == Feel.LAYER_BALL, "delivered still lifted off the table")
		var mid: Vector2 = table.socket(&"midfield")
		check(b.global_position.distance_to(mid) < 220.0,
				"delivered at %s, not at midfield %s" % [str(b.global_position), str(mid)])
		check(not docks.yard_rect().has_point(b.global_position),
				"the hoist put the ball back inside the yard")
	var pay := last_earn_in(TableScore.GROUP_RAMPS)
	near(float(pay.get("amount", 0.0)), TableScore.RAMP_CLIMB, 0.001, "a shipped load pays")
	var w := await watch(1.5)
	check(int(w["escapes"]) == 0, "the delivered ball left the table")

	# too slow for the hoist: the mouth simply is not taken
	reset_log()
	await drop_at(Docks.CARGO_MOUTH_AT - tangent * 30.0,
			tangent * (Docks.CARGO_ENTRY_SPEED - 200.0))
	await wait(0.4)
	check(not ramp.riding(), "the hoist took a %.0f px/s dribble"
			% (Docks.CARGO_ENTRY_SPEED - 200.0))
	table.despawn_ball()
	print("        gate %.0f (needs %.0f) | shipped to midfield, dribbles refused"
			% [Docks.CARGO_ENTRY_SPEED, need])
	finish()


## 8 — the Penthouse's numbers: five chairs that leave real routes between them, a floor that
## sheds both ways, and a room that fits a ball everywhere it can go.
func _s8_penthouse_geometry() -> void:
	begin("penthouse geometry: offset chair rows, a ridge floor, no ball-sized gap")
	var dia := Feel.BALL_RADIUS * 2.0
	var inner_l: float = Penthouse.ROOM_LEFT + Penthouse.WALL_THICK * 0.5
	var inner_r: float = Penthouse.ROOM_RIGHT - Penthouse.WALL_THICK * 0.5
	check(pent.chairs.targets().size() == 5,
			"the Commission has %d chairs" % pent.chairs.targets().size())

	var half: float = (Penthouse.CHAIR_LENGTH + Penthouse.CHAIR_THICK) * 0.5
	for row: Array in [[Penthouse.CHAIR_ROW_A_X, Penthouse.CHAIR_ROW_A_RAKE],
			[Penthouse.CHAIR_ROW_B_X, Penthouse.CHAIR_ROW_B_RAKE]]:
		var xs: PackedFloat32Array = row[0]
		var rakes: PackedFloat32Array = row[1]
		var edges: Array[Vector2] = []
		for i in range(xs.size()):
			var reach: float = half * cos(deg_to_rad(rakes[i]))
			edges.append(Vector2(xs[i] - reach, xs[i] + reach))
			# A chair is a standup, so it is rubber: its rake has to outrun 0.30, not 0.14.
			check(tan(deg_to_rad(absf(rakes[i]))) > Feel.RUBBER_FRICTION + 0.05,
					"chair at x=%.0f is raked only %.0f° — a ball parks on its back"
					% [xs[i], absf(rakes[i])])
		route_or_wall(edges[0].x - inner_l, "the lane left of the row")
		route_or_wall(inner_r - edges[edges.size() - 1].y, "the lane right of the row")
		for i in range(edges.size() - 1):
			route_or_wall(edges[i + 1].x - edges[i].y, "the gap between two chairs")

	# the two rows must not line up, or the room is a chute rather than a shot
	for a: float in Penthouse.CHAIR_ROW_A_X:
		for b: float in Penthouse.CHAIR_ROW_B_X:
			check(absf(a - b) > half, "chairs at x=%.0f in both rows line up" % a)

	var left_rake: float = absf(Penthouse.FLOOR_APEX.y - Penthouse.FLOOR_LEFT.y) \
			/ absf(Penthouse.FLOOR_APEX.x - Penthouse.FLOOR_LEFT.x)
	var right_rake: float = absf(Penthouse.FLOOR_APEX.y - Penthouse.FLOOR_RIGHT.y) \
			/ absf(Penthouse.FLOOR_RIGHT.x - Penthouse.FLOOR_APEX.x)
	check(left_rake > Feel.WALL_FRICTION + 0.05,
			"the floor's Sit-Down side (%.3f) holds the ball" % left_rake)
	check(right_rake > Feel.WALL_FRICTION + 0.05,
			"the floor's return side (%.3f) holds the ball" % right_rake)
	check(Penthouse.FLOOR_APEX.y < Penthouse.FLOOR_LEFT.y
			and Penthouse.FLOOR_APEX.y < Penthouse.FLOOR_RIGHT.y,
			"the floor is a bowl, not a ridge — a ball would sit in the middle of the room")
	check(Penthouse.ROOM_BOTTOM <= -460.0 and Penthouse.ROOM_TOP >= -880.0,
			"the room is outside the spec's y band")
	check(Penthouse.ROOM_RIGHT <= ClubDeck.DECK_LEFT,
			"the room overlaps the Club deck")
	# the Sit-Down has to sit in the floor it is fed by
	var floor_y: float = Penthouse.FLOOR_LEFT.y + (Penthouse.SITDOWN_AT.x - Penthouse.FLOOR_LEFT.x) \
			* (Penthouse.FLOOR_APEX.y - Penthouse.FLOOR_LEFT.y) \
			/ (Penthouse.FLOOR_APEX.x - Penthouse.FLOOR_LEFT.x)
	var ball_y: float = floor_y - Penthouse.FLOOR_THICK * 0.5 - Feel.BALL_RADIUS
	check(absf(ball_y - Penthouse.SITDOWN_AT.y) < Penthouse.SITDOWN_R - 6.0,
			"a ball rolling to the low end misses the Sit-Down by %.0f px"
			% absf(ball_y - Penthouse.SITDOWN_AT.y))
	print("        5 chairs, rows offset | floor ridge %.2f/%.2f | room %.0f×%.0f"
			% [left_rake, right_rake, Penthouse.ROOM_RIGHT - Penthouse.ROOM_LEFT,
			Penthouse.ROOM_BOTTOM - Penthouse.ROOM_TOP])
	finish()


## 9 — the way up. A lap of the Club's ceiling channel with pace left in it takes the room;
## a staircase arrival is far too slow and still feeds the wheel.
func _s9_penthouse_stairs() -> void:
	begin("penthouse stairs: a lap climbs, a staircase arrival does not")
	use(CLUB_IDS + PENT_IDS)
	var stairs := pent.stairs
	var need := stairs.required_entry_speed()
	check(Penthouse.STAIR_ENTRY_SPEED > need + 150.0,
			"the gate (%.0f) must sit clear of the climb it demands (%.0f)"
			% [Penthouse.STAIR_ENTRY_SPEED, need])
	check(Penthouse.STAIR_ENTRY_SPEED > ClubDeck.STAIR_RELEASE_SPEED + 200.0,
			"a staircase arrival (%.0f) would be swallowed by the Penthouse ramp"
			% ClubDeck.STAIR_RELEASE_SPEED)

	await drop_at(Penthouse.STAIR_MOUTH + Vector2(120.0, 0.0),
			Vector2(-(Penthouse.STAIR_ENTRY_SPEED + 260.0), 0.0))
	var climbed := false
	for i in range(ticks(4.0)):
		await step(1)
		if not _pent_in.is_empty():
			climbed = true
			break
	check(climbed, "a lap with pace never reached the Penthouse")
	check(hit_switch("penthouse_stairs_entry"), "no entry switch")
	var b := table.ball
	if b != null and is_instance_valid(b):
		check(pent.bounds().grow(60.0).has_point(b.global_position),
				"the ball did not arrive in the room (at %s)" % str(b.global_position))
		check(b.collision_layer == Feel.LAYER_BALL, "handed to the room still lifted")
	var pay := last_earn_in(TableScore.GROUP_RAMPS)
	near(float(pay.get("amount", 0.0)), TableScore.RAMP_CLIMB, 0.001, "a completed climb pays")
	table.despawn_ball()

	reset_log()
	await drop_at(Penthouse.STAIR_MOUTH + Vector2(120.0, 0.0),
			Vector2(-ClubDeck.STAIR_RELEASE_SPEED, 0.0))
	await wait(0.6)
	check(_pent_in.is_empty(), "a staircase-speed arrival was taken up to the Penthouse")
	check(not stairs.riding(), "the mouth took a ball it should have let past")
	table.despawn_ball()
	print("        gate %.0f (needs %.0f) — a staircase arrival at %.0f is refused"
			% [Penthouse.STAIR_ENTRY_SPEED, need, ClubDeck.STAIR_RELEASE_SPEED])
	finish()


## 10 — five chairs, five switches, one Commission.
func _s10_chairs() -> void:
	begin("the Commission's five chairs switch and pay")
	use(CLUB_IDS + PENT_IDS)
	pent.chairs.reset_now()
	await step(2)
	var first: StandupTarget = pent.chairs.targets()[0]
	await drop_at(first.to_global(Vector2(0.0, 36.0)))
	await step(3)
	check(hit_switch(String(first.id)), "hitting a chair produced no switch")
	var pay := last_earn_in(TableScore.GROUP_PENTHOUSE)
	check(String(pay.get("group", "")) == "penthouse", "a chair paid the wrong group")
	near(float(pay.get("amount", 0.0)), TableScore.PENTHOUSE_CHAIR, 0.001, "a chair pays")
	check(_chairs.size() == 1 and _chairs[0] == 0, "chair_taken reported %s" % str(_chairs))
	check(pent.chairs_standing() == 4, "%d chairs still standing" % pent.chairs_standing())

	for i in range(1, pent.chairs.targets().size()):
		var t: StandupTarget = pent.chairs.targets()[i]
		await drop_at(t.to_global(Vector2(0.0, 36.0)))
		await step(3)
	check(pent.chairs.is_complete(), "five chairs down did not seat the Commission")
	check(_chairs_done == 1, "chairs_completed fired %d times" % _chairs_done)
	check(pent.chairs_standing() == 0, "%d chairs left standing" % pent.chairs_standing())
	check(earn_count(TableScore.GROUP_PENTHOUSE) == 5,
			"%d payouts for 5 chairs" % earn_count(TableScore.GROUP_PENTHOUSE))
	table.despawn_ball()
	await wait(pent.chairs.reset_seconds + 0.3)
	check(pent.chairs.marked_count() == 0, "the chairs never stood back up")
	print("        5 × $%d in group `penthouse`, Commission seated, chairs reset"
			% int(TableScore.PENTHOUSE_CHAIR))
	finish()


## 11 — the Sit-Down: a one-second capture, a signal, and always a kick-out.
func _s11_sitdown() -> void:
	begin("the Sit-Down holds for a second and always lets go")
	use(CLUB_IDS + PENT_IDS)
	var saucer := pent.sitdown
	near(saucer.hold_seconds, 1.0, 0.001, "the Sit-Down's capture is 1 s")
	await drop_at(Penthouse.SITDOWN_AT, Vector2.ZERO)
	await step(3)
	check(_sitdowns == 1, "sitdown_entered fired %d times" % _sitdowns)
	check(saucer.holds_ball(), "the Sit-Down did not take the ball")
	check(hit_switch(String(Penthouse.ID_SITDOWN)), "the Sit-Down reported no switch")
	check(earn_count(TableScore.GROUP_PENTHOUSE) == 0,
			"the capture paid money — flow owns the negotiation, not the table")
	await wait(saucer.hold_seconds * 0.5)
	check(saucer.holds_ball(), "the Sit-Down let go early")
	var kicked := 0.0
	for i in range(ticks(saucer.hold_seconds + 0.5)):
		await step(1)
		if not saucer.holds_ball():
			kicked = table.ball.speed()
			break
	check(not saucer.holds_ball(), "the Sit-Down never let go")
	check(table.ball.collision_layer == Feel.LAYER_BALL, "handed back still lifted")
	check(kicked > 400.0, "handed back at %.0f px/s — no kick" % kicked)
	var w := await watch(1.5)
	check(int(w["escapes"]) == 0, "the ejected ball left the room")
	table.despawn_ball()
	print("        held %.1fs, kicked out at %.0f px/s" % [saucer.hold_seconds, kicked])
	finish()


## 12 — the way down. Everything that reaches the room's down-field lip is caught and put
## back on the Club deck, in play, never on the drain line.
func _s12_penthouse_return() -> void:
	begin("the Penthouse return puts the ball back on the deck")
	use(CLUB_IDS + PENT_IDS)
	await drop_at(Penthouse.RETURN_CATCH_AT, Vector2(120.0, 60.0))
	var caught := false
	for i in range(ticks(1.5)):
		await step(1)
		if pent.return_lane.riding():
			caught = true
			break
	check(caught, "a ball at the room's lip was not caught by the return")
	var home := false
	var landed := Vector2.ZERO
	for i in range(ticks(5.0)):
		await step(1)
		if _pent_out > 0:
			home = true
			landed = table.ball.global_position if table.ball != null else Vector2.ZERO
			break
	check(home, "the return never delivered the ball")
	check(_pent_out == 1, "the return fired %d times" % _pent_out)
	if home:
		var b := table.ball
		check(b.collision_layer == Feel.LAYER_BALL, "delivered still lifted off the table")
		check(club_bounds().grow(80.0).has_point(landed),
				"delivered at %s — that is not the Club deck" % str(landed))
		check(landed.y < 0.0, "delivered downstairs at y=%.0f" % landed.y)
		check(b.speed() <= Penthouse.RETURN_RELEASE_SPEED + 80.0,
				"delivered at %.0f px/s — a wireform does not fire the ball out" % b.speed())
	var w := await watch(2.0)
	check(int(w["escapes"]) == 0, "the delivered ball left the table")
	table.despawn_ball()
	print("        caught at the lip, delivered to %s at %.0f px/s"
			% [str(landed), Penthouse.RETURN_RELEASE_SPEED])
	finish()


func club_bounds() -> Rect2:
	return table.club.bounds()


## 13 — the Truck Route is a sequence: enter low in the corridor, still be there at the top.
func _s13_truck_route() -> void:
	begin("the Truck Route pays on entry→exit, never on either alone")
	use(ORBIT_R_IDS)
	check(table.hardware_present(&"orbit_right"), "the Truck Route did not arrive")
	await _right_orbit_run()
	check(_orbits == 1, "a full traverse scored %d orbits" % _orbits)
	check(_trucks == 1, "the Truck Route reported itself %d times" % _trucks)
	check(hit_switch("orbit_right_entry"), "the entry gate never reported")
	check(hit_switch("orbit_right"), "no orbit_right switch")
	var pay := last_earn_in(TableScore.GROUP_ORBIT)
	check(String(pay.get("group", "")) == "orbit", "the Truck Route paid the wrong group")
	check(float(pay.get("amount", 0.0)) >= TableScore.ORBIT,
			"the Truck Route paid %.0f, under the orbit base %d"
			% [float(pay.get("amount", 0.0)), int(TableScore.ORBIT)])

	reset_log()
	table.despawn_ball()
	await wait(OrbitLane.WINDOW + 0.5)
	await drop_at(table.orbit_right.exit_position())
	await step(3)
	check(_orbits == 0, "the exit gate alone counted as a loop")
	table.despawn_ball()

	reset_log()
	await drop_at(table.orbit_right.entry_position())
	await step(3)
	table.despawn_ball()
	await wait(OrbitLane.WINDOW + 0.4)
	await drop_at(table.orbit_right.exit_position())
	await step(3)
	check(_orbits == 0, "a stale entry still paid a loop %.1fs later" % OrbitLane.WINDOW)
	table.despawn_ball()

	# and the left orbit must still be its own switch
	reset_log()
	use([&"orbit_right"], false)
	await drop_at(table.orbit_right.entry_position())
	await step(3)
	check(not hit_switch("orbit_right_entry"), "a dormant Truck Route still switched")
	table.despawn_ball()
	print("        entry→exit pays, exit alone and a lapsed entry do not")
	finish()


func _right_orbit_run() -> void:
	reset_log()
	await drop_at(table.orbit_right.entry_position())
	await step(3)
	var b := table.ball
	if b != null and is_instance_valid(b):
		b.place(table.orbit_right.exit_position())
	await step(4)
	table.despawn_ball()


## 14 — construction. The crew is a picture: collision is live from the first frame, the fade
## finishes, and headless runs never see it at all.
func _s14_construction() -> void:
	begin("the build-in is cosmetic and headless runs skip it")
	use([], false)
	await step(2)
	check(not table.construction.enabled,
			"a headless run must not animate purchases — sim timings ride on that")
	table.force_hardware(DOCKS_IDS, true)
	await step(2)
	check(table.construction.building() == 0, "the crew turned out on a headless run")
	var shell_node: Node = table.hardware_node(&"containers")
	near((shell_node as Node2D).modulate.a, 1.0, 0.001,
			"a piece built with the animation off is not fully drawn")

	# now with the animation on: collision has to be there from the first tick
	use([], false)
	await step(2)
	table.construction.enabled = true
	table.force_hardware(DOCKS_IDS, true)
	await step(1)
	var crates: ContainerStacks = table.hardware_node(&"containers")
	check(table.construction.building() > 0, "the crew never turned out")
	check(crates.visible, "the piece is not on the table while it is being built")
	check(not Dormant.is_collision_off(crates),
			"collision arrived late — half-on hardware is the worst state a table can be in")
	check(crates.modulate.a < 1.0, "nothing faded in")
	await wait(BuildIn.DURATION * 0.5)
	check(crates.modulate.a > 0.1, "the fade is not moving")
	await wait(BuildIn.DURATION * 0.6 + 0.2)
	near(crates.modulate.a, 1.0, 0.001, "the piece never finished building")
	check(table.construction.building() == 0, "the crew never went home")

	# switching a piece off mid-build must not leave a ghost
	table.force_hardware(DOCKS_IDS, false)
	await step(1)
	table.force_hardware(DOCKS_IDS, true)
	await step(2)
	table.force_hardware(DOCKS_IDS, false)
	await step(2)
	near(crates.modulate.a, 1.0, 0.001, "a cancelled build left the piece half-faded")
	table.construction.enabled = false
	table.construction.finish_all()
	print("        %.1fs build-in, collision from tick one, off under --headless"
			% BuildIn.DURATION)
	finish()


## 15 — the camera. The table is taller again; it has to reach the Penthouse ceiling and
## still never frame a pixel of nothing.
func _s15_camera() -> void:
	begin("camera: reaches the Penthouse and never shows void")
	use(CLUB_IDS + PENT_IDS + DOCKS_IDS)
	await step(2)
	var bounds := table.bounds()
	near(bounds.position.y, Penthouse.ROOM_TOP - Penthouse.WALL_THICK * 0.5, 0.001,
			"the table's top is the Penthouse ceiling")
	var top_seen := INF
	var bottom_seen := -INF
	var void_frames := 0
	var legs: Array = [
		Vector2(276.0, -820.0), Vector2(430.0, -540.0), Vector2(880.0, -560.0),
		Vector2(230.0, 1280.0), Vector2(490.0, 1700.0),
	]
	for at: Vector2 in legs:
		await drop_at(at)
		for i in range(ticks(1.4)):
			if table.ball != null and is_instance_valid(table.ball):
				table.ball.place(at)
			await step(1)
			var r := camera.view_rect()
			top_seen = minf(top_seen, r.position.y)
			bottom_seen = maxf(bottom_seen, r.end.y)
			if r.position.y < bounds.position.y - 0.5 or r.end.y > bounds.end.y + 0.5:
				void_frames += 1
		if at.y < Penthouse.ROOM_BOTTOM:
			var rc := camera.view_rect()
			check(rc.position.y <= Penthouse.ROOM_TOP + 1.0,
					"the Penthouse ceiling is off screen with the ball in the room (view %s)"
					% str(rc))
	check(void_frames == 0, "the camera framed out-of-bounds void on %d ticks" % void_frames)
	near(top_seen, bounds.position.y, 14.0, "the camera reached the top of the table")
	near(bottom_seen, bounds.end.y, 14.0, "the camera reached the bottom of the table")
	table.despawn_ball()
	print("        framed %.0f..%.0f of %.0f..%.0f"
			% [top_seen, bottom_seen, bounds.position.y, bounds.end.y])
	finish()


## 16 — the whole machine, both rooms live, under a seeded thrashing. The yard's own drain
## makes this soak different from the others: balls are *supposed* to be lost here, so what is
## measured is escapes and wedges, not survival.
func _s16_soak() -> void:
	begin("no-tunnel soak with the Docks and the Penthouse on (%.0fs)" % SOAK_SECONDS)
	use(CLUB_IDS + PENT_IDS + DOCKS_IDS + ORBIT_R_IDS)
	table.auto_respawn = true
	table.despawn_ball()
	await step(2)
	table.spawn_ball()
	await wait(0.3)
	table.plunger.launch(1.0)

	var escapes := 0
	var still := 0
	var still_max := 0
	var still_at := Vector2.ZERO
	var last := Vector2.INF
	var next_flip := [0, 0]
	var flip := [false, false]
	var in_yard := 0
	var in_room := 0
	var next_trip := ticks(2.5)
	var trips := 0
	reset_log()

	for t in range(ticks(SOAK_SECONDS)):
		for s in range(2):
			if t >= next_flip[s]:
				flip[s] = not flip[s]
				var f: Flipper = table.flipper_left if s == 0 else table.flipper_right
				f.set_pressed(flip[s])
				next_flip[s] = t + ticks(_rng.randf_range(0.3, 0.7))
		if table.plunger.ball_ready():
			table.plunger.launch(_rng.randf_range(0.85, 1.0))
		# a random flipper cannot be relied on to find either room, so post the ball into one
		# by hand every few seconds — alternating, so both get real time under the thrashing
		if t >= next_trip and table.ball != null and is_instance_valid(table.ball) \
				and not BallHold.is_held(table.ball):
			if trips % 2 == 0:
				table.ball.place(Vector2(103.0, 1080.0))
				table.ball.set_velocity(Vector2(_rng.randf_range(-40.0, 40.0),
						_rng.randf_range(500.0, 1100.0)))
			else:
				table.ball.place(Penthouse.STAIR_MOUTH + Vector2(130.0, 0.0))
				table.ball.set_velocity(Vector2(
						-(Penthouse.STAIR_ENTRY_SPEED + _rng.randf_range(120.0, 700.0)),
						_rng.randf_range(-40.0, 40.0)))
			trips += 1
			next_trip = t + ticks(_rng.randf_range(3.0, 4.5))
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			last = Vector2.INF
			continue
		var p := b.global_position
		if docks.yard_rect().has_point(p):
			in_yard += 1
		if pent.bounds().has_point(p):
			in_room += 1
		if p.x < BOUND_MIN.x or p.x > BOUND_MAX.x or p.y < BOUND_MIN.y or p.y > BOUND_MAX.y:
			escapes += 1
			if escapes <= 3:
				print("        ESCAPE at %s v=%s" % [p, b.linear_velocity])
		if last != Vector2.INF and p.distance_to(last) < 0.5 and not BallHold.is_held(b):
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p

	table.flipper_left.set_pressed(false)
	table.flipper_right.set_pressed(false)
	table.auto_respawn = false
	var stuck := float(still_max) / float(Engine.physics_ticks_per_second)
	var groups := {}
	for e: Dictionary in _earned:
		groups[e["group"]] = int(groups.get(e["group"], 0)) + 1
	print("        served %d | trips %d | yard %d ticks | room %d ticks | switches %d"
			% [table.balls_served, trips, in_yard, in_room, _switches.size()])
	print("        crates %d | shipped %d | pier+drain losses %d | longest still %.2fs at %s"
			% [_stacks.size(), _shipped.size(), _lost, stuck, str(still_at)])
	print("        groups hit: %s" % str(groups))
	check(escapes == 0, "the ball escaped the table %d times" % escapes)
	check(_switches.size() > 0, "nothing on the table was ever hit")
	check(stuck < 2.0, "ball sat motionless for %.2fs — wedged in the new geometry" % stuck)
	check(in_yard > ticks(0.5), "the soak never spent any time in the yard")
	finish()
