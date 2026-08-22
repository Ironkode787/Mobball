extends RefCounted
## The M2 half of the balance autoplayer, unit-tested (game/sim/sim_club.gd + the club money
## path on SimState).
##
## `tests/test_sim_smoke.gd` proves the sim COMPILES, is deterministic, and has not drifted
## from the constants it mirrors. This file proves the club MODEL does what the flow lane's
## rules say: that a deck visit gates the Jackpot, that the wheel's money goes down the right
## pipe depending on one Ledger flag, that a Meeting takes a guy off the Bench and puts one
## inside, and that the Commission really does hold a rank hostage. All of it is a handful of
## objects and no Nights, so it stays inside the normal harness.

const SEED := 424242


func run(t: TestCtx) -> void:
	_deck_menu(t)
	_wheel_money(t)
	_jackpot_needs_one_visit(t)
	_high_roller(t)
	_meeting(t)
	_commission_gate(t)
	_specialists(t)


## The club-era shot menu: the Staircase downstairs, the deck as a second menu upstairs, and
## neither of them present until the licence is bought.
func _deck_menu(t: TestCtx) -> void:
	var profile := SimProfile.get_profile("decent")
	var bare := _stats({})
	var bare_table := SimTable.build(bare, profile)
	t.ok(bare_table.deck == null, "no licence, no deck")
	t.eq(_kinds(bare_table, SimTable.Kind.RAMP), 0, "no licence, no Staircase")

	var club := _stats(_club_owned())
	var table := SimTable.build(club, profile)
	t.eq(_kinds(table, SimTable.Kind.RAMP), 1, "the licence puts the Staircase on the menu")
	t.ok(table.deck != null, "…and builds the deck as its own menu")
	t.eq(_kinds(table.deck, SimTable.Kind.ROULETTE), 1, "the wheel is up there")
	t.eq(_kinds(table.deck, SimTable.Kind.REEL), SimTable.SLOT_COLUMNS, "so are three reels")
	t.eq(_kinds(table.deck, SimTable.Kind.BACKROOM), 1, "so is the back room")
	t.eq(_kinds(table.deck, SimTable.Kind.HIGH_ROLLER), 0,
			"the High Roller is a separate purchase")
	t.ok(table.deck.deck_visit_seconds(profile) < profile.deck_seconds_mean,
			"a deck with no mini-bats is one lap, not a rally")

	var bats := _stats(_club_owned({"muscle.second_set": 1}))
	var with_bats := SimTable.build(bats, profile)
	t.near(with_bats.deck.deck_visit_seconds(profile), profile.deck_seconds_mean, 1e-6,
			"the mini-bats buy the whole visit")
	t.ok(with_bats.deck.deck_rate(profile) > table.deck.deck_rate(profile),
			"…and a busier one")


## Every dollar the wheel pays, and which pipe it goes down. The Wash is one Ledger node and
## it is the difference between laundering and shuffling.
func _wheel_money(t: TestCtx) -> void:
	var owned := _club_owned()
	var dirty := BigMoney.of(1.0, 6)

	var no_wash := _state(owned, dirty)
	var stake := Casino.stake_for(dirty, no_wash.rank)
	t.ok(stake.equals_approx(BigMoney.min_of(dirty.mul(Casino.CasinoRules.STAKE_FRACTION),
			Casino.stake_cap(no_wash.rank)), 1e-6),
			"the stake is 5% of held dirty, under the rank cap")
	t.ok(stake.equals_approx(Casino.stake_cap(0), 1e-6),
			"…and at R0 with a million in the wallet the cap is what binds")
	var lost := no_wash.casino_roulette(RouletteWheel.HOUSE_POCKETS[0], true)
	t.ok(bool(lost["bet"]), "a house pocket is still a bet")
	t.ok(not (lost["won"] as BigMoney).is_positive(), "…that pays nothing")
	t.ok(no_wash.wallet.dirty.equals_approx(dirty.sub_clamped(stake), 1e-6),
			"a losing spin costs exactly the stake")

	var win := _state(owned, dirty)
	var r := win.casino_roulette(1, false)
	t.ok((r["paid"] as BigMoney).is_positive(), "a player pocket pays")
	t.ok(not bool(r["clean"]), "…in DIRTY until the Casino Wash is bought")
	t.ok(not win.total_clean_direct.is_positive(), "…so no clean was created at all")

	var washed := _state(_club_owned({"fronts.casino_wash": 1}), dirty)
	var w := washed.casino_roulette(1, false)
	t.ok(bool(w["clean"]), "the Wash makes the house pay you clean")
	t.ok((w["paid"] as BigMoney).equals_approx(stake.mul(Casino.payout_rate(washed.stats)), 1e-6),
			"a clean payout is the stake × the wheel's payout, untouched by heat or combo")
	t.ok(washed.total_clean_direct.equals_approx(w["paid"], 1e-6), "…and it books as direct clean")
	t.ok(not washed.night_laundered.is_positive(),
			"casino clean is NOT laundering: it must not eat the per-Night wash cap")
	t.near(washed.launder_cap_left().approx_float(), washed.stats.launder_cap().approx_float(),
			1e-6, "…the cap is still whole")

	# The Cooler: five straight losses and the sixth win pays its apology.
	var cooler := _state(_club_owned({"fronts.casino_wash": 1}), BigMoney.of(1.0, 9))
	for _i in Casino.CasinoRules.COOLER_STREAK:
		cooler.casino_roulette(RouletteWheel.HOUSE_POCKETS[0], true)
	t.eq(cooler.casino.loss_streak, Casino.CasinoRules.COOLER_STREAK, "the streak counted")
	var apology := cooler.casino_roulette(1, false)
	t.ok(bool(apology["cooler"]), "the cooler got fired")
	t.near(float(apology["multiplier"]),
			Casino.payout_rate(cooler.stats) * (1.0 + Casino.CasinoRules.COOLER_BONUS), 1e-6,
			"…and the next win paid the apology")


## The Jackpot is a deck-visit shot: three columns between the top of the Staircase and coming
## back downstairs. Columns cleared outside a visit are worth nothing extra.
func _jackpot_needs_one_visit(t: TestCtx) -> void:
	var state := _state(_club_owned({"muscle.second_set": 1}), BigMoney.of(1.0, 6))
	var club := _club(state, "shark")
	# Outside a visit: the reels still drop, but nobody is counting.
	for c in SimTable.SLOT_COLUMNS:
		for _r in SimTable.SLOT_ROWS:
			club.reel(c)
	t.eq(state.jackpots, 0, "a full grid downstairs is not a Jackpot")

	# The columns re-arm on their own clocks, so give them time to come back up.
	club.tick(SimTable.SLOT_RESET_SEC + 0.1)
	club.enter_deck()
	t.ok(state.casino.visit_open(), "a climb opens the visit")
	for c in SimTable.SLOT_COLUMNS:
		for _r in SimTable.SLOT_ROWS:
			club.reel(c)
	t.eq(state.jackpots, 1, "three columns inside one visit is the Jackpot")
	t.ok(state.clean_direct_from.has(&"slot_reels"), "…and it pays clean")
	t.near(state.heat.value, Casino.CasinoRules.JACKPOT_HEAT, 1e-6, "…and it puts you on the map")
	t.eq(state.meeting.jackpots_tonight, 1, "…and the back room noticed")
	t.ok(not state.meeting.lit, "one Jackpot does not light the Family Meeting on its own")

	club.leave_deck()
	t.ok(not state.casino.visit_open(), "coming downstairs closes the visit")


## The ladder is greed, and greed buys VARIANCE: the rungs multiply the next BET, the wheel
## still decides what it was worth, and every rung is flat Heat. `risk_appetite` is how far up
## a profile goes. Balance-sim ruling — on the payout this was an unpriced +80% of realized EV.
func _high_roller(t: TestCtx) -> void:
	var owned := _club_owned({"fronts.casino_wash": 1, "fronts.high_roller": 1})
	var state := _state(owned, BigMoney.of(1.0, 9))
	var club := _club(state, "shark")
	var held := club.high_roller()
	t.ok(held > 0.0, "a shark holds the saucer")
	t.ok(state.heat.value > 0.0, "greed costs Heat immediately")
	t.ok(state.casino.armed_multiplier() > 1.0, "…and arms the next bet")
	var armed := state.casino.armed_multiplier()
	var table_stake := Casino.stake_for(state.wallet.dirty, state.rank)
	var ev_before := Casino.expected_value(state.stats)

	var lost := state.casino_roulette(RouletteWheel.HOUSE_POCKETS[0], true)
	t.ok((lost["staked"] as BigMoney).equals_approx(table_stake.mul(armed), 1e-6),
			"the losing spin rode the ladder: staked %s against a table stake of %s"
			% [(lost["staked"] as BigMoney).text(), table_stake.text()])
	t.near(state.casino.armed_multiplier(), 1.0, 1e-6,
			"…and it is spent, win or lose — it rode the wheel")
	t.near(Casino.expected_value(state.stats), ev_before, 1e-9,
			"a ladder must not move what a dollar staked is worth")

	var r := state.casino_roulette(1, false)
	t.near(float(r["multiplier"]), Casino.payout_rate(state.stats), 1e-6,
			"a win pays the wheel's payout and nothing on top of it")
	t.ok((r["paid"] as BigMoney).equals_approx(
			(r["staked"] as BigMoney).mul(Casino.payout_rate(state.stats)), 1e-6),
			"…so a payout is exactly stake × payout, whatever else is happening tonight")

	var timid := _club(_state(owned, BigMoney.of(1.0, 9)), "duffer")
	t.near(timid.high_roller(), 0.0, 1e-6, "a duffer never holds at all")


## The back room: two guys out, all dirty doubled, one of them pinched when it ends.
func _meeting(t: TestCtx) -> void:
	var state := _state(_club_owned({"muscle.second_set": 1}), BigMoney.of(1.0, 6))
	var club := _club(state, "decent")
	var first: Dictionary = state.bench.available()[0]
	state.set_fielded([first])
	t.near(state.mode_multiplier(), GuyTraits.dirty_mult_for([first]), 1e-6,
			"one guy on the table is his own traits and nothing else")

	club.backroom()
	t.ok(not club.meeting_active(), "an unlit back room is just a saucer")
	state.meeting.note_collection_round()
	t.ok(state.meeting.lit, "a perfect Collection Round lights it")
	club.backroom()
	t.ok(club.meeting_active(), "…and the next back-room shot starts the Meeting")
	t.eq(state.fielded.size(), 2, "a second named guy is on the table")
	t.ok(not state.meeting.lit, "starting the Meeting spent the light")
	t.near(state.mode_multiplier(),
			FamilyMeeting.DIRTY_MULT * GuyTraits.dirty_mult_for(state.fielded), 1e-6,
			"ALL dirty doubles while the crew is out together")

	var before_paid := state.meeting_paid
	club.backroom()
	t.ok(state.meeting_paid.cmp(before_paid) > 0, "the back room pays the growing jackpot")
	t.ok(state.clean_direct_from.has(&"meeting"), "…clean, and outside the wash cap")

	var pinched_before := state.guys_pinched
	club.end_meeting(false)
	t.ok(not club.meeting_active(), "one ball left ends the Meeting")
	t.eq(state.guys_pinched, pinched_before + 1, "the drained guy goes inside like anyone")
	t.eq(state.bench.holding().size(), 1, "…and he is on the Bench's holding list")
	t.near(state.mode_multiplier(), GuyTraits.dirty_mult_for(state.fielded), 1e-6,
			"the ×2 goes away with him")


## The ☆ get you the meeting, the fight gets you the chair (docs/05 §6).
func _commission_gate(t: TestCtx) -> void:
	var state := SimState.new(SEED)
	state.add_respect(Game.RANK_RESPECT[4] + 10)
	t.eq(state.rank_for_respect(state.respect), 4, "the ☆ have bought R4")
	t.eq(state.rank, 3, "…and the Commission is holding it at R3")
	t.ok(state.rank_is_gated(), "the sim can see the ladder is stuck")
	var waiting := state.boss_waiting()
	t.eq(String(waiting.get("id", "")), String(Commission.SAMMY), "Sammy is who is waiting")

	state.commission.begin_fight(Commission.SAMMY)
	var lost := state.boss_finished(Commission.SAMMY, false)
	t.ok(not bool(lost["won"]), "a lost fight is a lost fight")
	t.eq(state.rank, 3, "…and the rank stays where it was")
	t.eq(state.commission.attempts_at(Commission.SAMMY), 1, "…but the attempt is on the record")
	t.ok(not state.boss_waiting().is_empty(), "he is still waiting — a loss retries")

	state.commission.begin_fight(Commission.SAMMY)
	var won := state.boss_finished(Commission.SAMMY, true)
	t.ok((won["purse"] as BigMoney).equals_approx(
			Commission.purse_for(Commission.fight(Commission.SAMMY)), 1e-6),
			"victory pays the fixed clean purse")
	t.ok(state.wallet.clean.cmp(BigMoney.zero()) > 0, "…into the clean pile")
	t.ok(state.has_spoil(Commission.SPOIL_SAMMY), "…and hands over the spoil")
	t.ok(state.rank >= 4, "…and the promotion the ☆ had already earned")
	t.ok(state.boss_waiting().is_empty(), "a beaten man does not wait for you twice")


## The specialists the sim reads, each one visible in the number it is supposed to move.
func _specialists(t: TestCtx) -> void:
	var profile := SimProfile.get_profile("decent")
	var base := _stats({})
	var sal := _stats({"muscle.enforcer_corner": 1, "crew.big_sal": 1})
	var plain_kick := _stats({"muscle.enforcer_corner": 1})
	t.ok(SimNight.ball_time_scale(sal) > SimNight.ball_time_scale(plain_kick),
			"Big Sal's shorter cooldown is more ball time")
	t.ok(SimNight.ball_time_scale(plain_kick) > SimNight.ball_time_scale(base),
			"…and a kickback at all is more than none")
	var both := _stats({"muscle.enforcer_corner": 1, "muscle.right_hand_man": 1})
	t.ok(SimNight.ball_time_scale(both) > SimNight.ball_time_scale(plain_kick),
			"the second kicker is worth its own outlane")

	var vacation := _stats({"influence.inspector_vacation": 1})
	t.ok(SimNight.tilt_chance_for(profile, vacation) < SimNight.tilt_chance_for(profile, base),
			"the Inspector's vacation buys back nudges")

	var skids := _stats({"crew.skids": 1})
	t.ok(skids.serve_speed_mult() > 1.0, "Skids serves faster")
	var nussbaum := _stats({"fronts.coin_op": 1, "crew.nussbaum": 1})
	t.ok(nussbaum.auto_launder_per_sec() > 0.0, "Nussbaum washes on his own")
	var manny := _stats(_club_owned({"crew.manny": 1}))
	t.ok(manny.auto_collect_interval() > 0.0, "Manny works a till on a clock")
	var cohen := _stats({"influence.coffee_fund": 1, "influence.beat_cop": 1, "crew.cohen": 1})
	t.ok(cohen.heat_decay_mult() > 1.0, "Cohen cools the meter faster")
	var state := SimState.new(SEED)
	state.owned = {"influence.coffee_fund": 1, "influence.beat_cop": 1, "crew.cohen": 1}
	state._recompute_stats()
	t.near(state.heat.decay_scale, cohen.heat_decay_mult(), 1e-9,
			"…and the sim's meter is actually told about it")

	# Traits fold into the money path exactly as `Game.mode_multiplier` folds them.
	var loud := {"id": 1, "trait": GuyTraits.LOUD}
	var careful := {"id": 2, "trait": GuyTraits.CAREFUL}
	var s := SimState.new(SEED)
	s.set_fielded([loud])
	t.near(s.mode_multiplier(), GuyTraits.DIRTY_MULT[GuyTraits.LOUD], 1e-9,
			"a Loud guy pays more")
	t.near(s.heat.gain_scale, GuyTraits.HEAT_SCALE[GuyTraits.LOUD], 1e-9, "…and runs hotter")
	s.set_fielded([loud, careful])
	t.near(s.heat.gain_scale, GuyTraits.HEAT_SCALE[GuyTraits.LOUD]
			* GuyTraits.HEAT_SCALE[GuyTraits.CAREFUL], 1e-9,
			"two guys out is two guys' traits, multiplied")


# --- helpers -------------------------------------------------------------------------


## The Ledger nodes that put a Club on the table, plus whatever else the caller wants.
static func _club_owned(extra: Dictionary = {}) -> Dictionary:
	var owned := {
		"fronts.coin_op": 1,
		"rackets.protection_laundromat": 1,
		"rackets.protection_pizzeria": 1,
		"rackets.protection_pawn": 1,
		"rackets.club_license": 1,
	}
	for id: Variant in extra:
		owned[String(id)] = int(extra[id])
	return owned


static func _stats(owned: Dictionary) -> Stats:
	var s := Stats.new()
	s.recompute(owned)
	return s


static func _state(owned: Dictionary, dirty: BigMoney) -> SimState:
	var state := SimState.new(SEED)
	state.owned = owned.duplicate()
	state._recompute_stats()
	state.start_night()
	state.wallet.earn_dirty(dirty)
	return state


static func _club(state: SimState, profile_id: String) -> SimClub:
	var profile := SimProfile.get_profile(profile_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	return SimClub.new(state, profile, SimTable.build(state.stats, profile, state.catalog), rng)


static func _kinds(menu: SimTable, kind: int) -> int:
	var n := 0
	for row in menu.shots:
		if int(row["kind"]) == kind:
			n += 1
	return n
