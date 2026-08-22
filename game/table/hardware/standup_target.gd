class_name StandupTarget
extends StaticBody2D
## A standup: a payphone on The Wire, a cop during a raid, the beat cop's donut shop. It
## never leaves the playfield — it lights instead of dropping — so the geometry a player
## learns stays put. Whether a hit pays, and how much, is the owner's business: this only
## reports the strike.

signal struck(target: StandupTarget, ball: Ball)

const COOLDOWN := 0.22

@export var id: StringName = &"standup"

var marked: bool = false            ## bank bookkeeping: already collected this round
var length: float = 76.0
var thickness: float = 18.0
var facing: Vector2 = Vector2.LEFT

var _present: bool = true
var _face: Area2D = null
var _cooldown: float = 0.0
var _pulse: float = 0.0


func configure(p_id: StringName, center: Vector2, p_facing: Vector2, p_length: float = 76.0) -> void:
	id = p_id
	position = center
	facing = p_facing.normalized()
	length = p_length
	rotation = facing.angle() - PI * 0.5


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, 0.30)

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


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 5.0, 0.0)
		queue_redraw()


func _on_face_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present or _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	_pulse = 1.0
	queue_redraw()
	struck.emit(self, body as Ball)


func set_marked(value: bool) -> void:
	if marked == value:
		return
	marked = value
	queue_redraw()


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _face != null:
		_face.collision_layer = Feel.LAYER_ZONES if _present else 0
		_face.collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var half := length * 0.5
	var face := Feel.COL_BRASS if marked else Feel.COL_BRASS.darkened(0.55)
	face = face.lerp(Feel.COL_NEWSPRINT, _pulse * 0.8)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Feel.COL_INK, thickness + 6.0)
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), face, thickness)
	if marked:
		draw_line(Vector2(-half * 0.6, 0.0), Vector2(half * 0.6, 0.0),
				Feel.COL_NEWSPRINT, 4.0)
