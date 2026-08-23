extends RefCounted
## The inlane has to admit a ball. A device report had the ball wedging between the return
## sweep and the sling triangle: the channel measured 51px against a 56px ball, and the pinch
## sat on the sling's square corner, which carries no sensor band — so nothing kicked it out.
##
## The gap is a consequence of four constants that are edited independently, so it is asserted
## here rather than left to be re-discovered on a phone.

const T := preload("res://game/table/segments/progression_table.gd")

## A ball rolling a lane needs more than a hairline over its own width, or it wedges on the
## first bounce. Real inlanes run appreciably wider than the ball.
const MARGIN := 1.15


func run(t: TestCtx) -> void:
	var diameter := Feel.BALL_RADIUS * 2.0
	var need := diameter * MARGIN

	t.begin("inlane admits the ball")
	var gap := _channel_gap()
	t.ok(gap >= diameter,
			"inlane channel %.1fpx is narrower than the %.1fpx ball" % [gap, diameter])
	t.ok(gap >= need,
			"inlane channel %.1fpx leaves no rolling room (want >= %.1fpx)" % [gap, need])

	t.begin("the pinch is not on the sling's dead corner")
	# The square corner (p0) has no face sensor: a ball resting against it is never kicked
	# free. Keep it the *widest* part of the channel, not the narrowest.
	var corner_clear := _dist_to_bar(T.SLING_OUTER_BOTTOM) - _guide_half()
	t.ok(corner_clear >= need,
			"sling square corner clears the return by only %.1fpx" % corner_clear)

	t.begin("outlane stays passable")
	var out_gap := _outlane_gap()
	t.ok(out_gap >= diameter,
			"outlane channel %.1fpx is narrower than the %.1fpx ball" % [out_gap, diameter])


func _guide_half() -> float:
	return T.GUIDE_THICK * 0.5


func _tri() -> Array[Vector2]:
	return [T.SLING_OUTER_BOTTOM, T.SLING_INNER, T.SLING_OUTER_TOP]


## Narrowest point of the return sweep, measured from the guide's face to the triangle.
func _channel_gap() -> float:
	var a: Vector2 = Vector2(T.OUTLANE_X, T.OUTLANE_BOTTOM)
	var b: Vector2 = T.INLANE_END
	return _sweep(a, b) - _guide_half()


func _outlane_gap() -> float:
	var a := Vector2(T.OUTLANE_X, T.OUTLANE_TOP)
	var b := Vector2(T.OUTLANE_X, T.OUTLANE_BOTTOM)
	return _sweep(a, b) - _guide_half()


## Walk a guide's centreline and return the closest approach to the sling triangle.
func _sweep(a: Vector2, b: Vector2) -> float:
	var closest := INF
	var steps := 400
	var tri := _tri()
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		for j in range(3):
			closest = minf(closest, _point_to_seg(p, tri[j], tri[(j + 1) % 3]))
	return closest


func _dist_to_bar(p: Vector2) -> float:
	return _point_to_seg(p, Vector2(T.OUTLANE_X, T.OUTLANE_BOTTOM), T.INLANE_END)


func _point_to_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var u := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * u)
