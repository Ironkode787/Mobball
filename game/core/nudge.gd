class_name NudgeController
extends Node
## Leaning on the cabinet (docs/01 §5). A lean is two things at once: a table-space impulse
## on every live ball, and a spring-damped visual kick of the camera. It also feeds the
## Inspector's suspicion — TILT kills the flippers until the guy is pinched.

signal shake_changed(offset: Vector2)

## Table space: +x right, -z up the field.
const DIRS := {
	&"left": Vector3(1.0, 0.0, -Feel.NUDGE_UP_BIAS),
	&"right": Vector3(-1.0, 0.0, -Feel.NUDGE_UP_BIAS),
	&"up": Vector3(0.0, 0.0, -1.0),
}

var meter := TiltMeter.new()
var shake_target: Camera3D = null
var enabled: bool = true

var _ball: Ball = null
var _offset: Vector2 = Vector2.ZERO
var _offset_vel: Vector2 = Vector2.ZERO
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
	var dir: Vector3 = (DIRS[dir_name] as Vector3).normalized()
	var live := Balls.live()
	if live.is_empty():
		if _ball != null and is_instance_valid(_ball):
			_ball.kick(dir * Feel.NUDGE_IMPULSE)
	else:
		for b in live:
			b.kick(dir * Feel.NUDGE_IMPULSE)
	if Presentation.fx == null or not Presentation.fx.reduced_motion:
		_offset_vel += Vector2(dir.x, dir.z) * Feel.NUDGE_VISUAL_OFFSET * sqrt(Feel.NUDGE_SPRING)
	AudioDirector.play(&"nudge_thump")
	Events.nudged.emit(Vector2(dir.x, dir.z))

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
	meter.advance(delta)


func _process(delta: float) -> void:
	if Presentation.fx != null and Presentation.fx.reduced_motion:
		if _offset != Vector2.ZERO or _offset_vel != Vector2.ZERO:
			_offset = Vector2.ZERO
			_offset_vel = Vector2.ZERO
			_apply_shake()
			shake_changed.emit(_offset)
		return
	if _offset == Vector2.ZERO and _offset_vel == Vector2.ZERO:
		return
	var accel := -_offset * Feel.NUDGE_SPRING - _offset_vel * Feel.NUDGE_DAMP
	_offset_vel += accel * delta
	_offset += _offset_vel * delta
	_offset = _offset.limit_length(Feel.NUDGE_VISUAL_OFFSET)
	if _offset.length() < 0.0005 and _offset_vel.length() < 0.01:
		_offset = Vector2.ZERO
		_offset_vel = Vector2.ZERO
	_apply_shake()
	shake_changed.emit(_offset)


## Camera3D has frame offsets for exactly this, so the cabinet appears to jump without any
## body in the physics world moving.
func _apply_shake() -> void:
	if shake_target == null or not is_instance_valid(shake_target):
		return
	shake_target.h_offset = _offset.x
	shake_target.v_offset = -_offset.y
