class_name BallHold
extends RefCounted
## Taking the ball off the playfield — the one contract every Club toy uses.
##
## The Club sits above the main field, and a 2D table has no second storey: a ball riding
## the Staircase is drawn over the arch it is physically passing *above*. So a held ball is
## lifted out of the world instead of being layered around it — `collision_layer = 0` means
## no Area2D can see it (no rollovers score, no drain swallows it) and `collision_mask = 0`
## means no wall can stop it. The holder then drives it by hand.
##
## Driving is done by writing velocity, never by teleporting: `place()` resets physics
## interpolation every time it is called, and a ball moved that way 120 times a second
## stutters on screen. Steering to a target point with the velocity that reaches it in one
## tick looks identical to the solver and reads correctly to the interpolator — and, as a
## bonus, `linear_velocity` stays honest, so the camera's look-ahead still works while the
## ball is on a ramp.
##
## The restore is exact because Ball's own values are constants, not authored per instance.

const MAX_STEER := 5200.0


## Lift the ball out of the world. Idempotent.
static func take(ball: Ball) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	ball.collision_layer = 0
	ball.collision_mask = 0
	ball.gravity_scale = 0.0
	ball.angular_velocity = 0.0


## Put it back exactly as Ball._ready() left it.
static func give_back(ball: Ball) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	ball.collision_layer = Feel.LAYER_BALL
	ball.collision_mask = Feel.BALL_MASK
	ball.gravity_scale = 1.0


static func is_held(ball: Ball) -> bool:
	return ball != null and is_instance_valid(ball) and ball.collision_layer == 0


## Move a held ball to `to` over exactly one physics tick.
static func steer(ball: Ball, to: Vector2, delta: float) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	var v := (to - ball.global_position) / maxf(delta, 0.00001)
	ball.set_velocity(v.limit_length(MAX_STEER))


## Hand the ball back with a velocity of the holder's choosing.
static func release(ball: Ball, at: Vector2, velocity: Vector2) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	give_back(ball)
	ball.place(at)
	ball.set_velocity(velocity)
