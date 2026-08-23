class_name DrainMagnet
extends Node2D
## The Captain's magnet — raid hardware (specs/m1-hook.md Lane 1 "Raid v1"). Under the
## playfield by the drain; while a raid is running it winds up, warns, and yanks.
##
## The warning is the whole point: 1.2 s of visible tell before the pull, so a player who is
## paying attention can flip or lean out of it. A magnet that grabs without warning is not
## difficulty, it is a coin flip.
##
## Visual only, deliberately: the flow lane's RaidMode owns the raid soundscape (a looping
## siren bed), and a 7 s wail retriggered every 6 s telegraph is a machine gun. A short
## squelch cue for this belongs to a future audio wave.
##
## RaidMode also owns the raid clock and applies the pull itself, so this runs the telegraph
## and leaves the impulse alone unless `self_driven` is set.

signal telegraph_started()
signal pulled(ball: Ball)

const PERIOD := 6.0
const TELEGRAPH := 1.2
const IMPULSE := 620.0

var active: bool = false
var self_driven: bool = false
var drain_point: Vector2 = Vector2(490.0, 1920.0)
## How fast the cycle runs. 1.0 is the shipped 6 s beat; the RICO raid's street sweep asks
## the table for double time (ProgressionTable.set_raid_speed). The *tell* does not shrink
## with it — see `_telegraph_at()`, because 1.2 s of warning is this piece's whole reason to
## exist and a raid that reads faster must not also read less.
var rate: float = 1.0

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


## Seconds until the next pull (negative when idle). Real seconds, whatever `rate` is doing.
func time_to_pull() -> float:
	return (PERIOD - _phase) / _rate() if active else -1.0


## Push the next pull out to `seconds` from now, cancelling a telegraph that has not earned
## its place yet. Two coils under one table must never wind up at once — a player can read
## one tell, not two — so the table keeps them apart with this (`set_federal_raid` phase 3).
func reschedule(seconds: float) -> void:
	_phase = PERIOD - clampf(seconds * _rate(), 0.0, PERIOD)
	_telegraphing = _phase >= _telegraph_at()
	queue_redraw()


func _rate() -> float:
	return clampf(rate, 0.25, 4.0)


## Where in the cycle the warning starts, scaled so the warning itself is always TELEGRAPH
## *real* seconds long however fast the cycle is running.
func _telegraph_at() -> float:
	return maxf(PERIOD - TELEGRAPH * _rate(), PERIOD * 0.2)


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
	_phase += delta * _rate()
	if not _telegraphing and _phase >= _telegraph_at():
		_telegraphing = true
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
		var from := _telegraph_at()
		warn = clampf((_phase - from) / maxf(PERIOD - from, 0.001), 0.0, 1.0)
	var glow := maxf(warn, _flash)
	var col := Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g, Feel.COL_DIRTY.b, 0.25 + glow * 0.65)
	for i in range(3):
		var r := 34.0 + float(i) * 26.0 + glow * 30.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, col, 5.0 - float(i))
	draw_circle(Vector2.ZERO, 16.0 + glow * 8.0, col)
