class_name SimNight
extends RefCounted
## One Night, played by a bot, with no physics and no scene tree.
##
## The shape of the Night is `game/flow/night.gd`'s: up to three guys off the Bench, one ball
## each, ball-saves, tilts, the 1.2 s pinch beat, the per-second idle trickle, the passive
## wash, the skill shot, the combo clock and the Raid — and then `end_night()`'s pocket-money
## wash. What is replaced is only the *source of switch events*: instead of a ball bouncing
## around geometry, switches arrive as a Poisson process whose rate and target mix come from
## the skill profile (see SimTable).
##
## ## Why this is closed-form where it matters
##
## Time advances by exact jumps between events, never by fixed physics ticks. Every clock in
## the economy is written to survive that: `HeatMeter.tick` integrates its earn window
## analytically (so one 30 s step credits exactly what 3600 steps would), `Combo.tick` is a
## countdown, `Jobs.tick` accumulates. The only per-tick loop left is the spinner blade, and
## that one is integrated in closed form too — a kick at v rad/s closes v²/(2·FRICTION·π)
## switches over v/FRICTION seconds, and the segments inside one time step are paid in ONE
## `earn_repeat` call instead of a hundred `earn_switch` calls. That is exact rather than
## approximate: every consumer past the multiplier (wallet, heat window, night tally, Jobs'
## earn checks) is linear in the amount, and segments 2..n of a spin always pay ×1 combo
## because `Combo.on_hit` resets a chain the moment its own group repeats.
##
## Cost: one event per switch closure plus one clock step per gap — a few thousand BigMoney
## ops per Night. Measured in this environment: ~1,300 Nights/minute for a fully built T3
## table (the worst case; early-career Nights are several times faster), and ~950/minute
## end-to-end once the purchase policy's projections are counted in.
##
## ## The model's assumptions, in one place
##
## Everything below this line is a guess about humans, not about the game: shot rate, target
## mix, ball survival, and the hardware→survival modifiers. They live in `profiles.json` and
## in the constants right below.

## Mirrors `NightController.GUYS_PER_NIGHT` / `PINCH_BEAT` / `BALL_SAVE_SECONDS` /
## `SURVIVE_SECONDS` / `TILT_HEAT` / `WASH_COOLDOWN`.
const GUYS_PER_NIGHT := 3
const PINCH_BEAT := 1.2
const BALL_SAVE_SECONDS := 8.0
const BALL_SAVE_BEAT := 0.4
const SURVIVE_SECONDS := 60.0
const TILT_HEAT := 5.0
## Mirrors `RaidMode.DURATION`.
const RAID_SECONDS := 45.0

## Longest step the event loop will take with no shot in it. Only bounds how coarsely the
## spinner tail, the idle trickle and the storefront timers are sampled — the economy math
## is step-size exact either way.
const MAX_STEP := 1.0

## Job checks that read individual switch closures. When tonight's slips contain none of
## them, `Jobs.on_switch` is a no-op for every switch on the table — including all ~90
## segments of a spinner pass — so the sim skips the call rather than the work inside it.
const SWITCH_CHECKS: PackedStringArray = [
	"bumper_burst", "switch_count_one_ball", "switch_cover", "bank_completions",
]

## Guard rails (survival modifiers). Inlane guides tame the outlanes; the kickback buys back
## one outlane drain per cooldown. Both are the *reason* those nodes exist, so the projection
## and the sim have to credit them or they read as dead nodes.
const GUIDES_BALL_TIME := 1.15
const KICKBACK_BALL_TIME := 1.12
## Ball saves are modelled exactly (a drain inside 8 s of the serve costs a charge instead of
## the guy), so they need no fudge factor here.
## A chargeable plunger lets a player pick the lit lane instead of taking whatever the rubber
## band gives; `plunger_bands` is otherwise invisible to an economy sim, and it is the T0
## node the whole skill-shot faucet hangs off.
const PLUNGER_SKILL_BONUS := 1.5
## The Captain's magnet makes a raid roughly this much deadlier per second alive.
const RAID_HAZARD := 2.5
## Ball-save charges are finite, so this only bounds a pathological profile.
const MAX_BALL_SEGMENTS := 32

var state: SimState
var profile: SimProfile
var table: SimTable

var seconds: float = 0.0
var shots: int = 0
var wasted_shots: int = 0
var wash_passes: int = 0
## Wash shots that moved nothing because tonight's laundering cap was already spent.
var wash_dead: int = 0
var collects: int = 0
var spin_segments: int = 0
var guys_lost: int = 0
var tilts: int = 0
var raid_result: String = ""
var by_group: Dictionary = {}

var _rng: RandomNumberGenerator
var _saves_left: int = 0
var _idle_accum: float = 0.0
var _wash_cool: float = 0.0
var _next_shot: float = 0.0
var _spin_vel: float = 0.0
var _spin_angle: float = 0.0
var _spin_dir: float = 1.0
var _wire_marked: Array[bool] = [false, false, false]
var _wire_reset: float = -1.0
## Per storefront: {"state": &"armed"/&"open"/&"cooldown", "down": int, "timer": float}
var _fronts: Dictionary = {}
var _raid_left: float = -1.0
var _raid_pending: bool = false
var _shot_rate: float = 1.0
var _spin_kick: float = 0.0
var _last_group: StringName = &""
var _watch_switches: bool = false


## Play one whole Night: `start_night` → three guys → `end_night`. Returns the Count summary
## with the sim's own telemetry folded in.
static func play(p_state: SimState, p_profile: SimProfile, rng: RandomNumberGenerator) -> Dictionary:
	var n := SimNight.new()
	n.state = p_state
	n.profile = p_profile
	n._rng = rng
	return n._run_night()


# --- the Night ----------------------------------------------------------------------


func _run_night() -> Dictionary:
	state.start_night()
	table = SimTable.build(state.stats, profile, state.catalog)
	_saves_left = state.stats.ball_saves()
	_shot_rate = table.shot_rate(profile, state.stats)
	_spin_kick = minf(profile.spinner_kick_speed * state.stats.flipper_power(),
			SimTable.SPIN_MAX_SPEED)
	_next_shot = _draw_gap()
	for hw in table.storefronts:
		_fronts[hw] = {"state": &"armed", "down": 0, "timer": 0.0}
	state.heat.raid_triggered.connect(_on_raid_triggered)
	_watch_switches = _jobs_watch_switches()

	var lineup: Array[Dictionary] = []
	for g in state.bench.available():
		if lineup.size() >= GUYS_PER_NIGHT:
			break
		lineup.append(g)

	if lineup.size() < GUYS_PER_NIGHT:
		state.short_lineups += 1

	for i in lineup.size():
		var guy: Dictionary = lineup[i]
		state.jobs.begin_ball(i)
		var alive := _serve()
		if alive >= SURVIVE_SECONDS:
			state.bench.survived_night(guy)
		state.bench.pinch(guy, _raid_left > 0.0)
		if _raid_left > 0.0:
			_end_raid(false)
		guys_lost += 1
		state.guys_pinched += 1
		state.combo.reset()
		_advance(PINCH_BEAT)

	state.heat.raid_triggered.disconnect(_on_raid_triggered)
	var summary := state.end_night({
		"guys_fielded": lineup.size(),
		"guys_lost": guys_lost,
		"tilts": tilts,
		"raid": raid_result,
	})
	summary["sim_seconds"] = seconds
	summary["sim_shots"] = shots
	summary["sim_wasted"] = wasted_shots
	summary["sim_wash_passes"] = wash_passes
	summary["sim_wash_dead"] = wash_dead
	summary["sim_collects"] = collects
	summary["sim_spin_segments"] = spin_segments
	summary["sim_by_group"] = by_group
	return summary


## One guy: his ball, his ball-saves, his tilt. Returns the seconds he stayed up.
func _serve() -> float:
	var alive := 0.0
	var segment := 0
	while segment < MAX_BALL_SEGMENTS:
		segment += 1
		if state.stats.hardware_unlocked(&"rollovers") and _rng.randf() < _skill_chance():
			var paid := state.award_skill_shot()
			var acc: BigMoney = by_group.get(&"skill_shot", null)
			by_group[&"skill_shot"] = paid if acc == null else acc.add(paid)
		var span := _draw_ball_seconds()
		var tilted := _rng.randf() < _tilt_chance()
		if tilted:
			span *= _rng.randf()
		var ran := _run(span)
		alive += ran
		if tilted:
			tilts += 1
			state.tilts += 1
			state.heat.add_flat(TILT_HEAT)
			break
		if ran <= BALL_SAVE_SECONDS and _saves_left > 0:
			# Drained inside the save window: the charge buys the same guy another ball.
			_saves_left -= 1
			_advance(BALL_SAVE_BEAT)
			continue
		break
	return alive


## Advance `span` seconds of live ball, firing shots as they arrive.
func _run(span: float) -> float:
	var t := 0.0
	while t < span - 1.0e-6:
		var dt := minf(minf(_next_shot, span - t), MAX_STEP)
		dt = maxf(dt, 1.0e-6)
		_advance(dt)
		t += dt
		_next_shot -= dt
		if _next_shot <= 1.0e-6:
			_next_shot = _draw_gap()
			_shoot()
	return t


## Time passing, with nobody shooting: the clocks the flow lane ticks every physics frame.
func _advance(dt: float) -> void:
	if dt <= 0.0:
		return
	seconds += dt
	state.play_clock += dt
	state.clock += dt
	state.heat.tick(dt)
	state.peak_heat = maxf(state.peak_heat, state.heat.value)
	state.combo.tick(dt)
	state.jobs.tick(dt, state.heat.value)
	_tick_idle(dt)
	_tick_wash(dt)
	_spin_advance(dt)
	_tick_hardware(dt)
	_wash_cool = maxf(_wash_cool - dt, 0.0)
	if _raid_left > 0.0:
		_raid_left -= dt
		if _raid_left <= 0.0:
			_end_raid(true)
	if profile.bribe_at_heat > 0.0 and state.heat.value >= profile.bribe_at_heat:
		state.bribe()


## `NightController._tick_idle`: whole seconds only, exactly like the real one.
func _tick_idle(dt: float) -> void:
	var rate := state.stats.idle_rate_total()
	if rate == null or not rate.is_positive():
		return
	_idle_accum += dt
	while _idle_accum >= 1.0:
		_idle_accum -= 1.0
		state.earn_idle(rate)


## `NightController._tick_wash`: front businesses wash while a bank is armed. The real one
## runs at 120 Hz and this one runs per event gap; `launder_fraction` compounds, so the two
## differ by (1−f·dt)^n vs (1−f·T) — under 0.005 %/s at the shipped 1 %/s rate.
func _tick_wash(dt: float) -> void:
	var per_sec := state.stats.passive_wash_per_sec()
	if per_sec <= 0.0 or not _storefront_armed():
		return
	state.launder(per_sec * dt, state.launder_cap_left())


## The blade, integrated: `Spinner._physics_process` with the segment count solved instead
## of stepped. Segments crossed inside this step are paid in one `earn_repeat`.
func _spin_advance(dt: float) -> void:
	if is_zero_approx(_spin_vel):
		return
	var before := _spin_angle
	var stop_in := absf(_spin_vel) / SimTable.SPIN_FRICTION
	var span := minf(dt, stop_in)
	# ∫v dt with v shedding FRICTION per second, signed.
	var travelled := _spin_vel * span - signf(_spin_vel) * 0.5 * SimTable.SPIN_FRICTION * span * span
	_spin_angle += travelled
	_spin_vel = move_toward(_spin_vel, 0.0, SimTable.SPIN_FRICTION * dt)
	var crossed := absi(int(floor(_spin_angle / PI)) - int(floor(before / PI)))
	if crossed > 0:
		_pay_spin(crossed)


## The storefront banks and the payphone bank, on their own clocks.
func _tick_hardware(dt: float) -> void:
	if _wire_reset > 0.0:
		_wire_reset -= dt
		if _wire_reset <= 0.0:
			_wire_reset = -1.0
			_wire_marked = [false, false, false]
	for hw: Variant in _fronts:
		var f: Dictionary = _fronts[hw]
		if f["timer"] <= 0.0:
			continue
		f["timer"] = float(f["timer"]) - dt
		if f["timer"] > 0.0:
			continue
		f["timer"] = 0.0
		if f["state"] == &"open":
			# Nobody came through: the shutters go back up (Storefront._close).
			f["state"] = &"armed"
			f["down"] = 0
		elif f["state"] == &"cooldown":
			f["state"] = &"armed"
			f["down"] = 0


# --- shots ---------------------------------------------------------------------------


## Where the next switch closes. Mostly the ball stays where it is (`profile.cluster`) —
## the nest, the bank, the sling pair — and only sometimes does it get moved somewhere else.
func _pick_shot() -> Dictionary:
	if _last_group != &"" and _last_group != &"laundry" and _rng.randf() < profile.cluster:
		var same := table.pick_in_group(_last_group, _rng)
		if not same.is_empty():
			return same
	return table.pick(_rng)


func _shoot() -> void:
	var shot := _pick_shot()
	if shot.is_empty():
		return
	shots += 1
	_last_group = shot["group"]
	var kind: int = shot["kind"]
	match kind:
		SimTable.Kind.BUMPER, SimTable.Kind.SLING, SimTable.Kind.ROLLOVER:
			_earn(shot["group"], shot["base_big"], shot["id"])
		SimTable.Kind.SPINNER:
			_spin_kick_now()
		SimTable.Kind.WIRE:
			_shoot_wire()
		SimTable.Kind.STOREFRONT:
			_shoot_storefront(shot["id"])
		SimTable.Kind.ORBIT:
			# The lane reports entry (no money) and then the completed loop.
			if _watch_switches:
				state.jobs.on_switch(&"orbit_left_entry", &"orbit")
			_earn(&"orbit", shot["base_big"], &"orbit_left")
		SimTable.Kind.WASH:
			if table.wash_gated_by_bank:
				# Lucky's door is behind its own drop bank now: the wash rides the bank
				# cycle, it is no longer a free-standing doorway.
				_shoot_storefront(&"storefront_laundromat")
			else:
				_wash_pass()


## The single money path, plus the switch event the flow lane forwards to Jobs.
func _earn(group: StringName, base: BigMoney, id: StringName) -> void:
	if _watch_switches:
		state.jobs.on_switch(id, group)
	var got := state.earn_switch(group, base, {"switch": id})
	var acc: BigMoney = by_group.get(group, null)
	by_group[group] = got if acc == null else acc.add(got)


func _spin_kick_now() -> void:
	var kick := maxf(_spin_kick, SimTable.SPIN_MIN_KICK)
	_spin_vel = clampf(_spin_vel * 0.35 + _spin_dir * kick,
			-SimTable.SPIN_MAX_SPEED, SimTable.SPIN_MAX_SPEED)
	_spin_dir = -_spin_dir


## `n` blade segments. The first goes through the full pipeline (it may extend a chain); the
## rest cannot — they repeat their own group, which resets the chain — so they are paid in
## one call with the multiplier pinned to ×1, then the chain is left where the last segment
## would have left it.
func _pay_spin(n: int) -> void:
	if n <= 0:
		return
	spin_segments += n
	var base := BigMoney.from_float(SimTable.SPINNER_SEGMENT)
	if _watch_switches:
		for _i in n:
			state.jobs.on_switch(&"spinner_numbers", &"spinner")
	var got := state.earn_switch(&"spinner", base)
	if n > 1:
		got = got.add(state.earn_repeat(&"spinner", base, n - 1))
		state.combo.on_hit(&"spinner")
	var acc: BigMoney = by_group.get(&"spinner", null)
	by_group[&"spinner"] = got if acc == null else acc.add(got)


## Three payphones. A hit on an already-marked phone scores nothing at all (TargetBank
## returns early) — that is where target discipline shows up in the money.
func _shoot_wire() -> void:
	var idx := _rng.randi() % _wire_marked.size()
	if _rng.randf() < profile.target_discipline:
		var live: PackedInt32Array = []
		for i in _wire_marked.size():
			if not _wire_marked[i]:
				live.append(i)
		if not live.is_empty():
			idx = live[_rng.randi() % live.size()]
	if _wire_marked[idx]:
		wasted_shots += 1
		return
	_wire_marked[idx] = true
	_earn(&"wire", BigMoney.from_float(SimTable.WIRE_TARGET), StringName("wire_%d" % (idx + 1)))
	var all_down := true
	for m in _wire_marked:
		all_down = all_down and m
	if all_down:
		_earn(&"wire", BigMoney.from_float(SimTable.BANK_COMPLETE), &"wire_bank_complete")
		_wire_reset = SimTable.WIRE_RESET_SEC


func _shoot_storefront(prefer: StringName) -> void:
	var hw := _pick_storefront(prefer)
	if hw == &"":
		wasted_shots += 1
		return
	var f: Dictionary = _fronts[hw]
	match f["state"]:
		&"armed":
			f["down"] = int(f["down"]) + 1
			# Drop targets report but do not pay (TableScore.hit).
			if _watch_switches:
				state.jobs.on_switch(StringName("%s_t%d" % [hw, int(f["down"])]), &"storefronts")
			if int(f["down"]) >= SimTable.STOREFRONT_TARGETS:
				f["state"] = &"open"
				f["timer"] = SimTable.STOREFRONT_OPEN_SEC
		&"open":
			if hw == &"storefront_laundromat":
				_wash_pass()
			var value := SimTable.collect_value(hw, state.stats, state.catalog)
			_earn(&"storefronts", value, StringName(String(hw) + "_collect"))
			state.jobs.on_storefront(hw)
			collects += 1
			f["state"] = &"cooldown"
			f["down"] = 0
			f["timer"] = SimTable.STOREFRONT_REARM_SEC
		_:
			wasted_shots += 1


## `NightController._wash_pass`: one pass washes `launder_rate` of held dirty against
## tonight's cap.
func _wash_pass() -> void:
	if _wash_cool > 0.0:
		wasted_shots += 1
		return
	_wash_cool = SimTable.WASH_COOLDOWN
	var rate := state.stats.launder_rate()
	if rate <= 0.0:
		return
	if _watch_switches:
		state.jobs.on_switch(&"laundromat_loop", &"laundry")
	var moved := state.launder(rate, state.launder_cap_left())
	wash_passes += 1
	if not moved.is_positive():
		wasted_shots += 1
		wash_dead += 1


# --- raid ----------------------------------------------------------------------------


func _on_raid_triggered() -> void:
	if _raid_left > 0.0:
		return
	_raid_pending = true
	_raid_left = RAID_SECONDS


func _end_raid(survived: bool) -> void:
	if not _raid_pending:
		return
	_raid_pending = false
	_raid_left = -1.0
	if survived:
		raid_result = "survived"
		state.wallet.earn_clean(state.wallet.dirty.mul(SimState.RAID_CLEAN_PAYOUT))
		state.add_respect(SimState.RESPECT_RAID_SURVIVED, &"raid")
		state.raids_survived += 1
	else:
		raid_result = "lost"
		state.wallet.confiscate_dirty(Rates.RAID_CONFISCATE_FRACTION)
		state.raids_lost += 1
	state.heat.reset_after_raid(survived)


# --- draws ---------------------------------------------------------------------------


## Ball survival: a floor plus an exponential tail, scaled by the guard rails the Ledger has
## bought. Exponential because pinball drains are close to memoryless once the ball is in
## play — the risk per second barely depends on how long you have already survived.
func _draw_ball_seconds() -> float:
	var scale := 1.0
	if state.stats.hardware_unlocked(&"inlane_guides"):
		scale *= GUIDES_BALL_TIME
	if state.stats.hardware_unlocked(&"kickback_left"):
		scale *= KICKBACK_BALL_TIME
	var tail := maxf(profile.ball_seconds_mean - profile.ball_seconds_min, 1.0)
	var span := (profile.ball_seconds_min + _expo(tail)) * scale
	if _raid_left > 0.0:
		span /= RAID_HAZARD
	return span


func _draw_gap() -> float:
	return _expo(1.0 / maxf(_shot_rate, 0.01))


func _expo(mean: float) -> float:
	return -log(maxf(1.0 - _rng.randf(), 1.0e-12)) * mean


## Does any of tonight's work read raw switch closures? See SWITCH_CHECKS.
func _jobs_watch_switches() -> bool:
	for j in state.jobs.active_jobs():
		if SWITCH_CHECKS.has(String(j.get("check", ""))):
			return true
	return false


## A chargeable plunger turns the delivery from a lottery into a shot.
func _skill_chance() -> float:
	if not state.stats.flag(&"plunger_bands"):
		return profile.skill_shot_p
	return minf(profile.skill_shot_p * PLUNGER_SKILL_BONUS, 1.0)


## More warnings before the Inspector calls it means proportionally more nudging per tilt.
func _tilt_chance() -> float:
	var leans := maxi(state.stats.tilt_leans(), 1)
	return profile.tilt_per_ball * float(Stats.BASE_TILT_LEANS) / float(leans)


func _storefront_armed() -> bool:
	if _fronts.is_empty():
		return true
	for hw: Variant in _fronts:
		if (_fronts[hw] as Dictionary)["state"] != &"cooldown":
			return true
	return false


## Which storefront this shot actually lands on. A disciplined player works the one that is
## open (or one still standing); a duffer sprays across the block and hits shutters.
func _pick_storefront(prefer: StringName) -> StringName:
	if _fronts.is_empty():
		return &""
	if _rng.randf() < profile.target_discipline:
		if _fronts.has(prefer) and (_fronts[prefer] as Dictionary)["state"] != &"cooldown":
			return prefer
		var open_ones: Array[StringName] = []
		var armed: Array[StringName] = []
		for hw: Variant in _fronts:
			match (_fronts[hw] as Dictionary)["state"]:
				&"open":
					open_ones.append(hw)
				&"armed":
					armed.append(hw)
		if not open_ones.is_empty():
			return open_ones[_rng.randi() % open_ones.size()]
		if not armed.is_empty():
			return armed[_rng.randi() % armed.size()]
	var all: Array = _fronts.keys()
	return all[_rng.randi() % all.size()]


## M2 PLACEHOLDER — the casino, the Wire draws and mystery briefcases are not modelled.
## When they land (specs/m2-empire.md FLOW-2) this is where `profile.risk_appetite` turns
## into staked dirty and clean winnings; until then the sim reports the ratios WITHOUT the
## only positive-EV laundry in the design, which makes its clean-side numbers conservative.
func _casino_stub() -> void:
	pass
