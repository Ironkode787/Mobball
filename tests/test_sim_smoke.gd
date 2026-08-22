extends RefCounted
## The balance autoplayer, kept alive in the normal harness (game/sim/).
##
## The full run is `tools/balance.sh` and it is deliberately NOT in tools/check.sh — a
## 14-day × 3-profile sweep is seconds of wall clock and balance is a tuning question, not a
## build gate. What IS a build gate: the sim compiles, it is deterministic, and the constants
## it mirrors out of the flow/table lanes still match the originals. That last one is the
## whole point of this file — `SimState` reimplements `Game`'s money path, and a silent drift
## between them would quietly invalidate every number in the tuning report.

const PROFILE := "duffer"
const SEED := 20250822
const DAYS := 2


func run(t: TestCtx) -> void:
	# The experiment switches are process-wide statics; pin both to the SHIPPED values so this
	# file measures the shipped economy no matter what ran before it in the same process.
	# (`high_roller_scales_stake` is gone: that counterfactual won and is the rule now.)
	SimState.skill_shot_scales_with_rank = false
	SimState.clean_eats_wash_cap = false
	_mirrored_constants(t)
	_profiles_load(t)
	_career(t)
	_determinism(t)
	_money_path_matches_game(t)


## Every number `game/sim/` copied out of another lane, checked against its original.
func _mirrored_constants(t: TestCtx) -> void:
	t.eq(Array(SimState.RANK_RESPECT), Array(Game.RANK_RESPECT), "rank ladder mirrors Game")
	t.eq(SimState.RESPECT_SKILL_SHOT, Game.RESPECT_SKILL_SHOT, "skill shot ☆ mirrors Game")
	t.eq(SimState.RESPECT_RAID_SURVIVED, Game.RESPECT_RAID_SURVIVED, "raid ☆ mirrors Game")
	t.near(SimState.RAID_CLEAN_PAYOUT, Game.RAID_CLEAN_PAYOUT, 1e-9, "raid payout mirrors Game")
	t.near(SimState.SKILL_SHOT_MANTISSA, Game.SKILL_SHOT_MANTISSA, 1e-9, "skill shot cash mirrors Game")
	t.eq(SimState.SKILL_SHOT_EXP, Game.SKILL_SHOT_EXP, "skill shot exponent mirrors Game")

	t.eq(SimNight.GUYS_PER_NIGHT, NightController.GUYS_PER_NIGHT, "guys per Night mirrors flow")
	t.near(SimNight.PINCH_BEAT, NightController.PINCH_BEAT, 1e-9, "pinch beat mirrors flow")
	t.near(SimNight.BALL_SAVE_SECONDS, NightController.BALL_SAVE_SECONDS, 1e-9, "save window mirrors flow")
	t.near(SimNight.SURVIVE_SECONDS, NightController.SURVIVE_SECONDS, 1e-9, "survive time mirrors flow")
	t.near(SimNight.TILT_HEAT, NightController.TILT_HEAT, 1e-9, "tilt heat mirrors flow")
	t.near(SimNight.RAID_SECONDS, RaidMode.DURATION, 1e-9, "raid duration mirrors flow")

	t.near(SimTable.BUMPER, TableScore.BUMPER, 1e-9, "bumper value mirrors the table")
	t.near(SimTable.SLING, TableScore.SLING, 1e-9, "sling value mirrors the table")
	t.near(SimTable.SPINNER_SEGMENT, TableScore.SPINNER_SEGMENT, 1e-9, "spinner value mirrors the table")
	t.near(SimTable.ROLLOVER, TableScore.ROLLOVER, 1e-9, "rollover value mirrors the table")
	t.near(SimTable.WIRE_TARGET, TableScore.WIRE_TARGET, 1e-9, "wire value mirrors the table")
	t.near(SimTable.BANK_COMPLETE, TableScore.BANK_COMPLETE, 1e-9, "bank bonus mirrors the table")
	t.near(SimTable.ORBIT, TableScore.ORBIT, 1e-9, "orbit value mirrors the table")
	t.near(SimTable.SPIN_FRICTION, Spinner.FRICTION, 1e-9, "spinner friction mirrors the table")
	t.near(SimTable.SPIN_MAX_SPEED, Spinner.MAX_SPEED, 1e-9, "spinner max speed mirrors the table")
	t.near(SimTable.SPIN_MIN_KICK, Spinner.MIN_KICK, 1e-9, "spinner min kick mirrors the table")
	t.near(SimTable.WASH_COOLDOWN, Storefront.WASH_COOLDOWN, 1e-9, "wash cooldown mirrors the table")
	t.near(SimTable.WIRE_RESET_SEC, TargetBank.new().reset_seconds, 1e-9, "bank reset mirrors the table")
	t.eq(SimTable.STOREFRONT_TARGETS, 3, "a storefront bank is three drop targets")

	_m2_constants(t)


## M2 (specs/m2-content.md): the Club deck, the casino's rulebook, the Family Meeting and the
## Commission ladder. Every one of these is a number `game/sim/` copied out of the flow or
## table lane, and a change on either side has to break this test rather than a tuning report.
func _m2_constants(t: TestCtx) -> void:
	# --- the deck's hardware (game/table) ---
	t.near(SimTable.RAMP_CLIMB, TableScore.RAMP_CLIMB, 1e-9, "staircase pay mirrors the table")
	t.near(SimTable.CASINO_POCKET, TableScore.CASINO_POCKET, 1e-9, "pocket pay mirrors the table")
	t.near(SimTable.CASINO_REEL, TableScore.CASINO_REEL, 1e-9, "reel pay mirrors the table")
	t.eq(SimTable.SLOT_COLUMNS, SlotReels.COLS, "reel columns mirror the slots")
	t.eq(SimTable.SLOT_ROWS, SlotReels.ROWS, "reel rows mirror the slots")
	t.near(SimTable.SLOT_RESET_SEC, SlotReels.new().reset_seconds, 1e-9,
			"reel re-arm mirrors the slots")
	t.eq(SimTable.ROULETTE_POCKETS, RouletteWheel.POCKETS, "pocket count mirrors the wheel")
	t.eq(Array(SimTable.HOUSE_POCKETS), Array(RouletteWheel.HOUSE_POCKETS),
			"the house's pockets mirror the wheel")
	t.eq(Array(SimTable.HOUSE_GIVE_ORDER), Array(RouletteWheel.HOUSE_GIVE_ORDER),
			"the give-order mirrors the wheel")
	t.eq(SimTable.ROULETTE_POCKETS, Casino.CasinoRules.POCKETS, "wheel and rulebook agree")
	t.eq(RouletteWheel.PLAYER_POCKETS_BASE, Casino.CasinoRules.PLAYER_POCKETS,
			"the wheel's base pockets are the rulebook's")
	t.near(SimTable.HIGH_ROLLER_STEP_SEC, HoldSaucer.new().step_seconds, 1e-9,
			"the ladder's cadence mirrors the saucer")
	t.eq(Array(Casino.CasinoRules.HIGH_ROLLER_MULT), Array(ClubDeck.HIGH_ROLLER_STEPS),
			"the ladder the deck builds is the ladder the rulebook prices")
	t.eq(SimClub.LADDER_TOP, Casino.CasinoRules.HIGH_ROLLER_MULT.size() - 1,
			"the sim's greed tops out on the last rung of the real ladder")

	# --- the casino's rulebook (game/flow/casino.gd) — read, never re-guessed ---
	var scratch := Stats.new()
	scratch.recompute({})
	t.near(Casino.expected_value(scratch), float(Casino.CasinoRules.PLAYER_POCKETS)
			/ float(Casino.CasinoRules.POCKETS) * Casino.CasinoRules.PAYOUT - 1.0, 1e-9,
			"a bare wheel is 5/8 × PAYOUT − 1")
	t.near(Casino.CasinoRules.STAKE_FRACTION, 0.05, 1e-9, "table stakes are 5% of held dirty")
	t.eq(Casino.CasinoRules.JACKPOT_COLUMNS, SlotReels.COLS, "a Jackpot is every column")
	t.eq(SimTable.SLOT_COLUMNS, Casino.CasinoRules.JACKPOT_COLUMNS,
			"the sim clears the same three columns the rulebook wants")
	# The pocket give-order and the pocket cap have to agree, or a maxed Loaded Dice asks the
	# wheel for a pocket it has no rule for.
	t.ok(Casino.CasinoRules.PLAYER_POCKETS_MAX <= Casino.CasinoRules.POCKETS
			- (RouletteWheel.HOUSE_POCKETS.size() - RouletteWheel.HOUSE_GIVE_ORDER.size()),
			"the wheel can give back every pocket the rulebook lets Influence buy")
	t.eq(Casino.CasinoRules.PLAYER_POCKETS_MAX, Stats.CASINO_POCKETS_MAX,
			"the pocket ceiling is the same on both sides")
	t.eq(Casino.CasinoRules.PLAYER_POCKETS, Stats.CASINO_POCKETS_BASE,
			"the pocket floor is the same on both sides")
	# THE RULING (balance sim): the edge is bought in PAYOUT only. The ceiling equals the base
	# so no shipped node can move the wheel, and the payout ceiling is exactly the base payout
	# plus every edge point Influence can own — which lands the EV on +5.0% and nowhere else.
	t.eq(Casino.CasinoRules.PLAYER_POCKETS_MAX, Casino.CasinoRules.PLAYER_POCKETS,
			"the pocket ceiling is the base: Influence buys payout, not pockets")
	t.near(Casino.CasinoRules.PAYOUT + Stats.CASINO_EDGE_MAX, Casino.CasinoRules.PAYOUT_MAX,
			1e-9, "the edge cap and the payout cap are one decision written twice")
	var fully_bought := Stats.new()
	fully_bought.recompute({"crew.eddie": 12, "influence.loaded_dice": 8})
	t.near(fully_bought.casino_edge_add(), Stats.CASINO_EDGE_MAX, 1e-9,
			"the shipped catalog can buy the whole edge")
	t.near(Casino.expected_value(fully_bought), 0.05, 1e-9,
			"and full investment is exactly +5% EV, which is the top of the design band")
	# The High Roller rides the STAKE, so nothing it does may show up in the wheel's book.
	var ladder := Casino.new()
	ladder.arm(Casino.CasinoRules.HIGH_ROLLER_MULT.size() - 1)
	t.near(Casino.expected_value(fully_bought), 0.05, 1e-9,
			"an armed ladder is variance, not expectation: EV must not move")
	var bet := ladder.stake_with_ladder(BigMoney.from_float(100.0), BigMoney.of(1.0, 9))
	t.ok(bet.equals_approx(BigMoney.from_float(500.0), 1e-9),
			"the top rung is ×5 on the BET (%s)" % bet.text())
	t.near(float(ladder.resolve(1, false, bet, Casino.CasinoRules.PAYOUT, false)["multiplier"]),
			Casino.CasinoRules.PAYOUT, 1e-9, "and the payout stays the wheel's own")
	for pocket in range(Casino.CasinoRules.POCKETS):
		t.eq(SimTable.pocket_is_house(pocket, Casino.CasinoRules.PLAYER_POCKETS),
				RouletteWheel.HOUSE_POCKETS.has(pocket),
				"pocket %d is the house's on a bare wheel, both sides" % pocket)
	var house_at_max := 0
	for pocket in range(Casino.CasinoRules.POCKETS):
		if SimTable.pocket_is_house(pocket, Casino.CasinoRules.PLAYER_POCKETS_MAX):
			house_at_max += 1
	t.eq(house_at_max, Casino.CasinoRules.POCKETS - Casino.CasinoRules.PLAYER_POCKETS_MAX,
			"a fully-bought wheel leaves the house exactly its cap")

	# --- the Family Meeting (game/flow/meeting.gd) ---
	t.near(FamilyMeeting.DIRTY_MULT, 2.0, 1e-9, "a Meeting doubles all dirty")
	t.eq(FamilyMeeting.JACKPOTS_TO_LIGHT, 2, "two slots Jackpots light the back room")
	t.near(SimPolicy.MEETING_JACKPOTS, 1.0, 1e-9,
			"the projection credits one back-room re-entry per Meeting")
	t.near(FamilyMeeting.JACKPOT_GROWTH, 1.5, 1e-9, "the back room grows by half each take")
	t.eq(int(SimPolicy.JACKPOT_HITS), SlotReels.COLS * SlotReels.ROWS,
			"a Jackpot costs one drop per target in the grid")
	t.eq(CollectionRound.RESPECT, 10, "a perfect Collection Round is ☆10")
	t.near(CollectionRound.SECONDS, 25.0, 1e-9, "a Collection Round runs 25 s")
	# Once a Night, like the combo's ☆ (balance-sim ruling). Both sides of the sim drive the
	# real `CollectionRound`, so proving the rulebook here proves it for the career runs.
	var block := CollectionRound.new()
	block.begin_night()
	t.eq(block.take_respect(), CollectionRound.RESPECT, "the first perfect round pays ☆10")
	t.eq(block.take_respect(), 0, "the second one pays money and nothing else")
	block.begin_night()
	t.eq(block.take_respect(), CollectionRound.RESPECT, "and the next Night re-arms it")
	t.near(SimNight.STOREFRONT_POLL, NightController.STOREFRONT_POLL, 1e-9,
			"the block is read at the flow lane's cadence")

	# --- the Commission (game/flow/bosses/commission.gd) ---
	t.eq(Commission.FIGHTS.size(), 2, "two fights gate the M2 ladder")
	t.eq(Commission.fight_gating(3).get("id", &""), Commission.SAMMY, "Sammy gates R3→R4")
	t.eq(Commission.fight_gating(4).get("id", &""), Commission.BUTCHER, "the Butcher gates R4→R5")
	t.ok(Commission.purse_for(Commission.fight(Commission.SAMMY))
			.equals_approx(BigMoney.of(5.0, 5), 1e-6), "Sammy's purse is $500K")
	t.ok(Commission.purse_for(Commission.fight(Commission.BUTCHER))
			.equals_approx(BigMoney.of(5.0, 6), 1e-6), "the Butcher's purse is $5M")
	for f in Commission.FIGHTS:
		var gated := int(f["gates"])
		t.ok(gated + 1 < Game.RANK_RESPECT.size(), "%s gates a rank the ladder has" % f["id"])
		for id in SimProfile.ORDER:
			var p := SimProfile.get_profile(id)
			t.ok(p != null and p.boss_win.has(String(f["id"])),
					"%s has a win rate for %s" % [id, f["id"]])
	# The gate itself: respect alone must not promote past a fight that has not been won.
	var gate := Commission.new()
	t.eq(gate.rank_cap(3, 5), 3, "an unbeaten Sammy caps the ladder at R3")
	gate.mark_beaten(Commission.SAMMY)
	t.eq(gate.rank_cap(3, 5), 4, "beating Sammy opens exactly one rank")
	gate.mark_beaten(Commission.BUTCHER)
	t.eq(gate.rank_cap(3, 5), 5, "both fights won lets the ☆ through")

	# --- specialist vocabulary the sim reads (game/meta/stats.gd) ---
	for kind in [&"casino_edge_add", &"casino_pocket_add", &"auto_launder_per_sec",
			&"auto_collect_interval", &"serve_speed_mult", &"kickback_cooldown_mult",
			&"heat_decay_mult", &"all_dirty_mult", &"job_respect_mult"]:
		t.ok(Stats.FOLD.has(kind), "Stats still folds `%s`, which the sim reads" % kind)
	t.near(Stats.CASINO_EDGE_MAX, 0.20, 1e-9, "the edge cap is where the sim thinks it is")
	t.near(WireDraws.PERIOD, 90.0, 1e-9, "the tote board draws every 90 s")
	t.near(WireDraws.EXACT_MULT, 80.0, 1e-9, "an exact Wire number pays ×80")
	t.near(WireDraws.LAST_DIGIT_MULT, 6.0, 1e-9, "a last-digit Wire number pays ×6")

	# --- M3 geometry that already pays through TableScore (specs/m3-fall-rise.md TABLE-3) ---
	t.near(SimTable.SMUGGLING_CRATE, TableScore.SMUGGLING_CONTAINER, 1e-9,
			"a crate pays what the table says")
	t.near(SimTable.PENTHOUSE_CHAIR, TableScore.PENTHOUSE_CHAIR, 1e-9,
			"a chair pays what the table says")
	t.eq(SimTable.CRATE_STACKS, ContainerStacks.STACKS, "three stacks on the quay")
	t.eq(SimTable.CRATES_PER_STACK, ContainerStacks.PER_STACK, "two crates a stack")
	t.near(SimTable.CRATE_RESET_SEC, ContainerStacks.new().reset_seconds, 1e-9,
			"a stack comes back up on the quay's own clock")
	t.eq(SimTable.PENTHOUSE_CHAIRS,
			Penthouse.CHAIR_ROW_A_X.size() + Penthouse.CHAIR_ROW_B_X.size(),
			"five chairs at the long table")


func _profiles_load(t: TestCtx) -> void:
	var all := SimProfile.load_all()
	t.eq(all.size(), 3, "three skill profiles ship")
	for id in SimProfile.ORDER:
		var p: SimProfile = all.get(id, null)
		t.ok(p != null, "profile %s loads" % id)
		if p == null:
			continue
		t.ok(p.errors.is_empty(), "profile %s parses clean: %s" % [id, ", ".join(p.errors)])
		t.ok(p.switches_per_sec > 0.0, "%s closes switches" % id)
		t.ok(p.ball_seconds_mean > 0.0, "%s keeps the ball alive for a while" % id)
	var duffer: SimProfile = all["duffer"]
	var shark: SimProfile = all["shark"]
	t.ok(shark.ball_seconds_mean > duffer.ball_seconds_mean, "a shark holds a ball longer than a duffer")
	t.ok(shark.target_discipline > duffer.target_discipline, "a shark aims better than a duffer")


func _career(t: TestCtx) -> void:
	var c := SimCareer.run(PROFILE, SEED, DAYS)
	t.eq(c.rows.size(), DAYS, "one report row per simulated day")
	t.ok(c.nights_played > 0, "the career actually played Nights")
	t.ok(c.state.night_no == c.nights_played, "Night counter agrees with the career")
	t.ok(c.state.total_dirty.is_positive(), "a bare alley still earns dirty cash")
	t.ok(c.state.total_clean_earned.is_positive(), "pocket money washes some of it clean")
	t.ok(c.state.wallet.clean.cmp(c.state.total_clean_earned) <= 0,
			"clean held never exceeds clean earned")
	t.ok(c.median_night_seconds() > 0.0, "Nights take time")
	t.ok(c.active_seconds > 0.0, "and that time is play time")
	t.ok(c.state.peak_heat >= 0.0, "heat stays finite")

	# Purchases: every one legal, paid for, and inside the catalog.
	var catalog := Upgrades.shared()
	var spent := BigMoney.zero()
	for p in c.state.purchases:
		var id := String(p["id"])
		t.ok(catalog.has_id(id), "bought a node that exists: %s" % id)
		t.ok(int(p["level"]) <= catalog.max_level(id), "%s never passes its max level" % id)
		t.ok(int(p["rank"]) >= int(catalog.def(id)["tier"]), "%s was rank-legal when bought" % id)
		spent = spent.add(p["cost"])
	t.ok(spent.equals_approx(c.state.total_spent, 1e-6), "the purchase log adds up to what was spent")
	# Clean earned = clean held + clean spent (nothing else moves clean in M1).
	t.ok(c.state.total_clean_earned.sub_clamped(spent).equals_approx(c.state.wallet.clean, 1e-6),
			"clean cash is conserved: earned − spent == held")


func _determinism(t: TestCtx) -> void:
	var a := SimCareer.run(PROFILE, SEED, DAYS)
	var b := SimCareer.run(PROFILE, SEED, DAYS)
	t.eq(a.nights_played, b.nights_played, "same seed, same Night count")
	t.eq(a.shots_fired, b.shots_fired, "same seed, same shots")
	t.eq(a.state.respect, b.state.respect, "same seed, same Respect")
	t.ok(a.state.total_dirty.equals_approx(b.state.total_dirty, 1e-12), "same seed, same dirty")
	t.eq(Array(a.owned_ids()), Array(b.owned_ids()), "same seed, same build")
	var other := SimCareer.run(PROFILE, SEED + 1, DAYS)
	t.ok(other.state.total_dirty.cmp(a.state.total_dirty) != 0
			or other.shots_fired != a.shots_fired, "a different seed plays a different career")


## The sim's money path against the real one, on the same inputs. This is the assertion that
## catches `Game.earn_switch` changing shape without `SimState` following it.
func _money_path_matches_game(t: TestCtx) -> void:
	var owned := {"rackets.trash_2": 1, "rackets.can_deposits": 2, "muscle.brass_balls": 1}
	var catalog := Upgrades.shared()

	var sim := SimState.new(1, catalog)
	sim.owned = owned.duplicate()
	sim.stats.recompute(sim.owned)
	var mine := sim.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))

	var real_save := Game.save
	Game.save = SaveGame.new("user://test_sim_smoke.json")
	Game.save.erase()
	Game.new_game(1)
	Game.owned = owned.duplicate()
	Game.stats.recompute(Game.owned)
	Game.combo.reset()
	Game.heat.reset()
	var theirs := Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	t.ok(mine.equals_approx(theirs, 1e-9),
			"SimState.earn_switch pays what Game.earn_switch pays (%s vs %s)" % [mine.text(), theirs.text()])
	t.ok(sim.wallet.dirty.equals_approx(Game.wallet.dirty, 1e-9), "…and the wallets agree")
	t.near(sim.heat.pending_units(), Game.heat.pending_units(), 1e-9, "…and the heat windows agree")

	# The BASE line the Wire prices its ticket off (balance-sim ruling). Both sides book it in
	# the same place as the multiplied one, and neither may book the post-multiplier amount.
	t.ok(sim.night_group_base_dirty(&"bumpers").equals_approx(
			Game.night_group_base_dirty(&"bumpers"), 1e-9),
			"SimState books the same base line Game does (%s vs %s)"
			% [sim.night_group_base_dirty(&"bumpers").text(),
				Game.night_group_base_dirty(&"bumpers").text()])
	t.ok(sim.night_group_base_dirty(&"bumpers").equals_approx(
			Game.ledger_value(&"bumpers", BigMoney.from_float(TableScore.BUMPER)), 1e-9),
			"…and the base line is the Ledger's value, before Heat, mode and combo")

	# Flat money: the wheel and the tote board already priced it, so both sides pay it at face
	# value — hot money, never a chain, never multiplied again.
	var flat_before := Game.heat.pending_units()
	var chain_before := Game.combo.count
	var flat_mine := sim.earn_flat_dirty(BigMoney.from_float(1_000.0), &"casino")
	var flat_theirs := Game.earn_flat_dirty(BigMoney.from_float(1_000.0), &"casino")
	t.ok(flat_mine.equals_approx(flat_theirs, 1e-9), "SimState.earn_flat_dirty pays what Game does")
	t.ok(flat_theirs.equals_approx(BigMoney.from_float(1_000.0), 1e-9),
			"…which is face value, whatever the Heat band and the Ledger say")
	t.ok(Game.heat.pending_units() > flat_before, "…and it is still hot money")
	t.eq(Game.combo.count, chain_before, "…and still not a shot: it cannot touch a chain")

	# M2: the same comparison with the mode multiplier live — a Loud guy on the table and a
	# Family Meeting running. `Game.preview_switch` folds both; so must the sim's copy.
	var loud := {"id": 7, "name": "Loud Guy", "trait": GuyTraits.LOUD}
	sim.set_fielded([loud])
	Game.set_fielded([loud])
	sim.meeting.active = true
	Game.meeting.active = true
	t.near(sim.mode_multiplier(), Game.mode_multiplier(), 1e-9,
			"SimState.mode_multiplier is Game.mode_multiplier (Meeting ×2 × traits)")
	sim.combo.reset()
	Game.combo.reset()
	var mine_hot := sim.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	var their_hot := Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	t.ok(mine_hot.equals_approx(their_hot, 1e-9),
			"…and the doubled, Loud payout matches too (%s vs %s)"
			% [mine_hot.text(), their_hot.text()])
	t.near(sim.heat.gain_scale, Game.heat.gain_scale, 1e-9,
			"…and both meters took the same trait scale")
	sim.meeting.active = false
	Game.meeting.active = false
	sim.set_fielded([])
	Game.set_fielded([])

	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)
