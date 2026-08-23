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
## Reunion joiners are dealt along the deck from that socket, alternating sides.
const MEETING_SPREAD := Vector2(-90.0, -36.0)
## Outer band of the playfield width, each side, that counts as an outlane for the Slippery
## trait. Read against the table's own bounds so flow never hard-codes this table's posts.
const OUTLANE_BAND := 0.25
## How often the storefront banks are read for a Collection Round trigger.
const STOREFRONT_POLL := 0.25
## Sammy's Spare (specs/m2-content.md §5): the first jam of the Night falls out by itself, and
## every jam after it is this fraction of its natural length.
const SPARE_JAM_SCALE := 1.0 / 3.0
## Beat between the last panel going down and The Count — long enough for the knocker, the
## fanfare and the man in the limo driving off (docs/00: a boss beaten is a limo, not a body).
const BOSS_CEREMONY := 2.4
## Gap between the tote board's three chimes.
const WIRE_ARPEGGIO_GAP := 0.09

var table: Node2D = null
var nudge: NudgeController = null
var input: InputController = null
var raid: RaidMode = null
## THE RICO RAID (docs/05 §9). When the Feds are at the door this Night IS the raid: the
## guys are fielded as usual and the economy stays on, but it is two minutes and it ends
## when the last man is inside.
var rico: RicoRaid = null
## Sim hook, same as `raid_duration`: shorten the two minutes for a headless run.
var rico_duration: float = 0.0
var _rico_result: String = ""
var _rico_payout: BigMoney = BigMoney.zero()
## The Commission fight this Night IS, when The Count sent us to one (specs/m2-content.md §5).
## While it is live the economy is off, raids are off, and the table is wearing his hardware.
var boss: BossFight = null

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
## The raid on the table was called by the rat, not by the meter (docs/05 §7).
var _raid_from_rat: bool = false
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
## The table has briefcase hardware, so the bagman does his rounds this Night.
var _briefcases_on: bool = false
var _collect_poll: float = 0.0
## Guys whose ball was saved and is waiting to be put back on the table next tick.
var _reserve_queue: Array[Dictionary] = []
## `last_ball` fired; the Meeting ends unless a pending save puts a ball back first.
var _meeting_end_pending: bool = false
## Queued one-shots, each waiting `in` seconds after the one before it (the tote arpeggio).
var _arp: Array[Dictionary] = []
## Sammy's Spare is one wrench a Night, and this is whether tonight's is still in the boot.
var _spare_ready: bool = false
## Inside `_finish()`: a fight decided on the way out must not try to schedule a ceremony.
var _ending: bool = false
## Manny's clock (`auto_collect_interval`): seconds until he works a till by himself.
var _collect_in: float = 0.0
## The fight's result, folded into the Night summary The Count reads.
var _boss_result: Dictionary = {}


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
	_raid_from_rat = false
	_raid_payout = BigMoney.zero()
	_raid_confiscated = BigMoney.zero()
	_rico_result = ""
	_rico_payout = BigMoney.zero()
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
	_spare_ready = Game.has_spoil(Commission.SPOIL_SAMMY)
	_collect_in = Game.stats.auto_collect_interval()
	_boss_result = {}
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
	# `raid_triggered` is NOT connected here: the meter latches and it ticks between Nights
	# too, so `Game` owns that one connection for the life of the process and calls
	# `on_raid_called()` on whichever Night is live (see `Game._on_raid_triggered`).
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
	_connect_table(&"deck_returned", _on_deck_returned)
	# The table's own storefront signal carries the amount; the bus version does not, and the
	# Collection Round has to pay the last shop its value a second time.
	_connect_table(&"storefront_collected", _on_table_storefront)
	# M3 — THE DOCKS and THE PENTHOUSE (specs/m3-fall-rise.md FLOW-3). Same contract as the
	# Club: the yard and the room report, flow owns the runs and the money.
	_connect_table(&"docks_entered", _on_docks_entered)
	_connect_table(&"container_stack_cleared", _on_stack_cleared)
	_connect_table(&"containers_state", _on_containers_state)
	_connect_table(&"cargo_shipped", _on_cargo_shipped)
	_connect_table(&"sitdown_entered", _on_sitdown_entered)
	# The small rituals (docs/05 §10). The table owns the token and the walk-off; flow owns
	# what is in the case and who is on the phone.
	_briefcases_on = _connect_table(&"briefcase_collected", _on_briefcase_collected)
	_connect_table(&"briefcase_expired", _on_briefcase_expired)
	_connect_table(&"chair_taken", _on_chair_taken)
	_connect_table(&"chairs_completed", _on_chairs_completed)
	_connect_table(&"penthouse_entered", _on_penthouse_entered)
	_connect_table(&"orbit_completed", _on_orbit_completed)
	# THE CITY HALL CIRCUIT (docs/02 §2 R7). The dome is the last leg and the table reports it
	# itself; a table with no dome overhead simply has no crown to light, which is correct —
	# City Hall is a purchase (`city_hall`), not a default.
	_connect_table(&"dome_loop_completed", _on_dome_loop)

	_start_boss()
	_start_heist()
	_start_rico()

	# Nights do not always open cold — coming off a survived raid the meter is still at 30.
	if Game.administration_active():
		_open_the_block()
	# THE RAT (docs/05 §7). Three names in the backglass, and nothing else about the Night
	# changes — which is what makes it a whodunit rather than a mode.
	if Game.rat_night():
		_arpeggio([&"radio_squelch", &"chime_b"], 0.12)

	AudioDirector.music_set_state(_music_state())
	guy_index = -1
	_next_guy()
	# They were waiting for you to open up: the meter crossed 100 while nobody was playing
	# (The Count ticks Heat too), so the raid kicks the door in on the first serve rather than
	# sitting latched forever. Ordinary mode from here — telegraph, magnet, 45 seconds.
	if Game.heat.is_raid_pending():
		on_raid_called()
	set_physics_process(true)


## THE COMMISSION (specs/m2-content.md §5). The Count sent us to a fight, so this Night is
## one: the guys are fielded exactly as usual and the Night is exactly as long, but the
## economy is off and the table has somebody else's hardware standing on it.
func _start_boss() -> void:
	var id := Game.commission.pending
	if id == &"":
		return
	var fight := BossFight.make(id)
	if fight == null:
		# A boss with no script yet is not a Night-breaker: the pending fight is simply
		# dropped and the player gets an ordinary Night out of it.
		Game.commission.pending = &""
		return
	Game.commission.begin_fight(id)
	# ★ Reputation Precedes You: the FIRST fight of a city opens a phase in. Every fight after
	# it in the same city starts where fights always start.
	if Game.commission.beaten.is_empty():
		fight.start_phase = SkipTown.boss_start_phase()
	boss = fight
	boss.name = "Boss"
	add_child(boss)
	boss.finished.connect(_on_boss_finished)
	Game.boss = boss
	boss.begin(table, self)


## Tear the Night down without ending it (scene change, app quit).
func stop() -> void:
	if not running:
		return
	running = false
	set_physics_process(false)
	_set_raid_visual(false)
	if raid != null and is_instance_valid(raid):
		raid.abort()
	if rico != null and is_instance_valid(rico):
		rico.abort()
	if boss != null and is_instance_valid(boss):
		boss.abort()
		Game.boss = null
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
	_tick_crew(delta)
	_wash_cooldown = maxf(_wash_cooldown - delta, 0.0)

	_tick_balls(delta)
	_tick_deck()
	_tick_docks(delta)
	_tick_sitdown(delta)
	_tick_election(delta)
	_tick_empire(delta)
	_tick_briefcases(delta)
	_tick_phone(delta)
	_tick_heist(delta)
	_tick_raid_hold()
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
	if Game.economy_paused():
		return
	var rate := Game.stats.idle_rate_total()
	if rate == null or not rate.is_positive():
		return
	_idle_accum += delta
	while _idle_accum >= 1.0:
		_idle_accum -= 1.0
		Game.earn_idle(rate)


## Front businesses wash while their bank is armed (docs/03 §2 v1.5).
func _tick_wash(delta: float) -> void:
	if Game.economy_paused():
		return
	var per_sec := Game.stats.passive_wash_per_sec()
	if per_sec > 0.0 and _storefront_armed():
		Game.launder(per_sec * delta, Game.launder_cap_left())
	# Nussbaum washes whether or not a shop is open — that is what the accountant is FOR
	# (`auto_launder_per_sec`, specs/m2-content.md §2). Same per-Night cap as everything else.
	var auto := Game.stats.auto_launder_per_sec()
	if auto > 0.0:
		Game.launder(auto * delta, Game.launder_cap_left())


## The crew working on their own clocks. Manny (`auto_collect_interval`) walks a till every
## N seconds and hands the money in — visible, because a specialist earning off-screen is a
## tax, not a hire, so the collect goes out on `Game.auto_collected` for the HUD to flash.
func _tick_crew(delta: float) -> void:
	var every := Game.stats.auto_collect_interval()
	if every <= 0.0 or Game.economy_paused():
		return
	_collect_in -= delta
	if _collect_in > 0.0:
		return
	_collect_in = every
	var before := Game.wallet.dirty
	var got := StringName(TableAPI.call_if(table, "auto_collect_one", [], &""))
	if got == &"":
		# Nothing was lit. He waits a beat rather than a whole interval — he is standing
		# right there.
		_collect_in = minf(every, STOREFRONT_POLL * 4.0)
		return
	Game.auto_collected.emit(got, Game.wallet.dirty.sub_clamped(before))


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
	Game.heat_add_flat(TILT_HEAT)
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
	# A ball that is actually gone is the one thing that ends a heist (docs/05 §5) — a ball
	# save or a Slippery escape never reaches here, which is exactly right.
	_heist_ball_lost()
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
	if boss != null and is_instance_valid(boss) and boss.active:
		boss.on_guy_lost()

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
	Game.smuggling.abort()
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
	_ending = true
	# The Night ran out on him. A fight that was already decided (the Butcher's door is down
	# and only the payout lap was left) still counts as won.
	if boss != null and is_instance_valid(boss) and boss.active:
		boss.lose()
	# A job still open when the Night runs out comes home with what it has.
	if Game.heist != null and Game.heist.active:
		Game.heist.abort()
		Game.heist_finished(Game.heist)
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
		"rico": _rico_result,
		"rico_payout": _rico_payout,
		"confiscated": _raid_confiscated,
		"rank_before": _rank_before,
		"rank_up": Game.rank > _rank_before,
		"boss": _boss_result.duplicate(),
	}
	_ending = false
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
	Game.smuggling.abort()
	Game.sitdown.abort()
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


func _on_switch_hit(id: StringName, _ball_node: Node2D, strength: float) -> void:
	if not running:
		return
	var group := Switches.group_for(id)
	Game.jobs.on_switch(id, group)
	# Election Night: every switch on the machine is a ballot (docs/05 §8).
	Game.elections.on_vote()
	_canvass(group)
	_heist_switch(group, strength)
	if not _wash_from_signal and (group == &"laundry" or String(id).begins_with("laundromat")):
		_wash_pass()
	if group == &"wire" and Game.phone.ringing:
		_answer_phone()
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
	Game.rat_clue(TheRat.CLUE_COLLECTION)
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
		Game.rat_clue(TheRat.CLUE_LAUNDROMAT)


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
func _on_rollover_rolled(index: int, was_lit: bool) -> void:
	if not running:
		return
	# The Butcher counts lanes whether or not a delivery window is open — his ×2 is a whole
	# fight's worth of top-lane traffic, not one skill shot.
	if boss != null and is_instance_valid(boss) and boss.active:
		boss.on_rollover(index, was_lit)
	if _rat_accusation(index):
		return
	if not _skill_open:
		return
	_close_skill_window()
	if was_lit:
		Game.award_skill_shot()


## Fallback for a table that only emits `switch_hit`: work the lane out of the switch id.
func _check_skill_shot(id: StringName) -> void:
	var lane_index := Switches.index_of(id)
	if _rat_accusation(lane_index if _lanes_zero_based else lane_index - 1):
		return
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
	if not running:
		return
	Game.casino.open_visit()
	Game.empire_leg(&"staircase")


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
	Game.election_note(&"club")
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
##
## THE FAMILY REUNION (docs/02 §2 R7): at R7, once Empire has been lit tonight, the back room
## does not send one man — it sends four, and every Meeting rule scales with the crew. The
## graces are staggered so five balls do not all come off their save window on one frame.
func _start_meeting() -> void:
	var reunion := Game.reunion_ready()
	var want := (FamilyMeeting.REUNION_GUYS - 1) if reunion else 1
	var joined: Array[Dictionary] = []
	var balls: Array[Ball] = []
	for i in want:
		var spare := _spare_guy(joined)
		if spare.is_empty():
			break
		var extra: Variant = TableAPI.call_if(table, "spawn_extra_ball",
				[_meeting_spawn(i)], null)
		if not (extra is Ball):
			break
		joined.append(spare)
		balls.append(extra as Ball)
	if joined.is_empty():
		# A table that cannot serve a second ball simply has no Meeting; the light stays on.
		return

	Game.meeting.start_with(joined)
	_bind_guy(_ball(), current_guy())
	_arm_save(_ball(), FamilyMeeting.BALL_SAVE_SECONDS, true)
	for i in joined.size():
		extras.append(joined[i])
		_bind_guy(balls[i], joined[i])
		_arm_save(balls[i], FamilyMeeting.BALL_SAVE_SECONDS
				+ float(i) * FamilyMeeting.REUNION_SAVE_STAGGER, true)
	Game.set_fielded(_live_guys())
	Game.meeting_changed.emit(true, Game.meeting.lit)
	AudioDirector.play(&"reunion_start" if Game.meeting.is_reunion() else &"meeting_start")
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
func _spare_guy(also_taken: Array[Dictionary] = []) -> Dictionary:
	var taken := {}
	for g in lineup:
		taken[int(g["id"])] = true
	for g in extras:
		taken[int(g["id"])] = true
	for g in also_taken:
		taken[int(g["id"])] = true
	for g in Game.bench.available():
		if not taken.has(int(g["id"])):
			return g
	return Game.bench.hire()


## Where the nth joiner comes in. They are spread along the deck rather than stacked, because
## five balls born on one pixel is one ball with a physics problem.
func _meeting_spawn(index: int = 0) -> Vector2:
	var spread := Vector2(float(index % 2) * MEETING_SPREAD.x,
			float(index) * MEETING_SPREAD.y)
	var at: Variant = TableAPI.call_if(table, "socket", [&"club_deck"], null)
	if at is Vector2 and (at as Vector2) != Vector2.ZERO:
		return (at as Vector2) + MEETING_SPAWN_OFFSET + spread
	return spread


## The ball came home down the Club's return lane. The visit closes on the same test the
## poll uses, because a second ball may still be upstairs working the reels.
func _on_deck_returned() -> void:
	if running:
		_tick_deck()


# ============================================== the Docks / the Penthouse =====


## SMUGGLING RUNS (docs/02 §2 R5). The window is the mode; the yard is the table's.
func _tick_docks(delta: float) -> void:
	# The clock runs whether or not a run is on it: the yard's re-arm gap is on the same tick,
	# and a cooldown that only counts down while a run is live never counts down at all.
	var was_running := Game.smuggling.active
	Game.smuggling.tick(delta)
	if Game.smuggling.active or not was_running:
		return
	# It ran out with cargo still standing. Nothing is lost but the window.
	Game.smuggling_changed.emit(_smuggling_state(false, false))
	AudioDirector.play(&"drop_bank_reset")


func _smuggling_state(shipped: bool, hot: bool) -> Dictionary:
	return {
		"shipped": shipped,
		"hot": hot,
		"active": Game.smuggling.active,
		"cleared": Game.smuggling.cleared_count(),
		"time_left": Game.smuggling.time_left,
		"paid": BigMoney.zero(),
	}


func _on_docks_entered() -> void:
	if not running:
		return
	if not Game.smuggling.on_docks_entered(_stacks_standing()):
		return
	AudioDirector.play(&"smuggling_start")
	AudioDirector.play(&"knocker")
	Game.smuggling_changed.emit(_smuggling_state(false, false))


## How much cargo is still up. A yard that does not report is assumed loaded — a run that
## arms on an empty quay simply lapses, which is a far better failure than never arming.
func _stacks_standing() -> int:
	var yard: Variant = TableAPI.prop(table, "docks", null)
	var crates: Variant = TableAPI.prop(yard as Object, "containers", null)
	if crates == null:
		return SmugglingRun.STACKS
	var cleared: Variant = TableAPI.call_if(crates as Object, "cleared_stacks", [], null)
	if not (cleared is Array):
		return SmugglingRun.STACKS
	return maxi(SmugglingRun.STACKS - (cleared as Array).size(), 0)


func _on_stack_cleared(stack: int) -> void:
	if running and Game.smuggling.active:
		_settle_shipment(Game.smuggling.on_stack_cleared(stack))


func _on_containers_state(cleared_stacks: Array) -> void:
	if running and Game.smuggling.active:
		_settle_shipment(Game.smuggling.on_containers_state(cleared_stacks))


## The load is out. `Game` pays it; this is the noise and the light.
func _settle_shipment(shipped: bool) -> void:
	if not shipped:
		# The crate's own noise is the table's (`container_break`); this is only the mode.
		Game.smuggling_changed.emit(_smuggling_state(false, Game.smuggling.hot))
		return
	var hot := Game.smuggling.hot
	Game.smuggling_shipment(hot)
	Game.election_note(&"docks")
	AudioDirector.play(&"shipment_out")
	_arpeggio([&"drop_bank_down", &"chime_a", &"chime_c", &"knocker"], 0.1)


## The hoist crested onto the main field: the load reached the truck and the shipment doubles.
func _on_cargo_shipped(_speed: float) -> void:
	if not running or not Game.smuggling.active:
		return
	Game.smuggling.on_cargo_shipped()
	AudioDirector.play(&"chime_c")
	Game.smuggling_changed.emit(_smuggling_state(false, true))


## THE SIT-DOWN (docs/02 §2 R6): the meter stops for a minute and the block re-arms.
func _on_sitdown_entered() -> void:
	if not running:
		return
	if not Game.sitdown_begin():
		return
	# The saucer's capture is the table's `sitdown`; this is the room going quiet.
	AudioDirector.play(&"chime_b")
	# "Storefronts auto-arm" — the table owns the banks, so this is an ask, not a reach.
	_open_the_block()


func _tick_sitdown(delta: float) -> void:
	if not Game.sitdown.active:
		return
	if not Game.sitdown.tick(delta):
		return
	Game.sitdown_changed.emit(false, 0.0)
	AudioDirector.play(&"drop_bank_reset")


## A chair went down. The table pays the switch; `Game` owns the claim and the ☆.
func _on_chair_taken(index: int) -> void:
	if running:
		Game.chair_taken(index)


## The whole room in one pass. With every seat already claimed this is what lights the
## campaign — and it is the only thing that does.
func _on_chairs_completed() -> void:
	if not running:
		return
	if Game.chairs_completed():
		_arpeggio([&"chime_a", &"chime_b", &"chime_c", &"headline_sting"], 0.12)


# ================================================================= elections =====


## Canvassing (docs/05 §8): a district is worked by playing that zone, so the campaign rides
## the switch traffic that is already flowing rather than needing a counter of its own.
func _canvass(group: StringName) -> void:
	if not Game.elections.unlocked:
		return
	match group:
		&"bumpers", &"slings":
			Game.election_note(&"alley")
		&"wire":
			Game.election_note(&"corner")
		&"cop":
			# City Hall's cops are escorts, not a patrol (docs/05 §8).
			if Game.administration_active():
				Game.heat_reduce(Elections.ADMIN_COP_HEAT)


func _tick_election(delta: float) -> void:
	if not Game.elections.active:
		return
	if not Game.elections.tick(delta):
		return
	var result := Game.election_settle()
	if bool(result["won"]):
		_arpeggio([&"knocker", &"chime_a", &"chime_c", &"headline_sting"], 0.12)
	else:
		AudioDirector.play(&"drop_bank_reset")


## The block opens up for City Hall and for the Sit-Down. The banks are the table's, so this
## is an ask that a table without the API simply ignores.
func _open_the_block() -> void:
	TableAPI.call_if(table, "arm_storefronts")


# ============================================================== the City Hall Circuit =====
##
## docs/02 §2 R7: the full-table orbit, the staircase, the Penthouse gate and the dome loop,
## chained. Four legs, four signals the table already emits, and one mode at the end of it.


## The getaway loop closed. It is the first leg of the circuit and it is also just an orbit —
## the table pays it either way.
func _on_orbit_completed() -> void:
	if running:
		Game.empire_leg(&"orbit")


func _on_penthouse_entered(_speed: float) -> void:
	if running:
		Game.empire_leg(&"penthouse")


func _on_dome_loop(_speed: float) -> void:
	if running:
		Game.empire_leg(&"dome")


func _tick_empire(delta: float) -> void:
	if not Game.empire.tick(delta):
		return
	Game.empire_finished()
	AudioDirector.music_set_state(_music_state())


# =================================================================== the heist =====
##
## A heist runs on an ordinary Night with the economy on (docs/05 §5). This owns the clock and
## the switch feed; `HeistRun` owns the checklist and `Game` owns the take.


## The Count booked a job for tonight. Nothing about the Night changes except that a crew is
## working: same three guys, same rackets, same raid.
func _start_heist() -> void:
	var plan := Game.heists.pending
	if plan.is_empty():
		return
	var target := StringName(plan.get("target", ""))
	var run := HeistRun.make(target, StringName(plan.get("approach", Heists.QUIET)),
			plan.get("guy", {}))
	if run == null:
		# A target with no script yet is not a Night-breaker: the job is simply dropped.
		Game.heists.clear_pending()
		return
	Game.heists.begin(target, Game.night_no)
	Game.heist = run
	run.begin()
	Game.heat_add_flat(run.heat_cost())
	AudioDirector.play(&"heist_start")
	AudioDirector.play(&"knocker")
	Game.heist_changed.emit(run.state())


func _tick_heist(delta: float) -> void:
	var run := Game.heist
	if run == null or not run.active:
		return
	if not run.tick(delta):
		return
	# A blown beat is a worse payday, never an ended job (docs/05 §5, P5).
	AudioDirector.play(&"heist_blown")
	if run.active:
		Game.heist_changed.emit(run.state())
	else:
		Game.heist_finished(run)


## Every switch is offered to the checklist. The beat decides whether it was the shot it
## wanted — and, for the Vault's walk-out, whether it was gentle enough.
func _heist_switch(group: StringName, strength: float) -> void:
	var run := Game.heist
	if run == null or not run.active:
		return
	var before := run.beat_index
	match run.on_switch(group, strength):
		HeistRun.HIT_OK:
			AudioDirector.play(&"heist_beat" if run.beat_index > before else &"chime_a")
			if run.active:
				Game.heist_changed.emit(run.state())
			else:
				_arpeggio([&"chime_a", &"chime_b", &"chime_c", &"headline_sting"], 0.11)
				Game.heist_finished(run)
		HeistRun.HIT_GENTLE:
			# Right shot, too much on it. The beat stands and the player gets told why.
			AudioDirector.play(&"drop_clack")
			Game.heist_changed.emit(run.state())


## A ball went down. That is the one thing that ends a heist — unless the inside man had a
## way out for exactly this.
func _heist_ball_lost() -> void:
	var run := Game.heist
	if run == null or not run.active:
		return
	if not run.on_ball_lost():
		AudioDirector.play(&"chime_b")
		Game.heist_changed.emit(run.state())
		return
	AudioDirector.play(&"heist_blown")
	Game.heist_finished(run)


# ==================================================== briefcases & the phone =====
##
## docs/05 §10. The table owns the case (where it stands, how long, and the bagman walking off
## with it) and the payphones; everything about what is IN the case, and who is on the line,
## is flow's.


func _tick_briefcases(delta: float) -> void:
	if not _briefcases_on or Game.economy_paused():
		return
	if not Game.briefcases.tick(delta, GuyTraits.briefcase_odds_add(current_guy())):
		return
	if bool(TableAPI.call_if(table, "briefcase_live", [], false)):
		return
	TableAPI.call_if(table, "spawn_briefcase")
	if bool(TableAPI.call_if(table, "briefcase_live", [], false)):
		AudioDirector.play(&"briefcase_drop")


func _on_briefcase_collected() -> void:
	if not running:
		return
	var result := Game.open_briefcase()
	match StringName(result["kind"]):
		Briefcases.WAD:
			AudioDirector.play(&"coin_drop")
			_arpeggio([&"chime_a", &"chime_c"], 0.09)
		Briefcases.SETUP:
			# Stung: Heat and a face at the door. The cop belongs to the raid's hardware, so
			# it is an ask — a table without one costs the player the Heat and nothing else.
			AudioDirector.play(&"drop_clack")
			AudioDirector.play(&"siren")
			TableAPI.call_if(table, "spawn_cop_target")
		Briefcases.BOON:
			AudioDirector.play(&"chime_b")
			if StringName(result["boon"]) == Briefcases.BOON_SAVE:
				# The ball saves are the Night's, so the Night is where the charge lands.
				saves_left += 1


func _on_briefcase_expired() -> void:
	if running:
		Game.briefcases.on_expired()
		AudioDirector.play(&"briefcase_leave")


## The payphones ARE the phone on this table (see game/flow/phone.gd): while it rings, a hit
## on the Wire bank picks it up, which costs a real shot under a real clock.
func _tick_phone(delta: float) -> void:
	if not _wire_enabled or Game.economy_paused():
		return
	var was := Game.phone.ringing
	if Game.phone.tick(delta):
		AudioDirector.play(&"radio_squelch")
		Game.phone_changed.emit({"ringing": true, "caller": ""})
		Game.rat_clue(TheRat.CLUE_PAYPHONE)
		return
	if was and not Game.phone.ringing:
		Game.phone_rang_out()


func _answer_phone() -> void:
	var result := Game.answer_phone()
	if not bool(result.get("answered", false)):
		return
	AudioDirector.play(&"chime_b")
	if StringName(result["caller"]) == ThePhone.NONNA:
		AudioDirector.play(&"chime_a")


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
	elif Game.administration_active():
		# In office the block is never shut: the banks come back up for you (docs/05 §8).
		_open_the_block()


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
	Game.election_note(&"block")
	AudioDirector.play(&"job_done")
	_arpeggio([&"chime_a", &"chime_c"], 0.1)
	Game.collection_changed.emit(false, int(Switches.COVER_SIZE.get(&"storefronts", 3)))


# =================================================================== raid =====


## The Inspector is at the door. Called by `Game._on_raid_triggered` when the meter latches
## during this Night, and by `start()` when it latched before this Night opened. Idempotent:
## a raid already on the table swallows the call, so a pending latch fires exactly one raid.
## `scale` shortens the mode (The Rat's phone call is half a raid, docs/05 §7) and `from_rat`
## says the Inspector did not send it — so it neither reads nor resets his file.
func on_raid_called(scale: float = 1.0, from_rat: bool = false) -> void:
	if not running or (raid != null and is_instance_valid(raid) and raid.active):
		return
	# The Commission does not share a Night with the Inspector: a boss fight is pure skill
	# (docs/05 §6), and the meter is not even earning while one runs. Neither does the RICO
	# raid — the Feds do not queue behind a squad car.
	if boss != null and is_instance_valid(boss) and boss.active:
		return
	if rico != null and is_instance_valid(rico) and rico.active:
		return
	# City Hall holds him at the door until the meter clears the Administration's own bar.
	# A rat's phone call is not the Inspector's raid and is not held by anybody's term.
	if not from_rat and Game.heat.value < Game.elections.raid_threshold():
		return
	_raid_from_rat = from_rat
	raid = RaidMode.new()
	raid.name = "Raid"
	if raid_duration > 0.0:
		raid.duration = raid_duration
	raid.duration *= clampf(scale, 0.1, 1.0)
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
		Game._book_lifetime_clean(_raid_payout)
		Game.career_raid_survived()
		Game.add_respect(Game.RESPECT_RAID_SURVIVED, &"raid")
		Game.mark_reveal_event(&"first_raid_survived")
		AudioDirector.play(&"raid_win")
	else:
		# The raid was lost either way — the front page still says so. ★ rain_insurance
		# (specs/m2-content.md §3) only covers the money, once a Night.
		_raid_result = "lost"
		if _rain_insured():
			Game.night_insured = true
			AudioDirector.play(&"stamp_thunk")
		else:
			_raid_confiscated = Game.wallet.confiscate_dirty(Rates.RAID_CONFISCATE_FRACTION)
		AudioDirector.play(&"raid_lose")
	# A raid the rat called is not the Inspector's, so his file is exactly where it was: a
	# wrong name must not be a way to launder a hot meter.
	if not _raid_from_rat:
		Game.heat.reset_after_raid(survived)
	_raid_from_rat = false
	Events.raid_ended.emit(survived)
	AudioDirector.music_set_state(_music_state())
	if raid != null and is_instance_valid(raid):
		raid.queue_free()
		raid = null


## Is a confiscation covered? One policy, one Night (docs/04 T5 ★rain_insurance).
func _rain_insured() -> bool:
	return Game.stats.flag(&"rain_insurance") and not Game.night_insured


# ============================================================== the RICO raid =====
##
## docs/05 §9. The blue meter topped out, so this Night is the federal raid: two minutes,
## three phases, and it is over when the last guy is inside. Everything else about the Night
## is normal — the economy runs, the modes run, the guys are the guys.


func _start_rico() -> void:
	if not Game.rico_pending():
		return
	rico = RicoRaid.new()
	rico.name = "Rico"
	if rico_duration > 0.0:
		rico.duration = rico_duration
	add_child(rico)
	rico.finished.connect(_on_rico_finished)
	rico.changed.connect(_on_rico_changed)
	_set_raid_visual(true)
	rico.begin(table)
	AudioDirector.music_set_state(&"raid")


## Every phase change is republished as Game traffic: the wiretap phase takes the audio away
## on purpose (docs/08 §6), so the HUD has to be able to say what is happening without it.
func _on_rico_changed(state: Dictionary) -> void:
	Game.federal_changed.emit({"rico_state": state, "enabled": Game.federal.enabled,
			"value": Game.federal.value, "meter": Game.federal.meter_value(),
			"rico": true})


func _on_rico_finished(survived: bool) -> void:
	_set_raid_visual(false)
	var result := Game.rico_finished(survived, _rain_insured())
	if bool(result.get("insured", false)):
		Game.night_insured = true
	_rico_result = "survived" if survived else "lost"
	_rico_payout = result["payout"]
	_raid_confiscated = _raid_confiscated.add(result["confiscated"])
	# The red meter is reset by the federal raid exactly as it is by an ordinary one: the
	# Inspector's file and the Bureau's are the same night's work.
	Game.heat.reset_after_raid(survived)
	AudioDirector.play(&"raid_win" if survived else &"raid_lose")
	AudioDirector.play(&"headline_sting")
	Events.raid_ended.emit(survived)
	AudioDirector.music_set_state(_music_state())
	if rico != null and is_instance_valid(rico):
		rico.queue_free()
		rico = null
	# Two minutes of federal raid IS the Night (docs/05 §9): there is nothing after it.
	if running and not _ending:
		_close_skill_window()
		_beat(&"end", BOSS_CEREMONY)


## THE ADMINISTRATION'S DOOR (docs/05 §8). The meter latches its raid at 100 — that is the
## economy core's and it is frozen — so a term in office does not lower the latch, it refuses
## to open the door until the number is genuinely embarrassing. The latch stays pending in the
## meantime, which is exactly the state `HeatMeter` already models, so nothing is invented: the
## poll simply asks again each tick and `NightController.start()` still catches a crossing that
## happened while nobody was playing.
func _tick_raid_hold() -> void:
	if not running or not Game.administration_active():
		return
	if raid != null and is_instance_valid(raid) and raid.active:
		return
	if not Game.heat.is_raid_pending() or Game.heat.value < Game.elections.raid_threshold():
		return
	on_raid_called()


func _on_band_changed(_band: int) -> void:
	if not running:
		return
	if raid != null and is_instance_valid(raid) and raid.active:
		return
	AudioDirector.music_set_state(_music_state())


func _music_state() -> StringName:
	if raid != null and is_instance_valid(raid) and raid.active:
		return &"raid"
	if rico != null and is_instance_valid(rico) and rico.active:
		return &"raid"
	# A fight earns nothing, so the Heat band drifts down through it — the band must not be
	# allowed to take the room back to `calm` while a Commission boss is on the table.
	if boss != null and is_instance_valid(boss) and boss.active:
		return &"hot"
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


# ============================================================ the Commission =====


## The fight is decided. `Game` pays the purse, hands over the spoil and lets the promotion
## the ☆ had already earned actually land; this ends the Night on the ceremony.
func _on_boss_finished(victory: bool) -> void:
	var id: StringName = &""
	if boss != null and is_instance_valid(boss):
		id = boss.id
		boss.queue_free()
	boss = null
	Game.boss = null
	_boss_result = Game.boss_finished(id, victory)
	if not victory:
		return
	AudioDirector.play(&"knocker")
	AudioDirector.play(&"rankup_fanfare")
	_arpeggio([&"chime_a", &"chime_b", &"chime_c", &"headline_sting"], 0.12)
	if _ending or not running:
		return
	# Nothing is left to earn on a paused table: the ceremony IS the end of the Night.
	_close_skill_window()
	_beat(&"end", BOSS_CEREMONY)


## A boss puts a wrench through one bat. Sammy's Spare is spent here rather than in the fight,
## because the Spare is the Night's property: it hands back a Lean, and Leans belong to the
## tilt meter this Night is running (specs/m2-content.md §5). Returns whether a jam landed.
func jam_flipper(side: StringName, seconds: float) -> bool:
	var f := _flipper(side)
	if f == null:
		return false
	if _spare_ready:
		# "the NEXT jam self-clears instantly, +1 free Lean"
		_spare_ready = false
		f.unjam()
		_free_lean()
		AudioDirector.play(&"kickback")
		AudioDirector.play(&"chime_b")
		return false
	var length := seconds
	if Game.has_spoil(Commission.SPOIL_SAMMY):
		length *= SPARE_JAM_SCALE
	f.jam(length)
	AudioDirector.play(&"drop_clack")
	return true


func telegraph_flipper(side: StringName, seconds: float) -> void:
	var f := _flipper(side)
	if f != null:
		f.telegraph(seconds)


func _flipper(side: StringName) -> Flipper:
	var f: Variant = TableAPI.prop(table, "flipper_right" if side == &"right" else "flipper_left")
	return f as Flipper if f is Flipper and is_instance_valid(f as Flipper) else null


## One Lean back. A used warning is refunded first; with a clean meter the ceiling goes up
## instead, so the Spare is worth the same whenever it fires.
func _free_lean() -> void:
	if nudge == null or not is_instance_valid(nudge):
		return
	if nudge.meter.warnings > 0:
		nudge.meter.warnings -= 1
	else:
		nudge.meter.max_warnings += 1


## THE ACCUSATION (docs/05 §7). With the clues in hand the three top lanes are the three
## names: rolling one points at a man. There is no menu — the accusation costs a real shot,
## and it can be made by mistake, which is exactly the weight it is supposed to carry.
## Returns true if the lane was spent naming somebody.
func _rat_accusation(lane: int) -> bool:
	if not Game.rat.can_accuse() or lane < 0 or lane >= TheRat.SUSPECTS:
		return false
	var result := Game.rat_accuse(lane)
	if not bool(result["made"]):
		return false
	_close_skill_window()
	if bool(result["right"]):
		_arpeggio([&"chime_a", &"chime_b", &"chime_c", &"headline_sting"], 0.12)
		return true
	# He makes one phone call. Half a raid, right now, and no reprieve on the meter — this
	# one is not the Inspector's, so it does not reset his file when it is over.
	AudioDirector.play(&"headline_sting")
	on_raid_called(TheRat.RAID_STRENGTH, true)
	return true


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
