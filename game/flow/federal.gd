class_name FederalHeat
extends RefCounted
## FEDERAL HEAT (docs/03 §4, docs/05 §9). The blue stage of the meter, 100 to 200, and the
## only pressure in this game that does not come from playing badly: it comes from being big.
##
## "You're too big to ignore" is implemented literally — the meter accrues per NIGHT, per
## owned Ledger node past the fortieth, and nothing else moves it. No shot warms it, no bribe
## cools it, and laying low does not help. It is a soft timer toward prestige (docs/06), which
## is exactly why it must never be a wall: it accrues at a rate an empire chooses by being an
## empire, and the answer to it is the RICO raid, which you can win.
##
## The red meter underneath is untouched. `HeatMeter` latches its ordinary raid at 100 and
## that is the economy core's business (frozen); this is a second number kept alongside it,
## displayed as 100 + `value` so the player reads one dial with two stages.

## The rank the FBI starts caring (docs/02 §1 R7 — Kingpin).
const RANK := 7
## Nodes you are allowed to own before anybody notices.
const NODE_FLOOR := 40
## Per owned node past the floor, per Night.
const PER_NODE_PER_NIGHT := 0.5
## The blue stage is a hundred points wide: `value` 0 is meter 100, `value` 100 is meter 200.
const MAX := 100.0
const METER_BASE := 100.0
## At the top of the stage the RICO raid replaces the next Night (docs/05 §9).
const RICO_AT := 100.0
## Surviving it takes a hundred off the meter — the whole stage.
const SURVIVE_DROP := 100.0
## Losing it does not: the case is still open. It buys a few Nights, not a reprieve, and The
## Count starts suggesting the train (docs/06 §1).
const FAIL_DROP := 25.0

var enabled: bool = false
var value: float = 0.0
## The next Night IS the raid. Latched, saved, and cleared only by running it.
var rico_pending: bool = false
var raids_survived: int = 0
var raids_lost: int = 0
## What the last roll call added — The Count's "the file got thicker" line.
var last_gain: float = 0.0


## R7 opens the second stage. Returns true the first time it does.
func enable(on: bool) -> bool:
	if on == enabled:
		return false
	enabled = on
	return on


## Roll call. `nodes` is how much empire there is to notice. Returns what it added.
func night_tick(nodes: int) -> float:
	last_gain = 0.0
	if not enabled or rico_pending:
		return 0.0
	var over := maxi(nodes - NODE_FLOOR, 0)
	if over <= 0:
		return 0.0
	last_gain = float(over) * PER_NODE_PER_NIGHT
	value = clampf(value + last_gain, 0.0, MAX)
	if value >= RICO_AT:
		rico_pending = true
	return last_gain


## Direct additions (a failed heist that made the papers, a future subpoena target). Kept
## because the stage has to be able to move for a reason other than size the day one exists.
func add(amount: float) -> void:
	if not enabled or amount <= 0.0:
		return
	value = clampf(value + amount, 0.0, MAX)
	if value >= RICO_AT:
		rico_pending = true


## The number the HUD draws: one dial, two stages.
func meter_value() -> float:
	return METER_BASE + value


func fraction() -> float:
	return clampf(value / MAX, 0.0, 1.0)


## Nights of accrual left before the Feds come, at the current empire size. -1 when the
## empire is small enough that they never will.
func nights_to_rico(nodes: int) -> int:
	var over := maxi(nodes - NODE_FLOOR, 0)
	if not enabled or over <= 0:
		return -1
	if rico_pending:
		return 0
	var per := float(over) * PER_NODE_PER_NIGHT
	return int(ceil((RICO_AT - value) / per))


## The raid was run. Survive and the stage empties; lose and the case stays open.
func resolve_rico(survived: bool) -> void:
	rico_pending = false
	if survived:
		raids_survived += 1
		value = maxf(value - SURVIVE_DROP, 0.0)
	else:
		raids_lost += 1
		value = maxf(value - FAIL_DROP, 0.0)


## A new city is a cold trail (docs/06 §1).
func reset() -> void:
	enabled = false
	value = 0.0
	rico_pending = false
	last_gain = 0.0


func night_summary() -> Dictionary:
	return {
		"enabled": enabled,
		"value": value,
		"meter": meter_value(),
		"gain": last_gain,
		"rico": rico_pending,
	}


func to_dict() -> Dictionary:
	return {
		"enabled": enabled,
		"value": value,
		"pending": rico_pending,
		"survived": raids_survived,
		"lost": raids_lost,
	}


func from_dict(d: Dictionary) -> void:
	enabled = false
	value = 0.0
	rico_pending = false
	raids_survived = 0
	raids_lost = 0
	last_gain = 0.0
	if d == null or d.is_empty():
		return
	enabled = bool(d.get("enabled", false))
	value = clampf(float(d.get("value", 0.0)), 0.0, MAX)
	rico_pending = bool(d.get("pending", false))
	raids_survived = maxi(int(d.get("survived", 0)), 0)
	raids_lost = maxi(int(d.get("lost", 0)), 0)
