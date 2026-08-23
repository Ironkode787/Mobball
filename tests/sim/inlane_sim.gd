extends Node2D
## Regression for a device report: the ball wedged between the inlane return sweep and the
## slingshot and sat there. The pinch was 51px wide against a 56px ball, and it landed on the
## sling's square corner — no sensor band, so no kick. Ball search does reach it, but only
## after BALL_SEARCH_DELAY (5s) of a dead-still ball, which is not a save, it is a stall.
##
## Both feeds are driven here, on the bare starter table: its slings are dead rubber, so
## nothing can bail the lane out and the geometry has to be right on its own.

const TABLE := preload("res://game/table/table_main.tscn")

## A ball crawling this slowly in the lane is not rolling, it is parked.
const CRAWL_SPEED := 60.0
## Well under the table's 5s ball search: the coil must never be what rescues a feed.
const STALL_LIMIT := 1.0
const FEED_SPEED := 520.0
const ARRIVE_RADIUS := 90.0
const BUDGET_SECONDS := 4.0

var table: Node2D = null
var failures := 0
var scenarios := 0


func _ready() -> void:
	table = TABLE.instantiate()
	add_child(table)
	table.set("auto_respawn", false)
	await _run()


func _run() -> void:
	print("== KINGPIN inlane feed sim ==")
	print("physics %d Hz | ball %.0fpx | stall limit %.2fs"
			% [Engine.physics_ticks_per_second, Feel.BALL_RADIUS * 2.0, STALL_LIMIT])
	await _frames(6)

	await _feed(1.0, "left")
	await _feed(-1.0, "right")

	print("---")
	print("scenarios: %d  passed: %d  failed: %d" % [scenarios, scenarios - failures, failures])
	print("OK" if failures == 0 else "FAILED")
	get_tree().quit(0 if failures == 0 else 1)


## Roll a ball down one return sweep and watch it all the way to the flipper.
func _feed(s: float, side: String) -> void:
	var a := _mx(ProgressionTable.OUTLANE_X, s, ProgressionTable.OUTLANE_BOTTOM)
	var b := _mx(ProgressionTable.INLANE_END.x, s, ProgressionTable.INLANE_END.y)
	var pivot: Vector2 = table.get("flipper_left").position if s > 0.0 \
			else table.get("flipper_right").position

	# Enter the lane up-field of the pinch, riding the guide's face.
	var along := (b - a).normalized()
	var up_lane := _lane_normal(a, b, s)
	var entry := a.lerp(b, 0.10) + up_lane * (ProgressionTable.GUIDE_THICK * 0.5 \
			+ Feel.BALL_RADIUS + 2.0)

	table.despawn_ball()
	await _frames(2)
	var ball: Ball = table.spawn_ball()
	ball.place(entry)
	ball.set_velocity(along * FEED_SPEED)

	var stalled := 0.0
	var worst := 0.0
	var arrived := false
	var where := Vector2.ZERO
	var tick := 1.0 / float(Engine.physics_ticks_per_second)
	for i in int(BUDGET_SECONDS * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		if not is_instance_valid(ball):
			break
		var p := ball.global_position
		if p.distance_to(pivot) <= ARRIVE_RADIUS or p.y > pivot.y:
			arrived = true
			break
		# Only the lane itself is under test; a ball that bounces back up-field has not
		# wedged, and the open playfield is somebody else's scenario.
		if _near_segment(p, a, b) <= 120.0 and ball.speed() < CRAWL_SPEED:
			stalled += tick
			if stalled > worst:
				worst = stalled
				where = p
		else:
			stalled = 0.0

	print("        %s feed: %s | longest still %.2fs%s" % [
			side,
			"reached the flipper" if arrived else "never reached the flipper",
			worst,
			"" if worst <= 0.0 else " at (%.0f, %.0f)" % [where.x, where.y]])
	_check(arrived and worst <= STALL_LIMIT,
			"%s inlane feeds the flipper without wedging" % side)
	table.despawn_ball()
	await _frames(4)


## The lane side of the guide bar: whichever normal faces the sling triangle.
func _lane_normal(a: Vector2, b: Vector2, s: float) -> Vector2:
	var n := (b - a).normalized().orthogonal()
	var sling := _mx(ProgressionTable.SLING_INNER.x, s, ProgressionTable.SLING_INNER.y)
	return n if n.dot(sling - (a + b) * 0.5) > 0.0 else -n


func _near_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var u := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * u)


func _mx(x: float, s: float, y: float) -> Vector2:
	return Vector2(x if s > 0.0 else ProgressionTable.MIRROR_X * 2.0 - x, y)


func _check(cond: bool, msg: String) -> void:
	scenarios += 1
	if cond:
		print("  [PASS] " + msg)
	else:
		failures += 1
		printerr("  [FAIL] " + msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
