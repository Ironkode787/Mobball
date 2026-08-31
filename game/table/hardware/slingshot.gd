class_name Slingshot
extends StaticBody2D
## Kicker triangle. Solid convex body plus a thin sensor band laid over the kicker face
## (points[1] → points[2]); anything that touches the band gets thrown along the face normal.

@export var id: StringName = &"sling"
@export var value: int = Feel.SLING_VALUE
## Economy group these corner boys pay into (specs/ledger-data.md `value_mult` targets).
@export var group: StringName = &"slings"
## Progression-table triangles are physical dead rubber before Corner Boys are hired. M0's
## feel fixture leaves this false, so its slings retain the original all-or-nothing behavior.
@export var passive_when_inactive: bool = false

var points: PackedVector2Array = PackedVector2Array()
var face_normal: Vector2 = Vector2.UP

var _present: bool = true
var _powered: bool = true
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
	_apply_collision()


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 8.0, 0.0)
		queue_redraw()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not _powered:
		return
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
	if not _powered:
		return
	if _cooldown > 0.0:
		return
	_kick(body as Ball)


func _kick(ball: Ball) -> void:
	if not _powered:
		return
	_cooldown = Feel.SLING_COOLDOWN
	var dir := (face_normal.rotated(global_rotation)).normalized()
	ball.kick(dir * Feel.SLING_IMPULSE)
	_pulse = 1.0
	queue_redraw()
	AudioDirector.play(&"sling_hit")
	TableScore.earn(group, float(value), id, ball, Feel.SLING_IMPULSE)


## Corner Boys power the progression-table triangles. In that table's passive mode, the
## physical triangle remains as dead rubber while the face sensor and kicker stay dormant.
func set_hardware_active(active: bool) -> void:
	_powered = active
	_present = active or passive_when_inactive
	visible = _present
	_inside.clear()
	_apply_collision()
	queue_redraw()


func is_present() -> bool:
	return _present


func is_powered() -> bool:
	return _powered


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _band != null:
		_band.collision_layer = Feel.LAYER_ZONES if _present and _powered else 0
		_band.collision_mask = Feel.LAYER_BALL if _present and _powered else 0


## Presentation only: passive triangles stay idle, while a powered face is an invitation and
## a hit is active. The physical passive-body exception is intentionally represented by `idle`.
func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _pulse > 0.0:
		state = TableVisualState.VisualState.ACTIVE
		mods.append(&"pulse")
	elif _powered:
		state = TableVisualState.VisualState.ARMED
	return TableVisualState.state_token(state, mods)


func _ambient_material(role: StringName, fallback: Color) -> Color:
	if Presentation.city != null:
		var candidate := Presentation.city.material_for(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


func _reduced_flash() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_flash


func _draw() -> void:
	if not _present or points.size() != 3:
		return
	var token := visual_state()
	var ink := _ambient_material(&"ink_glass", Feel.COL_INK)
	var brass := _ambient_material(&"brass", Feel.COL_BRASS)
	var paper := _ambient_material(&"paper", Feel.COL_NEWSPRINT)
	var pulse_alpha := _pulse * (0.25 if _reduced_flash() else 1.0)
	draw_colored_polygon(points, ink)
	var a := points[1]
	var b := points[2]
	var lit := brass.darkened(0.52) if not _powered \
			else brass.lerp(paper, 0.22 + pulse_alpha * 0.62)
	var edge := brass.darkened(0.62) if not _powered else brass.darkened(0.35)
	draw_line(a, b, lit, 9.0 + _pulse * 5.0)
	draw_line(points[0], points[1], edge, 5.0)
	draw_line(points[2], points[0], edge, 5.0)
	if _pulse > 0.0:
		var mid := (a + b) * 0.5
		draw_circle(mid, Feel.BALL_RADIUS + 8.0 + pulse_alpha * 8.0,
				Color(paper, pulse_alpha * 0.18), false, 4.0)
		# Four short rays are a contact mark, not a painted extension of the face.
		for i in range(4):
			var ray := face_normal.rotated(float(i) * PI * 0.5)
			draw_line(mid + ray * (Feel.BALL_RADIUS + 12.0),
					mid + ray * (Feel.BALL_RADIUS + 24.0 + pulse_alpha * 8.0),
					Color(paper, pulse_alpha * 0.70), 3.0)
	elif _powered:
		# A face chevron reads as an invitation in grayscale; it does not imply a new route.
		var mid := (a + b) * 0.5
		var along := (b - a).normalized()
		var across := along.orthogonal()
		for offset: float in [-18.0, 0.0, 18.0]:
			var p := mid + along * offset
			draw_line(p - along * 7.0 - across * 5.0, p + across * 5.0,
					Color(paper, 0.75), 3.0)
			draw_line(p + across * 5.0, p + along * 7.0 - across * 5.0,
					Color(paper, 0.75), 3.0)

	if _powered:
		# The "Corner Boy" is a tiny coat-and-fedora silhouette sitting behind the kicker face.
		# It is paint only; the triangle remains the exact collision shape.
		var back := points[0].lerp((a + b) * 0.5, 0.34)
		var coat := Feel.COL_NEWSPRINT.darkened(0.72)
		draw_circle(back + Vector2(0.0, -16.0), 9.0, coat)
		draw_line(back + Vector2(-13.0, -24.0), back + Vector2(13.0, -24.0), coat, 5.0)
		draw_colored_polygon(PackedVector2Array([
			back + Vector2(-14.0, -6.0), back + Vector2(14.0, -6.0),
			back + Vector2(20.0, 22.0), back + Vector2(-20.0, 22.0),
		]), coat)
		# folding chair, because these guys have been waiting here all night
		draw_line(back + Vector2(-19.0, 23.0), back + Vector2(-12.0, 37.0),
				Feel.COL_BRASS.darkened(0.45), 3.0)
		draw_line(back + Vector2(19.0, 23.0), back + Vector2(12.0, 37.0),
				brass.darkened(0.45), 3.0)
