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


func visual_state() -> int:
	if not active:
		return TableVisualState.VisualState.DISABLED
	if _telegraphing or _flash > 0.02:
		return TableVisualState.VisualState.DANGER
	return TableVisualState.VisualState.IDLE


func visual_modifiers() -> Dictionary:
	return {
		&"telegraph": _telegraphing,
		&"flash": _flash > 0.02,
		&"raid_phase": active,
	}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var candidate := Presentation.city.material_for(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


func _draw_hatch(center: Vector2, radius: float, color: Color) -> void:
	for i in range(8):
		var a := float(i) * TAU / 8.0 + 0.18
		var p := Vector2(cos(a), sin(a)) * radius
		draw_line(center + p * 0.38, center + p * 0.82, color, 3.0)


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	if mark == "telegraph_hatch" or mark == "hazard_hatch":
		draw_arc(center, radius, 0.0, TAU, 20, color, 4.0)
		_draw_hatch(center, radius, color)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)


func _draw() -> void:
	if not active:
		return
	var token := visual_token()
	var warn := 0.0
	if _telegraphing:
		var from := _telegraph_at()
		warn = clampf((_phase - from) / maxf(PERIOD - from, 0.001), 0.0, 1.0)
	var glow := maxf(warn, _flash)
	var flash_scale := 0.25 if Presentation.fx != null and Presentation.fx.reduced_flash else 1.0
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var col := Color(Feel.COL_DIRTY.r, Feel.COL_DIRTY.g, Feel.COL_DIRTY.b,
			0.22 + glow * 0.65 * flash_scale)
	# The plate anchors the warning to the drain without adding a collider or route.
	draw_circle(Vector2.ZERO, 24.0, Color(ink.r, ink.g, ink.b, 0.84))
	draw_arc(Vector2.ZERO, 25.0, 0.0, TAU, 24, brass.darkened(0.36), 4.0)
	for i in range(3):
		var r := 34.0 + float(i) * 26.0 + glow * 30.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 28, col, 5.0 - float(i))
	draw_circle(Vector2.ZERO, 16.0 + glow * 8.0 * flash_scale, col)
	if _telegraphing:
		_draw_hatch(Vector2.ZERO, 56.0, Color(paper.r, paper.g, paper.b, 0.46))
	var font := Presentation.theme.font_for(&"annotation")
	if font != null:
		draw_string(font, Vector2(-38.0, 78.0), "MAGNET",
				HORIZONTAL_ALIGNMENT_CENTER, 76.0, 14, paper)
	_draw_state_cue(Vector2(0.0, -62.0), 11.0, token, Feel.COL_DIRTY)
