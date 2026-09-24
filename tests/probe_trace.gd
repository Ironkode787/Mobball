extends SimBase
## One flip, traced: PROBE_SIDE, PROBE_D (reflip delay), PROBE_ALL=0 for the bare table.
## PROBE_PLUNGE=power traces a plunge instead. PROBE_EVERY=n prints every n ticks,
## PROBE_CONTACTS=1 lists what the ball touches (=2 adds each shape and the contact normal).

func _ready() -> void:
	make_table(OS.get_environment("PROBE_ALL") != "0")
	table.shot_made.connect(func(s: StringName, _b: Ball) -> void: print("   SHOT ", s))
	Events.switch_hit.connect(func(id: StringName, _b: Node3D, _s: float) -> void: print("   switch ", id))
	_run()


func _run() -> void:
	if OS.get_environment("PROBE_PLUNGE") != "":
		await _plunge(OS.get_environment("PROBE_PLUNGE").to_float())
		get_tree().quit(0)
		return
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
		_print_tick(b, i)
	get_tree().quit(0)


func _plunge(power: float) -> void:
	var b := table.spawn_ball()
	for i in range(ticks(1.0)):
		await step(1)
		if table.plunger.ball_ready():
			break
	table.plunger.launch(power)
	for i in range(ticks(3.0)):
		await step(1)
		if not is_instance_valid(b):
			print("gone at tick ", i)
			return
		_print_tick(b, i)


func _print_tick(b: Ball, i: int) -> void:
	var every := maxi(OS.get_environment("PROBE_EVERY").to_int(), 1) if OS.get_environment("PROBE_EVERY") != "" else 6
	if i % every != 0:
		return
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
				var tag := "%s/%s" % [(col as Node).get_parent().name, (col as Node).name]
				if OS.get_environment("PROBE_CONTACTS") == "2":
					var own_id := (col as CollisionObject3D).shape_find_owner(int(r["shape"]))
					var cs := (col as CollisionObject3D).shape_owner_get_owner(own_id) as CollisionShape3D
					tag += "#%d:%s@(%.2f,%.2f)" % [int(r["shape"]), cs.shape.get_class().replace("Shape3D", ""),
							cs.position.x, cs.position.z]
				hits.append(tag)
		if OS.get_environment("PROBE_CONTACTS") == "2":
			var info := get_world_3d().direct_space_state.get_rest_info(q)
			if not info.is_empty():
				var n: Vector3 = b.get_parent().global_transform.basis.inverse() * (info["normal"] as Vector3)
				hits.append("n=(%.2f,%.2f,%.2f)" % [n.x, n.y, n.z])
	print("  t=%.3f p=(%.2f, %.2f, %.2f) v=%.1f (%.1f, %.1f) %s" % [float(i) / 240.0, p.x, p.y, p.z, v.length(), v.x, v.z, ",".join(hits)])
