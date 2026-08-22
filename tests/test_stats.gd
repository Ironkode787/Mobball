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
	_test_fold_table(t)
	_test_specialist_powers(t, fixture)
	_test_specialist_caps(t, fixture)
	_test_min_and_max_buckets(t, fixture)
	_test_specialist_roster(t, fixture)
	_test_docket_preview(t, fixture)
	_test_shipped_catalog(t)


# --- fixture ------------------------------------------------------------------


func _node(id: String, tier: int, cost: String, effects: Array, repeat: Variant = null,
		requires: Array = [], specialist: Variant = null) -> Dictionary:
	return {
		"id": id, "branch": "crew", "tier": tier,
		"name": id, "flavor": "flavor", "cost": cost,
		"repeat": repeat, "requires": requires,
		"effects": effects, "table_change": "something appears",
		"specialist": specialist,
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
			# --- the M2 crew: one node per new effect kind (specs/m2-content.md §2) ---
			_node("crew.skids", 1, "5K", [
				{"kind": "serve_speed_mult", "value": 1.15, "per_level": true},
			], {"max": 5, "growth": 1.2}, [], {"id": "skids", "instrument": "harmonica"}),
			_node("crew.nussbaum", 2, "60K", [
				{"kind": "auto_launder_per_sec", "value": 0.004, "per_level": true},
			], {"max": 6, "growth": 1.3}, [], {"id": "nussbaum", "instrument": "clarinet", "quips": "numbers_nussbaum"}),
			_node("crew.sal", 2, "40K", [
				{"kind": "kickback_cooldown_mult", "value": 0.9, "per_level": true},
			], {"max": 5, "growth": 1.4}, [], {"id": "big_sal", "instrument": "tuba", "quips": "big_sal"}),
			_node("crew.professor", 3, "80K", [
				{"kind": "aim_line", "value": 1, "per_level": true},
			], {"max": 5, "growth": 1.4}, [], {"id": "professor", "instrument": "oboe"}),
			_node("crew.rosa", 3, "50K", [
				{"kind": "all_dirty_mult", "value": 1.05, "per_level": true},
			], {"max": 10, "growth": 1.3}, [], {"id": "rosa", "instrument": "alto_sax"}),
			_node("crew.cohen", 4, "1M", [
				{"kind": "heat_decay_mult", "value": 1.2, "per_level": true},
				{"kind": "bail_discount", "value": 0.05, "per_level": true},
			], {"max": 8, "growth": 1.25}, [], {"id": "cohen", "instrument": "violin"}),
			_node("crew.manny", 4, "2M", [
				{"kind": "auto_collect_interval", "value": 45.0, "per_level": true},
			], {"max": 4, "growth": 1.3}, [], {"id": "manny", "instrument": "cornet"}),
			_node("crew.eddie", 5, "20M", [
				{"kind": "casino_edge_add", "value": 0.01, "per_level": true},
			], {"max": 12, "growth": 1.2}, [], {"id": "eddie_odds", "instrument": "trombone"}),
			_node("crew.consigliere", 5, "30M", [
				{"kind": "job_reroll_add", "value": 1, "per_level": true},
				{"kind": "job_respect_mult", "value": 1.1, "per_level": true},
			], {"max": 6, "growth": 1.3}, [], {"id": "consigliere", "instrument": "cello"}),
			# One-offs that collide with the crew on purpose: caps, min-wins and max-wins.
			_node("crew.slowfix", 4, "900K", [
				{"kind": "auto_collect_interval", "value": 60.0},
			]),
			_node("crew.chalk", 3, "90K", [
				{"kind": "aim_line", "value": 3},
			]),
			_node("crew.bigbail", 5, "5M", [
				{"kind": "bail_discount", "value": 0.5},
			]),
			# Deliberately greedy: 12 levels of Eddie plus this is 0.24, past the Stats cap.
			_node("crew.bigedge", 5, "6M", [
				{"kind": "casino_edge_add", "value": 0.12},
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
	# M2: an uncrewed career must read exactly like the M1 build — every specialist power
	# is identity at zero hires, so the flow/table lanes can multiply by them unconditionally.
	t.eq(s.heat_decay_mult(), 1.0, "Heat decays at the docs/03 rate with no lawyer")
	t.eq(s.bail_discount(), 0.0, "nobody talks the bondsman down")
	t.eq(s.auto_collect_interval(), 0.0, "0 means nobody is collecting for you")
	t.eq(s.casino_edge_add(), 0.0, "the house edge is the house's")
	t.eq(s.job_rerolls(), 0, "no rerolls")
	t.eq(s.job_respect_mult(), 1.0, "a Job pays what the slip says")
	t.eq(s.serve_speed_mult(), 1.0, "the ball takes as long as it takes")
	t.eq(s.auto_launder_per_sec(), 0.0, "no accountant, no automatic wash")
	t.eq(s.kickback_cooldown_mult(), 1.0, "kickbacks cool down at full price")
	t.eq(s.aim_line_level(), 0, "no ghost line on Case the Joint")
	t.eq(s.specialists(), [] as Array[Dictionary], "an empty roster")


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


## The fold table is the contract between the engine and the docket's next-level preview.
## Every kind the loader accepts must name a bucket, or a level preview silently guesses.
func _test_fold_table(t: TestCtx) -> void:
	for kind: Variant in Upgrades.EFFECT_SPECS:
		t.ok(Stats.FOLD.has(kind), "effect kind `%s` names a fold bucket" % kind)
	for kind: Variant in Stats.FOLD:
		t.ok(Upgrades.EFFECT_SPECS.has(kind), "fold bucket `%s` is a kind the loader accepts" % kind)
	t.eq(Stats.fold_of(&"value_mult"), Stats.Fold.PRODUCT, "multipliers compound")
	t.eq(Stats.fold_of(&"value_add"), Stats.Fold.SUM, "flat adds sum")
	t.eq(Stats.fold_of(&"job_slots_set"), Stats.Fold.MAX, "`set` kinds take the highest")
	t.eq(Stats.fold_of(&"auto_collect_interval"), Stats.Fold.MIN, "an interval takes the shortest")
	t.eq(Stats.fold_of(&"bribe_unlock"), Stats.Fold.UNION, "unlocks are unions")
	t.eq(Stats.fold_of(&"not_a_kind"), Stats.Fold.UNION, "an unknown kind folds into nothing")

	# The three per-level shapes, straight off the statics the docket previews with.
	var mult := {"kind": &"value_mult", "num": 1.25, "money": BigMoney.zero(), "per_level": true}
	var add := {"kind": &"bench_slot_add", "num": 2.0, "money": BigMoney.zero(), "per_level": true}
	var interval := {"kind": &"auto_collect_interval", "num": 45.0, "money": BigMoney.zero(), "per_level": true}
	var once := {"kind": &"value_mult", "num": 1.25, "money": BigMoney.zero(), "per_level": false}
	t.near(Stats.scaled_value(mult, 3), pow(1.25, 3.0), 1e-9, "PRODUCT compounds")
	t.near(Stats.scaled_value(add, 3), 6.0, 1e-9, "SUM scales linearly")
	t.near(Stats.scaled_value(interval, 3), 15.0, 1e-9, "MIN divides — three levels, three collects")
	t.near(Stats.scaled_value(once, 9), 1.25, 1e-9, "a one-off ignores the level")
	var money := {"kind": &"launder_cap_add", "num": 0.0, "money": BigMoney.parse("1K"), "per_level": true}
	_money(t, Stats.scaled_money(money, 4), "4K", "money scales linearly")


## Every M2 getter under one owned crew, at levels that separate the shapes.
func _test_specialist_powers(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {
		"crew.skids": 2, "crew.nussbaum": 3, "crew.sal": 3, "crew.professor": 2,
		"crew.rosa": 4, "crew.cohen": 2, "crew.manny": 3, "crew.eddie": 5,
		"crew.consigliere": 2,
	})
	t.near(s.serve_speed_mult(), pow(1.15, 2.0), 1e-9, "Skids: serve speed compounds")
	t.near(s.auto_launder_per_sec(), 0.012, 1e-9, "Nussbaum: 0.4%/sec per level, summed")
	t.near(s.kickback_cooldown_mult(), pow(0.9, 3.0), 1e-9, "Big Sal: cooldown discount compounds")
	t.eq(s.aim_line_level(), 2, "The Professor: the aim line is a level, not a stack")
	t.near(s.value_mult(&"all"), pow(1.05, 4.0), 1e-9, "Rosa folds into the `all` multiplier")
	t.near(s.value_mult(&"bumpers"), pow(1.05, 4.0), 1e-9, "and every group inherits it")
	t.near(s.heat_decay_mult(), pow(1.2, 2.0), 1e-9, "Cohen: Heat decay compounds")
	t.near(s.bail_discount(), 0.10, 1e-9, "Cohen: bail discount sums")
	t.near(s.auto_collect_interval(), 15.0, 1e-9, "Manny: 45s at level 3 is one every 15s")
	t.near(s.casino_edge_add(), 0.05, 1e-9, "Eddie Odds: edge points sum")
	t.eq(s.job_rerolls(), 2, "The Consigliere: a reroll a level")
	t.near(s.job_respect_mult(), pow(1.1, 2.0), 1e-9, "The Consigliere: Job Respect compounds")

	# The M1 surface is untouched by a full crew — nothing here leaks into another bucket.
	t.eq(s.bench_slots(), 4, "hiring the crew does not widen the Bench")
	t.eq(s.job_slots(), 2, "nor the Job board")
	t.near(s.flipper_power(), 1.0, 1e-9, "nor the flippers")


## Two of these are capped by design: influence buys the odds, never the outcome.
func _test_specialist_caps(t: TestCtx, fixture: Upgrades) -> void:
	var s := _stats(fixture, {"crew.cohen": 8, "crew.bigbail": 1, "crew.eddie": 12, "crew.bigedge": 1})
	t.near(s.bail_discount(), Stats.BAIL_DISCOUNT_MAX, 1e-9, "bail discount stops at 60 percent")
	t.near(s.casino_edge_add(), Stats.CASINO_EDGE_MAX, 1e-9, "casino edge stops at 20 points")
	var under := _stats(fixture, {"crew.cohen": 4, "crew.eddie": 3})
	t.near(under.bail_discount(), 0.20, 1e-9, "under the cap the sum is the sum")
	t.near(under.casino_edge_add(), 0.03, 1e-9, "same for the edge")
	# The loader must not be able to author a single effect past the Stats cap. The edge cap is
	# now a TOTAL that two nodes have to sum to (Eddie Odds ×12 + Loaded Dice ×8 = 0.20, the
	# balance-sim ruling), so the loader's per-effect band is allowed to be tighter than it —
	# what it may never be is looser, because then one line of content could own the wheel.
	t.eq(float(Upgrades.EFFECT_SPECS[&"bail_discount"]["max"]), Stats.BAIL_DISCOUNT_MAX,
		"the loader's bail ceiling is the Stats cap")
	t.ok(float(Upgrades.EFFECT_SPECS[&"casino_edge_add"]["max"]) <= Stats.CASINO_EDGE_MAX,
		"the loader lets one effect author %.2f of a %.2f cap"
		% [float(Upgrades.EFFECT_SPECS[&"casino_edge_add"]["max"]), Stats.CASINO_EDGE_MAX])


func _test_min_and_max_buckets(t: TestCtx, fixture: Upgrades) -> void:
	t.near(_stats(fixture, {"crew.slowfix": 1}).auto_collect_interval(), 60.0, 1e-9,
		"one collector, its own interval")
	t.near(_stats(fixture, {"crew.slowfix": 1, "crew.manny": 1}).auto_collect_interval(), 45.0, 1e-9,
		"the faster hire wins")
	t.near(_stats(fixture, {"crew.slowfix": 1, "crew.manny": 4}).auto_collect_interval(), 11.25, 1e-9,
		"and keeps winning as he levels")
	# Order must not matter: MIN starts from "nobody", not from zero.
	t.near(_stats(fixture, {"crew.manny": 1, "crew.slowfix": 1}).auto_collect_interval(), 45.0, 1e-9,
		"the fold does not depend on owned-map order")

	t.eq(_stats(fixture, {"crew.chalk": 1}).aim_line_level(), 3, "a one-off aim line is its own level")
	t.eq(_stats(fixture, {"crew.chalk": 1, "crew.professor": 2}).aim_line_level(), 3,
		"aim line takes the highest, it does not add")
	t.eq(_stats(fixture, {"crew.chalk": 1, "crew.professor": 5}).aim_line_level(), 5,
		"until the levelled one passes it")


func _test_specialist_roster(t: TestCtx, fixture: Upgrades) -> void:
	t.eq(fixture.specialists().size(), 9, "the catalog knows every hireable specialist")
	t.eq(fixture.is_specialist("crew.sal"), true, "Big Sal is a person")
	t.eq(fixture.is_specialist("crew.chalk"), false, "a chalkboard is not")

	var s := _stats(fixture, {"crew.sal": 3, "crew.rosa": 1, "crew.mult": 2})
	var roster := s.specialists()
	t.eq(roster.size(), 2, "only the hired ones report for work")
	var sal: Dictionary = roster[0]
	t.eq(String(sal["id"]), "big_sal", "descriptor carries the specialist id")
	t.eq(String(sal["node"]), "crew.sal", "and the node that hired him")
	t.eq(String(sal["instrument"]), "tuba", "and his voice (docs/08 §5)")
	t.eq(String(sal["quips"]), "big_sal", "and his one-liner table")
	t.eq(int(sal["level"]), 3, "and the level he is at")
	t.eq(int(sal["max_level"]), 5, "and how far he goes")
	t.eq(String(sal["branch"]), "crew", "specialists are branch D")
	t.eq(String(roster[1]["quips"]), "rosa", "quips defaults to the specialist id")

	# A corrupt save must not hand the mixer a level the content does not sell.
	t.eq(int(_stats(fixture, {"crew.sal": 99}).specialists()[0]["level"]), 5, "level clamps to max")
	t.eq(_stats(fixture, {"crew.root": 1}).specialists(), [] as Array[Dictionary],
		"an ordinary node hires nobody")


## The docket's next-level preview is a promise about the engine, made on the one screen
## where money changes hands. It has to print the number Stats will actually fold, and the
## delta has to be the arithmetic difference of the two lines above it — not a re-derivation.
func _test_docket_preview(t: TestCtx, fixture: Upgrades) -> void:
	var mult: Dictionary = (fixture.def("crew.mult")["effects"] as Array)[0]
	t.ok(LedgerStyle.effect_line(mult).ends_with("per level"), "an unlevelled line still says per level")
	t.eq(LedgerStyle.effect_line_at(mult, 3),
		"%s on bumpers hits" % LedgerStyle.percent(_stats(fixture, {"crew.mult": 3}).value_mult(&"bumpers")),
		"the preview prints the multiplier Stats folded")
	# The three numbers on screen have to add up: 95.3 + 48.8 = 144.1, not 95.3 + 48.9.
	t.eq(LedgerStyle.effect_line_at(mult, 3), "+95.3% on bumpers hits", "the NOW line")
	t.eq(LedgerStyle.effect_line_at(mult, 4), "+144.1% on bumpers hits", "the NEXT line")
	t.eq(LedgerStyle.effect_delta(mult, 3), "+48.8%", "and a delta that is the gap between them")

	var bench: Dictionary = (fixture.def("crew.bench")["effects"] as Array)[0]
	t.eq(LedgerStyle.effect_line_at(bench, 2), "+4 Bench slots", "additive levels read as their total")
	t.eq(LedgerStyle.effect_line_at(bench, 3), "+6 Bench slots", "one more level, one more pair")
	t.eq(LedgerStyle.effect_delta(bench, 2), "+2", "with the flat step spelled out")
	var saves: Dictionary = (fixture.def("crew.bench")["effects"] as Array)[2]
	t.eq(LedgerStyle.effect_line_at(saves, 1), "+1 ball save a Night", "one is singular")
	t.eq(LedgerStyle.effect_line_at(saves, 2), "+2 ball saves a Night", "two is not")

	var cap: Dictionary = (fixture.def("crew.wash")["effects"] as Array)[1]
	t.eq(LedgerStyle.effect_line_at(cap, 3), "+$3.00K wash cap per Night", "money folds linearly in the preview")
	t.eq(LedgerStyle.effect_delta(cap, 3), "+$1.00K", "a money delta is the level's own amount")

	var manny: Dictionary = (fixture.def("crew.manny")["effects"] as Array)[0]
	t.eq(LedgerStyle.effect_line_at(manny, 3), "A lit award collects itself every 15s",
		"the MIN bucket previews as the shorter interval")
	t.eq(LedgerStyle.effect_delta(manny, 3), "-3.8s", "and its delta counts down, not up")

	# Every per_level effect in the fixture: the preview must agree with a real recompute.
	for id in fixture.ids():
		var node := fixture.def(id)
		if int(node["max_level"]) < 2:
			continue
		var effects: Array = node["effects"]
		for e: Variant in effects:
			var effect := e as Dictionary
			if not bool(effect["per_level"]):
				continue
			var one := LedgerStyle.effect_line_at(effect, 1)
			var two := LedgerStyle.effect_line_at(effect, 2)
			t.ok(one != two, "%s/%s: a level visibly changes the line" % [id, effect["kind"]])
			t.eq(LedgerStyle.effect_line_at(effect, 1), LedgerStyle.effect_line(_one_off(effect)),
				"%s/%s: level 1 reads like the one-off it is" % [id, effect["kind"]])


func _one_off(effect: Dictionary) -> Dictionary:
	var out := effect.duplicate()
	out["per_level"] = false
	return out


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
