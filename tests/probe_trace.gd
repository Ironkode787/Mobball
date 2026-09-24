extends SimBase
## One flip, traced: PROBE_SIDE, PROBE_D (reflip delay), PROBE_ALL=0 for the bare table.

func _ready() -> void:
	make_table(OS.get_environment("PROBE_ALL") != "0")
	table.shot_made.connect(func(s: StringName, _b: Ball) -> void: print("   SHOT ", s))
	Events.switch_hit.connect(func(id: StringName, _b: Node3D, _s: float) -> void: print("   switch ", id))
	_run()


func _run() -> void:
	var side := OS.get_environment("PROBE_SIDE")
	var f: Flipper = table.flipper_right if side == "right" else table.flipper_left
	var d := OS.get_environment("PROBE_D").to_float()
	f.release()
	await step(24)
	f.press()
	await step(24)
	var b := table.spawn_ball()
	b.place(f.cradle_point(0.45) + Vector3(0.0, 0.03, 0.0))
	await wait(0.6)
	print("trapped at ", b.table_position())
	f.release()
	await wait(d)
	f.press()
	for i in range(ticks(2.5)):
		await step(1)
		if not is_instance_valid(b):
			print("gone at tick ", i)
			break
		var every := maxi(OS.get_environment("PROBE_EVERY").to_int(), 1) if OS.get_environment("PROBE_EVERY") != "" else 6
		if i % every == 0:
			var p := b.table_position()
			var v := b.local_velocity()
			var hits := PackedStringArray()
			if OS.get_environment("PROBE_CONTACTS") != "":
				var q := PhysicsShapeQueryParameters3D.new()
				var sph := SphereShape3D.new()
				sph.radius = Feel.BALL_RADIUS + 0.01
				q.shape = sph
				q.transform = b.global_transform
				q.collision_mask = 0xFFFF
				q.exclude = [b.get_rid()]
				for r in get_world_3d().direct_space_state.intersect_shape(q, 8):
					var col: Object = r["collider"]
					if col is Node:
						hits.append("%s/%s" % [(col as Node).get_parent().name, (col as Node).name])
			print("  t=%.3f p=(%.2f, %.2f, %.2f) v=%.1f (%.1f, %.1f) %s" % [float(i) / 240.0, p.x, p.y, p.z, v.length(), v.x, v.z, ",".join(hits)])
	get_tree().quit(0)
