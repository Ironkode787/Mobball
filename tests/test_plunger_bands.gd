extends RefCounted
## Focused contracts for the starter rubber-band agency and the free bad-break window.


class _TableStub:
	extends Node2D

	var ball: Ball = null

	func despawn_ball() -> void:
		ball = null


func run(t: TestCtx) -> void:
	_starter_bands(t)
	_starter_press_latch(t)
	_touch_plunger_paths(t)
	_live_launch_and_loss(t)


func _starter_bands(t: TestCtx) -> void:
	var plunger := BandedPlunger.new()
	t.eq(BandedPlunger.STARTER_POWERS, [0.945, 0.97, 0.99],
			"starter powers are the three Drop-Off lanes: right, centre, left")
	plunger.set_starter_pull(0.0)
	t.near(plunger.starter_power(), 0.945, 1e-9, "short pull selects the safe low band")
	plunger.set_starter_pull(BandedPlunger.STARTER_BAND_DISTANCE_PX)
	t.near(plunger.starter_power(), 0.97, 1e-9, "middle pull selects the middle band")
	plunger.set_starter_pull(BandedPlunger.STARTER_BAND_DISTANCE_PX * 2.0)
	t.near(plunger.starter_power(), 0.99, 1e-9, "long pull selects the high band")
	var selected := plunger.starter_band
	plunger.bands_enabled = true
	plunger.set_starter_pull(0.0)
	t.eq(plunger.starter_band, selected,
			"real-plunger mode leaves the coarse band untouched")


func _starter_press_latch(t: TestCtx) -> void:
	var plunger := BandedPlunger.new()
	var ball := Ball.new()
	plunger.lane_rect = Rect2(-20.0, -20.0, 40.0, 40.0)
	plunger.set_ball(ball)

	# A release without a ready press must be inert, including a release after the ball left
	# the lane. This is the stale-touch protection the starter path needs.
	plunger.set_pressed(false)
	t.ok(not ball.launched, "starter release without a press does not launch")
	plunger.set_pressed(true)
	ball.position = Vector2(100.0, 100.0)
	plunger.set_pressed(false)
	t.ok(not ball.launched, "starter release after the ball leaves the lane is inert")

	ball.position = Vector2.ZERO
	plunger.set_pressed(true)
	plunger.set_pressed(false)
	t.ok(ball.launched, "a ready starter press arms and release launches")


func _touch_plunger_paths(t: TestCtx) -> void:
	var input := InputController.new()
	var starter := BandedPlunger.new()
	var starter_ball := Ball.new()
	starter.lane_rect = Rect2(-20.0, -20.0, 40.0, 40.0)
	starter.set_ball(starter_ball)
	input.bind(null, null, starter, null)

	# A lane tap uses the desktop-equivalent middle band and releases through the latch.
	input._on_touch(_touch(1, Vector2(960.0, 1200.0), true))
	input._on_touch(_touch(1, Vector2(960.0, 1200.0), false))
	t.eq(starter.starter_band, BandedPlunger.DEFAULT_STARTER_BAND,
			"starter lane tap selects the default middle band")
	t.ok(starter_ball.launched, "starter lane tap launches on release")

	# A longer pull selects the top band before the same release edge fires.
	starter_ball.launched = false
	starter_ball.linear_velocity = Vector2.ZERO
	input._on_touch(_touch(2, Vector2(960.0, 1200.0), true))
	input._on_drag(_drag(2, Vector2(960.0, 1200.0 + BandedPlunger.STARTER_BAND_DISTANCE_PX * 2.0)))
	input._on_touch(_touch(2, Vector2(960.0, 1328.0), false))
	t.eq(starter.starter_band, 2, "starter lane drag selects the top coarse band")
	t.ok(starter_ball.launched, "starter lane drag launches on release")

	# Real Plunger keeps the inherited continuous charge path on the same touch role.
	var real := Plunger.new()
	var real_ball := Ball.new()
	real.lane_rect = Rect2(-20.0, -20.0, 40.0, 40.0)
	real.set_ball(real_ball)
	input.bind(null, null, real, null)
	input._on_touch(_touch(3, Vector2(960.0, 1200.0), true))
	t.ok(real.charging, "real plunger starts continuous charge on lane touch-down")
	real._physics_process(0.20)
	t.ok(real.power > 0.0 and real.power < 1.0,
			"real plunger touch charge remains continuous before release")
	input._on_touch(_touch(3, Vector2(960.0, 1200.0), false))
	t.ok(real_ball.launched, "real plunger touch release launches the charged ball")


func _live_launch_and_loss(t: TestCtx) -> void:
	_bad_break_does_not_spend_paid_save(t)
	_live_paid_save_consumes_charge(t)
	_free_save_expires_without_a_charge(t)
	_tilt_bypasses_saves(t)
	_meeting_save_order(t)


func _bad_break_does_not_spend_paid_save(t: TestCtx) -> void:
	var night := NightController.new()
	var ball := Ball.new()
	var guy := {"id": 42, "name": "test"}
	night.running = true
	night.saves_left = 1
	night._ball_guys[ball.get_instance_id()] = guy
	night._on_ball_launched(ball, 0.95)
	var rows: Array = night._saves[ball.get_instance_id()]
	t.eq(rows.size(), 2, "a shooter launch arms free and paid windows together")

	night._on_ball_lost(ball)
	t.eq(night.saves_left, 1, "a live free bad-break return leaves Second Wind charged")
	t.ok(night._bad_break_used.has(42), "live free bad-break return is consumed for the guy")
	t.ok(night._saves.is_empty(), "drained ball bookkeeping is cleaned after a free return")
	t.eq(night._serve_in, 0.4, "a saved single-ball drain queues a fresh shooter serve")

	# The next shooter ball has a normal paid launch window, but no second free grace.
	var fresh := Ball.new()
	night._ball_guys[fresh.get_instance_id()] = guy
	night._on_ball_launched(fresh, 0.95)
	var fresh_rows: Array = night._saves[fresh.get_instance_id()]
	t.eq(fresh_rows.size(), 1, "fresh saved-ball serve re-arms the paid window")
	t.eq(bool((fresh_rows[0] as Dictionary).get("free", true)), false,
			"one-use bad-break protection is not re-armed on the fresh serve")


func _live_paid_save_consumes_charge(t: TestCtx) -> void:
	var night := NightController.new()
	var ball := Ball.new()
	var guy := {"id": 43, "name": "paid"}
	night.running = true
	night.saves_left = 1
	night._bad_break_used[43] = true
	night._ball_guys[ball.get_instance_id()] = guy
	night._on_ball_launched(ball, 0.95)
	night._on_ball_lost(ball)
	t.eq(night.saves_left, 0, "a live paid save consumes one Second Wind charge")
	t.ok(night._saves.is_empty(), "paid saved-ball bookkeeping is cleaned after the return")


func _free_save_expires_without_a_charge(t: TestCtx) -> void:
	var night := NightController.new()
	var ball := Ball.new()
	night.saves_left = 1
	night._arm_save(ball, NightController.BAD_BREAK_SAVE_SECONDS, true,
			NightController.BAD_BREAK_SAVE_KIND)
	night._tick_balls(NightController.BAD_BREAK_SAVE_SECONDS + 0.1)
	t.ok(night._take_save(ball).is_empty(), "an expired free window cannot catch a later drain")
	t.eq(night.saves_left, 1, "an expired free window does not consume Second Wind")


func _tilt_bypasses_saves(t: TestCtx) -> void:
	var night := NightController.new()
	var table := _TableStub.new()
	var ball := Ball.new()
	table.ball = ball
	night.table = table
	night.running = true
	night.saves_left = 1
	night._arm_save(ball, NightController.BAD_BREAK_SAVE_SECONDS, true,
			NightController.BAD_BREAK_SAVE_KIND)
	night._arm_save(ball, NightController.BALL_SAVE_SECONDS, false)
	night._on_tilted()
	t.eq(night.saves_left, 1, "tilt bypasses saves without consuming Second Wind")
	t.ok(night._saves.is_empty(), "tilt clears both per-ball save windows")
	t.eq(night.tilts, 1, "tilt still records the Inspector event")


func _meeting_save_order(t: TestCtx) -> void:
	var prior_active := Game.meeting.active
	Game.meeting.active = true
	var night := NightController.new()
	var guy := {"id": 44, "name": "meeting"}
	night.running = true
	night.saves_left = 1
	night._ball_guys.clear()

	var free_ball := Ball.new()
	night._ball_guys[free_ball.get_instance_id()] = guy
	night._on_ball_launched(free_ball, 0.95)
	night._on_ball_lost(free_ball)
	t.eq(night.saves_left, 1, "Meeting primary drain takes free protection first")
	t.ok(Game.meeting.active, "a free Meeting save does not end the Meeting")

	var paid_ball := Ball.new()
	night._ball_guys[paid_ball.get_instance_id()] = guy
	# The real save beat has elapsed before the fresh serve is launched.
	night._serve_in = -1.0
	night._on_ball_launched(paid_ball, 0.95)
	night._on_ball_lost(paid_ball)
	t.eq(night.saves_left, 0, "Meeting primary drain then spends the paid charge")
	t.ok(Game.meeting.active, "a paid Meeting save also leaves mode state to the Meeting flow")
	Game.meeting.active = prior_active


func _touch(index: int, position: Vector2, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = position
	ev.pressed = pressed
	return ev


func _drag(index: int, position: Vector2) -> InputEventScreenDrag:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = position
	return ev
