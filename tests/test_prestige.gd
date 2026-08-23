extends RefCounted
## Prestige: the Juice formula (docs/06 §2), the wallet that never resets, and the fold of
## the Black Book onto the promises a new city starts with.
##
## Two fixtures, same reason as tests/test_stats.gd. A synthetic Book exercises every perk
## kind and every fold at levels the shipped file does not reach (and with the ★ perks made
## live, since a deferred perk can never be bought); the shipped Book then proves the same
## folding survives real data. The shipped file's own shape is guarded next door, in
## tests/test_blackbook_data.gd.


func run(t: TestCtx) -> void:
	var fixture := _fixture()
	t.eq(fixture.errors.size(), 0, "the fixture Book itself is valid: %s" % ", ".join(fixture.errors))
	_test_juice_vectors(t)
	_test_juice_terms(t)
	_test_juice_pacing_targets(t)
	_test_juice_garbage_in(t)
	_test_wallet(t)
	_test_buying(t)
	_test_folds(t, fixture)
	_test_caps(t, fixture)
	_test_deferred_getters(t, fixture)
	_test_stats_effects(t, fixture)
	_test_serialization(t, fixture)
	_test_shipped_book(t)


# --- fixture ------------------------------------------------------------------


func _perk(id: String, cost: int, effects: Array, repeat: Variant = null,
		deferred: bool = false, requires: Array = []) -> Dictionary:
	return {
		"id": id, "name": id, "flavor": "flavor", "note": "note",
		"cost": cost, "repeat": repeat, "requires": requires, "deferred": deferred,
		"effects": effects,
	}


## Every perk kind, all live, so the folds can be driven past the shipped numbers.
func _fixture() -> BlackBook:
	return BlackBook.from_variant({
		"schema": 1,
		"perks": [
			_perk("blackbook.contacts", 1, [
				{"kind": "start_rank", "value": 1, "per_level": true},
			], {"max": 5, "step": 1}),
			_perk("blackbook.kept", 1, [
				{"kind": "kept_specialist", "value": 1, "per_level": true},
			], {"max": 5, "step": 2}),
			_perk("blackbook.light", 2, [{"kind": "pocket_city_scale"}]),
			_perk("blackbook.rep", 2, [{"kind": "boss_start_phase", "value": 2}]),
			_perk("blackbook.rep_more", 2, [{"kind": "boss_start_phase", "value": 3}]),
			_perk("blackbook.stash", 3, [{"kind": "stash_fraction", "value": 0.05}]),
			_perk("blackbook.bench", 3, [{"kind": "bench_starters", "value": 2}]),
			_perk("blackbook.learner", 8, [{"kind": "star_requirement_mult", "value": 0.8}]),
			_perk("blackbook.learner_more", 8, [{"kind": "star_requirement_mult", "value": 0.8}]),
			_perk("blackbook.learner_most", 8, [{"kind": "star_requirement_mult", "value": 0.8}]),
			_perk("blackbook.learner_again", 8, [{"kind": "star_requirement_mult", "value": 0.8}]),
			# The ★ vocabulary, made buyable here on purpose: this is the only place the
			# deferred getters can be exercised before M4 turns them on in content.
			_perk("blackbook.double", 5, [{"kind": "idle_carryover", "value": 0.10}]),
			_perk("blackbook.sleep", 5, [
				{"kind": "saint_statue", "value": 1, "per_level": true},
			], {"max": 3, "step": 5}),
			_perk("blackbook.museum", 8, [{"kind": "museum"}]),
			_perk("blackbook.era", 10, [{"kind": "golden_ball_tier", "value": 5}]),
			_perk("blackbook.era_later", 10, [{"kind": "golden_ball_tier", "value": 6}]),
			_perk("blackbook.silent", 15, [
				{"kind": "safe_cap_mult", "value": 2.0},
				{"kind": "safe_clean_share", "value": 0.10},
			]),
			_perk("blackbook.gauntlet", 25, [{"kind": "gauntlet"}]),
			# A perk that speaks the LEDGER's vocabulary instead of the Book's.
			_perk("blackbook.union_dues", 4, [
				{"kind": "idle_rate_add", "target": "union", "value": "2K", "per_level": true},
				{"kind": "value_mult", "target": "all", "value": 1.1, "per_level": true},
			], {"max": 4, "step": 2}),
			# Deferred, and therefore never purchasable however much Juice is in the wallet.
			_perk("blackbook.someday", 3, [{"kind": "museum"}], null, true),
		],
	}, "test_prestige fixture")


func _prestige(book: BlackBook, owned: Dictionary = {}, juice: int = 0) -> Prestige:
	var p := Prestige.new(book)
	p.award(juice)
	p.set_owned(owned)
	return p


# --- the formula --------------------------------------------------------------


## docs/06 §2 is `floor(sqrt(lifetime_clean / 1e9))`, and the whole reason it goes through
## BigMoney is that a late career's clean is a number a float cannot hold.
func _test_juice_vectors(t: TestCtx) -> void:
	var cases := {
		"0": 0,
		"1": 0,
		"999M": 0,
		"1B": 1,
		"3.9B": 1,
		"4B": 2,
		"9B": 3,
		"25B": 5,
		"99B": 9,
		"100B": 10,
		# An odd exponent has to borrow an order off the mantissa before the root is taken.
		"2.5e10": 5,
		"1T": 31,
		"1e15": 1000,
		"1e21": 1000000,
	}
	for text: String in cases:
		t.eq(Prestige.juice_from_clean(BigMoney.parse(text)), int(cases[text]),
			"sqrt(%s / 1e9) floors to %d" % [text, int(cases[text])])

	# Huge exponents: the answer saturates instead of overflowing an int or printing INF.
	for wild: String in ["1e40", "1e120", "1e300"]:
		t.eq(Prestige.juice_from_clean(BigMoney.parse(wild)), Prestige.JUICE_MAX,
			"%s of clean saturates at JUICE_MAX rather than overflowing" % wild)
	t.eq(Prestige.juice_from_clean(BigMoney.parse("-5B")), 0, "a negative balance is worth nothing")
	t.eq(Prestige.juice_from_clean(null), 0, "no clean at all is worth nothing")

	# The precision contract: one order either side of a perfect square still floors right.
	t.eq(Prestige.juice_from_clean(BigMoney.parse("15.99B")), 3, "3.99… floors to 3")
	t.eq(Prestige.juice_from_clean(BigMoney.parse("16B")), 4, "16B is exactly 4")


## Every term of the formula, moved one at a time.
func _test_juice_terms(t: TestCtx) -> void:
	var base := {
		"lifetime_clean": BigMoney.parse("64B"),
		"bosses_beaten": 2, "heists_cleared": 3, "raids_survived": 4,
		"excess_respect": 1250,
	}
	var b := Prestige.juice_breakdown(base)
	t.eq(int(b["clean"]), 8, "sqrt(64) is 8")
	t.eq(int(b["bosses"]), 2, "a boss is a point")
	t.eq(int(b["heists"]), 3, "a heist is a point")
	t.eq(int(b["raids"]), 4, "a survived raid is a point")
	t.eq(int(b["respect"]), 2, "1250 excess ☆ is two 500s, floored")
	t.eq(int(b["total"]), 19, "and the terms add up")
	t.eq(Prestige.juice_for(base), 19, "juice_for is the breakdown's total")

	# The flat adds are what pay for DOING things: the same wealth with nothing done is worth
	# only its root, which is the docs/06 §2 point of the whole shape.
	t.eq(Prestige.juice_for({"lifetime_clean": BigMoney.parse("64B")}), 8,
		"a farmed career scores the sqrt term alone")
	t.eq(Prestige.juice_for({"bosses_beaten": 6}), 6, "and a broke career still scores its wins")
	t.eq(Prestige.juice_for({}), 0, "an empty career is worth nothing")

	# ☆ under a threshold pays nothing, which is what `floor(excess/500)` means.
	t.eq(Prestige.juice_for({"excess_respect": 499}), 0, "499 ☆ is not 500")
	t.eq(Prestige.juice_for({"excess_respect": 500}), 1, "500 ☆ is")
	t.eq(Prestige.juice_for({"respect": 1000}), 2, "`respect` reads as the alias for excess ☆")

	# Doubling the money must NOT double the Juice — the whole reason there is a sqrt.
	var poor := Prestige.juice_for({"lifetime_clean": BigMoney.parse("100B")})
	var rich := Prestige.juice_for({"lifetime_clean": BigMoney.parse("200B")})
	t.ok(rich < poor * 2, "doubling wealth (%d -> %d) is not doubling Juice" % [poor, rich])
	t.ok(rich > poor, "…but it is still worth more")


## docs/06 §2 names two numbers: 8–15 for a first Skip Town, 25–60 for a completed city on a
## later loop. They are the pacing contract, so the formula is measured against them here.
func _test_juice_pacing_targets(t: TestCtx) -> void:
	# A plausible first career: R7 reached, $25B lifetime clean, both M2 bosses, a couple of
	# heists, a few raids ridden out, and change left on the ☆ ladder.
	var first := Prestige.juice_for({
		"lifetime_clean": BigMoney.parse("25B"),
		"bosses_beaten": 2, "heists_cleared": 1, "raids_survived": 2,
		"excess_respect": 600,
	})
	t.ok(first >= 8 and first <= 15,
		"a first Skip Town pays inside the docs/06 §2 band 8–15 (got %d)" % first)

	# A completed city on a later loop: the empire is an order up and everything got done.
	var later := Prestige.juice_for({
		"lifetime_clean": BigMoney.parse("400B"),
		"bosses_beaten": 5, "heists_cleared": 8, "raids_survived": 6,
		"excess_respect": 2500,
	})
	t.ok(later >= 25 and later <= 60,
		"a completed city pays inside the docs/06 §2 band 25–60 (got %d)" % later)


func _test_juice_garbage_in(t: TestCtx) -> void:
	# The career dictionary comes off a save file, so every field has to survive nonsense.
	t.eq(Prestige.juice_for({"lifetime_clean": "9B"}), 3, "clean as a content string parses")
	t.eq(Prestige.juice_for({"lifetime_clean": BigMoney.parse("9B").to_dict()}), 3,
		"clean as a saved {m, e} dict parses")
	t.eq(Prestige.juice_for({"lifetime_clean": 4e9}), 2, "clean as a bare float parses")
	t.eq(Prestige.juice_for({"lifetime_clean": "a lot", "bosses_beaten": "two"}), 0,
		"unparseable fields count as zero rather than failing")
	t.eq(Prestige.juice_for({"bosses_beaten": -5, "raids_survived": -1}), 0,
		"negative tallies do not subtract Juice")
	t.eq(Prestige.juice_for({"heists_cleared": 2.7}), 2, "a fractional tally floors")
	t.eq(Prestige.juice_for({"lifetime_clean": null, "bosses_beaten": null}), 0,
		"a career whose fields are null is zero, not a crash")


# --- the wallet ---------------------------------------------------------------


func _test_wallet(t: TestCtx) -> void:
	var p := Prestige.new(_fixture())
	t.eq(p.juice, 0, "a new player has no Juice")
	t.eq(p.juice_earned, 0, "…and has earned none")
	t.eq(p.city_number(), 1, "and is playing city 1")

	t.eq(p.award(7), 7, "award pays in")
	t.eq(p.juice, 7, "the wallet holds it")
	t.eq(p.juice_earned, 7, "and remembers it")
	t.eq(p.award(0), 0, "awarding nothing does nothing")
	t.eq(p.award(-9), 0, "Juice is never taken away")
	t.eq(p.juice, 7, "…so the wallet is untouched")

	var career := {"lifetime_clean": BigMoney.parse("25B"), "bosses_beaten": 2}
	var paid := p.skip_town(career)
	t.eq(paid, Prestige.juice_for(career), "skip_town pays exactly what the career scored")
	t.eq(p.juice, 7 + paid, "and banks it on top of what was there")
	t.eq(p.city_number(), 2, "the next city is city 2")
	p.skip_town({})
	t.eq(p.city_number(), 3, "a city left with nothing still counts as left")
	t.eq(p.juice, 7 + paid, "and pays nothing")


func _test_buying(t: TestCtx) -> void:
	var book := _fixture()
	var p := _prestige(book, {}, 6)

	t.eq(p.block_for("blackbook.contacts"), BlackBook.Block.NONE, "1 Juice is affordable at 6")
	t.eq(p.buy("blackbook.contacts"), 1, "buying returns the new level")
	t.eq(p.juice, 5, "and the price came out of the wallet")
	t.eq(p.juice_earned, 6, "spending does not lower what was earned")
	t.eq(p.level_of("blackbook.contacts"), 1, "the level is owned")
	t.eq(p.start_rank(), 1, "and the promise is live")

	# The ladder is `cost + step × level`, in whole Juice.
	t.eq(p.cost_of("blackbook.contacts"), 2, "level 2 of a 1/step-1 perk costs 2")
	t.eq(p.buy("blackbook.contacts"), 2, "and buys")
	t.eq(p.juice, 3, "…for 2")
	t.eq(book.total_cost("blackbook.contacts"), 1 + 2 + 3 + 4 + 5, "the whole ladder is 15")

	# What refuses, and the fact that a refusal never moves the wallet.
	var before := p.juice
	t.eq(p.buy("blackbook.gauntlet"), 0, "25 Juice is not 3 Juice")
	t.eq(p.block_for("blackbook.gauntlet"), BlackBook.Block.JUICE, "…and it says why")
	t.eq(p.buy("blackbook.someday"), 0, "a deferred perk cannot be bought at any price")
	t.eq(p.block_for("blackbook.someday"), BlackBook.Block.DEFERRED, "…and it says why")
	t.eq(p.buy("blackbook.nothing_here"), 0, "an unknown id buys nothing")
	t.eq(p.block_for("blackbook.nothing_here"), BlackBook.Block.UNKNOWN, "…and it says why")
	t.eq(p.juice, before, "no refused purchase moved a point of Juice")

	# Maxed: a ladder ends.
	var maxed := _prestige(book, {"blackbook.light": 1}, 50)
	t.eq(maxed.block_for("blackbook.light"), BlackBook.Block.MAXED, "a one-off is maxed once owned")
	t.eq(maxed.buy("blackbook.light"), 0, "and refuses a second sale")

	# `requires`: the Book supports it even though the shipped file is flat.
	var gated := BlackBook.from_variant({"schema": 1, "perks": [
		_perk("blackbook.first", 1, [{"kind": "museum"}]),
		_perk("blackbook.second", 1, [{"kind": "gauntlet"}], null, false, ["blackbook.first"]),
	]}, "gated fixture", true)
	var g := _prestige(gated, {}, 9)
	t.eq(g.block_for("blackbook.second"), BlackBook.Block.REQUIRES, "a gated perk names its parent")
	g.buy("blackbook.first")
	t.eq(g.block_for("blackbook.second"), BlackBook.Block.NONE, "…and opens when the parent is in")


# --- the folds ----------------------------------------------------------------


func _test_folds(t: TestCtx, fixture: BlackBook) -> void:
	# SUM, and per_level scaling on top of it.
	var summed := _prestige(fixture, {"blackbook.contacts": 2, "blackbook.bench": 1})
	t.eq(summed.start_rank(), 2, "two levels of a +1 perk is +2")
	t.eq(summed.bench_starters(), 2, "a flat perk contributes its number")

	# MAX: two perks promising a phase, the later one wins.
	var maxed := _prestige(fixture, {"blackbook.rep": 1, "blackbook.rep_more": 1})
	t.eq(maxed.boss_start_phase(), 3, "boss_start_phase takes the highest owned")
	t.eq(_prestige(fixture, {}).boss_start_phase(), 1, "…and 1 when nobody bought one")

	# MIN: the EARLIEST Golden Ball tier wins, which is the shape "unlock it sooner" needs.
	var earliest := _prestige(fixture, {"blackbook.era": 1, "blackbook.era_later": 1})
	t.eq(earliest.golden_ball_tier(), 5, "golden_ball_tier takes the earliest owned")
	t.eq(_prestige(fixture, {}).golden_ball_tier(), Prestige.GOLDEN_BALL_TIER,
		"…and T7 when nobody bought one")

	# PRODUCT: two −20%s compound to 0.64, they do not add to 0.6.
	var product := _prestige(fixture, {"blackbook.learner": 1, "blackbook.learner_more": 1})
	t.near(product.star_requirement_mult(), 0.64, 1e-9, "star_requirement_mult compounds")

	# UNION: a flag is on or off, and buying it twice is still on.
	var flagged := _prestige(fixture, {"blackbook.light": 1})
	t.eq(flagged.pocket_scales_with_city(), true, "a flag perk sets its flag")
	t.eq(_prestige(fixture, {}).pocket_scales_with_city(), false, "…and nothing else does")

	# The fold vocabulary itself has to be complete, or a level silently guesses.
	for kind: Variant in BlackBook.PERK_SPECS:
		t.ok(BlackBook.FOLD.has(kind), "perk kind `%s` names a fold bucket" % kind)
	for kind: Variant in BlackBook.FOLD:
		t.ok(BlackBook.PERK_SPECS.has(kind), "fold bucket `%s` is a kind the loader accepts" % kind)


## Nothing in the Book may promise something a system cannot honour. The caps are those
## limits, and no stack of levels may cross one.
func _test_caps(t: TestCtx, fixture: BlackBook) -> void:
	var greedy := _prestige(fixture, {
		"blackbook.contacts": 5, "blackbook.kept": 5, "blackbook.sleep": 3,
	})
	t.eq(greedy.start_rank(), Prestige.START_RANK_MAX, "Old Contacts cannot seat you past R3")
	t.eq(greedy.kept_specialists(), Prestige.KEPT_MEN_MAX, "Kept Man tops out")
	t.eq(greedy.saint_statues(), Prestige.SAINTS_MAX, "the saints top out")

	var learned := _prestige(fixture, {
		"blackbook.learner": 1, "blackbook.learner_more": 1, "blackbook.learner_most": 1,
	})
	t.near(learned.star_requirement_mult(), 0.512, 1e-9, "three −20%s compound to 0.512…")
	learned.set_owned({
		"blackbook.learner": 1, "blackbook.learner_more": 1, "blackbook.learner_most": 1,
		"blackbook.learner_again": 1,
	})
	t.near(learned.star_requirement_mult(), Prestige.STAR_REQUIREMENT_MIN, 1e-9,
		"…and a fourth would be 0.41; the ☆ ladder is never cut past half")

	var bare := _prestige(fixture, {})
	t.eq(bare.start_rank(), 0, "no Book, no head start")
	t.eq(bare.kept_specialists(), 0, "no Book, nobody comes with you")
	t.eq(bare.bench_starters(), 0, "no Book, an empty Bench")
	t.near(bare.stash_fraction(), 0.0, 1e-9, "no Book, no stash")
	t.near(bare.star_requirement_mult(), 1.0, 1e-9, "no Book, the full ☆ ladder")
	t.eq(bare.pocket_money_mult(), 1.0, "no Book, Pocket Money is Pocket Money")


func _test_deferred_getters(t: TestCtx, fixture: BlackBook) -> void:
	# Identity today, on a career that owns nothing: this is what makes it safe for the flow
	# lane to read them before M4 exists.
	var bare := _prestige(fixture, {})
	t.near(bare.idle_carryover(), 0.0, 1e-9, "no Double Life, no second income")
	t.eq(bare.saint_statues(), 0, "no statues")
	t.eq(bare.museum_unlocked(), false, "no Museum")
	t.eq(bare.golden_ball_tier(), 7, "the Golden Ball is where docs/04 left it")
	t.near(bare.safe_cap_mult(), 1.0, 1e-9, "the Safe is the Safe")
	t.near(bare.safe_clean_share(), 0.0, 1e-9, "and it fills with dirty")
	t.eq(bare.gauntlet_unlocked(), false, "no gauntlet")

	# …and each reports its promise the day it is switched on.
	var bought := _prestige(fixture, {
		"blackbook.double": 1, "blackbook.museum": 1, "blackbook.silent": 1,
		"blackbook.gauntlet": 1, "blackbook.era": 1, "blackbook.sleep": 2,
	})
	t.near(bought.idle_carryover(), 0.10, 1e-9, "Double Life keeps a tenth flowing")
	t.eq(bought.museum_unlocked(), true, "the Museum opens")
	t.near(bought.safe_cap_mult(), 2.0, 1e-9, "Silent Empire doubles the Safe")
	t.near(bought.safe_clean_share(), 0.10, 1e-9, "…and a tenth of it arrives clean")
	t.eq(bought.gauntlet_unlocked(), true, "the Sixth Family opens")
	t.eq(bought.golden_ball_tier(), 5, "the Golden Era moves the Golden Ball to T5")
	t.eq(bought.saint_statues(), 2, "two retired men are watching")


## A perk may also promise a LEDGER effect. It never folds into the perk buckets; it comes
## back out through `stats_effects()` for the lane that applies it, already at its level.
func _test_stats_effects(t: TestCtx, fixture: BlackBook) -> void:
	t.eq(_prestige(fixture, {}).stats_effects().size(), 0, "an unbought Book changes no Stats")
	var p := _prestige(fixture, {"blackbook.union_dues": 3, "blackbook.contacts": 1})
	var effects := p.stats_effects()
	t.eq(effects.size(), 2, "only the Ledger-vocabulary effects come out")
	var by_kind: Dictionary = {}
	for e in effects:
		by_kind[String(e["kind"])] = e
	t.ok(by_kind.has("idle_rate_add"), "the idle line survived the load")
	t.ok(by_kind.has("value_mult"), "so did the multiplier")
	if by_kind.has("idle_rate_add"):
		var idle: Dictionary = by_kind["idle_rate_add"]
		t.eq(bool(idle["per_level"]), false, "…already folded, so a consumer applies it once")
		t.ok((idle["money"] as BigMoney).equals_approx(BigMoney.parse("6K")),
			"three levels of $2K is $6K, not $2K")
	if by_kind.has("value_mult"):
		var mult: Dictionary = by_kind["value_mult"]
		t.near(float(mult["num"]), pow(1.1, 3.0), 1e-9, "and a multiplier compounded, not summed")
	t.eq(p.start_rank(), 1, "the perk-kind effect on another perk still folded normally")


# --- serialization ------------------------------------------------------------


func _test_serialization(t: TestCtx, fixture: BlackBook) -> void:
	var p := _prestige(fixture, {}, 20)
	p.buy("blackbook.contacts")
	p.buy("blackbook.stash")
	p.skip_town({"bosses_beaten": 3})
	var d := p.to_dict()

	var loaded := Prestige.new(fixture)
	loaded.from_dict(d)
	t.eq(loaded.juice, p.juice, "the wallet round-trips")
	t.eq(loaded.juice_earned, p.juice_earned, "so does what was earned")
	t.eq(loaded.cities_finished, p.cities_finished, "so do the cities")
	t.eq(loaded.owned(), p.owned(), "so does the Book")
	t.eq(loaded.start_rank(), p.start_rank(), "…and the promises come back with it")
	t.near(loaded.stash_fraction(), p.stash_fraction(), 1e-9, "all of them")

	# A save file is not to be trusted: every field is sanitized on the way in.
	var junk := Prestige.new(fixture)
	junk.from_dict({
		"juice": -50, "earned": 2, "cities": -3,
		"owned": {
			"blackbook.contacts": 99,        # past the ladder
			"blackbook.someday": 1,          # deferred: never buyable, so never owned
			"blackbook.ghost": 2,            # not in the Book at all
			"blackbook.stash": 0,            # not really owned
			7: 1,                            # not even a string
		},
	})
	t.eq(junk.juice, 0, "a negative wallet loads as empty")
	t.eq(junk.cities_finished, 0, "a negative city count loads as none")
	t.eq(junk.level_of("blackbook.contacts"), 5, "a level past the ladder clamps to it")
	t.eq(junk.start_rank(), Prestige.START_RANK_MAX, "…and still cannot cross the cap")
	t.eq(junk.has("blackbook.someday"), false, "a deferred perk cannot be owned")
	t.eq(junk.has("blackbook.ghost"), false, "an id the Book does not know is dropped")
	t.eq(junk.has("blackbook.stash"), false, "a level of zero owns nothing")
	t.eq(junk.owned().size(), 1, "and nothing else survived")

	t.eq(Prestige.new(fixture).to_dict()["owned"], {}, "a fresh Prestige serializes empty")
	var blank := Prestige.new(fixture)
	blank.from_dict({})
	t.eq(blank.juice, 0, "an absent save section is a new player, not an error")

	# The owned map handed out must be a copy — the save system sorts and keeps it.
	var copy := p.owned()
	copy["blackbook.gauntlet"] = 1
	t.eq(p.has("blackbook.gauntlet"), false, "owned() hands out a copy")


# --- the shipped Book ---------------------------------------------------------


func _test_shipped_book(t: TestCtx) -> void:
	var book := BlackBook.shared()
	t.ok(book.is_valid(), "the shipped Black Book loads: %s" % ", ".join(book.errors))
	if not book.is_valid():
		return
	var p := _prestige(book, {}, 30)

	# The docs/06 §3 perks that are LIVE must actually promise something through the getters.
	t.eq(p.buy("blackbook.old_contacts"), 1, "Old Contacts is buyable at 1 Juice")
	t.eq(p.start_rank(), 1, "…and starts the next city one rank up")
	t.eq(p.buy("blackbook.kept_man"), 1, "Kept Man is buyable")
	t.eq(p.kept_specialists(), 1, "…and carries one guy")
	t.eq(p.buy("blackbook.traveling_light"), 1, "Traveling Light is buyable")
	t.eq(p.pocket_scales_with_city(), true, "…and Pocket Money now knows what city it is in")
	t.eq(p.pocket_money_mult(), 1.0, "…which is still city 1 until somebody skips town")
	p.skip_town({})
	t.eq(p.pocket_money_mult(), 2.0, "…and city 2 doubles it")
	t.eq(p.buy("blackbook.the_stash"), 1, "The Stash is buyable")
	t.near(p.stash_fraction(), 0.05, 1e-9, "…at the docs/06 5%")
	t.eq(p.buy("blackbook.everybody_knows_somebody"), 1, "Everybody Knows Somebody is buyable")
	t.eq(p.bench_starters(), 2, "…and seats two")
	t.eq(p.buy("blackbook.reputation_precedes_you"), 1, "Reputation Precedes You is buyable")
	t.eq(p.boss_start_phase(), 2, "…and opens the first fight at phase 2")
	t.eq(p.buy("blackbook.fast_learner"), 1, "Fast Learner is buyable")
	t.near(p.star_requirement_mult(), 0.8, 1e-9, "…at the docs/06 −20%")

	# And every ★ perk refuses, at any wallet, until its system exists.
	var rich := _prestige(book, {}, 500)
	for id in ["blackbook.double_life", "blackbook.the_big_sleep", "blackbook.museum_of_crime",
			"blackbook.the_golden_era", "blackbook.silent_empire", "blackbook.the_sixth_family"]:
		t.eq(rich.block_for(id), BlackBook.Block.DEFERRED, "%s is deferred, not for sale" % id)
		t.eq(rich.buy(id), 0, "…and 500 Juice does not change that" % [])
	t.eq(rich.juice, 500, "…and none of those refusals cost anything")

	# The shared instance is the one the flow lane saves; it must survive being asked for twice.
	t.ok(Prestige.shared() == Prestige.shared(), "shared() is one object")
	Prestige.reset_shared()
