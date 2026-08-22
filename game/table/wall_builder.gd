class_name WallBuilder
extends RefCounted
## Builds table geometry as *rounded polylines*: every wall is a chain of overlapping
## capsules sharing endpoints, so the collision surface has no seams, no thin segments and
## no sharp internal edges for a fast ball to catch on. Thickness is a real dimension —
## nothing here is ever thinner than a ball can cross in one 120 Hz tick.
##
## It also keeps the chains around so the segment's `_draw()` renders exactly what the
## physics sees; geometry and art can never drift apart.

const MIN_THICKNESS := 12.0

var body: StaticBody2D
var chains: Array[Dictionary] = []      ## { points: PackedVector2Array, thickness: float }


func _init(p_body: StaticBody2D) -> void:
	body = p_body


## Add one rounded polyline. `points` are in the body's local space.
func chain(points: PackedVector2Array, thickness: float) -> void:
	if points.size() < 2:
		return
	var t := maxf(thickness, MIN_THICKNESS)
	var r := t * 0.5
	for i in range(points.size() - 1):
		_capsule(points[i], points[i + 1], r)
	chains.append({"points": points, "thickness": t})


func bar(from: Vector2, to: Vector2, thickness: float) -> void:
	chain(PackedVector2Array([from, to]), thickness)


## Circular arc sampled into a rounded polyline. Angles in radians, measured with +Y down.
func arc(center: Vector2, radius: float, from_angle: float, to_angle: float,
		segments: int, thickness: float) -> void:
	var pts := PackedVector2Array()
	var steps := maxi(segments, 2)
	for i in range(steps + 1):
		var a := lerpf(from_angle, to_angle, float(i) / float(steps))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	chain(pts, thickness)


func _capsule(a: Vector2, b: Vector2, radius: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.0001:
		return
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = radius
	cap.height = len + radius * 2.0
	shape.shape = cap
	shape.position = (a + b) * 0.5
	shape.rotation = d.angle() + PI * 0.5
	body.add_child(shape)


func draw_into(canvas: CanvasItem, color: Color, rim: Color) -> void:
	for c: Dictionary in chains:
		var pts: PackedVector2Array = c["points"]
		var t: float = c["thickness"]
		canvas.draw_polyline(pts, rim, t + 4.0, true)
		canvas.draw_polyline(pts, color, t, true)
