class_name Spinner
extends Node2D
## The bicycle wheel in the numbers lane (docs/02 §2 R1). It does not block the ball — it
## is a blade on an axle across the lane. A ball through it spins it up; friction winds it
## down, and every half turn is one switch closure. That decay is the whole feel of a
## spinner: the payout you already earned keeps ticking in after the ball has gone.
##
## The running spin total is kept because The Wire's number draw reads it (docs/02 §2 R2).

signal spun(total: int)

## rad/s² bled off while spinning. A real spinner is dead in two to four seconds; at 7.0 this
## one coasted for eleven and paid 87–138 segments off a single pass — $2.2K–$3.5K at T1, a
## couple of hundred bumper hits for one shot (SIM lane balance report, design-approved).
## At 25.0 a full-speed pass is worth ~39 segments and the decay is still audible.
const FRICTION := 25.0
const MAX_SPEED := 78.0               ## rad/s — about 12 turns/s, 25 segments/s
const SPEED_PER_PX := 0.055           ## ball speed (px/s) → blade speed (rad/s)
const MIN_KICK := 6.0

@export var id: StringName = &"spinner_numbers"

var spins_total: int = 0              ## half-turn segments since boot
var blade_length: float = 84.0
var lane_width: float = 90.0

var _present: bool = true
var _area: Area2D = null
var _angle: float = 0.0
var _vel: float = 0.0
var _segment: int = 0
var _ball: Ball = null


func configure(p_id: StringName, center: Vector2, p_lane_width: float) -> void:
	id = p_id
	position = center
	lane_width = p_lane_width
	blade_length = p_lane_width - 8.0


func _ready() -> void:
	_area = Area2D.new()
	_area.name = "Sensor"
	_area.collision_layer = Feel.LAYER_ZONES
	_area.collision_mask = Feel.LAYER_BALL
	_area.monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(lane_width, 34.0)
	cs.shape = rect
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_ball_entered)
	_area.body_exited.connect(_on_ball_exited)
	_apply_collision()


func _on_ball_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball := body as Ball
	_ball = ball
	var dir := -1.0 if ball.linear_velocity.y < 0.0 else 1.0
	var kick := maxf(ball.speed() * SPEED_PER_PX, MIN_KICK)
	_vel = clampf(_vel * 0.35 + dir * kick, -MAX_SPEED, MAX_SPEED)


func _on_ball_exited(body: Node2D) -> void:
	if body == _ball:
		_ball = null


func _physics_process(delta: float) -> void:
	if not _present or is_zero_approx(_vel):
		return
	_angle += _vel * delta
	_vel = move_toward(_vel, 0.0, FRICTION * delta)
	var seg := int(floor(_angle / PI))
	while seg != _segment:
		_segment += 1 if seg > _segment else -1
		_score()
	queue_redraw()


func _score() -> void:
	spins_total += 1
	AudioDirector.play(&"spinner_tick")
	TableScore.earn(TableScore.GROUP_SPINNER, TableScore.SPINNER_SEGMENT, id, _ball)
	spun.emit(spins_total)


## Spin the blade by hand — the growth sim uses this instead of aiming a ball down a lane.
func kick(speed: float) -> void:
	_vel = clampf(speed, -MAX_SPEED, MAX_SPEED)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if not active:
		_vel = 0.0
	_apply_collision()


func _apply_collision() -> void:
	if _area == null:
		return
	_area.collision_layer = Feel.LAYER_ZONES if _present else 0
	_area.collision_mask = Feel.LAYER_BALL if _present else 0


func _draw() -> void:
	var half := blade_length * 0.5
	draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), Feel.COL_INK, 5.0)
	# a blade on a horizontal axle, seen from above: it foreshortens as it turns over
	var squash := absf(cos(_angle))
	var h := 15.0 * squash + 2.0
	var col := Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, squash * 0.35)
	draw_rect(Rect2(Vector2(-half, -h), Vector2(blade_length, h * 2.0)), col)
	draw_rect(Rect2(Vector2(-half, -h), Vector2(blade_length, h * 2.0)), Feel.COL_INK, false, 3.0)
	for i in range(3):
		var x := lerpf(-half * 0.7, half * 0.7, float(i) / 2.0)
		draw_line(Vector2(x, -h), Vector2(x, h), Feel.COL_INK, 2.0)
	draw_circle(Vector2.ZERO, 6.0, Feel.COL_INK)
