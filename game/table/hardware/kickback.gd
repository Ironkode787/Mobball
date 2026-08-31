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


func visual_state() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if not ready_to_fire():
		return TableVisualState.VisualState.DISABLED
	if _flash > 0.02:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {
		&"cooldown": not ready_to_fire(),
		&"pulse": _flash > 0.02,
		&"flash": _flash > 0.02,
	}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var candidate := Presentation.city.material_for(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


func _draw_hatch(rect: Rect2, color: Color) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += 14.0


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	if mark == "invitation_pin":
		draw_circle(center, radius * 0.72, color)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-radius * 0.36, radius * 0.25),
			center + Vector2(radius * 0.36, radius * 0.25),
			center + Vector2(0.0, radius * 1.1),
		]), color)
	elif mark == "contact_pulse":
		draw_arc(center, radius, 0.0, TAU, 20, color, 4.0)
		draw_circle(center, radius * 0.25, color)
	elif mark == "cooldown_clock":
		draw_arc(center, radius, -PI * 0.5, PI, 16, color, 3.0)
		draw_line(center, center + Vector2(0.0, -radius * 0.5), color, 2.0)
		draw_line(center, center + Vector2(radius * 0.34, radius * 0.2), color, 2.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)
	if String(token["pattern"]) == "cooldown_dash" or String(token["pattern"]) == "offline_hatch":
		for i in range(3):
			var y := center.y - radius * 0.35 + float(i) * radius * 0.35
			draw_line(Vector2(center.x - radius * 0.42, y), Vector2(center.x + radius * 0.42, y), color, 2.0)


func _draw() -> void:
	var token := visual_token()
	var state := String(token["state"])
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var state_col := brass if state == "armed" else paper
	if state == "active":
		state_col = paper
	if state == "disabled":
		state_col = paper.darkened(0.36)
	var charged := ready_to_fire()
	var col := brass if charged else brass.darkened(0.72)
	col = col.lerp(paper, _flash * 0.85)
	var half := _size * 0.5
	var plate := Rect2(-half, _size)
	draw_rect(Rect2(plate.position + Vector2(6.0, 8.0), plate.size), Color(ink.r, ink.g, ink.b, 0.52))
	draw_rect(plate, ink.darkened(0.28))
	draw_rect(plate, state_col.darkened(0.30), false, 5.0)
	draw_rect(Rect2(-half + Vector2(7.0, 7.0), _size - Vector2(14.0, 14.0)), col)
	if not charged:
		_draw_hatch(Rect2(-half + Vector2(7.0, 7.0), _size - Vector2(14.0, 14.0)),
				Color(paper.r, paper.g, paper.b, 0.26))
	var dir := direction.normalized()
	var start := -dir * minf(half.length() * 0.30, 20.0)
	var tip := dir * minf(half.length() * 0.66, 34.0)
	draw_line(start, tip, ink, 5.0)
	draw_line(tip, tip - dir.rotated(0.52) * 13.0, ink, 5.0)
	draw_line(tip, tip - dir.rotated(-0.52) * 13.0, ink, 5.0)
	var font := Presentation.theme.font_for(&"annotation")
	if font != null:
		draw_string(font, Vector2(-half.x, half.y - 8.0), "KICKBACK",
				HORIZONTAL_ALIGNMENT_CENTER, _size.x, 13, state_col)
	_draw_state_cue(Vector2(half.x - 15.0, -half.y + 15.0), 10.0, token, state_col)
