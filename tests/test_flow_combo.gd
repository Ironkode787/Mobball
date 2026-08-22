extends RefCounted
## Clean Work (game/flow/combo.gd): chains of *different* shots inside 4 s.


func run(t: TestCtx) -> void:
	_chain(t)
	_cap(t)
	_repeat_restarts(t)
	_window(t)
	_respect(t)


func _chain(t: TestCtx) -> void:
	var c := Combo.new()
	t.near(c.multiplier(), 1.0, 1e-9, "no chain, no multiplier")
	t.near(c.on_hit(&"bumpers"), 1.0, 1e-9, "the first hit is x1")
	t.eq(c.count, 1, "chain of one")
	t.near(c.on_hit(&"slings"), 1.5, 1e-9, "the second different shot is x1.5")
	t.near(c.on_hit(&"spinner"), 2.25, 1e-9, "the third is x1.5^2")
	t.eq(c.count, 3, "chain of three")
	t.near(c.time_left(), Combo.WINDOW, 1e-9, "each link refreshes the window")


func _cap(t: TestCtx) -> void:
	var c := Combo.new()
	var groups: Array[StringName] = [&"a", &"b", &"c", &"d", &"e", &"f", &"g", &"h", &"i"]
	var last := 0.0
	for g in groups:
		last = c.on_hit(g)
	t.ok(last <= Combo.CAP + 1e-9, "the multiplier never passes the cap")
	t.near(last, Combo.CAP, 1e-9, "a long chain sits exactly on the cap")


func _repeat_restarts(t: TestCtx) -> void:
	var c := Combo.new()
	c.on_hit(&"bumpers")
	c.on_hit(&"slings")
	t.eq(c.count, 2, "two different shots chain")
	t.near(c.on_hit(&"bumpers"), 1.0, 1e-9, "a shot already in the chain starts a new one")
	t.eq(c.count, 1, "and the chain is back to one")


func _window(t: TestCtx) -> void:
	var c := Combo.new()
	var seen: Array[int] = []
	c.changed.connect(func(n: int) -> void: seen.append(n))
	c.on_hit(&"bumpers")
	c.tick(Combo.WINDOW * 0.5)
	t.near(c.on_hit(&"slings"), 1.5, 1e-9, "inside the window the chain continues")
	c.tick(Combo.WINDOW + 0.01)
	t.eq(c.count, 0, "past the window the chain lapses")
	t.near(c.multiplier(), 1.0, 1e-9, "and the multiplier goes home")
	t.eq(seen, [1, 2, 0], "changed() reports every step, including the lapse")

	c.on_hit(&"bumpers")
	c.reset()
	t.eq(c.count, 0, "reset drops the chain")


func _respect(t: TestCtx) -> void:
	var c := Combo.new()
	# GDScript lambdas capture by value, so the tally has to live in a reference type.
	var stars: Array[int] = []
	c.respect_earned.connect(func(n: int) -> void: stars.append(n))
	c.on_hit(&"bumpers")
	c.on_hit(&"slings")
	t.eq(stars.size(), 0, "a chain of two pays no Respect")
	c.on_hit(&"spinner")
	t.eq(stars, [Combo.RESPECT_STARS], "x3 pays the stars")
	c.on_hit(&"wire")
	t.eq(stars.size(), 1, "and only once per chain")
	c.reset()
	c.on_hit(&"bumpers")
	c.on_hit(&"slings")
	c.on_hit(&"spinner")
	t.eq(stars, [Combo.RESPECT_STARS, Combo.RESPECT_STARS], "a fresh chain can earn again")
