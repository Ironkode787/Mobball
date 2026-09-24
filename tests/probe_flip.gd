extends SimBase
## Flip energy budget on the bare table: exit speed, rolling speed and the highest point
## up-field a ball reaches when flipped from rest at fractions of the bat, and when fed down
## the inlane and flipped at a delay. Prints a table; no pass/fail.
##   godot --headless --fixed-fps 60 --path . res://tests/probe_flip.tscn


func _ready() -> void:
	make_table(false)
	_run()


func _run() -> void:
	print("== flip energy (bare table) ==")
	if OS.get_environment("PROBE_TRAPTRACE") == "1":
		await _trap_trace()
		get_tree().quit(0)
		return
	for side: StringName in [&"left", &"right"]:
		var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
		for t: float in ([] if OS.get_environment("PROBE_STATIC") != "1" else [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95]):
			table.despawn_ball()
			f.release()
			await step(20)
			var b := table.spawn_ball()
			b.place(f.cradle_point(t) + Vector3(0.0, 0.004, 0.0))
			await step(2)
			f.press()
			var r := await _measure(b)
			f.release()
			print("  %s t=%.2f  exit %5.1f  at0.15s %5.1f  apex z %5.2f  %s" % [side, t, r[0], r[1], r[2], r[3]])
	for side: StringName in [&"left", &"right"]:
		await _sweep_reflip(side)
	if OS.get_environment("PROBE_INLANE") != "1":
		get_tree().quit(0)
		return
	for side: StringName in [&"left", &"right"]:
		var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
		var s := -1.0 if side == &"left" else 1.0
		var best := 0.0
		var best_d := 0.0
		var d := 0.0
		while d <= 0.30:
			table.despawn_ball()
			f.release()
			await step(20)
			var b := table.spawn_ball()
			b.place(Layout.p3(Vector2(Layout.inlane_guide_x(s) - s * 0.2, Layout.INLANE_GUIDE_BOTTOM - 0.2), Feel.BALL_RADIUS + 0.01))
			b.set_velocity(Vector3(-s * 1.0, 0.0, 4.0))
			for i in range(ticks(1.5)):
				await step(1)
				if Layout.plan(b.table_position()).distance_to(Layout.plan(f.position)) < f.bat_length() + 0.2 \
						and b.table_position().z > f.position.z - 0.35:
					break
			await wait(d)
			f.press()
			var r := await _measure(b)
			f.release()
			if r[0] > best:
				best = r[0]
				best_d = d
			print("  %s inlane d=%.2f  exit %5.1f  at0.15s %5.1f  apex z %5.2f  %s" % [side, d, r[0], r[1], r[2], r[3]])
			d += 0.01
		print("  %s inlane best exit %.1f at d=%.2f" % [side, best, best_d])
	get_tree().quit(0)


func _trap_trace() -> void:
	var f: Flipper = table.flipper_left
	f.press()
	await step(24)
	var b := table.spawn_ball()
	b.place(f.cradle_point(0.45) + Vector3(0.0, 0.03, 0.0))
	await wait(0.6)
	print("  held at ", b.table_position() - f.position)
	f.release()
	for i in range(30):
		await step(4)
		var p := b.table_position() - f.position
		print("  t=%.3f rel(%.3f, %.3f, %.3f) v=%.2f bat_prog=%.2f" % [i * 4.0 / 240.0, p.x, p.y, p.z, b.speed(), f.progress])


## The aimed shot: a ball trapped on the raised bat, the bat released, then flipped again
## after `d` seconds — the delay picks both where on the bat the ball is and how far the
## bat has fallen, which is the whole of a player's aim.
func _sweep_reflip(side: StringName) -> void:
	var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
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
		if d == 0.0:
			var loc := f.to_local(f.get_parent().to_global(b.table_position())) if false else b.table_position() - f.position
			print("    trapped ball at %s (rel pivot %s) speed %.2f" % [str(b.table_position()), str(loc), b.speed()])
		f.release()
		await wait(d)
		f.press()
		var r := await _measure(b)
		f.release()
		print("  %s reflip d=%.3f  exit %5.1f  at0.15s %5.1f  apex z %5.2f  %s" % [side, d, r[0], r[1], r[2], r[3]])
		d += 0.04


## Returns [exit speed, speed 0.15 s later, apex z, "heading° | x at z=0 | x at z=-2 | x at z=-4"].
## Heading is the plan direction of travel between 0.10 s and 0.25 s after the flip, in
## degrees from straight up-field (positive = toward +x).
func _measure(b: Ball) -> Array:
	var exit := 0.0
	var later := 0.0
	var apex := INF
	var p10 := Vector3.INF
	var p25 := Vector3.INF
	var cross := {0.0: INF, -2.0: INF, -4.0: INF}
	var last := b.table_position()
	for i in range(ticks(2.5)):
		await step(1)
		if not is_instance_valid(b):
			break
		var v := b.local_velocity()
		var p := b.table_position()
		if i < ticks(0.06):
			exit = maxf(exit, v.length())
		if i == ticks(0.15):
			later = v.length()
		if i == ticks(0.10):
			p10 = p
		if i == ticks(0.25):
			p25 = p
		for zc: float in cross.keys():
			if is_inf(float(cross[zc])) and last.z > zc and p.z <= zc:
				cross[zc] = lerpf(last.x, p.x, (last.z - zc) / maxf(last.z - p.z, 0.0001))
		last = p
		apex = minf(apex, p.z)
	var head := "--"
	if p10 != Vector3.INF and p25 != Vector3.INF and p10.distance_to(p25) > 0.05:
		head = "%+.0f" % rad_to_deg(atan2(p25.x - p10.x, -(p25.z - p10.z)))
	var xs := PackedStringArray()
	for zc: float in [0.0, -2.0, -4.0]:
		xs.append("--" if is_inf(float(cross[zc])) else "%+.2f" % float(cross[zc]))
	return [exit, later, apex, "%s° | x@0 %s | x@-2 %s | x@-4 %s" % [head, xs[0], xs[1], xs[2]]]
