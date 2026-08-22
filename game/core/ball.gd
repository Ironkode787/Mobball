class_name Ball
extends RigidBody2D
## The steel. RigidBody2D with cast-shape CCD and a hard speed clamp — a tunnelling ball
## is a dead game (docs/09 §2), so every escape hatch is closed here rather than in asserts.
##
## Rotation is locked on purpose: a 2D circle has no visible spin, but an unlocked circle
## *always* rolls off an inclined bat no matter the friction, which kills trapping.

signal hit_wall(strength: float)

const RIM_WIDTH := 4.0

var top_speed: float = 0.0          ## fastest this ball has been (debug HUD)
var launched: bool = false          ## has left the shooter lane under power at least once
var _draw_radius: float = Feel.BALL_RADIUS


func _ready() -> void:
	mass = Feel.BALL_MASS
	gravity_scale = 1.0
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	contact_monitor = true
	max_contacts_reported = 6
	lock_rotation = true
	can_sleep = false
	linear_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	linear_damp = Feel.BALL_LINEAR_DAMP
	angular_damp = 1.0
	physics_material_override = Feel.ball_material()
	collision_layer = Feel.LAYER_BALL
	collision_mask = Feel.BALL_MASK

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = Feel.BALL_RADIUS
	shape.shape = circle
	shape.name = "Shape"
	add_child(shape)

	body_entered.connect(_on_body_entered)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var v := state.linear_velocity
	var speed := v.length()
	if speed > Feel.BALL_MAX_SPEED:
		state.linear_velocity = v * (Feel.BALL_MAX_SPEED / speed)
		speed = Feel.BALL_MAX_SPEED
	top_speed = maxf(top_speed, speed)


func speed() -> float:
	return linear_velocity.length()


## Hard set — used by the plunger and by anti-tunnel corrections, never by gameplay code
## that should be going through impulses.
func set_velocity(v: Vector2) -> void:
	linear_velocity = v.limit_length(Feel.BALL_MAX_SPEED)


func kick(impulse: Vector2) -> void:
	apply_central_impulse(impulse)


func place(at: Vector2) -> void:
	var t := global_transform
	t.origin = at
	global_transform = t
	PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, t)
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0


func pulse() -> void:
	_draw_radius = Feel.BALL_RADIUS * 1.12
	queue_redraw()


func _process(delta: float) -> void:
	if not is_equal_approx(_draw_radius, Feel.BALL_RADIUS):
		_draw_radius = move_toward(_draw_radius, Feel.BALL_RADIUS, 90.0 * delta)
		queue_redraw()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D and (body.collision_layer & Feel.LAYER_WALLS) != 0:
		hit_wall.emit(speed())


func _draw() -> void:
	var r := _draw_radius
	draw_circle(Vector2(0.0, 2.0), r, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(Vector2.ZERO, r, Color(0.78, 0.79, 0.82))
	draw_circle(Vector2(-r * 0.28, -r * 0.3), r * 0.34, Color(0.94, 0.95, 0.97))
	draw_arc(Vector2.ZERO, r - RIM_WIDTH * 0.5, 0.0, TAU, 32, Color(0.32, 0.33, 0.36), RIM_WIDTH)
