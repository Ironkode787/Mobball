extends RefCounted
## Deterministic touch-role and nudge-intent coverage for game/core/input_controller.gd.

const SCREEN := Vector2(1080.0, 1920.0)


class _NudgeSpy:
	extends NudgeController

	var calls: Array[StringName] = []

	func nudge(direction: StringName) -> bool:
		calls.append(direction)
		return true


func run(t: TestCtx) -> void:
	_roles(t)
	_intents(t)
	_live_touch_gestures(t)


func _roles(t: TestCtx) -> void:
	t.eq(InputController.classify_touch_role(Vector2(100.0, 100.0), SCREEN), &"nudge_left",
			"left corner is an immediate left-nudge role")
	t.eq(InputController.classify_touch_role(Vector2(980.0, 100.0), SCREEN), &"nudge_right",
			"right corner is an immediate right-nudge role")
	t.eq(InputController.classify_touch_role(Vector2(540.0, 500.0), SCREEN), &"flick",
			"upper centre remains the flick field")
	t.eq(InputController.classify_touch_role(Vector2(100.0, 900.0), SCREEN), &"flip_left",
			"lower left remains a flipper role")
	t.eq(InputController.classify_touch_role(Vector2(900.0, 900.0), SCREEN), &"flip_right",
			"lower right remains a flipper role")
	# This is intentionally checked after the corner tests: lane precedence must win if the
	# authored lane is ever moved upward into a corner target in a future table.
	t.eq(InputController.classify_touch_role(Vector2(960.0, 1200.0), SCREEN), &"lane",
			"shooter lane wins over all nudge roles")
	t.eq(Feel.NUDGE_IMPULSE, 360.0, "baseline nudge impulse is the mobile-feel value")


func _intents(t: TestCtx) -> void:
	t.eq(InputController.corner_nudge_direction(&"nudge_left"), &"left",
			"left corner maps to left nudge")
	t.eq(InputController.corner_nudge_direction(&"nudge_right"), &"right",
			"right corner maps to right nudge")
	t.eq(InputController.drag_nudge_direction(&"flick", Vector2(0.0, -90.0), 0.10), &"up",
			"quick upward flick maps to up nudge")
	t.eq(InputController.drag_nudge_direction(&"flick", Vector2(-120.0, 8.0), 0.10), &"left",
			"quick horizontal flick keeps left nudge")
	t.eq(InputController.drag_nudge_direction(&"flip_left", Vector2(120.0, 0.0), 0.10), &"right",
			"quick flipper-zone drag adds right nudge")
	t.eq(InputController.drag_nudge_direction(&"flip_right", Vector2(-120.0, 0.0), 0.10), &"left",
			"quick right-zone drag adds left nudge")
	t.eq(InputController.drag_nudge_direction(&"lane", Vector2(120.0, -120.0), 0.10), &"",
			"shooter lane never becomes a nudge drag")
	t.eq(InputController.drag_nudge_direction(&"flick", Vector2(120.0, 0.0), 0.181), &"",
			"slow drag misses the quick-flick window")


func _live_touch_gestures(t: TestCtx) -> void:
	var spy := _NudgeSpy.new()
	var input := InputController.new()
	var left := Flipper.new()
	var right := Flipper.new()
	right.side = &"right"
	input.bind(left, right, Plunger.new(), spy)

	# A corner tap fires on touch-down and never fires again if the finger later moves.
	input._on_touch(_touch(1, Vector2(100.0, 100.0), true))
	t.eq(spy.calls.size(), 1, "corner tap nudges immediately on touch-down")
	t.eq(spy.calls[0], &"left", "left corner tap has left direction")
	input._on_drag(_drag(1, Vector2(250.0, 100.0)))
	t.eq(spy.calls.size(), 1, "corner gesture can issue only one nudge")
	input._on_touch(_touch(1, Vector2(250.0, 100.0), false))

	# The bat remains held while the horizontal drag is interpreted, and the original role
	# remains available to the touch-up path so release cannot be swallowed by the nudge.
	input._on_touch(_touch(2, Vector2(100.0, 900.0), true))
	t.ok(left.is_held(), "flipper-zone touch presses the left bat")
	input._on_drag(_drag(2, Vector2(230.0, 900.0)))
	t.eq(spy.calls.size(), 2, "flipper-zone horizontal drag nudges once")
	t.ok(left.is_held(), "horizontal nudge does not consume the left flip")
	input._on_drag(_drag(2, Vector2(320.0, 900.0)))
	t.eq(spy.calls.size(), 2, "repeated drag updates do not add a second nudge")
	input._on_touch(_touch(2, Vector2(320.0, 900.0), false))
	t.ok(not left.is_held(), "touch-up still releases the flipper after a nudge")

	# The mirrored zone gets the same additive path: right bat stays held, then releases, and
	# repeated drag events still count as one gesture nudge.
	input._on_touch(_touch(5, Vector2(900.0, 900.0), true))
	t.ok(right.is_held(), "flipper-zone touch presses the right bat")
	input._on_drag(_drag(5, Vector2(760.0, 900.0)))
	t.eq(spy.calls.size(), 3, "right flipper-zone horizontal drag nudges once")
	t.ok(right.is_held(), "right horizontal nudge does not consume the flip")
	input._on_drag(_drag(5, Vector2(650.0, 900.0)))
	t.eq(spy.calls.size(), 3, "right repeated drag remains one nudge")
	input._on_touch(_touch(5, Vector2(650.0, 900.0), false))
	t.ok(not right.is_held(), "right touch-up releases after a nudge")

	# A top-field upward flick is a distinct direction and also obeys one-per-gesture.
	input._on_touch(_touch(3, Vector2(540.0, 500.0), true))
	input._on_drag(_drag(3, Vector2(540.0, 380.0)))
	t.eq(spy.calls.size(), 4, "upward flick registers one up nudge")
	t.eq(spy.calls[3], &"up", "upward flick direction is up")
	input._on_drag(_drag(3, Vector2(540.0, 250.0)))
	t.eq(spy.calls.size(), 4, "upward flick remains one nudge")
	input._on_touch(_touch(3, Vector2(540.0, 250.0), false))

	# Lane touches keep their shooter role even when the drag has a nudge-sized horizontal and
	# upward component.
	input._on_touch(_touch(4, Vector2(960.0, 1200.0), true))
	input._on_drag(_drag(4, Vector2(1080.0, 1080.0)))
	t.eq(spy.calls.size(), 4, "shooter-lane drag has nudge precedence protection")
	input._on_touch(_touch(4, Vector2(1080.0, 1080.0), false))


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
