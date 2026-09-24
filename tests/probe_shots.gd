extends SimBase
## The shot map (docs/20 §3): which shot each flipper makes, and across how much of its timing.
## Three feeds per bat: the aimed shot (a trapped ball released and re-flipped after a delay,
## 0..0.8 s), the live feed (a ball rolled down the inlane and flipped after a delay) and the
## flip on the fly. Each flip records the first `shot_made` the ball reaches within the watch
## window; a shot's window is how many steps landed on it times the step.
##   godot --headless --fixed-fps 60 --path . res://tests/probe_shots.tscn
##   PROBE_FEED=reflip|inlane|fly (default all)   PROBE_SIDE=left|right (default both)
##   PROBE_STEP=0.01 (seconds between flips, default 0.02)

const WATCH_SECONDS := 3.0
const MINOR: Array[StringName] = [&"spinner", &"dropoff"]

var _first: String = ""
var _minor: String = ""
var _hit: String = ""
var _step: float = 0.02


func _ready() -> void:
	make_table(true)
	if table.docks != null:
		table.docks.set_lit(false)
	table.shot_made.connect(_on_shot)
	Events.switch_hit.connect(_on_switch)
	_run()


## The first thing the flip reaches, by switch: what the player aimed at.
func _on_switch(id: StringName, _b: Node3D, _s: float) -> void:
	if _hit != "":
		return
	var s := String(id)
	for pre: Array in [["storefront_pizzeria", "Nonna's"], ["storefront_pawn", "Tony's"], ["wire", "Wire"],
			["bribe", "Cop"], ["laundromat", "Lucky's"], ["orbit_left", "Getaway"], ["orbit_right", "Truck"],
			["staircase", "Stairs"], ["bumper", "Alley"], ["rollover", "DropOff"], ["spinner", "Spinner"]]:
		if s.begins_with(String(pre[0])):
			_hit = String(pre[1])
			return


func _on_shot(shot: StringName, _b: Ball) -> void:
	if MINOR.has(shot):
		if _minor == "":
			_minor = String(shot)
		return
	if _first == "":
		_first = String(shot)


func _run() -> void:
	print("== KINGPIN shot map ==")
	var step_env := OS.get_environment("PROBE_STEP")
	if step_env.is_valid_float():
		_step = step_env.to_float()
	var feed := OS.get_environment("PROBE_FEED")
	var only := OS.get_environment("PROBE_SIDE")
	for side: StringName in [&"left", &"right"]:
		if only != "" and only != String(side):
			continue
		if feed == "" or feed == "reflip":
			await _sweep_reflip(side)
		if feed == "" or feed == "inlane":
			await _sweep_inlane(side)
		if feed == "" or feed == "fly":
			await _sweep_fly(side)
	get_tree().quit(0)


func _sweep_reflip(side: StringName) -> void:
	var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
	var tally := {}
	var rows: PackedStringArray = []
	var d := 0.0
	while d <= 0.80:
		table.despawn_ball()
		f.release()
		await step(24)
		f.press()
		await step(24)
		var b := table.spawn_ball()
		b.place(f.cradle_point(0.45) + Vector3(0.0, 0.03, 0.0))
		await wait(0.6)
		f.release()
		await wait(d)
		f.press()
		var res := await _follow(b)
		f.release()
		tally[res] = int(tally.get(res, 0)) + 1
		rows.append("%.2f:%s" % [d, res])
		d += _step
	_print_tally("%s bat, aimed (trap, release, re-flip after d = 0..0.80 s)" % side, tally, rows)


func _sweep_inlane(side: StringName) -> void:
	var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
	var s := -1.0 if side == &"left" else 1.0
	var start := Vector2(Layout.inlane_guide_x(s) - s * 0.2, Layout.INLANE_GUIDE_BOTTOM - 0.2)
	var tally := {}
	var rows: PackedStringArray = []
	var d := 0.0
	while d <= 0.60:
		table.despawn_ball()
		f.release()
		await step(12)
		var b := table.spawn_ball()
		b.place(Layout.p3(start, Feel.BALL_RADIUS + 0.01))
		b.set_velocity(Vector3(-s * 1.0, 0.0, 4.0))
		var contact := false
		for i in range(ticks(1.5)):
			await step(1)
			if not is_instance_valid(b):
				break
			if Layout.plan(b.table_position()).distance_to(Layout.plan(f.position)) < f.bat_length() + 0.2 \
					and b.table_position().z > f.position.z - 0.35:
				contact = true
				break
		if not contact or not is_instance_valid(b):
			rows.append("%.2f:nofeed" % d)
			d += _step
			continue
		await wait(d)
		if not is_instance_valid(b):
			rows.append("%.2f:gone" % d)
			d += _step
			continue
		f.press()
		var res := await _follow(b)
		f.release()
		tally[res] = int(tally.get(res, 0)) + 1
		rows.append("%.2f:%s" % [d, res])
		d += _step
	_print_tally("%s bat, inlane feed, flip after d = 0..0.60 s" % side, tally, rows)


## On the fly: a ball rolled down the inlane, flipped at a fixed time after it was fed, from
## before it reaches the bat (the bat meets it part-way up its stroke) to well after.
func _sweep_fly(side: StringName) -> void:
	var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
	var s := -1.0 if side == &"left" else 1.0
	var start := Vector2(Layout.inlane_guide_x(s) - s * 0.2, Layout.INLANE_GUIDE_BOTTOM - 0.2)
	var tally := {}
	var rows: PackedStringArray = []
	var at := 0.20
	while at <= 0.66:
		table.despawn_ball()
		f.release()
		await step(12)
		var b := table.spawn_ball()
		b.place(Layout.p3(start, Feel.BALL_RADIUS + 0.01))
		b.set_velocity(Vector3(-s * 1.0, 0.0, 4.0))
		await wait(at)
		if not is_instance_valid(b):
			rows.append("%.2f:gone" % at)
			at += _step
			continue
		f.press()
		var res := await _follow(b)
		f.release()
		tally[res] = int(tally.get(res, 0)) + 1
		rows.append("%.2f:%s" % [at, res])
		at += _step
	_print_tally("%s bat, on the fly (inlane feed, flip at T = 0.20..0.66 s after the feed; contact ~0.40)" % side, tally, rows)


func _follow(b: Ball) -> String:
	_first = ""
	_minor = ""
	_hit = ""
	var min_z := INF
	for i in range(ticks(WATCH_SECONDS)):
		await step(1)
		if _first != "":
			return (_hit + ">" if _hit != "" else "") + _first
		if not is_instance_valid(b):
			return (_hit + ">" if _hit != "" else "") + "drained"
		min_z = minf(min_z, b.table_position().z)
	if _hit != "":
		return _hit
	if min_z > 2.0:
		return "weak"
	return "none(z%.1f)" % min_z


func _print_tally(title: String, tally: Dictionary, rows: PackedStringArray) -> void:
	print("-- %s --" % title)
	var keys := tally.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(tally[a]) > int(tally[b]))
	var total := 0
	for k: Variant in keys:
		total += int(tally[k])
	for k: Variant in keys:
		print("    %-22s %3d  (%d%%)  %3d ms" % [String(k), int(tally[k]),
				int(round(100.0 * float(tally[k]) / maxf(1.0, float(total)))), int(round(float(tally[k]) * _step * 1000.0))])
	print("    sequence: " + " ".join(rows))
