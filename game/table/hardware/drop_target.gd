class_name DropTarget
extends StaticBody2D
## One drop target out of a storefront bank. Body is a capsule (rounded ends, no sharp
## internal corner for a fast ball to catch on) with a thin sensor band laid over the face
## it is meant to be hit from; touching the band drops it, which takes the body out of the
## world so the ball keeps going.
##
## Banks are raked a few degrees off square on purpose — a flat ledge across the playfield
## is somewhere a ball rolling down from above sits down and stops.

signal dropped(target: DropTarget)
signal raised(target: DropTarget)

@export var id: StringName = &"drop_target"

var down: bool = false
var length: float = 44.0
var thickness: float = 20.0
var facing: Vector2 = Vector2.DOWN

var _present: bool = true
var _face: Area2D = null
var _pulse: float = 0.0


func configure(p_id: StringName, center: Vector2, p_facing: Vector2, p_length: float) -> void:
	id = p_id
	position = center
	facing = p_facing.normalized()
	length = p_length
	rotation = facing.angle() - PI * 0.5


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.22)

	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = thickness * 0.5
	cap.height = length + thickness
	shape.shape = cap
	shape.rotation = PI * 0.5
	shape.name = "Body"
	add_child(shape)

	_face = Area2D.new()
	_face.name = "Face"
	_face.collision_layer = Feel.LAYER_ZONES
	_face.collision_mask = Feel.LAYER_BALL
	_face.monitorable = false
	var fs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, Feel.BALL_RADIUS * 0.8)
	fs.shape = rect
	fs.position = Vector2(0.0, thickness * 0.5 + Feel.BALL_RADIUS * 0.4)
	_face.add_child(fs)
	add_child(_face)
	_face.body_entered.connect(_on_face_entered)
	_apply_collision()


func _on_face_entered(body: Node2D) -> void:
	if not (body is Ball) or down or not _present:
		return
	drop(body as Ball)


func drop(ball: Ball = null) -> void:
	if down:
		return
	down = true
	_pulse = 1.0
	_apply_collision()
	queue_redraw()
	AudioDirector.play(&"drop_clack")
	TableScore.hit(id, ball)
	dropped.emit(self)


func raise() -> void:
	if not down:
		return
	down = false
	_apply_collision()
	queue_redraw()
	raised.emit(self)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


## Presentation-only state. The body remains the same capsule and the gameplay drop/raise
## contract stays owned by this node; this read is consumed only at the draw edge.
func _visual_state_id() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if down:
		return TableVisualState.VisualState.COMPLETED
	if _pulse > 0.0:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.IDLE


func visual_state() -> Dictionary:
	return TableVisualState.state_token(_visual_state_id(), {
		&"down": down, &"pulse": _pulse > 0.0,
	})


func visual_token() -> Dictionary:
	return visual_state()


func _material_fill(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _hatch(rect: Rect2, color: Color, spacing: float = 12.0) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += spacing


func _reduced_flash() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_flash


func _apply_collision() -> void:
	var solid := _present and not down
	collision_layer = Feel.LAYER_HARDWARE if solid else 0
	if _face != null:
		_face.collision_layer = Feel.LAYER_ZONES if solid else 0
		_face.collision_mask = Feel.LAYER_BALL if solid else 0


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 4.0, 0.0)
		queue_redraw()


func _draw() -> void:
	var half := length * 0.5
	var token := visual_token()
	var state := StringName(token["state"])
	var ink := _material_fill(&"ink_glass", Feel.COL_INK)
	var brass := _material_fill(&"brass", Feel.COL_BRASS)
	var paper := _material_fill(&"newsprint", Feel.COL_NEWSPRINT)
	var pulse_strength := _pulse * (0.25 if _reduced_flash() else 1.0)
	var body := brass
	if state == &"idle":
		body = brass.darkened(0.34)
	elif state == &"active":
		body = brass.lerp(paper, 0.16 + pulse_strength * 0.26)
	elif state == &"completed":
		body = paper.darkened(0.16)
	elif state == &"disabled":
		body = ink.lightened(0.18)
	var outline := ink.lightened(0.14)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), outline, thickness + 8.0)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), body, thickness)
	draw_line(Vector2(-half, -thickness * 0.25), Vector2(half, -thickness * 0.25),
			paper.darkened(0.28) if state != &"disabled" else outline, 3.0)
	# Every state has a shape cue: down bar, strike pulse, or a quiet invitation notch.
	if state == &"completed":
		draw_line(Vector2(-half * 0.58, -3.0), Vector2(half * 0.58, -3.0), paper, 4.0)
	elif state == &"active":
		draw_arc(Vector2.ZERO, thickness * 0.96, 0.0, TAU, 20, paper, 3.0)
	elif state == &"disabled":
		_hatch(Rect2(Vector2(-half, -thickness * 0.5), Vector2(length, thickness)),
			Color(paper.r, paper.g, paper.b, 0.32), 13.0)
	else:
		draw_line(Vector2(-half * 0.52, thickness * 0.48),
			Vector2(-half * 0.22, thickness * 0.48), brass.lightened(0.22), 3.0)
