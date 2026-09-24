class_name PathRide
extends RefCounted
## A scripted carrier (docs/19 §8): a held ball driven along a table-space polyline at a set
## pace, then handed back to physics with a real velocity. Owners call `step()` from their
## physics tick; `done()` flips when the last point is reached.

var ball: Ball = null
var points: PackedVector3Array = PackedVector3Array()
var speed: float = 3.0

var _cum: PackedFloat32Array = PackedFloat32Array()
var _s: float = 0.0


static func start(b: Ball, path: PackedVector3Array, p_speed: float) -> PathRide:
	var r := PathRide.new()
	r.ball = b
	r.points = path
	r.speed = maxf(p_speed, 0.1)
	r._cum.resize(path.size())
	var total := 0.0
	for i in range(path.size()):
		if i > 0:
			total += path[i].distance_to(path[i - 1])
		r._cum[i] = total
	BallHold.take(b)
	return r


func length() -> float:
	return _cum[_cum.size() - 1] if _cum.size() > 0 else 0.0


func progress() -> float:
	var l := length()
	return clampf(_s / l, 0.0, 1.0) if l > 0.0 else 1.0


func point_at(s: float) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	if s <= 0.0:
		return points[0]
	for i in range(1, points.size()):
		if s <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			var t := (s - _cum[i - 1]) / seg if seg > 0.0 else 1.0
			return points[i - 1].lerp(points[i], t)
	return points[points.size() - 1]


## Direction of travel at the end of the path (for the hand-back velocity).
func exit_direction() -> Vector3:
	var n := points.size()
	if n < 2:
		return Vector3.FORWARD
	return (points[n - 1] - points[n - 2]).normalized()


func step(delta: float) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	_s = minf(_s + speed * delta, length())
	BallHold.steer(ball, point_at(_s), delta)


func done() -> bool:
	return ball == null or not is_instance_valid(ball) or _s >= length() - 0.0001


func release(velocity: Vector3) -> void:
	if ball != null and is_instance_valid(ball):
		BallHold.release(ball, points[points.size() - 1], velocity)
	ball = null
