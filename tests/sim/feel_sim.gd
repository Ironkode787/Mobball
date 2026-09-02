extends SimBase
## The feel gate for the 3D machine (docs/01 §2): the ball rolls, flips have the pace real
## machines have, a held bat traps, the plunger serves, and a random soak never tunnels,
## never escapes the cabinet, and never wedges.

const SEED := 0x4B494E47
const FLIP_MIN_SPEED := 14.0
const FLIP_MAX_SPEED := 70.0
const SOAK_SECONDS := 25.0

var _rng := RandomNumberGenerator.new()
var _fired: Dictionary = {&"left": 0, &"right": 0}
var _drains: int = 0


func _ready() -> void:
	_rng.seed = SEED
	make_table(false)
	Events.flipper_fired.connect(func(side: StringName) -> void: _fired[side] = int(_fired[side]) + 1)
	table.ball_lost.connect(func(_b: Ball) -> void: _drains += 1)
	_run()


func _run() -> void:
	print("== KINGPIN feel sim (3D) ==")
	await _s_roll_and_drain()
	await _s_plunge_serves()
	await _s_flip_pace()
	await _s_trap()
	await _s_soak()
	report("feel")


## 1 — a ball let go mid-field rolls down the incline and drains between the bats.
func _s_roll_and_drain() -> void:
	begin("a loose ball rolls down and drains")
	var b := await drop_at(Vector2(Layout.MIRROR_X, 1.5))
	var w := await watch(4.0, b)
	check(not w["alive"], "the ball never drained")
	check(_drains >= 1, "no ball_lost")
	check(not w["escaped"], "the ball left the cabinet")
	finish()


## 2 — the starter plunger puts the ball on the field from rest.
func _s_plunge_serves() -> void:
	begin("the plunger serves onto the field")
	table.despawn_ball()
	var b := table.spawn_ball()
	await wait(0.3)
	check(table.plunger.ball_ready(), "a resting ball in the lane is not plungeable")
	table.plunger.launch(0.55)
	var reached := false
	for i in range(ticks(3.0)):
		await step(1)
		if b == null or not is_instance_valid(b):
			break
		if b.table_position().x < Layout.DIVIDER_X - 0.2:
			reached = true
			break
	check(reached, "the soft band never left the shooter lane")
	table.despawn_ball()
	finish()


## 3 — a flip off a resting bat sends the ball up-field at real pace.
func _s_flip_pace() -> void:
	begin("a flip has pinball pace")
	for side: StringName in [&"left", &"right"]:
		var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
		var at := f.cradle_point(0.6)
		table.despawn_ball()
		await step(2)
		var b := table.spawn_ball()
		b.place(at + Vector3(0.0, 0.01, 0.0))
		await wait(0.25)
		f.press()
		var top := 0.0
		var min_z := INF
		for i in range(ticks(0.6)):
			await step(1)
			if b == null or not is_instance_valid(b):
				break
			top = maxf(top, b.speed())
			min_z = minf(min_z, b.table_position().z)
		f.release()
		check(top >= FLIP_MIN_SPEED and top <= FLIP_MAX_SPEED,
				"%s flip peaked at %.1f u/s (want %.0f–%.0f)" % [side, top, FLIP_MIN_SPEED, FLIP_MAX_SPEED])
		check(min_z < 2.0, "%s flip did not send the ball up the field (min z %.2f)" % [side, min_z])
		await wait(0.3)
	check(int(_fired[&"left"]) >= 1 and int(_fired[&"right"]) >= 1, "flipper_fired did not fire for both bats")
	table.despawn_ball()
	finish()


## 4 — a ball rolling down onto a held bat comes to rest against it (the live catch).
func _s_trap() -> void:
	begin("a held bat traps a slow ball")
	var f := table.flipper_left
	table.despawn_ball()
	await step(2)
	f.press()
	await wait(0.2)
	var b := table.spawn_ball()
	var at := f.cradle_point(0.55)
	b.place(at + Vector3(0.0, 0.5, -0.4))
	var w := await watch(2.5, b)
	check(w["alive"], "the trapped ball drained")
	if w["alive"]:
		check(b.speed() < 1.5, "the ball is still moving at %.2f u/s on a held bat" % b.speed())
		var p := b.table_position()
		check(p.z > 3.6 and p.x < Layout.MIRROR_X, "the ball did not settle on the left bat (%s)" % str(p))
	f.release()
	table.despawn_ball()
	finish()


## 5 — chaos: random plunges and flips for a while. Nothing leaves the cabinet, nothing
## sits still where a ball has no business sitting still.
func _s_soak() -> void:
	begin("soak: %d s of random play" % int(SOAK_SECONDS))
	table.auto_respawn = true
	table.despawn_ball()
	table.spawn_ball()
	var worst_still := 0
	var worst_at := Vector3.ZERO
	var still := 0
	var last := Vector3.INF
	var escapes := 0
	var bounds := table.bounds()
	var flips := 0
	var lane_box := table.lane_box()
	for i in range(ticks(SOAK_SECONDS)):
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			continue
		if table.plunger.ball_ready() and i % 60 == 0:
			table.plunger.launch(_rng.randf_range(0.5, 1.0))
		var p := b.table_position()
		if not bounds.has_point(p):
			escapes += 1
		if p.z > 2.5 and _rng.randf() < 0.05:
			var f := table.flipper_left if p.x < Layout.MIRROR_X else table.flipper_right
			f.press()
			flips += 1
			get_tree().create_timer(_rng.randf_range(0.08, 0.3)).timeout.connect(f.release)
		var resting_in_lane := lane_box.has_point(p)
		if last != Vector3.INF and p.distance_to(last) < 0.002 and not resting_in_lane and not BallHold.is_held(b):
			still += 1
			if still > worst_still:
				worst_still = still
				worst_at = p
		else:
			still = 0
		last = p
	check(escapes == 0, "the ball left the cabinet %d ticks" % escapes)
	check(worst_still < ticks(4.0), "a ball sat still for %.1f s at %s" % [float(worst_still) / float(Engine.physics_ticks_per_second), str(worst_at)])
	check(flips > 5, "the soak barely flipped (%d)" % flips)
	for f: Flipper in [table.flipper_left, table.flipper_right]:
		var walked := f.position.distance_to(f.pivot())
		check(walked < 0.0005, "the %s bat walked %.4f u off its pivot" % [f.side, walked])
	print("        %d flips, %d drains, longest still %.1fs" % [flips, _drains, float(worst_still) / float(Engine.physics_ticks_per_second)])
	table.auto_respawn = false
	table.despawn_ball()
	finish()
