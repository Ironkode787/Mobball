extends Node2D
## TEMPORARY probe (TABLE-4): what does a lap up the deck's right lane carry to the corner?

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

var table: ProgressionTable = null


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.refresh_hardware()
	_run()


func step(n: int = 1) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _run() -> void:
	await step(6)
	var pent := table.penthouse
	var dome := table.city_hall
	for v0: float in [2000.0, 2400.0, 2600.0, 2900.0, 3300.0, 3800.0]:
		table.despawn_ball()
		await step(2)
		var b := table.spawn_ball()
		b.place(Vector2(985.0, -200.0))
		b.set_velocity(Vector2(0.0, -v0))
		var best_dome := 0.0
		var best_pent := 0.0
		var got := ""
		for i in range(300):
			await step(1)
			if b == null or not is_instance_valid(b):
				got = "lost"
				break
			var p := b.global_position
			if dome.loop.entry_rect().has_point(p):
				best_dome = maxf(best_dome,
						b.linear_velocity.dot(dome.loop.tangent_at(dome.loop.project(p))))
			if pent.stairs.entry_rect().has_point(p):
				best_pent = maxf(best_pent,
						b.linear_velocity.dot(pent.stairs.tangent_at(pent.stairs.project(p))))
			if dome.loop.riding():
				got = "DOME"
				break
			if pent.stairs.riding():
				got = "penthouse"
				break
			if table.club.roulette.holds_ball():
				got = "wheel"
				break
		print("  up the right lane at %.0f -> %s | best along dome %.0f, pent %.0f"
				% [v0, got if got != "" else "(nothing)", best_dome, best_pent])
	table.despawn_ball()
	await step(2)
	get_tree().quit(0)
