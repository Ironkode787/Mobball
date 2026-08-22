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
## Fires when a chain reaches a RESPECT_TIERS length for the FIRST time this Night.
## Balance-sim ruling: per-chain ☆ made combos 95-98% of all career Respect, so rank
## tracked shot volume instead of skill. Once per Night per tier, ranks belong to Jobs.
signal respect_earned(stars: int)

const WINDOW := 4.0
const STEP := 1.5
const CAP := 8.0
## chain length reached -> ☆ awarded, first time each per Night (docs/03 §5).
const RESPECT_TIERS := {3: 2, 6: 5}

var count: int = 0

var _groups: Dictionary = {}
var _timer: float = 0.0
var _night_scored: Dictionary = {}


## Register a scoring hit and return the multiplier that hit earns.
func on_hit(group: StringName) -> float:
	if count > 0 and (_timer <= 0.0 or _groups.has(group)):
		# Replaced in the same beat rather than dropped: no changed(0) flicker.
		_clear()
		count = 0
	_groups[group] = true
	_timer = WINDOW
	_set_count(count + 1)
	var stars := int(RESPECT_TIERS.get(count, 0))
	if stars > 0 and not _night_scored.has(count):
		_night_scored[count] = true
		respect_earned.emit(stars)
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


## A new Night re-arms the once-per-Night ☆ tiers. Called by Game.start_night().
func reset_night() -> void:
	reset()
	_night_scored.clear()


func _clear() -> void:
	_groups.clear()
	_timer = 0.0


func _set_count(v: int) -> void:
	if count == v:
		return
	count = v
	changed.emit(count)
