extends Node3D
## Dev probe (not a gate): exercises the 3D machine headless and prints what the ball does.
##   godot --headless --path . res://tests/probe_machine.tscn
## Plunger sweep → which top lane / orbit; a shot up the Staircase; both orbits; a ball
## dropped at the flippers → does it drain; a soak of random flips → stuck anywhere?

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const POWERS: PackedFloat32Array = [0.55, 0.58, 0.60, 0.62, 0.65, 0.68, 0.72, 0.76, 0.80, 0.85, 0.90, 0.95]

var table: ProgressionTable = null
var _rollover: int = -1
var _orbit: int = 0
var _climbed: bool = false
var _drained: bool = false
var _events: PackedStringArray = []


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.refresh_hardware()
	table.rollover_rolled.connect(func(i: int, _lit: bool) -> void:
		if _rollover < 0:
			_rollover = i)
	table.orbit_completed.connect(func() -> void: _orbit += 1)
	table.staircase_climbed.connect(func(_s: float) -> void: _climbed = true)
	table.ball_lost.connect(func(_b: Ball) -> void: _drained = true)
	Events.switch_hit.connect(func(id: StringName, _b: Node3D, _s: float) -> void: _events.append(String(id)))
	_run()


func _colliders_near(at: Vector3, pad: float) -> void:
	var probe := AABB(at - Vector3.ONE * (Feel.BALL_RADIUS + pad), Vector3.ONE * 2.0 * (Feel.BALL_RADIUS + pad))
	var stack: Array[Node] = [table]
	var inv: Transform3D = table.global_transform.affine_inverse()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CollisionShape3D and n.shape != null and n.is_inside_tree():
			var cs := n as CollisionShape3D
			var body := cs.get_parent()
			if body is CollisionObject3D and (body as CollisionObject3D).collision_layer == 0:
				continue
			var local: Transform3D = inv * cs.global_transform
			var box: AABB = local * cs.shape.get_debug_mesh().get_aabb()
			if box.intersects(probe):
				print("   near: %s %s" % [str(cs.get_path()).replace(str(table.get_path()), ""), str(box)])


func _reset() -> void:
	_rollover = -1
	_orbit = 0
	_climbed = false
	_drained = false
	_events.clear()


func _watch(ticks: int, b: Variant) -> Dictionary:
	var min_z := INF
	var max_y := -INF
	var last := Vector3.ZERO
	var still := 0
	var still_max := 0
	var still_at := Vector3.ZERO
	for i in range(ticks):
		await get_tree().physics_frame
		if b == null or not is_instance_valid(b):
			break
		var p: Vector3 = b.table_position()
		min_z = minf(min_z, p.z)
		max_y = maxf(max_y, p.y)
		if p.distance_to(last) < 0.002:
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p
	return {"min_z": min_z, "max_y": max_y, "end": last, "still_max": still_max, "still_at": still_at,
			"alive": b != null and is_instance_valid(b)}


func _run() -> void:
	if OS.get_environment("PROBE_NEAR") != "":
		var parts := OS.get_environment("PROBE_NEAR").split(",")
		_colliders_near(Vector3(float(parts[0]), float(parts[1]), float(parts[2])), 0.12)
		get_tree().quit()
		return
	if OS.get_environment("PROBE_DUMP_LANE") != "":
		var lane: RampLane = table.get_node(OS.get_environment("PROBE_DUMP_LANE")) as RampLane
		var frames: Array = lane._frames()
		for i in range(0, frames.size(), 5):
			var c: Vector3 = frames[i][0]
			var r: Vector3 = frames[i][1]
			var hw: float = float(frames[i][3])
			print("%3d s=%.2f c=(%.2f,%.2f,%.2f) roll=%.1f left_y=%.3f right_y=%.3f hw=%.2f" % [
				i, lane._cum[i], c.x, c.y, c.z, rad_to_deg(asin(clampf(r.y, -1.0, 1.0))), (c - r * hw).y, (c + r * hw).y, hw])
		get_tree().quit()
		return
	print("== KINGPIN machine probe ==")
	print("-- plunger sweep")
	for p in POWERS:
		_reset()
		table.despawn_ball()
		var b := table.spawn_ball()
		for i in range(72):
			await get_tree().physics_frame
		var ready := table.plunger.ball_ready()
		if not is_instance_valid(b):
			print("power %.2f: the ball was lost before launch (drained=%s)" % [p, str(_drained)])
			continue
		table.plunger.launch(p)
		var v_gate := -1.0
		var v_top := -1.0
		var v0 := b.speed()
		var lane_trace := PackedStringArray()
		for i in range(240 * 3):
			await get_tree().physics_frame
			if b == null or not is_instance_valid(b):
				break
			var tp := b.table_position()
			if is_equal_approx(p, 0.62) and i % 12 == 0 and tp.x > 2.17 and tp.z > -3.0:
				lane_trace.append("z%.1f:%.1f" % [tp.z, b.speed()])
			if v_gate < 0.0 and tp.z < -3.0:
				v_gate = b.speed()
			if v_top < 0.0 and tp.z < -4.6:
				v_top = b.speed()
		var w := await _watch(240 * 2, b)
		var lane := ("lane %d" % (_rollover + 1)) if _rollover >= 0 else "no lane"
		print("power %.2f (v0 %.1f, gate %.1f, top %.1f) -> %s orbit=%d drained=%s min_z=%.2f end=%s stuck=%d"
				% [p, v0, v_gate, v_top, lane, _orbit, str(_drained), w["min_z"], str(w["end"]), w["still_max"]])
		if not lane_trace.is_empty():
			print("   lane trace: %s" % " ".join(lane_trace))
	print("-- staircase shot from the mouth")
	for speed in [20.0, 28.0, 36.0]:
		_reset()
		table.despawn_ball()
		var b := table.spawn_ball()
		b.place(Layout.p3(Layout.STAIR_MOUTH + Vector2(0.0, 0.5), Feel.BALL_RADIUS + 0.01))
		await get_tree().physics_frame
		var dir := (Layout.STAIR_PATH[1] - Layout.STAIR_PATH[0])
		dir.y = 0.0
		b.set_velocity(dir.normalized() * speed)
		var trace := PackedStringArray()
		for k in range(60):
			for j in range(10):
				await get_tree().physics_frame
			if b == null or not is_instance_valid(b):
				break
			var tp := b.table_position()
			trace.append("(%.1f,%.2f,%.1f|%.0f)" % [tp.x, tp.y, tp.z, b.speed()])
		print("   trace: %s" % " ".join(trace.slice(0, 22)))
		var w := await _watch(240 * 1, b)
		print("stair %.0f u/s -> climbed=%s drained=%s max_y=%.2f end=%s stuck=%d@%s events=%s"
				% [speed, str(_climbed), str(_drained), w["max_y"], str(w["end"]), w["still_max"], str(w["still_at"]),
				",".join(_events.slice(0, 8))])
	print("-- penthouse stairs from the deck mouth")
	for speed in [21.0, 32.0]:
		_reset()
		table.despawn_ball()
		var b := table.spawn_ball()
		var start := ClubDeck.PENTHOUSE_MOUTH + Vector2(0.30, 0.30)
		b.place(Layout.p3(start, ClubDeck.DECK_H + Feel.BALL_RADIUS + 0.01))
		await get_tree().physics_frame
		var dir := Penthouse.STAIR_PATH[1] - Penthouse.STAIR_PATH[0]
		dir.y = 0.0
		b.set_velocity(dir.normalized() * speed)
		var trace := PackedStringArray()
		for k in range(30):
			for j in range(8):
				await get_tree().physics_frame
			if b == null or not is_instance_valid(b):
				break
			var tp := b.table_position()
			trace.append("(%.2f,%.2f,%.2f|%.0f)" % [tp.x, tp.y, tp.z, b.speed()])
		print("stairs %.0f -> events=%s" % [speed, ",".join(_events.slice(0, 8))])
		print("   trace: %s" % " ".join(trace.slice(0, 20)))
		if b != null and is_instance_valid(b) and b.speed() < 0.5:
			_colliders_near(b.table_position(), 0.2)
	print("-- docks: a lane ball rolling down into the yard")
	for speed in [4.0, 9.0]:
		_reset()
		table.despawn_ball()
		var db := table.spawn_ball()
		db.place(Layout.p3(Vector2(-2.36, -0.9), Feel.BALL_RADIUS + 0.01))
		await get_tree().physics_frame
		db.set_velocity(Vector3(0.0, 0.0, speed))
		var dtrace := PackedStringArray()
		for k in range(40):
			for j in range(30):
				await get_tree().physics_frame
			if db == null or not is_instance_valid(db):
				break
			var tp := db.table_position()
			dtrace.append("(%.2f,%.2f,%.2f|%.0f)" % [tp.x, tp.y, tp.z, db.speed()])
		print("docks %.0f -> events=%s" % [speed, ",".join(_events.slice(0, 8))])
		print("   trace: %s" % " ".join(dtrace.slice(0, 40)))
		if db != null and is_instance_valid(db) and db.speed() < 0.5:
			_colliders_near(db.table_position(), 0.1)
	print("-- left orbit from the entry")
	for speed in [10.0, 18.0, 26.0]:
		_reset()
		table.despawn_ball()
		var b := table.spawn_ball()
		b.place(Layout.p3(Layout.ORBIT_L_ENTRY + Vector2(0.0, 0.6), Feel.BALL_RADIUS + 0.01))
		await get_tree().physics_frame
		b.set_velocity(Vector3(0.0, 0.0, -speed))
		var w := await _watch(240 * 5, b)
		print("orbitL %.0f -> orbits=%d lane=%d min_z=%.2f end=%s stuck=%d events=%s"
				% [speed, _orbit, _rollover, w["min_z"], str(w["end"]), w["still_max"], ",".join(_events.slice(0, 8))])
	print("-- drop at the flippers, no flip")
	_reset()
	table.despawn_ball()
	var b0 := table.spawn_ball()
	b0.place(Layout.p3(Vector2(0.0, 2.0), Feel.BALL_RADIUS + 0.01))
	var w0 := await _watch(240 * 4, b0)
	print("drop -> drained=%s end=%s stuck=%d@%s" % [str(_drained), str(w0["end"]), w0["still_max"], str(w0["still_at"])])
	print("-- flip soak (20 s, random flips)")
	_reset()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	table.auto_respawn = true
	table.despawn_ball()
	table.spawn_ball()
	var drains := 0
	var flips := 0
	var worst_still := 0
	var worst_at := Vector3.ZERO
	var still := 0
	var last := Vector3.ZERO
	table.ball_lost.connect(func(_b: Ball) -> void: drains += 1)
	for i in range(240 * 20):
		await get_tree().physics_frame
		var b := table.ball
		if b == null or not is_instance_valid(b):
			continue
		if table.plunger.ball_ready() and i % 120 == 0:
			table.plunger.launch(rng.randf_range(0.7, 1.0))
		var p := b.table_position()
		if p.z > 3.0 and rng.randf() < 0.04:
			var f := table.flipper_left if p.x < 0.0 else table.flipper_right
			f.press()
			flips += 1
			get_tree().create_timer(0.12).timeout.connect(f.release)
		if p.distance_to(last) < 0.002:
			still += 1
			if still > worst_still:
				worst_still = still
				worst_at = p
		else:
			still = 0
		last = p
	print("soak -> drains=%d flips=%d dirty=%d switches=%d worst_still=%d ticks @%s"
			% [drains, flips, 0, _events.size(), worst_still, str(worst_at)])
	get_tree().quit(0)
