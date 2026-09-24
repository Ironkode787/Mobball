class_name LaneMouth
extends Area3D
## The throat of an orbit lane (docs/19 §3.1). On a real machine the outer wall curves into the
## throat, so a ball shot in at the cross-field angle rides the curve up the lane instead of
## slamming a straight wall and losing a third of its speed. The walls here stay straight (a
## curved one would close the kickback's way up), and this is that curve for a *rising* ball:
## an arc of ball-centre radius `radius` about `center`, ending vertical against the outer wall.
## A ball whose centre reaches it glancing rides it with its speed and spin; a steep one takes
## it like a wall. A ball rising inside the arc, or coming back down the lane, never meets it.

var center: Vector2 = Vector2.ZERO
var radius: float = 0.7
## +1 when the outer wall is on the right (the curve bends toward +x going up), −1 on the left.
var outer_side: float = 1.0


func configure(p_center: Vector2, p_radius: float, p_outer_side: float) -> void:
	center = p_center
	radius = p_radius
	outer_side = p_outer_side
	name = "LaneMouthR" if p_outer_side > 0.0 else "LaneMouthL"
	collision_layer = Feel.LAYER_ZONES
	collision_mask = Feel.LAYER_BALL
	monitorable = false
	# the part of the circle that is the throat: below its centre line, on the outer side
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(radius + Feel.BALL_RADIUS * 2.0, 0.5, radius * 0.75 + Feel.BALL_RADIUS * 2.0)
	cs.shape = box
	cs.position = Layout.p3(center + Vector2(radius * 0.5 * outer_side, radius * 0.375), 0.25)
	add_child(cs)


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is Ball and not BallHold.is_held(body as Ball):
			_meet(body as Ball)


func _meet(b: Ball) -> void:
	var v3 := b.local_velocity()
	var v := Vector2(v3.x, v3.z)
	var speed := v.length()
	if v.y >= 0.0 or speed < Feel.LANE_MOUTH_MIN_SPEED:
		return
	var r := Layout.plan(b.table_position()) - center
	var d := r.length()
	if d < radius or r.x * outer_side <= 0.0 or r.y < 0.0 or r.y > radius * 0.75:
		return
	var n := r / d
	var into := v.dot(n)
	if into <= 0.0:
		return
	var tangent := Vector2(-n.y, n.x)
	if tangent.dot(v) < 0.0:
		tangent = -tangent
	var out: Vector2
	if into <= v.dot(tangent) * tan(Feel.LANE_MOUTH_GLANCE):
		out = tangent * speed
	else:
		out = v - n * into * (1.0 + Feel.WALL_BOUNCE)
	b.set_velocity(Vector3(out.x, v3.y, out.y))
	# the roll turns with the ball, or the felt would scrub the difference off as a skid
	var turn := v.angle_to(out)
	var up := (b.get_parent() as Node3D).global_transform.basis.y.normalized()
	b.angular_velocity = b.angular_velocity.rotated(up, -turn)
