class_name NightController
extends Node
## One Night: roll call, work, and the hand-off to The Count (docs/01 §3).
##
## This is the only place that knows about both the table and the session model. It fields
## guys off the Bench one at a time, serves their ball, converts drains into pinches, runs
## the idle trickle, the laundering shots, the skill shot, the combo clock and the Raid,
## and hands `Game.end_night()` a summary when the last guy is inside.
##
## M2 adds the modes that live on the Club deck and the block: the casino's auto-bets and
## Jackpots, the Family Meeting's second guy, the Wire's 90-second draws and the Collection
## Round's 25-second clock. All four are pure logic in their own files — this feeds them
## table events and a clock, and `Game` pays whatever they decide.
##
## Everything is timed on the physics tick, never wall time, so a headless sim that steps
## physics frames sees exactly the Night a player would.
##
## Multiball changes one deep assumption: a drain is no longer "the guy is gone, next man
## up". A drained ball pinches ITS OWN guy (the registry says which), and the line-up only
## advances when the LAST live ball is down. Ball-save windows are per ball instance for the
## same reason.
##
## Defensive by design: the table lane is rebuilding `table_main.tscn` in parallel, so every
## table API is called through a `has_method` guard and the flow degrades to "the M0 alley
## still plays" rather than erroring.

## Emitted when the last guy is pinched, just before Game.end_night().
signal night_finished(summary: Dictionary)

const GUYS_PER_NIGHT := 3
## Seconds of mugshot beat between guys — "a pinched guy is a beat, not a punishment".
const PINCH_BEAT := 1.2
## Ball-save window after a launch, per charge from `stats.ball_saves()`.
const BALL_SAVE_SECONDS := 8.0
## Grace on a ball that was put back into play mid-multiball: it did not come up the shooter
## lane, so it never got the launch window everything else gets.
const RESERVE_SAVE_SECONDS := 2.0
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
## Anything above this line is upstairs in the Club (the deck lives in negative y). A deck
## visit — the window the slots Jackpot has to be completed inside — ends when nothing is.
const DECK_LINE := 0.0
## Where the Family Meeting's second guy comes in, as an offset from the deck's own socket:
## on the deck, below the back room, above the mini bats. Derived from the table's geometry
## rather than restated, so the deck can move without this following it.
const MEETING_SPAWN_OFFSET := Vector2(270.0, -260.0)
## Outer band of the playfield width, each side, that counts as an outlane for the Slippery
## trait. Read against the table's own bounds so flow never hard-codes this table's posts.
const OUTLANE_BAND := 0.25
## How often the storefront banks are read for a Collection Round trigger.
const STOREFRONT_POLL := 0.25
## Gap between the tote board's three chimes.
const WIRE_ARPEGGIO_GAP := 0.09

var table: Node2D = null
var nudge: NudgeController = null
var input: InputController = null
var raid: RaidMode = null

## Sim hook: overrides RaidMode's 45 s when positive, so a headless run can exercise both
## raid branches without spending a minute and a half of wall clock on them.
var raid_duration: float = 0.0

var lineup: Array[Dictionary] = []
## Guys who joined mid-Night (the Family Meeting's second man). They are fielded and can be
## pinched like anyone, but they are not part of the three the Night is counted in.
var extras: Array[Dictionary] = []
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
## Per-ball save windows, keyed by instance id: `{"left": float, "free": bool}`. A free one
## is a grace (the Meeting's 8 s) and costs no charge; the rest spend `saves_left`.
var _saves: Dictionary = {}
## The Bench guy riding each live ball. `Balls` keeps the same map, but it erases its entry
## BEFORE it emits — by the time `ball_lost` reaches us the registry has already forgotten
## whose ball that was, so flow keeps the mirror it needs to pinch the right man.
var _ball_guys: Dictionary = {}
## Seconds each live ball has been out, keyed by instance id (specs/ball-registry.md: save
## windows and survival credit are per instance once there can be two of them).
var _ball_age: Dictionary = {}
## Guy id -> his one Slippery escape is spent.
var _slippery_used: Dictionary = {}
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
var _wire_enabled: bool = false
var _collect_poll: float = 0.0
## Guys whose ball was saved and is waiting to be put back on the table next tick.
var _reserve_queue: Array[Dictionary] = []
## `last_ball` fired; the Meeting ends unless a pending save puts a ball back first.
var _meeting_end_pending: bool = false
## Queued one-shots, each waiting `in` seconds after the one before it (the tote arpeggio).
var _arp: Array[Dictionary] = []


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
	_wire_enabled = Game.stats.hardware_unlocked(&"wire_bank")
	_saves.clear()
	_ball_guys.clear()
	_ball_age.clear()
	_slippery_used.clear()
	_arp.clear()
	_reserve_queue.clear()
	_meeting_end_pending = false
	extras = []

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
	if not Balls.last_ball.is_connected(_on_last_ball):
		Balls.last_ball.connect(_on_last_ball)
	_connect_table(&"ball_lost", _on_ball_lost)
	# The M1 table reports these itself; without them flow falls back to reading switch ids.
	_wash_from_signal = _connect_table(&"laundromat_pass", _wash_pass)
	_lanes_from_signal = _connect_table(&"rollover_rolled", _on_rollover_rolled)
	_connect_table(&"bribe_offered", _on_bribe_offered)
	# THE CLUB (specs/m2-content.md §1/§4). Hardware reports outcomes; flow owns the money.
	_connect_table(&"staircase_climbed", _on_staircase_climbed)
	_connect_table(&"roulette_landed", _on_roulette_landed)
	_connect_table(&"reels_state", _on_reels_state)
	_connect_table(&"high_roller_held", _on_high_roller_held)
	_connect_table(&"backroom_entered", _on_backroom_entered)
	# The table's own storefront signal carries the amount; the bus version does not, and the
	# Collection Round has to pay the last shop its value a second time.
	_connect_table(&"storefront_collected", _on_table_storefront)

	# Nights do not always open cold — coming off a survived raid the meter is still at 30.
	AudioDirector.music_set_state(_music_state())
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
	_release_night()


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
	_tick_reserves()
	_settle_meeting()
	Game.combo.tick(delta)
	Game.jobs.tick(delta, Game.heat.value)
	_tick_idle(delta)
	_tick_wash(delta)
	_wash_cooldown = maxf(_wash_cooldown - delta, 0.0)

	_tick_balls(delta)
	_tick_deck()
	_tick_wire(delta)
	_tick_collection(delta)
	_tick_arpeggio(delta)
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


## Per-ball clocks: how long each guy has been out, and how long his save window has left.
func _tick_balls(delta: float) -> void:
	for b in Balls.live():
		var id := b.get_instance_id()
		_ball_age[id] = float(_ball_age.get(id, 0.0)) + delta
	for key: Variant in _saves.keys():
		var row: Dictionary = _saves[key]
		row["left"] = maxf(float(row["left"]) - delta, 0.0)
		if float(row["left"]) <= 0.0:
			_saves.erase(key)
	var primary := _ball()
	guy_alive = _age_of(primary) if primary != null else guy_alive


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


## Queue of one-shots, each `in` seconds after the one before it. Only the head counts down,
## so the arpeggio keeps its spacing however the frames fall.
func _tick_arpeggio(delta: float) -> void:
	while not _arp.is_empty():
		var row: Dictionary = _arp[0]
		row["in"] = float(row["in"]) - delta
		if float(row["in"]) > 0.0:
			return
		AudioDirector.play(StringName(row["event"]))
		_arp.pop_front()


func _arpeggio(events: Array, gap: float) -> void:
	var first := true
	for e: Variant in events:
		_arp.append({"in": 0.0 if first else gap, "event": StringName(e)})
		first = false


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
	_bind_guy(_ball(), current_guy())
	Game.set_fielded(_live_guys())
	_open_skill_window()


## Put a saved ball back into play. With other balls still live a full serve is not an option
## — the table's `spawn_ball()` clears the primary first — so the save drops a fresh ball onto
## the playfield the way a kickback would, still carrying the same guy.
##
## The ball cannot be served from here: `ball_lost` reaches us out of the drain's
## `body_entered`, which fires while the physics server is flushing its queries, and adding a
## body then is an error. It is queued for the top of the next tick, the same way the table
## defers its own auto-respawn.
func _reserve(guy: Dictionary) -> void:
	if Balls.count() <= 0:
		_beat(&"same", 0.4)
		return
	_reserve_queue.append(guy)


func _tick_reserves() -> void:
	if _reserve_queue.is_empty():
		return
	var queued := _reserve_queue.duplicate()
	_reserve_queue.clear()
	for guy: Dictionary in queued:
		if Balls.count() <= 0:
			_beat(&"same", 0.4)
			continue
		var b: Variant = TableAPI.call_if(table, "spawn_extra_ball", [_reserve_point()], null)
		if not (b is Ball):
			_beat(&"same", 0.4)
			continue
		_bind_guy(b as Ball, guy)
		_arm_save(b as Ball, RESERVE_SAVE_SECONDS, true)
	Game.set_fielded(_live_guys())


func _reserve_point() -> Vector2:
	var at: Variant = TableAPI.call_if(table, "socket", [&"midfield"], null)
	return at if at is Vector2 else Vector2.ZERO


## A drain. Per-ball save first, then the trait escape, then the pinch.
func _on_ball_lost(ball_node: Node = null) -> void:
	if not running or _serve_in > 0.0:
		return
	var ball := ball_node as Ball
	var guy := _guy_riding(ball)
	var age := _age_of(ball)
	var save: Dictionary = _take_save(ball)
	var slipped := save.is_empty() and _try_slippery(guy, ball)
	_forget_ball(ball)
	if not save.is_empty():
		if not bool(save["free"]):
			saves_left -= 1
		AudioDirector.play(&"kickback")
		_reserve(guy)
		return
	if slipped:
		AudioDirector.play(&"kickback")
		AudioDirector.play(&"chime_b")
		_reserve(guy)
		return
	_lose_guy(guy, age)


func _on_tilted() -> void:
	if not running or _serve_in > 0.0:
		return
	tilts += 1
	Game.heat.add_flat(TILT_HEAT)
	# The Inspector takes this guy, and no save covers his own fault.
	var ball := _ball()
	var guy := _guy_riding(ball)
	var age := _age_of(ball)
	_take_save(ball)
	_forget_ball(ball)
	TableAPI.call_if(table, "despawn_ball")
	_lose_guy(guy, age)


## He's inside. A pinch is a beat, not a punishment (docs/01 §8): mugshot, one-liner,
## next man up — or The Count if he was the last one out there.
func _lose_guy(guy: Dictionary, age: float = 0.0) -> void:
	if guy.is_empty():
		return
	if age >= SURVIVE_SECONDS:
		Game.bench.survived_night(guy)
	var raid_stretch := raid != null and is_instance_valid(raid) and raid.active
	Game.bench.pinch(guy, raid_stretch)
	guys_lost += 1
	if guys_lost >= 2:
		Game.mark_reveal_event(&"first_double_pinch")
	AudioDirector.play(&"guy_pinched")
	Events.guy_pinched.emit(guy)

	if Balls.count() > 0:
		# Multiball: somebody is still working, so the Night does not move on. If the man who
		# just went inside was the one the line-up was pointing at, the survivor takes over
		# his slot — from here on he IS the guy on the table.
		_promote_survivor(guy)
		Game.set_fielded(_live_guys())
		return

	Game.combo.reset()
	Game.set_fielded([])
	Game.casino.close_visit()
	_close_skill_window()
	if raid_stretch:
		raid.on_guy_lost()
	_beat(&"end" if guy_index + 1 >= lineup.size() else &"next", PINCH_BEAT)


func _promote_survivor(lost: Dictionary) -> void:
	if guy_index < 0 or guy_index >= lineup.size():
		return
	if int(lineup[guy_index].get("id", -1)) != int(lost.get("id", -2)):
		return
	var survivor := _guy_on(Balls.primary())
	if not survivor.is_empty():
		lineup[guy_index] = survivor


func _finish() -> void:
	if not running:
		return
	running = false
	set_physics_process(false)
	_close_skill_window()
	if raid != null and is_instance_valid(raid):
		raid.abort()
	_set_raid_visual(false)
	_release_night()

	var roster: Array = []
	for g in lineup:
		roster.append(_roster_row(g, false))
	for g in extras:
		roster.append(_roster_row(g, true))
	var summary := {
		"guys": roster,
		"guys_fielded": lineup.size() + extras.size(),
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


static func _roster_row(g: Dictionary, from_meeting: bool) -> Dictionary:
	return {
		"id": int(g["id"]),
		"name": String(g["name"]),
		"state": String(g["state"]),
		"trait": String(g.get("trait", "")),
		"meeting": from_meeting,
	}


## Everything that must not outlive the Night: the extra balls a Meeting put on the table,
## the registry connection, and the guys' trait folds on the Heat meter.
func _release_night() -> void:
	if Balls.last_ball.is_connected(_on_last_ball):
		Balls.last_ball.disconnect(_on_last_ball)
	Game.meeting.end()
	Game.casino.close_visit()
	Game.set_fielded([])
	TableAPI.call_if(table, "despawn_ball")
	for b in Balls.live():
		if is_instance_valid(b):
			b.queue_free()
	_saves.clear()
	_ball_guys.clear()
	_ball_age.clear()
	_arp.clear()
	_reserve_queue.clear()
	_meeting_end_pending = false


# ============================================================ ball bookkeeping =====


func _bind_guy(ball: Ball, guy: Dictionary) -> void:
	if ball == null or not is_instance_valid(ball) or guy.is_empty():
		return
	Balls.set_guy(ball, guy)
	_ball_guys[ball.get_instance_id()] = guy


## Strictly who is on this ball — empty if nobody was ever attached to it.
func _guy_on(ball: Ball) -> Dictionary:
	if ball == null:
		return {}
	var mine: Variant = _ball_guys.get(ball.get_instance_id(), null)
	if mine is Dictionary:
		return mine
	return Balls.guy_for(ball)


## Who to pinch for this ball. Falls back to the line-up's current man so a table that never
## registered its ball (the M0 alley) still plays a normal single-ball Night.
func _guy_riding(ball: Ball) -> Dictionary:
	var g := _guy_on(ball)
	return g if not g.is_empty() else current_guy()


func _live_guys() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in Balls.live():
		var g := _guy_on(b)
		if not g.is_empty():
			out.append(g)
	if out.is_empty() and not current_guy().is_empty() and _ball() != null:
		out.append(current_guy())
	return out


func _forget_ball(ball: Ball) -> void:
	if ball == null:
		return
	var id := ball.get_instance_id()
	_ball_guys.erase(id)
	_ball_age.erase(id)
	_saves.erase(id)


func _age_of(ball: Ball) -> float:
	if ball == null:
		return 0.0
	return float(_ball_age.get(ball.get_instance_id(), 0.0))


func _arm_save(ball: Ball, seconds: float, free: bool) -> void:
	if ball == null or not is_instance_valid(ball) or seconds <= 0.0:
		return
	_saves[ball.get_instance_id()] = {"left": seconds, "free": free}


## Spend this ball's window if it has one and it can be honoured. Returns the window (with
## its `free` flag) or an empty dict.
func _take_save(ball: Ball) -> Dictionary:
	if ball == null:
		return {}
	var id := ball.get_instance_id()
	var row: Variant = _saves.get(id, null)
	if not (row is Dictionary):
		return {}
	var window: Dictionary = row
	_saves.erase(id)
	if not bool(window["free"]) and saves_left <= 0:
		return {}
	return window


## "One free outlane escape per Night" (docs/01 §4). Spent before any ball-save charge, and
## only on an outlane drain: the trait is a slip out of the side lane, not immortality.
func _try_slippery(guy: Dictionary, ball: Ball) -> bool:
	if guy.is_empty() or not GuyTraits.can_outlane_save(guy):
		return false
	var id := int(guy.get("id", -1))
	if _slippery_used.has(id) or not _is_outlane_drain(ball):
		return false
	_slippery_used[id] = true
	return true


func _is_outlane_drain(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	var r := TableAPI.bounds(table, Rect2())
	if r.size.x <= 0.0:
		return true
	var t := (ball.global_position.x - r.position.x) / r.size.x
	return t <= OUTLANE_BAND or t >= 1.0 - OUTLANE_BAND


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


func _on_ball_launched(ball_node: Node2D, _power: float) -> void:
	if not running:
		return
	if saves_left > 0:
		_arm_save(ball_node as Ball, BALL_SAVE_SECONDS, false)
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


# ================================================================ the club =====


## A completed climb opens a deck visit: the window the slots Jackpot has to be finished
## inside (specs/m2-content.md §1).
func _on_staircase_climbed(_speed: float) -> void:
	if running:
		Game.casino.open_visit()


## The visit closes as soon as nothing is upstairs any more — the return lane took it home,
## or it drained.
func _tick_deck() -> void:
	if not Game.casino.visit_open():
		return
	for b in Balls.live():
		if b.global_position.y < DECK_LINE:
			return
	Game.casino.close_visit()


func _on_roulette_landed(pocket: int, house: bool) -> void:
	if not running:
		return
	var r := Game.casino_roulette(pocket, house)
	if not bool(r.get("bet", false)):
		return
	if (r["won"] as BigMoney).is_positive():
		AudioDirector.play(&"coin_drop")
		AudioDirector.play(&"chime_c" if bool(r.get("cooler", false)) else &"chime_a")
	else:
		AudioDirector.play(&"drop_clack")


func _on_reels_state(cleared_columns: Array) -> void:
	if not running:
		return
	var paid := Game.casino_reels(cleared_columns)
	if not paid.is_positive():
		return
	_arpeggio([&"drop_bank_down", &"chime_a", &"chime_b", &"chime_c", &"knocker"], 0.10)


func _on_high_roller_held(steps: int) -> void:
	if not running:
		return
	if Game.casino_high_roller(steps) > 0.0:
		AudioDirector.play(&"chime_c")


## The back room: it starts the Family Meeting, and during one it pays the growing jackpot.
func _on_backroom_entered() -> void:
	if not running:
		return
	if Game.meeting.active:
		var pay := Game.meeting.take_jackpot(Game.stats.idle_rate_total())
		if pay.is_positive():
			Game.earn_clean(pay, &"meeting")
			AudioDirector.play(&"meeting_jackpot")
			_arpeggio([&"drop_bank_down", &"chime_c"], 0.08)
		return
	if Game.meeting.can_start(Game.stats.hardware_unlocked(&"club_deck")):
		_start_meeting()


## FAMILY MEETING (specs/m2-content.md §4): a second named guy joins the table, both balls
## get a grace, all dirty doubles, and the back room starts paying.
func _start_meeting() -> void:
	var spare := _spare_guy()
	if spare.is_empty():
		return
	var extra: Variant = TableAPI.call_if(table, "spawn_extra_ball", [_meeting_spawn()], null)
	if not (extra is Ball):
		# A table that cannot serve a second ball simply has no Meeting; the light stays on.
		return
	Game.meeting.start(spare)
	extras.append(spare)
	_bind_guy(_ball(), current_guy())
	_bind_guy(extra as Ball, spare)
	_arm_save(_ball(), FamilyMeeting.BALL_SAVE_SECONDS, true)
	_arm_save(extra as Ball, FamilyMeeting.BALL_SAVE_SECONDS, true)
	Game.set_fielded(_live_guys())
	Game.meeting_changed.emit(true, Game.meeting.lit)
	AudioDirector.play(&"meeting_start")
	_arpeggio([&"drop_bank_down", &"chime_c", &"knocker"], 0.09)


## One ball left: the crew is not out together any more (BallRegistry's `last_ball`).
##
## It is only a candidate for the end here. `last_ball` fires from inside `unregister`, before
## `ball_lost` has told us whether that drain was a save — and a saved ball comes back next
## tick. Ending the Meeting on the signal itself would break it up every time a grace window
## caught somebody.
func _on_last_ball(_ball_node: Ball) -> void:
	if running and Game.meeting.active:
		_meeting_end_pending = true


func _settle_meeting() -> void:
	if not _meeting_end_pending:
		return
	_meeting_end_pending = false
	if not Game.meeting.active or Balls.count() > 1:
		return
	Game.meeting.end()
	Game.set_fielded(_live_guys())
	Game.meeting_changed.emit(false, Game.meeting.lit)
	AudioDirector.play(&"meeting_end")
	AudioDirector.play(&"drop_bank_reset")


## The next man up who is not already out tonight. Nobody free? Hire one — the Bench never
## hard-locks (docs/01 §8).
func _spare_guy() -> Dictionary:
	var taken := {}
	for g in lineup:
		taken[int(g["id"])] = true
	for g in extras:
		taken[int(g["id"])] = true
	for g in Game.bench.available():
		if not taken.has(int(g["id"])):
			return g
	return Game.bench.hire()


func _meeting_spawn() -> Vector2:
	var at: Variant = TableAPI.call_if(table, "socket", [&"club_deck"], null)
	if at is Vector2 and (at as Vector2) != Vector2.ZERO:
		return (at as Vector2) + MEETING_SPAWN_OFFSET
	return Vector2.ZERO


# ================================================================= the wire =====


func _tick_wire(delta: float) -> void:
	if not _wire_enabled or not Game.wire.tick(delta):
		return
	var ticket := int(TableAPI.call_if(table, "spinner_spins", [], 0))
	var result := Game.wire_draw(ticket)
	_arpeggio([&"chime_a", &"chime_b", &"chime_c"], WIRE_ARPEGGIO_GAP)
	if StringName(result["hit"]) != WireDraws.HIT_NONE:
		AudioDirector.play(&"headline_sting")


# ========================================================= collection rounds =====


func _tick_collection(delta: float) -> void:
	var was_active := Game.collection.active
	Game.collection.tick(delta)
	if was_active and not Game.collection.active:
		Game.collection_changed.emit(false, Game.collection.collected_count())
	_collect_poll -= delta
	if _collect_poll > 0.0:
		return
	_collect_poll = STOREFRONT_POLL
	if Game.collection.active or not _all_storefronts_armed():
		return
	if Game.collection.on_all_armed():
		AudioDirector.play(&"paper_slip")
		Game.collection_changed.emit(true, 0)


## All three banks standing at once (docs/05 §3). Read off the table's own storefront list;
## a table that does not have one simply never starts a round.
func _all_storefronts_armed() -> bool:
	var raw: Variant = TableAPI.prop(table, "storefronts", null)
	if not (raw is Array):
		return false
	var shops: Array = raw
	if shops.size() < int(Switches.COVER_SIZE.get(&"storefronts", 3)):
		return false
	for s: Variant in shops:
		var node := s as Node2D
		if node == null or not is_instance_valid(node) or not node.visible:
			return false
		if not node.has_method("state_name"):
			return false
		if StringName(node.call("state_name")) != &"armed":
			return false
	return true


func _on_table_storefront(id: StringName, amount: BigMoney) -> void:
	if not running:
		return
	if not Game.collection.on_collected(id):
		Game.collection_changed.emit(Game.collection.active, Game.collection.collected_count())
		return
	# Perfect round: the last shop pays its value again, ☆10, and the back room lights up.
	Game.collection_completed(id, amount)
	AudioDirector.play(&"job_done")
	_arpeggio([&"chime_a", &"chime_c"], 0.1)
	Game.collection_changed.emit(false, int(Switches.COVER_SIZE.get(&"storefronts", 3)))


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
	if table.has_method("set_raid_active"):
		# The table owns its own red wash and cop targets; do not tint it twice.
		table.call("set_raid_active", on)
		return
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
