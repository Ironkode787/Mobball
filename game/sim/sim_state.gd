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
var capped_nights: int = 0
var capped_possible: int = 0
var total_respect_from: Dictionary = {}
var purchases: Array[Dictionary] = []
var rank_at: Dictionary = {}
var raids_survived: int = 0
var raids_lost: int = 0
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


func _init(seed_value: int = 0, from_catalog: Upgrades = null) -> void:
	catalog = from_catalog if from_catalog != null else Upgrades.shared()
	stats.catalog = catalog
	_rng.seed = seed_value
	stats.recompute(owned)
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
	if not bool(meta.get("no_combo", false)):
		v = v.mul(combo.on_hit(group))
	wallet.earn_dirty(v)
	heat.on_dirty_earned(v, Rates.rank_scale(rank))
	night_dirty = night_dirty.add(v)
	total_dirty = total_dirty.add(v)
	jobs.on_earn(v, group)
	return v


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
	var total := unit.mul(float(count))
	if not total.is_positive():
		return BigMoney.zero()
	wallet.earn_dirty(total)
	heat.on_dirty_earned(total, Rates.rank_scale(rank))
	night_dirty = night_dirty.add(total)
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


func _check_rank() -> void:
	var want := rank_for_respect(respect)
	if want <= rank:
		return
	rank = want
	if not rank_at.has(rank):
		rank_at[rank] = {"clock": clock, "play": play_clock, "night": night_no}


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
	heat.bribe()
	jobs.on_bribe(heat_before)
	return true


## `Game.buy_upgrade` + the meta lane's level mint, without the LedgerState statics.
func buy_upgrade(id: String, cost: BigMoney) -> bool:
	if not wallet.spend_clean(cost):
		return false
	owned[id] = int(owned.get(id, 0)) + 1
	stats.recompute(owned)
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
	if bench != null:
		bench.night_tick(stats.bench_slots())
	jobs.roll(rank, stats, stats.job_slots(), _rng)
	jobs.begin_night()
	combo.reset_night()
	night_dirty = BigMoney.zero()
	night_idle = BigMoney.zero()
	night_laundered = BigMoney.zero()
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
	return s


func rng() -> RandomNumberGenerator:
	return _rng


# ================================================================ internals =====


func _on_job_completed(_j: Dictionary, stars: int) -> void:
	night_jobs += 1
	add_respect(stars, &"job")


func _on_combo_respect(stars: int) -> void:
	add_respect(stars, &"combo")


func _on_combo_changed(count: int) -> void:
	night_best_combo = maxi(night_best_combo, count)
