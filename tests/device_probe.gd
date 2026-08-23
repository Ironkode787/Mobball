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

	# PINCH ZOOM (device request): two fingers diverging over the board must zoom in,
	# maps-style. Raw ScreenTouch/Drag events through the full pipeline.
	var board := _find_by_method(get_tree().root, "cycle_zoom")
	_check(board != null, "the Ledger board exists")
	if board != null:
		var z0: float = board.call("zoom")
		var c := (board as Control).get_global_rect().get_center()
		var xf := (board as Control).get_viewport().get_final_transform() \
				* (board as Control).get_canvas_transform()
		var mid: Vector2 = xf * c
		await _pinch(mid, 90.0, 260.0)
		var z1: float = board.call("zoom")
		_check(z1 > z0 * 1.3, "pinch-out zooms the board in (%.2f -> %.2f)" % [z0, z1])

	# And back.
	var close_btn := _find_button(get_tree().root, "CLOSE")
	if close_btn != null:
		await _tap(close_btn)
		await _frames(20)
		_check(Game.state == &"count", "CLOSE returns to The Count (state=%s)" % Game.state)
	await _shot("5_back")

	# RESTART REGRESSION (second device save bug): buy hardware, kill the app, reopen —
	# the bought piece must be STANDING on the fresh table with no purchase event fired.
	var mint: GDScript = load("res://game/meta/ledger_state.gd")
	mint.add_level("rackets.trash_2")
	Events.upgrade_purchased.emit("rackets.trash_2", 1)
	await _frames(10)
	var table: Node2D = main.get("table")
	_check(bool(table.call("hardware_present", &"bumper_2")),
			"bought bumper stands on the field")
	main.queue_free()
	await _frames(5)
	main = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(40)
	var table2: Node2D = main.get("table")
	_check(bool(table2.call("hardware_present", &"bumper_2")),
			"RESTART: the bought bumper is back on the fresh table")
	await _shot("6_restart")

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


## Two synthesized fingers moving apart symmetrically around `mid` (window coords).
func _pinch(mid: Vector2, from_half: float, to_half: float) -> void:
	for i in 2:
		var d := InputEventScreenTouch.new()
		d.index = i
		d.position = mid + Vector2(from_half * (1.0 if i == 0 else -1.0), 0)
		d.pressed = true
		Input.parse_input_event(d)
	await _frames(3)
	var steps := 12
	for s in steps:
		var half := lerpf(from_half, to_half, float(s + 1) / steps)
		for i in 2:
			var g := InputEventScreenDrag.new()
			g.index = i
			g.position = mid + Vector2(half * (1.0 if i == 0 else -1.0), 0)
			g.relative = Vector2((to_half - from_half) / steps * (1.0 if i == 0 else -1.0), 0)
			Input.parse_input_event(g)
		await _frames(2)
	for i in 2:
		var u := InputEventScreenTouch.new()
		u.index = i
		u.position = mid + Vector2(to_half * (1.0 if i == 0 else -1.0), 0)
		u.pressed = false
		Input.parse_input_event(u)
	await _frames(6)


func _find_by_method(node: Node, method: String) -> Control:
	if node is Control and node.has_method(method) and (node as Control).is_visible_in_tree():
		return node
	for child in node.get_children():
		var found := _find_by_method(child, method)
		if found != null:
			return found
	return null


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
