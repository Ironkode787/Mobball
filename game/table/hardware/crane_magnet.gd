class_name CraneMagnet
extends Node2D
## The Docks crane (docs/02 §2 R5). A gantry trolley that runs the width of the yard, winds
## up, warns, and swings whatever it is holding out over the water.
##
## Same contract as the Captain's magnet by the drain (hardware/drain_magnet.gd) — a visible
## `TELEGRAPH` before every pull, because a grab with no tell is a coin flip, not difficulty
## — with three things that magnet does not need:
##
##   * **A gantry.** The trolley travels, so the pull comes from a place the player can watch
##     rather than from under the felt. Purely a transform on the drawing: a moving collider
##     in a room this size would be a wedge waiting to happen.
##   * **A zone.** It only ever reaches for a ball inside `zone`. A force field that could
##     yank a ball off the main playfield from inside a room it is not in would be a bug.
##   * **Self-driving by default.** The raid's magnet is scheduled by RaidMode; the crane is
##     table furniture and has no mode behind it yet, so it runs its own clock until the flow
##     lane takes it over with `self_driven = false`.

signal telegraph_started()
signal pulled(ball: Ball)

const PERIOD := 7.0
const TELEGRAPH := 1.2
const IMPULSE := 900.0
const TRAVEL_SPEED := 96.0
const HOOK_DROP := 46.0

@export var id: StringName = &"crane"

var active: bool = false
var self_driven: bool = true
## Where the hook swings the ball out to: the harbour, in table space.
var drop_point: Vector2 = Vector2.ZERO
## Only a ball inside this rect is in reach.
var zone: Rect2 = Rect2()
var rail_from: Vector2 = Vector2.ZERO
var rail_to: Vector2 = Vector2.ZERO

var _ball: Ball = null
var _phase: float = 0.0
var _telegraphing: bool = false
var _flash: float = 0.0
var _travel: float = 0.0
var _travel_dir: float = 1.0


func configure(p_id: StringName, from: Vector2, to: Vector2, p_zone: Rect2,
		p_drop: Vector2) -> void:
	id = p_id
	rail_from = from
	rail_to = to
	zone = p_zone
	drop_point = p_drop


func _ready() -> void:
	visible = false


func set_ball(b: Ball) -> void:
	_ball = b


func set_active(on: bool) -> void:
	if active == on:
		return
	active = on
	visible = on
	_phase = 0.0
	_telegraphing = false
	_flash = 0.0
	queue_redraw()


func is_telegraphing() -> bool:
	return _telegraphing


func time_to_pull() -> float:
	return PERIOD - _phase if active else -1.0


## Where the trolley is right now, in table space.
func trolley_position() -> Vector2:
	return rail_from.lerp(rail_to, _travel)


## Is there a ball the hook could actually reach?
func has_target(b: Ball = null) -> bool:
	var target := b if b != null else _ball
	if target == null or not is_instance_valid(target):
		return false
	if BallHold.is_held(target):
		return false                  # already riding a ramp: not the crane's to take
	return zone.has_point(target.global_position)


func pull(b: Ball = null) -> bool:
	var target := b if b != null else _ball
	if not has_target(target):
		return false
	if target == null:
		target = _ball
	var dir := drop_point - target.global_position
	if dir.length() < 1.0:
		return false
	target.kick(dir.normalized() * IMPULSE)
	_flash = 1.0
	queue_redraw()
	pulled.emit(target)
	return true


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()
	if not active:
		return
	_run_gantry(delta)
	_phase += delta
	if not _telegraphing and _phase >= PERIOD - TELEGRAPH:
		_telegraphing = true
		AudioDirector.play(&"crane_telegraph")
		telegraph_started.emit()
	if _phase < PERIOD:
		if _telegraphing:
			queue_redraw()
		return
	_phase = 0.0
	_telegraphing = false
	if self_driven:
		pull()
	queue_redraw()


## The trolley parks over the ball while it winds up and patrols when it has nothing to do —
## the telegraph is *where* it is as much as how bright it is.
func _run_gantry(delta: float) -> void:
	var span := rail_from.distance_to(rail_to)
	if span < 1.0:
		return
	var want := -1.0
	if has_target():
		var along := (_ball.global_position - rail_from).dot((rail_to - rail_from) / span)
		want = clampf(along / span, 0.0, 1.0)
	if want >= 0.0:
		var step := TRAVEL_SPEED * delta / span
		_travel = move_toward(_travel, want, step * 2.0)
	else:
		_travel += _travel_dir * TRAVEL_SPEED * delta / span
		if _travel >= 1.0:
			_travel = 1.0
			_travel_dir = -1.0
		elif _travel <= 0.0:
			_travel = 0.0
			_travel_dir = 1.0
	queue_redraw()


## The crane is yard furniture, not mode hardware: while it is built it is running. What the
## flow lane takes over later is `self_driven` — who decides *when* the hook drops.
func set_hardware_active(p_active: bool) -> void:
	set_active(p_active)


func is_hardware_active() -> bool:
	return active


func _draw() -> void:
	if not active:
		return
	var warn := 0.0
	if _telegraphing:
		warn = clampf((_phase - (PERIOD - TELEGRAPH)) / TELEGRAPH, 0.0, 1.0)
	var glow := maxf(warn, _flash)
	var rail := Feel.COL_BRASS.darkened(0.55)
	draw_line(rail_from, rail_to, Feel.COL_INK, 16.0)
	draw_line(rail_from, rail_to, rail, 8.0)
	var trolley := trolley_position()
	draw_rect(Rect2(trolley - Vector2(18.0, 12.0), Vector2(36.0, 24.0)),
			Feel.COL_BRASS.lerp(Feel.COL_NEWSPRINT, glow))
	# the hook, lowered as it winds up
	var hook := trolley + Vector2(0.0, HOOK_DROP * (0.35 + glow * 0.65))
	draw_line(trolley, hook, rail.lightened(0.2), 3.0)
	draw_arc(hook, 9.0, 0.0, TAU, 14, Feel.COL_BRASS.lerp(Feel.COL_DIRTY, glow), 4.0)
	if glow <= 0.0:
		return
	var col := Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g, Feel.COL_DIRTY.b, 0.20 + glow * 0.6)
	for i in range(3):
		draw_arc(hook, 22.0 + float(i) * 20.0 + glow * 22.0, 0.0, TAU, 24, col, 4.0 - float(i))
	draw_line(hook, drop_point, Color(col.r, col.g, col.b, col.a * 0.5), 3.0)
