extends Node2D
## TEMPORARY probe (TABLE-4): how fast can a club mini-flipper get a ball round the ceiling?

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
	var club := table.club
	var pent := table.penthouse
	var dome := table.city_hall
	print("gravity %.0f" % ProjectSettings.get_setting("physics/2d/default_gravity"))
	var fl: Flipper = club.flipper_left
	for offset: float in [0.3, 0.45, 0.6, 0.75, 0.9]:
		table.despawn_ball()
		await step(2)
		var b := table.spawn_ball()
		var at: Vector2 = fl.cradle_point(offset) + fl.strike_normal() * 6.0
		b.place(at)
		b.set_velocity(Vector2.ZERO)
		await step(6)
		var launch := b.speed()
		table.flipper_left.set_pressed(true)
		var best := 0.0
		var at_corner := 0.0
		var in_dome := false
		var in_pent := false
		var top := 0.0
		for i in range(360):
			await step(1)
			if i == 12:
				table.flipper_left.set_pressed(false)
			if b == null or not is_instance_valid(b):
				break
			var p := b.global_position
			best = maxf(best, b.speed())
			top = minf(top, p.y)
			if dome.loop.entry_rect().has_point(p):
				at_corner = maxf(at_corner,
						b.linear_velocity.dot(dome.loop.tangent_at(dome.loop.project(p))))
			if pent.stairs.entry_rect().has_point(p):
				at_corner = maxf(at_corner, 0.0)
			if dome.loop.riding():
				in_dome = true
				break
			if pent.stairs.riding():
				in_pent = true
				break
		print("  cradle %.2f: launch %.0f best %.0f | along-dome-at-mouth %.0f | dome=%s pent=%s top=%.0f"
				% [offset, launch, best, at_corner, in_dome, in_pent, top])
		table.flipper_left.set_pressed(false)
	table.despawn_ball()
	await step(2)
	get_tree().quit(0)
