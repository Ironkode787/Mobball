extends RefCounted
## HeatMeter: the band table from docs/03 §4, the windowed-earn approximation, calm
## decay and its grace period, bribes, and the raid latch.
##
## Every test drives the clock by hand — the meter never reads time itself.


func run(t: TestCtx) -> void:
	_test_initial_state(t)
	_test_band_table(t)
	_test_band_signal(t)
	_test_earn_credits_over_the_window(t)
	_test_step_size_independence(t)
	_test_earn_guards(t)
	_test_calm_grace_and_decay(t)
	_test_decay_step_size_independence(t)
	_test_tick_guards(t)
	_test_scripted_night(t)
	_test_bribe_and_lay_low(t)
	_test_raid_latch(t)
	_test_reset_paths(t)
	_test_federal_stage(t)
	_test_scales(t)
	_test_extreme_earn(t)
	_test_serialization(t)


# --- helpers ------------------------------------------------------------------


## A meter with decay switched off, so credit math can be checked in isolation.
func _quiet_meter() -> HeatMeter:
	var h := HeatMeter.new()
	h.decay_scale = 0.0
	return h


func _r0() -> BigMoney:
	return Rates.rank_scale(0)


# --- tests --------------------------------------------------------------------


func _test_initial_state(t: TestCtx) -> void:
	var h := HeatMeter.new()
	t.eq(h.value, 0.0, "fresh meter is cold")
	t.eq(h.band(), 0, "fresh meter is band 0")
	t.eq(h.multiplier(), 1.0, "band 0 pays x1.0")
	t.eq(h.max_value(), 100.0, "ceiling is 100 until the federal stage")
	t.ok(not h.is_raid_pending(), "no raid pending")
	t.eq(h.pending_units(), 0.0, "no earnings in the window")
	t.eq(HeatMeter.new(55.0).value, 55.0, "a meter can be constructed warm")
	t.eq(HeatMeter.new(-10.0).value, 0.0, "a negative start clamps to zero")
	t.eq(HeatMeter.new(500.0).value, 100.0, "an over-max start clamps to the ceiling")


func _test_band_table(t: TestCtx) -> void:
	# docs/03 §4, exactly: 0–39 x1.0 | 40–69 x1.5 | 70–89 x2.5 | 90–99 x4.0 | 100 RAID.
	var table: Array = [
		[0.0, 0, 1.0], [1.0, 0, 1.0], [39.0, 0, 1.0], [39.999, 0, 1.0],
		[40.0, 1, 1.5], [55.0, 1, 1.5], [69.999, 1, 1.5],
		[70.0, 2, 2.5], [80.0, 2, 2.5], [89.999, 2, 2.5],
		[90.0, 3, 4.0], [95.0, 3, 4.0], [99.999, 3, 4.0],
		[100.0, 4, 4.0],
	]
	for row: Array in table:
		var h := HeatMeter.new()
		h.value = float(row[0])
		t.eq(h.band(), int(row[1]), "band at heat %s" % row[0])
		t.eq(h.multiplier(), float(row[2]), "multiplier at heat %s" % row[0])
		t.eq(Rates.heat_multiplier(float(row[0])), float(row[2]), "Rates agrees at heat %s" % row[0])
	t.eq(Rates.BAND_THRESHOLDS.size(), 4, "four band edges")
	t.eq(Rates.band_for(-5.0), 0, "negative heat still reads as band 0")


func _test_band_signal(t: TestCtx) -> void:
	var h := HeatMeter.new()
	var bands: Array = []
	h.band_changed.connect(func(b: int) -> void: bands.append(b))
	var heats: Array = []
	h.heat_changed.connect(func(v: float) -> void: heats.append(v))

	h.value = 20.0
	t.eq(bands.size(), 0, "moving inside a band does not signal")
	t.eq(heats.size(), 1, "but the value change does")
	h.value = 45.0
	t.eq(bands, [1], "crossing into 40 signals band 1")
	h.value = 50.0
	t.eq(bands.size(), 1, "moving inside band 1 does not signal")
	h.value = 95.0
	# A jump that skips a band reports where it landed, not every edge it flew past.
	t.eq(bands, [1, 3], "a jump across two edges signals the band it landed in")
	h.value = 10.0
	t.eq(bands, [1, 3, 0], "falling back down signals the new band")
	h.value = 10.0
	t.eq(heats.size(), 5, "re-assigning the same heat emits nothing")


func _test_earn_credits_over_the_window(t: TestCtx) -> void:
	var h := _quiet_meter()
	# One rank_scale of dirty ($50k at R0) is one unit = +1 heat, spread over ~10s.
	h.on_dirty_earned(_r0(), _r0())
	t.near(h.pending_units(), 1.0, 1e-9, "one rank_scale earned is one pending unit")
	t.eq(h.value, 0.0, "nothing is credited until the clock moves")

	h.tick(Rates.HEAT_WINDOW_SEC)
	t.near(h.value, 1.0 - exp(-1.0), 1e-9, "one window's worth credits 1 - 1/e")
	h.tick(1000.0)
	t.near(h.value, 1.0, 1e-9, "the full +1 lands once the window drains")
	t.near(h.pending_units(), 0.0, 1e-9, "and the window is empty")

	# The total is exactly HEAT_PER_UNIT per rank_scale however it is sliced up.
	var drip := _quiet_meter()
	for i in 100:
		drip.on_dirty_earned(_r0().mul(0.01), _r0())
		drip.tick(0.05)
	drip.tick(1000.0)
	t.near(drip.value, 1.0, 1e-6, "100 small earns credit the same +1 as one big one")

	# Scale: ten rank-scales of dirty is ten units, whatever the scale is set to.
	var burst := _quiet_meter()
	burst.on_dirty_earned(_r0().mul(10.0), _r0())
	burst.tick(1000.0)
	t.near(burst.value, 10.0, 1e-9, "10x the R0 scale is +10 heat")

	# Rank scaling: one R1 rank-scale of dirty at the R1 threshold is one unit.
	var ranked := _quiet_meter()
	ranked.on_dirty_earned(Rates.rank_scale(1), Rates.rank_scale(1))
	ranked.tick(1000.0)
	t.near(ranked.value, 1.0, 1e-9, "one R1-scale haul at R1 is only +1 heat")


func _test_step_size_independence(t: TestCtx) -> void:
	# The window integration is closed-form, so the balance sim can take huge steps.
	var coarse := _quiet_meter()
	coarse.on_dirty_earned(_r0().mul(10.0), _r0())
	coarse.tick(4.0)

	var fine := _quiet_meter()
	fine.on_dirty_earned(_r0().mul(10.0), _r0())
	for i in 400:
		fine.tick(0.01)

	t.near(coarse.value, fine.value, 1e-9, "one 4s step credits what 400 x 10ms steps do")
	t.near(coarse.value, 10.0 * (1.0 - exp(-0.4)), 1e-9, "and matches the closed form")
	t.near(coarse.pending_units(), fine.pending_units(), 1e-9, "the window agrees too")


func _test_earn_guards(t: TestCtx) -> void:
	var h := _quiet_meter()
	h.on_dirty_earned(null, _r0())
	h.on_dirty_earned(_r0(), null)
	h.on_dirty_earned(BigMoney.zero(), _r0())
	h.on_dirty_earned(BigMoney.of(-5.0, 5), _r0())
	h.on_dirty_earned(_r0(), BigMoney.zero())
	h.on_dirty_earned(_r0(), BigMoney.of(-5.0, 4))
	t.eq(h.pending_units(), 0.0, "null / zero / negative earnings never enter the window")
	h.tick(10.0)
	t.eq(h.value, 0.0, "and never raise heat")

	# Dust: earning a millionth of a rank scale is a real, tiny amount of heat.
	h.on_dirty_earned(_r0().mul(1e-6), _r0())
	h.tick(1000.0)
	t.near(h.value, 1e-6, 1e-9, "tiny earnings credit tiny heat")


func _test_calm_grace_and_decay(t: TestCtx) -> void:
	var h := HeatMeter.new()
	h.add_flat(50.0)
	t.eq(h.value, 50.0, "a loud act adds flat heat")
	t.eq(h.calm_seconds(), 0.0, "a loud act breaks the calm")
	t.ok(not h.is_calm(), "and the meter is not calm")

	h.tick(4.0)
	t.eq(h.value, 50.0, "no decay inside the 8s grace")
	h.tick(4.0)
	t.eq(h.value, 50.0, "no decay at exactly the grace boundary")
	t.ok(h.is_calm(), "the grace has now elapsed")
	h.tick(4.0)
	t.near(h.value, 48.0, 1e-9, "decay runs at 0.5/s once calm")

	# A gain event restarts the grace.
	h.add_flat(2.0)
	t.eq(h.calm_seconds(), 0.0, "a loud act restarts the grace")
	h.tick(4.0)
	t.near(h.value, 50.0, 1e-9, "no decay again until the grace elapses")

	# Decay floors at zero, it never goes negative.
	h.tick(1000.0)
	t.eq(h.value, 0.0, "decay floors at zero")
	t.eq(h.band(), 0, "and lands in band 0")

	# add_flat guards.
	h.add_flat(0.0)
	h.add_flat(-10.0)
	h.add_flat(NAN)
	t.eq(h.value, 0.0, "zero / negative / NaN loud acts do nothing")


func _test_decay_step_size_independence(t: TestCtx) -> void:
	var coarse := HeatMeter.new()
	coarse.value = 60.0
	coarse.tick(20.0)

	var fine := HeatMeter.new()
	fine.value = 60.0
	for i in 20:
		fine.tick(1.0)

	t.near(coarse.value, 54.0, 1e-9, "20s with an 8s grace decays 12s worth")
	t.near(coarse.value, fine.value, 1e-9, "one big step decays like many small ones")


func _test_tick_guards(t: TestCtx) -> void:
	var h := HeatMeter.new()
	h.value = 50.0
	h.tick(0.0)
	h.tick(-5.0)
	h.tick(NAN)
	h.tick(INF)
	t.eq(h.value, 50.0, "zero / negative / NaN / INF deltas are no-ops")
	t.eq(h.calm_seconds(), 0.0, "and do not advance the calm timer")

	# Assigning nonsense must not poison the meter either.
	h.value = NAN
	t.eq(h.value, 50.0, "assigning NaN leaves the meter where it was")
	h.value = INF
	t.eq(h.value, 100.0, "assigning INF clamps to the ceiling")
	h.value = -INF
	t.eq(h.value, 0.0, "assigning -INF clamps to the floor")
	h.gain_scale = NAN
	h.add_flat(10.0)
	t.ok(is_finite(h.value), "a NaN gain_scale cannot make the heat NaN")


func _test_scripted_night(t: TestCtx) -> void:
	# A hot streak: six rank-scales of dirty every second. Heat should climb
	# through every band and end in a raid, with the multiplier tracking the table.
	var h := HeatMeter.new()
	# Lambdas capture locals by value, so a counter has to live in a reference type.
	var raids: Array = []
	h.raid_triggered.connect(func() -> void: raids.append(1))
	var seen_bands: Array = []
	h.band_changed.connect(func(b: int) -> void: seen_bands.append(b))

	var last := -1.0
	var monotonic := true
	for i in 30:
		h.on_dirty_earned(_r0().mul(6.0), _r0())
		h.tick(1.0)
		if h.value < last:
			monotonic = false
		last = h.value
		t.ok(h.multiplier() == Rates.heat_multiplier(h.value), "multiplier tracks the table at step %d" % i)

	t.ok(monotonic, "heat climbs monotonically while the earnings keep coming")
	t.eq(h.value, 100.0, "a sustained hot streak pins the meter")
	t.eq(h.band(), 4, "which is the raid band")
	t.eq(h.multiplier(), 4.0, "the raid band still pays x4.0")
	t.eq(seen_bands, [1, 2, 3, 4], "every band was entered exactly once, in order")
	t.eq(raids.size(), 1, "the raid fired exactly once")


func _test_bribe_and_lay_low(t: TestCtx) -> void:
	var h := HeatMeter.new()
	h.value = 50.0
	h.bribe()
	t.eq(h.value, 30.0, "a bribe takes 20 heat")
	t.eq(h.band(), 0, "which can drop a band")

	# Floor at 0, never negative — the adversarial case: bribing at heat 5.
	h.value = 5.0
	h.bribe()
	t.eq(h.value, 0.0, "bribing at heat 5 floors at zero, it does not go negative")
	h.bribe()
	t.eq(h.value, 0.0, "bribing at zero stays at zero")

	# Bribes do not reset the calm grace — a bribe is not a loud act.
	h.value = 40.0
	h.tick(10.0)
	var before := h.value
	h.bribe()
	h.tick(1.0)
	t.near(h.value, before - Rates.BRIBE_HEAT - 0.5, 1e-9, "decay keeps running through a bribe")

	# Escalating cost per use within a Night.
	var c0 := h.bribe_cost(0)
	var c1 := h.bribe_cost(1)
	var c2 := h.bribe_cost(2)
	t.ok(c1.cmp(c0) > 0, "the second bribe of the Night costs more")
	t.ok(c2.cmp(c1) > 0, "and the third costs more again")
	t.ok(c0.equals_approx(Rates.bribe_cost(0)), "HeatMeter.bribe_cost delegates to Rates")
	t.ok(h.bribe_cost(-3).equals_approx(c0), "a negative use count reads as the first bribe")

	h.value = 25.0
	h.lay_low_night()
	t.eq(h.value, 15.0, "laying low takes 10 heat")
	h.value = 5.0
	h.lay_low_night()
	t.eq(h.value, 0.0, "laying low floors at zero too")

	h.value = 50.0
	h.reduce(0.0)
	h.reduce(-5.0)
	h.reduce(NAN)
	t.eq(h.value, 50.0, "zero / negative / NaN reductions do nothing")


func _test_raid_latch(t: TestCtx) -> void:
	var h := HeatMeter.new()
	var raids: Array = []
	h.raid_triggered.connect(func() -> void: raids.append(1))

	h.value = 99.9
	t.eq(raids.size(), 0, "no raid below 100")
	h.value = 100.0
	t.eq(raids.size(), 1, "the raid fires at exactly 100")
	t.ok(h.is_raid_pending(), "and latches")

	# Everything that could double-fire it: more heat, more earnings, more ticks.
	h.value = 100.0
	h.add_flat(50.0)
	h.on_dirty_earned(BigMoney.of(1.0, 9), _r0())
	h.tick(1.0)
	h.tick(60.0)
	t.eq(raids.size(), 1, "the latch holds through more heat, earnings and ticks")

	# Even a dip below 100 and a climb back cannot re-fire it before the reset.
	h.value = 20.0
	t.ok(h.is_raid_pending(), "the latch survives the heat dropping")
	h.value = 100.0
	t.eq(raids.size(), 1, "and re-reaching 100 does not re-fire it")

	h.reset_after_raid(true)
	t.ok(not h.is_raid_pending(), "the reset clears the latch")
	h.value = 100.0
	t.eq(raids.size(), 2, "the next raid fires normally")


func _test_reset_paths(t: TestCtx) -> void:
	var survived := HeatMeter.new()
	survived.value = 100.0
	survived.on_dirty_earned(BigMoney.of(1.0, 9), _r0())
	survived.reset_after_raid(true)
	t.eq(survived.value, Rates.RAID_SURVIVE_HEAT, "surviving a raid resets to 30")
	t.eq(survived.value, 30.0, "which is still a warm band 0")
	t.eq(survived.band(), 0, "band recomputed after the reset")
	t.eq(survived.pending_units(), 0.0, "the pre-raid earn window is cleared")
	survived.tick(1.0)
	t.eq(survived.value, 30.0, "so the meter does not immediately climb again")

	var busted := HeatMeter.new()
	busted.value = 100.0
	busted.reset_after_raid(false)
	t.eq(busted.value, Rates.RAID_BUST_HEAT, "getting busted resets to 0")
	t.eq(busted.value, 0.0, "which is stone cold")

	var fresh := HeatMeter.new()
	fresh.value = 88.0
	fresh.on_dirty_earned(BigMoney.of(1.0, 6), _r0())
	fresh.reset()
	t.eq(fresh.value, 0.0, "reset() (new city) clears the heat")
	t.eq(fresh.pending_units(), 0.0, "and the window")
	t.eq(fresh.calm_seconds(), 0.0, "and the calm timer")
	t.ok(not fresh.is_raid_pending(), "and the latch")


func _test_federal_stage(t: TestCtx) -> void:
	var h := HeatMeter.new()
	t.ok(not h.federal_enabled, "federal heat is off by default")
	h.value = 500.0
	t.eq(h.value, 100.0, "without it, heat clamps at 100")

	h.federal_enabled = true
	t.eq(h.max_value(), Rates.HEAT_FEDERAL_MAX, "the federal ceiling is 200")
	h.value = 150.0
	t.eq(h.value, 150.0, "federal heat goes past 100")
	t.eq(h.band(), 4, "everything past 100 is the raid band")
	h.value = 500.0
	t.eq(h.value, 200.0, "and clamps at 200")

	h.federal_enabled = false
	t.eq(h.value, 100.0, "turning it off re-clamps the current value")


func _test_scales(t: TestCtx) -> void:
	var h := _quiet_meter()
	h.gain_scale = 2.0
	h.on_dirty_earned(_r0(), _r0())
	h.tick(1000.0)
	t.near(h.value, 2.0, 1e-9, "gain_scale multiplies earned heat (loud rackets)")

	var loud := HeatMeter.new()
	loud.gain_scale = 1.5
	loud.add_flat(10.0)
	t.near(loud.value, 15.0, 1e-9, "gain_scale multiplies loud acts too")

	var lawyer := HeatMeter.new()
	lawyer.decay_scale = 2.0
	lawyer.value = 50.0
	lawyer.tick(18.0)
	t.near(lawyer.value, 40.0, 1e-9, "decay_scale doubles calm decay (Lawyer retainer)")

	var frozen := HeatMeter.new()
	frozen.decay_scale = -5.0
	frozen.value = 50.0
	frozen.tick(100.0)
	t.eq(frozen.value, 50.0, "a negative decay_scale cannot heat you up")


func _test_extreme_earn(t: TestCtx) -> void:
	# A payout 300 orders of magnitude past the rank scale must not produce INF/NaN.
	var h := HeatMeter.new()
	var raids: Array = []
	h.raid_triggered.connect(func() -> void: raids.append(1))
	h.on_dirty_earned(BigMoney.of(1.0, 400), _r0())
	t.ok(is_finite(h.pending_units()), "an absurd payout leaves the window finite")
	t.eq(h.pending_units(), HeatMeter.MAX_WINDOW_UNITS, "and saturates it")
	h.tick(0.1)
	t.eq(h.value, 100.0, "the meter pins at the ceiling")
	t.ok(is_finite(h.value), "with a finite value")
	t.eq(raids.size(), 1, "and the raid fires exactly once")

	# Also fine when the rank scale dwarfs the payout.
	var cold := _quiet_meter()
	cold.on_dirty_earned(BigMoney.of(1.0, 0), BigMoney.of(1.0, 400))
	cold.tick(100.0)
	t.eq(cold.value, 0.0, "a payout 400 orders below the scale is no heat at all")


func _test_serialization(t: TestCtx) -> void:
	var h := HeatMeter.new()
	h.federal_enabled = true
	h.value = 120.0
	h.on_dirty_earned(BigMoney.of(1.0, 5), _r0())
	h.tick(1.0)
	var d := h.to_dict()

	var back := HeatMeter.new()
	back.from_dict(d)
	t.near(back.value, h.value, 1e-9, "heat round-trips")
	t.eq(back.federal_enabled, true, "the federal flag round-trips")
	t.eq(back.is_raid_pending(), h.is_raid_pending(), "the raid latch round-trips")
	t.near(back.pending_units(), h.pending_units(), 1e-9, "the earn window round-trips")
	t.near(back.calm_seconds(), h.calm_seconds(), 1e-9, "the calm timer round-trips")
	t.eq(back.band(), h.band(), "the band is recomputed on load")

	var junk := HeatMeter.new()
	junk.from_dict({})
	t.eq(junk.value, 0.0, "loading an empty save is a cold meter, not a broken one")
	t.eq(junk.pending_units(), 0.0, "with an empty window")
