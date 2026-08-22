extends RefCounted
## Wallet: the dirty/clean split, laundering caps, spend failures that must not
## mutate, confiscation math, and the signal contract.


func run(t: TestCtx) -> void:
	_test_construction(t)
	_test_earning(t)
	_test_signals(t)
	_test_launder_fraction(t)
	_test_launder_cap(t)
	_test_spending(t)
	_test_spend_failure_is_inert(t)
	_test_confiscation(t)
	_test_property_guards(t)
	_test_serialization(t)


# --- helpers ------------------------------------------------------------------


func _same(t: TestCtx, got: BigMoney, want: BigMoney, msg: String) -> void:
	if got == null:
		t.fail("%s — got null" % msg)
		return
	t.ok(got.equals_approx(want), "%s — got %s, want %s" % [msg, got.text(), want.text()])


func _wallet(dirty: BigMoney = null, clean: BigMoney = null) -> Wallet:
	return Wallet.new(dirty, clean)


# --- tests --------------------------------------------------------------------


func _test_construction(t: TestCtx) -> void:
	var w := Wallet.new()
	t.ok(w.dirty.is_zero(), "fresh wallet has no dirty")
	t.ok(w.clean.is_zero(), "fresh wallet has no clean")

	var seeded := _wallet(BigMoney.of(1.0, 3), BigMoney.of(5.0, 2))
	_same(t, seeded.dirty, BigMoney.of(1.0, 3), "seeded dirty")
	_same(t, seeded.clean, BigMoney.of(5.0, 2), "seeded clean")

	# A wallet can never start (or become) negative.
	var negative := _wallet(BigMoney.of(-1.0, 3), BigMoney.of(-5.0, 2))
	t.ok(negative.dirty.is_zero(), "negative starting dirty clamps to zero")
	t.ok(negative.clean.is_zero(), "negative starting clean clamps to zero")


func _test_earning(t: TestCtx) -> void:
	var w := _wallet()
	w.earn_dirty(BigMoney.of(1.0, 2))
	w.earn_dirty(BigMoney.of(5.0, 1))
	_same(t, w.dirty, BigMoney.of(1.5, 2), "earnings accumulate")
	t.ok(w.clean.is_zero(), "earning dirty never touches clean")

	w.earn_dirty(null)
	w.earn_dirty(BigMoney.zero())
	w.earn_dirty(BigMoney.of(-9.0, 9))
	_same(t, w.dirty, BigMoney.of(1.5, 2), "null / zero / negative earnings are ignored")

	w.earn_clean(BigMoney.of(2.0, 2))
	_same(t, w.clean, BigMoney.of(2.0, 2), "heists and bonds pay clean directly")
	_same(t, w.dirty, BigMoney.of(1.5, 2), "earning clean never touches dirty")

	# Dust below the precision rule is a documented no-op, not a rounding lie.
	var whale := _wallet(BigMoney.of(1.0, 30))
	whale.earn_dirty(BigMoney.of(1.0, 10))
	_same(t, whale.dirty, BigMoney.of(1.0, 30), "a $10B tip does not move a $1No pile")


func _test_signals(t: TestCtx) -> void:
	var w := _wallet()
	var dirty_events: Array = []
	var clean_events: Array = []
	var wash_events: Array = []
	w.dirty_changed.connect(func(v: BigMoney) -> void: dirty_events.append(v))
	w.clean_changed.connect(func(v: BigMoney) -> void: clean_events.append(v))
	w.laundered.connect(func(v: BigMoney) -> void: wash_events.append(v))

	w.earn_dirty(BigMoney.of(1.0, 3))
	t.eq(dirty_events.size(), 1, "earning dirty emits once")
	t.eq(clean_events.size(), 0, "earning dirty does not emit clean_changed")
	_same(t, dirty_events[0], BigMoney.of(1.0, 3), "signal carries the new balance")

	w.earn_dirty(BigMoney.zero())
	t.eq(dirty_events.size(), 1, "a no-op earn emits nothing")

	w.launder_fraction(0.5, null)
	t.eq(dirty_events.size(), 2, "laundering emits dirty_changed")
	t.eq(clean_events.size(), 1, "laundering emits clean_changed")
	t.eq(wash_events.size(), 1, "laundering emits laundered")
	_same(t, wash_events[0], BigMoney.of(5.0, 2), "laundered carries the amount moved")

	w.launder_fraction(0.0, null)
	t.eq(wash_events.size(), 1, "a zero-fraction wash emits nothing")


func _test_launder_fraction(t: TestCtx) -> void:
	var w := _wallet(BigMoney.of(1.0, 3))
	var moved := w.launder_fraction(Rates.LAUNDER_LOOP_FRACTION, null)
	_same(t, moved, BigMoney.of(8.0, 1), "the v1 loop washes 8% of held dirty")
	_same(t, w.dirty, BigMoney.of(9.2, 2), "dirty drops by exactly what moved")
	_same(t, w.clean, BigMoney.of(8.0, 1), "clean rises by exactly what moved")

	# Fraction clamping.
	var over := _wallet(BigMoney.of(1.0, 3))
	_same(t, over.launder_fraction(5.0, null), BigMoney.of(1.0, 3), "fraction > 1 clamps to everything")
	t.ok(over.dirty.is_zero(), "washing everything empties dirty")
	_same(t, over.clean, BigMoney.of(1.0, 3), "washing everything moves the whole pile")

	var under := _wallet(BigMoney.of(1.0, 3))
	t.ok(under.launder_fraction(-0.5, null).is_zero(), "a negative fraction washes nothing")
	_same(t, under.dirty, BigMoney.of(1.0, 3), "a negative fraction leaves dirty alone")
	t.ok(under.launder_fraction(NAN, null).is_zero(), "a NaN fraction washes nothing")
	t.ok(under.launder_fraction(INF, null).is_zero(), "an INF fraction washes nothing")
	_same(t, under.dirty, BigMoney.of(1.0, 3), "and neither touches the pile")
	t.ok(under.confiscate_dirty(INF).is_zero(), "an INF confiscation fraction takes nothing")
	t.ok(under.launder_fraction(0.0, null).is_zero(), "a zero fraction washes nothing")

	var empty := _wallet()
	t.ok(empty.launder_fraction(1.0, null).is_zero(), "washing an empty wallet yields zero")
	t.ok(empty.clean.is_zero(), "washing an empty wallet adds no clean")


func _test_launder_cap(t: TestCtx) -> void:
	# Cap binds: 8% of $10k is $800, cap is $200 (the v0 Pocket Money cap).
	var capped := _wallet(BigMoney.of(1.0, 4))
	var moved := capped.launder_fraction(0.08, Rates.pocket_money_per_night())
	_same(t, moved, BigMoney.of(2.0, 2), "the cap wins when the fraction is bigger")
	_same(t, capped.dirty, BigMoney.of(9.8, 3), "only the capped amount leaves dirty")
	_same(t, capped.clean, BigMoney.of(2.0, 2), "only the capped amount lands clean")

	# Fraction binds: 8% of $1k is $80, well under the $200 cap.
	var loose := _wallet(BigMoney.of(1.0, 3))
	_same(t, loose.launder_fraction(0.08, BigMoney.of(2.0, 2)), BigMoney.of(8.0, 1),
		"the fraction wins when the cap is bigger")

	# A zero cap is a real cap of zero — "tonight's allowance is used up".
	var zero_capped := _wallet(BigMoney.of(1.0, 4))
	t.ok(zero_capped.launder_fraction(1.0, BigMoney.zero()).is_zero(), "a zero cap washes nothing")
	_same(t, zero_capped.dirty, BigMoney.of(1.0, 4), "a zero cap leaves the pile alone")
	t.ok(zero_capped.clean.is_zero(), "a zero cap adds no clean")

	# A negative cap is nonsense; treat it as zero rather than as a credit.
	t.ok(zero_capped.launder_fraction(1.0, BigMoney.of(-5.0, 2)).is_zero(), "a negative cap washes nothing")

	# The cap can also exceed the whole balance.
	var small := _wallet(BigMoney.of(5.0, 1))
	_same(t, small.launder_fraction(1.0, BigMoney.of(1.0, 9)), BigMoney.of(5.0, 1),
		"an unreachable cap never invents money")
	t.ok(small.dirty.is_zero(), "and the balance still lands at exactly zero")


func _test_spending(t: TestCtx) -> void:
	var w := _wallet(BigMoney.of(1.0, 3), BigMoney.of(5.0, 2))
	t.ok(w.can_afford_clean(BigMoney.of(5.0, 2)), "can afford exactly the balance")
	t.ok(not w.can_afford_clean(BigMoney.of(5.1, 2)), "cannot afford a hair more")
	t.ok(w.can_afford_dirty(BigMoney.of(1.0, 3)), "can afford exactly the dirty balance")

	t.ok(w.spend_clean(BigMoney.of(2.0, 2)), "spend_clean succeeds")
	_same(t, w.clean, BigMoney.of(3.0, 2), "clean drops by the price")
	_same(t, w.dirty, BigMoney.of(1.0, 3), "spending clean never touches dirty")

	t.ok(w.spend_dirty(BigMoney.of(1.0, 3)), "spend_dirty can empty the pile exactly")
	t.ok(w.dirty.is_zero(), "spending the exact balance lands on zero")

	t.ok(w.spend_clean(BigMoney.zero()), "spending nothing succeeds")
	t.ok(w.spend_clean(null), "spending null succeeds")
	_same(t, w.clean, BigMoney.of(3.0, 2), "spending nothing costs nothing")


func _test_spend_failure_is_inert(t: TestCtx) -> void:
	var w := _wallet(BigMoney.of(1.0, 3), BigMoney.of(5.0, 2))
	var dirty_events: Array = []
	var clean_events: Array = []
	w.dirty_changed.connect(func(v: BigMoney) -> void: dirty_events.append(v))
	w.clean_changed.connect(func(v: BigMoney) -> void: clean_events.append(v))

	t.ok(not w.spend_clean(BigMoney.of(5.1, 2)), "spend_clean fails when short")
	_same(t, w.clean, BigMoney.of(5.0, 2), "a failed clean purchase does not mutate")
	t.ok(not w.spend_dirty(BigMoney.of(1.1, 3)), "spend_dirty fails when short")
	_same(t, w.dirty, BigMoney.of(1.0, 3), "a failed dirty purchase does not mutate")
	t.eq(dirty_events.size(), 0, "a failed purchase emits nothing (dirty)")
	t.eq(clean_events.size(), 0, "a failed purchase emits nothing (clean)")

	# Failure at absurd scale too — no exponent tricks let a purchase slip through.
	t.ok(not w.spend_clean(BigMoney.of(1.0, 300)), "cannot buy a $1e300 upgrade on $500")
	_same(t, w.clean, BigMoney.of(5.0, 2), "and the wallet is still untouched")


func _test_confiscation(t: TestCtx) -> void:
	var w := _wallet(BigMoney.of(1.0, 4), BigMoney.of(2.0, 3))
	var taken := w.confiscate_dirty(Rates.RAID_CONFISCATE_FRACTION)
	_same(t, taken, BigMoney.of(3.0, 3), "a busted raid takes 30% of held dirty")
	_same(t, w.dirty, BigMoney.of(7.0, 3), "70% survives")
	_same(t, w.clean, BigMoney.of(2.0, 3), "clean cash is never confiscated")

	t.ok(w.confiscate_dirty(0.0).is_zero(), "a zero fraction takes nothing")
	t.ok(w.confiscate_dirty(-1.0).is_zero(), "a negative fraction takes nothing")
	_same(t, w.dirty, BigMoney.of(7.0, 3), "and leaves the pile alone")

	var wiped := _wallet(BigMoney.of(4.0, 5))
	_same(t, wiped.confiscate_dirty(2.0), BigMoney.of(4.0, 5), "fraction > 1 clamps to everything")
	t.ok(wiped.dirty.is_zero(), "confiscating everything empties the pile")

	var empty := _wallet()
	t.ok(empty.confiscate_dirty(0.3).is_zero(), "confiscating from an empty wallet yields zero")

	var reset_me := _wallet(BigMoney.of(1.0, 5), BigMoney.of(1.0, 5))
	reset_me.reset()
	t.ok(reset_me.dirty.is_zero() and reset_me.clean.is_zero(), "reset() clears both currencies")


func _test_property_guards(t: TestCtx) -> void:
	var w := _wallet()
	var dirty_events: Array = []
	w.dirty_changed.connect(func(v: BigMoney) -> void: dirty_events.append(v))

	w.dirty = BigMoney.of(1.0, 3)
	_same(t, w.dirty, BigMoney.of(1.0, 3), "assigning dirty works")
	t.eq(dirty_events.size(), 1, "assigning dirty emits")

	w.dirty = BigMoney.of(1.0, 3)
	t.eq(dirty_events.size(), 1, "assigning the same value emits nothing")

	w.dirty = BigMoney.of(-1.0, 3)
	t.ok(w.dirty.is_zero(), "assigning a negative clamps to zero")
	w.clean = null
	t.ok(w.clean.is_zero(), "assigning null clamps to zero")


func _test_serialization(t: TestCtx) -> void:
	var w := _wallet(BigMoney.of(1.234, 7), BigMoney.of(9.5, 11))
	var d := w.to_dict()
	var back := Wallet.new()
	back.from_dict(d)
	_same(t, back.dirty, w.dirty, "wallet dict round-trip (dirty)")
	_same(t, back.clean, w.clean, "wallet dict round-trip (clean)")

	var junk := Wallet.new()
	junk.from_dict({})
	t.ok(junk.dirty.is_zero() and junk.clean.is_zero(), "loading an empty save is empty, not broken")
	junk.from_dict({"dirty": "nope", "clean": 42})
	t.ok(junk.dirty.is_zero() and junk.clean.is_zero(), "loading corrupt fields is empty, not broken")
