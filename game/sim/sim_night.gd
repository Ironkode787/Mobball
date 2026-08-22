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
## Mirrors `NightController.STOREFRONT_POLL`: how often the banks are read for a Collection
## Round trigger. It matters — a block that is all-armed for less than one poll never starts
## a round, which is the difference between a Meeting lighting tonight and not.
const STOREFRONT_POLL := 0.25

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

# --- M2 specialists and flags (specs/m2-content.md §2/§3) --------------------------
## Every constant below turns a shipped effect the sim could not otherwise see into a number.
## They are player-behaviour guesses like everything else above this line, not game rules.
##
## Big Sal shortens the kickback's cooldown, so the guard rail is up more of the time. The
## gain is capped: a kickback that is always ready is still only one outlane.
const KICKBACK_COOLDOWN_GAIN_MAX := 2.0
## The Inspector's vacation (`inspector_vacation`) is 20 s of free nudging a Night, and a
## player spends it on the nudges they would otherwise not dare — so it buys back this share
## of the Night's tilts.
const INSPECTOR_TILT_CUT := 0.25
## The insurance policy (`insurance_policy`) turns a TILT into a limp: the guy keeps playing
## at half value for ten seconds instead of going inside.
const INSURANCE_LIMP_SECONDS := 10.0
const INSURANCE_LIMP_VALUE := 0.5
## The police scanner (`police_scanner`) is ten seconds of warning before the hardware that
## raises heat goes live — the player is never caught mid-ramp by a raid.
const SCANNER_RAID_HAZARD := 0.75
## The Wiretap (`wiretap_wire`) shows the next Wire number 15 s early and the spinner IS the
## ticket, so a player who can count segments can dial the last two digits. This is the
## softest guess in the file: it converts a share of draws into EXACT hits (×80, clean),
## scaled by discipline, and it is capped well under what a perfect counter could do.
const WIRETAP_AIM := 0.25
## Seconds Manny waits before trying a till again when nothing at all is lit — he is standing
## right there, so he does not burn a whole interval on an empty block.
const AUTO_COLLECT_RETRY := 1.0
## How much of the drain clock a second on the Club deck spends. The deck itself cannot drain
## a ball, but a visit always ends with the return lane feeding a live ball into the right
## inlane, and that feed is a drain risk like any other. A quarter is the model's read of "one
## risky moment per trip instead of a continuous one" — and it matters: at zero the Club would
## make a shark's ball immortal, which is the one thing the geometry definitely does not do.
const DECK_DRAIN_SHARE := 0.25

var state: SimState
var profile: SimProfile
var table: SimTable
## THE CLUB, when the licence has been bought (specs/m2-content.md §1). Null otherwise, and
## every call site guards on it — an M1 career must play exactly the Night it played before.
var club: SimClub = null

var seconds: float = 0.0
var shots: int = 0
var wasted_shots: int = 0
var wash_passes: int = 0
## Wash shots that moved nothing because tonight's laundering cap was already spent.
var wash_dead: int = 0
var collects: int = 0
var auto_collects: int = 0
var spin_segments: int = 0
var guys_lost: int = 0
var tilts: int = 0
var limps: int = 0
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
var _deck_rate: float = 1.0
var _spin_kick: float = 0.0
var _last_group: StringName = &""
var _watch_switches: bool = false
## Seconds of half-value play left on an insured TILT, and whether tonight's one policy has
## already been claimed (`muscle.insurance_policy`).
var _limp_left: float = 0.0
var _limp_used: bool = false
## Manny's clock (`auto_collect_interval`).
var _collect_in: float = 0.0
## Storefront-poll clock for the Collection Round trigger (`NightController.STOREFRONT_POLL`).
var _collect_poll: float = 0.0
## The guy the line-up is currently pointing at — his traits are on the money path.
var _guy: Dictionary = {}
var _guy_slot: int = -1
var _lineup: Array[Dictionary] = []


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
	_collect_in = state.stats.auto_collect_interval()
	for hw in table.storefronts:
		_fronts[hw] = {"state": &"armed", "down": 0, "timer": 0.0}
	state.heat.raid_triggered.connect(_on_raid_triggered)
	# `HeatMeter.raid_triggered` latches. `NightController` only listens during a Night, but
	# `Game._process` ticks the meter in EVERY state — so a meter that crosses 100 at The
	# Count (crediting the earn window a Night left behind) latches with nobody connected, and
	# no raid can ever fire again. Mirrored exactly, and counted, because it is a real bug.
	if state.heat.is_raid_pending():
		state.raids_latched += 1
	_watch_switches = _jobs_watch_switches()
	if table.deck != null:
		club = SimClub.new(state, profile, table, _rng)
		_deck_rate = club.rate()

	_lineup = []
	for g in state.bench.available():
		if _lineup.size() >= GUYS_PER_NIGHT:
			break
		_lineup.append(g)

	if _lineup.size() < GUYS_PER_NIGHT:
		state.short_lineups += 1

	for i in _lineup.size():
		_guy_slot = i
		_guy = _lineup[i]
		state.set_fielded([_guy])
		state.jobs.begin_ball(i)
		var alive := _serve()
		# A Meeting the guy took with him ends here: one ball left is not the crew out
		# together, and the man still standing is the one who is about to be pinched anyway.
		if club != null:
			club.on_night_end()
		# `_guy` may not be `_lineup[i]` any more — a Family Meeting can promote the survivor
		# into this slot, and it is the man actually holding the ball who goes inside.
		if alive >= SURVIVE_SECONDS:
			state.bench.survived_night(_guy)
		state.bench.pinch(_guy, _raid_left > 0.0)
		if _raid_left > 0.0:
			_end_raid(false)
		guys_lost += 1
		state.guys_pinched += 1
		state.combo.reset()
		state.set_fielded([])
		_advance(_beat(PINCH_BEAT))

	state.heat.raid_triggered.disconnect(_on_raid_triggered)
	var summary := state.end_night({
		"guys_fielded": _lineup.size(),
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
	summary["sim_auto_collects"] = auto_collects
	summary["sim_spin_segments"] = spin_segments
	summary["sim_by_group"] = by_group
	summary["sim_deck_seconds"] = club.deck_seconds if club != null else 0.0
	summary["sim_deck_visits"] = club.visits if club != null else 0
	summary["sim_meeting_seconds"] = club.meeting_seconds if club != null else 0.0
	summary["sim_limps"] = limps
	return summary


## THE COMMISSION (specs/m2-content.md §5): the Night The Count sent to a fight. The guys are
## fielded and lost exactly as usual and the Night is exactly as long, but the economy is off
## — `Game.economy_paused()` suppresses every payout — so the fight pays the purse and the
## table pays nothing at all. Win or lose is one draw against the profile; a loss costs the
## Night and nothing else, and The Count offers the rematch (docs/05 §6).
static func play_boss(p_state: SimState, p_profile: SimProfile, fight_id: StringName,
		rng: RandomNumberGenerator) -> Dictionary:
	var n := SimNight.new()
	n.state = p_state
	n.profile = p_profile
	n._rng = rng
	return n._run_boss_night(fight_id)


func _run_boss_night(fight_id: StringName) -> Dictionary:
	state.start_night()
	state.commission.begin_fight(fight_id)
	state.boss_nights += 1
	if state.boss_first_night.is_empty():
		state.boss_first_night = {"night": state.night_no, "clock": state.clock}
	var lineup: Array[Dictionary] = []
	for g in state.bench.available():
		if lineup.size() >= GUYS_PER_NIGHT:
			break
		lineup.append(g)
	# No table money means no reason to run the shot loop: what a fight costs is the clock,
	# the three guys and the Heat that keeps decaying while nobody is earning.
	for guy in lineup:
		state.set_fielded([guy])
		var alive := _draw_ball_seconds()
		_advance(alive)
		if alive >= SURVIVE_SECONDS:
			state.bench.survived_night(guy)
		state.bench.pinch(guy, false)
		guys_lost += 1
		state.guys_pinched += 1
		state.set_fielded([])
		_advance(_beat(PINCH_BEAT))
	var won := _rng.randf() < profile.boss_win_chance(fight_id)
	var result := state.boss_finished(fight_id, won)
	var summary := state.end_night({
		"guys_fielded": lineup.size(),
		"guys_lost": guys_lost,
		"tilts": 0,
		"raid": "",
		"boss": result,
	})
	summary["sim_seconds"] = seconds
	summary["sim_shots"] = 0
	summary["sim_wasted"] = 0
	summary["sim_wash_passes"] = 0
	summary["sim_wash_dead"] = 0
	summary["sim_collects"] = 0
	summary["sim_auto_collects"] = 0
	summary["sim_spin_segments"] = 0
	summary["sim_by_group"] = {}
	summary["sim_deck_seconds"] = 0.0
	summary["sim_deck_visits"] = 0
	summary["sim_meeting_seconds"] = 0.0
	summary["sim_limps"] = 0
	summary["sim_boss"] = result
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
		var insured := tilted and state.stats.flag(&"insurance_policy") and not _limp_used
		if tilted and not insured:
			span *= _rng.randf()
		var ran := _run(span)
		alive += ran
		if tilted:
			tilts += 1
			state.tilts += 1
			state.heat.add_flat(TILT_HEAT)
			if not insured:
				break
			# `insurance_policy` (T5): the guy limps at half value for ten seconds instead of
			# going inside. One policy a Night, and the ball is still his.
			_limp_used = true
			_limp_left = INSURANCE_LIMP_SECONDS
			limps += 1
			continue
		# The ball is down. During a Family Meeting that is not the end of the guy — the OTHER
		# man is still working, so one of them is pinched and play carries on (SimClub).
		if club != null and club.meeting_active():
			club.end_meeting(true)
			_take_promotion()
			continue
		if ran <= BALL_SAVE_SECONDS and _saves_left > 0:
			# Drained inside the save window: the charge buys the same guy another ball.
			_saves_left -= 1
			_advance(_beat(BALL_SAVE_BEAT))
			continue
		break
	return alive


## The survivor of a Meeting takes over the line-up slot of the man who drained
## (`NightController._promote_survivor`): from here on HE is the guy on the table.
func _take_promotion() -> void:
	if club == null or club.promote_to.is_empty():
		return
	_guy = club.promote_to
	club.promote_to = {}
	if _guy_slot >= 0 and _guy_slot < _lineup.size():
		_lineup[_guy_slot] = _guy
	state.set_fielded([_guy])


## Advance `span` seconds of live ball, firing shots as they arrive.
##
## `span` is the ball's DRAIN clock, and the Club is only PARTLY on it. The deck has no floor
## and its return lane delivers everything below the mini-bats to the right inlane
## (`ClubDeck.RETURN_PATH`), so falling off the Club costs the trip, not the ball — but the
## trip ends with a live ball dropped into an inlane, and that has to be caught like anything
## else. Deck seconds therefore spend the drain clock at `DECK_DRAIN_SHARE` of normal rather
## than not at all, which is why `alive` can exceed the drawn span but not indefinitely.
func _run(span: float) -> float:
	var t := 0.0
	var lived := 0.0
	while t < span - 1.0e-6:
		var dt := minf(minf(_next_shot, span - t), MAX_STEP)
		dt = maxf(dt, 1.0e-6)
		_advance(dt)
		lived += dt
		t += dt * (DECK_DRAIN_SHARE if _upstairs() else 1.0)
		_next_shot -= dt
		if _next_shot <= 1.0e-6:
			_next_shot = _draw_gap()
			_shoot()
	return lived


func _upstairs() -> bool:
	return club != null and club.upstairs


## Time passing, with nobody shooting: the clocks the flow lane ticks every physics frame.
func _advance(dt: float) -> void:
	if dt <= 0.0:
		return
	seconds += dt
	state.play_clock += dt
	state.clock += dt
	state.heat.tick(dt)
	state.peak_heat = maxf(state.peak_heat, state.heat.value)
	state.band_seconds[state.heat.band()] = float(state.band_seconds[state.heat.band()]) + dt
	state.combo.tick(dt)
	state.jobs.tick(dt, state.heat.value)
	_limp_left = maxf(_limp_left - dt, 0.0)
	_tick_idle(dt)
	_tick_wash(dt)
	_tick_crew(dt)
	_spin_advance(dt)
	_tick_hardware(dt)
	_tick_wire(dt)
	_tick_collection(dt)
	_wash_cool = maxf(_wash_cool - dt, 0.0)
	if club != null:
		var was_up := club.upstairs
		club.tick(dt)
		if was_up and not club.upstairs:
			# Down the return lane and back on the main playfield: a different menu, a
			# different cadence, and no chain carried across the trip.
			_take_promotion()
			_last_group = &""
			_next_shot = _draw_gap()
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
	if per_sec > 0.0 and _storefront_armed():
		state.launder(per_sec * dt, state.launder_cap_left())
	# Nussbaum washes whether or not a shop is open — that is what the accountant is FOR
	# (`auto_launder_per_sec`, specs/m2-content.md §2). Same per-Night cap as everything else.
	var auto := state.stats.auto_launder_per_sec()
	if auto > 0.0:
		state.launder(auto * dt, state.launder_cap_left())


## `NightController._tick_crew`: Manny (`auto_collect_interval`) walks a till every N seconds
## and hands the money in. He can only work a shop that is actually open — an empty block
## costs him a beat, not the whole interval, because he is standing right there.
func _tick_crew(dt: float) -> void:
	var every := state.stats.auto_collect_interval()
	if every <= 0.0:
		return
	_collect_in -= dt
	if _collect_in > 0.0:
		return
	var open_shop := &""
	for hw: Variant in _fronts:
		if (_fronts[hw] as Dictionary)["state"] == &"open":
			open_shop = hw
			break
	if open_shop == &"":
		_collect_in = minf(every, AUTO_COLLECT_RETRY)
		return
	_collect_in = every
	auto_collects += 1
	_collect_from(open_shop)


## `NightController._tick_wire`: every 90 s of play the tote board draws 00–99 and the
## spinner's session count is the ticket (docs/05 §4).
func _tick_wire(dt: float) -> void:
	if not state.stats.hardware_unlocked(&"wire_bank") or not state.wire.tick(dt):
		return
	var ticket := state.spin_segments_total
	if state.stats.flag(&"wiretap_wire") and _rng.randf() < profile.target_discipline * WIRETAP_AIM:
		# Fifteen seconds of warning and a spinner that moves the ticket one segment at a
		# time: a player who can count lands the exact number on purpose.
		ticket = state.wire.peek()
	state.wire_draw(ticket)


## `NightController._tick_collection`: all three banks standing at once starts a 25 s round.
func _tick_collection(dt: float) -> void:
	state.collection.tick(dt)
	_collect_poll -= dt
	if _collect_poll > 0.0:
		return
	_collect_poll = STOREFRONT_POLL
	if state.collection.active or not _all_storefronts_armed():
		return
	if state.collection.on_all_armed():
		state.collection_rounds += 1


func _all_storefronts_armed() -> bool:
	if _fronts.size() < int(Switches.COVER_SIZE.get(&"storefronts", 3)):
		return false
	for hw: Variant in _fronts:
		if (_fronts[hw] as Dictionary)["state"] != &"armed":
			return false
	return true


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
	var menu := table.deck if _upstairs() else table
	if _last_group != &"" and _last_group != &"laundry" and _rng.randf() < profile.cluster:
		var same := menu.pick_in_group(_last_group, _rng)
		if not same.is_empty():
			return same
	return menu.pick(_rng)


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
		SimTable.Kind.RAMP:
			_shoot_staircase(shot)
		SimTable.Kind.ROULETTE:
			_earn(&"casino", shot["base_big"], shot["id"])
			club.roulette()
		SimTable.Kind.REEL:
			# The reel pays its courtesy switch only when a target was actually there to drop.
			if club.reel(_reel_column(shot["id"])):
				_earn(&"casino", shot["base_big"], shot["id"])
			else:
				wasted_shots += 1
		SimTable.Kind.HIGH_ROLLER:
			var held := club.high_roller()
			if held > 0.0:
				_advance(held)
			else:
				wasted_shots += 1
		SimTable.Kind.BACKROOM:
			club.backroom()


## The Staircase mouth: a SPEED gate, not a switch. A shot with the pace climbs, pays the
## ramp and opens a deck visit; one without it is simply not taken and the ball carries on up
## the corridor (`ClubDeck` STAIR_ENTRY_SPEED, and `SimClub.try_climb`).
func _shoot_staircase(shot: Dictionary) -> void:
	if club == null or not club.live() or not club.try_climb():
		wasted_shots += 1
		return
	_earn(&"ramps", shot["base_big"], shot["id"])
	club.enter_deck()
	_last_group = &""
	_next_shot = _draw_gap()


static func _reel_column(id: StringName) -> int:
	return maxi(String(id).right(1).to_int() - 1, 0)


## The single money path, plus the switch event the flow lane forwards to Jobs.
func _earn(group: StringName, base: BigMoney, id: StringName) -> void:
	if _watch_switches:
		state.jobs.on_switch(id, group)
	var value := base if _limp_left <= 0.0 else base.mul(INSURANCE_LIMP_VALUE)
	var got := state.earn_switch(group, value, {"switch": id})
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
	# The Wire's ticket is the spinner's count since boot, not since roll call.
	state.spin_segments_total += n
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
			_collect_from(hw)
		_:
			wasted_shots += 1


## Cash out one open till. The Collection Round watches these: three in one 25 s window and
## the last one pays its value again, ☆10 lands, and the back room lights up (docs/05 §3).
func _collect_from(hw: StringName) -> void:
	var f: Dictionary = _fronts[hw]
	var value := SimTable.collect_value(hw, state.stats, state.catalog)
	_earn(&"storefronts", value, StringName(String(hw) + "_collect"))
	state.jobs.on_storefront(hw)
	collects += 1
	f["state"] = &"cooldown"
	f["down"] = 0
	f["timer"] = SimTable.STOREFRONT_REARM_SEC
	if state.collection.on_collected(hw):
		state.collection_completed(hw, value)


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
		state.earn_clean(state.wallet.dirty.mul(SimState.RAID_CLEAN_PAYOUT), &"raid")
		state.add_respect(SimState.RESPECT_RAID_SURVIVED, &"raid")
		state.raids_survived += 1
	else:
		raid_result = "lost"
		# `rain_insurance` (T5): one confiscation a Night is simply not paid.
		if state.stats.flag(&"rain_insurance") and not state.night_insured:
			state.night_insured = true
			state.raids_insured += 1
		else:
			state.wallet.confiscate_dirty(Rates.RAID_CONFISCATE_FRACTION)
		state.raids_lost += 1
	state.heat.reset_after_raid(survived)


# --- draws ---------------------------------------------------------------------------


## Ball survival: a floor plus an exponential tail, scaled by the guard rails the Ledger has
## bought. Exponential because pinball drains are close to memoryless once the ball is in
## play — the risk per second barely depends on how long you have already survived.
func _draw_ball_seconds() -> float:
	var scale := ball_time_scale(state.stats)
	var tail := maxf(profile.ball_seconds_mean - profile.ball_seconds_min, 1.0)
	var span := (profile.ball_seconds_min + _expo(tail)) * scale
	if _raid_left > 0.0:
		span /= _raid_hazard()
	return span


## Everything the Ledger has bought that keeps a ball alive longer, in one place so the
## projection and the sim cannot disagree about what a guard rail is worth.
static func ball_time_scale(stats: Stats) -> float:
	var scale := 1.0
	if stats.hardware_unlocked(&"inlane_guides"):
		scale *= GUIDES_BALL_TIME
	# Each kicker is one outlane bought back, and Big Sal's shorter cooldown means it is ready
	# more of the time (`kickback_cooldown_mult` runs 1.0 down toward 0).
	var ready := clampf(1.0 / maxf(stats.kickback_cooldown_mult(), 0.01), 1.0,
			KICKBACK_COOLDOWN_GAIN_MAX)
	for side in [&"kickback_left", &"kickback_right"]:
		if stats.hardware_unlocked(side):
			scale *= 1.0 + (KICKBACK_BALL_TIME - 1.0) * ready
	return scale


## `police_scanner` (T5): ten seconds of warning before the raid hardware goes live means
## nobody is caught mid-ramp by the Captain's magnet.
func _raid_hazard() -> float:
	return RAID_HAZARD * (SCANNER_RAID_HAZARD if state.stats.flag(&"police_scanner") else 1.0)


func _draw_gap() -> float:
	var rate := _deck_rate if _upstairs() else _shot_rate
	return _expo(1.0 / maxf(rate, 0.01))


## A between-balls beat, shortened by Skids (`serve_speed_mult`): the table divides its serve
## duration by it, so a fast server is more Nights per session, not more money per Night.
func _beat(sec: float) -> float:
	return sec / maxf(state.stats.serve_speed_mult(), 0.1)


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


func _tilt_chance() -> float:
	return tilt_chance_for(profile, state.stats)


## More warnings before the Inspector calls it means proportionally more nudging per tilt, and
## `inspector_vacation` buys twenty seconds a Night where the warnings do not count at all.
static func tilt_chance_for(p: SimProfile, stats: Stats) -> float:
	var leans := maxi(stats.tilt_leans(), 1)
	var chance := p.tilt_per_ball * float(Stats.BASE_TILT_LEANS) / float(leans)
	if stats.flag(&"inspector_vacation"):
		chance *= 1.0 - INSPECTOR_TILT_CUT
	return chance


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


## STILL NOT MODELLED (M3 content, specs/m3-fall-rise.md): mystery briefcases, smuggling
## runs, heists, elections, Federal Heat and the RICO raid. The Lucky trait's
## `briefcase_odds_add` is therefore inert here, exactly as it is in the shipped game.
