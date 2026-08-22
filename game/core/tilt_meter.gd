class_name TiltMeter
extends RefCounted
## The Inspector's suspicion, as pure logic (no nodes) so it unit tests cleanly.
## Each lean adds a warning; warnings bleed off one per `decay_seconds`. Going past
## `max_warnings` tilts, and a tilt only clears when the ball drains.

var warnings: int = 0
var tilted: bool = false

var max_warnings: int = Feel.TILT_MAX_WARNINGS
var decay_seconds: float = Feel.TILT_DECAY_SECONDS

var _decay_timer: float = 0.0


func _init(p_max: int = Feel.TILT_MAX_WARNINGS, p_decay: float = Feel.TILT_DECAY_SECONDS) -> void:
	max_warnings = p_max
	decay_seconds = p_decay


## Register one lean. Returns &"tilt", &"warning", or &"ignored" (already tilted).
func lean() -> StringName:
	if tilted:
		return &"ignored"
	warnings += 1
	_decay_timer = 0.0
	if warnings > max_warnings:
		tilted = true
		return &"tilt"
	return &"warning"


## Advance decay. Returns true when a warning actually bled off this step.
func advance(delta: float) -> bool:
	if tilted or warnings <= 0 or decay_seconds <= 0.0:
		return false
	_decay_timer += delta
	if _decay_timer >= decay_seconds:
		_decay_timer -= decay_seconds
		warnings -= 1
		return true
	return false


func reset() -> void:
	warnings = 0
	tilted = false
	_decay_timer = 0.0


## Fraction of the way to the next decay tick — for HUD/inspector art later.
func decay_fraction() -> float:
	if decay_seconds <= 0.0:
		return 0.0
	return clampf(_decay_timer / decay_seconds, 0.0, 1.0)
