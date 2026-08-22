extends RefCounted
## The session model (game/flow/game.gd): the single money path, the rank ladder and the
## state machine. Runs against the live `Game` autoload with its save redirected, because
## that singleton IS the thing under test.

const SAVE_PATH := "user://test_flow_game.json"


func run(t: TestCtx) -> void:
	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()

	_money_path(t)
	_combo_multiplier(t)
	_idle_and_laundering(t)
	_rank_ladder(t)
	_state_machine(t)
	_serialization(t)

	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


func _fresh() -> void:
	Game.new_game(20250822)
	Game.heat.reset()
	Game.combo.reset()


func _money_path(t: TestCtx) -> void:
	_fresh()
	var got := Game.earn_switch(&"bumpers", BigMoney.from_float(10.0))
	t.ok(got.equals_approx(BigMoney.from_float(10.0)), "a bare table pays face value")
	t.ok(Game.wallet.dirty.equals_approx(got), "and it lands in the wallet as dirty")
	t.ok(Game.night_dirty.equals_approx(got), "and is booked for The Count")
	t.ok(Game.heat.pending_units() > 0.0, "hot money feeds the Heat window")

	var earned: Array[BigMoney] = []
	var groups: Array[StringName] = []
	var probe := func(a: BigMoney, g: StringName) -> void:
		earned.append(a)
		groups.append(g)
	Events.dirty_earned.connect(probe)
	Game.earn_switch(&"slings", BigMoney.from_float(5.0))
	Events.dirty_earned.disconnect(probe)
	t.eq(earned.size(), 1, "every payout announces itself once")
	t.eq(groups[0], &"slings", "with its group")

	_fresh()
	Game.heat.value = 75.0
	var hot := Game.earn_switch(&"bumpers", BigMoney.from_float(10.0))
	t.ok(hot.equals_approx(BigMoney.from_float(10.0 * Rates.multiplier_for_band(2))),
			"the Heat band multiplies every dirty payout")


func _combo_multiplier(t: TestCtx) -> void:
	_fresh()
	var a := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0))
	var b := Game.earn_switch(&"slings", BigMoney.from_float(100.0))
	var c := Game.earn_switch(&"spinner", BigMoney.from_float(100.0))
	t.ok(a.equals_approx(BigMoney.from_float(100.0)), "the first shot of a chain is x1")
	t.ok(b.equals_approx(BigMoney.from_float(150.0)), "the second different shot is x1.5")
	t.ok(c.equals_approx(BigMoney.from_float(225.0)), "the third is x2.25")
	t.eq(Game.night_best_combo, 3, "the Night remembers its best chain")
	t.eq(Game.respect, Combo.RESPECT_STARS, "x3 pays Respect")

	var no_combo := Game.earn_switch(&"wire", BigMoney.from_float(100.0), {"no_combo": true})
	t.ok(no_combo.equals_approx(BigMoney.from_float(100.0)), "a no_combo payout is unmultiplied")
	t.eq(Game.combo.count, 3, "and does not extend the chain")


func _idle_and_laundering(t: TestCtx) -> void:
	_fresh()
	Game.earn_idle(BigMoney.from_float(50.0))
	t.ok(Game.wallet.dirty.equals_approx(BigMoney.from_float(50.0)), "the trickle is real money")
	t.ok(Game.night_idle.equals_approx(BigMoney.from_float(50.0)), "tracked separately for The Count")
	t.eq(Game.combo.count, 0, "but it is not a shot: no chain")
	t.near(Game.heat.pending_units(), 0.0, 1e-9, "and it is not hot money either")

	var washed := Game.launder(0.5)
	t.ok(washed.equals_approx(BigMoney.from_float(25.0)), "laundering moves the fraction asked for")
	t.ok(Game.wallet.clean.equals_approx(washed), "into clean")
	t.ok(Game.night_laundered.equals_approx(washed), "and books it for The Count")

	# The per-Night cap counts what has already been washed tonight.
	var cap_left := Game.launder_cap_left()
	t.ok(not cap_left.is_positive(), "with no laundromat bought there is no allowance")


func _rank_ladder(t: TestCtx) -> void:
	_fresh()
	t.eq(Game.rank_for_respect(0), 0, "R0 at zero")
	t.eq(Game.rank_for_respect(9), 0, "still R0 at nine")
	t.eq(Game.rank_for_respect(10), 1, "R1 at ten")
	t.eq(Game.rank_for_respect(49), 1, "R1 holds to fifty")
	t.eq(Game.rank_for_respect(50), 2, "R2 at fifty")
	t.eq(Game.rank_for_respect(150), 3, "R3 at a hundred and fifty")

	var ranks: Array[int] = []
	var probe := func(r: int) -> void: ranks.append(r)
	Events.rank_changed.connect(probe)
	Game.add_respect(9, &"test")
	t.eq(Game.rank, 0, "nine stars is not a promotion")
	t.eq(Game.respect_to_next_rank(), 1, "one star short")
	Game.add_respect(1, &"test")
	t.eq(Game.rank, 1, "the tenth star promotes")
	Game.add_respect(1, &"test")
	Events.rank_changed.disconnect(probe)
	t.eq(ranks, [1], "rank_changed fires once per promotion")
	t.eq(Game.night_respect, 11, "the Night tallies its own stars")
	t.eq(Game.rank_title(), "ERRAND BOY", "and the ladder knows what to call you")


func _state_machine(t: TestCtx) -> void:
	_fresh()
	t.eq(Game.state, &"attract", "a new career opens on the attract screen")

	var states: Array[StringName] = []
	var probe := func(s: StringName) -> void: states.append(s)
	Game.state_changed.connect(probe)

	var started: Array[int] = []
	var start_probe := func(n: int) -> void: started.append(n)
	Events.night_started.connect(start_probe)
	Game.start_night()
	Events.night_started.disconnect(start_probe)
	t.eq(Game.state, &"night", "ROLL CALL starts the Night")
	t.eq(Game.night_no, 1, "which is Night 1")
	t.eq(started, [1], "night_started announced it")
	t.ok(Game.jobs.active.size() >= 1, "with at least one Job slip on the board")

	Game.earn_switch(&"bumpers", BigMoney.from_float(500.0))
	var summary := Game.end_night({"guys_lost": 3, "tilts": 0, "raid": ""})
	t.eq(Game.state, &"count", "the last guy hands over to The Count")
	t.eq(int(summary.get("night", 0)), 1, "the summary knows its Night")
	t.ok((summary.get("dirty", BigMoney.zero()) as BigMoney).is_positive(), "and what was earned")
	t.ok((summary.get("pocket", BigMoney.zero()) as BigMoney).is_positive(),
			"pocket money auto-cleans at The Count")
	t.ok(Game.wallet.clean.is_positive(), "so the first upgrade is affordable")
	t.ok(not String(summary.get("headline", "")).is_empty(), "the paper printed something")

	Game.open_ledger()
	t.eq(Game.state, &"ledger", "The Count opens the Ledger")
	Game.open_ledger()
	t.eq(Game.state, &"ledger", "opening it twice is idempotent")
	Game.close_ledger()
	t.eq(Game.state, &"count", "and closing it comes back to The Count")
	Game.start_night()
	t.eq(Game.night_no, 2, "NEXT NIGHT is Night 2")
	Game.state_changed.disconnect(probe)
	t.eq(states, [&"night", &"count", &"ledger", &"count", &"night"],
			"the state machine only ever walks the paths in the spec")


func _serialization(t: TestCtx) -> void:
	_fresh()
	Game.earn_switch(&"bumpers", BigMoney.from_float(1000.0))
	Game.add_respect(12, &"test")
	Game.buy_upgrade("muscle.real_plunger", BigMoney.zero())
	Game.bench.pinch(Game.bench.guys[0])

	t.ok(Game.save_now(), "save_now wrote the file: %s" % Game.save.last_error)
	var before := JSON.stringify(Game.to_dict())
	Game.new_game(1)
	t.eq(Game.respect, 0, "the wipe took")
	Game.from_dict(Game.save.read())
	t.eq(JSON.stringify(Game.to_dict()), before, "the whole session round-trips")
	t.eq(Game.respect, 12, "respect came back")
	t.eq(Game.rank, 1, "and so did the rank it bought")
	t.ok(Game.stats.flag(&"plunger_bands"), "Stats recomputed from the loaded owned map")
	t.eq(String(Game.bench.guys[0]["state"]), Bench.STATE_HOLDING, "the Bench came back too")
