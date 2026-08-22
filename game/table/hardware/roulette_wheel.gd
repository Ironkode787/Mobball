class_name RouletteWheel
extends Node2D
## The Club's flagship toy: a spinning pocket disc set in a shallow bowl (docs/02 §2 R4).
##
## The bowl is real geometry — a capsule arc around the lower half of the wheel — so a ball
## fed in over the open top is genuinely caught and rattles down to the bottom the way it
## would in a real one. The eight pockets sweep past underneath it on the kinematic disc;
## whichever one arrives first takes the ball, rides it round for `HOLD` seconds and throws
## it back out over the rim. Three of the eight are the house's.
##
## No money is decided here beyond the courtesy switch: which pocket, and whether it was the
## house's, goes out as a signal and the flow lane settles the bet (specs/m2-empire.md
## "hardware reports outcomes, flow owns money").
##
## Anti-park is the whole design. A ball in a bowl is a ball in a hole, so every path out of
## this object is on a clock: capture happens within one pocket sweep (~0.9 s), `FORCE_AFTER`
## takes any ball that is somehow still loose in the bowl regardless of speed or pocket
## alignment, and a captured ball is always ejected. There is no state in here that can hold
## the ball for longer than HOLD + FORCE_AFTER.

## The ball dropped in. `pocket` is 0..POCKETS-1, `house` is the three marked ones.
signal landed(pocket: int, house: bool)
signal thrown(pocket: int)

const POCKETS := 8
const HOUSE_POCKETS: PackedInt32Array = [0, 3, 6]
const RADIUS := 96.0
const WALL_THICK := 16.0
## The pockets ride where a ball settles against the inside of the bowl, so a resting ball is
## already in the sweep line — no pocket can pass "under" it and miss.
const POCKET_RING := 60.0
const POCKET_R := 20.0
const GRAB := 24.0
const SPIN := 0.9                   ## rad/s
const HOLD := 1.2
const CAPTURE_SPEED := 900.0
const EJECT_SPEED := 1150.0
## Up and to the right: out over the open rim, away from the deck's left wall, into the
## underside of the orbit guide — which is exactly where the rest of the deck is.
const EJECT_DIR := Vector2(0.72, -0.69)
const COOLDOWN := 0.55
const FORCE_AFTER := 3.0

@export var id: StringName = &"roulette_wheel"

var angle: float = 0.0

var _present: bool = true
var _ball: Ball = null
var _bowl: StaticBody2D = null
var _walls: WallBuilder = null
var _held: bool = false
var _pocket: int = 0
var _hold_t: float = 0.0
var _cool: float = 0.0
var _inside_t: float = 0.0
var _flash: float = 0.0
var _last_pocket: int = -1


func _ready() -> void:
	_bowl = StaticBody2D.new()
	_bowl.name = "Bowl"
	_bowl.collision_layer = Feel.LAYER_WALLS
	_bowl.collision_mask = 0
	_bowl.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, Feel.WALL_BOUNCE)
	add_child(_bowl)
	_walls = WallBuilder.new(_bowl)
	# lower half only: the top is the way in and the way out
	_walls.arc(Vector2.ZERO, RADIUS, 0.0, PI, 26, WALL_THICK)


func set_ball(b: Ball) -> void:
	if _held and b != _ball:
		_held = false
	_ball = b


func holds_ball() -> bool:
	return _held and _ball != null and is_instance_valid(_ball)


func pocket_count() -> int:
	return POCKETS


static func is_house(pocket: int) -> bool:
	return HOUSE_POCKETS.has(pocket)


func pocket_angle(i: int) -> float:
	return angle + float(i) * TAU / float(POCKETS)


func pocket_position(i: int) -> Vector2:
	var a := pocket_angle(i)
	return global_position + Vector2(cos(a), sin(a)) * POCKET_RING


## Where a ball comes to rest in the bowl if nothing takes it — the bottom of the well.
func rest_position() -> Vector2:
	return global_position + Vector2(0.0, RADIUS - WALL_THICK * 0.5 - Feel.BALL_RADIUS)


func last_pocket() -> int:
	return _last_pocket


func _physics_process(delta: float) -> void:
	if not _present:
		return
	angle = wrapf(angle + SPIN * delta, 0.0, TAU)
	queue_redraw()
	_cool = maxf(_cool - delta, 0.0)
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)
	if _ball == null or not is_instance_valid(_ball):
		_held = false
		_inside_t = 0.0
		return
	if _held:
		_hold_t += delta
		BallHold.steer(_ball, pocket_position(_pocket), delta)
		if _hold_t >= HOLD:
			_throw()
		return
	if BallHold.is_held(_ball):
		_inside_t = 0.0
		return                          # a ramp or a saucer has it
	var d := _ball.global_position.distance_to(global_position)
	if d > RADIUS - WALL_THICK * 0.5:
		_inside_t = 0.0
		return
	_inside_t += delta
	if _cool > 0.0:
		return
	var forced := _inside_t >= FORCE_AFTER
	if not forced and _ball.speed() > CAPTURE_SPEED:
		return
	var best := -1
	var best_d := INF
	for i in range(POCKETS):
		var pd := _ball.global_position.distance_to(pocket_position(i))
		if pd < best_d:
			best_d = pd
			best = i
	if best < 0:
		return
	if best_d > GRAB and not forced:
		return
	_take(best)


func _take(pocket: int) -> void:
	_held = true
	_pocket = pocket
	_last_pocket = pocket
	_hold_t = 0.0
	_inside_t = 0.0
	_flash = 1.0
	BallHold.take(_ball)
	AudioDirector.play(&"coin_drop")
	TableScore.earn(TableScore.GROUP_CASINO, TableScore.CASINO_POCKET, id, _ball)
	landed.emit(pocket, is_house(pocket))


func _throw() -> void:
	_held = false
	_cool = COOLDOWN
	var tangential := Vector2(-sin(pocket_angle(_pocket)), cos(pocket_angle(_pocket)))
	var dir := (EJECT_DIR + tangential * 0.18).normalized()
	BallHold.release(_ball, pocket_position(_pocket), dir * EJECT_SPEED)
	AudioDirector.play(&"kickback")
	thrown.emit(_pocket)


func set_hardware_active(active: bool) -> void:
	if _present == active:
		return
	_present = active
	visible = active
	_bowl.collision_layer = Feel.LAYER_WALLS if active else 0
	_inside_t = 0.0
	if not active and _held:
		_held = false
		BallHold.release(_ball, global_position + Vector2(0.0, RADIUS + 40.0), Vector2.ZERO)


func is_hardware_active() -> bool:
	return _present


func _draw() -> void:
	var felt := Feel.COL_FELT.darkened(0.35)
	draw_circle(Vector2.ZERO, RADIUS - WALL_THICK * 0.5, felt)
	draw_arc(Vector2.ZERO, RADIUS - WALL_THICK * 0.5, 0.0, TAU, 48,
			Feel.COL_INK.lightened(0.10), 3.0)
	for i in range(POCKETS):
		var a := pocket_angle(i)
		var p := Vector2(cos(a), sin(a)) * POCKET_RING
		var house := is_house(i)
		var col := Feel.COL_DIRTY.darkened(0.25) if house else Feel.COL_INK.darkened(0.2)
		if _held and i == _pocket:
			col = col.lerp(Feel.COL_NEWSPRINT, 0.35 + _flash * 0.4)
		draw_circle(p, POCKET_R, col)
		draw_arc(p, POCKET_R, 0.0, TAU, 16, Feel.COL_BRASS.darkened(0.3), 3.0)
		draw_line(Vector2(cos(a), sin(a)) * (POCKET_RING + POCKET_R),
				Vector2(cos(a), sin(a)) * (RADIUS - WALL_THICK), Feel.COL_BRASS.darkened(0.55), 2.0)
	draw_circle(Vector2.ZERO, 22.0, Feel.COL_BRASS.darkened(0.2))
	draw_arc(Vector2.ZERO, 22.0, 0.0, TAU, 20, Feel.COL_INK, 3.0)
	# the bowl itself, drawn from the same chains the physics uses
	if _walls != null:
		_walls.draw_into(self, Feel.COL_INK.lightened(0.16), Feel.COL_INK)
