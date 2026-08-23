extends Node2D
## TEMPORARY probe (TABLE-4): fly the dome loop and report what happens.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

var table: ProgressionTable = null
var _laps: Array[float] = []
var _home: int = 0


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.refresh_hardware()
	table.dome_loop_completed.connect(func(s: float) -> void: _laps.append(s))
	table.city_hall.returned_home.connect(func(_a: Vector2) -> void: _home += 1)
	_run()


func step(n: int = 1) -> void:
	for i in range(n):
		await get_tree().physics_frame


func drop(at: Vector2, v: Vector2) -> Ball:
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	b.place(at)
	b.set_velocity(v)
	await step(2)
	return b


func _who_is_there(at: Vector2) -> void:
	var space := get_world_2d().direct_space_state
	var shape := CircleShape2D.new()
	shape.radius = Feel.BALL_RADIUS + 6.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	for hit: Dictionary in space.intersect_shape(q, 8):
		var c: Object = hit.get("collider")
		if c is Node:
			print("            touching %s (%s)" % [(c as Node).get_path(), c.get_class()])


func _run() -> void:
	await step(6)
	var loop: RampLane = table.city_hall.loop
	print("rail length %.0f | needs %.0f | close at %.0f | gate %.0f"
			% [loop.length(), loop.required_entry_speed(), table.city_hall.close_length(),
			CityHall.ENTRY_SPEED])
	print("bounds %s" % str(table.bounds()))

	for speed: float in [700.0, 950.0, 1100.0, 1400.0, 1800.0]:
		_laps.clear()
		_home = 0
		var dir := Vector2(-0.985, -0.174)
		var b := await drop(CityHall.MOUTH_AT - dir * 60.0, dir * speed)
		var took := false
		var maxy := 0.0
		var out := Vector2.ZERO
		for i in range(720):
			await step(1)
			if loop.riding():
				took = true
			var cur := table.ball
			if cur == null or not is_instance_valid(cur):
				break
			maxy = minf(maxy, cur.global_position.y)
			out = cur.global_position
			if took and not loop.riding():
				break
		var vend := -1.0
		if table.ball != null and is_instance_valid(table.ball):
			vend = table.ball.speed()
		print("  %5.0f px/s -> taken=%s laps=%d home=%d top=%.0f end=%s v=%.0f"
				% [speed, took, _laps.size(), _home, maxy, str(out), vend])
		if not _laps.is_empty():
			print("          lap closed at %.0f px/s" % _laps[0])
		var settle := Vector2.ZERO
		var last := Vector2.INF
		var still := 0
		var still_max := 0
		var still_at := Vector2.ZERO
		var trail: PackedStringArray = []
		for i in range(600):
			await step(1)
			if table.ball == null or not is_instance_valid(table.ball):
				last = Vector2.INF
				continue
			settle = table.ball.global_position
			if i % 40 == 0:
				trail.append("%.0f,%.0f" % [settle.x, settle.y])
			if last != Vector2.INF and settle.distance_to(last) < 0.5:
				still += 1
				if still > still_max:
					still_max = still
					still_at = settle
			else:
				still = 0
			last = settle
		print("          after: still %.2fs at %s | trail %s"
				% [float(still_max) / 120.0, str(still_at), " ".join(trail)])
		if table.ball != null and is_instance_valid(table.ball):
			print("          5s later: %s v=%s layer=%d grav=%.1f held=%s"
					% [str(settle), str(table.ball.linear_velocity), table.ball.collision_layer,
					table.ball.gravity_scale, BallHold.is_held(table.ball)])
			_who_is_there(settle)
		else:
			print("          2s later: gone")
	table.despawn_ball()
	await step(2)
	get_tree().quit(0)
