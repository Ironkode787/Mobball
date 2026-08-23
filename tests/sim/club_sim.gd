extends Node2D
## M2 acceptance runner for the TABLE (specs/m2-empire.md TABLE-2 "the table grows upward").
##
## The M1 growth sim proves the machine is a different table at every rank. This one proves
## the table has an *upstairs*: that the Staircase is a real speed gate rather than a switch,
## that everything which goes up comes back down somewhere fair, that the Club's toys hold
## the ball only ever on a clock, and that the camera which now has to move never shows the
## player a frame of nothing.
##
## Same house rules as every other sim here: physics ticks not wall time, seeded chaos, the
## real `table_main.tscn` rather than a rig, and a non-zero exit code on any failure.
##
## The Club has no Ledger nodes yet (game/content is the orchestrator's lane), so the deck is
## staged through `ProgressionTable.force_hardware` — the same door `KINGPIN_TABLE_HARDWARE`
## opens for screenshots.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

## The table's own bounds plus a ball radius of slack; anything outside is an escape.
const BOUND_MIN := Vector2(36.0, -906.0)
const BOUND_MAX := Vector2(1044.0, 1930.0)
const SOAK_SECONDS := 25.0
const SEED := 0x43554242

const CLUB_IDS: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
]
## A Capo's table: everything M1 sells, which is what the Club is bolted onto.
const T3_FIXTURE: Array = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
	"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
	"rackets.the_wire", "influence.beat_cop", "muscle.enforcer_corner",
	"rackets.protection_laundromat", "rackets.protection_pizzeria",
	"rackets.protection_pawn", "rackets.getaway_loop", "muscle.steel_toes",
]

var host: Node2D = null
var table: ProgressionTable = null
var club: ClubDeck = null
var camera: CameraRig = null
var input: InputController = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

var _earned: Array[Dictionary] = []
var _switches: PackedStringArray = []
var _landings: Array[Dictionary] = []
var _reels: Array = []
var _holds: Array[int] = []
var _backrooms: int = 0
var _climbs: Array[float] = []
var _returns: int = 0
var _entries: Array[float] = []
var _rollbacks: Array[float] = []


func _ready() -> void:
	_rng.seed = SEED
	host = Node2D.new()
	host.name = "Host"
	add_child(host)
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	host.add_child(table)
	club = table.club
	camera = CameraRig.new()
	camera.name = "CameraRig"
	host.add_child(camera)
	input = InputController.new()
	input.name = "InputController"
	host.add_child(input)
	input.bind(table.flipper_left, table.flipper_right, table.plunger, null)
	table.auto_respawn = false
	table.ball_spawned.connect(func(b: Ball) -> void: camera.set_target(b))

	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		_earned.append({"amount": amount.approx_float(), "group": group}))
	Events.switch_hit.connect(func(id: StringName, _b: Node2D, _s: float) -> void:
		_switches.append(String(id)))
	table.roulette_landed.connect(func(pocket: int, house: bool) -> void:
		_landings.append({"pocket": pocket, "house": house}))
	table.reels_state.connect(func(cols: Array) -> void: _reels.append(cols))
	table.high_roller_held.connect(func(steps: int) -> void: _holds.append(steps))
	table.backroom_entered.connect(func() -> void: _backrooms += 1)
	table.staircase_climbed.connect(func(speed: float) -> void: _climbs.append(speed))
	club.return_lane.crested.connect(func(_s: float) -> void: _returns += 1)
	club.staircase.entered.connect(func(s: float) -> void: _entries.append(s))
	club.staircase.rolled_back.connect(func(s: float) -> void: _rollbacks.append(s))
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


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if _fails.is_empty() else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


func use_club(on: bool = true) -> void:
	Game.stats = FixtureStats.new(T3_FIXTURE)
	table.refresh_hardware()
	table.force_hardware(CLUB_IDS, on)
	reset_log()


func reset_log() -> void:
	Game.heat.reset()
	Game.combo.reset()
	_earned.clear()
	_switches = PackedStringArray()
	_landings.clear()
	_reels.clear()
	_holds.clear()
	_climbs.clear()
	_entries.clear()
	_rollbacks.clear()
	_backrooms = 0
	_returns = 0


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


## Drop a ball at a point and give physics a moment to notice it.
func drop_at(at: Vector2, velocity: Vector2 = Vector2.ZERO, settle: int = 4) -> Ball:
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	b.place(at)
	if velocity != Vector2.ZERO:
		b.set_velocity(velocity)
	await step(settle)
	return b


## Step `seconds`, watching for the two things that end a night quietly: a ball outside the
## table, and a ball that has stopped somewhere it cannot leave.
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
		if last != Vector2.INF and p.distance_to(last) < 0.5:
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
	print("== KINGPIN M2 club sim ==")
	print("physics %d Hz | seed 0x%X | viewport %s"
			% [Engine.physics_ticks_per_second, SEED, str(camera.view_size())])
	await step(4)

	await _s1_deck_dormancy()
	await _s2_geometry()
	await _s3_staircase_gate()
	await _s4_staircase_rollback()
	await _s5_return_lane()
	await _s6_roulette()
	await _s7_roulette_soak()
	await _s8_slot_reels()
	await _s9_high_roller()
	await _s10_backroom()
	await _s11_club_flippers()
	await _s12_camera()
	await _s13_soak()

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


## 1 — a Capo's table with the Club unbought is the M1 table, to the collider.
func _s1_deck_dormancy() -> void:
	begin("the Club is absent until it is bought")
	use_club(false)
	await step(2)
	for id: StringName in CLUB_IDS:
		check(not table.hardware_present(id), "%s is on the table before it is bought" % id)
	for piece: Dictionary in table.hardware_pieces():
		if not CLUB_IDS.has((piece["ids"] as Array[StringName])[0]):
			continue
		var node: Node2D = piece["node"]
		check(not node.visible, "%s is visible while dormant" % node.name)
		check(Dormant.is_collision_off(node), "%s is hidden but still collides" % node.name)
	check(not club.is_hardware_active(), "the deck reports itself live")
	near(table.bounds().position.y, 0.0, 0.001, "table bounds must not grow before the deck")
	near(table.bounds().size.y, ProgressionTable.PLAY_BOTTOM, 0.001, "M1 table height")

	# the staircase mouth must be inert too: a rocket up the right corridor stays downstairs
	await drop_at(ClubDeck.STAIR_MOUTH + Vector2(0.0, 90.0), Vector2(0.0, -2600.0))
	await wait(0.6)
	check(_entries.is_empty(), "the Staircase took a ball before it was built")
	var b := table.ball
	check(b != null and is_instance_valid(b) and b.collision_layer == Feel.LAYER_BALL,
			"the ball was lifted off a table with no ramp on it")
	table.despawn_ball()
	finish()

	begin("buying the Club puts the deck on the table")
	use_club(true)
	await step(2)
	for id: StringName in CLUB_IDS:
		check(table.hardware_present(id), "%s did not arrive with the deck" % id)
	check(club.is_hardware_active(), "the deck is not live")
	var deck := club.bounds()
	near(table.bounds().position.y, deck.position.y, 0.001, "table bounds grew to the deck")
	check(table.bounds().size.y > 2700.0,
			"the table should be ~2.8 screens tall, got %.0f" % table.bounds().size.y)
	# A piece of the deck with no deck under it is not hardware — and if the deck goes while
	# it has the ball, the ball comes downstairs rather than being left standing in the sky.
	await drop_at(club.roulette.global_position + Vector2(0.0, -150.0), Vector2(0.0, 260.0))
	for i in range(ticks(3.0)):
		await step(1)
		if club.roulette.holds_ball():
			break
	check(club.roulette.holds_ball(), "the wheel did not take the ball for the teardown test")
	table.force_hardware([ClubDeck.ID_DECK], false)
	await step(3)
	check(not table.hardware_present(&"roulette_wheel"),
			"the wheel stayed on the table with the deck switched off")
	check(not club.holds_ball(), "the Club kept the ball after being switched off")
	var stranded := table.ball
	check(stranded != null and is_instance_valid(stranded)
			and stranded.collision_layer == Feel.LAYER_BALL,
			"the ball was left lifted off the table when the deck went")
	if stranded != null and is_instance_valid(stranded):
		check(stranded.global_position.y > 0.0,
				"the ball was left in the sky at %s" % str(stranded.global_position))
	table.despawn_ball()
	table.force_hardware([ClubDeck.ID_DECK], true)
	await step(2)
	print("        deck %s | table now %.0f px tall" % [str(deck), table.bounds().size.y])
	finish()


## 2 — every lane upstairs passes a ball, and every slot up there is a wall.
func _s2_geometry() -> void:
	begin("deck geometry: lanes pass a ball, gaps do not")
	var dia := Feel.BALL_RADIUS * 2.0
	var inner_l := ClubDeck.DECK_LEFT + ClubDeck.WALL_THICK * 0.5
	var inner_r := ClubDeck.DECK_RIGHT - ClubDeck.WALL_THICK * 0.5
	var half := SlotReels.TARGET_LENGTH * 0.5
	var col_l: float = ClubDeck.REELS_AT.x - SlotReels.COL_PITCH - half
	var col_r: float = ClubDeck.REELS_AT.x + SlotReels.COL_PITCH + half
	check(col_l - inner_l >= dia + 20.0,
			"left lane is %.0f px" % (col_l - inner_l))
	check(inner_r - col_r >= dia + 20.0,
			"right lane (the deck's orbit) is %.0f px" % (inner_r - col_r))
	var between := SlotReels.COL_PITCH - SlotReels.TARGET_LENGTH
	check(between >= dia + 20.0, "gap between reels is %.0f px" % between)
	check(SlotReels.ROW_PITCH - 20.0 < dia,
			"reel rows leave a %.0f px slot" % (SlotReels.ROW_PITCH - 20.0))

	# the orbit channel has to pass a ball between the deck's rounded corner and the guide
	var channel: float = (ClubDeck.CORNER_RADIUS - ClubDeck.WALL_THICK * 0.5) \
			- (ClubDeck.ORBIT_GUIDE_RADIUS + ClubDeck.GUIDE_THICK * 0.5)
	check(channel >= dia + 20.0, "orbit channel is %.0f px" % channel)

	# the mini bats have to leave a real drain gap for an unscaled ball
	var reach := Feel.FLIPPER_LENGTH * ClubDeck.FLIPPER_SCALE * cos(deg_to_rad(Feel.FLIPPER_REST_DEG))
	var tip := Feel.FLIPPER_TIP_RADIUS * ClubDeck.FLIPPER_SCALE
	var gap: float = (ClubDeck.FLIPPER_PIVOT_R.x - reach - tip) \
			- (ClubDeck.FLIPPER_PIVOT_L.x + reach + tip)
	check(gap > dia, "the deck's drain gap (%.0f px) passes a ball" % gap)
	check(gap < dia + 45.0, "the deck's drain gap is not a barn door (%.0f px)" % gap)
	near(club.flipper_left.bat_length(), Feel.FLIPPER_LENGTH * 0.8, 0.001, "mini bat length")
	near(table.flipper_left.bat_length(), Feel.FLIPPER_LENGTH, 0.001,
			"the main table's bats are untouched by the mini pair")

	# beside the wheel is either a lane or a wall, never a ball-sized slot to wedge in
	var wheel_slot: float = (ClubDeck.WHEEL_AT.x - RouletteWheel.RADIUS) - inner_l
	check(wheel_slot >= dia + 20.0 or wheel_slot < dia,
			"the wheel leaves a %.0f px slot against the left wall" % wheel_slot)
	# and the deck's own bats must not reach the walls either
	check(ClubDeck.FLIPPER_PIVOT_L.x - Feel.FLIPPER_PIVOT_RADIUS * ClubDeck.FLIPPER_SCALE
			- inner_l < dia, "the left bat leaves a ball-sized notch beside it")
	print("        left lane %.0f | orbit lane %.0f | channel %.0f | drain gap %.0f"
			% [col_l - inner_l, inner_r - col_r, channel, gap])
	finish()


## 3 — the Staircase is a speed gate. A shot with pace makes the top; one without is not
## taken at all and stays on the playfield.
func _s3_staircase_gate() -> void:
	begin("staircase: a clean hit climbs, a soft one is refused")
	use_club(true)
	var need := club.staircase.required_entry_speed()
	check(ClubDeck.STAIR_ENTRY_SPEED > need + 150.0,
			"the gate (%.0f) must sit clear of the climb it demands (%.0f)"
			% [ClubDeck.STAIR_ENTRY_SPEED, need])

	await drop_at(ClubDeck.STAIR_MOUTH + Vector2(0.0, 90.0),
			Vector2(0.0, -(ClubDeck.STAIR_ENTRY_SPEED + 260.0)))
	await wait(0.3)
	check(_entries.size() == 1, "the mouth did not take a %.0f px/s shot"
			% (ClubDeck.STAIR_ENTRY_SPEED + 260.0))
	check(hit_switch("staircase_ramp_entry"), "no entry switch")
	var b := table.ball
	check(b != null and b.collision_layer == 0, "a ball on the ramp is still on the playfield")
	var climbed := 0.0
	for i in range(ticks(4.0)):
		await step(1)
		if not _climbs.is_empty():
			climbed = _climbs[0]
			break
	check(climbed > 0.0, "the climb never reached the top")
	check(club.bounds().grow(60.0).has_point(table.ball.global_position),
			"the ball did not arrive on the deck (at %s)" % str(table.ball.global_position))
	check(table.ball.collision_layer == Feel.LAYER_BALL,
			"the ball was handed back to the deck still lifted off it")
	var pay := last_earn_in(TableScore.GROUP_RAMPS)
	near(float(pay.get("amount", 0.0)), TableScore.RAMP_CLIMB, 0.001, "a completed climb pays")
	check(hit_switch("staircase_ramp"), "no staircase_ramp switch on the crest")
	print("        gate %.0f (needs %.0f) | crest %.0f px/s | $%d"
			% [ClubDeck.STAIR_ENTRY_SPEED, need, climbed, int(TableScore.RAMP_CLIMB)])
	table.despawn_ball()

	reset_log()
	await drop_at(ClubDeck.STAIR_MOUTH + Vector2(0.0, 90.0),
			Vector2(0.0, -(ClubDeck.STAIR_ENTRY_SPEED - 400.0)))
	await wait(0.5)
	check(_entries.is_empty(), "a %.0f px/s shot was taken by the gate"
			% (ClubDeck.STAIR_ENTRY_SPEED - 400.0))
	check(_climbs.is_empty(), "a refused shot still paid a climb")
	var weak := table.ball
	check(weak != null and is_instance_valid(weak)
			and weak.collision_layer == Feel.LAYER_BALL,
			"a refused shot did not stay a normal ball")
	await wait(0.8)
	if weak != null and is_instance_valid(weak):
		check(weak.linear_velocity.y > 0.0, "the refused shot never came back down")
	table.despawn_ball()

	# a ball falling *down* through the mouth is not a ramp shot however fast it is
	reset_log()
	await drop_at(ClubDeck.STAIR_MOUTH - Vector2(0.0, 90.0), Vector2(0.0, 2400.0))
	await wait(0.25)
	check(_entries.is_empty(), "the mouth took a ball that was falling through it")
	table.despawn_ball()
	finish()


## 4 — a ball that gets into a ramp and runs out of climb comes back out of the mouth it
## went in by, on the playfield, under its own physics.
func _s4_staircase_rollback() -> void:
	begin("staircase: a stalled climb rolls back out of the mouth")
	use_club(true)
	var gate: float = club.staircase.entry_speed
	club.staircase.entry_speed = 300.0                # let a hopeless shot in on purpose
	await drop_at(ClubDeck.STAIR_MOUTH + Vector2(0.0, 24.0), Vector2(0.0, -520.0))
	await wait(0.3)
	check(_entries.size() == 1, "the lowered gate did not take the ball")
	var rolled := false
	for i in range(ticks(6.0)):
		await step(1)
		if not _rollbacks.is_empty():
			rolled = true
			break
	check(rolled, "a stalled climb never came back down")
	check(_climbs.is_empty(), "a stalled climb paid a completed climb")
	var b := table.ball
	check(b != null and is_instance_valid(b), "the ball was lost on the ramp")
	if b != null and is_instance_valid(b):
		check(b.collision_layer == Feel.LAYER_BALL, "the ball came back still lifted")
		check(b.linear_velocity.y > 0.0, "it came out of the mouth going the wrong way")
		check(absf(b.global_position.x - ClubDeck.STAIR_MOUTH.x) < 60.0,
				"it came out somewhere other than the mouth (%s)" % str(b.global_position))
	club.staircase.entry_speed = gate
	table.despawn_ball()
	if not _rollbacks.is_empty():
		print("        stalled at %.0f px/s and returned to the corridor" % _rollbacks[0])
	finish()


## 5 — the way down. Everything below the mini bats is the return lane's, it is one-way, and
## it puts the ball in the right inlane rather than on the drain line.
func _s5_return_lane() -> void:
	begin("the deck has no floor: the return lane feeds the right inlane")
	use_club(true)
	var landed := Vector2.ZERO
	await drop_at(Vector2(600.0, -95.0), Vector2(0.0, 220.0))
	var caught := false
	for i in range(ticks(1.5)):
		await step(1)
		if club.return_lane.riding():
			caught = true
			break
	check(caught, "a ball off the deck was not caught by the return lane")
	var arrived := false
	var lowest := -INF
	for i in range(ticks(5.0)):
		await step(1)
		var b := table.ball
		if b != null and is_instance_valid(b):
			lowest = maxf(lowest, b.global_position.y)
		if _returns > 0:
			arrived = true
			landed = b.global_position if b != null else Vector2.ZERO
			break
	check(arrived, "the return lane never delivered the ball")
	check(_returns == 1, "the return fired %d times" % _returns)
	if arrived:
		var b := table.ball
		check(b.collision_layer == Feel.LAYER_BALL, "delivered still lifted off the table")
		check(landed.y < ProgressionTable.OUTLANE_BOTTOM,
				"delivered at y=%.0f — that is down at the drain line" % landed.y)
		# one tick of gravity lands between the release and this reading
		check(b.speed() <= ClubDeck.RETURN_RELEASE_SPEED + 60.0,
				"delivered at %.0f px/s — a wireform does not fire the ball out" % b.speed())
		var mirror_outlane: float = ProgressionTable.MIRROR_X * 2.0 - ProgressionTable.OUTLANE_X
		var sling_edge: float = ProgressionTable.MIRROR_X * 2.0 - ProgressionTable.SLING_OUTER_BOTTOM.x
		check(landed.x > sling_edge and landed.x < mirror_outlane,
				"delivered at x=%.0f, outside the right inlane (%.0f..%.0f)"
				% [landed.x, sling_edge, mirror_outlane])
	# ...and it must not have dipped below the drain on the way
	check(lowest < ProgressionTable.DRAIN_Y, "the ride passed through the drain line")
	var w := await watch(2.0)
	check(int(w["escapes"]) == 0, "the delivered ball left the table")
	print("        caught at the deck floor, delivered to %s at %.0f px/s"
			% [str(landed), ClubDeck.RETURN_RELEASE_SPEED])
	table.despawn_ball()
	finish()


## 6 — the wheel: it takes the ball, it says which pocket, it gives it back.
func _s6_roulette() -> void:
	begin("roulette: capture, report, eject")
	use_club(true)
	var wheel := club.roulette
	await drop_at(wheel.global_position + Vector2(0.0, -150.0), Vector2(0.0, 260.0))
	var took := 0
	for i in range(ticks(4.0)):
		await step(1)
		if not _landings.is_empty():
			took = i
			break
	check(not _landings.is_empty(), "the wheel never took the ball")
	if _landings.is_empty():
		finish()
		return
	var pocket := int(_landings[0]["pocket"])
	check(pocket >= 0 and pocket < RouletteWheel.POCKETS,
			"reported pocket %d out of range" % pocket)
	check(bool(_landings[0]["house"]) == RouletteWheel.is_house(pocket),
			"house flag disagrees with the marked pockets")
	check(wheel.holds_ball(), "the wheel reported a landing without holding the ball")
	var pay := last_earn_in(TableScore.GROUP_CASINO)
	near(float(pay.get("amount", 0.0)), TableScore.CASINO_POCKET, 0.001,
			"a pocket pays the courtesy switch")

	# it rides the wheel round while it is held, and it is always given back
	var held_at := table.ball.global_position
	await wait(RouletteWheel.HOLD * 0.5)
	check(table.ball.global_position.distance_to(held_at) > 12.0,
			"the ball did not ride the wheel round while it was held")
	var freed := false
	for i in range(ticks(RouletteWheel.HOLD + 0.5)):
		await step(1)
		if not wheel.holds_ball():
			freed = true
			break
	check(freed, "the wheel never let go")
	check(table.ball.collision_layer == Feel.LAYER_BALL, "ejected still lifted off the table")
	check(table.ball.speed() > 400.0, "ejected at %.0f px/s — that is a drop, not a throw"
			% table.ball.speed())
	await wait(0.6)
	check(table.ball.global_position.distance_to(wheel.global_position)
			> RouletteWheel.RADIUS * 0.5, "the ejected ball never left the wheel")
	print("        pocket %d (%s) after %.2fs, held %.1fs, thrown at speed"
			% [pocket, "house" if bool(_landings[0]["house"]) else "player",
			float(took) / float(Engine.physics_ticks_per_second), RouletteWheel.HOLD])
	table.despawn_ball()
	finish()


## 7 — the wheel is a hole with a clock on it. Twelve seeded drops: every one reports, every
## one is thrown back out, and the ball is never asleep in the bowl.
func _s7_roulette_soak() -> void:
	begin("roulette soak: 12 seeded drops, no ball ever parks in the bowl")
	use_club(true)
	var wheel := club.roulette
	var seen := {}
	var worst_hold := 0.0
	var worst_still := 0.0
	var still_where := Vector2.ZERO
	var taken := 0
	for run in range(12):
		reset_log()
		var from := wheel.global_position + Vector2(_rng.randf_range(-50.0, 50.0), -150.0)
		var vel := Vector2(_rng.randf_range(-200.0, 200.0), _rng.randf_range(120.0, 700.0))
		await drop_at(from, vel)
		var t0 := 0
		var landed_at := -1
		var freed_at := -1
		var still := 0
		var last := Vector2.INF
		for i in range(ticks(6.0)):
			await step(1)
			t0 += 1
			var b := table.ball
			if b == null or not is_instance_valid(b):
				break
			var p := b.global_position
			if last != Vector2.INF and p.distance_to(last) < 0.5 and not BallHold.is_held(b):
				still += 1
				var s := float(still) / float(Engine.physics_ticks_per_second)
				if s > worst_still:
					worst_still = s
					still_where = p
			else:
				still = 0
			last = p
			if landed_at < 0 and not _landings.is_empty():
				landed_at = i
			elif landed_at >= 0 and freed_at < 0 and not wheel.holds_ball():
				freed_at = i
				break
		if landed_at >= 0:
			taken += 1
			check(freed_at >= 0, "drop %d: the wheel never gave it back" % run)
		if landed_at >= 0 and freed_at >= 0:
			var held := float(freed_at - landed_at) / float(Engine.physics_ticks_per_second)
			worst_hold = maxf(worst_hold, held)
			check(held <= RouletteWheel.HOLD + 0.15,
					"drop %d held for %.2fs (spec %.1fs)" % [run, held, RouletteWheel.HOLD])
			var pocket := int(_landings[0]["pocket"])
			seen[pocket] = int(seen.get(pocket, 0)) + 1
		table.despawn_ball()
		await step(2)
	check(taken >= 10, "only %d of 12 drops into the wheel were caught" % taken)
	check(seen.size() >= 3, "12 drops only ever found %d of 8 pockets" % seen.size())
	check(worst_still < 1.5, "the ball sat motionless for %.2fs at %s"
			% [worst_still, str(still_where)])
	print("        caught %d/12 | pockets hit %s | longest hold %.2fs | longest still %.2fs at %s"
			% [taken, str(seen), worst_hold, worst_still, str(still_where)])
	finish()


## 8 — three reels, three targets each, each column on its own clock.
func _s8_slot_reels() -> void:
	begin("slot reels: pay per target, clear per column, reset independently")
	use_club(true)
	var reels := club.reels
	reels.reset_now()
	await step(2)
	for row in range(SlotReels.ROWS - 1, -1, -1):
		var t := reels.target_at(1, row)
		await drop_at(t.to_global(Vector2(0.0, 34.0)))
		await step(3)
	check(reels.column_is_clear(1), "the middle reel did not clear (%d down)"
			% reels.column_down(1))
	check(not reels.column_is_clear(0) and not reels.column_is_clear(2),
			"knocking one reel down took the others with it")
	check(earn_count(TableScore.GROUP_CASINO) == SlotReels.ROWS,
			"%d payouts for 3 targets" % earn_count(TableScore.GROUP_CASINO))
	var pay := last_earn_in(TableScore.GROUP_CASINO)
	near(float(pay.get("amount", 0.0)), TableScore.CASINO_REEL, 0.001, "a reel target pays")
	check(not _reels.is_empty() and (_reels[_reels.size() - 1] as Array).has(1),
			"reels_state never reported the cleared column")
	# one switch per target hit, not two: Jobs count switch ids
	var closes := 0
	for s in _switches:
		if s.begins_with("slot_reels_2"):
			closes += 1
	check(closes == SlotReels.ROWS, "%d switch closures for 3 targets" % closes)

	table.despawn_ball()
	await wait(reels.reset_seconds * 0.5)
	check(reels.column_is_clear(1), "the reel came back up early")
	await wait(reels.reset_seconds * 0.6 + 0.2)
	check(not reels.column_is_clear(1), "the reel never came back up")
	check(reels.column_down(1) == 0, "the reel came back up part-way")
	print("        reel 2: 3 × $%d, cleared, reset after %.1fs"
			% [int(TableScore.CASINO_REEL), reels.reset_seconds])
	finish()


## 9 — the High Roller: a ladder on a cadence, and a kick-out that gets hotter with it.
func _s9_high_roller() -> void:
	begin("high roller: 1x→2x→3x→5x on the beat, hot eject")
	use_club(true)
	var saucer := club.high_roller
	await drop_at(saucer.global_position, Vector2.ZERO)
	await step(3)
	check(saucer.holds_ball(), "the saucer did not take the ball")
	near(saucer.multiplier(), 1.0, 0.001, "a fresh hold starts at 1x")
	check(hit_switch("high_roller_saucer"), "the saucer reported no switch")
	check(earn_count(TableScore.GROUP_CASINO) == 0,
			"the hold paid money — flow owns the bet, not the table")

	await wait(saucer.step_seconds * 0.6)
	near(saucer.multiplier(), 1.0, 0.001, "the ladder climbed before its cadence")
	var steps_seen := 0
	for i in range(ticks(saucer.step_seconds * 4.0 + 0.6)):
		await step(1)
		steps_seen = maxi(steps_seen, saucer.step_index())
		if not saucer.holds_ball():
			break
	check(not saucer.holds_ball(), "the saucer never let go")
	check(_holds.size() == 1, "the hold reported %d times" % _holds.size())
	if not _holds.is_empty():
		check(_holds[0] == ClubDeck.HIGH_ROLLER_STEPS.size() - 1,
				"a full hold reported %d rungs, expected %d"
				% [_holds[0], ClubDeck.HIGH_ROLLER_STEPS.size() - 1])
	var hot := table.ball.speed()
	check(hot > saucer.eject_speed, "a full hold left at %.0f px/s — no heat" % hot)
	table.despawn_ball()

	# a short hold cannot happen on this saucer (it auto-ejects), so prove the heat rule
	# against the ladder instead: rung 0 would leave at the base speed.
	near(saucer.eject_speed + saucer.eject_heat * float(ClubDeck.HIGH_ROLLER_STEPS.size() - 1),
			hot, 40.0, "eject speed follows the rungs held")
	print("        ladder %s | ejected at %.0f px/s" % [str(ClubDeck.HIGH_ROLLER_STEPS), hot])
	finish()


## 10 — the back room takes the ball for a beat and hands it back (flow starts the Family
## Meeting from the signal later).
func _s10_backroom() -> void:
	begin("back room: 0.8 s capture behind the slots")
	use_club(true)
	var saucer := club.backroom
	await drop_at(saucer.global_position, Vector2.ZERO)
	await step(3)
	check(_backrooms == 1, "backroom_entered fired %d times" % _backrooms)
	check(saucer.holds_ball(), "the back room did not hold the ball")
	await wait(saucer.hold_seconds * 0.5)
	check(saucer.holds_ball(), "the back room let go early")
	var kicked := 0.0
	for i in range(ticks(saucer.hold_seconds + 0.4)):
		await step(1)
		if not saucer.holds_ball():
			kicked = table.ball.speed()
			break
	check(not saucer.holds_ball(), "the back room never let go")
	check(table.ball.collision_layer == Feel.LAYER_BALL, "handed back still lifted")
	check(kicked > 400.0, "handed back at %.0f px/s — no kick" % kicked)
	# it sits behind the middle reel: you have to clear that reel to get at it
	var top_target := club.reels.target_at(1, 0)
	check(saucer.global_position.y < top_target.global_position.y,
			"the back room is not behind the slots")
	table.despawn_ball()
	print("        held %.1fs, kicked out, sits behind reel 2" % saucer.hold_seconds)
	finish()


## 11 — the mini pair rides the same two actions, through the same InputController the main
## bats use, with the same buffer.
func _s11_club_flippers() -> void:
	begin("club flippers: same two inputs, same buffer, 0.8 scale")
	use_club(true)
	await drop_at(Vector2(780.0, -300.0), Vector2.ZERO)
	await step(2)
	Input.action_press(&"flipper_left")
	await step(4)
	check(table.flipper_left.state != Flipper.State.REST,
			"the main left bat did not fire from the action")
	check(club.flipper_left.state != Flipper.State.REST,
			"the Club's left bat did not follow the same press")
	check(club.flipper_right.state == Flipper.State.REST,
			"the Club's right bat fired on the left action")
	Input.action_release(&"flipper_left")
	await wait(0.3)
	check(club.flipper_left.state == Flipper.State.REST, "the Club's bat stayed up")

	Input.action_press(&"flipper_right")
	await step(4)
	check(club.flipper_right.state != Flipper.State.REST,
			"the Club's right bat did not follow the right action")
	Input.action_release(&"flipper_right")
	await wait(0.3)

	# switched off, the bats are gone and deaf
	table.force_hardware([ClubDeck.ID_FLIPPERS], false)
	await step(2)
	Input.action_press(&"flipper_left")
	await step(6)
	check(club.flipper_left.state == Flipper.State.REST,
			"a bat that was never bought still fires")
	check(Dormant.is_collision_off(club.flipper_left), "a dormant bat still collides")
	Input.action_release(&"flipper_left")
	table.force_hardware([ClubDeck.ID_FLIPPERS], true)
	await step(2)
	table.despawn_ball()
	print("        both bats mirror the main pair; dormant pair is deaf and cold")
	finish()


## 12 — the camera. It has to reach both ends of a 2.8-screen table, show the deck whole when
## the ball is up there, keep the flippers on screen while it is down here, and never frame a
## pixel of nothing.
func _s12_camera() -> void:
	begin("camera: reaches both extremes and never shows void")
	use_club(true)
	var view := camera.view_size()
	var bounds := table.bounds()
	var top_seen := INF
	var bottom_seen := -INF
	var void_frames := 0
	var flipper_line: float = ProgressionTable.FLIPPER_PIVOT_L.y
	var lost_flippers := 0

	# The ball is held at each station rather than played there: this scenario is about where
	# the camera goes for a given ball position, and a free ball would not stay put.
	var legs: Array = [
		{"at": Vector2(880.0, -820.0), "s": 1.6},
		{"at": Vector2(700.0, -300.0), "s": 1.2},
		{"at": Vector2(490.0, 900.0), "s": 1.6},
		{"at": Vector2(490.0, 1700.0), "s": 1.6},
	]
	# A teleport between stations is not a shot; the frame is given a beat to catch up before
	# the flipper-line rule is enforced. The uninterrupted ride home below has no such grace.
	var grace := ticks(0.35)
	var mid: float = bounds.position.y + bounds.size.y * 0.5
	for leg: Dictionary in legs:
		await drop_at(leg["at"])
		for i in range(ticks(float(leg["s"]))):
			if table.ball != null and is_instance_valid(table.ball):
				table.ball.place(leg["at"])
			await step(1)
			var r := camera.view_rect()
			top_seen = minf(top_seen, r.position.y)
			bottom_seen = maxf(bottom_seen, r.end.y)
			if r.position.y < bounds.position.y - 0.5 or r.end.y > bounds.end.y + 0.5:
				void_frames += 1
			var b := table.ball
			if i >= grace and b != null and is_instance_valid(b):
				if b.global_position.y >= mid and (r.end.y < flipper_line
						or r.position.y > flipper_line):
					lost_flippers += 1
		if float(leg["at"].y) < 0.0:
			var r := camera.view_rect()
			var deck := club.bounds()
			check(r.position.y <= deck.position.y + 1.0 and r.end.y >= deck.end.y - 1.0,
					"the deck is not fully in frame with the ball on it (view %s)" % str(r))

	# The real move: a ball that falls off the deck and rides the return lane all the way
	# home. The camera has to travel the whole table with it and be showing the bats by the
	# time the ball is anywhere near them.
	await drop_at(Vector2(600.0, -95.0), Vector2(0.0, 220.0))
	var below_for := 0
	var late := 0
	for i in range(ticks(4.0)):
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			break
		var r := camera.view_rect()
		top_seen = minf(top_seen, r.position.y)
		bottom_seen = maxf(bottom_seen, r.end.y)
		if r.position.y < bounds.position.y - 0.5 or r.end.y > bounds.end.y + 0.5:
			void_frames += 1
		if b.global_position.y >= mid:
			below_for += 1
			if below_for > ticks(0.25) and (r.end.y < flipper_line
					or r.position.y > flipper_line):
				late += 1
		else:
			below_for = 0
	check(late == 0,
			"riding the return lane home, the flippers were still off screen on %d ticks" % late)
	check(void_frames == 0, "the camera framed out-of-bounds void on %d ticks" % void_frames)
	check(lost_flippers == 0,
			"the flipper line left the frame on %d ticks with the ball downstairs"
			% lost_flippers)
	near(top_seen, bounds.position.y, 12.0, "the camera reached the top of the table")
	near(bottom_seen, bounds.end.y, 12.0, "the camera reached the bottom of the table")
	check(camera.follow_enabled, "vertical follow is switched off")
	# With no deck bought the frame is taller than the table. Design ruling (device
	# feedback): the camera BOTTOM-ANCHORS — flippers at thumb level, all overscan above
	# the arch — and a ball fired upward must not budge it from that park.
	table.despawn_ball()
	table.force_hardware(CLUB_IDS, false)
	await drop_at(Vector2(490.0, 300.0), Vector2(0.0, -1200.0))
	await wait(1.2)
	var r2 := camera.view_rect()
	var short_bounds := (table.bounds() as Rect2)
	check(absf(r2.end.y - short_bounds.end.y) <= 1.5,
			"a short table parks with its bottom on the screen bottom (view end %.0f, table end %.0f)"
			% [r2.end.y, short_bounds.end.y])
	table.force_hardware(CLUB_IDS, true)
	table.despawn_ball()
	print("        view %.0f×%.0f | framed %.0f..%.0f of %.0f..%.0f"
			% [view.x, view.y, top_seen, bottom_seen, bounds.position.y, bounds.end.y])
	finish()


## 13 — the whole machine, deck and all, under a seeded thrashing.
func _s13_soak() -> void:
	begin("no-tunnel soak with the Club unlocked (%.0fs)" % SOAK_SECONDS)
	use_club(true)
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
	var trips := 0
	var upstairs := 0
	var upstairs_run := 0
	var pushed_off := 0
	var next_trip := ticks(3.0)
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
		# every few seconds, put a ball up the stairs by hand: the soak has to spend real
		# time on the deck, and a random flipper cannot be relied on to make the shot
		# ...but only from downstairs: a trip that yanked the ball off the deck mid-play
		# would never let the return lane do its job.
		if t >= next_trip and table.ball != null and is_instance_valid(table.ball) \
				and table.ball.global_position.y > 400.0 \
				and not BallHold.is_held(table.ball) and not club.holds_ball():
			table.ball.place(ClubDeck.STAIR_MOUTH + Vector2(0.0, 70.0))
			table.ball.set_velocity(Vector2(_rng.randf_range(-60.0, 60.0),
					-(ClubDeck.STAIR_ENTRY_SPEED + _rng.randf_range(80.0, 900.0))))
			trips += 1
			next_trip = t + ticks(_rng.randf_range(4.0, 6.0))
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			last = Vector2.INF
			continue
		var p := b.global_position
		if p.y < 0.0:
			upstairs += 1
			upstairs_run += 1
			# The mini bats mirror the main pair, and a pair of bats flapping at random keeps
			# a ball alive on a small field almost indefinitely. Push it off the deck by hand
			# now and then so the way down gets as much of the soak as the way up.
			if upstairs_run > ticks(5.0) and not BallHold.is_held(b) and not club.holds_ball():
				b.place(Vector2(780.0, -50.0))
				b.set_velocity(Vector2(0.0, 120.0))
				upstairs_run = 0
				pushed_off += 1
		else:
			upstairs_run = 0
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
	print("        trips up %d | climbs %d | pushed off %d | returns %d | switches %d"
			% [trips, _climbs.size(), pushed_off, _returns, _switches.size()])
	print("        %.0f%% of the soak was upstairs | landings %d | longest still %.2fs at %s"
			% [100.0 * float(upstairs) / float(ticks(SOAK_SECONDS)), _landings.size(),
			stuck, str(still_at)])
	print("        groups hit: %s" % str(groups))
	check(escapes == 0, "the ball escaped the table %d times" % escapes)
	check(_climbs.size() > 0, "no ball ever made it up the stairs")
	check(_returns > 0, "no ball ever came back down")
	check(stuck < 2.0, "ball sat motionless for %.2fs — wedged in the new geometry" % stuck)
	check(upstairs > ticks(1.0), "the soak never spent any time on the deck")
	finish()
