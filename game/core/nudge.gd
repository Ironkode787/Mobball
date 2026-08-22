class_name NudgeController
extends Node
## Leaning on the cabinet (docs/01 §5). A lean is two things at once: a table-space impulse
## on the ball, and a spring-damped visual kick of the cabinet. It also feeds the Inspector's
## suspicion — TILT kills the flippers until the guy is pinched.
##
## The visual kick is applied to `shake_target` (the camera rig) rather than to the table's
## own transform: shoving live StaticBody2D/AnimatableBody2D geometry sideways mid-tick
## launches a cradled ball, and the on-screen result is identical.

signal shake_changed(offset: Vector2)

const DIRS := {
	&"left": Vector2(1.0, -Feel.NUDGE_UP_BIAS),
	&"right": Vector2(-1.0, -Feel.NUDGE_UP_BIAS),
	&"up": Vector2(0.0, -1.0),
}

var meter := TiltMeter.new()
var shake_target: Node2D = null
var enabled: bool = true

var _ball: Ball = null
var _offset: Vector2 = Vector2.ZERO
var _offset_vel: Vector2 = Vector2.ZERO
var _base: Vector2 = Vector2.ZERO
var _base_captured: bool = false
var _cooldown: float = 0.0


func set_ball(b: Ball) -> void:
	_ball = b


func tilted() -> bool:
	return meter.tilted


func warnings() -> int:
	return meter.warnings


## Lean the cabinet. `dir_name` is &"left" / &"right" / &"up". Returns true if it registered.
func nudge(dir_name: StringName) -> bool:
	if not enabled or _cooldown > 0.0:
		return false
	if not DIRS.has(dir_name):
		return false
	_cooldown = Feel.NUDGE_COOLDOWN
	var dir: Vector2 = (DIRS[dir_name] as Vector2).normalized()

	# Multiball: a lean shoves the whole cabinet, so every live ball feels it. With an
	# empty registry (M0 alley scenes) the single compat ref still works.
	var live := Balls.live()
	if live.is_empty():
		if _ball != null and is_instance_valid(_ball):
			_ball.kick(dir * Feel.NUDGE_IMPULSE)
	else:
		for b in live:
			b.kick(dir * Feel.NUDGE_IMPULSE)
	# camera moves *with* the impulse so the cabinet appears to jump the other way
	_offset_vel += dir * Feel.NUDGE_VISUAL_OFFSET * sqrt(Feel.NUDGE_SPRING)
	AudioDirector.play(&"nudge_thump")
	Events.nudged.emit(dir)

	match meter.lean():
		&"warning":
			AudioDirector.play(&"tilt_warning")
			Events.tilt_warning.emit(meter.warnings, meter.max_warnings)
		&"tilt":
			AudioDirector.play(&"tilt")
			Events.tilted.emit()
	return true


## Called by the table when the ball drains: the Inspector loses interest in a pinched guy.
func clear_tilt() -> void:
	if meter.tilted or meter.warnings > 0:
		meter.reset()
		Events.tilt_cleared.emit()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if meter.advance(delta):
		Events.tilt_warning.emit(meter.warnings, meter.max_warnings)


func _process(delta: float) -> void:
	if _offset == Vector2.ZERO and _offset_vel == Vector2.ZERO:
		return
	var accel := -_offset * Feel.NUDGE_SPRING - _offset_vel * Feel.NUDGE_DAMP
	_offset_vel += accel * delta
	_offset += _offset_vel * delta
	_offset = _offset.limit_length(Feel.NUDGE_VISUAL_OFFSET)
	if _offset.length() < 0.05 and _offset_vel.length() < 1.0:
		_offset = Vector2.ZERO
		_offset_vel = Vector2.ZERO
	_apply_shake()
	shake_changed.emit(_offset)


## Camera2D has a dedicated `offset` for exactly this; anything else gets moved bodily
## (with its authored position remembered so repeated leans don't drift it).
func _apply_shake() -> void:
	if shake_target == null or not is_instance_valid(shake_target):
		return
	if shake_target is Camera2D:
		(shake_target as Camera2D).offset = _offset
		return
	if not _base_captured:
		_base = shake_target.position
		_base_captured = true
	shake_target.position = _base + _offset
