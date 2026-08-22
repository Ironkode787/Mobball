extends RefCounted
## Offline accrual: the Safe cap, and the docs/09 §9 policy that clock weirdness is a
## no-op and never a punishment.


func run(t: TestCtx) -> void:
	_test_basic_accrual(t)
	_test_cap_clamp(t)
	_test_zero_and_negative_elapsed(t)
	_test_degenerate_inputs(t)
	_test_elapsed_clamped(t)
	_test_seconds_to_full(t)
	_test_fill_fraction(t)
	_test_big_scale(t)


func _same(t: TestCtx, got: BigMoney, want: BigMoney, msg: String) -> void:
	if got == null:
		t.fail("%s — got null" % msg)
		return
	t.ok(got.equals_approx(want), "%s — got %s, want %s" % [msg, got.text(), want.text()])


func _test_basic_accrual(t: TestCtx) -> void:
	var rate := BigMoney.from_float(5.0)  # $5/s
	_same(t, Offline.accrue(rate, 60.0, null), BigMoney.of(3.0, 2), "$5/s for a minute is $300")
	_same(t, Offline.accrue(rate, 1.0, null), BigMoney.of(5.0, 0), "$5/s for a second is $5")
	_same(t, Offline.accrue(rate, 3600.0, null), BigMoney.of(1.8, 4), "$5/s for an hour is $18k")
	# Under the cap, the cap does not interfere.
	var cap := Rates.safe_cap(rate)
	_same(t, Offline.accrue(rate, 60.0, cap), BigMoney.of(3.0, 2), "a distant cap changes nothing")


func _test_cap_clamp(t: TestCtx) -> void:
	var rate := BigMoney.from_float(5.0)
	var cap := Rates.safe_cap(rate, Rates.SAFE_CAP_HOURS_BASE)
	_same(t, cap, BigMoney.of(3.6, 4), "the base Safe holds 2h of income ($36k at $5/s)")

	_same(t, Offline.accrue(rate, 7200.0, cap), cap, "exactly 2h fills the Safe")
	_same(t, Offline.accrue(rate, 7199.0, cap), BigMoney.of(3.5995, 4), "a second short is a second short")
	_same(t, Offline.accrue(rate, 86400.0, cap), cap, "a full day away still only fills the Safe")
	_same(t, Offline.accrue(rate, 1e12, cap), cap, "and so does a geological absence")

	# Bigger safes hold more (docs/04 branch B, T1).
	var big_cap := Rates.safe_cap(rate, Rates.safe_cap_hours_for_tier(4))
	_same(t, big_cap, BigMoney.of(4.32, 5), "the 24h Safe holds $432k at $5/s")
	_same(t, Offline.accrue(rate, 86400.0, big_cap), big_cap, "and fills in exactly a day")
	t.eq(Rates.safe_cap_hours_for_tier(0), 2.0, "tier 0 is the 2h base")
	t.eq(Rates.safe_cap_hours_for_tier(99), 24.0, "an out-of-range tier clamps to the last one")
	t.eq(Rates.safe_cap_hours_for_tier(-5), 2.0, "a negative tier clamps to the first one")

	# A zero cap is a real cap of zero, not "uncapped".
	t.ok(Offline.accrue(rate, 3600.0, BigMoney.zero()).is_zero(), "a zero cap accrues nothing")
	t.ok(Offline.accrue(rate, 3600.0, BigMoney.of(-5.0, 3)).is_zero(), "a negative cap accrues nothing")
	t.ok(Rates.safe_cap(rate, 0.0).is_zero(), "a zero-hour safe has no capacity")
	t.ok(Rates.safe_cap(rate, -2.0).is_zero(), "a negative-hour safe has no capacity")
	t.ok(Rates.safe_cap(null).is_zero(), "no rate, no capacity")


func _test_zero_and_negative_elapsed(t: TestCtx) -> void:
	var rate := BigMoney.from_float(5.0)
	var cap := Rates.safe_cap(rate)
	t.ok(Offline.accrue(rate, 0.0, cap).is_zero(), "zero elapsed accrues nothing")
	# docs/09 §9: a backwards clock is a no-op, never a penalty.
	t.ok(Offline.accrue(rate, -1.0, cap).is_zero(), "negative elapsed accrues nothing")
	t.ok(Offline.accrue(rate, -1e9, cap).is_zero(), "a wildly backwards clock accrues nothing")
	t.ok(Offline.accrue(rate, NAN, cap).is_zero(), "NaN elapsed accrues nothing")
	t.ok(Offline.accrue(rate, INF, cap).is_zero(), "INF elapsed accrues nothing")
	t.ok(Offline.accrue(rate, -INF, cap).is_zero(), "-INF elapsed accrues nothing")


func _test_degenerate_inputs(t: TestCtx) -> void:
	var cap := BigMoney.of(1.0, 6)
	t.ok(Offline.accrue(null, 3600.0, cap).is_zero(), "a null rate accrues nothing")
	t.ok(Offline.accrue(BigMoney.zero(), 3600.0, cap).is_zero(), "a zero rate accrues nothing")
	t.ok(Offline.accrue(BigMoney.of(-5.0, 0), 3600.0, cap).is_zero(), "a negative rate accrues nothing")
	# A null cap means uncapped, which is a different thing from a zero cap.
	_same(t, Offline.accrue(BigMoney.from_float(1.0), 1e6, null), BigMoney.of(1.0, 6),
		"a null cap means uncapped")


func _test_elapsed_clamped(t: TestCtx) -> void:
	t.eq(Offline.elapsed_clamped(1000.0, 400.0), 600.0, "elapsed is now minus last seen")
	t.eq(Offline.elapsed_clamped(400.0, 1000.0), 0.0, "a backwards clock clamps to zero")
	t.eq(Offline.elapsed_clamped(1000.0, 1000.0), 0.0, "no time passed is zero")
	t.eq(Offline.elapsed_clamped(NAN, 1000.0), 0.0, "a NaN stamp is zero")
	t.eq(Offline.elapsed_clamped(1000.0, NAN), 0.0, "a NaN last-seen is zero")
	t.eq(Offline.elapsed_clamped(INF, 0.0), 0.0, "an INF stamp is zero")


func _test_seconds_to_full(t: TestCtx) -> void:
	var rate := BigMoney.from_float(5.0)
	var cap := Rates.safe_cap(rate)
	t.near(Offline.seconds_to_full(rate, cap), 7200.0, 1e-6, "the base Safe fills in 2h")
	t.near(Offline.seconds_to_full(rate.mul(2.0), cap), 3600.0, 1e-6, "double the rate, half the time")
	t.ok(is_inf(Offline.seconds_to_full(BigMoney.zero(), cap)), "a zero rate never fills the Safe")
	t.ok(is_inf(Offline.seconds_to_full(rate, null)), "an uncapped Safe never fills")
	t.eq(Offline.seconds_to_full(rate, BigMoney.zero()), 0.0, "a zero-capacity Safe is already full")


func _test_fill_fraction(t: TestCtx) -> void:
	var rate := BigMoney.from_float(5.0)
	var cap := Rates.safe_cap(rate)
	t.near(Offline.fill_fraction(rate, 0.0, cap), 0.0, 1e-9, "nothing away, nothing in the Safe")
	t.near(Offline.fill_fraction(rate, 3600.0, cap), 0.5, 1e-9, "an hour away half fills a 2h Safe")
	t.near(Offline.fill_fraction(rate, 7200.0, cap), 1.0, 1e-9, "two hours fills it")
	t.near(Offline.fill_fraction(rate, 1e9, cap), 1.0, 1e-9, "and it never overfills")
	t.eq(Offline.fill_fraction(rate, 3600.0, null), 0.0, "an uncapped Safe has no fill fraction")
	t.eq(Offline.fill_fraction(rate, -50.0, cap), 0.0, "a backwards clock leaves it empty")


func _test_big_scale(t: TestCtx) -> void:
	# Late-game rates are absurd; the accrual must stay exact and finite.
	var rate := BigMoney.of(4.2, 30)
	var cap := Rates.safe_cap(rate, 24.0)
	_same(t, Offline.accrue(rate, 3600.0, cap), BigMoney.of(1.512, 34), "$4.2No/s for an hour")
	_same(t, Offline.accrue(rate, 1e9, cap), cap, "and the day-long cap still binds")
	t.ok(is_finite(cap.m), "the cap mantissa stays finite")
	t.eq(cap.text(), "$363Dc", "a 24h Safe at $4.2No/s reads as $363Dc")
