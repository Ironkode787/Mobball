class_name Combo
extends RefCounted
## "Clean Work" — chaining hits of *different* switch groups inside a 4 s window
## (docs/01 §6, specs/m1-hook.md Lane 1). Chain n multiplies the hit that made it by
## ×1.5^(n−1), capped at ×8.
##
## Pure logic and clock-fed (`tick`), so the sims own the timeline. Hitting a group that
## is already in the chain does not extend it — it starts a fresh chain from that hit,
## which is what makes "different shots" the skill rather than "any shot, fast".

signal changed(count: int)
## Fires the first time a chain reaches RESPECT_AT (☆2, docs/03 §5).
signal respect_earned(stars: int)

const WINDOW := 4.0
const STEP := 1.5
const CAP := 8.0
const RESPECT_AT := 3
const RESPECT_STARS := 2

var count: int = 0

var _groups: Dictionary = {}
var _timer: float = 0.0
var _scored_respect: bool = false


## Register a scoring hit and return the multiplier that hit earns.
func on_hit(group: StringName) -> float:
	if count > 0 and (_timer <= 0.0 or _groups.has(group)):
		# Replaced in the same beat rather than dropped: no changed(0) flicker.
		_clear()
		count = 0
	_groups[group] = true
	_timer = WINDOW
	_set_count(count + 1)
	if count >= RESPECT_AT and not _scored_respect:
		_scored_respect = true
		respect_earned.emit(RESPECT_STARS)
	return multiplier()


## The multiplier the current chain is paying.
func multiplier() -> float:
	if count <= 1:
		return 1.0
	return minf(pow(STEP, float(count - 1)), CAP)


## Seconds left before the chain lapses (0 when there is no chain).
func time_left() -> float:
	return maxf(_timer, 0.0)


func tick(delta: float) -> void:
	if count <= 0 or delta <= 0.0:
		return
	_timer -= delta
	if _timer <= 0.0:
		_clear()
		_set_count(0)


## Between guys and between Nights the chain is gone, not just expired.
func reset() -> void:
	_clear()
	_set_count(0)


func _clear() -> void:
	_groups.clear()
	_timer = 0.0
	_scored_respect = false


func _set_count(v: int) -> void:
	if count == v:
		return
	count = v
	changed.emit(count)
