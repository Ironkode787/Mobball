extends Node2D
## TEMPORARY probe (TABLE-4): scan the midfield for briefcase spots with real clearance.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

var table: ProgressionTable = null


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.refresh_hardware()
	table.despawn_ball()
	_run()


func _run() -> void:
	for i in range(6):
		await get_tree().physics_frame
	print("== probe: no raid ==")
	_scan()
	table.set_raid_active(true)
	for i in range(4):
		await get_tree().physics_frame
	print("== probe: raid on ==")
	_scan()
	table.set_raid_active(false)
	table.set_boss_target(&"truck", &"park", 6)
	table.set_boss_target(&"sedan", &"park", 6)
	table.set_boss_goons(true)
	table.set_boss_door(true)
	for i in range(4):
		await get_tree().physics_frame
	print("== probe: full boss fight ==")
	_scan()
	get_tree().quit(0)


func _scan() -> void:
	var space := get_world_2d().direct_space_state
	var best: Array = []
	var x := 110.0
	while x <= 910.0:
		var y := 860.0
		while y <= 1440.0:
			var r := _clear_radius(space, Vector2(x, y))
			if r >= 108.0:
				best.append({"at": Vector2(x, y), "r": r})
			y += 10.0
		x += 10.0
	best.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["r"]) > float(b["r"]))
	print("  candidates: %d" % best.size())
	for c: Vector2 in [Vector2(590,1160), Vector2(610,1260), Vector2(730,1300),
			Vector2(810,1300), Vector2(810,1320), Vector2(400,990), Vector2(800,1000),
			Vector2(290,980), Vector2(540,1350), Vector2(240,900), Vector2(760,1180)]:
		print("    NAMED %s clear %.0f" % [str(c), _clear_radius(space, c)])
	var shown := 0
	var taken: Array[Vector2] = []
	for e: Dictionary in best:
		var p: Vector2 = e["at"]
		var far := true
		for t: Vector2 in taken:
			if t.distance_to(p) < 80.0:
				far = false
				break
		if not far:
			continue
		taken.append(p)
		print("    %s clear %.0f" % [str(p), float(e["r"])])
		shown += 1
		if shown >= 24:
			break


func _clear_radius(space: PhysicsDirectSpaceState2D, at: Vector2) -> float:
	var r := 40.0
	var last := 0.0
	while r <= 170.0:
		var shape := CircleShape2D.new()
		shape.radius = r
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, at)
		q.collision_mask = Feel.LAYER_WALLS | Feel.LAYER_HARDWARE | Feel.LAYER_FLIPPERS
		q.collide_with_bodies = true
		q.collide_with_areas = false
		if not space.intersect_shape(q, 1).is_empty():
			return last
		last = r
		r += 4.0
	return last
