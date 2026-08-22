class_name CameraRig
extends Camera2D
## The camera. M0/M1 framed the whole 1080×1920 table and never moved, because the whole
## table fitted on the screen. M2 builds the Club on top of it and the playfield becomes
## ~2.8 screens tall, so the vertical follow (docs/01 §2 "smart vertical follow with
## look-ahead") turns on here.
##
## Three rules, in priority order:
##
##   1. **Never show void.** The clamp comes from the live table's `bounds()`, re-read every
##      tick, so the camera's range grows the moment the deck is bought and not before.
##   2. **Never lose the flippers while the ball is downstairs.** The main field fits on
##      screen whole, so while the ball is in it the camera simply parks at the bottom of its
##      range. It only starts to climb as the ball rises out of the top of that frame, and it
##      is fully free by the time the ball is above the arch. A player looking at their bats
##      never has them slide off the bottom of the screen.
##   3. **Lead the ball.** A fraction of a second of velocity, capped, so a shot up the
##      Staircase opens the deck up ahead of the ball instead of chasing it.
##
## The HUD is a CanvasLayer and is not affected by any of this.

@export var follow_enabled: bool = true
@export var static_center: Vector2 = Vector2(540.0, 970.0)
@export var static_zoom: float = 0.98
@export var follow_lookahead: float = 0.16      ## seconds of velocity to lead the ball by
@export var follow_smooth: float = 7.5
## Coming home is chased harder than going up. A ball on its way down is about to need the
## flippers, and the frame has to be there before it arrives; a ball on its way up is a
## reveal, and a reveal wants easing.
@export var follow_smooth_down: float = 13.0
## Fallback clamp, used only when no table can be found to read `bounds()` from.
@export var follow_min_y: float = 620.0
@export var follow_max_y: float = 1180.0
## Derive the clamp from the hosted table instead of the two exports above.
@export var auto_bounds: bool = true

## A whole shot's worth of lead would swing the frame around; a third of a screen is plenty.
const LOOKAHEAD_MAX := 300.0
## Where the camera starts to unlock, as a fraction of the parked frame's height measured
## down from its top edge: the ball has to be well inside the top of the frame before the
## view moves at all, and clear of it before the view is free.
const UNLOCK_FROM := 0.28
const UNLOCK_TO := 0.02

var target: Node2D = null

var _table: Node = null
var _bounds: Rect2 = Rect2()


## Physics interpolation is on project-wide, so Camera2D is forced into physics-process mode
## regardless. Declaring it before the node enters the tree just stops the engine warning
## about it on every single boot.
func _init() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS


func _ready() -> void:
	enabled = true
	make_current()
	zoom = Vector2(static_zoom, static_zoom)
	_find_table()
	_read_bounds()
	position = Vector2(static_center.x, clampf(static_center.y, min_center_y(), max_center_y()))


func set_target(t: Node2D) -> void:
	target = t


## What the camera can see right now, in table space. Sims assert against this.
func view_rect() -> Rect2:
	var size := get_viewport_rect().size / maxf(static_zoom, 0.0001)
	return Rect2(position - size * 0.5, size)


func view_size() -> Vector2:
	return get_viewport_rect().size / maxf(static_zoom, 0.0001)


## Highest the camera may look — any higher and the frame runs off the top of the table.
func min_center_y() -> float:
	if not auto_bounds or _bounds.size.y <= 0.0:
		return follow_min_y
	return _bounds.position.y + view_size().y * 0.5


func max_center_y() -> float:
	if not auto_bounds or _bounds.size.y <= 0.0:
		return follow_max_y
	return _bounds.end.y - view_size().y * 0.5


## The table this rig is framing. Found once by shape rather than by name, so any segment
## that implements the TableSegment contract works.
func _find_table() -> void:
	var host := get_parent()
	if host == null:
		return
	for child in host.get_children():
		if child != self and child.has_method(&"bounds") and child.has_method(&"spawn_point"):
			_table = child
			return


func _read_bounds() -> void:
	if _table == null or not is_instance_valid(_table):
		_table = null
		_find_table()
	if _table == null:
		return
	var r: Variant = _table.call(&"bounds")
	if r is Rect2:
		_bounds = r


## Runs on the physics tick, not the idle frame: with interpolation on, an idle-frame write
## to `position` fights the interpolator instead of feeding it.
func _physics_process(delta: float) -> void:
	if not follow_enabled:
		return
	# Multiball: always frame the ball nearest danger (specs/ball-registry.md). With one
	# registered ball primary() IS the current target, so single-ball behavior is identical.
	if Balls.count() > 0:
		var p := Balls.primary()
		if p != null:
			target = p
	_read_bounds()
	var lo := min_center_y()
	var hi := max_center_y()
	if lo > hi:                                   # table shorter than the frame: centre it
		lo = (lo + hi) * 0.5
		hi = lo
	if target == null or not is_instance_valid(target):
		var home := clampf(static_center.y, lo, hi)
		position = position.lerp(Vector2(static_center.x, home),
				1.0 - exp(-follow_smooth * delta))
		return
	var ball_y := target.global_position.y
	var lead := 0.0
	if target is RigidBody2D:
		lead = clampf((target as RigidBody2D).linear_velocity.y * follow_lookahead,
				-LOOKAHEAD_MAX, LOOKAHEAD_MAX)
	var wanted := clampf(ball_y + lead, look_limit(ball_y, lo, hi), hi)
	var smooth := follow_smooth_down if wanted > position.y else follow_smooth
	position = position.lerp(Vector2(static_center.x, wanted), 1.0 - exp(-smooth * delta))


## Rule 2 in one number: the highest the camera is allowed to look given where the ball is.
## While the ball is inside the parked frame this is the parked position itself — the view
## cannot rise at all — and it opens up smoothly to the top of the table as the ball leaves
## the frame through the top.
func look_limit(ball_y: float, lo: float, hi: float) -> float:
	var h := view_size().y
	var parked_top := hi - h * 0.5
	var from_y := parked_top + h * UNLOCK_FROM
	var to_y := parked_top + h * UNLOCK_TO
	var t := clampf(inverse_lerp(from_y, to_y, ball_y), 0.0, 1.0)
	return lerpf(hi, lo, t)
