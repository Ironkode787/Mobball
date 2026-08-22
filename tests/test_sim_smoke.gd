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
	# The `--flat-skill` experiment switch is process-wide; pin it so this file tests the
	# shipped behaviour no matter what ran before it.
	SimState.skill_shot_scales_with_rank = true
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

	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)
