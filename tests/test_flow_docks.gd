extends RefCounted
## THE DOCKS (specs/m3-fall-rise.md FLOW-3): the smuggling run's window and the Sit-Down's
## freeze. Both are pure logic on a fed clock, so this is the whole rule set with no yard
## under it — and then the money half against the real `Game`.

const SAVE_PATH := "user://test_flow_docks.json"


func run(t: TestCtx) -> void:
	_window(t)
	_union_not_instant(t)
	_the_truck(t)
	_sitdown_clock(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_shipment_money(t)
	_freeze_is_a_freeze(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the window ---------------------------------------------------------------


func _window(t: TestCtx) -> void:
	var run_state := SmugglingRun.new()
	run_state.begin_night()
	t.ok(not run_state.on_docks_entered(0), "an empty quay is not a shipment")
	t.ok(run_state.on_docks_entered(3), "cargo standing arms the run")
	t.ok(not run_state.on_docks_entered(3), "and a second lap does not re-arm the same run")
	t.near(run_state.time_left, SmugglingRun.RUN_SECONDS, 1e-9, "forty seconds on the clock")

	run_state.tick(SmugglingRun.RUN_SECONDS - 1.0)
	t.ok(run_state.active, "the shipment is hot right up to the buzzer")
	run_state.tick(1.0)
	t.ok(not run_state.active, "then the window closes")
	t.eq(run_state.night_shipments, 0, "a lapsed run ships nothing")

	# A lapsed run leaves the yard exactly as it was, so the mouth is on a cooldown.
	t.ok(not run_state.on_docks_entered(3), "the next lap cannot re-arm inside the same shot")
	run_state.tick(SmugglingRun.RETRIGGER_GAP)
	t.ok(run_state.on_docks_entered(3), "a beat later the yard is live again")
	t.eq(run_state.night_runs, 2, "and both runs are on tonight's book")


func _union_not_instant(t: TestCtx) -> void:
	# Stacks reset on their own six-second clock, so "all three down at once" is not a shot
	# anybody can take: the window remembers which ones went down inside it.
	var run_state := SmugglingRun.new()
	run_state.begin_night()
	run_state.on_docks_entered(3)
	t.ok(not run_state.on_stack_cleared(0), "one stack is not a load")
	run_state.tick(10.0)
	t.ok(not run_state.on_stack_cleared(0), "and the same stack twice is still one stack")
	t.eq(run_state.cleared_count(), 1, "the union counts stacks, not hits")
	run_state.tick(10.0)
	t.ok(not run_state.on_stack_cleared(1), "two")
	run_state.tick(10.0)
	t.ok(run_state.on_stack_cleared(2), "three inside the window is the shipment")
	t.eq(run_state.night_shipments, 1, "booked once")
	t.ok(not run_state.active, "and the run is over")

	# The same union from the state report, for a yard that only says what is down.
	var by_state := SmugglingRun.new()
	by_state.begin_night()
	by_state.on_docks_entered(3)
	t.ok(not by_state.on_containers_state([0, 1]), "two cleared is not a load")
	t.ok(by_state.on_containers_state([2]), "the third completes it however it is reported")

	# Nothing counts outside a window.
	var cold := SmugglingRun.new()
	cold.begin_night()
	t.ok(not cold.on_stack_cleared(0), "crates broken with no run armed are just crates")
	t.eq(cold.cleared_count(), 0, "and nothing accumulates")


func _the_truck(t: TestCtx) -> void:
	var run_state := SmugglingRun.new()
	run_state.begin_night()
	run_state.on_cargo_shipped()
	t.ok(not run_state.hot, "the hoist outside a run is just a ramp")
	run_state.on_docks_entered(3)
	t.ok(not run_state.hot, "a fresh run is cold")
	run_state.on_cargo_shipped()
	t.ok(run_state.hot, "the load reached the truck")
	run_state.abort()
	t.ok(not run_state.active and not run_state.hot, "a drain takes the run and the truck with it")

	# A shipment is minutes of the empire's idle rate, floored so a bare career still gets one.
	var floor_value := BigMoney.of(SmugglingRun.SHIPMENT_FLOOR_MANTISSA,
			SmugglingRun.SHIPMENT_FLOOR_EXP)
	t.ok(SmugglingRun.base_value(BigMoney.zero()).equals_approx(floor_value, 1e-9),
			"no rackets, no scaling — the floor")
	var rate := BigMoney.from_float(1_000.0)
	t.ok(SmugglingRun.base_value(rate).equals_approx(
			rate.mul(SmugglingRun.SHIPMENT_MINUTES * 60.0), 1e-9),
			"an empire prices its own load")


func _sitdown_clock(t: TestCtx) -> void:
	var room := SitDown.new()
	room.begin_night()
	t.ok(room.begin(SitDown.SECONDS), "the saucer opens a negotiation")
	t.ok(room.active, "which is running")
	t.ok(not room.begin(SitDown.SECONDS), "walking back in does not start a second one")
	t.near(room.time_left, SitDown.SECONDS, 1e-9, "but it does refresh the room")
	t.eq(room.night_sitdowns, 1, "one Sit-Down tonight")
	t.ok(not room.tick(SitDown.SECONDS - 1.0), "it is not over early")
	t.ok(room.tick(1.0), "and it reports the tick it ends on")
	t.ok(not room.active, "then the meter is live again")
	t.ok(not room.tick(1.0), "and it only ends once")


# --- the money ----------------------------------------------------------------


func _shipment_money(t: TestCtx) -> void:
	Game.new_game(7)
	Game.start_night()
	var dirty_before := Game.wallet.dirty
	var heat_before := Game.heat.value

	var plain := Game.smuggling_shipment(false)
	t.ok(plain.is_positive(), "a shipment pays")
	t.ok(Game.wallet.dirty.equals_approx(dirty_before.add(plain), 1e-9),
			"in dirty cash, at face value")
	t.ok(Game.night_group_dirty(&"smuggling").equals_approx(plain, 1e-9),
			"booked on the smuggling line")
	t.ok(Game.heat.value >= heat_before + SmugglingRun.SHIPMENT_HEAT - 1e-6,
			"and a shipment is a loud act")

	# Nothing multiplied it, so the base line moves with it: flat money is its own base.
	t.ok(Game.night_group_base_dirty(&"smuggling").equals_approx(plain, 1e-9),
			"flat money is its own base")

	var hot := Game.smuggling_shipment(true)
	t.ok(hot.equals_approx(plain.mul(SmugglingRun.TRUCK_MULT), 1e-9),
			"the truck run doubles the take")

	# The combo is a chain of shots that landed; a shipment is a payout, not a shot.
	t.eq(Game.combo.count, 0, "and it neither opens nor extends a chain")


func _freeze_is_a_freeze(t: TestCtx) -> void:
	Game.new_game(8)
	Game.start_night()
	Game.heat.value = 50.0
	t.ok(not Game.heat_frozen(), "the meter runs by default")

	Game.sitdown_begin()
	t.ok(Game.heat_frozen(), "a Sit-Down stops it dead")
	var held := Game.heat.value
	Game.heat_add_flat(25.0)
	t.near(Game.heat.value, held, 1e-9, "a loud act does not move a frozen meter")
	Game.earn_flat_dirty(BigMoney.of(9.0, 9), &"smuggling")
	Game.earn_switch(&"bumpers", BigMoney.from_float(1_000_000.0))
	# `Game._process` is the meter's only clock, and it is the clock the freeze stops.
	Game._process(30.0)
	t.near(Game.heat.value, held, 1e-9, "and money made inside the minute is never hot money")
	t.near(Game.heat.pending_units(), 0.0, 1e-9,
			"not even later: the earn window was never fed")

	# It is a freeze, not a discount — the meter is exactly where it was left.
	Game.sitdown.abort()
	t.ok(not Game.heat_frozen(), "the room lets go")
	Game.heat_add_flat(10.0)
	t.ok(Game.heat.value > held, "and the meter is live again")


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(9)
	Game.start_night()
	Game.smuggling.on_docks_entered(3)
	Game.smuggling.on_containers_state([0, 1, 2])
	Game.smuggling.book_payout(BigMoney.of(4.0, 6))
	Game.sitdown_begin()
	var shipped := Game.smuggling.runs_shipped
	var sitdowns := Game.sitdown.sitdowns_total
	t.ok(Game.save_now(), "the career writes")

	Game.new_game(0)
	Game.from_dict(Game.save.read())
	t.eq(Game.smuggling.runs_shipped, shipped, "shipments survive the save")
	t.ok(Game.smuggling.total_paid.is_positive(), "so does what they paid")
	t.eq(Game.sitdown.sitdowns_total, sitdowns, "and the Sit-Downs are on the rap sheet")
	t.ok(not Game.smuggling.active, "a run in progress does not survive a reload")
	t.ok(not Game.sitdown.active, "and no freeze outlives its Night")
