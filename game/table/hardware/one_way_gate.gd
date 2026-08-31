class_name OneWayGate
extends Node2D
## A blade the ball may only cross from one side — the M1 shooter-lane flap generalised so
## the Docks can have one too (docs/02 §2 R5: "behind a one-way gate off the left channel").
##
## The physics is a latch, not a hinge. A hinged flap in a 2D solver is a body the ball can
## push *through* at 120 Hz, or get pinned under; instead the blade is a plain static bar
## whose collision layer is switched by which side of it the ball is on. Two rules keep that
## honest:
##
##   * **Hysteresis.** The side is only re-read while the ball is inside the blade's span,
##     and only once it is `LATCH_BAND` px clear of the blade plane. A ball wandering along
##     the blade cannot flutter it.
##   * **Never materialise inside the ball.** Within `HOLD_BAND` px of the plane the blade
##     keeps whatever state it already had, so it can never close on top of the ball.
##
## `pass_from` is the side the ball is allowed to arrive from: standing on that side the
## blade is *open*, standing on the other side it is *solid*. The Docks' gate points DOWN —
## a ball flipped up the numbers lane passes straight through, and the same ball coming back
## down the lane lands on a solid blade that is raked into the dock mouth.

signal opened()
signal closed()

const LATCH_BAND := 34.0
const HOLD_BAND := 40.0

@export var id: StringName = &"one_way_gate"

## The blade, in table space.
var from_point: Vector2 = Vector2.ZERO
var to_point: Vector2 = Vector2.ZERO
var thickness: float = 16.0
## Unit vector pointing at the side a ball may cross *from*.
var pass_from: Vector2 = Vector2.DOWN
var color: Color = Feel.COL_BRASS

var _body: StaticBody2D = null
var _present: bool = true
var _open: bool = false
var _ball: Ball = null
var _axis: Vector2 = Vector2.RIGHT
var _normal: Vector2 = Vector2.DOWN
var _centre: Vector2 = Vector2.ZERO
var _half_span: float = 0.0


func configure(p_id: StringName, from: Vector2, to: Vector2, p_thickness: float,
		p_pass_from: Vector2) -> void:
	id = p_id
	from_point = from
	to_point = to
	thickness = p_thickness
	pass_from = p_pass_from.normalized()
	_axis = (to - from).normalized()
	_normal = Vector2(-_axis.y, _axis.x)
	if _normal.dot(pass_from) < 0.0:
		_normal = -_normal                     # normal always points at the passing side
	_centre = (from + to) * 0.5
	_half_span = from.distance_to(to) * 0.5


func _ready() -> void:
	_body = StaticBody2D.new()
	_body.name = "Blade"
	_body.collision_layer = Feel.LAYER_WALLS
	_body.collision_mask = 0
	_body.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.12)
	add_child(_body)
	var walls := WallBuilder.new(_body)
	walls.bar(from_point, to_point, thickness)
	_apply_collision()


func set_ball(b: Ball) -> void:
	_ball = b


func is_open() -> bool:
	return _open


## Which side the ball is on, as a signed distance along the passing normal.
func side_of(p: Vector2) -> float:
	return (p - _centre).dot(_normal)


func _physics_process(_delta: float) -> void:
	if not _present or _ball == null or not is_instance_valid(_ball):
		return
	var p := _ball.global_position
	if absf((p - _centre).dot(_axis)) > _half_span + LATCH_BAND:
		return                                  # not at this blade: hold whatever we had
	var d := side_of(p)
	if absf(d) < HOLD_BAND:
		return                                  # never toggle on top of the ball
	var want_open := d > 0.0
	if want_open == _open:
		return
	_open = want_open
	_apply_collision()
	queue_redraw()
	if _open:
		opened.emit()
	else:
		closed.emit()


func _apply_collision() -> void:
	if _body == null:
		return
	_body.collision_layer = 0 if (_open or not _present) else Feel.LAYER_WALLS


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if not active:
		_open = false
	_apply_collision()
	queue_redraw()


func is_hardware_active() -> bool:
	return _present


## Closed/open is the existing latch state, not a new gameplay state. This read gives the draw
## edge an explicit armed invitation while retaining the plane, pass-from side, and hysteresis.
func _visual_state_id() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if _open:
		return TableVisualState.VisualState.ARMED
	return TableVisualState.VisualState.IDLE


func visual_state() -> Dictionary:
	return TableVisualState.state_token(_visual_state_id())


func visual_token() -> Dictionary:
	return visual_state()


func _material_fill(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _draw() -> void:
	var token := visual_token()
	var state := StringName(token["state"])
	var ink := _material_fill(&"ink_glass", Feel.COL_INK)
	var brass := _material_fill(&"brass", Feel.COL_BRASS)
	var paper := _material_fill(&"newsprint", Feel.COL_NEWSPRINT)
	var col := color.darkened(0.65) if _open else color
	if state == &"armed":
		col = brass
	elif state == &"disabled":
		col = ink.lightened(0.18)
	draw_line(from_point, to_point, ink, thickness + 8.0)
	draw_line(from_point, to_point, col, thickness)
	# a row of teeth on the solid side, so which way the blade lets you through reads at a glance
	var steps := maxi(int(_half_span * 2.0 / 22.0), 1)
	for i in range(steps):
		var t := (float(i) + 0.5) / float(steps)
		var p := from_point.lerp(to_point, t)
		draw_line(p, p - _normal * 9.0, col.darkened(0.35), 3.0)
	if state == &"armed":
		var mid := _centre + pass_from.normalized() * 18.0
		var side := Vector2(-_axis.y, _axis.x) * 10.0
		draw_line(mid - pass_from.normalized() * 14.0 + side, mid + pass_from.normalized() * 10.0,
			paper, 4.0)
		draw_line(mid - pass_from.normalized() * 14.0 - side, mid + pass_from.normalized() * 10.0,
			paper, 4.0)
	elif state == &"disabled":
		var mid := _centre
		draw_line(mid - Vector2(13.0, 13.0), mid + Vector2(13.0, 13.0),
			Color(paper.r, paper.g, paper.b, 0.30), 3.0)
		draw_line(mid + Vector2(13.0, -13.0), mid - Vector2(13.0, -13.0),
			Color(paper.r, paper.g, paper.b, 0.30), 3.0)
