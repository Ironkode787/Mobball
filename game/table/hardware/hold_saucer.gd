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


func _draw() -> void:
	var lit := Feel.COL_BRASS.darkened(0.55).lerp(Feel.COL_NEWSPRINT, _glow * 0.7)
	draw_circle(Vector2.ZERO, radius, Feel.COL_INK.darkened(0.4))
	draw_arc(Vector2.ZERO, radius - 3.0, 0.0, TAU, 28, lit, 5.0)
	if steps.is_empty():
		draw_line(Vector2(-radius * 0.4, 0.0), Vector2(radius * 0.4, 0.0), lit, 4.0)
		return
	# the multiplier ladder: one pip per rung, filled up to where the hold has got to
	for i in range(steps.size()):
		var a := -PI * 0.5 + float(i) * TAU / float(steps.size())
		var p := Vector2(cos(a), sin(a)) * (radius * 0.55)
		var on := _held and i <= _step
		draw_circle(p, 7.0, lit if on else Feel.COL_INK.lightened(0.25))
	if _held:
		draw_arc(Vector2.ZERO, radius * 0.24, 0.0, TAU, 16,
				Feel.COL_NEWSPRINT.darkened(0.1), 4.0)
