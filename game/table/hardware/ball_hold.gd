class_name BallHold
extends RefCounted
## Taking a ball out of free play (a saucer, a scoop, a kicker winding up) and giving it
## back. A held ball is invisible to every collider and weightless, so nothing else on the
## table can argue with the device that has it; `is_held` is how those devices stay out of
## each other's way. Positions and velocities are table space (see Ball).

const MAX_STEER := 60.0


static func take(ball: Ball) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	ball.collision_layer = 0
	ball.collision_mask = 0
	ball.gravity_scale = 0.0
	ball.angular_velocity = Vector3.ZERO


static func give_back(ball: Ball) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	ball.collision_layer = Feel.LAYER_BALL
	ball.collision_mask = Feel.BALL_MASK
	ball.gravity_scale = 1.0


static func is_held(ball: Ball) -> bool:
	return ball != null and is_instance_valid(ball) and ball.collision_layer == 0


static func visual_state(ball: Ball = null) -> Dictionary:
	var held := is_held(ball)
	var state := TableVisualState.VisualState.ACTIVE if held else TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if held:
		mods.append(&"held")
	var token := TableVisualState.state_token(state, mods)
	token["held"] = held
	return token


## Move a held ball toward `to` this tick (critically damped: it arrives, it never orbits).
static func steer(ball: Ball, to: Vector3, delta: float) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var v := (to - ball.table_position()) / maxf(delta, 0.00001)
	ball.set_velocity(v.limit_length(MAX_STEER))


static func release(ball: Ball, at: Vector3, velocity: Vector3) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	give_back(ball)
	ball.place(at)
	ball.set_velocity(velocity)
