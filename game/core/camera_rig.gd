class_name CameraRig
extends Camera3D
## The player's eye: a perspective camera over the inclined playfield, framing the whole
## machine from the flippers up and easing along the table to keep the ball and the shot it
## is heading for in view. Lives under the table root so its numbers are in table space.
##
## Rules, in priority order:
##   1. The flippers never leave the bottom of the frame while the ball is downstairs.
##   2. Lead the ball a little: a shot up a ramp opens the top of the table ahead of it.
##   3. Never show void: the frame is clamped to the table's `bounds()`.

@export var follow_enabled: bool = true
## Pitch of the view from straight down, degrees. Real players see the field at ~55°; a phone
## in portrait wants it steeper so the whole width fits.
@export var pitch_deg: float = 30.0
@export var fov_deg: float = 44.0
## How much of the table length is framed at once (units): the rest scrolls.
@export var frame_length: float = 9.8
@export var follow_lookahead: float = 0.10
@export var follow_smooth: float = 6.5
@export var follow_smooth_down: float = 11.0

var target: Node3D = null
var _table: Node3D = null
var _center_z: float = 0.0
var _init_done: bool = false


func _ready() -> void:
	current = true
	fov = fov_deg
	near = 0.5
	far = 120.0
	keep_aspect = Camera3D.KEEP_HEIGHT
	_table = get_parent() as Node3D
	_center_z = max_center_z()
	_place(_center_z)
	_init_done = true


func set_target(t: Node3D) -> void:
	target = t


func bounds() -> AABB:
	if _table != null and _table.has_method(&"bounds"):
		var b: Variant = _table.call(&"bounds")
		if b is AABB:
			return b
	return AABB(Vector3(-2.6, 0.0, -5.4), Vector3(5.2, 1.0, 10.8))


## Frame centre z when parked on the flippers (the lowest the view goes).
func max_center_z() -> float:
	return bounds().end.z - frame_length * 0.5 + 0.35


func min_center_z() -> float:
	return minf(bounds().position.z + frame_length * 0.5 - 0.6, max_center_z())


func _physics_process(delta: float) -> void:
	if not follow_enabled or not _init_done:
		return
	if Balls.count() > 0:
		var p := Balls.primary()
		if p != null:
			target = p
	var lo := min_center_z()
	var hi := max_center_z()
	var wanted := hi
	if target != null and is_instance_valid(target):
		var tp := (target as Node3D).position
		var lead := 0.0
		if target is RigidBody3D:
			var v: Vector3 = (target as Ball).local_velocity() if target is Ball \
					else (target as RigidBody3D).linear_velocity
			lead = clampf(v.z * follow_lookahead, -1.5, 1.5)
		# the view only starts to climb once the ball is well up the field
		var unlock_from := hi - frame_length * 0.20
		var unlock_to := hi - frame_length * 0.55
		var t := clampf(inverse_lerp(unlock_from, unlock_to, tp.z + lead), 0.0, 1.0)
		wanted = lerpf(hi, clampf(tp.z + lead, lo, hi), t)
	var smooth := follow_smooth_down if wanted > _center_z else follow_smooth
	var reduced := Presentation.fx != null and Presentation.fx.reduced_motion
	_center_z = wanted if reduced else lerpf(_center_z, wanted, 1.0 - exp(-smooth * delta))
	_place(_center_z)


func _place(center_z: float) -> void:
	var pitch := deg_to_rad(pitch_deg)
	var half := frame_length * 0.5
	var dist := half * cos(pitch) / tan(deg_to_rad(fov_deg) * 0.5)
	var focus := Vector3(0.0, 0.0, center_z)
	position = focus + Vector3(0.0, dist * cos(pitch), dist * sin(pitch))
	look_at_from_position(position, focus, Vector3(0.0, 0.0, -1.0))
