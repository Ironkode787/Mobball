class_name CameraRig
extends Camera3D
## The player's eye: a perspective camera over the inclined playfield, framing the whole
## machine from the flippers up and easing along the table to keep the ball and the shot it
## is heading for in view. Lives under the table root so its numbers are in table space.
##
## Rules, in priority order:
##   1. The whole width of the cabinet is on screen, whatever the phone's aspect: the frame
##      is fitted to the table's width at its near edge, where perspective is widest.
##   2. The flippers never leave the bottom of the frame while the ball is downstairs.
##   3. As much of the length as fits: the view keeps `pitch_deg` when the screen is tall
##      enough to show the whole table, flattens toward `pitch_min_deg` when it is not, and
##      only then scrolls, leading the ball a little so a ramp shot opens the top of the table.
##   4. Never show void: the frame is clamped to the table's `bounds()`.

@export var follow_enabled: bool = true
## Preferred pitch of the view from straight down, degrees. Real players see the field at
## ~55°; a phone in portrait wants it steeper so the whole width fits.
@export var pitch_deg: float = 30.0
## The flattest the view goes to fit the table's length before it falls back to scrolling.
@export var pitch_min_deg: float = 16.0
## Horizontal field of view, degrees: the width is what a portrait screen is short of, so
## the frame is defined by it and the vertical extent follows the screen's aspect.
@export var fov_deg: float = 26.0
## 0 frames the table's width (the game). A positive value frames a fixed length of field
## instead, for screenshots and probes.
@export var frame_length: float = 0.0
## Field shown beyond the cabinet's side walls and above the arch, units.
@export var side_margin: float = 0.12
@export var top_margin: float = 0.3
## The bottom edge of the frame sits this far inside the table's bounds (on the apron).
@export var bottom_inset: float = 0.1
## Height of the cabinet's side rails at the near corners: they lean toward the camera, so
## the width is fitted at their top, not at the felt.
@export var rail_height: float = 0.9
@export var follow_lookahead: float = 0.10
@export var follow_smooth: float = 6.5
@export var follow_smooth_down: float = 11.0

var target: Node3D = null
var _table: Node3D = null
var _center_z: float = 0.0
var _init_done: bool = false
var _aspect: float = 0.0
var _pitch: float = 0.0
var _height: float = 0.0
var _half_fov_v: float = 0.0
var _visible_length: float = 0.0
var _center_hi: float = 0.0
var _center_lo: float = 0.0


func _ready() -> void:
	current = true
	near = 0.5
	far = 120.0
	_table = get_parent() as Node3D
	_refit(true)
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
	_refit()
	return _center_hi


func min_center_z() -> float:
	_refit()
	return _center_lo


## Length of field on screen when parked, units.
func visible_length() -> float:
	_refit()
	return _visible_length


func _physics_process(delta: float) -> void:
	if not follow_enabled or not _init_done:
		return
	_refit()
	if Balls.count() > 0:
		var p := Balls.primary()
		if p != null:
			target = p
	var lo := _center_lo
	var hi := _center_hi
	var wanted := hi
	if target != null and is_instance_valid(target):
		var tp := (target as Node3D).position
		var lead := 0.0
		if target is RigidBody3D:
			var v: Vector3 = (target as Ball).local_velocity() if target is Ball \
					else (target as RigidBody3D).linear_velocity
			lead = clampf(v.z * follow_lookahead, -1.5, 1.5)
		# the view only starts to climb once the ball is well up the field
		var unlock_from := hi - _visible_length * 0.20
		var unlock_to := hi - _visible_length * 0.55
		var t := clampf(inverse_lerp(unlock_from, unlock_to, tp.z + lead), 0.0, 1.0)
		wanted = lerpf(hi, clampf(tp.z + lead, lo, hi), t)
	var smooth := follow_smooth_down if wanted > _center_z else follow_smooth
	var reduced := Presentation.fx != null and Presentation.fx.reduced_motion
	_center_z = wanted if reduced else lerpf(_center_z, wanted, 1.0 - exp(-smooth * delta))
	_place(_center_z)


func _screen_aspect() -> float:
	var vp := get_viewport()
	if vp == null:
		return 9.0 / 16.0
	var s := vp.get_visible_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return 9.0 / 16.0
	return s.x / s.y


## Recompute the pose for the current screen aspect. Cheap when nothing changed.
func _refit(force: bool = false) -> void:
	var aspect := _screen_aspect()
	if not force and is_equal_approx(aspect, _aspect):
		return
	_aspect = aspect
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = fov_deg
	var tan_h := tan(deg_to_rad(fov_deg) * 0.5)
	_half_fov_v = atan(tan_h / aspect)
	var b := bounds()
	var bottom_z := b.end.z - bottom_inset
	var top_goal := b.position.z - top_margin
	if frame_length > 0.0:
		_pitch = deg_to_rad(pitch_deg)
		var dist := frame_length * 0.5 * cos(_pitch) / tan(_half_fov_v)
		_height = dist * cos(_pitch)
		_visible_length = frame_length
		_center_hi = b.end.z - frame_length * 0.5 + 0.35
		_center_lo = minf(b.position.z + frame_length * 0.5 - 0.6, _center_hi)
		return
	var half_w := b.size.x * 0.5 + side_margin
	var p_hi := deg_to_rad(pitch_deg)
	var p_lo := deg_to_rad(minf(pitch_min_deg, pitch_deg))
	_pitch = p_hi
	if _parked_top_z(p_hi, half_w, tan_h, bottom_z) > top_goal \
			and _parked_top_z(p_lo, half_w, tan_h, bottom_z) <= top_goal:
		# the table's length does not fit at the preferred pitch: flatten just enough
		var a := p_lo
		var c := p_hi
		for _i in range(24):
			var mid := (a + c) * 0.5
			if _parked_top_z(mid, half_w, tan_h, bottom_z) <= top_goal:
				a = mid
			else:
				c = mid
		_pitch = a
	_height = _height_for(_pitch, half_w, tan_h)
	var cam_z := _parked_cam_z(_pitch, _height, bottom_z)
	var top_z := _top_z(_pitch, _height, cam_z)
	_visible_length = bottom_z - top_z
	_center_hi = cam_z - _height * tan(_pitch)
	var cam_z_top := top_goal + _height * tan(_top_ray(_pitch))
	_center_lo = minf(cam_z_top - _height * tan(_pitch), _center_hi)


## Camera height at which the frame's bottom row spans the cabinet's width at rail height.
## The bottom ray leaves the camera `_half_fov_v` behind the view axis; a field point on it
## at height h is (H - h) / cos(a_b) away and (H - h) cos(fv/2) / cos(a_b) deep.
func _height_for(p: float, half_w: float, tan_h: float) -> float:
	var a_b := p - _half_fov_v
	return rail_height + half_w * cos(a_b) / (cos(_half_fov_v) * tan_h)


func _parked_cam_z(p: float, h: float, bottom_z: float) -> float:
	return bottom_z + h * tan(p - _half_fov_v)


func _top_ray(p: float) -> float:
	return minf(p + _half_fov_v, deg_to_rad(80.0))


func _top_z(p: float, h: float, cam_z: float) -> float:
	return cam_z - h * tan(_top_ray(p))


func _parked_top_z(p: float, half_w: float, tan_h: float, bottom_z: float) -> float:
	var h := _height_for(p, half_w, tan_h)
	return _top_z(p, h, _parked_cam_z(p, h, bottom_z))


func _place(center_z: float) -> void:
	var focus := Vector3(0.0, 0.0, center_z)
	position = focus + Vector3(0.0, _height, _height * tan(_pitch))
	look_at_from_position(position, focus, Vector3(0.0, 0.0, -1.0))
