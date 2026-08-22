class_name Slingshot
extends StaticBody2D
## Kicker triangle. Solid convex body plus a thin sensor band laid over the kicker face
## (points[1] → points[2]); anything that touches the band gets thrown along the face normal.

@export var id: StringName = &"sling"
@export var value: int = Feel.SLING_VALUE

var points: PackedVector2Array = PackedVector2Array()
var face_normal: Vector2 = Vector2.UP

var _cooldown: float = 0.0
var _pulse: float = 0.0
var _band: Area2D = null
var _inside: Array[Ball] = []


## p0 is the square corner; p1 → p2 is the kicker face. Coordinates are table-space.
func configure(p_id: StringName, p0: Vector2, p1: Vector2, p2: Vector2) -> void:
	id = p_id
	var centroid := (p0 + p1 + p2) / 3.0
	position = centroid
	points = PackedVector2Array([p0 - centroid, p1 - centroid, p2 - centroid])


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, Feel.RUBBER_BOUNCE)
	if points.size() != 3:
		return

	var body := CollisionShape2D.new()
	var tri := ConvexPolygonShape2D.new()
	tri.set_point_cloud(points)
	body.shape = tri
	body.name = "Body"
	add_child(body)

	var a := points[1]
	var b := points[2]
	var edge := b - a
	var n := Vector2(-edge.y, edge.x).normalized()
	if n.dot((a + b) * 0.5) < 0.0:         # local origin is the centroid: point away from it
		n = -n
	face_normal = n

	_band = Area2D.new()
	_band.name = "Face"
	_band.collision_layer = Feel.LAYER_ZONES
	_band.collision_mask = Feel.LAYER_BALL
	_band.monitorable = false
	var bs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(edge.length(), Feel.BALL_RADIUS * 1.5)
	bs.shape = rect
	bs.position = (a + b) * 0.5 + n * (Feel.BALL_RADIUS * 0.75)
	bs.rotation = edge.angle()
	_band.add_child(bs)
	add_child(_band)
	_band.body_entered.connect(_on_ball_entered)
	_band.body_exited.connect(_on_ball_exited)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 8.0, 0.0)
		queue_redraw()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	if _cooldown > 0.0:
		return
	for b in _inside:                      # nothing sleeps on a live kicker face
		if b.speed() < Feel.HARDWARE_STALL_SPEED:
			_kick(b)
			return


func _on_ball_exited(body: Node2D) -> void:
	if body is Ball:
		_inside.erase(body as Ball)


func _on_ball_entered(body: Node2D) -> void:
	if not (body is Ball):
		return
	_inside.append(body as Ball)
	if _cooldown > 0.0:
		return
	_kick(body as Ball)


func _kick(ball: Ball) -> void:
	_cooldown = Feel.SLING_COOLDOWN
	var dir := (face_normal.rotated(global_rotation)).normalized()
	ball.kick(dir * Feel.SLING_IMPULSE)
	_pulse = 1.0
	queue_redraw()
	AudioDirector.play(&"sling_hit")
	Events.switch_hit.emit(id, ball, Feel.SLING_IMPULSE)
	Events.scored.emit(id, value)


func _draw() -> void:
	if points.size() != 3:
		return
	draw_colored_polygon(points, Feel.COL_INK)
	var a := points[1]
	var b := points[2]
	var lit := Feel.COL_BRASS.lerp(Color(1.0, 0.95, 0.75), _pulse)
	draw_line(a, b, lit, 9.0 + _pulse * 5.0)
	draw_line(points[0], points[1], Feel.COL_BRASS.darkened(0.35), 5.0)
	draw_line(points[2], points[0], Feel.COL_BRASS.darkened(0.35), 5.0)
