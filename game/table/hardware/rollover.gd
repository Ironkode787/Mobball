class_name Rollover
extends Area2D
## One of the three top-arch lanes (the chalk lines). A leaf switch in the floor: it never
## touches the ball, it only notices it. Which lane is lit is the flow lane's business —
## it drives the skill shot (specs/m1-hook.md Lane 1) through the table's
## `set_lit_rollover`.

signal rolled(index: int, was_lit: bool)

const COOLDOWN := 0.40
const RADIUS := 30.0

@export var id: StringName = &"rollover"

var index: int = 0
var lit: bool = false

var _present: bool = true
var _cooldown: float = 0.0
var _flash: float = 0.0


func configure(p_id: StringName, p_index: int, center: Vector2) -> void:
	id = p_id
	index = p_index
	position = center


func _ready() -> void:
	collision_layer = Feel.LAYER_ZONES
	collision_mask = Feel.LAYER_BALL
	monitorable = false
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	cs.shape = circle
	add_child(cs)
	body_entered.connect(_on_ball_entered)
	_apply_collision()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()


func _on_ball_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present or _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	_flash = 1.0
	queue_redraw()
	AudioDirector.play(&"rollover_click")
	TableScore.earn(TableScore.GROUP_ROLLOVERS, TableScore.ROLLOVER, id, body as Ball)
	rolled.emit(index, lit)


func set_lit(value: bool) -> void:
	if lit == value:
		return
	lit = value
	queue_redraw()


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_ZONES if _present else 0
	collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var col := Feel.COL_BRASS if lit else Feel.COL_BRASS.darkened(0.62)
	col = col.lerp(Feel.COL_NEWSPRINT, _flash * 0.9)
	# A long deco lane insert points up-table; circles made the three skill lanes look like
	# another bumper bank in screenshots.
	var insert := PackedVector2Array([
		Vector2(0.0, -RADIUS), Vector2(RADIUS * 0.72, -6.0),
		Vector2(RADIUS * 0.48, RADIUS), Vector2(-RADIUS * 0.48, RADIUS),
		Vector2(-RADIUS * 0.72, -6.0),
	])
	draw_colored_polygon(insert, Color(col.r, col.g, col.b, 0.16 if lit else 0.05))
	draw_polyline(PackedVector2Array([
		insert[0], insert[1], insert[2], insert[3], insert[4], insert[0],
	]), col, 4.0)
	if lit:
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -15.0), Vector2(12.0, 2.0), Vector2(5.0, 2.0),
			Vector2(5.0, 16.0), Vector2(-5.0, 16.0), Vector2(-5.0, 2.0),
			Vector2(-12.0, 2.0),
		]), col)
	draw_line(Vector2(-RADIUS * 0.45, RADIUS * 0.52),
			Vector2(RADIUS * 0.45, RADIUS * 0.52), col, 3.0)
