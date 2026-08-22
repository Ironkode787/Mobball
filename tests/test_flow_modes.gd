extends RefCounted
## The three modes that hang off the clock: the Wire's numbers draws (docs/05 §4), the
## Collection Round (docs/05 §3) and the Family Meeting's state machine
## (specs/m2-content.md §4). All three are pure logic on a fed clock, so this is the whole
## rule set without a table under it.

const SAVE_PATH := "user://test_flow_modes.json"


func run(t: TestCtx) -> void:
	_wire_clock(t)
	_wire_tickets(t)
	_wire_determinism(t)
	_collection(t)
	_meeting(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_meeting_money(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the Wire -----------------------------------------------------------------


func _wire_clock(t: TestCtx) -> void:
	var w := WireDraws.new()
	w.begin_night(1234, 1)
	t.near(w.time_left, WireDraws.PERIOD, 1e-9, "the tote board opens a full period out")
	t.ok(not w.tick(WireDraws.PERIOD - 1.0), "nothing is drawn early")
	t.ok(w.tick(1.0), "and a draw comes due at 90 seconds")
	t.near(w.time_left, WireDraws.PERIOD, 1e-6, "then the clock starts again")
	t.ok(not w.tick(0.0), "a zero step is not a draw")

	# The period carries its remainder, so a coarse sim step does not drift the schedule.
	var coarse := WireDraws.new()
	coarse.begin_night(1234, 1)
	t.ok(coarse.tick(WireDraws.PERIOD + 5.0), "an overshooting step still draws")
	t.near(coarse.time_left, WireDraws.PERIOD - 5.0, 1e-6, "and hands the overshoot forward")


func _wire_tickets(t: TestCtx) -> void:
	var w := WireDraws.new()
	w.begin_night(0, 0)
	var number := w.peek()
	t.ok(number >= 0 and number < WireDraws.NUMBERS, "the board draws 00-99")

	var spinner := BigMoney.from_float(4_000.0)
	var exact := w.draw(number, spinner)
	t.eq(StringName(exact["hit"]), WireDraws.HIT_EXACT, "the exact number is an exact hit")
	t.near(float(exact["mult"]), WireDraws.EXACT_MULT, 1e-9, "which pays x80")
	t.ok(bool(exact["clean"]), "in CLEAN — the house cannot pay that in cash")
	t.ok((exact["won"] as BigMoney).equals_approx(spinner.mul(WireDraws.EXACT_MULT), 1e-9),
			"off the Night's spinner earnings")
	t.eq(w.exacts, 1, "and the book counts it")

	var next := w.peek()
	var last_digit := (next + 10) % WireDraws.NUMBERS
	if last_digit == next:
		last_digit = (next + 20) % WireDraws.NUMBERS
	var close := w.draw(last_digit, spinner)
	t.eq(StringName(close["hit"]), WireDraws.HIT_LAST, "matching the last digit is a hit")
	t.near(float(close["mult"]), WireDraws.LAST_DIGIT_MULT, 1e-9, "worth x6")
	t.ok(not bool(close["clean"]), "paid dirty — that one is just a payout")

	var miss_ticket := (w.peek() + 1) % WireDraws.NUMBERS
	if miss_ticket % 10 == w.peek() % 10:
		miss_ticket = (miss_ticket + 2) % WireDraws.NUMBERS
	var miss := w.draw(miss_ticket, spinner)
	t.eq(StringName(miss["hit"]), WireDraws.HIT_NONE, "everything else is a miss")
	t.ok(not (miss["won"] as BigMoney).is_positive(), "and pays nothing")

	# The ticket is the spinner's raw count: the last two digits of it, however big it gets.
	var w2 := WireDraws.new()
	w2.begin_night(5, 5)
	var result := w2.draw(1_234, spinner)
	t.eq(int(result["ticket"]), 34, "the ticket is the last two digits of the spin count")
	t.eq(int(w2.draw(-1, spinner)["ticket"]), 99, "and a negative count still reads as a slip")

	# The T5 Wiretap: the number arrives before the draw does, but only inside its lead.
	var tap := WireDraws.new()
	tap.begin_night(11, 1)
	t.eq(tap.early_number(false), -1, "without the Wiretap the board keeps its number")
	t.eq(tap.early_number(true), -1, "and it stays quiet until the draw is close")
	tap.tick(WireDraws.PERIOD - WireDraws.WIRETAP_LEAD + 0.1)
	t.eq(tap.early_number(true), tap.peek(), "inside the lead it shows the next number")
	t.eq(tap.early_number(false), -1, "to the people who bought the ear for it")
	var told := tap.early_number(true)
	t.eq(int(tap.draw(told, BigMoney.zero())["number"]), told,
			"and the number it told you is the number it draws")

	var floor_amount := BigMoney.of(WireDraws.MIN_BASE_MANTISSA, WireDraws.MIN_BASE_EXP)
	t.ok(WireDraws.base_for(BigMoney.zero()).equals_approx(floor_amount, 1e-9),
			"a Night with a cold spinner still has a $500 base")
	t.ok(WireDraws.base_for(BigMoney.from_float(9_000.0))
			.equals_approx(BigMoney.from_float(9_000.0), 1e-9),
			"a hot one prices off what the lane actually made")


func _wire_determinism(t: TestCtx) -> void:
	var a := WireDraws.new()
	var b := WireDraws.new()
	a.begin_night(0xC0FFEE, 3)
	b.begin_night(0xC0FFEE, 3)
	var same := true
	for i in 8:
		if a.draw(0, BigMoney.zero())["number"] != b.draw(0, BigMoney.zero())["number"]:
			same = false
	t.ok(same, "the same career replaying the same Night draws the same numbers")

	var other := WireDraws.new()
	other.begin_night(0xC0FFEE, 4)
	var differs := false
	for i in 8:
		if other.draw(0, BigMoney.zero())["number"] != a.draw(0, BigMoney.zero())["number"]:
			differs = true
	t.ok(differs, "the next Night draws its own")


# --- Collection Rounds --------------------------------------------------------


func _collection(t: TestCtx) -> void:
	var c := CollectionRound.new()
	c.begin_night()
	t.ok(not c.active, "no round until the whole block is armed")
	t.ok(c.on_all_armed(), "three armed banks start one")
	t.ok(not c.on_all_armed(), "and it does not restart on top of itself")
	t.near(c.time_left, CollectionRound.SECONDS, 1e-9, "25 seconds on the clock")

	t.ok(not c.on_collected(&"storefront_laundromat"), "one shop is not a round")
	t.ok(not c.on_collected(&"storefront_laundromat"), "and the same shop twice is still one")
	t.eq(c.collected_count(), 1, "the round counts shops, not visits")
	t.ok(not c.on_collected(&"storefront_pizzeria"), "two is not a round either")
	t.ok(c.on_collected(&"storefront_pawn"), "the third one wins it")
	t.ok(not c.active, "which ends the round")
	t.eq(c.night_won, 1, "booked as perfect")

	# A lapsed round: the clock runs out and it costs nothing.
	var lapse := CollectionRound.new()
	lapse.begin_night()
	lapse.on_all_armed()
	lapse.on_collected(&"storefront_pizzeria")
	lapse.tick(CollectionRound.SECONDS + 0.1)
	t.ok(not lapse.active, "the clock runs out")
	t.eq(lapse.night_won, 0, "and nothing was won")
	t.ok(not lapse.on_all_armed(),
			"the block is still standing, but the round does not immediately re-arm")
	lapse.tick(CollectionRound.RETRIGGER_GAP + 0.1)
	t.ok(lapse.on_all_armed(), "after a beat of quiet it can start again")
	t.eq(lapse.collected_count(), 0, "from nothing")
	t.ok(not lapse.on_collected(&"storefront_pizzeria"),
			"the shop collected in the lapsed round does not count toward the new one")


# --- the Family Meeting -------------------------------------------------------


func _meeting(t: TestCtx) -> void:
	var m := FamilyMeeting.new()
	m.begin_night()
	t.ok(not m.lit, "the back room opens dark")
	t.ok(not m.can_start(true), "and an unlit back room starts nothing")
	t.ok(not m.note_casino_jackpot(), "one Jackpot is not enough")
	t.ok(m.note_casino_jackpot(), "two in a Night lights it")
	t.ok(m.lit, "lit")
	t.ok(not m.note_casino_jackpot(), "a third does not re-light what is already on")

	t.ok(not m.can_start(false), "no Club, no Meeting — the back room is part of the deck")
	t.ok(m.can_start(true), "with the deck bought, the next back-room shot starts it")

	var guy := {"id": 9, "name": "Little Enzo", "trait": GuyTraits.LOUD}
	m.start(guy)
	t.ok(m.active, "the Meeting is on")
	t.ok(not m.lit, "which spends the light")
	t.eq(int(m.guy["id"]), 9, "and the second ball is a named guy")
	t.near(m.dirty_multiplier(), FamilyMeeting.DIRTY_MULT, 1e-9, "ALL dirty doubles")
	t.ok(not m.can_start(true), "you cannot start a Meeting inside a Meeting")

	var rate := BigMoney.from_float(100.0)
	var first := m.take_jackpot(rate)
	t.ok(first.equals_approx(rate.mul(FamilyMeeting.JACKPOT_MINUTES * 60.0), 1e-9),
			"the first back-room re-entry pays four minutes of idle")
	var second := m.take_jackpot(rate)
	t.ok(second.equals_approx(first.mul(FamilyMeeting.JACKPOT_GROWTH), 1e-6),
			"and each one after that is half as much again")
	t.ok(m.take_jackpot(rate).equals_approx(
			first.mul(pow(FamilyMeeting.JACKPOT_GROWTH, 2.0)), 1e-6), "compounding")

	m.end()
	t.ok(not m.active, "one ball left ends it")
	t.near(m.dirty_multiplier(), 1.0, 1e-9, "and the money goes back to normal")
	t.ok(m.guy.is_empty(), "the second guy is off the table")
	t.eq(m.night_jackpots, 3, "the Night remembers what the back room paid")

	# A Collection Round lights it on its own (docs/05 §3).
	var m2 := FamilyMeeting.new()
	m2.begin_night()
	t.ok(m2.note_collection_round(), "a perfect Collection Round lights the back room")
	t.ok(m2.can_start(true), "with no Jackpots at all")

	# Lighting survives the Night: a Meeting you never spent is still owed.
	m2.begin_night()
	t.ok(m2.lit, "an unspent light carries into the next Night")
	t.eq(m2.jackpots_tonight, 0, "but the Jackpot count re-arms")


func _meeting_money(t: TestCtx) -> void:
	Game.new_game(31337)
	Game.heat.reset()
	Game.combo.reset()
	var plain := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	Game.meeting.start({"id": 1, "name": "Sal", "trait": ""})
	var doubled := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	t.ok(doubled.equals_approx(plain.mul(FamilyMeeting.DIRTY_MULT), 1e-9),
			"the Meeting doubles every dirty payout through the one money path")

	# ...and it stacks with the guys who are out there, because both of them are working.
	Game.set_fielded([{"id": 1, "trait": GuyTraits.LOUD}, {"id": 2, "trait": GuyTraits.FAST}])
	t.near(Game.mode_multiplier(), FamilyMeeting.DIRTY_MULT * 1.1 * 1.1, 1e-9,
			"mode and traits fold together")
	Game.meeting.end()
	Game.set_fielded([])
	t.near(Game.mode_multiplier(), 1.0, 1e-9, "and unfold when the crew goes home")

	var clean_before := Game.wallet.clean
	var dirty_before := Game.wallet.dirty
	var paid := Game.earn_clean(BigMoney.from_float(500.0), &"meeting")
	t.ok(Game.wallet.clean.equals_approx(clean_before.add(paid), 1e-9),
			"a clean mode payout lands in clean")
	t.ok(Game.wallet.dirty.equals_approx(dirty_before, 1e-9), "without moving anything dirty")
	t.ok(Game.night_clean.equals_approx(paid, 1e-9), "and books its own Count line")
	t.ok(not Game.night_laundered.is_positive(),
			"it is NOT laundering: nothing came out of the dirty pile")


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(4)
	Game.meeting.note_collection_round()
	Game.casino.resolve(0, true, BigMoney.from_float(50.0), 1.48, false)
	Game.casino.book_payout(BigMoney.from_float(10.0), true)
	Game.collection.on_all_armed()
	Game.collection.on_collected(&"a")
	Game.wire.begin_night(4, 1)
	Game.wire.draw(0, BigMoney.zero())

	t.ok(Game.save_now(), "saved: %s" % Game.save.last_error)
	var before := JSON.stringify(Game.to_dict())
	Game.new_game(5)
	t.ok(not Game.meeting.lit, "a new career opens with the back room dark")
	Game.from_dict(Game.save.read())
	t.eq(JSON.stringify(Game.to_dict()), before, "the whole M2 session round-trips")
	t.ok(Game.meeting.lit, "the unspent Meeting came back")
	t.eq(Game.casino.loss_streak, 1, "so did what the Cooler owes")
	t.ok(Game.casino.total_washed.is_positive(), "and the career's casino book")
	t.eq(Game.wire.total_draws, 1, "and the tote board's")
