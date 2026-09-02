extends RefCounted
## The Balls registry semantics (specs/ball-registry.md). Balls here never enter a tree,
## so they are freed by hand at the end.


func run(t: TestCtx) -> void:
	var reg: Node = load("res://game/core/ball_registry.gd").new()
	var a: Ball = Ball.new()
	var b: Ball = Ball.new()
	a.position = Vector3(-1.0, 0.1, -3.0)
	b.position = Vector3(0.5, 0.1, 3.5)

	var counts: Array[int] = []
	var lasts: Array = []
	reg.count_changed.connect(func(n: int) -> void: counts.append(n))
	reg.last_ball.connect(func(x: Ball) -> void: lasts.append(x))

	t.eq(reg.count(), 0, "starts empty")
	t.eq(reg.primary(), null, "no primary when empty")

	reg.register(a, {"name": "Sal"})
	reg.register(a)
	t.eq(reg.count(), 1, "double register is idempotent")
	t.eq(String(reg.guy_for(a).get("name", "")), "Sal", "guy rides the ball")
	t.eq(reg.guy_for(b), {}, "unknown ball has no guy")

	reg.register(b)
	t.eq(reg.count(), 2, "two live balls")
	t.eq(reg.primary(), b, "primary is the lowest ball (largest z)")
	a.position.z = 5.0
	t.eq(reg.primary(), a, "primary follows the danger")

	reg.unregister(a)
	t.eq(reg.count(), 1, "unregister removes")
	t.eq(lasts, [b], "last_ball fired once, with the survivor")
	reg.unregister(a)
	t.eq(counts.size(), 3, "double unregister emits nothing new")
	t.eq(reg.guy_for(a), {}, "the guy left with his ball")

	reg.set_guy(b, {"name": "Enzo"})
	t.eq(String(reg.guy_for(b).get("name", "")), "Enzo", "set_guy attaches late")

	reg.clear()
	t.eq(reg.count(), 0, "clear empties the registry")

	a.free()
	b.free()
	reg.free()
