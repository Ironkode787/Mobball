class_name BossTarget
extends AnimatableBody2D
## A Commission boss's vehicle (specs/m2-content.md §5): Sammy's sedan crossing the upper
## field on a rail, the Butcher's refrigerated truck riding the orbit channel. One class,
## because both are the same machine — a kinematic body that walks a path, takes a fixed
## number of hits and reports each one.
##
## Kinematic rather than static so the impulse transfer goes through the solver the way the
## flippers' does (`sync_to_physics`): a ball that meets a moving car gets shoved by a moving
## car. `min_speed` is the Butcher's rule — a hit that arrives without orbit pace rattles off
## the panel and does not count.
##
## Anti-trap is a design requirement, not a polish item. A body parked in a 108 px channel is
## a place a ball can be pinned against a wall for the rest of the Night, so every contact
## kicks the ball back off the panel and anything that comes to rest against it is popped
## loose on the next tick — the same rule the bumpers and slings live under.
##
## Boss hardware is never part of the owned set. Like the raid's cop targets it is built with
## the table, stands dormant, and only a live fight switches it on.

## One contact that counted. `speed` is what the ball arrived with.
signal struck(kind: StringName, hits_left: int, speed: float)
## The last hit landed.
signal broken(kind: StringName)
## A contact that did not count (too slow for `min_speed`) — the Butcher teaching the loop.
signal shrugged(kind: StringName, speed: float)

## Same beat as a standup: one contact is one hit, however many frames it touches for.
const COOLDOWN := 0.30
## Shove off the panel, so a car is never a wall to lean on.
const BOUNCE_IMPULSE := 620.0
## A ball resting against the panel gets the same treatment (Feel.HARDWARE_STALL_SPEED).
const STALL_IMPULSE := 780.0

@export var kind: StringName = &"sedan"

var hits_left: int = 0
## A hit under this speed bounces off and does not count. 0 = any contact counts.
var min_speed: float = 0.0
## Travel along the path, px/s. The path ping-pongs; the car turns round at each end.
var travel_speed: float = 240.0
var body_length: float = 150.0
var body_thick: float = 46.0
## Panel colour — the sedan is black, the truck is refrigerated white.
var color: Color = Feel.COL_INK.lightened(0.10)

var _present: bool = false
var _path: PackedVector2Array = PackedVector2Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _along: float = 0.0
var _dir: float = 1.0
var _moving: bool = false
var _cooldown: float = 0.0
var _pulse: float = 0.0
var _shape: CollisionShape2D = null
var _ring: Area2D = null
var _ring_shape: CollisionShape2D = null
var _inside: Array[Ball] = []


func _ready() -> void:
	process_physics_priority = 10
	# NOT `sync_to_physics`: that mode makes the physics server the owner of the transform and
	# quietly reverts a body this script places itself (the car parked at the origin and the
	# truck never left it). A car we drive ourselves has to own its own transform; the shove
	# a ball gets off the panel is applied by hand in `_on_ring_entered` anyway.
	sync_to_physics = false
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.24)

	_shape = CollisionShape2D.new()
	_shape.name = "Panel"
	var cap := CapsuleShape2D.new()
	cap.radius = body_thick * 0.5
	cap.height = body_length + body_thick
	_shape.shape = cap
	_shape.rotation = PI * 0.5
	add_child(_shape)

	_ring = Area2D.new()
	_ring.name = "Ring"
	_ring.collision_layer = Feel.LAYER_ZONES
	_ring.collision_mask = Feel.LAYER_BALL
	_ring.monitorable = false
	_ring_shape = CollisionShape2D.new()
	var ring_cap := CapsuleShape2D.new()
	ring_cap.radius = body_thick * 0.5 + Feel.BALL_RADIUS
	ring_cap.height = body_length + body_thick + Feel.BALL_RADIUS * 2.0
	_ring_shape.shape = ring_cap
	_ring_shape.rotation = PI * 0.5
	_ring.add_child(_ring_shape)
	add_child(_ring)
	_ring.body_entered.connect(_on_ring_entered)
	_ring.body_exited.connect(_on_ring_exited)
	_apply_size()
	_apply_collision()


## Body dimensions, in px. Call before `arm()`; the shapes follow immediately.
func size_to(length: float, thick: float) -> void:
	body_length = length
	body_thick = thick
	_apply_size()


func _apply_size() -> void:
	if _shape != null and _shape.shape is CapsuleShape2D:
		var cap: CapsuleShape2D = _shape.shape
		cap.radius = body_thick * 0.5
		cap.height = body_length + body_thick
	if _ring_shape != null and _ring_shape.shape is CapsuleShape2D:
		var ring: CapsuleShape2D = _ring_shape.shape
		ring.radius = body_thick * 0.5 + Feel.BALL_RADIUS
		ring.height = body_length + body_thick + Feel.BALL_RADIUS * 2.0
	queue_redraw()


## The rail this car rides, in table space. Two points is a straight run; a sampled arc is
## the Butcher's orbit. The car starts at the first point heading forward.
func set_path(points: PackedVector2Array) -> void:
	_path = points
	_lengths = PackedFloat32Array()
	_total = 0.0
	for i in range(1, _path.size()):
		var seg := _path[i].distance_to(_path[i - 1])
		_lengths.append(seg)
		_total += seg
	_along = 0.0
	_dir = 1.0
	_moving = _total > 0.0
	if _path.size() > 0:
		_place_along(0.0)


## Put the car somewhere and stop it there (Sammy's phase 3: the sedan parks).
func park_at(at: Vector2, facing: float = 0.0) -> void:
	_moving = false
	global_position = at
	rotation = facing


## Stand it up with `hits` panels left. `speed_gate` is the Butcher's orbit-pace rule.
func arm(hits: int, speed_gate: float = 0.0) -> void:
	hits_left = maxi(hits, 0)
	min_speed = maxf(speed_gate, 0.0)
	_cooldown = 0.0
	_inside.clear()
	queue_redraw()


func is_armed() -> bool:
	return _present and hits_left > 0


func set_moving(on: bool) -> void:
	_moving = on and _total > 0.0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_inside.clear()
	_cooldown = 0.0
	_apply_collision()
	queue_redraw()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _ring != null:
		_ring.collision_layer = Feel.LAYER_ZONES if _present else 0
		_ring.collision_mask = Feel.LAYER_BALL if _present else 0


# ==================================================================== the drive =====


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _present and _moving and _total > 0.0:
		_along += _dir * travel_speed * delta
		if _along >= _total:
			_along = _total
			_dir = -1.0
		elif _along <= 0.0:
			_along = 0.0
			_dir = 1.0
		_place_along(_along)
	_pop_stalled()


## Position and heading at `distance` along the path. The car turns to face its own tangent,
## so a truck riding the orbit lies along the channel instead of across it.
func _place_along(distance: float) -> void:
	if _path.size() < 2:
		if _path.size() == 1:
			global_position = _path[0]
		return
	var left := clampf(distance, 0.0, _total)
	for i in range(_lengths.size()):
		var seg := _lengths[i]
		if left <= seg or i == _lengths.size() - 1:
			var t := 0.0 if seg <= 0.0 else clampf(left / seg, 0.0, 1.0)
			var a := _path[i]
			var b := _path[i + 1]
			global_position = a.lerp(b, t)
			var heading := (b - a)
			if heading.length_squared() > 0.0001:
				rotation = heading.angle()
			return
		left -= seg


## A ball asleep against the panel is a dead Night. Same rule the bumpers keep.
func _pop_stalled() -> void:
	if not _present or _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	for b in _inside:
		if b.speed() < Feel.HARDWARE_STALL_SPEED:
			b.kick(_away_from(b) * STALL_IMPULSE)
			return


func _on_ring_exited(body: Node2D) -> void:
	if body is Ball:
		_inside.erase(body as Ball)


func _on_ring_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball: Ball = body
	_inside.append(ball)
	if _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	var speed := ball.speed()
	ball.kick(_away_from(ball) * BOUNCE_IMPULSE)
	_pulse = 1.0
	queue_redraw()
	if hits_left <= 0:
		AudioDirector.play(&"wall_tap")
		return
	if min_speed > 0.0 and speed < min_speed:
		# The Butcher's lesson: a panel hit without orbit pace is a dent, not a break.
		AudioDirector.play(&"wall_tap")
		shrugged.emit(kind, speed)
		return
	hits_left -= 1
	AudioDirector.play(&"drop_bank_down" if hits_left <= 0 else &"drop_clack")
	TableScore.hit(StringName("boss_%s" % kind), ball, speed)
	struck.emit(kind, hits_left, speed)
	if hits_left <= 0:
		broken.emit(kind)


func _away_from(ball: Ball) -> Vector2:
	var away := ball.global_position - global_position
	# Along the panel's short axis: a car shoves you off its flank, not off its nose.
	var normal := Vector2(0.0, 1.0).rotated(rotation)
	var side := 1.0 if away.dot(normal) >= 0.0 else -1.0
	var mixed := (normal * side * 1.4 + away.normalized() * 0.6)
	return mixed.normalized() if mixed.length() > 0.001 else Vector2.UP


# ==================================================================== drawing =====


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 4.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var half := body_length * 0.5
	var r := body_thick * 0.5
	var panel := color.lerp(Feel.COL_NEWSPRINT, _pulse * 0.55)
	if hits_left <= 0:
		panel = panel.darkened(0.45)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Feel.COL_INK, body_thick + 8.0)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), panel, body_thick)
	# a cabin, a windscreen and two wheels: enough car to read at a glance
	draw_rect(Rect2(Vector2(-half * 0.25, -r * 0.62), Vector2(half * 0.9, r * 1.24)),
			Feel.COL_FELT.darkened(0.25))
	draw_line(Vector2(half * 0.62, -r * 0.5), Vector2(half * 0.62, r * 0.5),
			Feel.COL_BRASS.darkened(0.2), 4.0)
	for x: float in [-half * 0.55, half * 0.55]:
		draw_circle(Vector2(x, r * 0.92), r * 0.34, Feel.COL_INK)
	# hits left, as pips along the flank — the panel count is the phase's clock
	for i in range(hits_left):
		var px := lerpf(-half * 0.7, half * 0.7, 0.0 if hits_left <= 1 else float(i) / float(hits_left - 1))
		draw_circle(Vector2(px, -r * 0.92), 6.0, Feel.COL_BRASS)
