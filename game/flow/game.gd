extends Node
## The Game autoload — owns the session (specs/m1-hook.md). The public surface below is
## contract-locked: `wallet` `heat` `stats` `respect` `rank` `night_no` `bench` `state`
## `state_changed` `earn_switch`. Everything else is the flow lane's internals.
##
## This is the model half of the session. It owns money, career and the state machine but
## never touches the scene tree: `game/main.gd` hosts the table and the screens and reacts
## to `state_changed`, and `game/flow/night.gd` drives the live Night.
##
##     attract ──start_night──▶ night ──end_night──▶ count ⇄ ledger
##                                ▲                    │
##                                └──── start_night ───┘

signal state_changed(state: StringName)
## Offline earnings waiting in the Safe (docs/03 §6). Zero once collected.
signal safe_changed(amount: BigMoney)

## ☆ thresholds per rank, docs/02 §1. R1=10 R2=50 R3=150 are M1's ladder; the rest are
## here so the ladder is data rather than a special case when M2 lands.
const RANK_RESPECT: PackedInt32Array = [0, 10, 50, 150, 400, 1000, 2500, 6000]
const RESPECT_SKILL_SHOT := 1
const RESPECT_RAID_SURVIVED := 25
## "Exhibit A returned": surviving a raid pays a quarter of the held dirty, in CLEAN.
const RAID_CLEAN_PAYOUT := 0.25
## Skill shot cash at R0; scales with rank_scale like every other payout (docs/03 §7).
const SKILL_SHOT_MANTISSA := 2.0
const SKILL_SHOT_EXP := 2
## Music stems audible per rank (docs/08 §1) — rank 0 already has a band, R7 has all eight.
const MUSIC_LEVEL_OFFSET := 1

var wallet := Wallet.new()
var heat := HeatMeter.new()
var stats := Stats.new()
var respect: int = 0
var rank: int = 0
var night_no: int = 0
var bench: Bench = null
var state: StringName = &"attract":
	set(v):
		if state == v:
			return
		state = v
		state_changed.emit(v)

# --- flow-lane additions ------------------------------------------------------

var save := SaveGame.new()
var jobs := Jobs.new()
var combo := Combo.new()
## Ledger node id -> owned level, and the half of it flow is responsible for: the save file.
## The meta lane keeps the same map in `LedgerState` for its board; the two are kept in step
## by `_push_owned_to_meta()` / `_pull_owned_from_meta()` on every purchase and every load.
var owned: Dictionary = {}
## The live NightController while `state == &"night"` (typed loosely to keep game.gd and
## night.gd out of a class-reference cycle).
var night: Node = null
## Untaken offline earnings; the attract screen and The Count offer them.
var safe_pending: BigMoney = BigMoney.zero()
## Wall-clock stamp the Safe accrues from.
var last_seen: float = 0.0
## Summary of the Night The Count is showing.
var last_night: Dictionary = {}
## Biggest Night so far — the headline generator's "record take" test.
var best_night: BigMoney = BigMoney.zero()
var session_seed: int = 0

# Per-Night tallies, reset by start_night() and read by the summary.
var night_dirty: BigMoney = BigMoney.zero()
var night_idle: BigMoney = BigMoney.zero()
var night_laundered: BigMoney = BigMoney.zero()
var night_respect: int = 0
var night_jobs: Array[String] = []
var night_skill_shots: int = 0
var night_best_combo: int = 0
var night_bribes: int = 0

## The meta lane's stores: the authoritative owned-upgrades map and the reveal history.
## Both are loaded by path rather than referenced as classes so the flow lane keeps booting
## if the meta lane moves them — the cost of one going missing is the Ledger board losing
## its state, not the game failing to start.
const LEDGER_STATE_PATH := "res://game/meta/ledger_state.gd"
const REVEAL_PATH := "res://game/meta/reveal.gd"

var _booted: bool = false
var _rng := RandomNumberGenerator.new()
var _headlines := Headlines.new()
var _ledger_state: GDScript = null
var _reveal_script: GDScript = null


## Wired at construction, not in `_ready()`: the headless test runner is a bare SceneTree
## that never reaches a frame, so `_ready()` would land after the tests had already used
## the singleton. Every connect below is guarded, so both paths are safe.
func _init() -> void:
	_wire(combo.changed, _on_combo_changed)
	_wire(combo.respect_earned, _on_combo_respect)
	_wire(jobs.completed, _on_job_completed)


func _ready() -> void:
	_wire(Events.upgrade_purchased, _on_upgrade_purchased)
	_wire(Events.tilted, _on_tilted)
	_wire(combo.changed, _on_combo_changed)
	_wire(combo.respect_earned, _on_combo_respect)
	_wire(jobs.completed, _on_job_completed)


## The Inspector's first report turns a face-down card over (docs/04 influence branch).
func _on_tilted() -> void:
	mark_reveal_event(&"first_tilt")


static func _wire(sig: Signal, to: Callable) -> void:
	if not sig.is_connected(to):
		sig.connect(to)


func _process(delta: float) -> void:
	heat.tick(delta)


# =============================================================== money path =====


## THE single money path: every dirty payout on the table flows through here.
## base_value × stats add/mult × heat multiplier × combo → wallet; the same post-multiplier
## amount feeds the heat window (hot money is what raises heat, docs/03 §4) and the Jobs.
##
## `Stats` already folds the &"all" group into every `value_add`/`value_mult` it returns, so
## there is exactly one lookup here — folding it in again would square the Brass Balls line.
##
## `meta` options: `no_combo` (idle/mode payouts that must not extend a chain),
## `switch` (the hardware id, for Jobs that count specific switches).
func earn_switch(group: StringName, base_value: BigMoney, meta: Dictionary = {}) -> BigMoney:
	var v := base_value.add(stats.value_add(group))
	v = v.mul(stats.value_mult(group))
	v = v.mul(heat.multiplier())
	if not bool(meta.get("no_combo", false)):
		v = v.mul(combo.on_hit(group))
	wallet.earn_dirty(v)
	heat.on_dirty_earned(v, Rates.rank_scale(rank))
	Events.dirty_earned.emit(v, group)
	night_dirty = night_dirty.add(v)
	jobs.on_earn(v, group)
	return v


## The idle layer's trickle (docs/03 §6): real dirty cash, but it is not "hot money" —
## it neither feeds Heat nor extends a combo.
func earn_idle(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	wallet.earn_dirty(amount)
	night_dirty = night_dirty.add(amount)
	night_idle = night_idle.add(amount)
	Events.dirty_earned.emit(amount, &"idle")


## Wash dirty → clean and book it for The Count. Returns what actually moved.
func launder(fraction: float, cap: BigMoney = null) -> BigMoney:
	var moved := wallet.launder_fraction(fraction, cap)
	if moved.is_positive():
		night_laundered = night_laundered.add(moved)
		jobs.on_launder(moved)
		Events.laundered.emit(moved)
	return moved


## Remaining wash allowance for tonight (docs/03 §2 — the loop is capped per Night).
func launder_cap_left() -> BigMoney:
	var cap := stats.launder_cap()
	if cap == null or not cap.is_positive():
		return BigMoney.zero()
	return cap.sub_clamped(night_laundered)


# ============================================================ career ladder =====


## Every ☆ in the game arrives here (docs/03 §5 — never purchasable, never idle).
func add_respect(stars: int, _source: StringName = &"") -> void:
	if stars <= 0:
		return
	respect += stars
	night_respect += stars
	Events.respect_changed.emit(respect)
	_check_rank()


func rank_for_respect(total: int) -> int:
	var r := 0
	for i in RANK_RESPECT.size():
		if total >= RANK_RESPECT[i]:
			r = i
	return r


func respect_to_next_rank() -> int:
	var next := rank + 1
	if next >= RANK_RESPECT.size():
		return 0
	return maxi(RANK_RESPECT[next] - respect, 0)


func _check_rank() -> void:
	var want := rank_for_respect(respect)
	if want <= rank:
		return
	rank = want
	Events.rank_changed.emit(rank)
	AudioDirector.play(&"knocker")
	AudioDirector.play(&"rankup_fanfare")
	AudioDirector.music_set_level(clampi(rank + MUSIC_LEVEL_OFFSET, 0, 8))
	save_now()


func rank_title() -> String:
	return Headlines.rank_title(rank)


# ========================================================== state machine ======


## Boot the session: load the save, accrue the Safe, land on the attract screen.
func boot(save_path: String = SaveGame.DEFAULT_PATH) -> void:
	save = SaveGame.new(save_path)
	var data := save.read()
	if data.is_empty():
		new_game(int(Time.get_unix_time_from_system()))
	else:
		from_dict(data)
		if not save.salvaged_from.is_empty():
			print("[save] salvaged from ", save.salvaged_from)
	_accrue_safe()
	_booted = true
	state = &"attract"
	AudioDirector.music_set_level(clampi(rank + MUSIC_LEVEL_OFFSET, 0, 8))
	AudioDirector.music_set_state(&"calm")


func is_booted() -> bool:
	return _booted


## A career from nothing. `seed` drives the Bench names and the Job draw.
func new_game(seed_value: int = 0) -> void:
	session_seed = seed_value
	_rng.seed = seed_value
	wallet.reset()
	heat.reset()
	respect = 0
	rank = 0
	night_no = 0
	owned = {}
	_push_owned_to_meta()
	stats.recompute(owned)
	bench = Bench.new(seed_value, stats.bench_slots())
	jobs = Jobs.new()
	_wire(jobs.completed, _on_job_completed)
	_reveal_from_dict({})
	combo.reset()
	safe_pending = BigMoney.zero()
	last_seen = Time.get_unix_time_from_system()
	best_night = BigMoney.zero()
	last_night = {}
	_reset_night_tallies()
	_booted = true
	state = &"attract"


## attract/count → night. The host scene builds the NightController when it sees the state.
func start_night() -> void:
	if state == &"night":
		return
	if bench == null:
		bench = Bench.new(session_seed, stats.bench_slots())
	night_no += 1
	bench.night_tick(stats.bench_slots())
	jobs.roll(rank, stats, stats.job_slots(), _rng)
	jobs.begin_night()
	combo.reset()
	_reset_night_tallies()
	state = &"night"
	Events.night_started.emit(night_no)
	AudioDirector.music_set_state(&"calm")


## night → count. `summary` comes from the NightController; the pocket-money wash, the
## headline and the record book are applied here so the Count screen only has to render.
func end_night(summary: Dictionary) -> Dictionary:
	var pocket := launder(1.0, BigMoney.min_of(stats.pocket_money(), night_dirty))
	var s := summary.duplicate()
	s["night"] = night_no
	s["rank"] = rank
	s["rank_title"] = rank_title()
	s["dirty"] = night_dirty
	s["idle"] = night_idle
	s["pocket"] = pocket
	s["laundered"] = night_laundered
	s["clean"] = wallet.clean
	s["dirty_held"] = wallet.dirty
	s["respect"] = night_respect
	s["respect_total"] = respect
	s["jobs"] = night_jobs.duplicate()
	s["jobs_done"] = night_jobs.size()
	s["skill_shots"] = night_skill_shots
	s["best_combo"] = night_best_combo
	s["heat"] = heat.value
	s["bench_free"] = bench.available().size() if bench != null else 0
	s["best_night"] = best_night
	s["quiet_floor"] = stats.pocket_money()
	s["rank_up"] = bool(s.get("rank_up", int(s.get("rank_before", rank)) < rank))
	s["headline"] = _headlines.pick(s, _rng)
	if night_dirty.cmp(best_night) > 0:
		best_night = night_dirty
	last_night = s
	state = &"count"
	Events.night_ended.emit(s)
	AudioDirector.music_set_state(&"count")
	save_now()
	return s


func open_ledger() -> void:
	if state == &"count":
		state = &"ledger"


func close_ledger() -> void:
	if state == &"ledger":
		state = &"count"


# ================================================================= actions =====


## Ledger purchase. Spends clean, levels the node, recomputes Stats, tells the world.
## Ledger purchase from outside the Ledger board (the flow sims, and any one-tap buy that
## lands later). The level is minted by the meta lane's `LedgerState` so the owned map has
## exactly one canonical home; `owned` is this file's mirror of it, for the save.
func buy_upgrade(id: String, cost: BigMoney) -> bool:
	if not wallet.spend_clean(cost):
		return false
	var level := _mint_level(id)
	stats.recompute(owned)
	AudioDirector.play(&"stamp_thunk")
	Events.upgrade_purchased.emit(id, level)
	return true


func _mint_level(id: String) -> int:
	_pull_owned_from_meta()
	var store := _meta_owned_store()
	var level := int(owned.get(id, 0)) + 1
	if store != null and store.has_method("add_level"):
		level = int(store.call("add_level", id))
	owned[id] = level
	_push_owned_to_meta()
	return level


## Post bail (docs/03 §8) — dirty cash, escalating with his rap sheet.
func bail_guy(guy: Dictionary) -> bool:
	if bench == null or guy.is_empty():
		return false
	var cost := bench.bail_cost(guy)
	if not wallet.can_afford_dirty(cost):
		return false
	if not wallet.spend_dirty(cost):
		return false
	bench.bail(guy)
	AudioDirector.play(&"bail_paid")
	Events.guy_bailed.emit(guy)
	save_now()
	return true


## The Beat Cop bribe shot: −20 heat for an escalating dirty cost (docs/03 §4).
func bribe() -> bool:
	var cost := heat.bribe_cost(night_bribes)
	if not wallet.can_afford_dirty(cost) or not wallet.spend_dirty(cost):
		return false
	var heat_before := heat.value
	night_bribes += 1
	heat.bribe()
	jobs.on_bribe(heat_before)
	AudioDirector.play(&"bribe_paid")
	return true


## Take the Safe (docs/03 §6). The session-open ritual.
func collect_safe() -> BigMoney:
	var got := safe_pending
	if got == null or not got.is_positive():
		return BigMoney.zero()
	wallet.earn_dirty(got)
	safe_pending = BigMoney.zero()
	last_seen = Time.get_unix_time_from_system()
	AudioDirector.play(&"safe_open")
	safe_changed.emit(safe_pending)
	save_now()
	return got


## Respect + cash for a clean Drop-Off (docs/01 §6). The cash rides the normal money path
## (so it is hot money like any other shot) but must not open a combo — the chain starts
## with the player's first real decision, not with the launch.
func award_skill_shot() -> BigMoney:
	night_skill_shots += 1
	var base := BigMoney.of(SKILL_SHOT_MANTISSA, SKILL_SHOT_EXP).mul_big(
			Rates.rank_scale(rank).div_big(Rates.rank_scale(0)))
	var payout := earn_switch(&"skill_shot", base, {"no_combo": true})
	add_respect(RESPECT_SKILL_SHOT, &"skill_shot")
	AudioDirector.play(&"skill_shot_ding")
	Events.skill_shot.emit()
	return payout


# =========================================================== offline / save =====


func _accrue_safe() -> void:
	var rate := stats.idle_rate_total()
	var now := Time.get_unix_time_from_system()
	var elapsed := Offline.elapsed_clamped(now, last_seen)
	safe_pending = Offline.accrue(rate, elapsed, Rates.safe_cap(rate, stats.safe_hours()))
	last_seen = now
	safe_changed.emit(safe_pending)


func save_now() -> bool:
	last_seen = Time.get_unix_time_from_system()
	return save.write(to_dict())


func to_dict() -> Dictionary:
	return {
		"wallet": wallet.to_dict(),
		"heat": heat.to_dict(),
		"respect": respect,
		"rank": rank,
		"night_no": night_no,
		"owned": owned.duplicate(),
		"bench": bench.to_dict() if bench != null else {},
		"jobs": jobs.to_dict(),
		"reveal": _reveal_to_dict(),
		"safe": {
			"last_seen": last_seen,
			"pending": safe_pending.to_dict(),
		},
		"records": {
			"best_night": best_night.to_dict(),
		},
		"rng": {
			"seed": str(session_seed),
			"state": str(_rng.state),
		},
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	wallet.from_dict(d.get("wallet", {}))
	heat.from_dict(d.get("heat", {}))
	respect = int(d.get("respect", 0))
	rank = int(d.get("rank", 0))
	night_no = int(d.get("night_no", 0))
	var raw_owned: Variant = d.get("owned", {})
	owned = {}
	if raw_owned is Dictionary:
		for k: Variant in raw_owned:
			owned[String(k)] = int((raw_owned as Dictionary)[k])
	_push_owned_to_meta()
	stats.recompute(owned)

	var rng_d: Dictionary = d.get("rng", {})
	session_seed = SaveGame.to_i64(rng_d.get("seed", 0), 0)
	_rng.seed = session_seed
	_rng.state = SaveGame.to_i64(rng_d.get("state", null), int(_rng.state))

	bench = Bench.new(session_seed, stats.bench_slots())
	bench.from_dict(d.get("bench", {}))
	jobs = Jobs.new()
	_wire(jobs.completed, _on_job_completed)
	jobs.from_dict(d.get("jobs", {}))
	_reveal_from_dict(d.get("reveal", {}))

	var safe_d: Dictionary = d.get("safe", {})
	last_seen = float(safe_d.get("last_seen", Time.get_unix_time_from_system()))
	safe_pending = BigMoney.from_dict(safe_d.get("pending", {}))
	var records: Dictionary = d.get("records", {})
	best_night = BigMoney.from_dict(records.get("best_night", {}))
	combo.reset()
	_reset_night_tallies()


# ================================================================ internals =====


func _reset_night_tallies() -> void:
	night_dirty = BigMoney.zero()
	night_idle = BigMoney.zero()
	night_laundered = BigMoney.zero()
	night_respect = 0
	night_jobs = []
	night_skill_shots = 0
	night_best_combo = 0
	night_bribes = 0


## Fires for our own purchases and for anything the meta lane buys directly — the level
## is absolute, so recording it twice is harmless.
func _on_upgrade_purchased(id: String, level: int) -> void:
	_pull_owned_from_meta()
	owned[id] = maxi(level, int(owned.get(id, 0)))
	stats.recompute(owned)
	_push_owned_to_meta()
	if bench != null:
		bench.slots = maxi(bench.slots, stats.bench_slots())
	save_now()


func _meta_owned_store() -> GDScript:
	if _ledger_state == null and ResourceLoader.exists(LEDGER_STATE_PATH):
		_ledger_state = load(LEDGER_STATE_PATH)
	return _ledger_state


## The meta lane's `Reveal` singleton — which face-down Ledger cards have been turned over.
## The events that flip them happen here (a TILT, a survived raid), and the save file is
## flow's, so flow marks them and flow persists them.
func _reveal() -> Object:
	if _reveal_script == null and ResourceLoader.exists(REVEAL_PATH):
		_reveal_script = load(REVEAL_PATH)
	if _reveal_script == null or not _reveal_script.has_method("shared"):
		return null
	return _reveal_script.call("shared")


## Record a milestone the Ledger reveals cards on (`first_tilt`, `first_raid_survived`,
## `first_double_pinch` — see Upgrades.REVEAL_EVENTS).
func mark_reveal_event(id: StringName) -> void:
	var r := _reveal()
	if r != null and r.has_method("mark_event"):
		r.call("mark_event", id)


func _reveal_to_dict() -> Dictionary:
	var r := _reveal()
	if r == null or not r.has_method("to_dict"):
		return {}
	var d: Variant = r.call("to_dict")
	return d if d is Dictionary else {}


func _reveal_from_dict(d: Variant) -> void:
	var r := _reveal()
	if r == null or not r.has_method("from_dict"):
		return
	r.call("from_dict", d if d is Dictionary else {})


func _push_owned_to_meta() -> void:
	var store := _meta_owned_store()
	if store != null and store.has_method("set_owned"):
		store.call("set_owned", owned)


func _pull_owned_from_meta() -> void:
	var store := _meta_owned_store()
	if store == null or not store.has_method("get_owned"):
		return
	var theirs: Variant = store.call("get_owned")
	if not (theirs is Dictionary):
		return
	for id: Variant in theirs as Dictionary:
		var key := String(id)
		owned[key] = maxi(int((theirs as Dictionary)[id]), int(owned.get(key, 0)))


func _on_job_completed(j: Dictionary, stars: int) -> void:
	night_jobs.append(String(j.get("name", j.get("id", "job"))))
	add_respect(stars, &"job")
	AudioDirector.play(&"job_done")
	Events.job_completed.emit(String(j.get("id", "")), stars)


func _on_combo_changed(count: int) -> void:
	night_best_combo = maxi(night_best_combo, count)
	Events.combo_changed.emit(count)
	if count == 2:
		AudioDirector.play(&"combo_2")
	elif count == 3:
		AudioDirector.play(&"combo_3")
	elif count >= 4:
		AudioDirector.play(&"combo_4")


func _on_combo_respect(stars: int) -> void:
	add_respect(stars, &"combo")
