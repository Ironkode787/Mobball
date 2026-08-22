class_name DrainMagnet
extends Node2D
## The Captain's magnet — raid hardware (specs/m1-hook.md Lane 1 "Raid v1"). Under the
## playfield by the drain; while a raid is running it winds up, warns, and yanks.
##
## The warning is the whole point: 1.2 s of visible, audible tell before the pull, so a
## player who is paying attention can flip or lean out of it. A magnet that grabs without
## warning is not difficulty, it is a coin flip.
##
## The flow lane (RaidMode) owns the raid clock and applies the pull itself, so this runs
## the telegraph and leaves the impulse alone unless `self_driven` is set.

signal telegraph_started()
signal pulled(ball: Ball)

const PERIOD := 6.0
const TELEGRAPH := 1.2
const IMPULSE := 620.0

var active: bool = false
var self_driven: bool = false
var drain_point: Vector2 = Vector2(490.0, 1920.0)

var _ball: Ball = null
var _phase: float = 0.0
var _telegraphing: bool = false
var _flash: float = 0.0


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


## Seconds until the next pull (negative when idle).
func time_to_pull() -> float:
	return PERIOD - _phase if active else -1.0


func pull(b: Ball = null) -> void:
	var target := b if b != null else _ball
	if target == null or not is_instance_valid(target):
		return
	var dir := drain_point - target.global_position
	if dir.length() < 1.0:
		return
	target.kick(dir.normalized() * IMPULSE)
	_flash = 1.0
	queue_redraw()
	pulled.emit(target)


func _physics_process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
		queue_redraw()
	if not active:
		return
	_phase += delta
	if not _telegraphing and _phase >= PERIOD - TELEGRAPH:
		_telegraphing = true
		AudioDirector.play(&"siren")
		telegraph_started.emit()
		queue_redraw()
	if _phase < PERIOD:
		if _telegraphing:
			queue_redraw()
		return
	_phase = 0.0
	_telegraphing = false
	if self_driven:
		pull()
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var warn := 0.0
	if _telegraphing:
		warn = clampf((_phase - (PERIOD - TELEGRAPH)) / TELEGRAPH, 0.0, 1.0)
	var glow := maxf(warn, _flash)
	var col := Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g, Feel.COL_DIRTY.b, 0.25 + glow * 0.65)
	for i in range(3):
		var r := 34.0 + float(i) * 26.0 + glow * 30.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, col, 5.0 - float(i))
	draw_circle(Vector2.ZERO, 16.0 + glow * 8.0, col)
