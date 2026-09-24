class_name SimBase
extends Node3D
## Shared plumbing for the machine sims: a table, physics-tick stepping (never wall time),
## PASS/FAIL bookkeeping, and the drop/hold helpers every scenario uses. Each sim scene quits
## 0 only if every scenario passed; tools/check.sh runs them all.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

var table: ProgressionTable = null
var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _switches: PackedStringArray = []


func make_table(all_hardware: bool = true) -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = all_hardware
	table.refresh_hardware()
	Events.switch_hit.connect(func(id: StringName, _b: Node3D, _s: float) -> void: _switches.append(String(id)))


func ticks(seconds: float) -> int:
	return int(ceil(seconds * float(Engine.physics_ticks_per_second)))


func step(count: int = 1) -> void:
	for i in range(count):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	await step(ticks(seconds))


func begin(name: String) -> void:
	_current = name
	_fails = PackedStringArray()
	_switches.clear()


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func near(a: float, b: float, tol: float, msg: String) -> void:
	check(absf(a - b) <= tol, "%s (got %.3f, want %.3f ±%.3f)" % [msg, a, b, tol])


func finish() -> void:
	var ok := _fails.is_empty()
	_results.append({"name": _current, "ok": ok, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if ok else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


func hit_switch(id: String) -> bool:
	return _switches.has(id)


func report(title: String) -> void:
	var passed := 0
	for r in _results:
		if r["ok"]:
			passed += 1
	print("%s scenarios: %d  passed: %d  failed: %d" % [title, _results.size(), passed, _results.size() - passed])
	print("OK" if passed == _results.size() else "FAILED")
	get_tree().quit(0 if passed == _results.size() else 1)


## A fresh ball at a plan point on whatever floor is there, optionally moving (table space).
func drop_at(plan: Vector2, velocity: Vector3 = Vector3.ZERO, settle: int = 4) -> Ball:
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	b.place(Layout.p3(plan, table.floor_height_at(plan) + Feel.BALL_RADIUS + 0.01))
	if velocity != Vector3.ZERO:
		b.set_velocity(velocity)
	await step(settle)
	return b


## A ball whose whole path over this long fits in a box `CAGE_SPAN` across is caged: parked,
## or rattling in a corner it cannot leave.
const CAGE_SECONDS := 2.5
const CAGE_SPAN := 0.8
const CAGE_EVERY := 12


## Step `seconds`, watching the ball: returns min and max z reached, max height, the longest
## still spell in ticks and where, whether the ball was ever caged (and where), and whether it
## survived. Time held by a scoop or a lock does not count as still or caged.
func watch(seconds: float, b: Ball) -> Dictionary:
	var min_z := INF
	var max_z := -INF
	var max_y := -INF
	var still := 0
	var still_max := 0
	var still_at := Vector3.ZERO
	var last := Vector3.INF
	var escaped := false
	var trail: Array[Vector2] = []
	var caged := false
	var caged_at := Vector3.ZERO
	var window := int(CAGE_SECONDS * 240.0 / float(CAGE_EVERY))
	var bounds := table.bounds()
	for i in range(ticks(seconds)):
		await step(1)
		if b == null or not is_instance_valid(b):
			break
		var p := b.table_position()
		if not bounds.has_point(p):
			escaped = true
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
		max_y = maxf(max_y, p.y)
		if BallHold.is_held(b):
			still = 0
			trail.clear()
			last = p
			continue
		if last != Vector3.INF and p.distance_to(last) < 0.002:
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p
		if i % CAGE_EVERY == 0:
			trail.append(Vector2(p.x, p.z))
			if trail.size() > window:
				trail.pop_front()
			if trail.size() == window and not caged:
				var box := Rect2(trail[0], Vector2.ZERO)
				for q in trail:
					box = box.expand(q)
				if box.size.x < CAGE_SPAN and box.size.y < CAGE_SPAN:
					caged = true
					caged_at = p
	return {"min_z": min_z, "max_z": max_z, "max_y": max_y, "still_max": still_max, "still_at": still_at,
			"caged": caged, "caged_at": caged_at, "alive": b != null and is_instance_valid(b), "escaped": escaped}
