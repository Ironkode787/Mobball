class_name Ball
extends RigidBody3D
## The steel. A real rolling sphere on Jolt with continuous collision and a hard speed clamp —
## a tunnelling ball is a dead game, so every escape hatch is closed here rather than in
## asserts. It rolls because the felt has friction; nothing fakes the spin.
##
## API convention: every vector the table hands a ball (`kick`, `set_velocity`, `place`,
## `local_velocity`) is in TABLE space — the inclined playfield frame the ball is a child of.
## The ball converts through its parent's basis so hardware never thinks about the pitch.

signal hit_wall(strength: float)

const WALL_TAP_SPEED := 7.0     ## below this a wall hit is silent — no machine-gun ticking

var top_speed: float = 0.0
var launched: bool = false
## Velocity going into the current physics step (world space): what a piece the ball just
## hit sees as the approach, since by the time the contact is reported the solver has already
## bounced `linear_velocity`. Captured in _physics_process, which runs before the step.
var _step_velocity: Vector3 = Vector3.ZERO
var _design: Dictionary = BallDesign.anonymous()
var _mesh: MeshInstance3D = null
var _skin_dirty: bool = true


func _ready() -> void:
	mass = Feel.BALL_MASS
	gravity_scale = 1.0
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = Feel.BALL_LINEAR_DAMP
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = Feel.BALL_ANGULAR_DAMP
	physics_material_override = Feel.ball_material()
	collision_layer = Feel.LAYER_BALL
	collision_mask = Feel.BALL_MASK

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = Feel.BALL_RADIUS
	shape.shape = sphere
	shape.name = "Shape"
	add_child(shape)

	var mesh := SphereMesh.new()
	mesh.radius = Feel.BALL_RADIUS
	mesh.height = Feel.BALL_RADIUS * 2.0
	mesh.radial_segments = 28
	mesh.rings = 14
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.name = "Skin"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh)
	body_entered.connect(_on_body_entered)


func _physics_process(_delta: float) -> void:
	_step_velocity = linear_velocity


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var v := state.linear_velocity
	var speed := v.length()
	if speed > Feel.BALL_MAX_SPEED:
		state.linear_velocity = v * (Feel.BALL_MAX_SPEED / speed)
		speed = Feel.BALL_MAX_SPEED
	top_speed = maxf(top_speed, speed)


func _process(_delta: float) -> void:
	if _skin_dirty and _mesh != null:
		_skin_dirty = false
		_mesh.material_override = MaterialLib.shared().ball(_design)


# ------------------------------------------------------------------ table-space API -----


func _basis() -> Basis:
	var p := get_parent() as Node3D
	return p.global_transform.basis if p != null else Basis.IDENTITY


## Velocity in table space.
func local_velocity() -> Vector3:
	return _basis().inverse() * linear_velocity


## Table-space position (the playfield is the parent; a ball is always a direct child).
func table_position() -> Vector3:
	return position


## Table-space velocity the ball approached its latest contact with.
func approach_velocity() -> Vector3:
	return _basis().inverse() * _step_velocity


func speed() -> float:
	return linear_velocity.length()


## Hard set — used by the plunger, kickers and holds, never by gameplay code that should be
## going through impulses.
func set_velocity(v_table: Vector3) -> void:
	linear_velocity = _basis() * v_table.limit_length(Feel.BALL_MAX_SPEED)


func kick(impulse_table: Vector3) -> void:
	apply_central_impulse(_basis() * impulse_table)


func place(at_table: Vector3) -> void:
	var p := get_parent() as Node3D
	var t := global_transform
	t.origin = (p.global_transform * at_table) if p != null else at_table
	global_transform = t
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Applies a guy's persistent visual identity without changing any physics state.
func apply_guy_design(guy: Dictionary) -> void:
	_design = BallDesign.for_guy(guy)
	_skin_dirty = true


func design() -> Dictionary:
	return _design.duplicate()


func _on_body_entered(body: Node) -> void:
	# hardware that reads a real contact (a slingshot's switch) hears about it here
	if body.has_method(&"on_ball_contact"):
		body.call(&"on_ball_contact", self)
	if not (body is StaticBody3D) or ((body as StaticBody3D).collision_layer & Feel.LAYER_WALLS) == 0:
		return
	var s := speed()
	hit_wall.emit(s)
	if s > WALL_TAP_SPEED:
		AudioDirector.play(&"wall_tap")
