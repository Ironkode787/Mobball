extends Node2D
## TEMPORARY tuning probe (table lane) — deleted before hand-off. Traces plunge paths and
## soaks the progression table so the top-lane feed can be aimed at where the ball actually
## goes rather than where the geometry says it ought to.

const TABLE := preload("res://game/table/table_main.tscn")

var table: ProgressionTable = null
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	var sd := OS.get_environment("PROBE_SEED")
	_rng.seed = sd.to_int() if sd != "" else 0x4B494E47
	table = TABLE.instantiate()
	table.debug_all_hardware = true
	add_child(table)
	table.auto_respawn = false
	await _run()


func ticks(s: float) -> int:
	return maxi(1, int(round(s * 120.0)))


func step(n: int = 1) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _run() -> void:
	var mode := OS.get_environment("PROBE_MODE")
	if mode == "soak":
		await _soak()
	else:
		await _plunges()
	get_tree().quit(0)


func _plunges() -> void:
	for p: float in [0.55, 0.7, 0.8, 0.86, 0.9, 0.94, 0.97, 1.0]:
		table.despawn_ball()
		await step(2)
		table.spawn_ball()
		await step(ticks(0.4))
		var b := table.ball
		table.plunger.launch(p)
		var apex := 9999.0
		var apex_x := 0.0
		var cross_800 := -1.0
		var cross_1100 := -1.0
		var top_lane := -1
		var hits: Array[String] = []
		var cb := func(id: StringName, _ball: Node2D, _s: float) -> void:
			if hits.size() < 14:
				hits.append(String(id))
		Events.switch_hit.connect(cb)
		for t in range(ticks(4.0)):
			await step(1)
			if not is_instance_valid(b):
				break
			var q := b.global_position
			if q.y < apex:
				apex = q.y
				apex_x = q.x
			if cross_800 < 0.0 and q.y > 800.0 and q.y < 830.0:
				cross_800 = q.x
			if cross_1100 < 0.0 and q.y > 1100.0 and q.y < 1130.0:
				cross_1100 = q.x
		Events.switch_hit.disconnect(cb)
		print("p=%.2f apex=(%.0f,%.0f) x@800=%.0f x@1100=%.0f lane=%d hits=%s"
				% [p, apex_x, apex, cross_800, cross_1100, top_lane, ", ".join(hits)])


func _soak() -> void:
	table.auto_respawn = true
	table.spawn_ball()
	await step(ticks(0.3))
	table.plunger.launch(1.0)
	var escapes := 0
	var still := 0
	var still_max := 0
	var still_at := Vector2.ZERO
	var last := Vector2.INF
	var next_flip := [0, 0]
	var flip := [false, false]
	var switches := {}
	var cb := func(id: StringName, _b: Node2D, _s: float) -> void:
		switches[id] = int(switches.get(id, 0)) + 1
	Events.switch_hit.connect(cb)
	var drains := {"left_outlane": 0, "centre": 0, "right_outlane": 0}
	var cross := Vector2.INF
	var total := ticks(float(OS.get_environment("PROBE_SECONDS").to_float()) if
			OS.get_environment("PROBE_SECONDS") != "" else 45.0)
	for t in range(total):
		for s in range(2):
			if t >= next_flip[s]:
				flip[s] = not flip[s]
				var f: Flipper = table.flipper_left if s == 0 else table.flipper_right
				f.set_pressed(flip[s])
				next_flip[s] = t + ticks(_rng.randf_range(0.3, 0.7))
		if table.plunger.ball_ready():
			table.plunger.launch(_rng.randf_range(0.85, 1.0))
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			if cross != Vector2.INF:
				if cross.x < 200.0:
					drains["left_outlane"] += 1
				elif cross.x > 780.0:
					drains["right_outlane"] += 1
				else:
					drains["centre"] += 1
				cross = Vector2.INF
			last = Vector2.INF
			continue
		var p := b.global_position
		if p.y > 1600.0 and cross == Vector2.INF:
			cross = p
		elif p.y < 1500.0:
			cross = Vector2.INF
		if p.x < 36.0 or p.x > 1044.0 or p.y < -4.0 or p.y > 1930.0:
			escapes += 1
			if escapes < 4:
				print("ESCAPE %s v=%s" % [p, b.linear_velocity])
		if last != Vector2.INF and p.distance_to(last) < 0.5:
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p
	Events.switch_hit.disconnect(cb)
	print("soak: served=%d escapes=%d longest_still=%.2fs at %s"
			% [table.balls_served, escapes, float(still_max) / 120.0, still_at])
	print("switches: ", switches)
	print("drains: ", drains)
