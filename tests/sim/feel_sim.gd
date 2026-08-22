extends Node2D
## M0 acceptance runner (specs/m0-feel.md §"Acceptance"). Boots the M0 alley, steps real
## physics headless, and drives the six scripted scenarios. Prints PASS/FAIL per scenario
## and quits 0 only if every one passed.
##
## Everything is counted in physics ticks (Engine.physics_ticks_per_second), never wall time,
## and the chaos is seeded — reruns take the same path.
##
## This hosts the alley itself rather than booting `game/main.tscn`. The feel numbers being
## guarded here are the M0 table's, and `main.tscn` now boots the M1 progression table and a
## whole session on top of it; going through it would make this sim fail for reasons that
## have nothing to do with the physics it exists to protect. The wiring below is exactly the
## part of Main these scenarios need: a nudge controller, and the tilt/drain housekeeping.

const TABLE_SCENE := preload("res://game/table/segments/alley_debug.tscn")

const BOUND_MIN := Vector2(36.0, -4.0)
const BOUND_MAX := Vector2(1044.0, 1930.0)

const SOAK_SECONDS := 30.0
const FLIP_MIN_SPEED := 1400.0
const FLIP_MAX_SPEED := 3600.0
const CRADLE_REST_SPEED := 20.0
const SEED := 0x4B494E47

var host: Node2D = null
var table: AlleyDebugTable = null
var nudge: NudgeController = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

var _watch_bounds: bool = false
var _bound_escapes: int = 0
var _worst: Vector2 = Vector2.ZERO
var _fired: Dictionary = {&"left": 0, &"right": 0}
var _tilt_count: int = 0
var _switches: int = 0
var _dirty: int = 0
var _last_pos: Vector2 = Vector2.INF
var _still: int = 0
var _still_max: int = 0
var _still_at: Vector2 = Vector2.ZERO


var soak_seconds: float = SOAK_SECONDS
var soak_seed: int = SEED


func _ready() -> void:
	# --soak=<s> / --seed=<n> after a bare `--` let this be fuzzed; check.sh passes neither.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--soak="):
			soak_seconds = maxf(arg.split("=")[1].to_float(), 0.5)
		elif arg.begins_with("--seed="):
			soak_seed = arg.split("=")[1].to_int()
	_rng.seed = soak_seed
	host = Node2D.new()
	host.name = "Host"
	add_child(host)
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	host.add_child(table)
	nudge = NudgeController.new()
	nudge.name = "Nudge"
	host.add_child(nudge)
	table.ball_spawned.connect(func(b: Ball) -> void: nudge.set_ball(b))
	table.ball_lost.connect(_on_ball_lost)
	Events.tilted.connect(_on_tilted)
	table.auto_respawn = false
	Events.flipper_fired.connect(func(side: StringName) -> void: _fired[side] = int(_fired[side]) + 1)
	Events.tilted.connect(func() -> void: _tilt_count += 1)
	Events.scored.connect(func(_id: StringName, v: int) -> void:
		_switches += 1
		_dirty += v)
	_run()


## The housekeeping game/main.gd does around a drain: the guy is gone, so the flippers come
## back and the Inspector forgets.
func _on_ball_lost(_ball: Ball) -> void:
	nudge.set_ball(null)
	nudge.clear_tilt()
	table.flipper_left.revive()
	table.flipper_right.revive()
	if table.plunger != null:
		table.plunger.enabled = true


## TILT: the guy's flippers are dead until he's pinched (docs/01 §5).
func _on_tilted() -> void:
	table.flipper_left.kill()
	table.flipper_right.kill()


# ---------------------------------------------------------------- harness

func ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(Engine.physics_ticks_per_second))))


func step(count: int = 1) -> void:
	for i in range(count):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	await step(ticks(seconds))


func begin(name: String) -> void:
	_current = name
	_fails = PackedStringArray()


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	var status := "PASS" if _fails.is_empty() else "FAIL"
	print("  [%s] %s" % [status, _current])
	for f in _fails:
		print("        - %s" % f)


func ball() -> Ball:
	return table.ball


func fresh_ball_in_lane() -> void:
	table.despawn_ball()
	await step(2)
	table.spawn_ball()
	await wait(0.5)


func _physics_process(_delta: float) -> void:
	if not _watch_bounds:
		return
	var b := table.ball
	if b == null or not is_instance_valid(b):
		return
	var p := b.global_position
	_worst.x = maxf(_worst.x, absf(p.x - 540.0))
	_worst.y = maxf(_worst.y, p.y)
	# a ball that stops moving for seconds on end is wedged in geometry, which the bounds
	# assert alone would happily call a pass
	if _last_pos != Vector2.INF and p.distance_to(_last_pos) < 0.5:
		_still += 1
		if _still > _still_max:
			_still_max = _still
			_still_at = p
	else:
		_still = 0
	_last_pos = p
	if p.x < BOUND_MIN.x or p.x > BOUND_MAX.x or p.y < BOUND_MIN.y or p.y > BOUND_MAX.y:
		_bound_escapes += 1
		if _bound_escapes <= 5:
			print("        ESCAPE at %s  v=%s" % [p, b.linear_velocity])


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M0 feel sim ==")
	print("physics %d Hz | seed 0x%X" % [Engine.physics_ticks_per_second, soak_seed])
	await step(4)

	await _s1_no_tunnel()
	await _s2_cradle()
	await _s3_flip_strength()
	await _s4_plunger_bands()
	await _s5_tilt()
	await _s6_input_buffer()

	var failed := 0
	for r: Dictionary in _results:
		if not (r["fails"] as PackedStringArray).is_empty():
			failed += 1
	print("---")
	print("scenarios: %d  passed: %d  failed: %d" % [_results.size(), _results.size() - failed, failed])
	print("OK" if failed == 0 else "SIM FAILED")
	table.despawn_ball()
	host.queue_free()
	await step(2)
	get_tree().quit(0 if failed == 0 else 1)


## 1 — 30 s of chaotic flipping and nudging; the ball may never leave the geometry.
func _s1_no_tunnel() -> void:
	begin("no-tunnel soak (%.0fs)" % soak_seconds)
	table.auto_respawn = true
	var relaxed := nudge.meter.max_warnings
	nudge.meter.max_warnings = 1 << 30      # tilt would park the flippers; we want stress
	await fresh_ball_in_lane()
	table.plunger.launch(1.0)

	_bound_escapes = 0
	_worst = Vector2.ZERO
	_still = 0
	_still_max = 0
	_last_pos = Vector2.INF
	_watch_bounds = true

	var total := ticks(soak_seconds)
	var next_flip := [0, 0]
	var flip_state := [false, false]
	var next_nudge := ticks(3.0)
	var nudge_names: Array[StringName] = [&"left", &"right", &"up"]
	var relaunches := 0

	for t in range(total):
		for s in range(2):
			if t >= next_flip[s]:
				flip_state[s] = not flip_state[s]
				var f: Flipper = table.flipper_left if s == 0 else table.flipper_right
				f.set_pressed(flip_state[s])
				next_flip[s] = t + ticks(_rng.randf_range(0.3, 0.7))
		if t >= next_nudge:
			next_nudge = t + ticks(3.0)
			nudge.nudge(nudge_names[_rng.randi() % 3])
		# a ball that dribbled back into the shooter lane gets re-plunged, so the soak
		# never degenerates into 30 s of a parked ball
		if table.plunger.ball_ready():
			table.plunger.launch(_rng.randf_range(0.85, 1.0))
			relaunches += 1
		await step(1)

	_watch_bounds = false
	table.flipper_left.set_pressed(false)
	table.flipper_right.set_pressed(false)
	nudge.meter.max_warnings = relaxed
	nudge.clear_tilt()
	table.auto_respawn = false

	var stuck := float(_still_max) / float(Engine.physics_ticks_per_second)
	print("        balls served %d | relaunches %d | switches %d ($%d) | max |x-540| %.0f | max y %.0f | longest still %.1fs at %s"
			% [table.balls_served, relaunches, _switches, _dirty, _worst.x, _worst.y, stuck, _still_at])
	check(_bound_escapes == 0, "ball escaped table bounds %d times" % _bound_escapes)
	check(table.balls_served >= 1, "no ball was ever served")
	check(_switches > 0, "no hardware was ever hit — the ball never reached the playfield")
	check(stuck < 2.0, "ball sat motionless for %.1fs — wedged in geometry" % stuck)
	finish()


## 2 — the ball must settle on a *resting* bat and stay there.
func _s2_cradle() -> void:
	begin("cradle on resting flipper")
	await _place_on_bat()
	await wait(1.2)
	var b := ball()
	var f := table.flipper_left
	if b == null or not is_instance_valid(b):
		check(false, "ball did not survive the settle (drained off the bat)")
		finish()
		return
	var aabb := f.bat_aabb().grow(Feel.BALL_RADIUS + 6.0)
	check(b.speed() < CRADLE_REST_SPEED,
			"ball not at rest after settle: %.1f px/s" % b.speed())
	check(aabb.has_point(b.global_position),
			"ball %s not on the bat %s" % [b.global_position, aabb])

	var start := b.global_position
	var max_speed := 0.0
	var below := 0
	for t in range(ticks(2.0)):
		await step(1)
		if not is_instance_valid(b):
			break
		max_speed = maxf(max_speed, b.speed())
		if f.to_local(b.global_position).y > 0.0:
			below += 1
	check(is_instance_valid(b), "ball vanished (fell through the bat)")
	if is_instance_valid(b):
		check(below == 0, "ball passed through the bat on %d ticks" % below)
		check(max_speed < CRADLE_REST_SPEED, "ball crept at %.1f px/s over 2 s" % max_speed)
		check(b.global_position.distance_to(start) < 12.0,
				"ball drifted %.1f px in 2 s" % b.global_position.distance_to(start))
	print("        rest speed %.2f px/s | drift %.2f px"
			% [max_speed, b.global_position.distance_to(start) if is_instance_valid(b) else -1.0])
	finish()


## 3 — fire from that cradle: real power, and the ball actually gets up the table.
func _s3_flip_strength() -> void:
	begin("flip strength from cradle")
	await _place_on_bat()
	await wait(1.2)
	var b := ball()
	if b == null or not is_instance_valid(b):
		check(false, "ball did not survive the settle (drained off the bat)")
		finish()
		return

	table.flipper_left.press()
	var best_up := 0.0
	for t in range(ticks(0.1)):
		await step(1)
		if not is_instance_valid(b):
			break
		best_up = maxf(best_up, -b.linear_velocity.y)
	table.flipper_left.release()

	var apex := 9999.0
	for t in range(ticks(1.6)):
		await step(1)
		if not is_instance_valid(b):
			break
		apex = minf(apex, b.global_position.y)

	print("        launch speed %.0f px/s | apex y %.0f" % [best_up, apex])
	check(best_up >= FLIP_MIN_SPEED and best_up <= FLIP_MAX_SPEED,
			"flip speed %.0f outside [%.0f, %.0f]" % [best_up, FLIP_MIN_SPEED, FLIP_MAX_SPEED])
	check(apex < 1000.0, "ball only reached y=%.0f (needs < 1000)" % apex)
	finish()


## 4 — plunger power bands must be three visibly different shots.
func _s4_plunger_bands() -> void:
	begin("plunger power bands")
	var powers := [0.35, 0.7, 1.0]
	var apexes: Array[float] = []
	for p: float in powers:
		await fresh_ball_in_lane()
		var b := ball()
		table.plunger.launch(p)
		var apex := 9999.0
		for t in range(ticks(2.6)):
			await step(1)
			if not is_instance_valid(b):
				break
			apex = minf(apex, b.global_position.y)
		apexes.append(apex)
	print("        apex y: %.0f / %.0f / %.0f" % [apexes[0], apexes[1], apexes[2]])
	check(apexes[0] - apexes[1] > 120.0,
			"0.35 and 0.70 land too close (%.0f vs %.0f)" % [apexes[0], apexes[1]])
	check(apexes[1] - apexes[2] > 120.0,
			"0.70 and 1.00 land too close (%.0f vs %.0f)" % [apexes[1], apexes[2]])
	check(apexes[2] < 300.0, "full power only reached y=%.0f (needs < 300)" % apexes[2])
	finish()


## 5 — four fast leans tilt the table; flippers stay dead until the guy is pinched.
func _s5_tilt() -> void:
	begin("tilt kills flippers until drain")
	table.auto_respawn = true
	await fresh_ball_in_lane()
	nudge.clear_tilt()
	_tilt_count = 0

	for i in range(4):
		nudge.nudge(&"left")
		await wait(Feel.NUDGE_COOLDOWN + 0.03)
	check(_tilt_count == 1, "tilted fired %d times, expected 1" % _tilt_count)
	check(nudge.tilted(), "nudge controller does not report tilted")

	var before := int(_fired[&"left"])
	table.flipper_left.press()
	await wait(0.1)
	check(int(_fired[&"left"]) == before, "flipper fired while tilted")
	check(table.flipper_left.progress == 0.0, "flipper moved while tilted")
	table.flipper_left.release()

	var b := ball()
	if is_instance_valid(b):
		b.place(Vector2(490.0, 1876.0))
	await wait(Feel.RESPAWN_DELAY + 0.6)
	check(not nudge.tilted(), "tilt did not clear on drain")
	check(table.ball != null, "no ball respawned after the drain")

	before = int(_fired[&"left"])
	table.flipper_left.press()
	await wait(0.1)
	check(int(_fired[&"left"]) == before + 1, "flipper did not come back after the drain")
	table.flipper_left.release()
	await wait(0.2)
	table.auto_respawn = false
	finish()


## 6 — a press landing inside Feel.INPUT_BUFFER of the bat coming home must still fire.
func _s6_input_buffer() -> void:
	begin("input buffer on the down-stroke")
	table.despawn_ball()
	await step(2)
	var f := table.flipper_left

	f.press()
	await wait(Feel.FLIPPER_UP_TIME + 0.01)
	check(f.state == Flipper.State.HELD, "flipper never reached full extension")
	f.release()

	var lead := 0.030
	await wait(maxf(Feel.FLIPPER_DOWN_TIME - lead, 0.0))
	check(f.state == Flipper.State.FALLING,
			"flipper already home before the buffered press (state %d)" % f.state)
	var before := int(_fired[&"left"])
	f.press()
	f.release()                                    # a tap, not a hold: the buffer must carry it
	check(int(_fired[&"left"]) == before, "flipper fired mid-return instead of buffering")

	var fired_after := -1
	for t in range(ticks(0.09)):
		await step(1)
		if int(_fired[&"left"]) > before:
			fired_after = t
			break
	print("        buffered press fired %d ticks after the tap" % fired_after)
	check(fired_after >= 0, "buffered press was dropped")
	check(fired_after <= ticks(lead) + 3,
			"buffered press fired %d ticks late" % fired_after)
	f.release()
	await wait(0.2)
	finish()


# ---------------------------------------------------------------- helpers

## Drop a ball 40 px above the middle of the left bat, flipper at rest.
func _place_on_bat() -> void:
	table.auto_respawn = false
	table.despawn_ball()
	table.flipper_left.set_pressed(false)
	table.flipper_right.set_pressed(false)
	# the bat must be genuinely home before its cradle point means anything
	for i in range(ticks(0.5)):
		await step(1)
		if table.flipper_left.state == Flipper.State.REST:
			break
	table.spawn_ball()
	var f := table.flipper_left
	var b := ball()
	b.place(f.cradle_point(0.5) + f.strike_normal() * 12.0)
	await step(1)
