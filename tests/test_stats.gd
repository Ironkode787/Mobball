extends RefCounted
## Stats: the pure recompute of the Ledger (specs/m1-hook.md, specs/ledger-data.md).
##
## Two fixtures on purpose. A synthetic catalog exercises every effect kind and both
## per_level shapes (value^level for multipliers, value×level for everything else) at
## levels the shipped content does not reach; the shipped catalog then proves the same
## folding survives real data, so a tuning commit that breaks an assumption is caught here
## as well as in tests/test_upgrades_data.gd.


func run(t: TestCtx) -> void:
	var fixture := _fixture()
	t.eq(fixture.errors.size(), 0, "the fixture catalog itself is valid: %s" % ", ".join(fixture.errors))
	_test_baseline(t, fixture)
	_test_full_fold(t, fixture)
	_test_per_level_shapes(t, fixture)
	_test_all_group_fold(t, fixture)
	_test_unlock_bridges(t, fixture)
	_test_launder_cap(t, fixture)
	_test_recompute_is_pure(t, fixture)
	_test_bad_owned_input(t, fixture)
	_test_shipped_catalog(t)


# --- fixture ------------------------------------------------------------------


func _node(id: String, tier: int, cost: String, effects: Array, repeat: Variant = null, requires: Array = []) -> Dictionary:
	return {
		"id": id, "branch": "crew", "tier": tier,
		"name": id, "flavor": "flavor", "cost": cost,
		"repeat": repeat, "requires": requires,
		"effects": effects, "table_change": "something appears",
	}


func _fixture() -> Upgrades:
	return Upgrades.from_variant({
		"schema": 1,
		"nodes": [
			_node("crew.root", 0, "100", [
				{"kind": "unlock_hardware", "target": "bumper_2"},
				{"kind": "feature_flag", "target": "plunger_bands"},
			]),
			_node("crew.mult", 0, "200", [
				{"kind": "value_mult", "target": "bumpers", "value": 1.25, "per_level": true},
			], {"max": 5, "growth": 1.2}),
			_node("crew.allmult", 1, "1K", [
				{"kind": "value_mult", "target": "all", "value": 1.1},
			]),
			_node("crew.adds", 1, "2K", [
				{"kind": "value_add", "target": "bumpers", "value": "10"},
				{"kind": "value_add", "target": "all", "value": "5"},
				{"kind": "idle_rate_add", "target": "numbers", "value": "3"},
			], null, ["crew.root"]),
			_node("crew.wash", 2, "20K", [
				{"kind": "launder_rate_add", "value": 0.05, "per_level": true},
				{"kind": "launder_cap_add", "value": "1K", "per_level": true},
				{"kind": "passive_wash_add", "value": 0.01, "per_level": true},
			], {"max": 3, "growth": 1.5}),
			_node("crew.sets", 2, "30K", [
				{"kind": "safe_hours_set", "value": 3, "per_level": true},
				{"kind": "pocket_money_set", "value": "500"},
				{"kind": "job_slots_set", "value": 4},
			], {"max": 4, "growth": 2.0}),
			_node("crew.bench", 3, "300K", [
				{"kind": "bench_slot_add", "value": 2, "per_level": true},
				{"kind": "tilt_leans_add", "value": 1, "per_level": true},
				{"kind": "ball_save_charges", "value": 1, "per_level": true},
			], {"max": 3, "growth": 1.5}),
			_node("crew.kick", 3, "400K", [
				{"kind": "kickback_unlock", "target": "left"},
				{"kind": "kickback_unlock", "target": "right"},
				{"kind": "bribe_unlock"},
			]),
			_node("crew.flip", 3, "500K", [
				{"kind": "flipper_power_mult", "value": 1.5, "per_level": true},
				{"kind": "collect_minutes_mult", "value": 2.0, "per_level": true},
			], {"max": 2, "growth": 2.0}),
			_node("crew.overwash", 3, "600K", [
				{"kind": "launder_rate_add", "value": 0.4},
			]),
			_node("crew.smallpocket", 3, "700K", [
				{"kind": "pocket_money_set", "value": "50"},
				{"kind": "safe_hours_set", "value": 1},
				{"kind": "job_slots_set", "value": 1},
			]),
		],
	}, "test_stats fixture")


func _stats(catalog: Upgrades, owned: Dictionary) -> Stats:
	var s := Stats.new()
	s.catalog = catalog
	s.recompute(owned)
	return s


func _money(t: TestCtx, got: BigMoney, want: String, msg: String) -> void:
	var target := BigMoney.parse(want)
	if got == null:
		t.fail("%s — got null, want %s" % [msg, target.text()])
		return
	t.ok(got.equals_approx(target), "%s — got %s, want %s" % [msg, got.text(), target.text()])


# --- cases --------------------------------------------------------------------


## Nothing owned is not "nothing works": the baselines are the bare alley of docs/02 R0.
func _test_baseline(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {})
	t.eq(s.value_mult(&"bumpers"), 1.0, "no upgrades, no bumper multiplier")
	t.eq(s.value_mult(&"all"), 1.0, "no upgrades, no global multiplier")
	_money(t, s.value_add(&"bumpers"), "0", "no flat adds")
	t.eq(s.hardware_unlocked(&"bumper_2"), false, "the second can is not free")
	t.eq(s.flag(&"plunger_bands"), false, "the plunger is still a rubber band")
	_money(t, s.idle_rate_total(), "0", "no idle income at R0")
	t.eq(s.launder_rate(), 0.0, "no laundromat loop yet")
	_money(t, s.launder_cap(), "0", "no wash cap yet")
	t.eq(s.passive_wash_per_sec(), 0.0, "no passive washer")
	_money(t, s.pocket_money(), "200", "Pocket Money starts at the docs/03 $200")
	t.eq(s.safe_hours(), Rates.SAFE_CAP_HOURS_BASE, "the Safe starts at 2h")
	t.eq(s.bench_slots(), 4, "the Bench opens with four guys")
	t.eq(s.ball_saves(), 0, "no ball saves at R0")
	t.eq(s.tilt_leans(), 3, "three leans, mirroring Feel.TILT_MAX_WARNINGS")
	t.eq(s.flipper_power(), 1.0, "stock flippers")
	t.eq(s.collect_minutes(), 5.0, "storefront collect starts at 5 minutes")
	t.eq(s.job_slots(), 2, "two job slips")
	t.eq(s.kickbacks(), [] as Array[StringName], "no kickbacks")
	t.eq(s.bribe_unlocked(), false, "the Beat Cop has not been met")
	t.eq(s.owned_level("crew.root"), 0, "owned_level of an unowned node is 0")


## One owned-set, every getter — the contract in one place.
func _test_full_fold(t: TestCtx, fixture: Upgrades) -> void:
	var owned := {
		"crew.root": 1, "crew.mult": 3, "crew.allmult": 1, "crew.adds": 1,
		"crew.wash": 2, "crew.sets": 3, "crew.bench": 2, "crew.kick": 1, "crew.flip": 2,
	}
	var s := _stats(fixture, owned)
	t.near(s.value_mult(&"bumpers"), pow(1.25, 3.0) * 1.1, 1e-9, "bumpers: 1.25^3 folded with the global x1.1")
	t.near(s.value_mult(&"all"), 1.1, 1e-9, "the global multiplier itself")
	t.near(s.value_mult(&"spinner"), 1.1, 1e-9, "an untouched group still gets the global fold")
	_money(t, s.value_add(&"bumpers"), "15", "bumper add is its own 10 plus the all-group 5")
	_money(t, s.value_add(&"all"), "5", "the all bucket does not add itself twice")
	_money(t, s.value_add(&"slings"), "5", "an untouched group inherits the all-group add")
	t.eq(s.hardware_unlocked(&"bumper_2"), true, "unlock_hardware is a union")
	t.eq(s.flag(&"plunger_bands"), true, "feature_flag is a union")
	_money(t, s.idle_rate_total(), "3", "idle rates sum")
	t.near(s.launder_rate(), 0.10, 1e-9, "launder_rate_add x2 levels")
	_money(t, s.launder_cap(), "2K", "launder_cap_add x2 levels")
	t.near(s.passive_wash_per_sec(), 0.02, 1e-9, "passive_wash_add x2 levels")
	_money(t, s.pocket_money(), "500", "pocket_money_set beats the $200 base")
	t.near(s.safe_hours(), 9.0, 1e-9, "safe_hours_set 3 at level 3 is 9h")
	t.eq(s.bench_slots(), 8, "4 base + 2 per level x2")
	t.eq(s.tilt_leans(), 5, "3 base + 1 per level x2")
	t.eq(s.ball_saves(), 2, "1 charge per level x2")
	t.near(s.flipper_power(), 2.25, 1e-9, "flipper_power_mult 1.5^2")
	t.near(s.collect_minutes(), 20.0, 1e-9, "5 base x 2.0^2")
	t.eq(s.job_slots(), 4, "job_slots_set takes the highest")
	t.eq(s.kickbacks(), [&"left", &"right"] as Array[StringName], "both kickbacks, in a stable order")
	t.eq(s.bribe_unlocked(), true, "bribe_unlock")
	t.eq(s.owned_level("crew.mult"), 3, "owned_level reports the stored level")


## The two per_level shapes have to stay apart: compounding a flat add (or summing a
## multiplier) is the classic incremental-game balance bug.
func _test_per_level_shapes(t: TestCtx, fixture: Upgrades) -> void:
	for level in [1, 2, 3, 4, 5]:
		var s := _stats(fixture, {"crew.mult": level})
		t.near(s.value_mult(&"bumpers"), pow(1.25, float(level)), 1e-9,
			"multiplicative per_level compounds at level %d" % level)
	for level in [1, 2, 3]:
		var s := _stats(fixture, {"crew.bench": level})
		t.eq(s.bench_slots(), 4 + 2 * level, "additive per_level scales linearly at level %d" % level)
		var w := _stats(fixture, {"crew.wash": level})
		_money(t, w.launder_cap(), str(1000 * level), "money per_level scales linearly at level %d" % level)

	# A level past `repeat.max` is a corrupt save, not a superpower.
	var over := _stats(fixture, {"crew.mult": 99})
	t.near(over.value_mult(&"bumpers"), pow(1.25, 5.0), 1e-9, "level clamps to repeat.max")
	var one_off := _stats(fixture, {"crew.allmult": 7})
	t.near(one_off.value_mult(&"all"), 1.1, 1e-9, "a one-off node cannot be levelled past 1")


func _test_all_group_fold(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {"crew.allmult": 1, "crew.mult": 2})
	for group: StringName in [&"bumpers", &"slings", &"spinner", &"wire", &"storefronts", &"orbit"]:
		var expect := 1.1 * (pow(1.25, 2.0) if group == &"bumpers" else 1.0)
		t.near(s.value_mult(group), expect, 1e-9, "all folds into %s" % group)
	t.near(s.value_mult(&"all"), 1.1, 1e-9, "asking for `all` does not square it")


## Content unlocks a kickback by side and the bribe by name, but the table asks for
## hardware ids (specs/m1-hook.md). Stats is where those two vocabularies meet.
func _test_unlock_bridges(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {"crew.kick": 1})
	t.eq(s.hardware_unlocked(&"kickback_left"), true, "kickback_unlock left lights the left kicker")
	t.eq(s.hardware_unlocked(&"kickback_right"), true, "kickback_unlock right lights the right kicker")
	t.eq(s.hardware_unlocked(&"bribe_target"), true, "bribe_unlock puts the donut shop on the table")
	t.eq(s.hardware_unlocked(&"orbit_left"), false, "nothing else came along for the ride")


func _test_launder_cap(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {"crew.overwash": 1, "crew.wash": 3})
	t.near(s.launder_rate(), Rates.LAUNDER_LOOP_FRACTION_MAX, 1e-9,
		"the loop cannot wash more than the docs/03 24% cap")


## The whole point of "pure recompute": order does not matter, repeats do not accumulate,
## and taking everything away returns the bare alley.
func _test_recompute_is_pure(t: TestCtx, fixture: Upgrades) -> void:
	var owned := {"crew.mult": 3, "crew.allmult": 1, "crew.wash": 2, "crew.sets": 2}
	var s := _stats(fixture, owned)
	var mult_once := s.value_mult(&"bumpers")
	var cap_once := s.launder_cap()
	for i in 4:
		s.recompute(owned)
	t.near(s.value_mult(&"bumpers"), mult_once, 1e-12, "recomputing four times changes nothing")
	t.ok(s.launder_cap().equals_approx(cap_once), "money buckets do not accumulate across recomputes")

	s.recompute({})
	t.eq(s.value_mult(&"bumpers"), 1.0, "respec back to nothing restores the baseline")
	_money(t, s.pocket_money(), "200", "respec restores the Pocket Money base")
	t.eq(s.bench_slots(), 4, "respec restores the Bench base")

	# `set` effects take the best owned, never the last one applied.
	var both := _stats(fixture, {"crew.sets": 1, "crew.smallpocket": 1})
	_money(t, both.pocket_money(), "500", "pocket_money_set keeps the highest")
	t.near(both.safe_hours(), 3.0, 1e-9, "safe_hours_set keeps the highest")
	t.eq(both.job_slots(), 4, "job_slots_set keeps the highest")


func _test_bad_owned_input(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {"crew.gone_in_v2": 4, "crew.mult": 0, "crew.root": -3})
	t.eq(s.hardware_unlocked(&"bumper_2"), false, "a negative level owns nothing")
	t.eq(s.value_mult(&"bumpers"), 1.0, "a zero level owns nothing")
	t.eq(s.bench_slots(), 4, "an id that no longer exists is skipped, not fatal")

	# The owned map handed in must not be aliased: Stats keeps its own copy.
	var owned := {"crew.root": 1}
	var s2 := _stats(fixture, owned)
	owned["crew.kick"] = 1
	t.eq(s2.bribe_unlocked(), false, "mutating the caller's dictionary does not reach Stats")


## The same folding rules against the real content file, at a level set a player could
## actually reach around R2–R3.
func _test_shipped_catalog(t: TestCtx) -> void:
	var s := Stats.new()
	s.recompute({
		"muscle.real_plunger": 1, "rackets.trash_2": 1, "rackets.trash_3": 1,
		"rackets.can_deposits": 3, "muscle.corner_boys": 1, "muscle.fresh_rubbers": 2,
		"muscle.chalk_lines": 1, "rackets.numbers_game": 1, "rackets.fast_fingers": 2,
		"muscle.brass_balls": 1, "fronts.coin_op": 1, "fronts.industrial_washers": 2,
		"fronts.creative_accounting": 1, "fronts.bigger_safe": 2, "crew.bench_depth": 2,
		"influence.coffee_fund": 3, "influence.beat_cop": 1, "muscle.enforcer_corner": 1,
		"rackets.street_tax": 1, "rackets.paper_route": 1, "muscle.second_wind": 1,
		"rackets.protection_laundromat": 1, "rackets.muscle_on_block": 2,
		"fronts.pizzeria_books": 1,
	})
	t.near(s.value_mult(&"bumpers"), pow(1.12, 3.0) * 1.05, 1e-9, "Can Deposits x3 under Brass Balls")
	t.near(s.value_mult(&"spinner"), pow(1.12, 2.0) * 1.05, 1e-9, "Fast Fingers x2 under Brass Balls")
	_money(t, s.value_add(&"slings"), "10", "Street Tax pays the corner boys")
	_money(t, s.idle_rate_total(), "62", "Numbers $2/s plus Lucky's $60/s")
	t.near(s.launder_rate(), 0.08 + 0.04 * 2, 1e-9, "Coin-Op plus two Industrial Washers")
	_money(t, s.launder_cap(), "128K", "$8K plus $60K per washer level")
	t.near(s.passive_wash_per_sec(), 0.01, 1e-9, "Pizzeria Books washes 1%/sec")
	_money(t, s.pocket_money(), "1K", "Creative Accounting")
	t.near(s.safe_hours(), 8.0, 1e-9, "Bigger Safe level 2")
	t.eq(s.bench_slots(), 6, "Bench Depth x2")
	t.eq(s.tilt_leans(), 6, "Coffee Fund x3")
	t.eq(s.ball_saves(), 1, "Second Wind")
	t.near(s.flipper_power(), pow(1.05, 2.0), 1e-9, "Fresh Rubbers x2")
	t.near(s.collect_minutes(), 5.0 * pow(1.12, 2.0), 1e-9, "Muscle on the Block x2")
	t.eq(s.job_slots(), 3, "Paper Route")
	t.eq(s.kickbacks(), [&"left"] as Array[StringName], "The Enforcer's Corner")
	t.eq(s.bribe_unlocked(), true, "Beat Cop on the Take")
	for id: StringName in [
		&"bumper_2", &"bumper_3", &"slingshots", &"rollovers", &"spinner_numbers",
		&"laundromat_loop", &"storefront_laundromat", &"kickback_left", &"bribe_target",
	]:
		t.eq(s.hardware_unlocked(id), true, "%s is live for this owned set" % id)
	for id: StringName in [&"wire_bank", &"orbit_left", &"storefront_pawn", &"inlane_guides"]:
		t.eq(s.hardware_unlocked(id), false, "%s stays dormant for this owned set" % id)
	t.eq(s.flag(&"plunger_bands"), true, "A Real Plunger")
