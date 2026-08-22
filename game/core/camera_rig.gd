class_name CameraRig
extends Camera2D
## M0 frames the whole 1080×1920 table and never moves. The M1 vertical-follow path
## (docs/01 §2 "smart vertical follow with look-ahead") is written and tested-by-inspection
## here but locked off behind `follow_enabled` so turning it on is a one-line change.

@export var follow_enabled: bool = false
@export var static_center: Vector2 = Vector2(540.0, 970.0)
@export var static_zoom: float = 0.98
@export var follow_lookahead: float = 0.22      ## seconds of velocity to lead the ball by
@export var follow_smooth: float = 6.0
@export var follow_min_y: float = 620.0
@export var follow_max_y: float = 1180.0

var target: Node2D = null


## Physics interpolation is on project-wide, so Camera2D is forced into physics-process mode
## regardless. Declaring it before the node enters the tree just stops the engine warning
## about it on every single boot.
func _init() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _ready() -> void:
	enabled = true
	make_current()
	position = static_center
	zoom = Vector2(static_zoom, static_zoom)


func set_target(t: Node2D) -> void:
	target = t


## Runs on the physics tick, not the idle frame: with interpolation on, an idle-frame write
## to `position` fights the interpolator instead of feeding it.
func _physics_process(delta: float) -> void:
	if not follow_enabled:
		return
	if target == null or not is_instance_valid(target):
		position = position.lerp(static_center, 1.0 - exp(-follow_smooth * delta))
		return
	var lead := Vector2.ZERO
	if target is RigidBody2D:
		lead = (target as RigidBody2D).linear_velocity * follow_lookahead
	var wanted := Vector2(
		static_center.x,
		clampf(target.global_position.y + lead.y, follow_min_y, follow_max_y)
	)
	position = position.lerp(wanted, 1.0 - exp(-follow_smooth * delta))
