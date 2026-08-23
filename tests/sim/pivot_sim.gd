extends Node2D
## Regression for the first device bug report: a ball resting on the flipper's pivot dome
## sits at the center of rotation, so flipping used to leave it exactly where it lay.
## Scenario 1: an un-flipped nap ends on the stall timer. Scenario 2: a flip clears it now.

const TABLE := preload("res://game/table/segments/alley_debug.tscn")

var table: Node2D = null
var failures := 0


func _ready() -> void:
	table = TABLE.instantiate()
	add_child(table)
	table.set("auto_respawn", false)
	await _run()


func _run() -> void:
	await _frames(10)
	var flipper: Node2D = table.get("flipper_left")
	var rest := _park_on_pivot(flipper)
	# 1 — the stall timer pops an un-flipped nap.
	var freed := false
	var budget := int((Feel.FLIPPER_PIVOT_STALL_SECONDS + 1.5) * 120.0)
	for i in budget:
		await get_tree().physics_frame
		if not is_instance_valid(rest):
			break
		if rest.global_position.distance_to(flipper.global_position) > 130.0 \
				or rest.linear_velocity.length() > 150.0:
			freed = true
			break
	_check(freed, "stall timer pops a pivot nap within %.1fs"
			% (Feel.FLIPPER_PIVOT_STALL_SECONDS + 1.5))
	if is_instance_valid(rest):
		rest.queue_free()
	await _frames(20)

	# 2 — a flip always disturbs a pivot sitter, immediately.
	var rest2 := _park_on_pivot(flipper)
	flipper.call("press")
	var cleared := false
	for i in 60:
		await get_tree().physics_frame
		if not is_instance_valid(rest2):
			break
		if rest2.global_position.distance_to(flipper.global_position) > 130.0 \
				or rest2.linear_velocity.length() > 150.0:
			cleared = true
			break
	_check(cleared, "a flip clears the pivot sitter within half a second")
	flipper.call("release")

	print("---")
	print("scenarios: 2  passed: %d  failed: %d" % [2 - failures, failures])
	print("OK" if failures == 0 else "FAILED")
	get_tree().quit(0 if failures == 0 else 1)


## Drop a ball dead onto the pivot dome and let it settle until it is truly napping.
func _park_on_pivot(flipper: Node2D) -> Ball:
	var b: Ball = (preload("res://game/core/ball.tscn") as PackedScene).instantiate()
	add_child(b)
	b.global_position = flipper.global_position \
			+ Vector2(0, -(Feel.FLIPPER_PIVOT_RADIUS + Feel.BALL_RADIUS + 1.0))
	b.linear_velocity = Vector2.ZERO
	return b


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] " + msg)
	else:
		failures += 1
		printerr("  [FAIL] " + msg)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
