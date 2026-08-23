extends Node
## DEVICE INPUT PROBE — run windowed (xvfb) at a phone resolution. Boots the real game,
## presses the real buttons with synthesized hardware touches (Input.parse_input_event →
## the full input pipeline, including emulate_mouse_from_touch), and screenshots each step
## to SHOT_DIR. Exit 0 only if every step lands. This is the harness for "it works on my
## desktop" bugs.

var shots_dir := "/tmp/device_probe"
var failures := 0


var main: Node = null


func _ready() -> void:
	var env := OS.get_environment("SHOT_DIR")
	if not env.is_empty():
		shots_dir = env
	DirAccess.make_dir_recursive_absolute(shots_dir)
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(main)
	_run()


func _run() -> void:
	await _frames(40)
	await _shot("1_attract")

	# ATTRACT → NIGHT via a real touch on ROLL CALL.
	var roll := _find_button(get_tree().root, "ROLL CALL")
	_check(roll != null, "ROLL CALL button exists")
	if roll != null:
		await _tap(roll)
		await _frames(30)
	_check(Game.state == &"night", "touch on ROLL CALL starts the night (state=%s)" % Game.state)
	await _shot("2_night")

	# Reach The Count fast: force-drain the guys (programmatic — input is not under test here).
	for i in 6:
		if Game.state != &"night":
			break
		var table: Node2D = main.get("table")
		var ball: Ball = table.get("ball")
		if ball != null and is_instance_valid(ball):
			ball.global_position = Vector2(490.0, 1885.0)
			ball.linear_velocity = Vector2(0, 400)
		await _frames(90)
	_check(Game.state == &"count", "the Night reached The Count (state=%s)" % Game.state)
	await _shot("3_count")

	# COUNT → LEDGER via a real touch on THE LEDGER. This is the user's bug report.
	var ledger_btn := _find_button(get_tree().root, "THE LEDGER")
	_check(ledger_btn != null, "THE LEDGER button exists on The Count")
	if ledger_btn != null:
		await _tap(ledger_btn)
		await _frames(30)
	_check(Game.state == &"ledger", "touch on THE LEDGER opens the Ledger (state=%s)" % Game.state)
	var overlay: Node = main.get("ledger")
	var overlay_visible: bool = overlay != null and is_instance_valid(overlay) \
			and overlay.get("visible") == true
	_check(overlay_visible, "the Ledger overlay exists and is visible")
	await _shot("4_ledger")

	# And back.
	var close_btn := _find_button(get_tree().root, "CLOSE")
	if close_btn != null:
		await _tap(close_btn)
		await _frames(20)
		_check(Game.state == &"count", "CLOSE returns to The Count (state=%s)" % Game.state)
	await _shot("5_back")

	print("DEVICE PROBE: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func _tap(c: Control) -> void:
	# Touch at the control's on-screen center, through the real pipeline.
	var center := c.get_global_rect().get_center()
	var xform := c.get_viewport().get_final_transform() * c.get_canvas_transform()
	# Controls under a CanvasLayer use the layer's transform; get_global_rect is in canvas
	# space, so map to window space with the final transform of that canvas.
	var screen_pos: Vector2 = xform * center
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = screen_pos
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(6)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = screen_pos
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(6)


func _find_button(node: Node, text: String) -> Control:
	if node is Button and (node as Button).text == text and (node as Button).is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] " + msg)
	else:
		failures += 1
		printerr("  [FAIL] " + msg)


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
