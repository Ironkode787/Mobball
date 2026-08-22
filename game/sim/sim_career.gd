class_name SimCareer
extends RefCounted
## A whole career on one seed: days of sessions, sessions of Nights, the Safe filling up in
## between, and a trip through the Ledger at every Count.
##
## The player-behaviour model is deliberately simple and lives entirely in the profile:
## `sessions_per_day` opens spread across a 16-hour waking day, `nights_per_session` Nights
## back to back inside one, `count_seconds` of Count/Ledger between them, and whatever wall
## clock is left over — most of it overnight — is the offline gap the Safe accrues against.
## That matches docs/03 §9's "session opens per day (healthy) 2–4, driven by Safe cap".
##
## Two clocks are kept because the docs use both: `clock` is wall time since the career
## started (what "R3 by day 1" means) and `play_clock` is time with a ball on the table
## (what "first upgrade in 90 seconds" and "time-to-R1 in 15 minutes" mean).

const HOUR := 3600.0
const DAY := 86400.0
## Sessions are spread across a waking day, not around the clock: the long gap is the one
## overnight, which is the gap the Safe cap is actually sized against (docs/03 §6).
const WAKING_HOURS := 16.0

var profile: SimProfile
var state: SimState
var policy: SimPolicy
var reveal: Reveal
var catalog: Upgrades

var seed_value: int = 0
var days: int = 14
## One row per simulated day — the career table the CLI prints.
var rows: Array[Dictionary] = []
var night_seconds: Array[float] = []
var nights_played: int = 0
var first_purchase: Dictionary = {}
## Dirty earned at the table (idle excluded) per hour of play, sampled over the whole career.
var active_dirty: BigMoney = BigMoney.zero()
var active_seconds: float = 0.0
## …and over the last day only, which is the fair comparison against the end-state idle rate.
var last_day_dirty: BigMoney = BigMoney.zero()
var last_day_seconds: float = 0.0
var by_group: Dictionary = {}
var shots_fired: int = 0
var wasted_shots: int = 0
var collects: int = 0
var auto_collects: int = 0
var wash_passes: int = 0
var wash_dead: int = 0
## The Club, career-wide: seconds spent upstairs, seconds of two-ball Meeting, and how much of
## a Night each is. `deck_seconds` is live-ball time the drain clock never ran on.
var deck_seconds: float = 0.0
var meeting_seconds: float = 0.0
var limps: int = 0

var _rng := RandomNumberGenerator.new()
var _last_session_end: float = 0.0


static func run(profile_id: String, p_seed: int, p_days: int, p_catalog: Upgrades = null) -> SimCareer:
	var c := SimCareer.new()
	c._setup(profile_id, p_seed, p_days, p_catalog)
	c._play()
	return c


func _setup(profile_id: String, p_seed: int, p_days: int, p_catalog: Upgrades) -> void:
	catalog = p_catalog if p_catalog != null else Upgrades.shared()
	profile = SimProfile.get_profile(profile_id)
	if profile == null:
		push_error("sim: unknown profile `%s`" % profile_id)
		profile = SimProfile.new()
	seed_value = p_seed
	days = maxi(p_days, 1)
	_rng.seed = p_seed
	state = SimState.new(p_seed, catalog)
	# A private Reveal instance, not `Reveal.shared()`: a balance run must not touch the
	# board state of a live career or of another test in the same process.
	reveal = Reveal.new(catalog)
	policy = SimPolicy.new(catalog, profile, reveal)


# --- the career ---------------------------------------------------------------------


func _play() -> void:
	var per_day := maxi(int(round(profile.sessions_per_day)), 1)
	var slot_gap := WAKING_HOURS / float(per_day) * HOUR
	var day_dirty := BigMoney.zero()
	var day_clean := BigMoney.zero()
	var day_nights := 0
	var day_play := 0.0
	var day := 0
	var session := 0
	var total_sessions := per_day * days
	while session < total_sessions:
		# t = 0 is the first session of the career, so "day 1" reads the way the docs mean it.
		var opens_at := float(session / per_day) * DAY + float(session % per_day) * slot_gap
		state.clock = maxf(state.clock, opens_at)
		# Session open ritual: the Safe (docs/03 §6).
		state.accrue_and_collect_safe(state.clock - _last_session_end)
		for _n in profile.nights_per_session:
			var before_dirty := state.total_dirty
			var before_clean := state.total_clean_earned
			var before_play := state.play_clock
			# THE COMMISSION (specs/m2-content.md §5): The Count grows a button when a
			# rival is waiting, and pressing it makes the NEXT Night the fight. The bot
			# always presses it — the rank ladder is stuck until it does, and a loss
			# costs nothing beyond the Night itself.
			var fight := state.boss_waiting()
			var summary: Dictionary = SimNight.play_boss(state, profile,
					StringName(fight["id"]), _rng) if not fight.is_empty() \
					else SimNight.play(state, profile, _rng)
			nights_played += 1
			day_nights += 1
			night_seconds.append(float(summary["sim_seconds"]))
			_gather(summary)
			var earned := state.total_dirty.sub_clamped(before_dirty)
			# "Active" means what the table paid: the idle trickle that ran during the Night
			# is the thing being compared against, so it comes back out.
			var idle_part: BigMoney = summary["idle"]
			active_dirty = active_dirty.add(earned.sub_clamped(idle_part))
			active_seconds += state.play_clock - before_play
			day_dirty = day_dirty.add(earned)
			day_clean = day_clean.add(state.total_clean_earned.sub_clamped(before_clean))
			day_play += state.play_clock - before_play
			if day == days - 1:
				last_day_dirty = last_day_dirty.add(earned.sub_clamped(idle_part))
				last_day_seconds += state.play_clock - before_play
			_after_night(summary)
			# The Count, then the Ledger: purchases only ever happen here, because
			# `Game.open_ledger()` only opens from the Count.
			state.clock += profile.count_seconds
			# `Game._process` ticks the Heat meter in EVERY state, so a minute on the Count
			# screen is a minute of calm decay — −22 heat at 0.5/s. Offline gaps are NOT
			# ticked, because the real game never catches the meter up on boot either.
			state.heat.tick(profile.count_seconds)
			var bought := policy.buy_pass(state)
			if first_purchase.is_empty() and bought.size() > 0:
				first_purchase = state.purchases[0].duplicate()
			var next_day := int(floor(state.clock / DAY))
			while day < next_day and day < days:
				rows.append(_row(day, day_nights, day_dirty, day_clean, day_play))
				day += 1
				day_dirty = BigMoney.zero()
				day_clean = BigMoney.zero()
				day_nights = 0
				day_play = 0.0
		_last_session_end = state.clock
		session += 1
	while day < days:
		rows.append(_row(day, day_nights, day_dirty, day_clean, day_play))
		day += 1
		day_dirty = BigMoney.zero()
		day_clean = BigMoney.zero()
		day_nights = 0
		day_play = 0.0


## The milestones that turn Ledger cards face up (docs/04 "Milestone reveals").
func _after_night(summary: Dictionary) -> void:
	reveal.rank = state.rank
	if int(summary["tilts"]) > 0:
		reveal.mark_event(&"first_tilt")
	if int(summary["guys_lost"]) >= 2:
		reveal.mark_event(&"first_double_pinch")
	if String(summary["raid"]) == "survived":
		reveal.mark_event(&"first_raid_survived")
	# The board reads held dirty at its peak, which is just before the pocket-money wash.
	reveal.note_dirty_held((summary["dirty_held"] as BigMoney).add(summary["pocket"]))


func _gather(summary: Dictionary) -> void:
	shots_fired += int(summary["sim_shots"])
	wasted_shots += int(summary["sim_wasted"])
	collects += int(summary["sim_collects"])
	auto_collects += int(summary["sim_auto_collects"])
	wash_passes += int(summary["sim_wash_passes"])
	wash_dead += int(summary["sim_wash_dead"])
	deck_seconds += float(summary["sim_deck_seconds"])
	meeting_seconds += float(summary["sim_meeting_seconds"])
	limps += int(summary["sim_limps"])
	for g: Variant in summary["sim_by_group"] as Dictionary:
		var acc: BigMoney = by_group.get(g, null)
		var add: BigMoney = (summary["sim_by_group"] as Dictionary)[g]
		by_group[g] = add if acc == null else acc.add(add)


func _row(day: int, night_count: int, dirty: BigMoney, clean: BigMoney, play: float) -> Dictionary:
	return {
		"day": day + 1,
		"rank": state.rank,
		"respect": state.respect,
		"nights": night_count,
		"nights_total": nights_played,
		"dirty_day": dirty,
		"clean_day": clean,
		"dirty_held": state.wallet.dirty,
		"clean_held": state.wallet.clean,
		"nodes": _nodes_owned(),
		"levels": _levels_owned(),
		"play_seconds": play,
		"heat": state.heat.value,
	}


func _nodes_owned() -> int:
	return state.owned.size()


func _levels_owned() -> int:
	var n := 0
	for id: Variant in state.owned:
		n += int(state.owned[id])
	return n


# --- readouts -----------------------------------------------------------------------


## Dirty per hour of play, table earnings only (the idle trickle is excluded — it is the
## thing being compared against).
func active_per_hour() -> BigMoney:
	if active_seconds <= 0.0:
		return BigMoney.zero()
	return active_dirty.mul(HOUR / active_seconds)


func last_day_per_hour() -> BigMoney:
	if last_day_seconds <= 0.0:
		return active_per_hour()
	return last_day_dirty.mul(HOUR / last_day_seconds)


## What an hour of pure idle pays at the end state — the rackets' rate, ignoring the Safe
## cap (which only ever makes idle worse, so this is the generous side of the comparison).
func idle_per_hour() -> BigMoney:
	return state.stats.idle_rate_total().mul(HOUR)


func median_night_seconds() -> float:
	if night_seconds.is_empty():
		return 0.0
	var sorted := night_seconds.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


## Wall-clock seconds until a rank, or -1 if it was never reached.
func rank_clock(rank: int) -> float:
	var at: Variant = state.rank_at.get(rank, null)
	return float((at as Dictionary)["clock"]) if at is Dictionary else -1.0


## Play seconds until a rank, or -1.
func rank_play(rank: int) -> float:
	var at: Variant = state.rank_at.get(rank, null)
	return float((at as Dictionary)["play"]) if at is Dictionary else -1.0


func owned_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(state.owned.keys())
	out.sort()
	return out
