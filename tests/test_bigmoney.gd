extends RefCounted
## BigMoney: normalization, arithmetic across magnitudes, the precision rule, the
## display table (exact strings), parsing, comparison and serialization.


func run(t: TestCtx) -> void:
	_test_construction(t)
	_test_normalization(t)
	_test_non_finite_guards(t)
	_test_display_table(t)
	_test_text_plain(t)
	_test_parse(t)
	_test_parse_text_roundtrip(t)
	_test_add(t)
	_test_precision_rule(t)
	_test_subtraction(t)
	_test_multiplication(t)
	_test_division_and_ratio(t)
	_test_cmp(t)
	_test_min_max(t)
	_test_immutability(t)
	_test_serialization(t)
	_test_huge_scale(t)


# --- helpers ------------------------------------------------------------------


func _money(t: TestCtx, got: BigMoney, want_m: float, want_e: int, msg: String) -> void:
	if got == null:
		t.fail("%s — got null" % msg)
		return
	t.ok(
		absf(got.m - want_m) <= 1e-12 * maxf(1.0, absf(want_m)) and got.e == want_e,
		"%s — got (m=%s, e=%s), want (m=%s, e=%s)" % [msg, got.m, got.e, want_m, want_e]
	)


func _same(t: TestCtx, got: BigMoney, want: BigMoney, msg: String) -> void:
	if got == null:
		t.fail("%s — got null" % msg)
		return
	t.ok(got.equals_approx(want), "%s — got %s, want %s" % [msg, got.text(), want.text()])


# --- tests --------------------------------------------------------------------


func _test_construction(t: TestCtx) -> void:
	_money(t, BigMoney.zero(), 0.0, 0, "zero()")
	t.ok(BigMoney.zero().is_zero(), "zero is_zero")
	t.ok(not BigMoney.zero().is_positive(), "zero is not positive")
	t.ok(not BigMoney.zero().is_negative(), "zero is not negative")
	t.eq(BigMoney.zero().sign_of(), 0, "sign of zero")

	_money(t, BigMoney.new(), 0.0, 0, "default ctor")
	_money(t, BigMoney.from_float(482.0), 4.82, 2, "from_float(482)")
	_money(t, BigMoney.from_float(-482.0), -4.82, 2, "from_float(-482)")
	_money(t, BigMoney.from_float(0.0), 0.0, 0, "from_float(0)")
	_money(t, BigMoney.of(1.0, 30), 1.0, 30, "of(1, 30)")
	t.eq(BigMoney.of(-3.0, 5).sign_of(), -1, "sign of negative")
	t.eq(BigMoney.from_float(1.0).sign_of(), 1, "sign of positive")


func _test_normalization(t: TestCtx) -> void:
	_money(t, BigMoney.of(1234.5, 0), 1.2345, 3, "mantissa >= 10 normalizes up")
	_money(t, BigMoney.of(1234.5, 5), 1.2345, 8, "mantissa >= 10 keeps exponent offset")
	_money(t, BigMoney.of(0.00042, 3), 4.2, -1, "mantissa < 1 normalizes down")
	_money(t, BigMoney.of(-0.5, 0), -5.0, -1, "negative mantissa normalizes")
	_money(t, BigMoney.of(0.0, 42), 0.0, 0, "zero mantissa forces exponent 0")
	_money(t, BigMoney.of(-0.0, 42), 0.0, 0, "negative zero collapses to zero")
	_money(t, BigMoney.of(10.0, 0), 1.0, 1, "exactly 10 carries")
	_money(t, BigMoney.of(9.999999999, 0), 9.999999999, 0, "just under 10 stays")
	_money(t, BigMoney.of(1.0, 0), 1.0, 0, "exactly 1 stays")
	# Big mantissa + big exponent together: no float overflow anywhere. (Compared
	# approximately: log10 of a value that is not exactly 10^n can land either side of
	# a decade boundary, and 9.99…e799 == 1.0e800 as far as money is concerned.)
	_same(t, BigMoney.of(1e300, 500), BigMoney.of(1.0, 800), "huge mantissa folds into exponent")
	_same(t, BigMoney.of(1e-300, -500), BigMoney.of(1.0, -800), "tiny mantissa folds into exponent")

	var deep := BigMoney.of(1.0, -BigMoney.MAX_EXP - 10)
	t.ok(deep.is_zero(), "exponent underflow collapses to zero")
	var high := BigMoney.of(1.0, BigMoney.MAX_EXP + 10)
	t.eq(high.e, BigMoney.MAX_EXP, "exponent saturates at MAX_EXP")


func _test_non_finite_guards(t: TestCtx) -> void:
	t.ok(BigMoney.of(NAN, 5).is_zero(), "NaN mantissa collapses to zero")
	t.ok(BigMoney.from_float(NAN).is_zero(), "from_float(NaN) is zero")
	var pos_inf := BigMoney.of(INF, 0)
	t.eq(pos_inf.e, BigMoney.MAX_EXP, "INF saturates the exponent")
	t.ok(pos_inf.is_positive(), "INF keeps its sign")
	var neg_inf := BigMoney.of(-INF, 0)
	t.ok(neg_inf.is_negative(), "-INF keeps its sign")
	t.ok(BigMoney.from_float(1.0).mul(NAN).is_zero(), "mul by NaN is zero, not NaN")
	t.ok(BigMoney.from_float(1.0).mul(INF).is_zero(), "mul by INF is zero, not INF")
	t.ok(BigMoney.from_float(1.0).div(0.0).is_zero(), "div by zero is zero, not INF")
	t.ok(BigMoney.from_float(1.0).div_big(BigMoney.zero()).is_zero(), "div_big by zero is zero")
	t.ok(not is_nan(BigMoney.of(NAN, 0).approx_float()), "no NaN escapes approx_float")


func _test_display_table(t: TestCtx) -> void:
	# Exact expected strings — the display contract. Three significant digits,
	# short-scale suffixes, scientific past Dc.
	var table: Array = [
		[BigMoney.zero(), "$0"],
		[BigMoney.of(4.82, 2), "$482"],
		[BigMoney.of(1.25, 4), "$12.5K"],
		[BigMoney.of(3.4, 6), "$3.40M"],
		[BigMoney.of(7.77, 12), "$7.77T"],
		[BigMoney.of(1.0, 0), "$1.00"],
		[BigMoney.of(9.99, 2), "$999"],
		[BigMoney.of(1.0, 3), "$1.00K"],
		[BigMoney.of(4.5678, 4), "$45.7K"],
		[BigMoney.of(9.99999, 5), "$1.00M"],
		[BigMoney.of(1.0, 9), "$1.00B"],
		[BigMoney.of(1.5, 15), "$1.50Qa"],
		[BigMoney.of(1.0, 18), "$1.00Qi"],
		[BigMoney.of(1.0, 21), "$1.00Sx"],
		[BigMoney.of(1.0, 24), "$1.00Sp"],
		[BigMoney.of(1.0, 27), "$1.00Oc"],
		[BigMoney.of(1.0, 30), "$1.00No"],
		[BigMoney.of(1.0, 33), "$1.00Dc"],
		[BigMoney.of(9.99, 35), "$999Dc"],
		[BigMoney.of(9.999, 35), "$1.0e36"],
		[BigMoney.of(1.0, 36), "$1.0e36"],
		[BigMoney.of(1.234, 40), "$1.2e40"],
		[BigMoney.of(1.0, 300), "$1.0e300"],
		[BigMoney.of(-5.0, 0), "-$5.00"],
		[BigMoney.of(-1.25, 4), "-$12.5K"],
		[BigMoney.of(5.0, -1), "$0.50"],
		[BigMoney.of(5.0, -2), "$0.05"],
		[BigMoney.of(1.0, -5), "$0.00"],
		[BigMoney.of(1.0, 2), "$100"],
		[BigMoney.of(9.996, 1), "$100"],
		[BigMoney.of(9.996, 0), "$10.0"],
		[BigMoney.of(1.0, 20), "$100Qi"],
	]
	for row: Array in table:
		var v: BigMoney = row[0]
		t.eq(v.text(), String(row[1]), "text() of (m=%s, e=%s)" % [v.m, v.e])
	# _to_string() is the same contract, so failures print readably.
	t.eq(str(BigMoney.of(3.4, 6)), "$3.40M", "_to_string mirrors text()")


func _test_text_plain(t: TestCtx) -> void:
	t.eq(BigMoney.zero().text_plain(), "0", "text_plain zero")
	t.eq(BigMoney.of(1.25, 4).text_plain(), "12.5K", "text_plain drops the $")
	t.eq(BigMoney.of(-1.25, 4).text_plain(), "-12.5K", "text_plain keeps the sign")
	t.eq(BigMoney.of(1.234, 40).text_plain(), "1.2e40", "text_plain scientific")


func _test_parse(t: TestCtx) -> void:
	_money(t, BigMoney.parse("1234"), 1.234, 3, "parse plain integer")
	_money(t, BigMoney.parse("12.5K"), 1.25, 4, "parse K suffix")
	_money(t, BigMoney.parse("3.2M"), 3.2, 6, "parse M suffix")
	_money(t, BigMoney.parse("1e30"), 1.0, 30, "parse scientific")
	_money(t, BigMoney.parse("1E+30"), 1.0, 30, "parse scientific, upper case and +")
	_money(t, BigMoney.parse("7.77T"), 7.77, 12, "parse T suffix")
	_money(t, BigMoney.parse("1.5Qa"), 1.5, 15, "parse two-letter suffix Qa")
	_money(t, BigMoney.parse("2Dc"), 2.0, 33, "parse two-letter suffix Dc")
	_money(t, BigMoney.parse("$1,234.50"), 1.2345, 3, "parse currency mark and separators")
	_money(t, BigMoney.parse("-5"), -5.0, 0, "parse negative")
	_money(t, BigMoney.parse("-$12.5k"), -1.25, 4, "parse negative, lower-case suffix")
	_money(t, BigMoney.parse("  42  "), 4.2, 1, "parse trims whitespace")
	_money(t, BigMoney.parse("+7"), 7.0, 0, "parse leading plus")
	_money(t, BigMoney.parse("1.2e40"), 1.2, 40, "parse big scientific without float overflow")
	_money(t, BigMoney.parse("1e-6"), 1.0, -6, "parse negative exponent")

	# Garbage is zero, never a crash and never a NaN.
	for junk in ["", "   ", "abc", "$", "-", "12.5Zz", "e10", "1e", "1eX"]:
		var v := BigMoney.parse(junk)
		t.ok(v.is_zero(), "parse(%s) is zero" % [junk if junk != "" else "<empty>"])


func _test_parse_text_roundtrip(t: TestCtx) -> void:
	# text() keeps three significant digits, so round-tripping is exact for values
	# that fit in three.
	for v: BigMoney in [
		BigMoney.of(4.82, 2),
		BigMoney.of(1.25, 4),
		BigMoney.of(3.4, 6),
		BigMoney.of(7.77, 12),
		BigMoney.of(1.5, 15),
		BigMoney.of(2.0, 33),
		BigMoney.of(-1.25, 4),
	]:
		_same(t, BigMoney.parse(v.text()), v, "round-trip %s" % v.text())
		_same(t, BigMoney.parse(v.text_plain()), v, "round-trip plain %s" % v.text_plain())
	# Scientific display round-trips too (two significant digits up there).
	_same(t, BigMoney.parse(BigMoney.of(1.2, 40).text()), BigMoney.of(1.2, 40), "round-trip sci")
	t.ok(BigMoney.parse(BigMoney.zero().text()).is_zero(), "round-trip zero")


func _test_add(t: TestCtx) -> void:
	_same(t, BigMoney.of(1.0, 3).add(BigMoney.of(1.0, 3)), BigMoney.of(2.0, 3), "add same magnitude")
	_same(t, BigMoney.of(9.0, 2).add(BigMoney.of(2.0, 2)), BigMoney.of(1.1, 3), "add carries")
	_same(t, BigMoney.of(1.0, 6).add(BigMoney.of(5.0, 5)), BigMoney.of(1.5, 6), "add across one order")
	_same(t, BigMoney.of(5.0, 5).add(BigMoney.of(1.0, 6)), BigMoney.of(1.5, 6), "add is commutative")
	_same(t, BigMoney.zero().add(BigMoney.of(4.0, 2)), BigMoney.of(4.0, 2), "zero + x")
	_same(t, BigMoney.of(4.0, 2).add(BigMoney.zero()), BigMoney.of(4.0, 2), "x + zero")
	_same(t, BigMoney.of(4.0, 2).add(null), BigMoney.of(4.0, 2), "x + null is a no-op")
	_same(t, BigMoney.of(5.0, 0).add(BigMoney.of(-5.0, 0)), BigMoney.zero(), "x + (-x) is zero")
	_same(t, BigMoney.of(1.0, 3).add(BigMoney.of(-5.0, 2)), BigMoney.of(5.0, 2), "add a negative")
	_same(t, BigMoney.of(-1.0, 3).add(BigMoney.of(-1.0, 3)), BigMoney.of(-2.0, 3), "add two negatives")
	# Cancellation renormalizes instead of leaving a denormal mantissa behind.
	var tiny := BigMoney.of(1.0, 10).add(BigMoney.of(-9.99, 9))
	_same(t, tiny, BigMoney.of(1.0, 7), "cancellation renormalizes")


func _test_precision_rule(t: TestCtx) -> void:
	var big := BigMoney.of(1.0, 20)
	# 15+ orders down is a documented no-op...
	_same(t, big.add(BigMoney.of(1.0, 5)), big, "adding 15 orders down is a no-op")
	_same(t, big.add(BigMoney.of(9.9, 4)), big, "adding 16 orders down is a no-op")
	_same(t, big.sub_clamped(BigMoney.of(1.0, 5)), big, "subtracting 15 orders down is a no-op")
	# ...14 orders down still lands.
	t.ok(not big.add(BigMoney.of(1.0, 6)).equals(big), "adding 14 orders down still lands")
	t.eq(BigMoney.PRECISION_ORDERS, 15, "precision rule is 15 orders")
	# The small side of the rule keeps the big side, not the small one.
	_same(t, BigMoney.of(1.0, 5).add(big), big, "small + huge keeps the huge value")


func _test_subtraction(t: TestCtx) -> void:
	_same(t, BigMoney.of(5.0, 3).sub_clamped(BigMoney.of(2.0, 3)), BigMoney.of(3.0, 3), "sub_clamped")
	t.ok(BigMoney.of(5.0, 3).sub_clamped(BigMoney.of(6.0, 3)).is_zero(), "sub_clamped floors at zero")
	t.ok(BigMoney.of(5.0, 3).sub_clamped(BigMoney.of(5.0, 3)).is_zero(), "sub_clamped exact is zero")
	_same(t, BigMoney.of(5.0, 3).sub_clamped(null), BigMoney.of(5.0, 3), "sub_clamped null is a no-op")
	t.ok(BigMoney.of(-5.0, 3).sub_clamped(BigMoney.zero()).is_zero(), "sub_clamped of a negative is zero")

	_same(t, BigMoney.of(5.0, 3).sub_exact(BigMoney.of(2.0, 3)), BigMoney.of(3.0, 3), "sub_exact")
	t.eq(BigMoney.of(5.0, 3).sub_exact(BigMoney.of(6.0, 3)), null, "sub_exact returns null when short")
	t.ok(BigMoney.of(5.0, 3).sub_exact(BigMoney.of(5.0, 3)).is_zero(), "sub_exact of the exact balance")
	_same(t, BigMoney.of(5.0, 3).sub_exact(null), BigMoney.of(5.0, 3), "sub_exact null is a no-op")
	_same(t, BigMoney.of(5.0, 0).neg(), BigMoney.of(-5.0, 0), "neg")
	_same(t, BigMoney.of(-5.0, 0).abs_of(), BigMoney.of(5.0, 0), "abs_of")


func _test_multiplication(t: TestCtx) -> void:
	_same(t, BigMoney.of(1.0, 3).mul(2.0), BigMoney.of(2.0, 3), "mul by 2")
	_same(t, BigMoney.of(5.0, 3).mul(3.0), BigMoney.of(1.5, 4), "mul carries the exponent")
	_same(t, BigMoney.of(1.0, 3).mul(0.08), BigMoney.of(8.0, 1), "mul by a fraction")
	t.ok(BigMoney.of(1.0, 3).mul(0.0).is_zero(), "mul by zero")
	t.ok(BigMoney.zero().mul(5.0).is_zero(), "zero times anything")
	_same(t, BigMoney.of(1.0, 3).mul(-2.0), BigMoney.of(-2.0, 3), "mul by a negative")

	_same(t, BigMoney.of(2.0, 3).mul_big(BigMoney.of(3.0, 4)), BigMoney.of(6.0, 7), "mul_big")
	_same(t, BigMoney.of(5.0, 3).mul_big(BigMoney.of(5.0, 3)), BigMoney.of(2.5, 7), "mul_big carries")
	t.ok(BigMoney.of(1.0, 3).mul_big(BigMoney.zero()).is_zero(), "mul_big by zero")
	t.ok(BigMoney.of(1.0, 3).mul_big(null).is_zero(), "mul_big by null")
	# The whole point of the type: no float64 range anywhere near this.
	_same(t, BigMoney.of(1.0, 300).mul_big(BigMoney.of(1.0, 300)), BigMoney.of(1.0, 600), "1e300 squared")
	_same(t, BigMoney.of(3.0, 200).mul_big(BigMoney.of(4.0, 200)), BigMoney.of(1.2, 401), "3e200 x 4e200")


func _test_division_and_ratio(t: TestCtx) -> void:
	_same(t, BigMoney.of(1.0, 3).div(2.0), BigMoney.of(5.0, 2), "div")
	_same(t, BigMoney.of(6.0, 7).div_big(BigMoney.of(3.0, 4)), BigMoney.of(2.0, 3), "div_big")
	_same(t, BigMoney.of(1.0, 3).shift(3), BigMoney.of(1.0, 6), "shift up")
	_same(t, BigMoney.of(1.0, 3).shift(-3), BigMoney.of(1.0, 0), "shift down")
	t.ok(BigMoney.zero().shift(5).is_zero(), "shift of zero")

	t.near(BigMoney.of(1.0, 10).ratio_to(BigMoney.of(5.0, 4)), 200000.0, 1e-6, "ratio_to")
	t.near(BigMoney.of(5.0, 4).ratio_to(BigMoney.of(1.0, 10)), 5e-6, 1e-12, "ratio_to below one")
	t.near(BigMoney.of(1.0, 3).ratio_to(BigMoney.of(1.0, 3)), 1.0, 1e-12, "ratio_to self")
	t.eq(BigMoney.of(1.0, 3).ratio_to(BigMoney.zero()), 0.0, "ratio_to zero is zero, not INF")
	t.eq(BigMoney.zero().ratio_to(BigMoney.of(1.0, 3)), 0.0, "ratio_to from zero")
	t.eq(BigMoney.of(1.0, 3).ratio_to(null), 0.0, "ratio_to null")
	t.ok(is_inf(BigMoney.of(1.0, 400).ratio_to(BigMoney.of(1.0, 0))), "ratio_to overflows to INF")
	t.eq(BigMoney.of(1.0, 0).ratio_to(BigMoney.of(1.0, 400)), 0.0, "ratio_to underflows to zero")

	t.near(BigMoney.of(4.82, 2).approx_float(), 482.0, 1e-9, "approx_float")
	t.eq(BigMoney.zero().approx_float(), 0.0, "approx_float zero")
	t.ok(is_inf(BigMoney.of(1.0, 400).approx_float()), "approx_float may be INF")
	t.eq(BigMoney.of(1.0, -400).approx_float(), 0.0, "approx_float underflows to zero")


func _test_cmp(t: TestCtx) -> void:
	t.eq(BigMoney.of(1.0, 5).cmp(BigMoney.of(1.0, 4)), 1, "bigger exponent wins")
	t.eq(BigMoney.of(1.0, 4).cmp(BigMoney.of(1.0, 5)), -1, "smaller exponent loses")
	t.eq(BigMoney.of(2.0, 5).cmp(BigMoney.of(1.0, 5)), 1, "same exponent, bigger mantissa")
	t.eq(BigMoney.of(1.0, 5).cmp(BigMoney.of(1.0, 5)), 0, "equal")
	t.eq(BigMoney.zero().cmp(BigMoney.zero()), 0, "zero equals zero")
	t.eq(BigMoney.zero().cmp(BigMoney.of(1.0, -30)), -1, "zero is less than any positive")
	t.eq(BigMoney.zero().cmp(BigMoney.of(-1.0, -30)), 1, "zero is greater than any negative")
	t.eq(BigMoney.of(-5.0, 0).cmp(BigMoney.of(3.0, 0)), -1, "negative < positive")
	# Negatives invert the exponent ordering: -1e5 is SMALLER than -1e4.
	t.eq(BigMoney.of(-1.0, 5).cmp(BigMoney.of(-1.0, 4)), -1, "bigger negative exponent is smaller")
	t.eq(BigMoney.of(-5.0, 0).cmp(BigMoney.of(-3.0, 0)), -1, "-5 < -3")
	t.eq(BigMoney.of(-3.0, 0).cmp(BigMoney.of(-5.0, 0)), 1, "-3 > -5")
	t.eq(BigMoney.of(1.0, 5).cmp(null), 1, "cmp against null treats it as zero")

	t.ok(BigMoney.of(1.0, 5).equals(BigMoney.of(1.0, 5)), "equals")
	t.ok(not BigMoney.of(1.0, 5).equals(BigMoney.of(1.0, 6)), "not equals")
	t.ok(BigMoney.of(1.0, 3).equals_approx(BigMoney.of(9.999999999999, 2)), "equals_approx across a decade")
	t.ok(not BigMoney.of(1.0, 3).equals_approx(BigMoney.of(9.9, 2)), "equals_approx rejects a real gap")
	t.ok(not BigMoney.of(1.0, 3).equals_approx(null), "equals_approx(null) is false")


func _test_min_max(t: TestCtx) -> void:
	var a := BigMoney.of(1.0, 3)
	var b := BigMoney.of(5.0, 2)
	_same(t, BigMoney.min_of(a, b), b, "min_of")
	_same(t, BigMoney.max_of(a, b), a, "max_of")
	_same(t, BigMoney.min_of(a, null), a, "min_of with null")
	_same(t, BigMoney.max_of(null, b), b, "max_of with null")
	_same(t, BigMoney.min_of(BigMoney.of(-1.0, 3), b), BigMoney.of(-1.0, 3), "min_of with a negative")


func _test_immutability(t: TestCtx) -> void:
	var a := BigMoney.of(5.0, 3)
	var b := BigMoney.of(2.0, 3)
	var results: Array = [
		a.add(b), a.sub_clamped(b), a.sub_exact(b), a.mul(3.0), a.mul_big(b),
		a.div(2.0), a.div_big(b), a.neg(), a.abs_of(), a.shift(2), a.copy(),
	]
	t.eq(results.size(), 11, "every op returned something")
	_money(t, a, 5.0, 3, "operand a is untouched")
	_money(t, b, 2.0, 3, "operand b is untouched")
	for r: BigMoney in results:
		t.ok(r != a and r != b, "ops return new instances, never an operand")
	var c := a.copy()
	t.ok(c != a and c.equals(a), "copy() is a distinct but equal instance")


func _test_serialization(t: TestCtx) -> void:
	for v: BigMoney in [
		BigMoney.zero(),
		BigMoney.of(1.2345, 7),
		BigMoney.of(-4.2, 3),
		BigMoney.of(9.999999, 300),
		BigMoney.of(1.0, -12),
	]:
		var d := v.to_dict()
		var back := BigMoney.from_dict(d)
		t.ok(back.equals(v), "dict round-trip of %s" % v.text())
		t.eq(back.m, v.m, "round-trip mantissa is bit-exact")
		t.eq(back.e, v.e, "round-trip exponent is bit-exact")
	var shape := BigMoney.of(1.5, 3).to_dict()
	t.eq(shape.get("m"), 1.5, "to_dict carries the mantissa under 'm'")
	t.eq(shape.get("e"), 3, "to_dict carries the exponent under 'e'")
	t.ok(BigMoney.from_dict({}).is_zero(), "from_dict of an empty dict is zero")
	t.ok(BigMoney.from_dict({"m": 1.0}).is_zero(), "from_dict without e is zero")
	t.ok(BigMoney.from_dict({"m": "x", "e": 3}).is_zero(), "from_dict with junk types is zero")
	# Ints in JSON-loaded dicts are common; they must not be rejected.
	_money(t, BigMoney.from_dict({"m": 2, "e": 3}), 2.0, 3, "from_dict accepts an int mantissa")


func _test_huge_scale(t: TestCtx) -> void:
	# Repeated growth at incremental-game scale must not overflow or go NaN.
	var v := BigMoney.of(1.0, 2)
	for i in 200:
		v = v.mul(1.15)
	t.ok(not is_nan(v.m) and is_finite(v.m), "200 growth steps stay finite")
	t.ok(v.e > 13 and v.e < 15, "200 steps of 1.15 land near 1e14 (got e=%s)" % v.e)

	# Squaring up to absurd magnitudes: exponent arithmetic, never float range.
	var huge := BigMoney.of(2.0, 300)
	for i in 10:
		huge = huge.mul_big(huge)
	t.ok(is_finite(huge.m) and huge.m >= 1.0 and huge.m < 10.0, "repeated squaring stays normalized")
	t.ok(huge.e > 300000, "repeated squaring reaches e>300000 (got e=%s)" % huge.e)
	t.eq(huge.text().substr(0, 1), "$", "absurd values still format")
