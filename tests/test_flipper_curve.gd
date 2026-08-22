extends RefCounted
## Rotation-curve math for the flipper bat (game/core/flipper_curve.gd).


func run(t: TestCtx) -> void:
	_easing(t)
	_strokes(t)
	_rotation(t)


func _easing(t: TestCtx) -> void:
	t.near(FlipperCurve.ease_up(0.0), 0.0, 1e-6, "ease_up starts at 0")
	t.near(FlipperCurve.ease_up(1.0), 1.0, 1e-6, "ease_up ends at 1")
	t.near(FlipperCurve.ease_down(0.0), 0.0, 1e-6, "ease_down starts at 0")
	t.near(FlipperCurve.ease_down(1.0), 1.0, 1e-6, "ease_down ends at 1")
	t.near(FlipperCurve.ease_up(-3.0), 0.0, 1e-6, "ease_up clamps below 0")
	t.near(FlipperCurve.ease_up(9.0), 1.0, 1e-6, "ease_up clamps above 1")

	# the up-stroke has to front-load its travel or the bat doesn't read as a solenoid
	t.ok(FlipperCurve.ease_up(0.25) > 0.25, "ease_up is fast off the stop")
	t.ok(FlipperCurve.ease_up(0.5) > 0.5, "ease_up stays ahead of linear")
	# the return is the opposite: it lets go gently
	t.ok(FlipperCurve.ease_down(0.25) < 0.25, "ease_down is slow off the top")

	var prev_up := -1.0
	var prev_down := -1.0
	for i in range(41):
		var x := float(i) / 40.0
		var u := FlipperCurve.ease_up(x)
		var d := FlipperCurve.ease_down(x)
		t.ok(u >= prev_up, "ease_up monotonic at %f" % x)
		t.ok(d >= prev_down, "ease_down monotonic at %f" % x)
		t.ok(u >= 0.0 and u <= 1.0, "ease_up in range at %f" % x)
		t.ok(d >= 0.0 and d <= 1.0, "ease_down in range at %f" % x)
		prev_up = u
		prev_down = d


func _strokes(t: TestCtx) -> void:
	t.near(FlipperCurve.up_progress(0.0), 0.0, 1e-6, "up-stroke starts at rest")
	t.near(FlipperCurve.up_progress(Feel.FLIPPER_UP_TIME), 1.0, 1e-6, "up-stroke completes on time")
	t.near(FlipperCurve.up_progress(Feel.FLIPPER_UP_TIME * 4.0), 1.0, 1e-6, "up-stroke saturates")

	t.near(FlipperCurve.down_progress(0.0, 1.0), 1.0, 1e-6, "return starts where it was")
	t.near(FlipperCurve.down_progress(Feel.FLIPPER_DOWN_TIME, 1.0), 0.0, 1e-6, "return reaches rest")
	t.near(FlipperCurve.down_remaining(0.0, 1.0), Feel.FLIPPER_DOWN_TIME, 1e-6,
			"a full return owes the full down time")
	t.near(FlipperCurve.down_remaining(Feel.FLIPPER_DOWN_TIME, 1.0), 0.0, 1e-6,
			"a finished return owes nothing")

	# releasing halfway up only spends half the return time
	var half := Feel.FLIPPER_DOWN_TIME * 0.5
	t.near(FlipperCurve.down_progress(half, 0.5), 0.0, 1e-6, "partial return reaches rest early")
	t.near(FlipperCurve.down_remaining(0.0, 0.5), half, 1e-6, "partial return owes half the time")
	t.ok(FlipperCurve.down_progress(half * 0.5, 0.5) < 0.5, "partial return actually descends")


func _rotation(t: TestCtx) -> void:
	for side: StringName in [&"left", &"right"]:
		t.near(FlipperCurve.rotation_for(side, 0.0), Feel.flipper_rest_rotation(side), 1e-6,
				"%s bat rests at the rest angle" % side)
		t.near(FlipperCurve.rotation_for(side, 1.0), Feel.flipper_up_rotation(side), 1e-6,
				"%s bat tops out at the up angle" % side)

	# both bats sweep the same amount, mirrored: tips must end up above the pivot line
	var sweep_l := absf(Feel.flipper_up_rotation(&"left") - Feel.flipper_rest_rotation(&"left"))
	var sweep_r := absf(Feel.flipper_up_rotation(&"right") - Feel.flipper_rest_rotation(&"right"))
	t.near(sweep_l, sweep_r, 1e-6, "left and right sweep the same arc")
	t.ok(sweep_l > deg_to_rad(30.0), "sweep is a real flipper stroke")

	for side: StringName in [&"left", &"right"]:
		var rest_tip := Vector2(Feel.FLIPPER_LENGTH, 0.0).rotated(Feel.flipper_rest_rotation(side))
		var up_tip := Vector2(Feel.FLIPPER_LENGTH, 0.0).rotated(Feel.flipper_up_rotation(side))
		t.ok(rest_tip.y > 0.0, "%s tip hangs below the pivot at rest" % side)
		t.ok(up_tip.y < 0.0, "%s tip is above the pivot when flipped" % side)
		var inward := 1.0 if side == &"left" else -1.0
		t.ok(rest_tip.x * inward > 0.0, "%s bat points inward" % side)
		t.ok(up_tip.x * inward > 0.0, "%s bat still points inward when flipped" % side)
