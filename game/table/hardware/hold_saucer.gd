class_name HoldSaucer
extends Node2D
## A hole that keeps the ball for a moment and then kicks it out: the Club's High Roller
## (hold to raise the multiplier) and the back-room saucer behind the slots.
##
## It has no collision geometry at all — it is a hole, not a cup — which is what makes it
## wedge-proof: there is no rim for a ball to balance on. Capture is a distance test against
## the live ball, the hold is a timer, and the kick-out always happens.
##
## With `steps` set it is the High Roller: the multiplier climbs on a fixed cadence with an
## ascending chime per rung, and the kick-out gets hotter the longer the ball was held —
## the ball leaves the way the player's night is going.

signal captured()
## One rung of the ladder. `step` is 1-based; the last one is the auto-eject.
signal stepped(step: int)
signal ejected(steps: int)

const STEP_SOUNDS: PackedStringArray = ["chime_a", "chime_b", "chime_c"]

@export var id: StringName = &"saucer"

var radius: float = 40.0
## Plain hold time, used when `steps` is empty.
var hold_seconds: float = 0.8
## Multiplier ladder. Empty = a plain capture-and-kick saucer.
var steps: PackedFloat32Array = PackedFloat32Array()
var step_seconds: float = 0.9
var eject_dir: Vector2 = Vector2(0.0, 1.0)
var eject_speed: float = 900.0
## Extra kick per rung held — "the longer held, the hotter it leaves".
var eject_heat: float = 150.0
var cooldown_seconds: float = 0.5

var _present: bool = true
var _ball: Ball = null
var _held: bool = false
var _t: float = 0.0
var _step: int = 0
var _cool: float = 0.0
var _glow: float = 0.0


func configure(p_id: StringName, at: Vector2, p_radius: float, dir: Vector2) -> void:
	id = p_id
	position = at
	radius = p_radius
	eject_dir = dir.normalized()


func set_ball(b: Ball) -> void:
	if _held and b != _ball:
		_held = false
	_ball = b


func holds_ball() -> bool:
	return _held and _ball != null and is_instance_valid(_ball)


func step_index() -> int:
	return _step


func multiplier() -> float:
	if steps.is_empty():
		return 1.0
	return steps[clampi(_step, 0, steps.size() - 1)]


func _physics_process(delta: float) -> void:
	if not _present:
		return
	_cool = maxf(_cool - delta, 0.0)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.6, 0.0)
		queue_redraw()
	if _ball == null or not is_instance_valid(_ball):
		_held = false
		return
	if _held:
		_hold(delta)
		return
	if _cool > 0.0 or BallHold.is_held(_ball):
		return
	if _ball.global_position.distance_to(global_position) <= radius - 6.0:
		_take()


func _take() -> void:
	_held = true
	_t = 0.0
	_step = 0
	_glow = 1.0
	BallHold.take(_ball)
	AudioDirector.play(&"safe_open" if steps.is_empty() else &"chime_a")
	TableScore.hit(id, _ball)
	captured.emit()
	queue_redraw()


func _hold(delta: float) -> void:
	_t += delta
	BallHold.steer(_ball, global_position, delta)
	if steps.is_empty():
		if _t >= hold_seconds:
			_eject()
		return
	if _t < step_seconds:
		return
	_t = 0.0
	_step += 1
	_glow = 1.0
	AudioDirector.play(StringName(STEP_SOUNDS[mini(_step - 1, STEP_SOUNDS.size() - 1)]))
	stepped.emit(_step)
	queue_redraw()
	if _step >= steps.size() - 1:
		_eject()


func _eject() -> void:
	var held_steps := _step
	_held = false
	_cool = cooldown_seconds
	_glow = 1.0
	var speed := eject_speed + eject_heat * float(held_steps)
	BallHold.release(_ball, global_position, eject_dir * speed)
	AudioDirector.play(&"kickback")
	ejected.emit(held_steps)
	queue_redraw()


func set_hardware_active(active: bool) -> void:
	if _present == active:
		return
	_present = active
	visible = active
	if not active and _held:
		_held = false
		BallHold.release(_ball, global_position, eject_dir * eject_speed)


func is_hardware_active() -> bool:
	return _present


func visual_state() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if _cool > 0.0:
		return TableVisualState.VisualState.DISABLED
	if _held:
		return TableVisualState.VisualState.ACTIVE
	if _glow > 0.02:
		return TableVisualState.VisualState.COMPLETED
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {
		&"cooldown": _cool > 0.0,
		&"held": _held,
		&"marked": _step > 0,
		&"pulse": _glow > 0.02,
	}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var candidate := Presentation.city.material_for(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


func _draw_hatch(center: Vector2, radius: float, color: Color) -> void:
	for i in range(5):
		var y := -radius * 0.64 + float(i) * radius * 0.32
		draw_line(center + Vector2(-radius * 0.62, y), center + Vector2(radius * 0.62, y), color, 2.0)


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	if mark == "held_ring":
		draw_arc(center, radius, 0.0, TAU, 20, color, 4.0)
		draw_circle(center, radius * 0.24, color)
	elif mark == "cooldown_clock":
		draw_arc(center, radius, -PI * 0.5, PI, 18, color, 3.0)
		draw_line(center, center + Vector2(0.0, -radius * 0.52), color, 2.0)
		draw_line(center, center + Vector2(radius * 0.34, radius * 0.2), color, 2.0)
	elif mark == "marked_stamp":
		draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)), color, false, 3.0)
		draw_line(center + Vector2(-radius * 0.5, 0.0), center + Vector2(-radius * 0.08, radius * 0.42), color, 3.0)
		draw_line(center + Vector2(-radius * 0.08, radius * 0.42), center + Vector2(radius * 0.55, -radius * 0.48), color, 3.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)
	if String(token["pattern"]) == "cooldown_dash" or String(token["pattern"]) == "offline_hatch":
		_draw_hatch(center, radius, color)


func _draw() -> void:
	var token := visual_token()
	var state := String(token["state"])
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var neon := _ambient(&"earned_neon", Feel.COL_NEON_ROSE)
	var lit := brass.darkened(0.48).lerp(paper, _glow * 0.72)
	var state_col := brass if state == "armed" else paper
	if state == "active":
		state_col = neon
	if state == "disabled":
		state_col = paper.darkened(0.36)
	draw_circle(Vector2.ZERO, radius + 9.0, Color(ink.r, ink.g, ink.b, 0.60))
	draw_circle(Vector2.ZERO, radius, ink.darkened(0.36))
	draw_circle(Vector2.ZERO, radius * 0.68, Color(ink.r, ink.g, ink.b, 0.75))
	draw_arc(Vector2.ZERO, radius - 3.0, 0.0, TAU, 32, lit, 6.0)
	draw_arc(Vector2.ZERO, radius * 0.70, 0.0, TAU, 28, brass.darkened(0.30), 2.0)
	if steps.is_empty():
		draw_line(Vector2(-radius * 0.4, 0.0), Vector2(radius * 0.4, 0.0), lit, 4.0)
		draw_line(Vector2(0.0, -radius * 0.4), Vector2(0.0, radius * 0.4), lit, 4.0)
	else:
		# The multiplier ladder is a fixed visual track; the live step is a fill, not a color-only cue.
		for i in range(steps.size()):
			var a := -PI * 0.5 + float(i) * TAU / float(steps.size())
			var p := Vector2(cos(a), sin(a)) * (radius * 0.55)
			var on := _held and i <= _step
			var pip := lit if on else brass.darkened(0.55)
			draw_circle(p, 8.0, pip)
			draw_arc(p, 8.0, 0.0, TAU, 12, paper.darkened(0.18), 2.0)
			if on:
				draw_line(p + Vector2(-4.0, 0.0), p + Vector2(4.0, 0.0), ink, 2.0)
		var value := multiplier()
		var font := Presentation.theme.font_for(&"annotation")
		if font != null:
			draw_string(font, Vector2(-radius, 5.0), "x%.1f" % value,
					HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 16, paper)
	# The arrow is a fixed eject affordance and does not imply a new collision route.
	var arrow := eject_dir.normalized() * (radius + 14.0)
	draw_line(eject_dir.normalized() * (radius - 2.0), arrow, state_col, 3.0)
	draw_line(arrow, arrow - eject_dir.normalized().rotated(0.52) * 11.0, state_col, 3.0)
	draw_line(arrow, arrow - eject_dir.normalized().rotated(-0.52) * 11.0, state_col, 3.0)
	if state == "disabled":
		_draw_hatch(Vector2.ZERO, radius * 0.66, Color(paper.r, paper.g, paper.b, 0.20))
	_draw_state_cue(Vector2(0.0, -radius - 14.0), 11.0, token, state_col)
