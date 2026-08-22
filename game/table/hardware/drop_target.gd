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
	var r := thickness * 0.5
	if down:
		draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Feel.COL_INK.lightened(0.10), 6.0)
		return
	var lit := Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, _pulse * 0.7)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Feel.COL_INK, thickness + 6.0)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), lit, thickness)
	draw_line(Vector2(-half, r * 0.35), Vector2(half, r * 0.35),
			Feel.COL_INK.lightened(0.25), 3.0)
