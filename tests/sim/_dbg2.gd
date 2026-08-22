extends Node2D
## Probe: how does Godot 4.5 2D combine friction and bounce between two bodies?

func _ready() -> void:
	_go()

func _run_case(fb: float, fw: float, bb: float, bw: float) -> Array:
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	floor_body.physics_material_override = Feel.make_material(fw, bw)
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(4000.0, 200.0)
	cs.shape = rect
	floor_body.add_child(cs)
	floor_body.position = Vector2(0.0, 400.0)
	floor_body.rotation = deg_to_rad(30.0)
	add_child(floor_body)

	var b := RigidBody2D.new()
	b.collision_layer = 2
	b.collision_mask = 1
	b.lock_rotation = true
	b.can_sleep = false
	b.physics_material_override = Feel.make_material(fb, bb)
	var bs := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = 28.0
	bs.shape = circ
	b.add_child(bs)
	b.position = Vector2(0.0, 400.0 - 100.0 * cos(deg_to_rad(30.0)) - 30.0)
	add_child(b)

	for i in range(120):
		await get_tree().physics_frame
	var res := [b.linear_velocity.length()]
	b.queue_free()
	floor_body.queue_free()
	await get_tree().physics_frame
	return res

func _go() -> void:
	# slope 30deg, tan=0.577. slide speed after 1s with friction f: g*(sin - f*cos)*1s
	for pair in [[1.0, 0.0], [0.0, 1.0], [1.0, 1.0], [0.0, 0.0], [1.0, 0.14], [0.5, 0.5]]:
		var r: Array = await _run_case(pair[0], pair[1], 0.0, 0.0)
		print("fball=%.2f fwall=%.2f -> speed after 1s = %.1f" % [pair[0], pair[1], r[0]])
	print("gravity=", ProjectSettings.get_setting("physics/2d/default_gravity"))
	print("frictionless expectation: g*sin30*1s = ", 3800.0 * 0.5)
	get_tree().quit(0)
