extends RefCounted
## THE COMMISSION's rules (game/flow/bosses/commission.gd, specs/m2-content.md §5): who is
## waiting, which rungs of the ladder are locked behind a fight, what a win is worth and what
## the save file has to remember. Pure logic — the fights themselves are physical and live in
## tests/sim/boss_sim.tscn.

const SAVE_PATH := "user://test_flow_bosses.json"


func run(t: TestCtx) -> void:
	_ladder(t)
	_waiting(t)
	_rank_cap(t)
	_serialization(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_session_gate(t)
	_spoils(t)
	_armored_money(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the ladder ---------------------------------------------------------------


func _ladder(t: TestCtx) -> void:
	t.eq(Commission.FIGHTS.size(), 2, "M2 ships two Commission fights")
	t.eq(StringName(Commission.fight(Commission.SAMMY).get("id", "")), Commission.SAMMY,
			"Sammy is in the book")
	t.ok(Commission.fight(&"nobody").is_empty(), "and a stranger is not")
	t.eq(int(Commission.fight_gating(3).get("gates", -1)), 3, "Sammy stands between R3 and R4")
	t.eq(int(Commission.fight_gating(4).get("gates", -1)), 4, "the Butcher between R4 and R5")
	for rank: int in [0, 1, 2, 5, 6, 7]:
		t.ok(Commission.fight_gating(rank).is_empty(),
				"R%d is not gated by anybody in M2" % rank)

	# The purses are the fixed clean ones from the spec: $500K and $5M.
	t.ok(Commission.purse_for(Commission.fight(Commission.SAMMY))
			.equals_approx(BigMoney.of(5.0, 5), 1e-9), "Sammy's purse is $500K")
	t.ok(Commission.purse_for(Commission.fight(Commission.BUTCHER))
			.equals_approx(BigMoney.of(5.0, 6), 1e-9), "the Butcher's is $5M")
	t.ok(not Commission.purse_for({}).is_positive(), "and nobody pays nothing")
	# Both spoils are `spoil.`-prefixed pseudo-ids, never Ledger nodes.
	for f: Dictionary in Commission.FIGHTS:
		var spoil := String(f["spoil"])
		t.ok(spoil.begins_with(Commission.SPOIL_PREFIX), "%s files its spoil as a spoil" % spoil)
		t.ok(not Upgrades.shared().has_id(spoil), "%s is not for sale in the Ledger" % spoil)


func _waiting(t: TestCtx) -> void:
	var c := Commission.new()
	var ladder := Game.RANK_RESPECT
	t.ok(c.waiting(2, 10_000, ladder).is_empty(), "an ungated rank never has anybody waiting")
	t.ok(c.waiting(3, ladder[4] - 1, ladder).is_empty(), "one star short is no invitation")
	t.eq(StringName(c.waiting(3, ladder[4], ladder).get("id", "")), Commission.SAMMY,
			"the R4 stars bring Sammy to the door")
	c.mark_beaten(Commission.SAMMY)
	t.ok(c.waiting(3, ladder[4], ladder).is_empty(), "a beaten boss does not come back")
	t.eq(StringName(c.waiting(4, ladder[5], ladder).get("id", "")), Commission.BUTCHER,
			"the next rank has its own man")
	t.eq(c.attempts_at(Commission.SAMMY), 0, "the book opens empty")
	c.pending = Commission.BUTCHER
	c.begin_fight(Commission.BUTCHER)
	t.eq(c.attempts_at(Commission.BUTCHER), 1, "a Night spent on him is booked")
	t.eq(String(c.pending), "", "and the pending fight is consumed by starting it")


func _rank_cap(t: TestCtx) -> void:
	var c := Commission.new()
	t.eq(c.rank_cap(0, 3), 3, "every rung below R3 promotes on the stars alone")
	t.eq(c.rank_cap(2, 7), 3, "and the ladder stops dead at Sammy")
	t.eq(c.rank_cap(3, 4), 3, "R3 cannot buy its way to R4")
	c.mark_beaten(Commission.SAMMY)
	t.eq(c.rank_cap(3, 4), 4, "beating him opens exactly one rung")
	t.eq(c.rank_cap(3, 7), 4, "not the whole ladder")
	c.mark_beaten(Commission.BUTCHER)
	t.eq(c.rank_cap(3, 7), 7, "with both down the stars are the only gate again")
	t.eq(c.rank_cap(5, 3), 5, "a cap never demotes anybody")


func _serialization(t: TestCtx) -> void:
	var c := Commission.new()
	c.mark_beaten(Commission.SAMMY)
	c.begin_fight(Commission.BUTCHER)
	c.pending = Commission.BUTCHER
	var d := c.to_dict()
	var back := Commission.new()
	back.from_dict(d)
	t.ok(back.is_beaten(Commission.SAMMY), "a beaten boss stays beaten across a save")
	t.ok(not back.is_beaten(Commission.BUTCHER), "and an unbeaten one stays unbeaten")
	t.eq(back.attempts_at(Commission.BUTCHER), 1, "the attempt count survives")
	t.eq(String(back.pending), "",
			"a fight that was pending when the app died is offered again, not auto-started")
	var empty := Commission.new()
	empty.from_dict({})
	t.ok(not empty.is_beaten(Commission.SAMMY), "an empty save is a career with everything to do")


# --- the session side ---------------------------------------------------------


## The rank ladder in `Game` reads the same gate, and `boss_waiting()` is the Count's button.
func _session_gate(t: TestCtx) -> void:
	Game.new_game(4242)
	Game.add_respect(Game.RANK_RESPECT[4], &"test")
	t.eq(Game.rank_for_respect(Game.respect), 4, "the stars are worth R4")
	t.eq(Game.rank, 3, "but the Commission holds the career at R3")
	t.eq(StringName(Game.boss_waiting().get("id", "")), Commission.SAMMY,
			"and Sammy is on the Count's button")
	t.ok(not Game.economy_paused(), "no fight is running, so the economy is not paused")

	# The fight is the ceremony: with him down the promotion the stars bought finally lands.
	var result := Game.boss_finished(Commission.SAMMY, true)
	t.eq(Game.rank, 4, "beating him promotes the career")
	t.ok(bool(result["won"]), "and the result says so")
	t.ok((result["purse"] as BigMoney).is_positive(), "the purse was paid")
	t.ok(Game.has_spoil(Commission.SPOIL_SAMMY), "the spoil was taken")
	t.ok(Game.boss_waiting().is_empty(), "and nobody is waiting any more")

	# A loss costs nothing but the Night.
	Game.add_respect(Game.RANK_RESPECT[5] - Game.respect, &"test")
	t.eq(Game.rank, 4, "the Butcher holds the next rung")
	var lost := Game.boss_finished(Commission.BUTCHER, false)
	t.ok(not bool(lost["won"]), "a loss is a loss")
	t.ok(not (lost["purse"] as BigMoney).is_positive(), "and pays nothing")
	t.eq(Game.rank, 4, "and promotes nobody")
	t.eq(StringName(Game.boss_waiting().get("id", "")), Commission.BUTCHER,
			"the rematch is back on the button")


func _spoils(t: TestCtx) -> void:
	Game.new_game(77)
	t.ok(not Game.has_spoil(Commission.SPOIL_BUTCHER), "a new career owns no spoils")
	t.eq(Game.spoils().size(), 0, "and lists none")
	Game.grant_spoil(Commission.SPOIL_BUTCHER)
	t.ok(Game.has_spoil(Commission.SPOIL_BUTCHER), "a granted spoil is owned")
	t.eq(Game.spoils().size(), 1, "and listed")
	Game.grant_spoil(Commission.SPOIL_BUTCHER)
	t.eq(int(Game.owned.get(Commission.SPOIL_BUTCHER, 0)), 1, "granting twice is not level 2")
	# It rides in `owned` and Stats simply does not know the id — which is the whole trick.
	t.ok(Game.to_dict().get("owned", {}).has(Commission.SPOIL_BUTCHER),
			"the save carries the spoil")
	Game.stats.recompute(Game.owned)
	t.eq(Game.stats.idle_rate_total().approx_float(), 0.0,
			"a spoil pseudo-node contributes no Ledger effects")


## Armored hardware pays nothing, and with Cold Storage owned it banks half of what it refused
## until the armor comes off (specs/m2-content.md §5).
func _armored_money(t: TestCtx) -> void:
	Game.new_game(99)
	Game.heat.reset()
	var can := BigMoney.from_float(TableScore.BUMPER)
	var live := Game.earn_switch(&"bumpers", can, {"no_combo": true})
	t.ok(live.is_positive(), "an un-armored can pays")

	Game.set_group_armored(&"bumpers", true)
	t.ok(Game.is_group_armored(&"bumpers"), "the armor is on")
	var denied := Game.earn_switch(&"bumpers", can, {"no_combo": true})
	t.ok(not denied.is_positive(), "an armored can pays nothing")
	t.ok(not Game.armored_bank(&"bumpers").is_positive(),
			"and banks nothing without the Butcher's spoil")
	Game.set_group_armored(&"bumpers", false)

	Game.grant_spoil(Commission.SPOIL_BUTCHER)
	Game.set_group_armored(&"bumpers", true)
	var want := Game.preview_switch(&"bumpers", can).mul(Game.COLD_STORAGE_FRACTION)
	Game.earn_switch(&"bumpers", can, {"no_combo": true})
	t.ok(Game.armored_bank(&"bumpers").equals_approx(want, 1e-9),
			"Cold Storage banks half of a denied can")
	var owed := Game.armored_bank(&"bumpers")
	var clean_before := Game.wallet.clean
	Game.set_group_armored(&"bumpers", false)
	t.ok(Game.wallet.clean.sub_clamped(clean_before).equals_approx(owed, 1e-9),
			"and pays it out clean when the armor comes off")
	t.ok(not Game.armored_bank(&"bumpers").is_positive(), "leaving nothing in the freezer")
