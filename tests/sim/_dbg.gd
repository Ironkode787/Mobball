extends Node2D

var main: Main


func _ready() -> void:
	main = load("res://game/main.tscn").instantiate()
	main.auto_start = false
	main.show_hud = false
	add_child(main)
	main.table.auto_respawn = false
	_go()


func _go() -> void:
	var t := main.table
	print("arch center=", t._arch_center, " r=", t._arch_radius)
	for x in [943.0, 970.0, 996.5, 1020.0]:
		var dx: float = x - t._arch_center.x
		var yy: float = t._arch_center.y - sqrt(max(t._arch_radius * t._arch_radius - dx * dx, 0.0))
		print("  arch inner y at x=", x, " -> ", yy)
	t.spawn_ball()
	for i in range(60):
		await get_tree().physics_frame
	var b := t.ball
	print("settled at ", b.global_position, " v=", b.linear_velocity)
	t.plunger.launch(1.0)
	for i in range(240):
		await get_tree().physics_frame
		if not is_instance_valid(b):
			print("ball gone at tick ", i)
			break
		if i % 6 == 0 or i < 4:
			print("t=%3d  p=%s  v=%s  gate=%s" % [i, b.global_position, b.linear_velocity, t._gate_closed])
	get_tree().quit(0)
