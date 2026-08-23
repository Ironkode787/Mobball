extends Node2D
## M1 acceptance runner for the TABLE (specs/m1-hook.md Lane 3 "Sim").
##
## The progression table's whole job is to be a different machine at every stage of a
## career, so this boots the real `table_main.tscn` against staged owned-set fixtures (bare
## / T1 / T2 / T3, resolved from the shipped upgrade data) and asserts three separate
## things about each one:
##
##   1. the right hardware is *there* — and, just as importantly, the wrong hardware is not,
##      with its collision genuinely switched off rather than merely invisible;
##   2. a scripted ball on each live piece produces the right switch and the right amount
##      through `Game.earn_switch`, including the Ledger's multipliers and flat adds;
##   3. the pieces with state — storefront collect/re-arm, the orbit's gate sequence, the
##      raid hardware, the plunger's rubber band — run their cycles.
##
## Everything is counted in physics ticks, never wall time, and the chaos soak is seeded.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

const BOUND_MIN := Vector2(36.0, -4.0)
const BOUND_MAX := Vector2(1044.0, 1930.0)
const SOAK_SECONDS := 25.0
const SEED := 0x4B494E47

## The growth rings M2 and M3 added. They have no Ledger nodes yet (game/content is the
## orchestrator's lane), so they are staged on top of a T3 career through `force_hardware` —
## the same door `KINGPIN_TABLE_HARDWARE` opens for screenshots.
const CLUB_SET: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
]
const DOCKS_SET: Array[StringName] = [
	&"docks", &"containers", &"crane", &"cargo_ramp", &"orbit_right",
]
const PENT_SET: Array[StringName] = [
	&"penthouse", &"commission_chairs", &"sitdown_saucer", &"penthouse_stairs",
]
## The crown (R7). One piece of furniture: the dome is a rail and a painting.
const DOME_SET: Array[StringName] = [&"city_hall"]

const T3_LEDGER: Array = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
	"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
	"rackets.the_wire", "influence.beat_cop", "muscle.enforcer_corner",
	"rackets.protection_laundromat", "rackets.protection_pizzeria",
	"rackets.protection_pawn", "rackets.getaway_loop", "muscle.steel_toes",
]

## Career stages as Ledger node ids. `requires` are closed over by FixtureStats, so these
## are the purchases a player would actually make, not a hand-maintained unlock list.
const FIXTURES := {
	"bare": [],
	"T1": [
		"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
		"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
	],
	"T2": [
		"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
		"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
		"rackets.the_wire", "influence.beat_cop", "muscle.enforcer_corner",
	],
	"T3": T3_LEDGER,
	# T4-T6 are a Capo's ledger plus the forced ring below: what the *table* does with an
	# owned set is the thing under test, and the content for these ranks lands separately.
	"T4": T3_LEDGER,
	"T5": T3_LEDGER,
	"T6": T3_LEDGER,
	"T7": T3_LEDGER,
}

## The ring forced on top of each stage's ledger (see CLUB_SET/DOCKS_SET/PENT_SET).
const FORCED := {
	"bare": [], "T1": [], "T2": [], "T3": [],
	"T4": CLUB_SET,
	"T5": CLUB_SET + DOCKS_SET,
	"T6": CLUB_SET + DOCKS_SET + PENT_SET,
	"T7": CLUB_SET + DOCKS_SET + PENT_SET + DOME_SET,
}
## Untyped: concatenating typed constant arrays yields a plain Array.
const ALL_FORCEABLE: Array = CLUB_SET + DOCKS_SET + PENT_SET + DOME_SET

## Every stage, in career order.
const STAGES: PackedStringArray = ["bare", "T1", "T2", "T3", "T4", "T5", "T6", "T7"]

## Hardware ids checked at every stage. `storefront_laundromat` is deliberately absent: it
## shares its shell with `laundromat_loop`, so the bank is asserted on its own below. The
## later rings' ids are all here so each one stays provably invisible to the careers below
## it — no earlier stage expects one, and the fixtures would fail if a ring leaked downward.
const TRACKED: Array[StringName] = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers",
	&"spinner_numbers", &"orbit_left", &"wire_bank", &"laundromat_loop",
	&"storefront_pizzeria", &"storefront_pawn", &"bribe_target", &"kickback_left",
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
	&"docks", &"containers", &"crane", &"cargo_ramp", &"orbit_right",
	&"penthouse", &"commission_chairs", &"sitdown_saucer", &"penthouse_stairs",
	&"city_hall",
]

const T3_LIVE: Array[StringName] = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers",
	&"spinner_numbers", &"laundromat_loop", &"wire_bank", &"bribe_target",
	&"kickback_left", &"orbit_left", &"storefront_pizzeria", &"storefront_pawn",
]

const EXPECT := {
	"bare": [],
	"T1": [
		&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers",
		&"spinner_numbers", &"laundromat_loop",
	],
	"T2": [
		&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers",
		&"spinner_numbers", &"laundromat_loop", &"wire_bank", &"bribe_target",
		&"kickback_left",
	],
	"T3": T3_LIVE,
	"T4": T3_LIVE + CLUB_SET,
	"T5": T3_LIVE + CLUB_SET + DOCKS_SET,
	"T6": T3_LIVE + CLUB_SET + DOCKS_SET + PENT_SET,
	"T7": T3_LIVE + CLUB_SET + DOCKS_SET + PENT_SET + DOME_SET,
}

var table: ProgressionTable = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

var _earned: Array[Dictionary] = []
var _switches: PackedStringArray = []
var _collected: PackedStringArray = []
var _washes: int = 0
var _orbits: int = 0


func _ready() -> void:
	_rng.seed = SEED
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		_earned.append({"amount": amount.approx_float(), "group": group}))
	Events.switch_hit.connect(func(id: StringName, _b: Node2D, _s: float) -> void:
		_switches.append(String(id)))
	Events.storefront_collected.connect(func(id: StringName) -> void:
		_collected.append(String(id)))
	table.laundromat_pass.connect(func() -> void: _washes += 1)
	table.orbit_completed.connect(func() -> void: _orbits += 1)
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
	check(absf(got - want) <= tol, "%s (got %.4f, want %.4f ±%.4f)" % [msg, got, want, tol])


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if _fails.is_empty() else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


## Install a career stage and let the table rebuild itself around it. The forced ring is
## cleared first, so a stage is exactly what it says it is however the last one was staged.
func use(fixture: String) -> FixtureStats:
	var stats := FixtureStats.new(FIXTURES[fixture])
	Game.stats = stats
	table.force_hardware(ALL_FORCEABLE, false)
	var ring: Array = FORCED[fixture]
	if not ring.is_empty():
		table.force_hardware(ring, true)
	table.refresh_hardware()
	reset_log()
	return stats


func reset_log() -> void:
	Game.heat.reset()
	Game.combo.reset()
	if table.spinner != null:
		table.spinner.kick(0.0)         # a wheel still ticking would salt the next reading
	_earned.clear()
	_switches = PackedStringArray()
	_collected = PackedStringArray()
	_washes = 0
	_orbits = 0


func first_earn() -> Dictionary:
	return _earned[0] if not _earned.is_empty() else {}


func last_earn_in(group: StringName) -> Dictionary:
	for i in range(_earned.size() - 1, -1, -1):
		if _earned[i]["group"] == group:
			return _earned[i]
	return {}


func earned_total() -> float:
	var sum := 0.0
	for e: Dictionary in _earned:
		sum += float(e["amount"])
	return sum


## One effect value read straight out of the shipped Ledger data. These scenarios are about
## the *plumbing* — that a multiplier or a flat add reaches the payout at all — not about
## what design has the number set to this week, so the expected value comes from the same
## file the game reads rather than from a second copy of it in here.
func effect_value(node_id: String, kind: String, target: String) -> float:
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(FixtureStats.FIXTURE_UPGRADES_PATH))
	if not (parsed is Dictionary):
		return 0.0
	for entry: Variant in (parsed as Dictionary).get("nodes", []):
		if not (entry is Dictionary) or String((entry as Dictionary).get("id", "")) != node_id:
			continue
		for effect: Variant in (entry as Dictionary).get("effects", []):
			var e := effect as Dictionary
			if String(e.get("kind", "")) != kind or String(e.get("target", "")) != target:
				continue
			var v: Variant = e.get("value", 0.0)
			return BigMoney.parse(str(v)).approx_float() if v is String else float(v)
	return 0.0


func hit_switch(id: String) -> bool:
	for s in _switches:
		if s == id:
			return true
	return false


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


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M1 table growth sim ==")
	print("physics %d Hz | seed 0x%X" % [Engine.physics_ticks_per_second, SEED])
	await step(4)

	await _s1_fixtures()
	await _s2_dormant_is_absent()
	await _s3_switch_values()
	await _s4_multipliers()
	await _s5_storefront_cycle()
	await _s6_laundromat_loop()
	await _s7_orbit_sequence()
	await _s8_plunger_bands()
	await _s9_raid_hardware()
	await _s10_purchase_refresh()
	await _s11_ball_search()
	await _s12_soak()

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


## 1 — each staged owned-set puts exactly the right hardware on the table.
func _s1_fixtures() -> void:
	for name: String in STAGES:
		begin("fixture %s: presence" % name)
		var stats := use(name)
		var banked := not (name in ["bare", "T1", "T2"])
		check(stats.missing_ids.is_empty(),
				"fixture names ids the content file does not have: %s" % str(stats.missing_ids))
		var want: Array = EXPECT[name]
		var live: PackedStringArray = []
		for id: StringName in TRACKED:
			var present := table.hardware_present(id)
			if present:
				live.append(String(id))
			check(present == want.has(id),
					"%s should be %s at %s" % [id, "present" if want.has(id) else "absent", name])
		# the laundromat's shell arrives with the wash loop; its drop bank is the R3 racket
		var lucky: Storefront = table.storefronts[0]
		check(lucky.bank_enabled == banked,
				"laundromat bank_enabled should be %s at %s" % [banked, name])
		check(lucky.wash_enabled == (name != "bare"),
				"laundromat wash_enabled should be %s at %s" % [name != "bare", name])
		check(table.plunger.bands_enabled == (name != "bare"),
				"plunger bands should be %s at %s" % [name != "bare", name])
		print("        %s: %s" % [name, ", ".join(live) if live.size() > 0 else "(bare alley)"])
		finish()

	begin("the table grows with each ring")
	use("T3")
	var flat := table.bounds()
	near(flat.size.y, ProgressionTable.PLAY_BOTTOM, 0.001, "an M1 career is one screen tall")
	use("T4")
	var with_club := table.bounds()
	check(with_club.size.y > 2700.0, "the Club should make the table ~2.8 screens tall")
	use("T6")
	var whole := table.bounds()
	near(whole.position.y, Penthouse.ROOM_TOP - Penthouse.WALL_THICK * 0.5, 0.001,
			"the Penthouse ceiling is the top of a T6 table")
	check(whole.end.y >= flat.end.y - 0.001, "the empire lost the bottom of the table")
	use("T7")
	var crowned := table.bounds()
	near(crowned.position.y, table.city_hall.bounds().position.y, 0.001,
			"the dome is the top of a T7 table")
	check(crowned.size.y > whole.size.y + 300.0,
			"the crown added only %.0f px of sky" % (crowned.size.y - whole.size.y))
	check(crowned.end.y >= flat.end.y - 0.001, "the crown lost the bottom of the table")
	print("        T3 %.0f px | T4 %.0f px | T6 %.0f px | T7 %.0f px tall"
			% [flat.size.y, with_club.size.y, whole.size.y, crowned.size.y])
	finish()

	begin("bare alley is walls, flippers, one can and a drain")
	use("bare")
	check(table.hardware_present(&"bumper_2") == false, "second can present on a bare table")
	check(table._bumpers[0].visible, "the one dented can is missing")
	check(table.flipper_left != null and table.flipper_right != null, "no flippers")
	check(table.plunger != null, "no plunger")
	near(table.flipper_left.power_scale, 1.0, 0.0001, "bare flipper power")
	finish()


## 2 — dormant means gone: no collider anywhere under a hidden piece.
func _s2_dormant_is_absent() -> void:
	for name: String in STAGES:
		begin("fixture %s: dormant hardware has no collision" % name)
		use(name)
		var checked := 0
		for piece: Dictionary in table.hardware_pieces():
			var node: Node2D = piece["node"]
			var should_be_live := false
			for id: StringName in piece["ids"]:
				if table.hardware_unlocked(id):
					should_be_live = true
					break
			check(node.visible == should_be_live,
					"%s visible=%s but unlocked=%s" % [node.name, node.visible, should_be_live])
			if not should_be_live:
				checked += 1
				check(Dormant.is_collision_off(node),
						"%s is hidden but still collides" % node.name)
		# the raid's cops are never part of an owned set
		for c: StandupTarget in table.cop_targets:
			check(not c.visible and Dormant.is_collision_off(c),
					"cop target %s is on the table outside a raid" % c.name)
		print("        %s: %d dormant pieces, all cold" % [name, checked])
		finish()


## 3 — every live switch pays the number specs/m1-hook.md says it pays.
func _s3_switch_values() -> void:
	begin("switch values (T3)")
	var stats := use("T3")
	check(stats.flipper_power() > 1.0,
			"T3 buys two bat upgrades; Stats reports %.4f" % stats.flipper_power())
	near(table.flipper_left.power_scale, stats.flipper_power(), 0.0001,
			"flippers took the Stats power")

	await _expect_hit("bumper", table._bumpers[0].global_position + Vector2(-73.0, 0.0),
			Vector2.ZERO, "bumper_1", &"bumpers", TableScore.BUMPER)

	var sling: Slingshot = table._slings[0]
	var face: Vector2 = sling.to_global((sling.points[1] + sling.points[2]) * 0.5
			+ sling.face_normal * (Feel.BALL_RADIUS * 0.75))
	await _expect_hit("slingshot", face, Vector2.ZERO, "sling_l", &"slings", TableScore.SLING)

	await _expect_hit("rollover", table.rollovers[1].global_position, Vector2.ZERO,
			"rollover_2", &"rollovers", TableScore.ROLLOVER)

	var phone: StandupTarget = table.wire_bank.targets()[0]
	await _expect_hit("wire payphone", phone.to_global(Vector2(0.0, 38.0)), Vector2.ZERO,
			"wire_1", &"wire", TableScore.WIRE_TARGET)

	# the spinner is a repeat switch: one pass, many segments, decaying
	table.despawn_ball()
	await wait(0.5)
	reset_log()
	await drop_at(table.spinner.global_position + Vector2(0.0, -50.0), Vector2(0.0, 900.0), 6)
	await wait(0.35)
	var spins_after_pass := table.spinner.spins_total
	check(spins_after_pass >= 3, "one pass only span the wheel %d times" % spins_after_pass)
	await wait(2.5)
	var spins_settled := table.spinner.spins_total
	check(spins_settled > spins_after_pass, "the spinner did not keep ticking after the ball left")
	await wait(4.0)
	check(table.spinner.spins_total == spins_settled + 0
			or table.spinner.spins_total >= spins_settled, "spin count went backwards")
	var per_segment := true
	var segments := 0
	for e: Dictionary in _earned:
		if e["group"] == &"spinner":
			segments += 1
			if absf(float(e["amount"]) - TableScore.SPINNER_SEGMENT) > 0.001:
				per_segment = false
	check(per_segment, "a spin segment did not pay %d" % int(TableScore.SPINNER_SEGMENT))
	check(segments == table.spinner.spins_total,
			"%d segments paid for %d spins" % [segments, table.spinner.spins_total])
	print("        spinner: %d segments at $%d, friction stopped it"
			% [segments, int(TableScore.SPINNER_SEGMENT)])
	finish()

	begin("wire bank completion and reset")
	use("T3")
	table.wire_bank.reset_now()
	for t: StandupTarget in table.wire_bank.targets():
		await drop_at(t.to_global(Vector2(0.0, 38.0)))
		await step(3)
	check(table.wire_bank.is_complete(), "three payphones down did not complete the bank")
	var complete := last_earn_in(&"wire")
	check(String(complete.get("group", "")) == "wire", "bank completion paid the wrong group")
	near(float(complete.get("amount", 0.0)), TableScore.BANK_COMPLETE, 0.001,
			"bank completion payout")
	check(hit_switch("wire_bank_complete"), "no wire_bank_complete switch")
	table.despawn_ball()
	await wait(table.wire_bank.reset_seconds + 0.3)
	check(table.wire_bank.marked_count() == 0, "the wire bank never reset")
	print("        wire: 3 × $%d + $%d, reset after %.1fs"
			% [int(TableScore.WIRE_TARGET), int(TableScore.BANK_COMPLETE),
			table.wire_bank.reset_seconds])
	finish()


## One isolated switch reading: everything on the table gets time to finish cooling down
## first, and the assertion is on the *first* payout after the reset — chain position one,
## so the combo multiplier is a known 1.0 and the number under test is the raw one.
func _expect_hit(what: String, at: Vector2, velocity: Vector2, switch_id: String,
		group: StringName, want: float) -> void:
	table.despawn_ball()
	await wait(0.5)
	reset_log()
	await drop_at(at, velocity)
	check(hit_switch(switch_id), "%s: no %s switch" % [what, switch_id])
	var e := first_earn()
	check(not e.is_empty(), "%s: nothing was earned" % what)
	if e.is_empty():
		return
	check(String(e["group"]) == String(group),
			"%s: paid group %s, expected %s" % [what, e["group"], group])
	near(float(e["amount"]), want, 0.001, "%s payout" % what)
	table.despawn_ball()


## 4 — the Ledger's multipliers and flat adds reach the table's payouts.
func _s4_multipliers() -> void:
	begin("stats multipliers reach the switch")
	var can_mult := effect_value("rackets.can_deposits", "value_mult", "bumpers")
	check(can_mult > 1.0, "Can Deposits is not a multiplier any more (%.3f)" % can_mult)
	Game.stats = FixtureStats.new({"rackets.can_deposits": 2})
	table.refresh_hardware()
	reset_log()
	await drop_at(table._bumpers[0].global_position + Vector2(-73.0, 0.0))
	var e := first_earn()
	near(float(e.get("amount", 0.0)), TableScore.BUMPER * can_mult * can_mult, 0.001,
			"two levels of Can Deposits on a $%d can" % int(TableScore.BUMPER))
	table.despawn_ball()

	# The Getaway Loop carries a flat value_add on the orbit group, so a T3 orbit is worth
	# the switch's base plus that add.
	var orbit_add := effect_value("rackets.getaway_loop", "value_add", "orbit")
	check(orbit_add > 0.0, "the Getaway Loop no longer adds to the orbit")
	use("T3")
	await _orbit_run()
	var orbit_pay := last_earn_in(&"orbit")
	near(float(orbit_pay.get("amount", 0.0)), TableScore.ORBIT + orbit_add, 0.001,
			"orbit with the loop's flat add")
	print("        can ×%.4f = $%.2f | orbit $%d + $%.0f add"
			% [can_mult * can_mult, TableScore.BUMPER * can_mult * can_mult,
			int(TableScore.ORBIT), orbit_add])
	finish()


## 5 — knock the bank down, the door opens, the ball collects, the block cools off.
func _s5_storefront_cycle() -> void:
	begin("storefront collect and re-arm")
	use("T3")
	var shop: Storefront = table.storefronts[1]          # Nonna's Pizzeria
	check(shop.open_seconds == 6.0, "door should stand open 6 s (spec), got %.1f" % shop.open_seconds)
	check(shop.rearm_seconds == 20.0, "re-arm should be 20 s (spec), got %.1f" % shop.rearm_seconds)
	shop.open_seconds = 1.5
	shop.rearm_seconds = 1.5

	for t: DropTarget in shop.targets():
		await drop_at(t.to_global(Vector2(0.0, 40.0)))
		await step(3)
	check(shop.down_count() == 3, "only %d of 3 targets went down" % shop.down_count())
	check(shop.is_open(), "the door did not open when the bank went down")

	reset_log()
	var door: Vector2 = shop.to_global(Vector2(0.0, -Storefront.DOOR_DEPTH * 0.5 - 14.0))
	await drop_at(door)
	await step(3)
	check(_collected.has("storefront_pizzeria"), "no storefront_collected for the pizzeria")
	var pay := last_earn_in(&"storefronts")
	var want := TableScore.storefront_idle_per_sec(&"storefront_pizzeria") * 5.0 * 60.0
	check(String(pay.get("group", "")) == "storefronts", "collection paid the wrong group")
	near(float(pay.get("amount", 0.0)), want, 0.5, "collection = collect_minutes × idle rate")
	check(shop.state_name() == &"cooldown", "the shop stayed open after being collected")
	check(shop.down_count() == 0, "the targets stayed down after a collection")
	table.despawn_ball()

	await wait(shop.rearm_seconds + 0.3)
	check(shop.state_name() == &"armed", "the shop never re-armed")

	# nobody came through: the shutters come back down on their own
	for t: DropTarget in shop.targets():
		await drop_at(t.to_global(Vector2(0.0, 40.0)))
		await step(3)
	check(shop.is_open(), "second knock-down did not open the door")
	table.despawn_ball()
	await wait(shop.open_seconds + 0.3)
	check(shop.state_name() == &"armed" and shop.down_count() == 0,
			"an uncollected door did not close itself")
	shop.open_seconds = 6.0
	shop.rearm_seconds = 20.0
	print("        pizzeria: $%.0f collected (5 min × $%.0f/s), re-armed"
			% [want, TableScore.storefront_idle_per_sec(&"storefront_pizzeria")])
	finish()


## 6 — Lucky's door is the wash loop before it is ever a drop bank.
func _s6_laundromat_loop() -> void:
	begin("laundromat loop washes before the bank exists")
	use("T1")
	var lucky: Storefront = table.storefronts[0]
	check(lucky.visible, "the laundromat shell is missing at T1")
	check(not lucky.bank_enabled, "the drop bank should not be fitted at T1")
	check(lucky.is_open(), "a doorway with no shutters should be open")
	reset_log()
	var door: Vector2 = lucky.to_global(Vector2(0.0, -Storefront.DOOR_DEPTH * 0.5 - 14.0))
	await drop_at(door)
	await step(3)
	check(_washes == 1, "the wash pass fired %d times" % _washes)
	check(hit_switch("laundromat_loop"), "no laundromat_loop switch")
	check(_collected.is_empty(), "a bankless laundromat paid a collection")
	check(earned_total() == 0.0, "the wash pass earned dirty money (it launders, it does not pay)")
	table.despawn_ball()

	table.despawn_ball()
	await wait(Storefront.WASH_COOLDOWN + 0.2)
	use("T3")
	check(lucky.bank_enabled, "the drop bank did not arrive at T3")
	check(lucky.wash_enabled, "the wash loop was lost when the bank arrived")
	check(not lucky.is_open(), "the shutters should be back up with a bank fitted")

	# Buying the racket must not take the laundering away: the wash pass is the loop's, and
	# it fires through the doorway whether or not the bank in front of it happens to be down.
	reset_log()
	await drop_at(door)
	await step(3)
	check(_washes == 1, "with the bank fitted, a pass through the door washed %d times"
			% _washes)
	check(_collected.is_empty(), "an armed bank paid a collection")
	table.despawn_ball()
	print("        Lucky's: loop-only at T1, bank + loop at T3, washing either way")
	finish()


## 7 — an orbit is a sequence, not a switch.
func _s7_orbit_sequence() -> void:
	begin("orbit gate sequence")
	use("T3")
	await _orbit_run()
	check(_orbits == 1, "a full traverse scored %d orbits" % _orbits)
	check(hit_switch("orbit_left_entry"), "the entry gate never reported")
	check(hit_switch("orbit_left"), "no orbit_left switch")

	reset_log()
	table.despawn_ball()
	await wait(OrbitLane.WINDOW + 0.5)                 # let any part-run lapse
	await drop_at(table.orbit.exit_position())
	await step(3)
	check(_orbits == 0, "the exit gate alone counted as an orbit")
	table.despawn_ball()

	reset_log()
	await drop_at(table.orbit.entry_position())
	await step(3)
	table.despawn_ball()
	await wait(OrbitLane.WINDOW + 0.4)
	await drop_at(table.orbit.exit_position())
	await step(3)
	check(_orbits == 0, "a stale entry still paid an orbit %.1fs later" % OrbitLane.WINDOW)
	table.despawn_ball()
	print("        entry→exit pays, exit alone and a lapsed entry do not")
	finish()


func _orbit_run() -> void:
	reset_log()
	await drop_at(table.orbit.entry_position())
	await step(3)
	var b := table.ball
	if b != null and is_instance_valid(b):
		b.place(table.orbit.exit_position())
	await step(4)
	table.despawn_ball()


## 8 — the rubber band, and the spring that replaces it.
func _s8_plunger_bands() -> void:
	begin("plunger: rubber band until the real one is bought")
	use("bare")
	check(not table.plunger.bands_enabled, "a bare table has charge bands")
	var bare_speed := await _launch_speed(1.0)
	use("T1")
	check(table.plunger.bands_enabled, "muscle.real_plunger did not fit the spring")
	var full_speed := await _launch_speed(1.0)
	var soft_speed := await _launch_speed(0.5)
	check(bare_speed > 0.0 and full_speed > 0.0, "the plunger did not launch")
	near(bare_speed / maxf(full_speed, 1.0), ProgressionTable.PLUNGER_FIXED_POWER, 0.02,
			"the rubber band should be a fixed %.2f of full power"
			% ProgressionTable.PLUNGER_FIXED_POWER)
	check(soft_speed < full_speed * 0.6, "charge bands are not a range")
	print("        rubber band %.0f px/s | spring 0.5 %.0f | spring 1.0 %.0f"
			% [bare_speed, soft_speed, full_speed])
	finish()


func _launch_speed(power: float) -> float:
	table.despawn_ball()
	await step(2)
	table.spawn_ball()
	await wait(0.35)
	table.plunger.launch(power)
	await step(1)
	var b := table.ball
	var speed := b.speed() if b != null and is_instance_valid(b) else 0.0
	table.despawn_ball()
	await step(2)
	return speed


## 9 — raid hardware comes out on cue and goes away again.
func _s9_raid_hardware() -> void:
	begin("raid: cops, magnet and telegraph")
	use("T3")
	table.set_raid_active(true)
	await step(2)
	for c: StandupTarget in table.cop_targets:
		check(c.visible, "cop %s did not come out" % c.name)
		check(not Dormant.is_collision_off(c), "cop %s is a ghost" % c.name)
	check(table.magnet.active, "the Captain's magnet is not running")
	check(not table.magnet.is_telegraphing(), "the magnet telegraphed immediately")

	reset_log()
	await drop_at(Vector2(490.0, 1000.0))
	await _expect_switch_from_cop()

	await wait(DrainMagnet.PERIOD - DrainMagnet.TELEGRAPH - 0.6)
	check(not table.magnet.is_telegraphing(), "the magnet telegraphed too early")
	await wait(0.9)
	check(table.magnet.is_telegraphing(),
			"no %.1fs telegraph before the pull" % DrainMagnet.TELEGRAPH)

	var b := table.ball
	var before := b.linear_velocity if b != null and is_instance_valid(b) else Vector2.ZERO
	table.magnet_pull()
	await step(1)
	if b != null and is_instance_valid(b):
		check(b.linear_velocity.y > before.y, "the magnet pull did not drag the ball drain-ward")
	table.despawn_ball()

	table.set_raid_active(false)
	await step(2)
	for c: StandupTarget in table.cop_targets:
		check(not c.visible and Dormant.is_collision_off(c),
				"cop %s stayed out after the raid" % c.name)
	check(not table.magnet.active, "the magnet stayed on after the raid")
	print("        4 cops out, %.1fs telegraph, magnet pulls drain-ward, all clear after"
			% DrainMagnet.TELEGRAPH)
	finish()


func _expect_switch_from_cop() -> void:
	var cop: StandupTarget = table.cop_targets[0]
	await drop_at(cop.to_global(Vector2(0.0, 38.0)))
	await step(3)
	check(hit_switch("cop_1"), "hitting a cop produced no switch")
	table.despawn_ball()


## 10 — a purchase mid-night rebuilds the table without a reload.
func _s10_purchase_refresh() -> void:
	begin("Events.upgrade_purchased rebuilds the table")
	use("T2")
	check(not table.hardware_present(&"orbit_left"), "the orbit is already there at T2")
	Game.stats = FixtureStats.new(FIXTURES["T3"])
	Events.upgrade_purchased.emit("rackets.getaway_loop", 1)
	await step(2)
	check(table.hardware_present(&"orbit_left"),
			"the getaway loop did not appear on upgrade_purchased")
	check(table.storefronts[0].bank_enabled, "the laundromat bank did not arrive with it")
	near(table.flipper_left.power_scale, Game.stats.flipper_power(), 0.0001,
			"flipper power did not follow the purchase")
	finish()


## 11 — the coils hunt for a ball that has stopped where it should not have.
func _s11_ball_search() -> void:
	begin("ball search frees a stuck ball")
	use("T3")
	# a one-slot Array, not an int: GDScript lambdas capture locals by value, so a captured
	# counter would be incremented on a copy and read back as zero forever
	var searches := [0]
	var tap := func(_at: Vector2) -> void: searches[0] += 1
	table.ball_searched.connect(tap)

	# A real wedge is a ball with no force left to move it. Holding it in place each tick
	# is the same thing to the table and, unlike balancing one on a rounded cap, it is
	# reproducible: a seeded soak found that perch once and could not be asked to find it
	# again on demand.
	var perch := Vector2(700.0, 950.0)
	var b := await drop_at(perch)
	for i in range(ticks(ProgressionTable.BALL_SEARCH_DELAY - 0.5)):
		b.place(perch)
		await step(1)
	check(int(searches[0]) == 0, "the coils fired before %.1fs of stillness"
			% ProgressionTable.BALL_SEARCH_DELAY)

	var guard := 0
	while int(searches[0]) == 0 and guard < ticks(4.0):
		b.place(perch)
		await step(1)
		guard += 1
	check(int(searches[0]) >= 1, "a ball parked for %.0f s was never searched for"
			% ProgressionTable.BALL_SEARCH_DELAY)
	check(b.speed() > 300.0,
			"the search pulse left the ball at %.0f px/s — not enough to free it" % b.speed())
	check(b.linear_velocity.y < 0.0, "the search pulse shoved the ball drain-ward")
	print("        parked at %s, pulse gave it %.0f px/s up-field" % [perch, b.speed()])
	table.ball_searched.disconnect(tap)
	table.despawn_ball()

	# a cradled ball is resting on purpose and must never be kicked off the bat
	searches[0] = 0
	table.ball_searched.connect(tap)
	table.flipper_left.set_pressed(false)
	await drop_at(table.flipper_left.cradle_point(0.5)
			+ table.flipper_left.strike_normal() * 10.0)
	await wait(ProgressionTable.BALL_SEARCH_DELAY + 1.5)
	check(int(searches[0]) == 0, "the ball search kicked a cradled ball off the bat")
	table.ball_searched.disconnect(tap)
	table.despawn_ball()
	finish()


## 12 — the new geometry has to survive a ball as badly as the old one did.
func _s12_soak() -> void:
	begin("no-tunnel soak on the built-out table (%.0fs)" % SOAK_SECONDS)
	use("T3")
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
	var relaunches := 0
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
			relaunches += 1
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			last = Vector2.INF
			continue
		var p := b.global_position
		if p.x < BOUND_MIN.x or p.x > BOUND_MAX.x or p.y < BOUND_MIN.y or p.y > BOUND_MAX.y:
			escapes += 1
			if escapes <= 3:
				print("        ESCAPE at %s v=%s" % [p, b.linear_velocity])
		if last != Vector2.INF and p.distance_to(last) < 0.5:
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
	print("        served %d | relaunches %d | switches %d | longest still %.2fs at %s"
			% [table.balls_served, relaunches, _switches.size(), stuck, still_at])
	print("        groups hit: %s" % str(groups))
	check(escapes == 0, "the ball escaped the table %d times" % escapes)
	check(_switches.size() > 0, "nothing on the table was ever hit")
	check(stuck < 2.0, "ball sat motionless for %.2fs — wedged in the new geometry" % stuck)
	finish()
