class_name Kickback
extends Area2D
## "Boys on the corner" — the outlane kicker. A ball that reaches the bottom of the outlane
## gets thrown back up it instead of draining. One shot, then a long cooldown: it is a
## reprieve, not a wall.

signal fired()

@export var id: StringName = &"kickback_left"

var cooldown_seconds: float = 60.0
var impulse: float = 1950.0
var direction: Vector2 = Vector2(0.20, -1.0).normalized()

var _present: bool = true
var _cool: float = 0.0
var _flash: float = 0.0
var _size: Vector2 = Vector2(90.0, 60.0)


func configure(p_id: StringName, at: Vector2, size: Vector2, dir: Vector2) -> void:
	id = p_id
	position = at
	_size = size
	direction = dir.normalized()


func _ready() -> void:
	collision_layer = Feel.LAYER_ZONES
	collision_mask = Feel.LAYER_BALL
	monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = _size
	cs.shape = rect
	add_child(cs)
	body_entered.connect(_on_ball_entered)
	_apply_collision()


func ready_to_fire() -> bool:
	return _present and _cool <= 0.0


func cooldown_left() -> float:
	return maxf(_cool, 0.0)


func _physics_process(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(_cool - delta, 0.0)
		if _cool == 0.0:
			queue_redraw()
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()


func _on_ball_entered(body: Node2D) -> void:
	if not (body is Ball) or not ready_to_fire():
		return
	var ball := body as Ball
	_cool = cooldown_seconds
	_flash = 1.0
	ball.set_velocity(Vector2.ZERO)
	ball.kick(direction * impulse)
	AudioDirector.play(&"kickback")
	TableScore.hit(id, ball, impulse)
	fired.emit()
	queue_redraw()


## Give the player their kickback back — the flow lane calls this at ball serve.
func recharge() -> void:
	_cool = 0.0
	queue_redraw()


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_ZONES if _present else 0
	collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var charged := _cool <= 0.0
	var col := Feel.COL_BRASS if charged else Feel.COL_BRASS.darkened(0.7)
	col = col.lerp(Feel.COL_NEWSPRINT, _flash)
	var half := _size * 0.5
	draw_rect(Rect2(-half, _size), Feel.COL_INK)
	draw_rect(Rect2(-half + Vector2(5.0, 5.0), _size - Vector2(10.0, 10.0)), col)
	draw_line(Vector2(0.0, half.y * 0.5), Vector2(0.0, -half.y * 0.7), Feel.COL_INK, 5.0)
