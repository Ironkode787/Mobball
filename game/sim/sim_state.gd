class_name SimState
extends RefCounted
## The session model, headless: everything `game/flow/game.gd` owns except the scene tree.
##
## This is the ONE file in the sim that mirrors flow code, and it mirrors it line for line —
## `earn_switch` below is `Game.earn_switch` with the `Events` emissions removed, in the same
## order, because the order is the economy (stats fold, then heat band, then combo, and the
## POST-multiplier amount is what feeds the heat window). The real Wallet, HeatMeter, Stats,
## Combo, Jobs, Bench, Rates and Upgrades objects do the actual work; nothing here
## re-implements economy math.
##
## DRIFT RISK, stated plainly: if `Game.earn_switch`, `Game.end_night`'s pocket-money wash,
## `Game.award_skill_shot` or `Game.RANK_RESPECT` change, this file must change with them.
## `tests/test_sim_smoke.gd` asserts the constants against the live `Game` autoload so at
## least the numbers cannot drift silently; the composition order cannot be asserted from
## outside, so it is spelled out above. The right long-term fix is extracting flow's money
## path into a pure `Session` object both can drive — proposed in the SIM report.

## Mirrors `Game.RANK_RESPECT` (docs/02 §1). Asserted equal in tests/test_sim_smoke.gd.
const RANK_RESPECT: PackedInt32Array = [0, 10, 50, 150, 400, 1000, 2500, 6000]
## Mirrors `Game.RESPECT_SKILL_SHOT` / `RESPECT_RAID_SURVIVED` / `RAID_CLEAN_PAYOUT`.
const RESPECT_SKILL_SHOT := 1
const RESPECT_RAID_SURVIVED := 25
const RAID_CLEAN_PAYOUT := 0.25
## Mirrors `Game.SKILL_SHOT_MANTISSA` / `SKILL_SHOT_EXP`.
const SKILL_SHOT_MANTISSA := 2.0
const SKILL_SHOT_EXP := 2

var wallet := Wallet.new()
var heat := HeatMeter.new()
var stats := Stats.new()
var combo := Combo.new()
var jobs := Jobs.new()
var bench: Bench = null
var catalog: Upgrades = null
## M2 modes (specs/m2-content.md). Real flow-lane objects, driven by the sim exactly the way
## `NightController` drives them: they own the rules, this file pays what they decide.
var casino := Casino.new()
var meeting := FamilyMeeting.new()
var wire := WireDraws.new()
var collection := CollectionRound.new()
var commission := Commission.new()
## The guys physically on the table — one normally, two during a Family Meeting. Their traits
## fold into every dirty payout and into the Heat meter's gain scale (`Game.set_fielded`).
var fielded: Array[Dictionary] = []

var respect: int = 0
var rank: int = 0
var night_no: int = 0
## Ledger node id -> owned level. The sim keeps its own map rather than touching the
## process-wide `LedgerState`, so a balance run cannot poison a live career or a test.
var owned: Dictionary = {}
var safe_pending: BigMoney = BigMoney.zero()

# Per-Night tallies, reset by start_night(), read by end_night() — same set as Game's.
var night_dirty: BigMoney = BigMoney.zero()
var night_idle: BigMoney = BigMoney.zero()
var night_laundered: BigMoney = BigMoney.zero()
## Clean paid straight out, never having been dirty (casino wins under the Wash, Jackpots,
## Meeting jackpots, exact Wire numbers, a boss purse). It does NOT eat the wash cap and it is
## not laundering — which is the whole reason the deck matters (`Game.earn_clean`).
var night_clean: BigMoney = BigMoney.zero()
## Dirty booked per value group tonight — the Wire prices its ticket off the spinner's line.
var night_group: Dictionary = {}
var night_insured: bool = false
var night_respect: int = 0
var night_skill_shots: int = 0
var night_best_combo: int = 0
var night_bribes: int = 0
var night_jobs: int = 0

# Career tallies the report reads.
var total_dirty: BigMoney = BigMoney.zero()
var total_clean_earned: BigMoney = BigMoney.zero()
var total_idle: BigMoney = BigMoney.zero()
var total_spent: BigMoney = BigMoney.zero()
## Clean that arrived as pocket money rather than through a wash — the R0 grace, and the
## report's evidence for how long it stays the only clean faucet.
var total_pocket: BigMoney = BigMoney.zero()
## Highest heat the career ever reached, and how many Nights spent the whole laundering cap.
var peak_heat: float = 0.0
## Seconds of live Night spent in each Heat band 0..4 — the honest answer to "is the risk
## system alive?", which peak heat alone cannot give (one spike is not a band).
var band_seconds: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
## Spinner half-turns since the career started: the Wire's ticket is the count since boot.
var spin_segments_total: int = 0
var capped_nights: int = 0
var capped_possible: int = 0
var total_respect_from: Dictionary = {}
## Career dirty per value group, taken off the money path itself — so a payout that never
## went through a shot (a Collection Round's double, a casino win with the Wash unbought) is
## in it, which is exactly the money a shot-level tally would lose.
var total_by_group: Dictionary = {}
var purchases: Array[Dictionary] = []
var rank_at: Dictionary = {}
var raids_survived: int = 0
var raids_lost: int = 0
## Confiscations `rain_insurance` refused to pay.
var raids_insured: int = 0
## Nights that OPENED with the Heat meter's raid latch already set — the meter crossed 100
## while nothing was listening for it (The Count ticks Heat too, `Game._process`), so the
## Inspector was called and never came. See the SIM report: this is a flow-lane bug, mirrored
## rather than papered over, and it is why a hot career can show zero raids.
var raids_latched: int = 0
## Clean that arrived through `earn_clean` rather than a wash — the deck's whole product.
var total_clean_direct: BigMoney = BigMoney.zero()
var clean_direct_from: Dictionary = {}
## The Club's book, career-wide (the casino keeps its own too; these are the sim's readouts).
var casino_spins: int = 0
var casino_wins: int = 0
var casino_staked: BigMoney = BigMoney.zero()
var casino_paid: BigMoney = BigMoney.zero()
var casino_clean: BigMoney = BigMoney.zero()
var casino_comped: int = 0
var casino_coolers: int = 0
## Sum of the payout multiple actually applied to a winning spin. Divided by `casino_wins` it
## is the average multiple, which is what separates the wheel's own edge (`payout_rate`) from
## everything the High Roller ladder and the Cooler add on top of it.
var casino_mult_sum: float = 0.0
var bribes_total: int = 0
var deck_visits: int = 0
var stair_attempts: int = 0
var jackpots: int = 0
var high_roller_holds: int = 0
var high_roller_heat: float = 0.0
var meetings: int = 0
var meeting_seconds: float = 0.0
var meeting_jackpots: int = 0
var meeting_paid: BigMoney = BigMoney.zero()
var collection_rounds: int = 0
var collection_wins: int = 0
var wire_draws: int = 0
var wire_hits: int = 0
var wire_exacts: int = 0
var wire_paid: BigMoney = BigMoney.zero()
## THE COMMISSION: Nights spent on fights, and what they cost/paid.
var boss_nights: int = 0
var boss_wins: int = 0
var boss_purse: BigMoney = BigMoney.zero()
var boss_first_night: Dictionary = {}
## Nights the ☆ said one rank and the Commission allowed a lower one (docs/05 §6).
var rank_gated_nights: int = 0
## Nights that opened with fewer than three fieldable guys — the only situation in which
## posting bail (docs/03 §8) would ever be worth a dollar.
var short_lineups: int = 0
var tilts: int = 0
var guys_pinched: int = 0

## Seconds of wall clock since the career started — the career sim owns this and the
## report reads it, so "time to R1" can be quoted in play time and in wall time.
var clock: float = 0.0
var play_clock: float = 0.0

## RETIRED EXPERIMENT (`tools/balance.sh --flat-skill`): the flat behavior WON and is now
## the real rule — Game.award_skill_shot pays a flat base (balance-sim ruling). The switch
## stays for A/B archaeology; default false mirrors production.
## Original note: `Game.award_skill_shot` multiplies
## its payout by `rank_scale(rank)/rank_scale(0)` — ×10 per rank — while every other switch
## on the table pays its R0 face value forever. Turning this off pins the skill shot at its
## R0 value so a run can show what the economy looks like without that one exception. It is
## a question for design, not a fix: the sim only measures both worlds.
static var skill_shot_scales_with_rank: bool = false

var _rng := RandomNumberGenerator.new()
var _seed: int = 0


func _init(seed_value: int = 0, from_catalog: Upgrades = null) -> void:
	catalog = from_catalog if from_catalog != null else Upgrades.shared()
	stats.catalog = catalog
	_rng.seed = seed_value
	_seed = seed_value
	_recompute_stats()
	bench = Bench.new(seed_value, stats.bench_slots())
	jobs.completed.connect(_on_job_completed)
	combo.respect_earned.connect(_on_combo_respect)
	combo.changed.connect(_on_combo_changed)


# =============================================================== money path =====


## `Game.earn_switch`, verbatim minus the Events emissions. Every dirty payout in the sim
## goes through here — including the idle-collect stubs' — exactly like the real table.
func earn_switch(group: StringName, base_value: BigMoney, meta: Dictionary = {}) -> BigMoney:
	var v := base_value.add(stats.value_add(group))
	v = v.mul(stats.value_mult(group))
	v = v.mul(heat.multiplier())
	v = v.mul(mode_multiplier())
	if not bool(meta.get("no_combo", false)):
		v = v.mul(combo.on_hit(group))
	wallet.earn_dirty(v)
	if not bool(meta.get("no_heat", false)):
		heat.on_dirty_earned(v, Rates.rank_scale(rank))
	night_dirty = night_dirty.add(v)
	_book_group(group, v)
	total_dirty = total_dirty.add(v)
	jobs.on_earn(v, group)
	return v


func _book_group(group: StringName, v: BigMoney) -> void:
	var night_total: Variant = night_group.get(group, null)
	night_group[group] = v if not (night_total is BigMoney) else (night_total as BigMoney).add(v)
	var career: Variant = total_by_group.get(group, null)
	total_by_group[group] = v if not (career is BigMoney) else (career as BigMoney).add(v)


## `Game.mode_multiplier`: the Family Meeting's ×2 while two guys are working, times the
## fielded guys' own traits (Loud, Fast). Multiplicative across guys, so during a Meeting both
## men's traits are live.
func mode_multiplier() -> float:
	return meeting.dirty_multiplier() * GuyTraits.dirty_mult_for(fielded)


## `Game.set_fielded`: who is on the table, and therefore whose traits scale the money path
## and the Heat meter's gains.
func set_fielded(guys: Array) -> void:
	fielded = []
	for g: Variant in guys:
		if g is Dictionary and not (g as Dictionary).is_empty():
			fielded.append(g as Dictionary)
	heat.gain_scale = GuyTraits.heat_scale_for(fielded)


## `Game.earn_clean`: money that was never dirty — casino wins under the Wash, the slots
## Jackpot, a Meeting jackpot, an exact Wire number, a boss purse. It does not move anything
## out of the dirty pile, so it does NOT eat the per-Night wash cap; it books its own line.
func earn_clean(amount: BigMoney, source: StringName = &"") -> BigMoney:
	if amount == null or not amount.is_positive():
		return BigMoney.zero()
	wallet.earn_clean(amount)
	night_clean = night_clean.add(amount)
	total_clean_earned = total_clean_earned.add(amount)
	total_clean_direct = total_clean_direct.add(amount)
	var acc: Variant = clean_direct_from.get(source, null)
	clean_direct_from[source] = amount if not (acc is BigMoney) else (acc as BigMoney).add(amount)
	jobs.on_launder(amount)
	return amount


func night_group_dirty(group: StringName) -> BigMoney:
	var v: Variant = night_group.get(group, null)
	return (v as BigMoney).copy() if v is BigMoney else BigMoney.zero()


## `count` identical hits of one group, paid in a single step with the combo multiplier
## pinned to ×1. Exactly equal to `count` `earn_switch` calls in that state, because every
## consumer downstream of the multiplier is linear in the amount: the wallet adds, the heat
## window adds `amount / rank_scale` units, `night_dirty` adds and `Jobs.on_earn` sums.
##
## Used for the spinner's decay tail: `Combo.on_hit` RESETS a chain when the group repeats,
## so segments 2..n of a spin each pay ×1 by construction (see SimNight._spin_advance).
func earn_repeat(group: StringName, base_value: BigMoney, count: int) -> BigMoney:
	if count <= 0:
		return BigMoney.zero()
	var unit := base_value.add(stats.value_add(group))
	unit = unit.mul(stats.value_mult(group))
	unit = unit.mul(heat.multiplier())
	unit = unit.mul(mode_multiplier())
	var total := unit.mul(float(count))
	if not total.is_positive():
		return BigMoney.zero()
	wallet.earn_dirty(total)
	heat.on_dirty_earned(total, Rates.rank_scale(rank))
	night_dirty = night_dirty.add(total)
	_book_group(group, total)
	total_dirty = total_dirty.add(total)
	jobs.on_earn(total, group)
	return total


## `Game.earn_idle`: real dirty, but not hot money — no heat, no combo.
func earn_idle(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	wallet.earn_dirty(amount)
	night_dirty = night_dirty.add(amount)
	night_idle = night_idle.add(amount)
	total_dirty = total_dirty.add(amount)
	total_idle = total_idle.add(amount)


func launder(fraction: float, cap: BigMoney = null) -> BigMoney:
	var moved := wallet.launder_fraction(fraction, cap)
	if moved.is_positive():
		night_laundered = night_laundered.add(moved)
		total_clean_earned = total_clean_earned.add(moved)
		jobs.on_launder(moved)
	return moved


func launder_cap_left() -> BigMoney:
	var cap := stats.launder_cap()
	if cap == null or not cap.is_positive():
		return BigMoney.zero()
	return cap.sub_clamped(night_laundered)


# ================================================================= the club =====
##
## `Game.casino_roulette` / `casino_reels` / `casino_high_roller` / `collection_completed` /
## the back-room jackpot, with the Events emissions and the audio removed. Every one of them
## delegates the RULES to the real `Casino` / `FamilyMeeting` / `CollectionRound` object and
## only owns the money, exactly as the flow lane does.


## One `roulette_landed`. Stakes 5% of held dirty (capped by rank), resolves it, pays it.
func casino_roulette(pocket: int, house: bool) -> Dictionary:
	var stake := Casino.stake_for(wallet.dirty, rank)
	var comped := casino.take_comp(stake)
	if stake.is_positive() and not comped and not wallet.spend_dirty(stake):
		stake = BigMoney.zero()
	var result := casino.resolve(pocket, house, stake, Casino.payout_rate(stats),
			Casino.wash_active(stats), Casino.cooler_bonus(stats), comped)
	if not bool(result["bet"]):
		return result
	casino_spins += 1
	if comped:
		casino_comped += 1
	if bool(result["cooler"]):
		casino_coolers += 1
	casino_staked = casino_staked.add(result["staked"])
	var paid := _pay_casino(result["won"], bool(result["clean"]), &"roulette_wheel")
	if paid.is_positive():
		casino_wins += 1
		casino_mult_sum += float(result["multiplier"])
		casino_paid = casino_paid.add(paid)
		if bool(result["clean"]):
			casino_clean = casino_clean.add(paid)
	result["paid"] = paid
	return result


## A `reels_state` report. Pays the JACKPOT when it completes all three columns inside one
## deck visit: eight minutes of the whole empire's idle rate, clean, plus flat Heat.
func casino_reels(cleared_columns: Array) -> BigMoney:
	if not casino.on_reels(cleared_columns):
		return BigMoney.zero()
	jackpots += 1
	var paid := _pay_casino(Casino.jackpot_value(stats.idle_rate_total()), true, &"slot_reels")
	heat.add_flat(Casino.CasinoRules.JACKPOT_HEAT)
	meeting.note_casino_jackpot()
	return paid


## A High Roller hold ended: arm the next payout, take the Heat the greed cost.
func casino_high_roller(steps: int) -> float:
	var added := casino.arm(steps)
	if added > 0.0:
		heat.add_flat(added)
		high_roller_holds += 1
		high_roller_heat += added
	return added


func _pay_casino(won: BigMoney, clean: bool, switch: StringName) -> BigMoney:
	if won == null or not won.is_positive():
		return BigMoney.zero()
	var paid := earn_clean(won, switch) if clean \
			else earn_switch(&"casino", won, {"no_heat": true, "no_combo": true})
	casino.book_payout(paid, clean)
	return paid


## The growing back-room re-entry during a Meeting (`FamilyMeeting.take_jackpot`), clean.
func meeting_jackpot() -> BigMoney:
	var pay := meeting.take_jackpot(stats.idle_rate_total())
	if not pay.is_positive():
		return BigMoney.zero()
	meeting_jackpots += 1
	meeting_paid = meeting_paid.add(pay)
	return earn_clean(pay, &"meeting")


## The third storefront of a Collection Round: the last one pays its value again, ☆10 lands,
## and the back room lights up (docs/05 §3).
func collection_completed(id: StringName, base_value: BigMoney) -> BigMoney:
	collection_wins += 1
	var bonus := BigMoney.zero()
	if base_value != null and base_value.is_positive():
		bonus = earn_switch(&"storefronts", base_value.mul(CollectionRound.LAST_PAYS_EXTRA),
				{"no_combo": true, "switch": id})
	add_respect(CollectionRound.RESPECT, &"collection")
	meeting.note_collection_round()
	return bonus


## One Wire draw (docs/05 §4). The ticket is the spinner's session count; the base is what the
## spinner has earned tonight, floored at $500. The exact number pays ×80 CLEAN.
func wire_draw(ticket: int) -> Dictionary:
	var result := wire.draw(ticket, night_group_dirty(&"spinner"))
	wire_draws += 1
	if String(result["hit"]) != String(WireDraws.HIT_NONE):
		wire_hits += 1
	if String(result["hit"]) == String(WireDraws.HIT_EXACT):
		wire_exacts += 1
	var won: BigMoney = result["won"]
	var paid := BigMoney.zero()
	if won.is_positive():
		if bool(result["clean"]):
			paid = earn_clean(won, &"wire")
		else:
			paid = earn_switch(&"wire", won, {"no_combo": true})
		wire.book_payout(paid)
		wire_paid = wire_paid.add(paid)
	result["paid"] = paid
	return result


# ============================================================ the Commission =====


## `Game.boss_waiting`: who is standing between this career and its next rank, or {}.
func boss_waiting() -> Dictionary:
	return commission.waiting(rank, respect, RANK_RESPECT)


## `Game.boss_finished` for a fight the sim has already decided. Victory is the whole rank-up
## ceremony: the purse (clean), the spoil, the ☆, and the promotion the Commission was holding.
func boss_finished(fight_id: StringName, victory: bool) -> Dictionary:
	var f := Commission.fight(fight_id)
	var result := {"id": String(fight_id), "won": victory, "purse": BigMoney.zero()}
	if not victory or f.is_empty():
		return result
	boss_wins += 1
	commission.mark_beaten(fight_id)
	var purse := earn_clean(Commission.purse_for(f), &"commission")
	boss_purse = boss_purse.add(purse)
	result["purse"] = purse
	grant_spoil(String(f.get("spoil", "")))
	add_respect(int(f.get("respect", 0)), &"boss")
	_check_rank()
	return result


## Spoils are taken, not bought: they ride in the same owned map as pseudo-ids, and
## `Stats.recompute` skips ids the catalog does not know (`Game.grant_spoil`).
func grant_spoil(id: String) -> void:
	if id.is_empty() or has_spoil(id):
		return
	owned[id] = 1
	_recompute_stats()


func has_spoil(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


# ============================================================ career ladder =====


func add_respect(stars: int, source: StringName = &"") -> void:
	if stars <= 0:
		return
	respect += stars
	night_respect += stars
	total_respect_from[source] = int(total_respect_from.get(source, 0)) + stars
	_check_rank()


func rank_for_respect(total: int) -> int:
	var r := 0
	for i in RANK_RESPECT.size():
		if total >= RANK_RESPECT[i]:
			r = i
	return r


## `Game._check_rank`: the ☆ say what rank you have earned; the Commission says what rank you
## are allowed to take (specs/m2-content.md §5). R3→R4 waits for Sammy, R4→R5 for the Butcher.
func _check_rank() -> void:
	var earned := rank_for_respect(respect)
	var want := commission.rank_cap(rank, earned)
	if want <= rank:
		return
	rank = want
	if not rank_at.has(rank):
		rank_at[rank] = {"clock": clock, "play": play_clock, "night": night_no}


## Is the ladder holding this career below the rank its ☆ have already bought?
func rank_is_gated() -> bool:
	return rank_for_respect(respect) > rank


# ================================================================= actions =====


## `Game.award_skill_shot`: hot money that must not open a chain, plus ☆1.
func award_skill_shot() -> BigMoney:
	night_skill_shots += 1
	var base := BigMoney.of(SKILL_SHOT_MANTISSA, SKILL_SHOT_EXP)
	if skill_shot_scales_with_rank:
		base = base.mul_big(Rates.rank_scale(rank).div_big(Rates.rank_scale(0)))
	var payout := earn_switch(&"skill_shot", base, {"no_combo": true})
	add_respect(RESPECT_SKILL_SHOT, &"skill_shot")
	return payout


## `Game.bribe`: −20 heat for an escalating dirty cost.
func bribe() -> bool:
	if not stats.bribe_unlocked():
		return false
	var cost := heat.bribe_cost(night_bribes)
	if not wallet.can_afford_dirty(cost) or not wallet.spend_dirty(cost):
		return false
	var heat_before := heat.value
	night_bribes += 1
	bribes_total += 1
	heat.bribe()
	jobs.on_bribe(heat_before)
	return true


## `Game.buy_upgrade` + the meta lane's level mint, without the LedgerState statics.
func buy_upgrade(id: String, cost: BigMoney) -> bool:
	if not wallet.spend_clean(cost):
		return false
	owned[id] = int(owned.get(id, 0)) + 1
	_recompute_stats()
	if bench != null:
		bench.slots = maxi(bench.slots, stats.bench_slots())
	total_spent = total_spent.add(cost)
	purchases.append({
		"id": id,
		"level": int(owned[id]),
		"cost": cost,
		"night": night_no,
		"clock": clock,
		"play": play_clock,
		"rank": rank,
	})
	return true


## `Game._accrue_safe` + `collect_safe`, with the wall clock passed in instead of read.
func accrue_and_collect_safe(elapsed_sec: float) -> BigMoney:
	var rate := stats.idle_rate_total()
	safe_pending = Offline.accrue(rate, elapsed_sec, Rates.safe_cap(rate, stats.safe_hours()))
	var got := safe_pending
	if got == null or not got.is_positive():
		return BigMoney.zero()
	wallet.earn_dirty(got)
	total_dirty = total_dirty.add(got)
	total_idle = total_idle.add(got)
	safe_pending = BigMoney.zero()
	return got


# ========================================================== state machine ======


## `Game.start_night`: tick the Bench, roll the Jobs, clear the per-Night tallies.
func start_night() -> void:
	night_no += 1
	if rank_is_gated():
		rank_gated_nights += 1
	if bench != null:
		# The rank goes in too: traits are only handed out once a career is worth naming a
		# crew for (`GuyTraits.MIN_RANK`), and the Bench needs to be told which rank it is.
		bench.night_tick(stats.bench_slots(), rank)
	jobs.roll(rank, stats, stats.job_slots(), _rng)
	jobs.begin_night()
	combo.reset_night()
	casino.begin_night(Casino.comps_for(stats))
	meeting.begin_night()
	collection.begin_night()
	wire.begin_night(_seed, night_no)
	set_fielded([])
	night_dirty = BigMoney.zero()
	night_idle = BigMoney.zero()
	night_laundered = BigMoney.zero()
	night_clean = BigMoney.zero()
	night_group = {}
	night_insured = false
	night_respect = 0
	night_skill_shots = 0
	night_best_combo = 0
	night_bribes = 0
	night_jobs = 0


## `Game.end_night`: the pocket-money wash, then the summary The Count would render.
func end_night(summary: Dictionary = {}) -> Dictionary:
	var pocket := launder(1.0, BigMoney.min_of(stats.pocket_money(), night_dirty))
	total_pocket = total_pocket.add(pocket)
	var cap := stats.launder_cap()
	if cap.is_positive():
		capped_possible += 1
		if night_laundered.cmp(cap.mul(0.999)) >= 0:
			capped_nights += 1
	var s := summary.duplicate()
	s["night"] = night_no
	s["rank"] = rank
	s["dirty"] = night_dirty
	s["idle"] = night_idle
	s["pocket"] = pocket
	s["laundered"] = night_laundered
	s["clean"] = wallet.clean
	s["dirty_held"] = wallet.dirty
	s["respect"] = night_respect
	s["respect_total"] = respect
	s["skill_shots"] = night_skill_shots
	s["best_combo"] = night_best_combo
	s["jobs_done"] = night_jobs
	s["heat"] = heat.value
	s["clean_earned"] = night_clean
	s["casino"] = casino.night_summary()
	s["meeting"] = meeting.night_summary()
	s["collection"] = collection.night_summary()
	s["wire"] = wire.night_summary()
	set_fielded([])
	return s


func rng() -> RandomNumberGenerator:
	return _rng


# ================================================================ internals =====


## `Game._recompute_stats`: every recompute pushes the handful of numbers other systems have
## to be TOLD about rather than asking every frame — Cohen's `heat_decay_mult` on the meter.
func _recompute_stats() -> void:
	stats.recompute(owned)
	heat.decay_scale = maxf(stats.heat_decay_mult(), 0.0)


## `Game._on_job_completed`: an Old-Timer on the table talks the Commission up (+25% ☆ on
## anything he was out for), and the Consigliere does the same from a desk.
func _on_job_completed(_j: Dictionary, stars: int) -> void:
	night_jobs += 1
	var paid := GuyTraits.job_respect(stars, fielded)
	paid = maxi(int(round(float(paid) * stats.job_respect_mult())), paid)
	add_respect(paid, &"job")


func _on_combo_respect(stars: int) -> void:
	add_respect(stars, &"combo")


func _on_combo_changed(count: int) -> void:
	night_best_combo = maxi(night_best_combo, count)
