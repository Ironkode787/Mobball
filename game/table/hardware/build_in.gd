class_name BuildIn
extends Node2D
## The construction animation (docs/02 §0: "new geometry slides in with a construction
## animation — scaffolding, tarps, a crew of little guys with hammers"). When a piece of
## hardware flips dormant→active it is built rather than switched on: a scaffold goes up
## around it, the hammers start, and the piece fades in under a tarp that lifts.
##
## Two rules keep this a purely cosmetic layer, which is what makes it safe to bolt onto a
## machine full of tuned physics:
##
##   * **Collision arrives instantly, the picture arrives over 1.2 s.** The piece's colliders
##     are switched on by Dormant exactly as before; only `modulate` moves. Half-on hardware
##     is the worst state a table can be in (see hardware/dormant.gd), and a build-in that
##     delayed collision would manufacture that state on every purchase.
##   * **Nothing moves.** The "rise" is drawn — the tarp and the scaffold travel, the piece
##     does not. Nudging a live StaticBody2D up 14 px and easing it home would be a real
##     geometry change for 1.2 s, and a sim that forces hardware on mid-scenario would be
##     measuring a table that is still moving.
##
## Headless runs (every sim, every test) get `instant = true`, so no scenario's timing can
## depend on a purchase animation. The screenshot rigs and the game get the animation.

const DURATION := 1.2
const HAMMER_TAPS := 6
const SCAFFOLD_PAD := 16.0

## Set false and the piece appears at once, alpha 1, with nothing drawn.
var enabled: bool = true

var _jobs: Array[Dictionary] = []          ## { node, rect, t, seed }
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0xB011D
	z_index = 40


## Start building `node`. Idempotent per node: a second call restarts the crew rather than
## stacking two of them.
func start(node: Node2D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not enabled or (Presentation.fx != null and Presentation.fx.reduced_motion):
		node.modulate.a = 1.0
		return
	for i in range(_jobs.size() - 1, -1, -1):
		if _jobs[i]["node"] == node:
			_jobs.remove_at(i)
	var rect := approx_rect(node)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		node.modulate.a = 1.0
		return
	node.modulate.a = 0.0
	_jobs.append({"node": node, "rect": rect.grow(SCAFFOLD_PAD), "t": 0.0,
			"seed": _rng.randi_range(0, 4096)})
	AudioDirector.play(&"stamp_thunk")
	queue_redraw()


## Stop building `node` and leave it fully visible — the piece was switched off again (or a
## sim reached in and forced the table), and a half-faded ghost must never be left behind.
func cancel(node: Node2D) -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		if _jobs[i]["node"] == node:
			_jobs.remove_at(i)
	if is_instance_valid(node):
		node.modulate.a = 1.0
	queue_redraw()


func building() -> int:
	return _jobs.size()


func is_building(node: Node2D) -> bool:
	for job: Dictionary in _jobs:
		if job["node"] == node:
			return true
	return false


## Drop every crew and leave the pieces fully built. Used when a scenario switches the whole
## table out from under the animation.
func finish_all() -> void:
	for job: Dictionary in _jobs:
		var node: Node2D = job["node"]
		if is_instance_valid(node):
			node.modulate.a = 1.0
	_jobs.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _jobs.is_empty():
		return
	for i in range(_jobs.size() - 1, -1, -1):
		var job := _jobs[i]
		var node: Node2D = job["node"]
		if not is_instance_valid(node):
			_jobs.remove_at(i)
			continue
		job["t"] = float(job["t"]) + delta
		var f := clampf(float(job["t"]) / DURATION, 0.0, 1.0)
		node.modulate.a = ease(f, 0.45)
		_jobs[i] = job
		if f >= 1.0:
			node.modulate.a = 1.0
			_jobs.remove_at(i)
	queue_redraw()


## A rough bounding box for anything with colliders under it, in this node's space. Hardware
## draws itself from its own numbers and has no shared "extent" call, so the scaffold is sized
## off the physics instead — which is the thing the player is about to start hitting.
##
## A piece with no colliders at all (City Hall is a painting and a wireform) has nothing to
## measure, so it may name its own box with `build_rect()`; without one the fallback would put
## the crew at the node's origin, which for a piece that draws in table space is the corner of
## the machine.
static func approx_rect(node: Node2D) -> Rect2:
	if node.has_method(&"build_rect"):
		var named: Variant = node.call(&"build_rect")
		if named is Rect2 and (named as Rect2).size.x > 0.0:
			return named
	var out := Rect2()
	var any := false
	for shape: CollisionShape2D in _collision_shapes(node):
		var r := shape.shape
		var reach := 30.0
		if r is CapsuleShape2D:
			reach = maxf((r as CapsuleShape2D).height, (r as CapsuleShape2D).radius * 2.0) * 0.5
		elif r is RectangleShape2D:
			reach = (r as RectangleShape2D).size.length() * 0.5
		elif r is CircleShape2D:
			reach = (r as CircleShape2D).radius
		var at := shape.global_position
		var box := Rect2(at - Vector2(reach, reach), Vector2(reach, reach) * 2.0)
		out = box if not any else out.merge(box)
		any = true
	if not any:
		var at2 := node.global_position
		return Rect2(at2 - Vector2(48.0, 48.0), Vector2(96.0, 96.0))
	return out


static func _collision_shapes(node: Node) -> Array[CollisionShape2D]:
	var out: Array[CollisionShape2D] = []
	if node is CollisionShape2D:
		out.append(node as CollisionShape2D)
	for child in node.get_children():
		out.append_array(_collision_shapes(child))
	return out


func _draw() -> void:
	for job: Dictionary in _jobs:
		_draw_job(job)


func _draw_job(job: Dictionary) -> void:
	var rect: Rect2 = job["rect"]
	var f := clampf(float(job["t"]) / DURATION, 0.0, 1.0)
	var fade := 1.0 - ease(f, 2.4)
	var scaffold := Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.85 * fade)
	# the frame goes up first, from the ground line
	var up := clampf(f / 0.45, 0.0, 1.0)
	var top := lerpf(rect.end.y, rect.position.y, ease(up, 0.4))
	draw_rect(Rect2(Vector2(rect.position.x, top),
			Vector2(rect.size.x, rect.end.y - top)), scaffold, false, 3.0)
	for i in range(3):
		var x := lerpf(rect.position.x, rect.end.x, float(i + 1) / 4.0)
		draw_line(Vector2(x, top), Vector2(x, rect.end.y), scaffold, 2.0)
	# the tarp, sliding off upward as the piece appears
	var tarp_h := rect.size.y * (1.0 - ease(clampf((f - 0.2) / 0.7, 0.0, 1.0), 0.6))
	if tarp_h > 1.0:
		draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - tarp_h),
				Vector2(rect.size.x, tarp_h)),
				Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g, Feel.COL_NEWSPRINT.b,
				0.30 * fade))
	# hammer taps: short sparks around the frame, on a seeded pattern per piece
	var seed_i := int(job["seed"])
	for i in range(HAMMER_TAPS):
		var phase := fmod(f * 3.0 + float(i) * 0.37 + float(seed_i % 17) * 0.05, 1.0)
		if phase > 0.35:
			continue
		var t := float((seed_i + i * 71) % 100) / 100.0
		var edge := (seed_i + i) % 4
		var p := _edge_point(rect, edge, t)
		var glow := (1.0 - phase / 0.35) * fade
		draw_circle(p, 3.0 + glow * 4.0,
				Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g, Feel.COL_NEWSPRINT.b, glow))
		draw_line(p, p + Vector2(6.0, -8.0),
				Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, glow), 2.0)


func _edge_point(rect: Rect2, edge: int, t: float) -> Vector2:
	match edge:
		0:
			return Vector2(lerpf(rect.position.x, rect.end.x, t), rect.position.y)
		1:
			return Vector2(rect.end.x, lerpf(rect.position.y, rect.end.y, t))
		2:
			return Vector2(lerpf(rect.position.x, rect.end.x, t), rect.end.y)
	return Vector2(rect.position.x, lerpf(rect.position.y, rect.end.y, t))
