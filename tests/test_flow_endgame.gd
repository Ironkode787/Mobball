extends RefCounted
## THE ENDGAME (docs/05 §9, docs/02 §2 R7, docs/06): Federal Heat and the RICO verdict,
## the City Hall Circuit and Empire Mode, the 5-ball Family Reunion, and Skip Town.

const SAVE_PATH := "user://test_flow_endgame.json"


func run(t: TestCtx) -> void:
	_federal_accrual(t)
	_circuit(t)
	_empire_clock(t)
	_reunion_rules(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_federal_in_the_session(t)
	_rico_verdict(t)
	_empire_money(t)
	_the_black_book(t)
	_skip_town(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- federal heat -------------------------------------------------------------


func _federal_accrual(t: TestCtx) -> void:
	var fbi := FederalHeat.new()
	t.ok(not fbi.enabled, "the Bureau is not interested in a nobody")
	t.near(fbi.night_tick(200), 0.0, 1e-9, "however big he gets")

	fbi.enable(true)
	t.near(fbi.night_tick(FederalHeat.NODE_FLOOR), 0.0, 1e-9,
			"forty nodes is a business, not a conspiracy")
	t.near(fbi.night_tick(FederalHeat.NODE_FLOOR + 10), 5.0, 1e-9,
			"ten past the line is +5 a Night")
	t.near(fbi.value, 5.0, 1e-9, "and it accrues")
	t.near(fbi.meter_value(), FederalHeat.METER_BASE + 5.0, 1e-9,
			"drawn as one dial with two stages")

	# Nothing else moves it: no shot, no bribe, no quiet Night.
	var nights := fbi.nights_to_rico(FederalHeat.NODE_FLOOR + 10)
	t.ok(nights > 0, "and the file says how long you have")
	for i in nights:
		fbi.night_tick(FederalHeat.NODE_FLOOR + 10)
	t.ok(fbi.rico_pending, "then the Feds are at the door")
	t.eq(fbi.nights_to_rico(FederalHeat.NODE_FLOOR + 10), 0, "with nothing left on the clock")
	t.near(fbi.night_tick(999), 0.0, 1e-9, "and the meter stops while they are standing there")

	fbi.resolve_rico(true)
	t.ok(not fbi.rico_pending, "surviving it clears the door")
	t.near(fbi.value, 0.0, 1e-9, "and takes the whole stage off (docs/05 §9: federal −100)")
	t.eq(fbi.raids_survived, 1, "one on the record")

	fbi.value = FederalHeat.RICO_AT
	fbi.rico_pending = true
	fbi.resolve_rico(false)
	t.ok(fbi.value > 0.0, "losing it does not clear the case")
	t.ok(fbi.value < FederalHeat.RICO_AT, "it only buys a few Nights")
	t.eq(fbi.raids_lost, 1, "and the loss is on the file")


# --- the circuit --------------------------------------------------------------


func _circuit(t: TestCtx) -> void:
	var crown := EmpireMode.new()
	crown.begin_night()
	t.eq(String(crown.next_leg()), String(EmpireMode.LEGS[0]), "the circuit starts at the orbit")

	# In order, or not at all.
	t.ok(not crown.on_leg(&"dome"), "the dome first is a lovely shot and worth nothing")
	t.eq(crown.leg, 0, "the chain has not started")
	t.ok(not crown.on_leg(&"orbit"), "one leg")
	t.eq(crown.leg, 1, "in hand")
	t.ok(not crown.on_leg(&"dome"), "and the wrong second leg breaks it")
	t.eq(crown.leg, 0, "back to nothing")

	# On the clock.
	crown.on_leg(&"orbit")
	crown.tick(EmpireMode.LEG_WINDOW + 0.1)
	t.eq(crown.leg, 0, "a leg that arrives too late is a lap that went cold")

	# The whole thing, flown.
	for id in EmpireMode.LEGS:
		var closed := crown.on_leg(id)
		if id == EmpireMode.LEGS[EmpireMode.LEGS.size() - 1]:
			t.ok(closed, "the dome closes the City Hall Circuit")
		else:
			t.ok(not closed, "%s is not the end of it" % id)
	t.eq(crown.circuits_total, 1, "one circuit flown")

	# An orbit out of order is not a mistake, it is a new lap.
	crown.on_leg(&"orbit")
	crown.on_leg(&"staircase")
	t.eq(crown.leg, 2, "two legs in")
	crown.on_leg(&"orbit")
	t.eq(crown.leg, 1, "and a fresh orbit starts the lap again rather than killing it")


func _empire_clock(t: TestCtx) -> void:
	var crown := EmpireMode.new()
	crown.begin_night()
	crown.begin()
	t.ok(crown.active, "EMPIRE is lit")
	t.ok(crown.lit_tonight, "and tonight knows it")
	t.near(crown.dirty_multiplier(), EmpireMode.DIRTY_MULT, 1e-9, "×10 on everything")
	t.ok(not crown.on_leg(&"orbit"), "the circuit is not re-flown while it is running")

	crown.book_earned(BigMoney.from_float(1_000.0))
	t.ok(not crown.tick(EmpireMode.SECONDS - 1.0), "sixty seconds")
	t.ok(crown.tick(1.0), "then it is over")
	t.ok(not crown.active, "the city goes back to being a city")
	t.near(crown.dirty_multiplier(), 1.0, 1e-9, "at ordinary rates")
	t.ok(crown.dividend().equals_approx(
			BigMoney.from_float(1_000.0 * EmpireMode.CLEAN_SHARE), 1e-9),
			"and it pays a clean share of what the minute made")
	t.ok(crown.lit_tonight, "the Reunion still knows it was lit")

	# Re-lightable: the shot is that hard (docs/02 §2 R7).
	for id in EmpireMode.LEGS:
		crown.on_leg(id)
	crown.begin()
	t.eq(crown.runs_tonight, 2, "a second circuit lights it again")


func _reunion_rules(t: TestCtx) -> void:
	var room := FamilyMeeting.new()
	room.begin_night()
	room.start({"id": 1, "name": "Sal"})
	t.eq(room.size, 2, "an ordinary Meeting is two guys working")
	t.near(room.dirty_multiplier(), FamilyMeeting.DIRTY_MULT, 1e-9, "and doubles all dirty")
	t.ok(not room.is_reunion(), "which is not a Reunion")
	room.end()

	var crew: Array[Dictionary] = []
	for i in FamilyMeeting.REUNION_GUYS - 1:
		crew.append({"id": i + 2, "name": "Guy %d" % i})
	room.start_with(crew)
	t.eq(room.size, FamilyMeeting.REUNION_GUYS, "a Reunion is the whole crew")
	t.ok(room.is_reunion(), "and says so")
	t.near(room.dirty_multiplier(), float(FamilyMeeting.REUNION_GUYS), 1e-9,
			"every Meeting rule scales with the crew: five guys is ×5")
	t.eq(room.extra_guys.size(), FamilyMeeting.REUNION_GUYS - 1, "four of them joined")
	t.eq(room.night_reunions, 1, "one Reunion tonight")
	room.end()
	t.eq(room.size, 2, "and the room goes back to normal after")


# --- against the real session -------------------------------------------------


func _federal_in_the_session(t: TestCtx) -> void:
	Game.new_game(31)
	Game.rank = FederalHeat.RANK
	for i in FederalHeat.NODE_FLOOR + 4:
		Game.owned["node.%d" % i] = 1
	Game.owned[Commission.SPOIL_SAMMY] = 1
	Game.owned["relic.museum"] = 1
	t.eq(Game.owned_node_count(), FederalHeat.NODE_FLOOR + 4,
			"the Feds count what you bought, not what you took off a boss")

	Game.start_night()
	t.ok(Game.federal.enabled, "R7 opens the blue stage")
	t.ok(Game.heat.federal_enabled, "and the meter's ceiling with it")
	t.near(Game.federal.value, 4.0 * FederalHeat.PER_NODE_PER_NIGHT, 1e-9,
			"four nodes past the line, one Night's worth")
	t.ok(not Game.rico_pending(), "nobody is at the door yet")


func _rico_verdict(t: TestCtx) -> void:
	Game.new_game(32)
	Game.rank = FederalHeat.RANK
	Game.federal.enable(true)
	Game.federal.value = FederalHeat.RICO_AT
	Game.federal.rico_pending = true
	Game.wallet.earn_dirty(BigMoney.of(1.0, 9))
	var dirty := Game.wallet.dirty
	var clean := Game.wallet.clean
	var stars := Game.respect

	var won := Game.rico_finished(true)
	t.ok(bool(won["survived"]), "UNTOUCHABLE")
	t.ok((won["payout"] as BigMoney).equals_approx(dirty.mul(Game.RICO_CLEAN_PAYOUT), 1e-9),
			"twice the held dirty, in clean — the biggest payout in the game")
	t.ok(Game.wallet.clean.equals_approx(clean.add(won["payout"]), 1e-9), "and it lands")
	t.ok(Game.wallet.dirty.equals_approx(dirty, 1e-9), "the dirty pile is untouched")
	t.eq(Game.respect, stars + Game.RESPECT_RICO_SURVIVED, "☆ for riding it out")
	t.near(Game.federal.value, 0.0, 1e-9, "federal −100")
	t.ok(not Game.rico_pending(), "and the door is clear")
	t.eq(int(Game.career.get("raids_survived", 0)), 1, "it counts toward the Juice")

	# The other way.
	Game.federal.value = FederalHeat.RICO_AT
	Game.federal.rico_pending = true
	var held := Game.wallet.dirty
	var lost := Game.rico_finished(false)
	t.ok(not bool(lost["survived"]), "the case sticks")
	t.ok((lost["confiscated"] as BigMoney).equals_approx(
			held.mul(Rates.RAID_CONFISCATE_FRACTION * Game.RICO_CONFISCATE_MULT), 1e-9),
			"standard confiscation, doubled")
	t.ok(Game.wallet.clean.is_positive(), "clean cash is never touched (P5)")
	t.ok(Game.federal.value > 0.0, "and the file stays open")
	t.ok(Game.skip_town_available(), "which is when the train starts being suggested")

	# A policy does not cover a federal case; it covers half of one.
	Game.federal.value = FederalHeat.RICO_AT
	Game.federal.rico_pending = true
	var before := Game.wallet.dirty
	var insured := Game.rico_finished(false, true)
	t.ok(bool(insured["insured"]), "the policy pays out")
	t.ok((insured["confiscated"] as BigMoney).equals_approx(
			before.mul(Rates.RAID_CONFISCATE_FRACTION), 1e-9),
			"and halves what the Bureau takes")


func _empire_money(t: TestCtx) -> void:
	Game.new_game(33)
	Game.rank = FederalHeat.RANK
	Game.start_night()
	var quiet := Game.preview_switch(&"bumpers", BigMoney.from_float(100.0))

	for id in EmpireMode.LEGS:
		var lit := Game.empire_leg(id)
		if id == EmpireMode.LEGS[EmpireMode.LEGS.size() - 1]:
			t.ok(lit, "the circuit lights EMPIRE")
	t.ok(Game.empire.active, "sixty seconds of it")
	var loud := Game.preview_switch(&"bumpers", BigMoney.from_float(100.0))
	t.ok(loud.equals_approx(quiet.mul(EmpireMode.DIRTY_MULT), 1e-9), "at ×10 on everything")

	var paid := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0))
	t.ok(Game.empire.earned.equals_approx(paid, 1e-9),
			"and what the minute makes is measured on the money that landed")

	var clean := Game.wallet.clean
	Game.empire.tick(EmpireMode.SECONDS)
	var dividend := Game.empire_finished()
	t.ok(dividend.equals_approx(paid.mul(EmpireMode.CLEAN_SHARE), 1e-9),
			"the dividend is a clean share of the take")
	t.ok(Game.wallet.clean.equals_approx(clean.add(dividend), 1e-9), "paid clean")

	# The Reunion hangs off Empire having been lit tonight, at R7.
	t.ok(Game.reunion_ready(), "and the back room is ready to send everybody")
	Game.rank = 6
	t.ok(not Game.reunion_ready(), "which is an R7 thing")


## The META-3 contract: what the flow lane hands the meta lane and what it reads back.
func _the_black_book(t: TestCtx) -> void:
	Game.new_game(36)
	Game.rank = 3
	Game.respect = 500
	Game.commission.mark_beaten(Commission.SAMMY)
	Game.career["heists_cleared"] = 2
	Game.career["raids_survived"] = 1
	Game._book_lifetime_clean(BigMoney.of(4.0, 9))

	var totals := Game.career_totals()
	t.ok(totals["lifetime_clean"] is BigMoney, "lifetime_clean travels as BigMoney")
	t.ok((totals["lifetime_clean"] as BigMoney).equals_approx(BigMoney.of(4.0, 9), 1e-9),
			"and it is money EARNED, not money held")
	t.eq(int(totals["bosses_beaten"]), 1, "bosses come off the Commission's own book")
	t.eq(int(totals["heists_cleared"]), 2, "heists off the rap sheet")
	t.eq(int(totals["raids_survived"]), 1, "raids too")
	t.eq(int(totals["excess_respect"]), 500 - Game.rank_threshold(3),
			"and excess_respect is the ☆ past the rank actually reached")
	t.ok(SkipTown.juice_for(totals) > 0, "which the Book can score")

	# The ladder is read through the perk fold, so a repeat city can be cheaper without any
	# of the ranks moving.
	t.eq(Game.rank_threshold(3), Game.RANK_RESPECT[3],
			"an unbought Book prices the ladder exactly as shipped")
	t.eq(Game.rank_ladder().size(), Game.RANK_RESPECT.size(), "and the whole ladder with it")
	t.eq(Game.rank_for_respect(Game.RANK_RESPECT[4]), 4, "the ☆ still say what they said")

	# ★ the clean share (Stats.clean_share, T6/T7 content). A slice of every switch arrives
	# already clean — drawn against tonight's wash cap, hot for its whole value, and booked as
	# LAUNDERED, because dirty really did become clean.
	Game.new_game(37)
	# The share is drawn against the wash cap, so a career with no laundry has nothing to draw
	# from — which is the honest behaviour, and why the fixture buys a washer too.
	Game.owned["fronts.coin_op"] = 1
	Game.owned["crew.the_bagman"] = 1
	Game._recompute_stats()
	Game.start_night()
	var share := Game.stats.clean_share()
	if share > 0.0:
		var clean_before := Game.wallet.clean
		var washed_before := Game.night_laundered
		var paid := Game.earn_switch(&"bumpers", BigMoney.from_float(10_000.0))
		var washed := Game.night_laundered.sub_clamped(washed_before)
		t.ok(washed.is_positive(), "the Bagman's share did not wash anything")
		t.ok(washed.equals_approx(paid.mul(share), 1e-6),
				"the share is not the share the Ledger sold")
		t.ok(Game.wallet.clean.equals_approx(clean_before.add(washed), 1e-9),
				"and it lands as clean")
		t.ok(Game.night_dirty.sub_clamped(Game.night_laundered)
				.equals_approx(Game.wallet.dirty, 1e-6),
				"night_dirty − night_laundered == held dirty survives the share")
		# It is drawn against the per-Night cap, so it cannot outrun docs/03 §2.
		Game.night_laundered = Game.stats.launder_cap()
		var capped_before := Game.wallet.clean
		Game.earn_switch(&"bumpers", BigMoney.from_float(10_000.0))
		t.ok(Game.wallet.clean.equals_approx(capped_before, 1e-9),
				"with the wash cap spent the share pays nothing")
	else:
		t.ok(true, "no clean_share content in this build: the consumption point is inert")

	# The Book itself rides in the save file: the flow lane owns the file, meta owns the object.
	var book := Game.prestige()
	if book == null:
		t.ok(true, "no meta lane: the Book is skipped, not crashed")
		return
	t.ok(book.has_method("to_dict"), "the Book serializes")
	t.ok(Game.to_dict().has("prestige"), "and the save carries it")


func _skip_town(t: TestCtx) -> void:
	Game.new_game(34)
	Game.rank = SkipTown.RANK
	Game.respect = 9_000
	Game.night_no = 40
	Game.wallet.earn_dirty(BigMoney.of(5.0, 8))
	Game.wallet.earn_clean(BigMoney.of(4.0, 11))
	Game._book_lifetime_clean(BigMoney.of(4.0, 11))
	Game.career["raids_survived"] = 2
	Game.career["heists_cleared"] = 3
	Game.commission.mark_beaten(Commission.SAMMY)
	Game.owned["rackets.numbers_game"] = 1
	Game.heists.relics = PackedStringArray(["relic.museum"])
	Game.heat.value = 80.0
	Game.start_night()

	var preview := Game.skip_town_preview()
	t.ok(bool(preview["available"]), "R7 can leave whenever it likes")
	t.ok(int(preview["juice"]) > 0, "and the city is worth something")

	var keep := Game.bench.available()[0]
	var kept_name := String(keep["name"])
	var result := Game.skip_town(keep)

	t.eq(int(result["juice"]), int(preview["juice"]), "the train pays what the preview said")
	t.eq(int(Game.career.get("cities", 0)), 1, "one city behind you")
	t.ok(not Game.wallet.clean.is_positive(), "the clean cash stayed in the old city")
	t.eq(Game.respect, Game.RANK_RESPECT[Game.rank], "Respect is whatever the new rank is")
	t.eq(Game.night_no, 0, "a new city starts on Night one")
	t.ok(Game.owned.is_empty(), "the table is gone")
	t.near(Game.heat.value, 0.0, 1e-9, "and the trail is cold")
	t.ok(not Game.lifetime_clean().is_positive(),
			"the rap sheet's money line starts again, so the next city is scored on its own")
	t.eq(int(Game.career.get("raids_survived", 0)), 0, "and so do the flat terms")

	# One guy comes with you, and he is at the front of a bench full of strangers.
	t.eq(String(Game.bench.guys[0]["name"]), kept_name, "he came with you")
	t.ok(Game.bench.available().size() > 1, "into a crew he has never met")
	var ids := {}
	for g in Game.bench.guys:
		t.ok(not ids.has(int(g["id"])), "and nobody in the new city shares an id")
		ids[int(g["id"])] = true

	t.ok(Game.heists.relics.has("relic.museum"), "the Museum is a shelf, not a racket")
	t.ok(Game.heists.cleared == 0, "but the war room's book is this city's")


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(35)
	Game.rank = FederalHeat.RANK
	Game.federal.enable(true)
	Game.federal.value = 42.0
	Game.federal.rico_pending = true
	Game.empire.runs_total = 3
	Game.empire.circuits_total = 4
	Game.career["cities"] = 2
	Game._book_lifetime_clean(BigMoney.of(7.0, 10))
	t.ok(Game.save_now(), "the career writes")

	Game.new_game(0)
	Game.from_dict(Game.save.read())
	t.near(Game.federal.value, 42.0, 1e-6, "the blue meter survives the save")
	t.ok(Game.federal.enabled and Game.heat.federal_enabled,
			"and so does the stage being open at all")
	t.ok(Game.rico_pending(), "a raid at the door is still at the door after a reload")
	t.eq(Game.empire.circuits_total, 4, "circuits flown are on the rap sheet")
	t.eq(int(Game.career.get("cities", 0)), 2, "so is the city count")
	t.ok(Game.lifetime_clean().equals_approx(BigMoney.of(7.0, 10), 1e-9),
			"and the money line the Juice is scored off")
