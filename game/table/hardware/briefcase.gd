class_name Briefcase
extends Node2D
## The mystery briefcase (specs/m3-fall-rise.md sub-wave B, docs/05). A man in a trench coat
## leaves a case on the felt, and it is yours if you can get to it inside a minute. If you
## cannot, he comes back and picks it up, and you get to watch him walk off with it.
##
## **It has no collision geometry, deliberately** — the same reasoning the hold saucers are
## built on. A collider that appears in the middle of a live playfield is a change to the
## machine's geometry mid-Night: a new thing to park on, a new gap to wedge in, and a new
## deflection the player never learned. So the case is a token: the ball reaches it and it is
## gone. Contact is measured against the case's own capsule, not a generous circle, so it
## still has to be *hit* — it is just that hitting it is the last thing that happens to it.
##
## The table owns where it lands (ProgressionTable.BRIEFCASE_SPOTS) and the flow lane owns
## what is inside it. Nothing here touches money.

## The ball got to it first.
signal collected(ball: Ball)
## Sixty seconds went by and the bagman came back for it. Fires when he starts walking, not
## when the drawing finishes: the case is out of play the moment the clock runs out.
signal expired()

const LENGTH := 44.0
const THICK := 22.0
## Half the token's longest reach — the table's spot rules are written in these px.
const REACH := (LENGTH + THICK) * 0.5
## Sat at an angle, like something put down in a hurry. Nothing can rest on it (there is
## nothing to rest on), so this is character rather than physics.
const RAKE_DEG := -12.0
const LIFETIME := 60.0
## The walk-off: he picks it up and leaves the frame. Cosmetic, and short enough that a
## briefcase dropped the instant one expires never overlaps the last one on screen.
const WALK_SECONDS := 0.8
const WALK_DISTANCE := 150.0

@export var id: StringName = &"briefcase"

## Overridable so sims can run the clock in a second instead of a minute.
var lifetime: float = LIFETIME

var _live: bool = false
var _left: float = 0.0
var _walk: float = 0.0
var _glow: float = 0.0
var _walk_dir: float = -1.0


func _ready() -> void:
	visible = false


## Put a case down here and start its clock. Re-dropping while one is live is the caller's
## business to avoid (ProgressionTable.spawn_briefcase refuses it).
func drop_at(at: Vector2) -> void:
	position = at
	rotation = deg_to_rad(RAKE_DEG)
	_live = true
	_left = maxf(lifetime, 0.1)
	_walk = 0.0
	_glow = 1.0
	# he leaves the way he came: toward the nearer side wall
	_walk_dir = -1.0 if at.x < ProgressionTable.MIRROR_X else 1.0
	visible = true
	AudioDirector.play(&"briefcase_drop")
	queue_redraw()


func is_live() -> bool:
	return _live


func seconds_left() -> float:
	return _left if _live else 0.0


## Take it off the table now, with no signal — the table's own teardown path (a Night ends,
## the piece is switched off) rather than either of the two ways a case can be resolved.
func clear() -> void:
	_live = false
	_walk = 0.0
	visible = false
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _walk > 0.0:
		_walk = maxf(_walk - delta, 0.0)
		if _walk <= 0.0:
			visible = false
		queue_redraw()
	if not _live:
		return
	if _glow > 0.0:
		_glow = maxf(_glow - delta * 1.5, 0.0)
		queue_redraw()
	_left -= delta
	if _left <= 0.0:
		_take_it_back()
		return
	var ball := _toucher()
	if ball != null:
		_collect(ball)


## The nearest live ball actually touching the case. Measured against the capsule so a ball
## flying past 50 px away does not collect a case it never reached.
func _toucher() -> Ball:
	var half := LENGTH * 0.5
	var axis := Vector2.RIGHT.rotated(rotation)
	var reach := THICK * 0.5 + Feel.BALL_RADIUS + 2.0
	for b in Balls.live():
		if b == null or not is_instance_valid(b) or BallHold.is_held(b):
			continue
		var p := b.global_position
		var along := clampf((p - global_position).dot(axis), -half, half)
		if (global_position + axis * along).distance_to(p) <= reach:
			return b
	return null


func _collect(ball: Ball) -> void:
	_live = false
	visible = false
	AudioDirector.play(&"drop_clack")
	TableScore.hit(id, ball)
	collected.emit(ball)
	queue_redraw()


func _take_it_back() -> void:
	_live = false
	_walk = WALK_SECONDS
	AudioDirector.play(&"briefcase_leave")
	expired.emit()
	queue_redraw()


# =================================================================== dormancy =====


## Nothing here is ever bought, so this is only the table's teardown door: switching the
## token off takes any live case off the felt without resolving it either way.
func set_hardware_active(active: bool) -> void:
	if not active:
		clear()


# ==================================================================== drawing =====


func _draw() -> void:
	if not _live and _walk <= 0.0:
		return
	var t := 0.0 if _walk <= 0.0 else 1.0 - _walk / WALK_SECONDS
	var slide := Vector2(_walk_dir * WALK_DISTANCE * t, -18.0 * sin(t * PI))
	var fade := 1.0 - t
	var half := LENGTH * 0.5
	var body := Feel.COL_INK.lightened(0.16).lerp(Feel.COL_BRASS, _glow * 0.35)
	body.a = fade
	var trim := Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, _glow * 0.6)
	trim.a = fade

	# the man, when there is one: a coat and a hat, walking out of frame with the case
	if _walk > 0.0:
		var coat := Feel.COL_INK.lightened(0.06)
		coat.a = fade
		var at := slide + Vector2(_walk_dir * 22.0, -30.0)
		draw_rect(Rect2(at + Vector2(-13.0, -18.0), Vector2(26.0, 44.0)), coat)
		draw_circle(at + Vector2(0.0, -26.0), 11.0, coat)
		draw_line(at + Vector2(-17.0, -32.0), at + Vector2(17.0, -32.0), coat, 5.0)

	var shadow := Feel.COL_INK.darkened(0.3)
	shadow.a = fade
	draw_rect(Rect2(slide + Vector2(-half, -THICK * 0.5), Vector2(LENGTH, THICK)), shadow)
	draw_rect(Rect2(slide + Vector2(-half + 2.0, -THICK * 0.5 + 2.0),
			Vector2(LENGTH - 4.0, THICK - 4.0)), body)
	# handle, seam and two brass clasps: enough case to read at a glance
	draw_arc(slide + Vector2(0.0, -THICK * 0.5), 9.0, PI, TAU, 12, trim, 3.0)
	draw_line(slide + Vector2(-half + 4.0, 0.0), slide + Vector2(half - 4.0, 0.0),
			trim.darkened(0.45), 2.0)
	for x: float in [-9.0, 9.0]:
		draw_rect(Rect2(slide + Vector2(x - 3.0, -2.5), Vector2(6.0, 5.0)), trim)
