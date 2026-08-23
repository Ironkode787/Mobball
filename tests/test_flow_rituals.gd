extends RefCounted
## THE SMALL EVENTS (docs/05 §10, odds docs/03 §3): the mystery briefcase and the phone.
## Both are pure logic on a fed clock with a seeded RNG, so the odds can be counted rather
## than hoped at.

const SAVE_PATH := "user://test_flow_rituals.json"


func run(t: TestCtx) -> void:
	_odds(t)
	_never_twice(t)
	_boons(t)
	_phone_clock(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_briefcase_money(t)
	_phone_offers(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the briefcase ------------------------------------------------------------


func _odds(t: TestCtx) -> void:
	t.eq(int(Briefcases.ODDS[Briefcases.WAD]), 70, "70% a wad of dirty (docs/03 §3)")
	t.eq(int(Briefcases.ODDS[Briefcases.BOON]), 20, "20% a boon")
	t.eq(int(Briefcases.ODDS[Briefcases.SETUP]), 10, "10% a setup")
	t.eq(int(Briefcases.ODDS_FENCED[Briefcases.SETUP]), 5,
			"and the Pawn halves the trouble, which is what a fence is for")
	var total := 0
	for k: Variant in Briefcases.ODDS:
		total += int(Briefcases.ODDS[k])
	t.eq(total, 100, "the odds are odds")

	# Counted over a long run: within a few points of the design's weights.
	var cases := Briefcases.new()
	cases.begin_night(1, 1)
	var seen := {Briefcases.WAD: 0, Briefcases.BOON: 0, Briefcases.SETUP: 0}
	for i in 3000:
		var kind := StringName(cases.open(false)["kind"])
		seen[kind] = int(seen[kind]) + 1
	var wad_pct := 100.0 * float(seen[Briefcases.WAD]) / 3000.0
	t.ok(absf(wad_pct - 70.0) < 6.0, "wads landed at %.1f%%, not ~70%%" % wad_pct)
	t.ok(int(seen[Briefcases.SETUP]) > 0, "a setup never fired in 3000 cases")
	var setup_pct := 100.0 * float(seen[Briefcases.SETUP]) / 3000.0
	t.ok(setup_pct < 11.0, "setups landed at %.1f%%, over the 10%% line" % setup_pct)


func _never_twice(t: TestCtx) -> void:
	# "Setup can't fire twice in a row" (docs/03 §3): being stung is a story, being stung
	# twice running is the game cheating.
	var cases := Briefcases.new()
	cases.begin_night(7, 3)
	var last := &""
	for i in 2000:
		var kind := StringName(cases.open(false)["kind"])
		if last == Briefcases.SETUP:
			t.ok(kind != Briefcases.SETUP, "a setup followed a setup")
		last = kind


func _boons(t: TestCtx) -> void:
	var cases := Briefcases.new()
	cases.begin_night(11, 1)
	t.near(cases.dirty_multiplier(), 1.0, 1e-9, "no boon, no multiplier")

	# Walk cases until a doubling boon comes up, then check it is on a clock.
	var found := false
	for i in 500:
		var r := cases.open(false)
		if StringName(r.get("boon", "")) == Briefcases.BOON_DOUBLE:
			found = true
			break
	t.ok(found, "500 cases produced no doubling boon")
	if found:
		t.near(cases.dirty_multiplier(), Briefcases.BOON_DOUBLE_MULT, 1e-9,
				"the boon does not double dirty")
		cases.tick(Briefcases.BOON_DOUBLE_SECONDS + 0.1)
		t.near(cases.dirty_multiplier(), 1.0, 1e-9, "a temporary boon is temporary")

	# The wad scales with the empire, and is floored for a career that has none.
	t.ok(Briefcases.wad_value(BigMoney.zero()).is_positive(), "an empty career still gets a wad")
	var rate := BigMoney.from_float(500.0)
	t.ok(Briefcases.wad_value(rate).equals_approx(
			rate.mul(Briefcases.WAD_MINUTES * 60.0), 1e-9), "and an empire prices its own")

	# The bagman leaving costs nothing but the case (P5).
	var before := cases.night_opened
	cases.on_expired()
	t.eq(cases.night_missed, 1, "a missed case is recorded")
	t.eq(cases.night_opened, before, "and not counted as opened")


func _phone_clock(t: TestCtx) -> void:
	var line := ThePhone.new()
	line.begin_night(3, 1)
	t.ok(not line.ringing, "the phone starts quiet")
	t.ok(not line.tick(ThePhone.PERIOD - 1.0), "and stays quiet")
	t.ok(line.tick(1.0), "then it rings")
	t.ok(line.ringing, "and keeps ringing")
	t.ok(CALLERS_HAS(line.caller), "with somebody actually on the line")

	t.eq(String(line.answer()), String(line.caller), "picking up says who it was")
	t.ok(not line.ringing, "and the ringing stops")
	t.eq(line.night_answered, 1, "one answered")
	t.eq(String(line.answer()), "", "answering a dead line is nothing")

	# Ringing out is free — the call is simply gone.
	line.tick(ThePhone.PERIOD)
	t.ok(line.ringing, "it rings again later")
	line.tick(ThePhone.RING_SECONDS + 0.1)
	t.ok(not line.ringing, "and rings out if nobody picks up")
	t.eq(line.night_missed, 1, "which is recorded")


static func CALLERS_HAS(who: StringName) -> bool:
	return ThePhone.CALLERS.has(who)


# --- against the real session -------------------------------------------------


func _briefcase_money(t: TestCtx) -> void:
	Game.new_game(41)
	Game.start_night()
	var opened := 0
	var wads := 0
	var setups := 0
	for i in 40:
		var heat_before := Game.heat.value
		var dirty_before := Game.wallet.dirty
		var r := Game.open_briefcase()
		opened += 1
		match StringName(r["kind"]):
			Briefcases.WAD:
				wads += 1
				t.ok((r["paid"] as BigMoney).is_positive(), "a wad paid nothing")
				t.ok(Game.wallet.dirty.cmp(dirty_before) > 0, "and none of it reached the pile")
			Briefcases.SETUP:
				setups += 1
				t.ok(Game.heat.value >= heat_before + Briefcases.SETUP_HEAT - 1e-6,
						"a setup did not cost Heat")
	t.ok(wads > 0 and setups > 0, "forty cases produced only one kind of case")
	t.eq(Game.briefcases.night_opened, opened, "the book counted every case")
	t.ok(Game.briefcases.night_paid.is_positive(), "and the wads are on tonight's line")
	t.ok(Game.night_group_dirty(&"briefcase").is_positive(),
			"booked in their own group, not somebody else's")


func _phone_offers(t: TestCtx) -> void:
	Game.new_game(42)
	Game.start_night()

	# The tip takes the wagon off your back.
	Game.heat.value = 60.0
	Game.phone.ringing = true
	Game.phone.caller = ThePhone.TIP
	var heat_before := Game.heat.value
	var tip := Game.answer_phone()
	t.eq(String(tip["caller"]), String(ThePhone.TIP), "the tip is the tip")
	t.near(Game.heat.value, heat_before - ThePhone.TIP_HEAT, 1e-6, "and it cools the meter")

	# The bet is the house buying one.
	Game.phone.ringing = true
	Game.phone.caller = ThePhone.BET
	var comps := Game.casino.comps_left
	Game.answer_phone()
	t.eq(Game.casino.comps_left, comps + 1, "the bet did not comp a stake")

	# The job pays ☆.
	Game.phone.ringing = true
	Game.phone.caller = ThePhone.JOB
	var stars := Game.respect
	Game.answer_phone()
	t.eq(Game.respect, stars + ThePhone.JOB_RESPECT, "the job paid no ☆")

	# Nonna is proud of you — and notices when you do not pick up.
	Game.phone.ringing = true
	Game.phone.caller = ThePhone.NONNA
	stars = Game.respect
	Game.answer_phone()
	t.eq(Game.respect, stars + ThePhone.NONNA_RESPECT, "she is proud of you")

	Game.phone.ringing = false
	Game.phone.caller = ThePhone.NONNA
	stars = Game.respect
	Game.phone_rang_out()
	t.eq(Game.respect, stars - ThePhone.NONNA_MISS_RESPECT,
			"and letting your grandmother ring out costs exactly one ☆")

	Game.phone.caller = ThePhone.TIP
	stars = Game.respect
	Game.phone_rang_out()
	t.eq(Game.respect, stars, "everybody else hangs up for free")


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(43)
	Game.start_night()
	Game.open_briefcase()
	Game.briefcases.on_expired()
	Game.phone.ringing = true
	Game.phone.caller = ThePhone.JOB
	Game.answer_phone()
	var opened := Game.briefcases.opened_total
	var answered := Game.phone.answered_total
	t.ok(Game.save_now(), "the career writes")

	Game.new_game(0)
	Game.from_dict(Game.save.read())
	t.eq(Game.briefcases.opened_total, opened, "cases opened survive the save")
	t.eq(Game.briefcases.missed_total, 1, "so do the ones that walked away")
	t.eq(Game.phone.answered_total, answered, "and the calls you took")
	t.ok(not Game.phone.ringing, "nothing is ringing on a fresh load")
