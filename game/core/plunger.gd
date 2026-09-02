class_name Plunger
extends Node
## "The Drop-Off". Holding the plunger winds a spring 0→1 over Feel.PLUNGER_CHARGE_TIME with
## audible ratchet detents; releasing hands the ball `power * PLUNGER_MAX_IMPULSE` straight up
## the shooter lane. Power bands are the skill shot, so the mapping stays strictly linear.

signal launched(power: float)

var power: float = 0.0
var charging: bool = false
## Table-space box the ball must rest in to be plungeable (the shooter lane).
var lane_box: AABB = AABB()
## Table-space direction the ball is fired in (up the lane).
var lane_dir: Vector3 = Vector3(0.0, 0.0, -1.0)
var enabled: bool = true

var _ball: Ball = null
var _detent: int = 0


func set_ball(b: Ball) -> void:
	_ball = b


func ball_ready() -> bool:
	if _ball == null or not is_instance_valid(_ball):
		return false
	if not lane_box.has_point(_ball.table_position()):
		return false
	return _ball.speed() <= Feel.PLUNGER_REST_SPEED


func set_pressed(pressed: bool) -> void:
	if not enabled:
		return
	if pressed and not charging:
		if not ball_ready():
			return
		charging = true
		power = 0.0
		_detent = 0
		Events.plunger_charge_changed.emit(0.0)
	elif not pressed and charging:
		release()


func release() -> void:
	if not charging:
		return
	charging = false
	var p := power
	power = 0.0
	Events.plunger_charge_changed.emit(0.0)
	launch(p)


## Fire immediately at an explicit power — used by auto-launch and by the sim scenarios.
func launch(p: float) -> void:
	if not ball_ready():
		return
	var clamped := clampf(p, 0.0, 1.0)
	if clamped <= 0.0:
		return
	_ball.set_velocity(Vector3.ZERO)
	_ball.kick(lane_dir.normalized() * (clamped * Feel.PLUNGER_MAX_IMPULSE))
	_ball.launched = true
	AudioDirector.play(&"plunger_launch")
	Events.ball_launched.emit(_ball, clamped)
	launched.emit(clamped)


func _physics_process(delta: float) -> void:
	if not charging:
		return
	if not ball_ready():
		charging = false
		power = 0.0
		Events.plunger_charge_changed.emit(0.0)
		return
	power = minf(power + delta / maxf(Feel.PLUNGER_CHARGE_TIME, 0.0001), 1.0)
	var d := int(power * float(Feel.PLUNGER_DETENTS))
	if d > _detent:
		_detent = d
		AudioDirector.play(&"plunger_pull")
	Events.plunger_charge_changed.emit(power)
