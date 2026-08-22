class_name SimTargets
extends RefCounted
## docs/03-ECONOMY.md §9, as assertions with tolerance bands (docs/09-TECH.md §7: "the tuning
## targets in §9 are CI assertions … balance regressions fail the build like bugs").
##
## Each row is {key, metric, target, got, verdict, note}. Verdicts:
##   PASS — inside the band.
##   WARN — outside the band but inside the loose band: tune, do not panic.
##   FAIL — outside both.
##   N/A  — the content this target measures does not exist yet (T4+), so the number would
##          be a lie. Marked cleanly rather than quietly passed.

const PASS := "PASS"
const WARN := "WARN"
const FAIL := "FAIL"
const NA := "N/A"

const MINUTE := 60.0
const DAY := 86400.0

## docs/03 §9 first upgrade ≤ 90 s. Interpreted as PLAY seconds, and see the note: the
## Ledger only opens from The Count, so the real floor is "one Night".
const FIRST_UPGRADE_SEC := 90.0
const FIRST_UPGRADE_WARN := 240.0
## Time-to-R1 ≤ 15 min of play.
const R1_PLAY_SEC := 15.0 * MINUTE
const R1_PLAY_WARN := 45.0 * MINUTE
## R3 by the end of day 1, R4 by day 2–3.
const R3_DAY := 1
const R4_DAY := 3
## Median Night length 3–8 min.
const NIGHT_LO := 3.0 * MINUTE
const NIGHT_HI := 8.0 * MINUTE
## Active vs pure idle ≥ ×10 (docs/03 §6 says the same thing from the other side: full-idle
## earns ≤ 10 %/h of an active hour).
const ACTIVE_IDLE := 10.0
const ACTIVE_IDLE_WARN := 6.0
## Skilled vs unskilled ≈ ×6, per hour of play.
const SKILL_RATIO := 6.0
const SKILL_BAND_LO := 3.0
const SKILL_BAND_HI := 12.0
## One build shared across seeds by more than this is a dominant strategy (docs/09 §7).
const DOMINANT_SHARE := 0.70
## docs/03 §3 and specs/m2-content.md §1: full Influence investment is supposed to land the
## wheel at "player-favored 4%". The band is the design's own ±: +2% to +5%.
const CASINO_EV_LO := 0.02
const CASINO_EV_HI := 0.05
## Anything past this is not an edge, it is a faucet.
const CASINO_EV_FAIL := 0.08
## The shipped ceiling lands EXACTLY on CASINO_EV_HI (5/8 × 1.68 − 1), so the comparison needs
## a hair of room or binary floating point reports the design's own target as a miss.
const CASINO_EV_EPSILON := 1.0e-6
## docs/03 §4 wants Heat to be a live dial, not a decoration: a career that never spends a
## tenth of its play above band 0 has the multipliers and the Raid as dead content.
const HEAT_LIVE_SHARE := 0.10
const HEAT_LIVE_WARN := 0.02


## `careers`: profile id -> Array[SimCareer] (one per seed).
static func evaluate(careers: Dictionary, catalog: Upgrades) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var ids := SimProfile.ids()
	for id in ids:
		if not careers.has(id):
			continue
		var runs: Array = careers[id]
		if runs.is_empty():
			continue
		rows.append(_first_upgrade(id, runs))
		rows.append(_time_to_rank(id, runs, 1))
		rows.append(_rank_by_day(id, runs, 3, R3_DAY))
		rows.append(_rank_by_day(id, runs, 4, R4_DAY, catalog))
		rows.append(_median_night(id, runs))
		rows.append(_active_idle(id, runs))
		rows.append(_heat_live(id, runs))
		rows.append(_dominant(id, runs))
	rows.append(_skill_ratio(careers))
	rows.append(_casino_ev(careers))
	rows.append(_dead_nodes(careers, catalog))
	return rows


static func dead_nodes(careers: Dictionary, catalog: Upgrades) -> PackedStringArray:
	var bought: Dictionary = {}
	for id: Variant in careers:
		for c: Variant in careers[id] as Array:
			for node_id in (c as SimCareer).owned_ids():
				bought[node_id] = true
	var out: PackedStringArray = []
	for n in catalog.nodes:
		if not bought.has(String(n["id"])):
			out.append(String(n["id"]))
	return out


## Nodes every profile bought on every seed — the spine of the only build the sim found.
static func core_nodes(careers: Dictionary) -> PackedStringArray:
	var counts: Dictionary = {}
	var runs := 0
	for id: Variant in careers:
		for c: Variant in careers[id] as Array:
			runs += 1
			for node_id in (c as SimCareer).owned_ids():
				counts[node_id] = int(counts.get(node_id, 0)) + 1
	var out: PackedStringArray = []
	for node_id: Variant in counts:
		if int(counts[node_id]) == runs and runs > 0:
			out.append(String(node_id))
	out.sort()
	return out


# --- rows ---------------------------------------------------------------------------


static func _first_upgrade(id: String, runs: Array) -> Dictionary:
	var values: Array[float] = []
	var walls: Array[float] = []
	var nights: Array[float] = []
	for c: Variant in runs:
		var career := c as SimCareer
		if career.first_purchase.is_empty():
			continue
		values.append(float(career.first_purchase["play"]))
		walls.append(float(career.first_purchase["clock"]))
		nights.append(float(career.first_purchase["night"]))
	if values.is_empty():
		return _row(id, "first upgrade", "≤ %ds of play" % int(FIRST_UPGRADE_SEC), "never", FAIL,
				"no profile could afford a single Ledger node")
	var play := _median(values)
	var verdict := PASS if play <= FIRST_UPGRADE_SEC else (WARN if play <= FIRST_UPGRADE_WARN else FAIL)
	return _row(id, "first upgrade", "≤ %ds of play" % int(FIRST_UPGRADE_SEC),
			"%.0fs play / %.0fs wall (Night %d)" % [play, _median(walls), int(_median(nights))],
			verdict,
			"floor is one whole Night: clean cash only exists after the pocket-money wash at The Count")


static func _time_to_rank(id: String, runs: Array, rank: int) -> Dictionary:
	var values: Array[float] = []
	var walls: Array[float] = []
	for c: Variant in runs:
		var t := (c as SimCareer).rank_play(rank)
		if t >= 0.0:
			values.append(t)
			walls.append((c as SimCareer).rank_clock(rank))
	if values.is_empty():
		return _row(id, "time to R%d" % rank, "≤ %d min of play" % int(R1_PLAY_SEC / MINUTE),
				"never reached", FAIL, "")
	var play := _median(values)
	var verdict := PASS if play <= R1_PLAY_SEC else (WARN if play <= R1_PLAY_WARN else FAIL)
	return _row(id, "time to R%d" % rank, "≤ %d min of play" % int(R1_PLAY_SEC / MINUTE),
			"%.1f min play / %.1f h wall" % [play / MINUTE, _median(walls) / 3600.0], verdict, "")


static func _rank_by_day(id: String, runs: Array, rank: int, by_day: int,
		catalog: Upgrades = null) -> Dictionary:
	if catalog != null and _max_tier(catalog) < rank:
		return _row(id, "R%d by day %d" % [rank, by_day], "day ≤ %d" % by_day, "no T%d content" % rank,
				NA, "the Ledger stops at T%d — R%d has nothing to spend on yet" % [_max_tier(catalog), rank])
	var reached: Array[float] = []
	var missed := 0
	for c: Variant in runs:
		var t := (c as SimCareer).rank_clock(rank)
		if t >= 0.0:
			reached.append(t)
		else:
			missed += 1
	if reached.is_empty():
		return _row(id, "R%d by day %d" % [rank, by_day], "day ≤ %d" % by_day, "never reached", FAIL, "")
	var day := floorf(_median(reached) / DAY) + 1.0
	var verdict := PASS if (day <= float(by_day) and missed == 0) else (WARN if day <= float(by_day) + 1.0 else FAIL)
	return _row(id, "R%d by day %d" % [rank, by_day], "day ≤ %d" % by_day,
			"day %d%s" % [int(day), "" if missed == 0 else " (%d/%d seeds missed)" % [missed, runs.size()]],
			verdict, "")


static func _median_night(id: String, runs: Array) -> Dictionary:
	var values: Array[float] = []
	for c: Variant in runs:
		values.append((c as SimCareer).median_night_seconds())
	var got := _median(values)
	var verdict := PASS if (got >= NIGHT_LO and got <= NIGHT_HI) else WARN
	return _row(id, "median Night", "%d–%d min" % [int(NIGHT_LO / MINUTE), int(NIGHT_HI / MINUTE)],
			"%.1f min" % (got / MINUTE), verdict,
			"a profile input (ball survival), not an outcome — listed so the rest reads in context")


static func _active_idle(id: String, runs: Array) -> Dictionary:
	var values: Array[float] = []
	for c: Variant in runs:
		var career := c as SimCareer
		var idle := career.idle_per_hour()
		if not idle.is_positive():
			continue
		values.append(career.last_day_per_hour().ratio_to(idle))
	if values.is_empty():
		return _row(id, "active : idle", "≥ ×%d" % int(ACTIVE_IDLE), "no idle rackets owned", NA,
				"nothing with an `idle_rate_add` was ever bought, so there is no idle side to compare")
	var got := _median(values)
	var verdict := PASS if got >= ACTIVE_IDLE else (WARN if got >= ACTIVE_IDLE_WARN else FAIL)
	return _row(id, "active : idle", "≥ ×%d" % int(ACTIVE_IDLE), "×%.1f" % got, verdict, "")


static func _skill_ratio(careers: Dictionary) -> Dictionary:
	if not (careers.has("shark") and careers.has("duffer")):
		return _row("all", "skilled : unskilled", "≈ ×%d" % int(SKILL_RATIO), "profiles missing", NA, "")
	var shark := _rate_of(careers["shark"])
	var duffer := _rate_of(careers["duffer"])
	if not duffer.is_positive():
		return _row("all", "skilled : unskilled", "≈ ×%d" % int(SKILL_RATIO), "duffer earns nothing", FAIL, "")
	var got := shark.ratio_to(duffer)
	var verdict := PASS if (got >= SKILL_BAND_LO and got <= SKILL_BAND_HI) else WARN
	if got > SKILL_BAND_HI * 2.0 or got < SKILL_BAND_LO * 0.5:
		verdict = FAIL
	return _row("all", "skilled : unskilled", "≈ ×%d (band ×%d–×%d)" % [int(SKILL_RATIO), int(SKILL_BAND_LO), int(SKILL_BAND_HI)],
			"×%.1f per hour of play" % got, verdict, "")


## Share of live play spent above Heat band 0 — the honest read of "is the risk dial alive".
static func _heat_live(id: String, runs: Array) -> Dictionary:
	var values: Array[float] = []
	for c: Variant in runs:
		var bands := (c as SimCareer).state.band_seconds
		var total := 0.0
		var live := 0.0
		for i in bands.size():
			total += bands[i]
			if i >= 1:
				live += bands[i]
		if total > 0.0:
			values.append(live / total)
	if values.is_empty():
		return _row(id, "heat liveliness", "≥ %d%% of play in band 1+" % int(HEAT_LIVE_SHARE * 100.0),
				"no play", NA, "")
	var got := _median(values)
	var verdict := PASS if got >= HEAT_LIVE_SHARE else (WARN if got >= HEAT_LIVE_WARN else FAIL)
	return _row(id, "heat liveliness", "≥ %d%% of play in band 1+" % int(HEAT_LIVE_SHARE * 100.0),
			"%.1f%%" % (got * 100.0), verdict,
			"" if verdict == PASS else "the ×1.5/×2.5/×4 bands and the Raid are near-dead content here")


## The wheel's realized edge at the investment the careers actually reached
## (specs/m2-content.md §1: "≈ +4% player EV at full investment").
static func _casino_ev(careers: Dictionary) -> Dictionary:
	var staked := BigMoney.zero()
	var paid := BigMoney.zero()
	var built := 0.0
	var seen := 0
	for id: Variant in careers:
		for c: Variant in careers[id] as Array:
			var s := (c as SimCareer).state
			if not s.casino_staked.is_positive():
				continue
			# The house's own comped stakes count as action: the wheel spun on them and paid on
			# them, so leaving them out of the denominator reads as free edge that is not there.
			staked = staked.add(s.casino_staked).add(s.casino_comped_staked)
			paid = paid.add(s.casino_paid)
			built = maxf(built, Casino.expected_value(s.stats))
			seen += 1
	if seen == 0:
		return _row("all", "casino EV", "+%d%%..+%d%% at max Influence"
				% [int(CASINO_EV_LO * 100.0), int(CASINO_EV_HI * 100.0)],
				"never played", NA, "no career reached the Club deck")
	var real := paid.ratio_to(staked) - 1.0
	var verdict := PASS if (built >= CASINO_EV_LO - CASINO_EV_EPSILON
			and built <= CASINO_EV_HI + CASINO_EV_EPSILON) \
			else (FAIL if built > CASINO_EV_FAIL else WARN)
	return _row("all", "casino EV", "+%d%%..+%d%% at max Influence"
			% [int(CASINO_EV_LO * 100.0), int(CASINO_EV_HI * 100.0)],
			"built %+.1f%%, realized %+.1f%% over %s staked" % [built * 100.0, real * 100.0,
			staked.text()], verdict,
			"" if verdict == PASS else "the shipped ceiling is Casino.CasinoRules.PAYOUT_MAX "
			+ "× Stats.CASINO_POCKETS_MAX — see the SIM report")


static func _dominant(id: String, runs: Array) -> Dictionary:
	if runs.size() < 2:
		return _row(id, "build diversity", "< %d%% identical across seeds" % int(DOMINANT_SHARE * 100.0),
				"1 seed", NA, "run with --seeds 3 or more to test this")
	var total := 0.0
	var pairs := 0
	for i in runs.size():
		for j in range(i + 1, runs.size()):
			total += _jaccard((runs[i] as SimCareer).owned_ids(), (runs[j] as SimCareer).owned_ids())
			pairs += 1
	var got := total / maxf(float(pairs), 1.0)
	var verdict := PASS if got < DOMINANT_SHARE else FAIL
	return _row(id, "build diversity", "< %d%% identical across seeds" % int(DOMINANT_SHARE * 100.0),
			"%.0f%% shared" % (got * 100.0), verdict,
			"" if verdict == PASS else "one build dominates: the same nodes win on every seed")


static func _dead_nodes(careers: Dictionary, catalog: Upgrades) -> Dictionary:
	var dead := dead_nodes(careers, catalog)
	var verdict := PASS if dead.is_empty() else FAIL
	return _row("all", "dead nodes", "none unbought by day 14", "%d of %d" % [dead.size(), catalog.nodes.size()],
			verdict, ", ".join(dead))


# --- helpers ------------------------------------------------------------------------


static func _rate_of(runs: Array) -> BigMoney:
	var total := BigMoney.zero()
	var n := 0
	for c: Variant in runs:
		total = total.add((c as SimCareer).last_day_per_hour())
		n += 1
	return total.div(maxf(float(n), 1.0))


static func _max_tier(catalog: Upgrades) -> int:
	var t := 0
	for n in catalog.nodes:
		t = maxi(t, int(n["tier"]))
	return t


static func _jaccard(a: PackedStringArray, b: PackedStringArray) -> float:
	var seen: Dictionary = {}
	for id in a:
		seen[id] = 1
	var both := 0
	for id in b:
		if seen.has(id):
			both += 1
		seen[id] = 1
	if seen.is_empty():
		return 1.0
	return float(both) / float(seen.size())


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


static func _row(profile: String, metric: String, target: String, got: String, verdict: String,
		note: String) -> Dictionary:
	return {
		"profile": profile, "metric": metric, "target": target,
		"got": got, "verdict": verdict, "note": note,
	}
