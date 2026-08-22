extends RefCounted
## The Club's book (game/flow/casino.gd): the odds, the stakes, the Cooler, the High Roller
## ladder, the Jackpot's deck visit — and the one rule that decides which pile a casino
## payout lands in (specs/m2-content.md §1/§3).

const SAVE_PATH := "user://test_flow_casino.json"


func run(t: TestCtx) -> void:
	_odds(t)
	_stakes(t)
	_cooler(t)
	_high_roller(t)
	_jackpot(t)
	_book(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_wash_gating(t)
	_heat_and_jackpot(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the honest edge ----------------------------------------------------------


func _odds(t: TestCtx) -> void:
	t.eq(Casino.CasinoRules.POCKETS, RouletteWheel.POCKETS,
			"the book and the wheel agree on how many pockets there are")
	t.eq(Casino.CasinoRules.POCKETS - Casino.CasinoRules.PLAYER_POCKETS,
			RouletteWheel.HOUSE_POCKETS.size(), "and on how many belong to the house")

	# A bare table: no Stats at all is the same as no edge bought.
	t.near(Casino.payout_rate(null), Casino.CasinoRules.PAYOUT, 1e-9, "base payout is 1.48x")
	t.eq(Casino.player_pockets(null), 5, "five of eight pockets pay")
	t.near(Casino.expected_value(null), -0.075, 1e-9,
			"5/8 x 1.48 - 1 is a 7.5% house edge")
	t.ok(not Casino.wash_active(null), "no Stats means no Casino Wash")
	t.near(Casino.cooler_bonus(null), Casino.CasinoRules.COOLER_BONUS, 1e-9,
			"and the plain Cooler apology")

	# The knobs move the EV honestly and cannot be pushed past their ceiling.
	var maxed := _EdgeStats.new(1.0, 6)
	t.near(Casino.payout_rate(maxed), Casino.CasinoRules.PAYOUT_MAX, 1e-9,
			"a huge edge stops at the design ceiling")
	t.near(Casino.expected_value(maxed), 6.0 / 8.0 * 1.55 - 1.0, 1e-9,
			"six pockets at 1.55x is the positive-EV laundry")
	t.ok(Casino.expected_value(maxed) > 0.0, "which is the only positive-EV laundry there is")

	# The cross-lane contract with META-2: the edge getter is a live read, not a permanent
	# fallback, and the meta lane's ceiling can actually reach the payout the design tops out
	# at (specs/m2-content.md §1: Loaded Dice nudges PAYOUT toward 1.55).
	var live := Stats.new()
	live.recompute({})
	t.ok(live.has_method("casino_edge_add"), "Stats carries the casino edge getter")
	t.near(Casino.payout_rate(live), Casino.CasinoRules.PAYOUT, 1e-9,
			"with no Influence bought the wheel pays its base 1.48x")
	t.near(Casino.expected_value(live), -0.075, 1e-9, "at the honest -7.5% edge")
	t.ok(Casino.CasinoRules.PAYOUT + Stats.CASINO_EDGE_MAX >= Casino.CasinoRules.PAYOUT_MAX,
			"the meta lane's edge ceiling (%.3f) cannot reach the design payout ceiling"
			% Stats.CASINO_EDGE_MAX)
	t.eq(Casino.player_pockets(live), Casino.CasinoRules.PLAYER_POCKETS,
			"and with no pocket-count effect in the vocabulary yet, the wheel is as built")


func _stakes(t: TestCtx) -> void:
	var pocket_change := BigMoney.from_float(10_000.0)
	t.ok(Casino.stake_for(pocket_change, 0).equals_approx(BigMoney.from_float(500.0), 1e-9),
			"table stakes are 5% of held dirty")
	t.ok(Casino.stake_for(BigMoney.of(1.0, 9), 0).equals_approx(Casino.stake_cap(0), 1e-9),
			"a fat wallet is capped")
	t.ok(not Casino.stake_for(BigMoney.zero(), 4).is_positive(),
			"an empty wallet cannot bet")
	t.ok(Casino.stake_cap(4).cmp(Casino.stake_cap(0)) > 0, "the cap climbs with rank")
	t.ok(Casino.stake_cap(4).equals_approx(
			Casino.stake_cap(0).mul(pow(Casino.CasinoRules.STAKE_CAP_PER_RANK, 4.0)), 1e-9),
			"by the same x3.5 per rank the rest of the economy grows at")

	var c := Casino.new()
	var no_bet := c.resolve(1, false, BigMoney.zero(), 1.48, false)
	t.ok(not bool(no_bet["bet"]), "no stake, no bet")
	t.eq(c.night_spins, 0, "and no spin on the book")
	t.eq(c.loss_streak, 0, "a landing you could not bet on is not a loss")


# --- the Cooler ---------------------------------------------------------------


func _cooler(t: TestCtx) -> void:
	var c := Casino.new()
	var stake := BigMoney.from_float(100.0)
	for i in Casino.CasinoRules.COOLER_STREAK:
		var lost := c.resolve(0, true, stake, 1.48, false)
		t.ok(not (lost["won"] as BigMoney).is_positive(), "a house pocket pays nothing")
		t.eq(int(lost["streak"]), i + 1, "and lengthens the streak")
	t.eq(c.night_wins, 0, "five straight losses")

	var win := c.resolve(1, false, stake, 1.48, false)
	t.ok(bool(win["cooler"]), "the fifth loss fires the Cooler")
	t.near(float(win["multiplier"]), 1.48 * 1.5, 1e-9, "and the next win pays +50%")
	t.eq(c.loss_streak, 0, "a win clears the streak")

	var plain := c.resolve(1, false, stake, 1.48, false)
	t.ok(not bool(plain["cooler"]), "the apology is not repeated")
	t.near(float(plain["multiplier"]), 1.48, 1e-9, "the next win is priced normally")

	# The upgradeable version doubles it (specs/m2-content.md §1).
	var c2 := Casino.new()
	for i in Casino.CasinoRules.COOLER_STREAK:
		c2.resolve(0, true, stake, 1.48, false)
	var fired := c2.resolve(1, false, stake, 1.48, false, Casino.CasinoRules.COOLER_BONUS_FIRED)
	t.near(float(fired["multiplier"]), 1.48 * 2.0, 1e-9, "coolers_fired makes it +100%")


func _high_roller(t: TestCtx) -> void:
	var c := Casino.new()
	var stake := BigMoney.from_float(100.0)
	t.near(c.arm(0), 0.0, 1e-9, "a saucer nobody held costs no Heat")
	t.near(c.armed_multiplier(), 1.0, 1e-9, "and arms nothing")

	t.near(c.arm(1), Casino.CasinoRules.HIGH_ROLLER_HEAT[1], 1e-9, "one rung is +3 Heat")
	t.near(c.armed_multiplier(), 2.0, 1e-9, "and arms x2")
	t.near(c.arm(3), Casino.CasinoRules.HIGH_ROLLER_HEAT[3], 1e-9, "the top rung is +12 Heat")
	t.near(c.armed_multiplier(), 5.0, 1e-9, "and arms x5")
	t.near(c.arm(99), Casino.CasinoRules.HIGH_ROLLER_HEAT[3], 1e-9,
			"a longer ladder than the book knows clamps rather than crashes")

	c.resolve(0, true, stake, 1.48, false)
	t.near(c.armed_multiplier(), 5.0, 1e-9, "a losing pocket does not burn the ladder")
	var win := c.resolve(1, false, stake, 1.48, false)
	t.near(float(win["multiplier"]), 1.48 * 5.0, 1e-9, "the win rides the ladder")
	t.near(c.armed_multiplier(), 1.0, 1e-9, "which is spent on that one payout")


# --- the slots ----------------------------------------------------------------


func _jackpot(t: TestCtx) -> void:
	var c := Casino.new()
	t.ok(not c.on_reels([0, 1, 2]), "clearing the reels off a deck visit pays nothing")

	c.open_visit()
	t.ok(c.visit_open(), "a completed climb opens the visit")
	t.ok(not c.on_reels([0]), "one column is not a Jackpot")
	t.ok(not c.on_reels([1]), "two is not either")
	t.eq(c.visit_columns(), 2, "the visit remembers columns across reel resets")
	t.ok(c.on_reels([2]), "the third column inside the same visit is the Jackpot")
	t.eq(c.night_jackpots, 1, "booked once")
	t.ok(not c.on_reels([0, 1, 2]), "and only once per visit")

	c.close_visit()
	t.ok(not c.visit_open(), "coming back downstairs closes the visit")
	c.open_visit()
	t.ok(not c.on_reels([0, 1]), "the next visit starts from nothing")
	t.ok(c.on_reels([2]), "and can be earned again")
	t.eq(c.night_jackpots, 2, "two Jackpots tonight")

	var rate := BigMoney.from_float(500.0)
	t.ok(Casino.jackpot_value(rate).equals_approx(
			rate.mul(Casino.CasinoRules.JACKPOT_MINUTES * 60.0), 1e-9),
			"a Jackpot is eight minutes of the whole empire's idle rate")
	t.ok(not Casino.jackpot_value(BigMoney.zero()).is_positive(),
			"an empire that earns nothing has nothing to pay out")


func _book(t: TestCtx) -> void:
	var c := Casino.new()
	c.resolve(1, false, BigMoney.from_float(100.0), 1.48, true)
	c.book_payout(BigMoney.from_float(148.0), true)
	t.ok(c.night_won.equals_approx(BigMoney.from_float(148.0), 1e-9),
			"the book records what landed, not what was promised")
	t.ok(c.night_washed.equals_approx(BigMoney.from_float(148.0), 1e-9), "clean is washed")
	t.ok(c.night_net().equals_approx(BigMoney.from_float(48.0), 1e-9), "net is won minus staked")

	var round_trip := Casino.new()
	round_trip.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	t.eq(JSON.stringify(round_trip.to_dict()), JSON.stringify(c.to_dict()),
			"the career book survives the save file")
	t.eq(round_trip.night_spins, 0, "loading starts a fresh Night's book")
	var losing := Casino.new()
	for i in 3:
		losing.resolve(0, true, BigMoney.from_float(10.0), 1.48, false)
	var reloaded := Casino.new()
	reloaded.from_dict(losing.to_dict())
	t.eq(reloaded.loss_streak, 3, "the Cooler owes you across a save")


# --- the wash -----------------------------------------------------------------


## The whole point of `fronts.casino_wash`: until it is bought the house pays you back in the
## same dirty money you handed it.
func _wash_gating(t: TestCtx) -> void:
	_fresh_club()
	Game.wallet.earn_dirty(BigMoney.from_float(100_000.0))
	var clean_before := Game.wallet.clean
	var dirty_before := Game.wallet.dirty
	Game.heat.reset()

	t.ok(not Game.stats.flag(&"casino_wash"), "the Wash is not bought yet")
	var dirty_win := Game.casino_roulette(1, false)
	t.ok(bool(dirty_win["bet"]), "the wheel took a bet")
	t.ok(not bool(dirty_win["clean"]), "and paid dirty")
	t.ok(Game.wallet.clean.equals_approx(clean_before, 1e-9),
			"no clean cash appears without the Wash")
	t.ok(Game.wallet.dirty.cmp(dirty_before) > 0, "the win landed in the dirty pile")
	t.near(Game.heat.pending_units(), 0.0, 1e-9,
			"casino money is the wash, not hot money: the Heat window never sees it")
	t.eq(Game.combo.count, 0, "and a bet is not a shot: no chain")

	Game.buy_upgrade("fronts.casino_wash", BigMoney.zero())
	t.ok(Game.stats.flag(&"casino_wash"), "the Wash is bought")
	clean_before = Game.wallet.clean
	var clean_win := Game.casino_roulette(1, false)
	t.ok(bool(clean_win["clean"]), "now the house launders for you")
	t.ok(Game.wallet.clean.cmp(clean_before) > 0, "the win landed in the clean pile")
	t.ok((clean_win["paid"] as BigMoney).is_positive(), "and the result says what was paid")
	t.ok(Game.casino.night_washed.is_positive(), "the Count's washed line has something on it")

	# A house pocket takes the stake and nothing else moves.
	var dirty_at_loss := Game.wallet.dirty
	var clean_at_loss := Game.wallet.clean
	var lost := Game.casino_roulette(0, true)
	t.ok(not (lost["won"] as BigMoney).is_positive(), "a house pocket pays nothing")
	t.ok(Game.wallet.clean.equals_approx(clean_at_loss, 1e-9), "and never touches clean")
	t.ok(Game.wallet.dirty.equals_approx(
			dirty_at_loss.sub_clamped(lost["staked"] as BigMoney), 1e-6),
			"the stake is what it costs")


func _heat_and_jackpot(t: TestCtx) -> void:
	_fresh_club()
	Game.buy_upgrade("fronts.casino_wash", BigMoney.zero())
	Game.heat.reset()
	var heat_before := Game.heat.value
	Game.casino_high_roller(2)
	t.near(Game.heat.value - heat_before, Casino.CasinoRules.HIGH_ROLLER_HEAT[2], 1e-6,
			"greed on the saucer is paid for in Heat")

	# The armed ladder rides the very next payout, whichever it is.
	Game.wallet.earn_dirty(BigMoney.from_float(100_000.0))
	var armed := Game.casino_roulette(1, false)
	t.near(float(armed["multiplier"]), Casino.payout_rate(Game.stats) * 3.0, 1e-9,
			"a two-rung hold triples the next win")

	Game.casino.open_visit()
	var clean_before := Game.wallet.clean
	heat_before = Game.heat.value
	var paid := Game.casino_reels([0, 1, 2])
	t.ok(paid.is_positive(), "the Jackpot pays: %s" % paid.text())
	t.ok(Game.wallet.clean.equals_approx(clean_before.add(paid), 1e-6),
			"clean, always — the Jackpot is not a bet")
	t.near(Game.heat.value - heat_before, Casino.CasinoRules.JACKPOT_HEAT, 1e-6,
			"and it puts the deck on the map")
	t.eq(Game.meeting.jackpots_tonight, 1, "the back room counts it")
	t.ok(not Game.meeting.lit, "one Jackpot is not enough to light the Meeting")

	Game.casino.close_visit()
	Game.casino.open_visit()
	Game.casino_reels([0, 1, 2])
	t.ok(Game.meeting.lit, "two Jackpots in a Night light the back room")


# --- helpers ------------------------------------------------------------------


## A career with the Club built and nothing else bought.
func _fresh_club() -> void:
	Game.new_game(20260822)
	Game.buy_upgrade("rackets.club_license", BigMoney.zero())
	Game.heat.reset()
	Game.combo.reset()


## Stand-in for META-2's `Stats` getters, which do not exist yet. The casino reads both
## through `has_method`, so this is exactly the shape the real ones have to arrive in.
class _EdgeStats:
	extends RefCounted

	var _edge: float
	var _pockets: int

	func _init(edge: float, pockets: int) -> void:
		_edge = edge
		_pockets = pockets

	func casino_edge_add() -> float:
		return _edge

	func casino_player_pockets() -> int:
		return _pockets

	func flag(_id: StringName) -> bool:
		return false
