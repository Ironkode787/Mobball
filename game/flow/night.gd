class_name NightController
extends Node
## One Night: roll call, work, and the hand-off to The Count (docs/01 §3).
##
## This is the only place that knows about both the table and the session model. It fields
## guys off the Bench one at a time, serves their ball, converts drains into pinches, runs
## the idle trickle, the laundering shots, the skill shot, the combo clock and the Raid,
## and hands `Game.end_night()` a summary when the last guy is inside.
##
## Everything is timed on the physics tick, never wall time, so a headless sim that steps
## physics frames sees exactly the Night a player would.
##
## Defensive by design: the table lane is rebuilding `table_main.tscn` in parallel, so every
## M1 table API is called through a `has_method` guard and the flow degrades to "the M0
## alley still plays" rather than erroring.

## Emitted when the last guy is pinched, just before Game.end_night().
signal night_finished(summary: Dictionary)

const GUYS_PER_NIGHT := 3
## Seconds of mugshot beat between guys — "a pinched guy is a beat, not a punishment".
const PINCH_BEAT := 1.2
## Ball-save window after a launch, per charge from `stats.ball_saves()`.
const BALL_SAVE_SECONDS := 8.0
## The rubber-band plunger fires at a fixed power until `plunger_bands` is bought.
const FIXED_PLUNGER_POWER := 0.75
## A ball left sitting in the lane launches itself, so a Night can never stall.
const AUTO_LAUNCH_SECONDS := 12.0
## Skill-shot lane cycle and how long after the launch the window stays open.
const SKILL_CYCLE := 1.5
const SKILL_WINDOW := 6.0
const SKILL_LANES := 3
## TILT is a Heat spike as well as a pinch (docs/01 §5).
const TILT_HEAT := 5.0
## One wash per pass: the laundromat door and the loop switch can both report the same run.
const WASH_COOLDOWN := 0.5
## A guy who worked this long banks the Night as experience (docs/01 §4).
const SURVIVE_SECONDS := 60.0
## Heat band that flips the music into its "hot" mix (docs/03 §4: 70+ is the tense band).
const HOT_BAND := 2

var table: Node2D = null
var nudge: NudgeController = null
var input: InputController = null
var raid: RaidMode = null

## Sim hook: overrides RaidMode's 45 s when positive, so a headless run can exercise both
## raid branches without spending a minute and a half of wall clock on them.
var raid_duration: float = 0.0

var lineup: Array[Dictionary] = []
var guy_index: int = -1
var guy_alive: float = 0.0
var guys_lost: int = 0
var tilts: int = 0
var saves_left: int = 0
var running: bool = false

var _rank_before: int = 0
var _raid_result: String = ""
var _raid_payout: BigMoney = BigMoney.zero()
var _raid_confiscated: BigMoney = BigMoney.zero()
var _serve_in: float = -1.0
var _save_window: float = 0.0
var _idle_accum: float = 0.0
var _wash_cooldown: float = 0.0
var _lane_idle: float = 0.0
var _skill_open: bool = false
var _skill_timer: float = 0.0
var _skill_cycle: float = 0.0
var _skill_lane: int = 0
var _lanes_zero_based: bool = false
var _bridge_scored: bool = false
## The table reports wash passes / lit-lane rolls itself, so flow stops guessing from ids.
var _wash_from_signal: bool = false
var _lanes_from_signal: bool = false
var _plunger: Plunger = null
## What happens when the between-balls beat runs out: &"same" (ball save), &"next", &"end".
var _after_beat: StringName = &""


func _ready() -> void:
	set_physics_process(false)


# =================================================================== setup =====


func bind(p_table: Node2D, p_nudge: NudgeController = null, p_input: InputController = null) -> void:
	table = p_table
	nudge = p_nudge
	input = p_input
	_plunger = TableAPI.prop(table, "plunger") as Plunger


## Roll call. `Game.start_night()` has already ticked the Bench and rolled the Jobs.
func start() -> void:
	if running:
		return
	running = true
	_rank_before = Game.rank
	guys_lost = 0
	tilts = 0
	_raid_result = ""
	_raid_payout = BigMoney.zero()
	_raid_confiscated = BigMoney.zero()
	saves_left = Game.stats.ball_saves()
	_bridge_scored = _needs_score_bridge()

	lineup = []
	for g in Game.bench.available():
		if lineup.size() >= GUYS_PER_NIGHT:
			break
		lineup.append(g)

	if TableAPI.has_property(table, "auto_respawn"):
		table.set("auto_respawn", false)
	if nudge != null:
		nudge.meter.max_warnings = Game.stats.tilt_leans()
		nudge.clear_tilt()
	_set_raid_visual(false)

	Events.switch_hit.connect(_on_switch_hit)
	Events.scored.connect(_on_scored)
	Events.storefront_collected.connect(_on_storefront_collected)
	Events.ball_launched.connect(_on_ball_launched)
	Events.tilted.connect(_on_tilted)
	Game.heat.raid_triggered.connect(_on_raid_triggered)
	Game.heat.band_changed.connect(_on_band_changed)
	_connect_table(&"ball_lost", _on_ball_lost)
	# The M1 table reports these itself; without them flow falls back to reading switch ids.
	_wash_from_signal = _connect_table(&"laundromat_pass", _wash_pass)
	_lanes_from_signal = _connect_table(&"rollover_rolled", _on_rollover_rolled)
	_connect_table(&"bribe_offered", _on_bribe_offered)

	guy_index = -1
	_next_guy()
	set_physics_process(true)


## Tear the Night down without ending it (scene change, app quit).
func stop() -> void:
	if not running:
		return
	running = false
	set_physics_process(false)
	_set_raid_visual(false)
	if raid != null and is_instance_valid(raid):
		raid.abort()
	TableAPI.call_if(table, "despawn_ball")


func current_guy() -> Dictionary:
	if guy_index < 0 or guy_index >= lineup.size():
		return {}
	return lineup[guy_index]


func guys_left() -> int:
	return maxi(lineup.size() - guy_index - 1, 0)


# ============================================================== the clock =====


func _physics_process(delta: float) -> void:
	if not running:
		return
	Game.combo.tick(delta)
	Game.jobs.tick(delta, Game.heat.value)
	_tick_idle(delta)
	_tick_wash(delta)
	_wash_cooldown = maxf(_wash_cooldown - delta, 0.0)

	if _save_window > 0.0:
		_save_window = maxf(_save_window - delta, 0.0)
	if guy_index >= 0 and _ball() != null:
		guy_alive += delta
	_tick_skill(delta)
	_tick_plunger(delta)

	if _serve_in > 0.0:
		_serve_in -= delta
		if _serve_in <= 0.0:
			_serve_in = -1.0
			match _after_beat:
				&"same":
					_serve()
				&"next":
					_next_guy()
				_:
					_finish()


## The idle layer ticks during play too (docs/03 §6) — the rackets do not stop earning
## just because you are at the table.
func _tick_idle(delta: float) -> void:
	var rate := Game.stats.idle_rate_total()
	if rate == null or not rate.is_positive():
		return
	_idle_accum += delta
	while _idle_accum >= 1.0:
		_idle_accum -= 1.0
		Game.earn_idle(rate)


## Front businesses wash while their bank is armed (docs/03 §2 v1.5).
func _tick_wash(delta: float) -> void:
	var per_sec := Game.stats.passive_wash_per_sec()
	if per_sec <= 0.0 or not _storefront_armed():
		return
	Game.launder(per_sec * delta, Game.launder_cap_left())


func _tick_skill(delta: float) -> void:
	if not _skill_open:
		return
	_skill_timer -= delta
	if _skill_timer <= 0.0:
		_close_skill_window()
		return
	_skill_cycle -= delta
	if _skill_cycle <= 0.0:
		_skill_cycle += SKILL_CYCLE
		_skill_lane = (_skill_lane + 1) % _lane_count()
		_light_lane(_skill_lane)


## How many top lanes the delivery window cycles through.
func _lane_count() -> int:
	return maxi(int(TableAPI.call_if(table, "rollover_count", [], SKILL_LANES)), 1)


## Fixed-power plunger until `plunger_bands` is owned: the charge is pinned rather than the
## plunger disabled, so touch, keys and scripted launches all still work.
func _tick_plunger(delta: float) -> void:
	if _plunger == null or not is_instance_valid(_plunger):
		return
	# A BandedPlunger enforces the rubber band itself; this is the fallback for a table
	# whose plunger does not know about `plunger_bands` yet.
	if not (_plunger is BandedPlunger) and not Game.stats.flag(&"plunger_bands") \
			and _plunger.charging:
		_plunger.power = FIXED_PLUNGER_POWER
	if _plunger.ball_ready():
		_lane_idle += delta
		if _lane_idle >= AUTO_LAUNCH_SECONDS:
			_lane_idle = 0.0
			# A BandedPlunger clamps this back to the rubber band when bands are off.
			_plunger.launch(1.0)
	else:
		_lane_idle = 0.0


# ============================================================ guy handling =====


func _next_guy() -> void:
	guy_index += 1
	if guy_index >= lineup.size():
		_beat(&"end", PINCH_BEAT)
		return
	guy_alive = 0.0
	Game.jobs.begin_ball(guy_index)
	_serve()


## Nothing happens for a moment: the mugshot slides in, then `what` happens.
func _beat(what: StringName, seconds: float) -> void:
	_after_beat = what
	_serve_in = maxf(seconds, 0.01)


func _serve() -> void:
	if table == null or not is_instance_valid(table):
		return
	Game.combo.reset()
	if nudge != null:
		nudge.clear_tilt()
	_revive_flippers()
	_lane_idle = 0.0
	TableAPI.call_if(table, "spawn_ball")
	_open_skill_window()


## A drain. Ball save first, then the pinch.
func _on_ball_lost(_ball_node: Node = null) -> void:
	if not running or _serve_in > 0.0:
		return
	if _save_window > 0.0 and saves_left > 0:
		saves_left -= 1
		_save_window = 0.0
		AudioDirector.play(&"kickback")
		_beat(&"same", 0.4)
		return
	_lose_guy()


func _on_tilted() -> void:
	if not running or _serve_in > 0.0:
		return
	tilts += 1
	Game.heat.add_flat(TILT_HEAT)
	# The Inspector takes this guy, and the save window does not cover his own fault.
	_save_window = 0.0
	TableAPI.call_if(table, "despawn_ball")
	_lose_guy()


## He's inside. A pinch is a beat, not a punishment (docs/01 §8): mugshot, one-liner,
## next man up — or The Count if he was the last of tonight's three.
func _lose_guy() -> void:
	var guy := current_guy()
	if guy.is_empty():
		return
	if guy_alive >= SURVIVE_SECONDS:
		Game.bench.survived_night(guy)
	var raid_stretch := raid != null and is_instance_valid(raid) and raid.active
	Game.bench.pinch(guy, raid_stretch)
	guys_lost += 1
	if guys_lost >= 2:
		Game.mark_reveal_event(&"first_double_pinch")
	Game.combo.reset()
	AudioDirector.play(&"guy_pinched")
	Events.guy_pinched.emit(guy)
	_close_skill_window()
	if raid_stretch:
		raid.on_guy_lost()
	_beat(&"end" if guy_index + 1 >= lineup.size() else &"next", PINCH_BEAT)


func _finish() -> void:
	if not running:
		return
	running = false
	set_physics_process(false)
	_close_skill_window()
	if raid != null and is_instance_valid(raid):
		raid.abort()
	_set_raid_visual(false)
	TableAPI.call_if(table, "despawn_ball")

	var roster: Array = []
	for g in lineup:
		roster.append({"id": int(g["id"]), "name": String(g["name"]), "state": String(g["state"])})
	var summary := {
		"guys": roster,
		"guys_fielded": lineup.size(),
		"guys_lost": guys_lost,
		"tilts": tilts,
		"raid": _raid_result,
		"raid_payout": _raid_payout,
		"confiscated": _raid_confiscated,
		"rank_before": _rank_before,
		"rank_up": Game.rank > _rank_before,
	}
	night_finished.emit(summary)
	Game.end_night(summary)


# ================================================================ scoring =====


## The M0 table still pays through `Events.scored`; the M1 table pays through
## `Game.earn_switch` itself. Bridging only when nobody else is doing it keeps the single
## money path single no matter which table is loaded.
func _on_scored(id: StringName, value: int) -> void:
	if not running or not _bridge_scored or value <= 0:
		return
	Game.earn_switch(Switches.group_for(id), BigMoney.from_float(float(value)), {"switch": id})


func _on_switch_hit(id: StringName, _ball_node: Node2D, _strength: float) -> void:
	if not running:
		return
	var group := Switches.group_for(id)
	Game.jobs.on_switch(id, group)
	if not _wash_from_signal and (group == &"laundry" or String(id).begins_with("laundromat")):
		_wash_pass()
	if group == &"rollovers":
		if not _lanes_from_signal:
			_check_skill_shot(id)
	elif group != &"cop":
		# Anything that is not a top lane means the ball is in play: the delivery window
		# closes on the player's first real shot.
		_close_skill_window()


func _on_storefront_collected(id: StringName) -> void:
	if not running:
		return
	AudioDirector.play(&"storefront_collect")
	Game.jobs.on_storefront(id)
	# Lucky's door doubles as the wash pass — unless the table says so itself.
	if not _wash_from_signal and String(id).findn("laundromat") >= 0:
		_wash_pass()


## The beat cop is holding out his hat (table `bribe_offered`): flow owns the price.
func _on_bribe_offered() -> void:
	if running:
		Game.bribe()


## One laundromat pass: wash `launder_rate` of held dirty against tonight's cap.
func _wash_pass() -> void:
	if _wash_cooldown > 0.0:
		return
	_wash_cooldown = WASH_COOLDOWN
	var rate := Game.stats.launder_rate()
	if rate <= 0.0:
		return
	var moved := Game.launder(rate, Game.launder_cap_left())
	if moved.is_positive():
		AudioDirector.play(&"laundromat_wash")


# ============================================================= skill shot =====


func _open_skill_window() -> void:
	if not Game.stats.hardware_unlocked(&"rollovers"):
		return
	_skill_open = true
	_skill_timer = SKILL_WINDOW + AUTO_LAUNCH_SECONDS
	_skill_cycle = SKILL_CYCLE
	_skill_lane = 0
	_light_lane(_skill_lane)


func _on_ball_launched(_ball_node: Node2D, _power: float) -> void:
	if not running:
		return
	_save_window = BALL_SAVE_SECONDS if saves_left > 0 else 0.0
	_lane_idle = 0.0
	if _skill_open:
		_skill_timer = minf(_skill_timer, SKILL_WINDOW)


## The table reports the lane and whether it was the lit one — no id parsing needed.
func _on_rollover_rolled(_index: int, was_lit: bool) -> void:
	if not running or not _skill_open:
		return
	_close_skill_window()
	if was_lit:
		Game.award_skill_shot()


## Fallback for a table that only emits `switch_hit`: work the lane out of the switch id.
func _check_skill_shot(id: StringName) -> void:
	if not _skill_open:
		return
	var idx := Switches.index_of(id)
	if idx == 0:
		_lanes_zero_based = true
	var lane := idx if _lanes_zero_based else idx - 1
	_close_skill_window()
	if lane == _skill_lane:
		Game.award_skill_shot()


func _close_skill_window() -> void:
	if not _skill_open:
		return
	_skill_open = false
	_light_lane(-1)


func _light_lane(index: int) -> void:
	TableAPI.call_if(table, "set_lit_rollover", [index])


# =================================================================== raid =====


func _on_raid_triggered() -> void:
	if not running or (raid != null and is_instance_valid(raid) and raid.active):
		return
	raid = RaidMode.new()
	raid.name = "Raid"
	if raid_duration > 0.0:
		raid.duration = raid_duration
	add_child(raid)
	raid.finished.connect(_on_raid_finished)
	_set_raid_visual(true)
	raid.begin(table)


func _on_raid_finished(survived: bool) -> void:
	_set_raid_visual(false)
	if survived:
		_raid_result = "survived"
		_raid_payout = Game.wallet.dirty.mul(Game.RAID_CLEAN_PAYOUT)
		Game.wallet.earn_clean(_raid_payout)
		Game.add_respect(Game.RESPECT_RAID_SURVIVED, &"raid")
		Game.mark_reveal_event(&"first_raid_survived")
		AudioDirector.play(&"raid_win")
	else:
		_raid_result = "lost"
		_raid_confiscated = Game.wallet.confiscate_dirty(Rates.RAID_CONFISCATE_FRACTION)
		AudioDirector.play(&"raid_lose")
	Game.heat.reset_after_raid(survived)
	Events.raid_ended.emit(survived)
	AudioDirector.music_set_state(_music_state())
	if raid != null and is_instance_valid(raid):
		raid.queue_free()
		raid = null


func _on_band_changed(_band: int) -> void:
	if not running:
		return
	if raid != null and is_instance_valid(raid) and raid.active:
		return
	AudioDirector.music_set_state(_music_state())


func _music_state() -> StringName:
	if raid != null and is_instance_valid(raid) and raid.active:
		return &"raid"
	return &"hot" if Game.heat.band() >= HOT_BAND else &"calm"


## The table darkens for the raid; a plain modulate keeps it working on a table that has
## not shipped its own raid dressing yet.
func _set_raid_visual(on: bool) -> void:
	if table == null or not is_instance_valid(table):
		return
	TableAPI.call_if(table, "set_raid_active", [on])
	table.modulate = RaidMode.DARKEN if on else Color.WHITE


# ================================================================ helpers =====


## Connect one of the table's own signals if this table has it. Returns whether it did, so
## the caller knows whether to fall back to reading switch ids.
func _connect_table(signal_name: StringName, to: Callable) -> bool:
	if table == null or not is_instance_valid(table) or not table.has_signal(signal_name):
		return false
	if not table.is_connected(signal_name, to):
		table.connect(signal_name, to)
	return true


func _ball() -> Ball:
	return TableAPI.ball(table)


func _revive_flippers() -> void:
	for key: String in ["flipper_left", "flipper_right"]:
		var f: Variant = TableAPI.prop(table, key)
		if f is Flipper and is_instance_valid(f as Flipper):
			(f as Flipper).revive()
	if _plunger != null and is_instance_valid(_plunger):
		_plunger.enabled = true


## A storefront is armed unless the table says otherwise — the passive wash should not
## wait on an API that has not landed.
func _storefront_armed() -> bool:
	return bool(TableAPI.call_if(table, "storefront_armed", [], true))


## Does anyone else already pay through `Game.earn_switch`? The M1 table does; the M0 alley
## only emits `Events.scored`, so flow bridges it. Exactly one of the two, never both.
func _needs_score_bridge() -> bool:
	if table == null:
		return false
	if TableAPI.has_property(table, "pays_through_game"):
		return not bool(table.get("pays_through_game"))
	return not table.has_method("set_raid_active")
