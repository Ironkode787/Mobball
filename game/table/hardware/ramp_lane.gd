class_name RampLane
extends Node2D
## A wireform ramp: the Staircase up to the Club, and the one-way lane back down.
##
## A ramp in a top-down table is the one piece of hardware that cannot be built out of walls.
## It passes *over* the playfield — over the arch, over the payphones, over the shooter-lane
## divider — and none of that geometry may touch it. So the ball is lifted off the field
## (see BallHold) and constrained to a rail: one arc-length coordinate `s` along an authored
## polyline, one speed `v` along it, and gravity resolved onto the local tangent.
##
## That keeps everything a ramp needs to be true, true by construction:
##
##   * **The climb is real.** `v` bleeds off against `climb_gravity` exactly as it would up
##     a slope, so a hard shot makes the top and a soft one dies part-way and slides back
##     out of the mouth it came in by. `climb_gravity` is the ramp's rake, not the table's:
##     a wireform climbing to the second storey is a gentler slope than the playfield.
##   * **It cannot wedge.** There is nowhere sideways to go. The only exits are the two ends,
##     and `STALL_TIMEOUT` guarantees one of them even if the numbers are ever tuned into a
##     dead spot.
##   * **The gate is a number.** Entry needs `entry_speed` *along the rail* — not raw speed,
##     so a ball crossing the mouth sideways or falling down through it is not a shot up the
##     ramp and is left alone on the playfield.

## The ball took the mouth. `speed` is its speed along the rail at that moment.
signal entered(speed: float)
## It made the top. This is the switch worth paying for.
signal crested(speed: float)
## It ran out of climb and came back out of the mouth.
signal rolled_back(speed: float)

const STALL_TIMEOUT := 8.0
const RAIL_HALF := 26.0             ## drawn half-width of the wireform
const ARROW_STEP := 190.0

@export var id: StringName = &"ramp"

## Speed along the rail the mouth demands. Anything less is not a ramp shot.
var entry_speed: float = 1500.0
## The ramp's own rake, px/s². Lower than the table's gravity: a ramp is a slope, not a wall.
var climb_gravity: float = 560.0
## Wireform friction ceiling — a real ramp does not let the ball accelerate forever.
var max_speed: float = 1800.0
## 0 keeps whatever speed the rail ends with; anything else is a controlled delivery.
var release_speed: float = 0.0
## A ball taken at rest still has to go somewhere (the deck's return catcher).
var min_forward: float = 0.0
## Mouth window in global space, centred on `entry_center` (defaults to the first point).
var entry_size: Vector2 = Vector2(78.0, 62.0)
var entry_center: Vector2 = Vector2.ZERO
## Where a ball is put down if the ramp is switched off underneath it.
var abort_at: Vector2 = Vector2.ZERO
var color: Color = Feel.COL_BRASS.darkened(0.35)

var points: PackedVector2Array = PackedVector2Array()

var _cum: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _present: bool = true
var _ball: Ball = null
var _riding: bool = false
var _s: float = 0.0
var _v: float = 0.0
var _ride_time: float = 0.0
var _flash: float = 0.0


func configure(p_id: StringName, path: PackedVector2Array) -> void:
	id = p_id
	points = path
	_cum = PackedFloat32Array()
	_total = 0.0
	_cum.append(0.0)
	for i in range(points.size() - 1):
		_total += points[i].distance_to(points[i + 1])
		_cum.append(_total)
	if entry_center == Vector2.ZERO and points.size() > 0:
		entry_center = points[0]
	if abort_at == Vector2.ZERO and points.size() > 0:
		abort_at = points[0]


func set_ball(b: Ball) -> void:
	if _riding and b != _ball:
		_riding = false                 # the old ball is gone; forget the ride, not the ramp
	_ball = b


func riding() -> bool:
	return _riding and _ball != null and is_instance_valid(_ball)


func length() -> float:
	return _total


## How far along the rail the current ride has got, in px. Zero when nothing is riding.
## The City Hall loop reads this to know the lap has closed before the ball is home.
func progress() -> float:
	return _s if riding() else 0.0


## Rail speed of the current ride, px/s (signed: negative is sliding back out the mouth).
func ride_speed() -> float:
	return _v if riding() else 0.0


## Rail speed needed at the mouth to reach the top, ignoring the speed ceiling. The sim
## holds `entry_speed` above this so a shot that passes the gate always makes the climb.
func required_entry_speed() -> float:
	var worst := 0.0
	var rise := 0.0
	for i in range(points.size() - 1):
		rise += (points[i].y - points[i + 1].y)     # positive = climbing
		worst = maxf(worst, rise)
	return sqrt(maxf(2.0 * climb_gravity * worst, 0.0))


func entry_rect() -> Rect2:
	return Rect2(entry_center - entry_size * 0.5, entry_size)


func point_at(s: float) -> Vector2:
	if points.is_empty():
		return global_position
	var t := clampf(s, 0.0, _total)
	for i in range(points.size() - 1):
		if t <= _cum[i + 1] or i == points.size() - 2:
			var seg := _cum[i + 1] - _cum[i]
			var f := 0.0 if seg <= 0.0 else clampf((t - _cum[i]) / seg, 0.0, 1.0)
			return points[i].lerp(points[i + 1], f)
	return points[points.size() - 1]


func tangent_at(s: float) -> Vector2:
	if points.size() < 2:
		return Vector2.UP
	var t := clampf(s, 0.0, _total)
	for i in range(points.size() - 1):
		if t <= _cum[i + 1] or i == points.size() - 2:
			var d := points[i + 1] - points[i]
			return d.normalized() if d.length() > 0.0001 else Vector2.UP
	return Vector2.UP


## Arc length of the point on the rail nearest `p` — where a ball joins it.
func project(p: Vector2) -> float:
	var best := 0.0
	var best_d := INF
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var f := 0.0 if l2 <= 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * f
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = _cum[i] + sqrt(l2) * f
	return best


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 1.5, 0.0)
		queue_redraw()
	if not _present or points.size() < 2:
		return
	if _ball == null or not is_instance_valid(_ball):
		_riding = false
		return
	if _riding:
		_advance(delta)
	else:
		_try_enter()


func _try_enter() -> void:
	if BallHold.is_held(_ball):
		return                          # already on some other piece of hardware
	if not entry_rect().has_point(_ball.global_position):
		return
	var s := project(_ball.global_position)
	var along := _ball.linear_velocity.dot(tangent_at(s))
	if along < entry_speed:
		return
	_riding = true
	_ride_time = 0.0
	_s = s
	_v = maxf(along, min_forward)
	_flash = 1.0
	BallHold.take(_ball)
	TableScore.hit(StringName(String(id) + "_entry"), _ball, _v)
	AudioDirector.play(&"orbit_whoosh")
	entered.emit(_v)
	queue_redraw()


func _advance(delta: float) -> void:
	_ride_time += delta
	_v += climb_gravity * tangent_at(_s).y * delta
	_v = clampf(_v, -max_speed, max_speed)
	_s += _v * delta
	if _ride_time > STALL_TIMEOUT:
		# Cannot happen with the shipped numbers; if tuning ever breaks that, the ball
		# leaves anyway rather than living in a pipe.
		if _s > _total * 0.5:
			_finish_top()
		else:
			_finish_bottom()
		return
	if _s >= _total:
		_finish_top()
	elif _s <= 0.0:
		_finish_bottom()
	else:
		BallHold.steer(_ball, point_at(_s), delta)


func _finish_top() -> void:
	var speed := absf(_v) if release_speed <= 0.0 else minf(absf(_v), release_speed)
	var dir := tangent_at(_total)
	_riding = false
	BallHold.release(_ball, points[points.size() - 1], dir * speed)
	crested.emit(speed)


func _finish_bottom() -> void:
	var speed := absf(_v)
	var dir := -tangent_at(0.0)
	_riding = false
	BallHold.release(_ball, points[0], dir * maxf(speed, 120.0))
	rolled_back.emit(speed)


func set_hardware_active(active: bool) -> void:
	if _present == active:
		return
	_present = active
	visible = active
	if not active and _riding:
		_riding = false
		BallHold.release(_ball, abort_at, Vector2.ZERO)


func is_hardware_active() -> bool:
	return _present


func _draw() -> void:
	if points.size() < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(points.size()):
		var t: Vector2 = tangent_at(_cum[i])
		if i == points.size() - 1:
			t = tangent_at(_total - 1.0)
		var n := Vector2(-t.y, t.x) * RAIL_HALF
		left.append(points[i] + n)
		right.append(points[i] - n)
	# a shadow first: the wireform reads as something the ball travels *over*
	var shade := PackedVector2Array()
	for p: Vector2 in points:
		shade.append(p + Vector2(7.0, 9.0))
	draw_polyline(shade, Color(0.0, 0.0, 0.0, 0.22), RAIL_HALF * 2.0, true)
	draw_polyline(points, Color(Feel.COL_FELT.r, Feel.COL_FELT.g, Feel.COL_FELT.b, 0.55),
			RAIL_HALF * 2.0 - 6.0, true)
	var rail := color.lerp(Feel.COL_NEWSPRINT, _flash * 0.8)
	draw_polyline(left, rail, 6.0, true)
	draw_polyline(right, rail, 6.0, true)
	# direction chevrons, so the shot reads at a glance
	var s := ARROW_STEP * 0.5
	while s < _total:
		var p := point_at(s)
		var t := tangent_at(s)
		var n := Vector2(-t.y, t.x) * 11.0
		draw_line(p - t * 11.0 + n, p + t * 11.0, rail, 4.0)
		draw_line(p - t * 11.0 - n, p + t * 11.0, rail, 4.0)
		s += ARROW_STEP
	# The mouth, when it is a shot you aim at. A catcher that spans a whole deck floor is not
	# one — it gets a lip along its edge instead of a box drawn round it.
	var mouth := entry_rect()
	var lip := Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, _flash)
	if mouth.size.x <= 200.0:
		draw_rect(mouth, lip, false, 4.0)
	else:
		draw_line(mouth.position, mouth.position + Vector2(mouth.size.x, 0.0),
				lip.darkened(0.35), 5.0)
