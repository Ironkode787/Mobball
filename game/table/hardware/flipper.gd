class_name Flipper
extends AnimatableBody2D
## A solenoid bat. Kinematic body swept along an authored curve (docs/09 §2: curves, not
## motors) so the feel is designed rather than emergent, with `sync_to_physics` doing the
## impulse transfer through the solver.
##
## Local geometry always points along +X; the right bat is the same shape turned around
## (see Feel.flipper_rest_rotation). "Striking side" is local -Y on the left, +Y on the right.

enum State { REST, RISING, HELD, FALLING }

@export var side: StringName = &"left"
## Bat size against the Feel numbers. 1.0 is the main table's bat, which is what the feel
## sims measure; the Club's mini pair is 0.8. Scaled here rather than on the node's transform
## on purpose — a scaled Node2D would leave `to_local` reporting stretched coordinates and
## quietly break the swept-contact guard below, which compares against a real ball radius.
@export var size_scale: float = 1.0

var state: State = State.REST
var progress: float = 0.0           ## 0 rest, 1 fully extended
var dead: bool = false              ## tilt kills the flippers until the ball drains
## Fresh Rubbers / Steel Toes: `Stats.flipper_power()` scales the surface speed the bat is
## guaranteed to hand the ball. 1.0 is the M0 curve, which is what the feel sims measure.
var power_scale: float = 1.0

var _phase_time: float = 0.0
var _fall_from: float = 0.0
var _held: bool = false
var _buffered_at: float = -1000.0   ## engine time of a press that arrived mid-return
var _ang_vel: float = 0.0
var _prev_rotation: float = 0.0
var _ball: Ball = null
var _prev_local_y: float = 0.0
var _prev_local_valid: bool = false
var _glow: float = 0.0

var _rest_rot: float = 0.0
var _up_rot: float = 0.0
var _strike_sign: float = -1.0
var _clock: float = 0.0             ## physics-tick time; never wall time (headless sims)
var _present: bool = true           ## hardware switch — the Club's bats before it is bought
## Sammy's crew put a wrench through the linkage (specs/m2-content.md §5). Seconds left of
## the jam, and of the wrench gag that telegraphs it.
var _jam: float = 0.0
var _telegraph: float = 0.0


func _ready() -> void:
	process_physics_priority = 10
	sync_to_physics = true
	collision_layer = Feel.LAYER_FLIPPERS
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.FLIPPER_FRICTION, Feel.FLIPPER_BOUNCE)
	_rest_rot = Feel.flipper_rest_rotation(side)
	_up_rot = Feel.flipper_up_rotation(side)
	_strike_sign = 1.0 if side == &"right" else -1.0
	rotation = _rest_rot
	_prev_rotation = rotation
	_build_shapes()


func bat_length() -> float:
	return Feel.FLIPPER_LENGTH * size_scale


func pivot_radius() -> float:
	return Feel.FLIPPER_PIVOT_RADIUS * size_scale


func tip_radius() -> float:
	return Feel.FLIPPER_TIP_RADIUS * size_scale


func _build_shapes() -> void:
	var l := bat_length()
	var rp := pivot_radius()
	var rt := tip_radius()

	var pivot := CollisionShape2D.new()
	var pc := CircleShape2D.new()
	pc.radius = rp
	pivot.shape = pc
	pivot.name = "Pivot"
	add_child(pivot)

	var tip := CollisionShape2D.new()
	var tc := CircleShape2D.new()
	tc.radius = rt
	tip.shape = tc
	tip.position = Vector2(l, 0.0)
	tip.name = "Tip"
	add_child(tip)

	var body := CollisionShape2D.new()
	var quad := ConvexPolygonShape2D.new()
	quad.set_point_cloud(PackedVector2Array([
		Vector2(0.0, -rp), Vector2(l, -rt), Vector2(l, rt), Vector2(0.0, rp),
	]))
	body.shape = quad
	body.name = "Bat"
	add_child(body)


func set_ball(b: Ball) -> void:
	_ball = b
	_prev_local_valid = false


func press() -> void:
	if dead or not _present or _jam > 0.0:
		return
	match state:
		State.REST:
			_held = true
			_fire()
		State.FALLING:
			_held = true
			_buffered_at = _now()
		_:
			_held = true


func release() -> void:
	_held = false
	if state == State.RISING or state == State.HELD:
		_begin_fall()


func set_pressed(pressed: bool) -> void:
	if pressed and not _held:
		press()
	elif not pressed and _held:
		release()


## Is the button down on this bat right now? The Club's mini pair rides the main flippers'
## button state rather than reading the input actions itself, so the deck inherits the input
## buffer, the touch zones and the tilt kill for free and there is one input path, not two.
func is_held() -> bool:
	return _held


func kill() -> void:
	dead = true
	_held = false
	_buffered_at = -1000.0
	if state == State.RISING or state == State.HELD:
		_begin_fall()


func revive() -> void:
	dead = false
	_jam = 0.0
	_telegraph = 0.0


## THE WRENCH (specs/m2-content.md §5). A jam is not a tilt and not dormancy: the bat is
## bought, present and alive, it simply eats input until the wrench comes out — and it droops
## on the way in, so a cradled ball is lost with it. Separate from `dead` on purpose; a Night
## that tilts mid-jam must still clear both independently.
func jam(seconds: float) -> void:
	if not _present or seconds <= 0.0:
		return
	_jam = maxf(_jam, seconds)
	_telegraph = 0.0
	_held = false
	_buffered_at = -1000.0
	if state == State.RISING or state == State.HELD:
		_begin_fall()
	queue_redraw()


func unjam() -> void:
	_jam = 0.0
	_telegraph = 0.0
	queue_redraw()


func is_jammed() -> bool:
	return _jam > 0.0


func jam_left() -> float:
	return _jam


## The gag before the wrench: the bat rattles for `seconds` and the player gets to decide
## what to do with the ball first (spec §5: 2 s of notice, every time).
func telegraph(seconds: float) -> void:
	if not _present or seconds <= 0.0:
		return
	_telegraph = maxf(_telegraph, seconds)
	queue_redraw()


func is_telegraphed() -> bool:
	return _telegraph > 0.0


## Dormant hardware (game/table/hardware/dormant.gd). Separate from `dead`, which is the
## tilt state the session owns: a bat that was never bought is not a bat that got tilted.
func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	collision_layer = Feel.LAYER_FLIPPERS if active else 0
	if active:
		return
	_held = false
	_buffered_at = -1000.0
	state = State.REST
	progress = 0.0
	rotation = _rest_rot


func is_hardware_active() -> bool:
	return _present


func _now() -> float:
	return _clock


## Global AABB of the bat right now — used by tests and by trap/cradle checks.
func bat_aabb() -> Rect2:
	var l := bat_length()
	var rp := pivot_radius()
	var rt := tip_radius()
	var pts := [
		to_global(Vector2(0.0, -rp)), to_global(Vector2(0.0, rp)),
		to_global(Vector2(l, -rt)), to_global(Vector2(l, rt)),
	]
	var r := Rect2(pts[0], Vector2.ZERO)
	for p: Vector2 in pts:
		r = r.expand(p)
	return r


## Outward normal of the striking face, in global space.
func strike_normal() -> Vector2:
	return Vector2(0.0, _strike_sign).rotated(global_rotation)


## Where a ball sits when cradled at `t` along the bat (0 = pivot, 1 = tip).
func cradle_point(t: float) -> Vector2:
	var x := bat_length() * clampf(t, 0.0, 1.0)
	return to_global(Vector2(x, 0.0)) + strike_normal() * (_bat_radius(x) + Feel.BALL_RADIUS)


func _fire() -> void:
	state = State.RISING
	_phase_time = 0.0
	_buffered_at = -1000.0
	_glow = 1.0
	Events.flipper_fired.emit(side)
	AudioDirector.play(&"flipper_up")


func _begin_fall() -> void:
	state = State.FALLING
	_fall_from = progress
	_phase_time = 0.0
	AudioDirector.play(&"flipper_down")


func _physics_process(delta: float) -> void:
	_clock += delta
	if _jam > 0.0:
		_jam = maxf(_jam - delta, 0.0)
		if _jam <= 0.0:
			queue_redraw()
	if _telegraph > 0.0:
		_telegraph = maxf(_telegraph - delta, 0.0)
		queue_redraw()
	_advance(delta)
	var target := FlipperCurve.rotation_for(side, progress)
	_ang_vel = wrapf(target - _prev_rotation, -PI, PI) / maxf(delta, 0.00001)
	rotation = target
	_prev_rotation = target
	_guard_ball(delta)
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 5.0, 0.0)
		queue_redraw()


func _advance(delta: float) -> void:
	_phase_time += delta
	match state:
		State.RISING:
			progress = FlipperCurve.up_progress(_phase_time)
			if _phase_time >= Feel.FLIPPER_UP_TIME:
				progress = 1.0
				state = State.HELD
				_phase_time = 0.0
				if not _held:
					_begin_fall()
		State.HELD:
			progress = 1.0
		State.FALLING:
			progress = FlipperCurve.down_progress(_phase_time, _fall_from)
			if FlipperCurve.down_remaining(_phase_time, _fall_from) <= 0.0:
				progress = 0.0
				state = State.REST
				_phase_time = 0.0
				_consume_buffer()
		State.REST:
			progress = 0.0


## A press that landed during the return stroke re-fires the instant the bat is home,
## as long as it was inside Feel.INPUT_BUFFER of that moment (mobile touch latency budget).
func _consume_buffer() -> void:
	if dead or _jam > 0.0:
		return
	if _held:
		_fire()
		return
	if _now() - _buffered_at <= Feel.INPUT_BUFFER:
		_fire()
	_buffered_at = -1000.0


## Belt-and-suspenders swept test (docs/09 §2). The bat can sweep ~24 px per tick at the
## tip; if the solver ever lets the ball out the wrong side we put it back and hand it the
## surface velocity rather than letting a shot silently vanish.
func _guard_ball(delta: float) -> void:
	if _ball == null or not is_instance_valid(_ball):
		_prev_local_valid = false
		return
	var local := to_local(_ball.global_position)
	var span_max := bat_length() + tip_radius()
	var in_span := local.x > -pivot_radius() and local.x < span_max
	var bat_r := _bat_radius(local.x)
	var reach := bat_r + Feel.BALL_RADIUS

	if in_span and _prev_local_valid and _ang_vel != 0.0:
		var was_striking := _prev_local_y * _strike_sign > 0.0
		var now_striking := local.y * _strike_sign > 0.0
		if was_striking and not now_striking and absf(local.y) < reach:
			_rescue(local, bat_r)
			local = to_local(_ball.global_position)

	if in_span and absf(local.y) <= reach + 2.0 and local.y * _strike_sign > 0.0:
		_assist(local, reach, delta)

	_prev_local_y = local.y
	_prev_local_valid = true


func _bat_radius(local_x: float) -> float:
	var t := clampf(local_x / bat_length(), 0.0, 1.0)
	return lerpf(pivot_radius(), tip_radius(), t)


func _rescue(local: Vector2, bat_r: float) -> void:
	var fixed := Vector2(local.x, _strike_sign * (bat_r + Feel.BALL_RADIUS + 1.0))
	_ball.place(to_global(fixed))
	var rel := _ball.global_position - global_position
	var surface := _ang_vel * Vector2(-rel.y, rel.x)
	_ball.set_velocity(surface)


## Guarantee the authored curve's power actually reaches the ball. Uses the surface speed at
## the real contact point, so tip shots stay hotter than base shots.
func _assist(local: Vector2, reach: float, _delta: float) -> void:
	if _ang_vel == 0.0 or state != State.RISING:
		return
	if absf(local.y) > reach + 1.0:
		return
	var rel := _ball.global_position - global_position
	var surface := _ang_vel * Vector2(-rel.y, rel.x)
	var n := (to_global(local) - to_global(Vector2(local.x, 0.0))).normalized()
	if n == Vector2.ZERO:
		return
	var vn_surface := surface.dot(n) * power_scale
	if vn_surface <= 0.0:
		return
	var vn_ball := _ball.linear_velocity.dot(n)
	if vn_ball < vn_surface:
		_ball.set_velocity(_ball.linear_velocity + n * (vn_surface - vn_ball))


func _draw() -> void:
	var l := bat_length()
	var rp := pivot_radius()
	var rt := tip_radius()
	var brass := Feel.COL_BRASS
	if _glow > 0.0:
		brass = brass.lerp(Color(1.0, 0.97, 0.8), _glow * 0.7)
	if _jam > 0.0:
		brass = brass.lerp(Feel.COL_DIRTY, 0.55).darkened(0.25)
	elif _telegraph > 0.0:
		# the wrench gag: the bat rattles a warning before the linkage goes
		brass = brass.lerp(Feel.COL_DIRTY, 0.35 * (0.5 + 0.5 * sin(_clock * 26.0)))
	var body := PackedVector2Array([
		Vector2(0.0, -rp), Vector2(l, -rt), Vector2(l, rt), Vector2(0.0, rp),
	])
	draw_colored_polygon(body, brass)
	draw_circle(Vector2.ZERO, rp, brass)
	draw_circle(Vector2(l, 0.0), rt, brass)
	draw_arc(Vector2.ZERO, rp, 0.0, TAU, 24, Feel.COL_INK, 3.0)
	draw_arc(Vector2(l, 0.0), rt, 0.0, TAU, 20, Feel.COL_INK, 3.0)
	draw_line(Vector2(0.0, -rp), Vector2(l, -rt), Feel.COL_INK, 3.0)
	draw_line(Vector2(0.0, rp), Vector2(l, rt), Feel.COL_INK, 3.0)
	draw_circle(Vector2.ZERO, rp * 0.32, Feel.COL_INK)
	if _jam > 0.0:
		# the wrench itself, laid across the linkage
		var mid := Vector2(l * 0.42, 0.0)
		draw_line(mid - Vector2(0.0, rp * 1.1), mid + Vector2(0.0, rp * 1.1),
				Feel.COL_NEWSPRINT.darkened(0.15), 7.0)
		draw_arc(mid - Vector2(0.0, rp * 1.1), rp * 0.42, PI * 0.2, PI * 1.8, 14,
				Feel.COL_NEWSPRINT.darkened(0.15), 6.0)
