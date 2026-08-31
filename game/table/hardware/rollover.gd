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


## The rollover has no gameplay completion flag: lit is the persistent invitation and flash is
## the short recent-hit cue. This is a draw-only read and does not alter the switch contract.
func _visual_state_id() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if _flash > 0.0:
		return TableVisualState.VisualState.ACTIVE
	if lit:
		return TableVisualState.VisualState.ARMED
	return TableVisualState.VisualState.IDLE


func visual_state() -> Dictionary:
	return TableVisualState.state_token(_visual_state_id(), {&"flash": _flash > 0.0})


func visual_token() -> Dictionary:
	return visual_state()


func _material_fill(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _draw_hatch(rect: Rect2, color: Color) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += 12.0


func _reduced_flash() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_flash


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_ZONES if _present else 0
	collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var token := visual_token()
	var state := StringName(token["state"])
	var ink := _material_fill(&"ink_glass", Feel.COL_INK)
	var brass := _material_fill(&"brass", Feel.COL_BRASS)
	var paper := _material_fill(&"newsprint", Feel.COL_NEWSPRINT)
	var flash_strength := _flash * (0.25 if _reduced_flash() else 1.0)
	var col := brass.darkened(0.62)
	if state == &"armed":
		col = brass
	elif state == &"active":
		col = brass.lerp(paper, 0.30 + flash_strength * 0.42)
	elif state == &"disabled":
		col = ink.lightened(0.18)
	# A long deco lane insert points up-table; circles made the three skill lanes look like
	# another bumper bank in screenshots.
	var insert := PackedVector2Array([
		Vector2(0.0, -RADIUS), Vector2(RADIUS * 0.72, -6.0),
		Vector2(RADIUS * 0.48, RADIUS), Vector2(-RADIUS * 0.48, RADIUS),
		Vector2(-RADIUS * 0.72, -6.0),
	])
	draw_colored_polygon(insert, Color(col.r, col.g, col.b, 0.20 if state != &"idle" else 0.06))
	draw_polyline(PackedVector2Array([
		insert[0], insert[1], insert[2], insert[3], insert[4], insert[0],
	]), col, 5.0)
	if state == &"armed" or state == &"active":
		draw_colored_polygon(PackedVector2Array([
			Vector2(0.0, -15.0), Vector2(12.0, 2.0), Vector2(5.0, 2.0),
			Vector2(5.0, 16.0), Vector2(-5.0, 16.0), Vector2(-5.0, 2.0),
			Vector2(-12.0, 2.0),
		]), col)
	elif state == &"disabled":
		_draw_hatch(Rect2(Vector2(-RADIUS * 0.65, -RADIUS * 0.32),
				Vector2(RADIUS * 1.3, RADIUS * 0.64)), Color(paper.r, paper.g, paper.b, 0.30))
	draw_line(Vector2(-RADIUS * 0.45, RADIUS * 0.52),
			Vector2(RADIUS * 0.45, RADIUS * 0.52), col, 3.0)
