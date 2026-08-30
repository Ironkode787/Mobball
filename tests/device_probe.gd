extends Node
## DEVICE INPUT PROBE — run windowed (xvfb) at a phone resolution. Boots the real game,
## presses the real buttons with synthesized hardware touches (Input.parse_input_event →
## the full input pipeline, including emulate_mouse_from_touch), and screenshots each step
## to SHOT_DIR. Exit 0 only if every step lands. This is the harness for "it works on my
## desktop" bugs.

var shots_dir := "/tmp/device_probe"
var failures := 0
const PROBE_SAVE := "user://device_probe_save.json"


var main: Node = null


func _ready() -> void:
	var env := OS.get_environment("SHOT_DIR")
	if not env.is_empty():
		shots_dir = env
	DirAccess.make_dir_recursive_absolute(shots_dir)
	_clean_probe_save()
	main = _spawn_main()
	_run()


func _spawn_main() -> Node:
	var instance := (load("res://game/main.tscn") as PackedScene).instantiate()
	instance.set("auto_start", false)
	add_child(instance)
	instance.call("start_session", PROBE_SAVE)
	return instance


func _run() -> void:
	await _frames(40)
	await _shot("1_attract")
	_check_visible_buttons_inside_safe(get_tree().root, "ATTRACT")

	# ATTRACT → ROLL CALL via a real touch on ROLL CALL, then start the prepared Night.
	var roll := _find_button(get_tree().root, "ROLL CALL")
	_check(roll != null, "ROLL CALL button exists")
	if roll != null:
		_check_inside_safe(roll, "ROLL CALL")
		await _tap(roll)
		await _frames(30)
	_check(Game.state == &"roll_call", "touch on ROLL CALL opens Roll Call (state=%s)" % Game.state)
	await _shot("1b_roll_call")
	_check_visible_buttons_inside_safe(get_tree().root, "ROLL CALL")
	var start_night := _find_button(get_tree().root, "START NIGHT")
	_check(start_night != null, "START NIGHT button exists on Roll Call")
	if start_night != null:
		_check_inside_safe(start_night, "START NIGHT")
		await _tap(start_night)
		await _frames(30)
	_check(Game.state == &"night", "START NIGHT launches the prepared Night (state=%s)" % Game.state)
	await _shot("2_night")
	var safe_content := Presentation.safe.content_rect()
	_check(safe_content.size.x > 0.0 and safe_content.size.y > 0.0,
			"asymmetric cutout leaves a positive safe content rectangle")
	var feedback: Node = Presentation.feedback
	_check(feedback != null and int(feedback.get("mouse_filter")) == Control.MOUSE_FILTER_IGNORE,
			"gameplay feedback overlay can never intercept a phone touch")
	var feedback_size: Vector2 = feedback.get("size") if feedback != null else Vector2.ZERO
	_check(feedback_size.x > 0.0 and feedback_size.y > 0.0,
			"gameplay feedback overlay fills the logical phone viewport (%s)" % feedback_size)
	var hud: Node = main.get("hud")
	var hud_strip: Rect2 = hud.call("strip_rect") if hud != null else Rect2()
	_check(hud != null and bool(hud.call("compact_layout")),
			"the tall phone uses the compact HUD")
	_check(hud_strip.position.y >= safe_content.position.y - 1.0,
			"unsafe top glass stays full-bleed instead of becoming black HUD padding")
	_check(hud_strip.size.y <= GameHUD.COMPACT_STRIP_H + 1.0,
			"the phone HUD obscures no more than one shallow two-row strip")
	# Deterministic presentation fixture on the real Night: readable content must stay safe,
	# while impact rings and edge atmosphere are allowed to bleed beneath rounded glass.
	Presentation.fx.request(&"impact", {"screen_position": Vector2(536.0, 1040.0),
			"strength": 1450.0})
	Presentation.fx.request(&"currency", {"currency": &"dirty", "amount": BigMoney.of(275.0, 0),
			"screen_position": Vector2(500.0, 1080.0)})
	Presentation.fx.request(&"currency", {"currency": &"clean", "amount": BigMoney.of(90.0, 0),
			"screen_position": Vector2(570.0, 1110.0)})
	Presentation.fx.request(&"combo", {"count": 4})
	await _frames(5)
	_check(int(feedback.call("active_count")) == 4,
			"hit/combo/currency fixture stays inside the bounded pool")
	_check(Presentation.budget.count(&"emitters") <= GameplayFeedback.MAX_EFFECTS,
			"live phone fixture respects the emitter budget")
	await _shot("2a_feedback_hits")
	feedback.call("clear")
	Presentation.fx.request(&"jackpot", {"source": &"slot_reels",
			"amount": BigMoney.of(125.0, 3), "clean": true})
	Presentation.fx.haptic(&"jackpot", 1.0)
	await _frames(5)
	await _shot("2b_feedback_jackpot")
	feedback.call("clear")
	_check(Presentation.budget.count(&"emitters") == 0,
			"phone fixture teardown returns every emitter token")

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
	_check(Presentation.budget.count(&"emitters") == 0,
			"leaving the Night clears gameplay effects before The Count")
	await _shot("3_count")
	_check_visible_buttons_inside_safe(get_tree().root, "THE COUNT")
	var count_screen: Node = main.get("count")
	if count_screen != null and count_screen.has_method("skip"):
		count_screen.call("skip")
		await _frames(3)
		_check(bool(count_screen.call("finished")), "the completed Count printed its headline")
		await _shot("3b_count_finished")

	# COUNT → LEDGER via a real touch on THE LEDGER. This is the user's bug report.
	var ledger_btn := _find_button(get_tree().root, "THE LEDGER")
	_check(ledger_btn != null, "THE LEDGER button exists on The Count")
	if ledger_btn != null:
		_check_inside_safe(ledger_btn, "THE LEDGER")
		await _tap(ledger_btn)
		await _frames(30)
	_check(Game.state == &"ledger", "touch on THE LEDGER opens the Ledger (state=%s)" % Game.state)
	var overlay: Node = main.get("ledger")
	var overlay_visible: bool = overlay != null and is_instance_valid(overlay) \
			and overlay.get("visible") == true
	_check(overlay_visible, "the Ledger overlay exists and is visible")
	await _shot("4_ledger")
	_check_visible_buttons_inside_safe(get_tree().root, "THE LEDGER")

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
		_check_inside_safe(close_btn, "Ledger CLOSE")
		var next_buy := _find_button(get_tree().root, "NEXT BUY  ▸")
		if next_buy != null:
			_check_inside_safe(next_buy, "Ledger NEXT BUY")
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
	main = _spawn_main()
	await _frames(40)
	var table2: Node2D = main.get("table")
	_check(bool(table2.call("hardware_present", &"bumper_2")),
			"RESTART: the bought bumper is back on the fresh table")
	await _shot("6_restart")

	print("DEVICE PROBE: %s" % ("OK" if failures == 0 else "%d FAILURES" % failures))
	_clean_probe_save()
	get_tree().quit(0 if failures == 0 else 1)


func _clean_probe_save() -> void:
	SaveGame.new(PROBE_SAVE).erase()


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


func _check_inside_safe(control: Control, label: String) -> void:
	var safe := Presentation.safe.content_rect()
	var rect := control.get_global_rect()
	# Containers may land on fractional pixels; the one-pixel tolerance is raster rounding,
	# not permission to put controls under curved glass.
	_check(safe.grow(1.0).encloses(rect), "%s stays inside safe content %s (got %s)" % [
			label, safe, rect])


func _check_visible_buttons_inside_safe(node: Node, scope: String) -> void:
	if node is Button and (node as Button).is_visible_in_tree():
		var button := node as Button
		var rect := button.get_global_rect()
		var viewport_rect := get_viewport().get_visible_rect()
		var rendered := _rendered_control_rect(button).intersection(viewport_rect)
		if rect.size.x > 0.0 and rect.size.y > 0.0 and rendered.size.x > 0.0 \
				and rendered.size.y > 0.0:
			_check_inside_safe(button, "%s / %s" % [scope, button.text])
	for child in node.get_children():
		_check_visible_buttons_inside_safe(child, scope)


## `is_visible_in_tree()` does not account for a ScrollContainer clipping its children.
## Walk the Control ancestry so off-scroll buttons are not mistaken for rendered controls;
## buttons that are actually on screen still receive the unchanged full-rect safe-area check.
func _rendered_control_rect(control: Control) -> Rect2:
	var rendered := control.get_global_rect()
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			rendered = rendered.intersection((ancestor as Control).get_global_rect())
			if rendered.size.x <= 0.0 or rendered.size.y <= 0.0:
				return Rect2()
		ancestor = ancestor.get_parent()
	return rendered


func _shot(name: String) -> void:
	await _frames(2)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [shots_dir, name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
