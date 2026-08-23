extends RefCounted
## Rates: the tuning tables from docs/03 and the cost curves built on them.
## The band table is checked against the doc in tests/test_heat.gd; here the focus is
## the curves — especially `repeatable_cost` at levels that would overflow a float.


func run(t: TestCtx) -> void:
	_test_band_helpers(t)
	_test_rank_scale(t)
	_test_launder_and_safe_constants(t)
	_test_bribe_cost(t)
	_test_bail_cost(t)
	_test_repeatable_cost_small(t)
	_test_repeatable_cost_huge(t)
	_test_repeatable_cost_guards(t)
	_test_tier_bands(t)


func _same(t: TestCtx, got: BigMoney, want: BigMoney, msg: String) -> void:
	if got == null:
		t.fail("%s — got null" % msg)
		return
	t.ok(got.equals_approx(want), "%s — got %s, want %s" % [msg, got.text(), want.text()])


func _test_band_helpers(t: TestCtx) -> void:
	t.eq(Rates.band_for(0.0), 0, "band 0 at zero")
	t.eq(Rates.band_for(39.9999), 0, "band 0 just under 40")
	t.eq(Rates.band_for(40.0), 1, "band 1 at 40")
	t.eq(Rates.band_for(70.0), 2, "band 2 at 70")
	t.eq(Rates.band_for(90.0), 3, "band 3 at 90")
	t.eq(Rates.band_for(100.0), 4, "band 4 (raid) at 100")
	t.eq(Rates.band_for(1e9), 4, "band 4 stays band 4 above 100")
	t.eq(Rates.multiplier_for_band(0), 1.0, "band 0 pays x1.0")
	t.eq(Rates.multiplier_for_band(1), 1.5, "band 1 pays x1.5")
	t.eq(Rates.multiplier_for_band(2), 2.5, "band 2 pays x2.5")
	t.eq(Rates.multiplier_for_band(3), 4.0, "band 3 pays x4.0")
	t.eq(Rates.multiplier_for_band(4), 4.0, "the raid band keeps x4.0")
	t.eq(Rates.multiplier_for_band(-1), 1.0, "an out-of-range band clamps low")
	t.eq(Rates.multiplier_for_band(99), 4.0, "an out-of-range band clamps high")


func _test_rank_scale(t: TestCtx) -> void:
	# Balance-sim ruling: +1 heat per $2K earned at R0, x3.5 per rank (income tracks
	# Ledger multipliers at ~x3-4/rank, so heat stays live at every rank).
	t.ok(Rates.rank_scale(0).equals_approx(BigMoney.of(2.0, 3), 1e-9), "R0 rank scale is $2k")
	t.ok(Rates.rank_scale(1).equals_approx(BigMoney.of(7.0, 3), 1e-9), "R1 is x3.5 of R0")
	t.ok(Rates.rank_scale(7).equals_approx(
			BigMoney.from_float(2000.0 * pow(3.5, 7.0)), 1e-9), "R7 matches 2K x 3.5^7")
	t.ok(Rates.rank_scale(-3).equals_approx(BigMoney.of(2.0, 3), 1e-9),
			"a negative rank clamps to R0")
	for r in 7:
		var here := Rates.rank_scale(r)
		var next := Rates.rank_scale(r + 1)
		t.near(next.ratio_to(here), Rates.RANK_SCALE_PER_RANK_FACTOR, 1e-9,
				"rank %d -> %d is exactly x3.5" % [r, r + 1])


func _test_launder_and_safe_constants(t: TestCtx) -> void:
	_same(t, Rates.pocket_money_per_night(), BigMoney.of(2.0, 2), "Pocket Money washes $200/Night")
	t.eq(Rates.LAUNDER_LOOP_FRACTION, 0.08, "the laundromat loop washes 8% a pass")
	t.ok(Rates.LAUNDER_LOOP_FRACTION_MAX > Rates.LAUNDER_LOOP_FRACTION, "upgrades raise the wash rate")
	t.eq(Rates.LAUNDER_LOOP_FRACTION_MAX, 0.24, "Industrial Washers cap it at 24%")
	t.eq(Rates.SAFE_CAP_HOURS_BASE, 2.0, "the base Safe holds 2h")
	t.eq(Rates.SAFE_CAP_HOURS_TIERS[0], 2.0, "safe tiers start at the base")
	var hours_ascend := true
	for i in Rates.SAFE_CAP_HOURS_TIERS.size() - 1:
		if Rates.SAFE_CAP_HOURS_TIERS[i + 1] <= Rates.SAFE_CAP_HOURS_TIERS[i]:
			hours_ascend = false
	t.ok(hours_ascend, "safe tiers strictly ascend")
	t.eq(Rates.RAID_CONFISCATE_FRACTION, 0.30, "a busted raid takes 30% of held dirty")
	t.eq(Rates.HEAT_WINDOW_SEC, 10.0, "the earn window is 10s")
	t.eq(Rates.HEAT_DECAY_PER_SEC, 0.5, "calm decay is 0.5/s")
	t.eq(Rates.HEAT_CALM_GRACE, 8.0, "the calm grace is 8s")
	t.eq(Rates.BRIBE_HEAT, 20.0, "a bribe is worth 20 heat")
	t.eq(Rates.LAY_LOW_HEAT, 10.0, "laying low is worth 10 heat")


func _test_bribe_cost(t: TestCtx) -> void:
	var first := Rates.bribe_cost(0)
	_same(t, first, BigMoney.of(5.0, 3), "the first bribe of the Night is $5k dirty")
	_same(t, Rates.bribe_cost(1), BigMoney.of(1.0, 4), "the second doubles")
	_same(t, Rates.bribe_cost(2), BigMoney.of(2.0, 4), "the third doubles again")
	_same(t, Rates.bribe_cost(-1), first, "a negative use count reads as the first")
	var prev := Rates.bribe_cost(0)
	for i in range(1, 12):
		var here := Rates.bribe_cost(i)
		t.ok(here.cmp(prev) > 0, "bribe %d costs more than bribe %d" % [i, i - 1])
		t.near(here.ratio_to(prev), Rates.BRIBE_COST_ESCALATOR, 1e-9, "each bribe is x2 the last")
		prev = here
	t.ok(is_finite(Rates.bribe_cost(500).m), "an absurd bribe count stays finite")


func _test_bail_cost(t: TestCtx) -> void:
	_same(t, Rates.bail_cost(0, 0), BigMoney.of(2.5, 2), "a clean rookie posts $250")
	_same(t, Rates.bail_cost(2, 0), BigMoney.of(5.0, 2), "level 2 doubles the base")
	_same(t, Rates.bail_cost(0, 1), BigMoney.of(4.0, 2), "one prior pinch is x1.6")
	_same(t, Rates.bail_cost(3, 2), BigMoney.of(1.6, 3), "level 3 with two priors is $1.6k")
	_same(t, Rates.bail_cost(3, 2, true), BigMoney.of(4.8, 3), "out of a raid, bail is x3")
	_same(t, Rates.bail_cost(-5, -5), Rates.bail_cost(0, 0), "negative inputs clamp to the base case")
	t.ok(Rates.bail_cost(0, 200).cmp(Rates.bail_cost(0, 199)) > 0, "the rap sheet keeps escalating")
	t.ok(is_finite(Rates.bail_cost(0, 500).m), "a 500-pinch rap sheet stays finite")


func _test_repeatable_cost_small(t: TestCtx) -> void:
	var base := BigMoney.of(1.0, 2)  # $100
	_same(t, Rates.repeatable_cost(base, 0), base, "level 0 costs the base price")
	_same(t, Rates.repeatable_cost(base, 1), BigMoney.of(1.15, 2), "level 1 is base x1.15")
	_same(t, Rates.repeatable_cost(base, 2), BigMoney.of(1.3225, 2), "level 2 is base x1.15^2")

	# Cross-check the log10-space curve against naive repeated multiplication, which
	# is still safe at these levels.
	var naive := base.copy()
	for level in range(1, 41):
		naive = naive.mul(Rates.REPEATABLE_GROWTH)
		var got := Rates.repeatable_cost(base, level)
		t.ok(got.equals_approx(naive, 1e-9), "level %d matches repeated multiplication (%s vs %s)"
			% [level, got.text(), naive.text()])

	# Each level is exactly one growth step above the last.
	var prev := Rates.repeatable_cost(base, 100)
	for level in range(101, 111):
		var here := Rates.repeatable_cost(base, level)
		t.near(here.ratio_to(prev), Rates.REPEATABLE_GROWTH, 1e-9, "level %d is x1.15 of the last" % level)
		prev = here

	t.near(Rates.REPEATABLE_GROWTH_LOG10, log(Rates.REPEATABLE_GROWTH) / log(10.0), 1e-15,
		"the cached log10(1.15) matches the computed one")


func _test_repeatable_cost_huge(t: TestCtx) -> void:
	var base := BigMoney.of(1.0, 2)
	# The spec's stress case: level 500 is ~x2.23e30, which a naive float pow would
	# survive but a naive integer accumulator would not. Exponent math handles it flat.
	var l500 := Rates.repeatable_cost(base, 500)
	t.ok(is_finite(l500.m) and not is_nan(l500.m), "level 500 is finite")
	t.eq(l500.e, 32, "level 500 of a $100 node lands at 1e32 scale")
	t.near(l500.m, 2.2331617306581113, 1e-9, "level 500 mantissa matches 1.15^500 x 100")
	t.eq(l500.text(), "$223No", "and it formats")

	# Well past what any float64 can hold on its own.
	var l5000 := Rates.repeatable_cost(base, 5000)
	t.ok(is_finite(l5000.m) and not is_nan(l5000.m), "level 5000 is finite")
	t.eq(l5000.e, 305, "level 5000 lands at 1e305 scale")
	var l50000 := Rates.repeatable_cost(base, 50000)
	t.ok(is_finite(l50000.m) and not is_nan(l50000.m), "level 50000 is finite")
	t.eq(l50000.e, 3036, "level 50000 lands at 1e3036 — far past float64 range")
	t.ok(l50000.m >= 1.0 and l50000.m < 10.0, "and is still normalized")

	# Monotonic all the way up.
	var prev := Rates.repeatable_cost(base, 0)
	var monotonic := true
	for level in range(1, 2001, 37):
		var here := Rates.repeatable_cost(base, level)
		if here.cmp(prev) <= 0:
			monotonic = false
		prev = here
	t.ok(monotonic, "the cost curve is strictly increasing across 2000 levels")


func _test_repeatable_cost_guards(t: TestCtx) -> void:
	var base := BigMoney.of(1.0, 2)
	_same(t, Rates.repeatable_cost(base, -5), base, "a negative level costs the base price")
	t.ok(Rates.repeatable_cost(BigMoney.zero(), 50).is_zero(), "a free node stays free")
	t.ok(Rates.repeatable_cost(null, 50).is_zero(), "a null base is zero, not a crash")
	# The base is not mutated by pricing.
	Rates.repeatable_cost(base, 300)
	_same(t, base, BigMoney.of(1.0, 2), "pricing does not mutate the base cost")


func _test_tier_bands(t: TestCtx) -> void:
	# docs/03 §7: T0 $50–500 · T1 1–10k · T2 10–100k · T3 0.1–1M · T4 1–20M
	#             T5 20–500M · T6 0.5–6B · T7 6B–120B (T6/T7 sim-derived, SIM-2)
	_same(t, Rates.tier_cost_low(0), BigMoney.of(5.0, 1), "T0 starts at $50")
	_same(t, Rates.tier_cost_high(0), BigMoney.of(5.0, 2), "T0 tops out at $500")
	_same(t, Rates.tier_cost_low(4), BigMoney.of(1.0, 6), "T4 starts at $1M")
	_same(t, Rates.tier_cost_high(6), BigMoney.of(6.0, 9), "T6 tops out at $6B")
	_same(t, Rates.tier_cost_high(7), BigMoney.of(1.2, 11), "T7 tops out at $120B")
	t.eq(Rates.TIER_BANDS.size(), 8, "eight tiers, T0..T7")
	var ascending := true
	for tier in 8:
		if Rates.tier_cost_high(tier).cmp(Rates.tier_cost_low(tier)) <= 0:
			ascending = false
		if tier > 0 and Rates.tier_cost_low(tier).cmp(Rates.tier_cost_low(tier - 1)) <= 0:
			ascending = false
	t.ok(ascending, "tier bands ascend and never invert")
	_same(t, Rates.tier_cost_low(-1), Rates.tier_cost_low(0), "an out-of-range tier clamps low")
	_same(t, Rates.tier_cost_high(99), Rates.tier_cost_high(7), "an out-of-range tier clamps high")
