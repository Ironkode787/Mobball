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
	_the_rat(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_briefcase_money(t)
	_phone_offers(t)
	_rat_in_the_session(t)
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


# --- the rat ------------------------------------------------------------------


func _the_rat(t: TestCtx) -> void:
	var roster: Array = []
	for i in 5:
		roster.append({"id": i + 1, "name": "Guy %d" % i})

	var rat := TheRat.new()
	t.ok(not rat.begin_night(1, 0, roster, 1), "a nobody has nobody to inform on him")
	t.ok(not rat.armed, "the arc is shut")

	t.ok(not rat.begin_night(2, TheRat.ARC_RANK, roster, 1),
			"reaching R6 starts the arc, it does not open the backglass the same Night")
	t.ok(rat.armed, "but he is out there now")
	t.near(rat.skim_fraction(), TheRat.SKIM, 1e-9, "and he is taking his cut off the wash")

	t.ok(rat.begin_night(3, TheRat.ARC_RANK, roster, 1), "the next Night is a clue Night")
	t.ok(rat.active, "three names in the backglass")
	t.eq(rat.suspects.size(), TheRat.SUSPECTS, "three of them")
	var names := {}
	for i in rat.suspects.size():
		names[rat.suspect_name(i)] = true
	t.eq(names.size(), TheRat.SUSPECTS, "and they are three different men")
	t.ok(rat.culprit >= 0 and rat.culprit < TheRat.SUSPECTS, "one of them is talking")

	# Clues are ordinary play, once each, and each rules out an innocent name.
	t.ok(not rat.can_accuse(), "no clues, no accusation")
	t.ok(rat.accuse(0)["made"] == false, "and naming somebody early does nothing")
	t.ok(rat.note_clue(TheRat.CLUE_LAUNDROMAT), "the short total is a clue")
	t.ok(not rat.note_clue(TheRat.CLUE_LAUNDROMAT), "the same clue twice is one clue")
	t.ok(not rat.can_accuse(), "one clue is not enough")
	t.ok(rat.note_clue(TheRat.CLUE_COLLECTION), "the collection is the second")
	t.ok(rat.can_accuse(), "two clues and you may name him")
	t.eq(rat.cleared.size(), 2, "and two innocent men have been ruled out")
	t.ok(not rat.is_cleared(rat.culprit), "never the one who is actually talking")
	t.ok(not rat.note_clue(&"a_hunch"), "a clue that is not a clue is not a clue")

	# Wrong: the real rat makes a phone call and the backglass goes dark for three Nights.
	var innocent := (rat.culprit + 1) % TheRat.SUSPECTS
	var wrong := rat.accuse(innocent)
	t.ok(bool(wrong["made"]) and not bool(wrong["right"]), "that was the wrong man")
	t.ok(not rat.active, "the Night's accusation is spent")
	t.ok(not rat.caught, "and he is still out there")
	rat.stand_down(3)
	t.ok(not rat.begin_night(4, TheRat.ARC_RANK, roster, 1), "no backglass the next Night")
	t.ok(not rat.begin_night(3 + TheRat.RETRY_NIGHTS - 1, TheRat.ARC_RANK, roster, 1),
			"nor the one after that")
	t.ok(rat.begin_night(3 + TheRat.RETRY_NIGHTS, TheRat.ARC_RANK, roster, 1),
			"three Nights later the names are back")

	# Right: he is flipped, the skim stops, and the arc is over for this career.
	rat.note_clue(TheRat.CLUE_LAUNDROMAT)
	rat.note_clue(TheRat.CLUE_PAYPHONE)
	var right := rat.accuse(rat.culprit)
	t.ok(bool(right["right"]), "that was the man")
	t.ok(rat.caught, "and he is flipped")
	t.near(rat.skim_fraction(), 0.0, 1e-9, "the wash comes in whole again")
	t.ok(not rat.begin_night(20, TheRat.ARC_RANK, roster, 1), "and the arc does not re-open")


func _rat_in_the_session(t: TestCtx) -> void:
	Game.new_game(44)
	Game.owned["fronts.coin_op"] = 1
	Game._recompute_stats()
	Game.rank = TheRat.ARC_RANK
	Game.start_night()
	Game.rat_night()
	Game.rat.armed = true
	Game.rat.caught = false

	# The cost is real and it lands in the wrong place: the wash is short, the pile is not.
	# Earned down the money path, so `night_dirty` is the whole of the pile and the invariant
	# below is the invariant the sims actually read.
	Game.earn_flat_dirty(BigMoney.of(1.0, 6), &"briefcase")
	var dirty_before := Game.wallet.dirty
	var clean_before := Game.wallet.clean
	var moved := Game.launder(0.5, Game.launder_cap_left())
	t.ok(moved.is_positive(), "the laundromat washed nothing")
	t.ok(dirty_before.sub_clamped(Game.wallet.dirty).equals_approx(moved, 1e-6),
			"the dirty side of the move is untouched — the invariant the sims read")
	t.ok(Game.wallet.clean.sub_clamped(clean_before).cmp(moved) < 0,
			"and what reached the pocket is short, which IS the clue")
	t.ok(Game.rat.skimmed.is_positive(), "he took his cut")
	t.ok(Game.night_dirty.sub_clamped(Game.night_laundered)
			.equals_approx(Game.wallet.dirty, 1e-6),
			"night_dirty − night_laundered == held dirty still holds")

	# Naming him right is worth ☆50 and stops the skim.
	var roster: Array = Game.bench.available()
	if roster.size() >= TheRat.SUSPECTS:
		Game.rat.begin_night(Game.night_no + 1, Game.rank, roster, Game.session_seed)
		Game.rat_clue(TheRat.CLUE_LAUNDROMAT)
		Game.rat_clue(TheRat.CLUE_COLLECTION)
		var stars := Game.respect
		var caught := Game.rat_accuse(Game.rat.culprit)
		t.ok(bool(caught["right"]), "the right name")
		t.eq(Game.respect, stars + TheRat.RESPECT_CAUGHT, "is worth ☆50")
		t.near(Game.rat.skim_fraction(), 0.0, 1e-9, "and the skim stops")


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

	# The Rat's arc is a career-long thing and travels with the file.
	Game.rat.armed = true
	Game.rat.next_night = 9
	Game.rat.book_skim(BigMoney.of(3.0, 5))
	Game.save_now()
	Game.new_game(0)
	Game.from_dict(Game.save.read())
	t.ok(Game.rat.armed, "he is still out there after a reload")
	t.eq(Game.rat.next_night, 9, "and the backglass keeps its clock")
	t.ok(Game.rat.skimmed.is_positive(), "what he took is on the rap sheet")
	t.ok(not Game.rat.active, "but no Night is flagged until roll call says so")
