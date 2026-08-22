class_name HeatMeter
extends RefCounted
## The Heat dial (docs/03-ECONOMY.md §4): one number that makes success dangerous.
##
## Time is fed in, never read — `tick(delta)` is the only clock, so tests and the
## headless balance sim own the timeline. No Node, no autoload, no `get_tree()`.
##
## ## The windowed-earn approximation
##
## Design says "+1 heat per $50k dirty earned within 10s". A literal ring buffer of
## (timestamp, amount) samples is O(window) per tick and allocates per earn event;
## this meter instead keeps ONE float — `_window_units`, the earnings still "inside"
## the window, measured in rank-scale units — and decays it exponentially with
## τ = HEAT_WINDOW_SEC:
##
##     u(t) = u₀·e^(−t/τ)         heat credited over dt: HEAT_PER_UNIT·u₀·(1 − e^(−dt/τ))
##
## Substituting the exponential kernel for the box-car window keeps the *total* heat
## per unit earned exactly right (∫₀^∞ u₀·e^(−t/τ)/τ dt = u₀, i.e. exactly +1 heat per
## rank_scale earned, no matter how the earnings are spread), and only changes *when*
## it lands: a burst ramps the meter over the following ~10 s instead of spiking it
## instantly. The integration above is closed-form, so a 5000-second sim step credits
## exactly what 5000 one-second steps would — no step-size drift, no ring buffer, O(1).
##
## What "velocity-based" then means mechanically: gain arrives smeared over ~10 s while
## calm decay (−0.5/s after 8 s of quiet) eats it, so a trickle of earnings never
## outruns the decay and a burst does. That is the intended pressure curve.

## Emitted whenever the value actually changes (already clamped).
signal heat_changed(value: float)
## 0..4, see Rates.BAND_THRESHOLDS.
signal band_changed(band: int)
## Fires ONCE when heat reaches 100; latched until `reset_after_raid()`.
signal raid_triggered

## Ceiling for `_window_units`, so one absurd payout cannot poison the meter with INF.
const MAX_WINDOW_UNITS := 1.0e9
const _WINDOW_EPSILON := 1.0e-9

## Multiplies heat GAINS (loud guys/rackets add %, docs/03 §4).
var gain_scale: float = 1.0
## Multiplies passive calm decay (Lawyer retainer improves it).
var decay_scale: float = 1.0

var _value: float = 0.0
var _band: int = 0
var _federal: bool = false
var _raid_latched: bool = false
var _window_units: float = 0.0
var _calm_timer: float = 0.0

## Current heat. Assigning clamps to [0, max_value()] and emits the signals — there is
## no way to move this meter without the band/raid bookkeeping running.
var value: float:
	get:
		return _value
	set(v):
		_set_heat(v)

## Federal stage (R7): raises the ceiling to 200. The raid at 100 still fires.
var federal_enabled: bool:
	get:
		return _federal
	set(v):
		_federal = v
		_set_heat(_value)


func _init(start_value: float = 0.0) -> void:
	_set_heat(start_value)


# --- clock --------------------------------------------------------------------


## The only clock. Credits the decaying earn window, then applies calm decay for
## whatever part of `delta` falls past the 8 s grace — so one big step and many small
## steps land on the same number.
func tick(delta: float) -> void:
	if delta <= 0.0 or not is_finite(delta):
		return

	if _window_units > 0.0:
		var f := exp(-delta / Rates.HEAT_WINDOW_SEC)
		var gained := Rates.HEAT_PER_UNIT * _window_units * (1.0 - f) * maxf(gain_scale, 0.0)
		_window_units *= f
		if _window_units < _WINDOW_EPSILON:
			_window_units = 0.0
		if gained > 0.0:
			_set_heat(_value + gained)

	_calm_timer += delta
	var calm_seconds := clampf(_calm_timer - Rates.HEAT_CALM_GRACE, 0.0, delta)
	if calm_seconds > 0.0 and _value > 0.0:
		_set_heat(_value - Rates.HEAT_DECAY_PER_SEC * maxf(decay_scale, 0.0) * calm_seconds)


# --- gains --------------------------------------------------------------------


## Feed every dirty payout through here. `rank_scale` is the dirty-per-heat scale for
## the player's rank (see [method Rates.rank_scale]); the heat lands over the next
## ~10 s, not instantly. Non-positive or null arguments are ignored.
func on_dirty_earned(amount: BigMoney, rank_scale: BigMoney) -> void:
	if amount == null or rank_scale == null:
		return
	if not amount.is_positive() or not rank_scale.is_positive():
		return
	var units := amount.ratio_to(rank_scale)
	if is_inf(units):
		units = MAX_WINDOW_UNITS
	elif not is_finite(units) or units <= 0.0:
		return
	_window_units = minf(_window_units + units, MAX_WINDOW_UNITS)
	_calm_timer = 0.0


## Loud acts: +5–15 (smuggling run, briefcase setup, failed heist step). Scaled by
## `gain_scale` and it breaks the calm grace, so decay restarts its 8 s countdown.
func add_flat(amount: float) -> void:
	if amount <= 0.0 or not is_finite(amount):
		return
	_calm_timer = 0.0
	_set_heat(_value + amount * maxf(gain_scale, 0.0))


# --- reductions ---------------------------------------------------------------


## Direct reduction, floored at 0. Not affected by `decay_scale` (that is passive
## decay only) and does not touch the calm timer.
func reduce(amount: float) -> void:
	if amount <= 0.0 or not is_finite(amount):
		return
	_set_heat(_value - amount)


## Beat Cop bribe shot: −20 heat, floored at 0. The dirty cost is the caller's problem
## — ask `bribe_cost()` for it.
func bribe() -> void:
	reduce(Rates.BRIBE_HEAT)


## Dirty cost of the next bribe this Night (escalates per use).
func bribe_cost(uses_this_night: int) -> BigMoney:
	return Rates.bribe_cost(uses_this_night)


## "Close up shop" for a Night: −10 heat.
func lay_low_night() -> void:
	reduce(Rates.LAY_LOW_HEAT)


# --- raid ---------------------------------------------------------------------


## True once `raid_triggered` has fired and before `reset_after_raid()`.
func is_raid_pending() -> bool:
	return _raid_latched


## Survive → 30 ("Beat the Rap"), bust → 0. Clears the latch and the earn window so
## the meter does not immediately re-fire off the pre-raid burst.
func reset_after_raid(survived: bool) -> void:
	_raid_latched = false
	_window_units = 0.0
	_calm_timer = 0.0
	_set_heat(Rates.RAID_SURVIVE_HEAT if survived else Rates.RAID_BUST_HEAT)


## Fresh city / new game (docs/06: prestige means a cold trail).
func reset() -> void:
	_raid_latched = false
	_window_units = 0.0
	_calm_timer = 0.0
	_set_heat(0.0)


# --- queries ------------------------------------------------------------------


## 0..4 per the docs/03 §4 table; 4 is the raid.
func band() -> int:
	return _band


## Multiplier on ALL dirty at the current band: 1.0 / 1.5 / 2.5 / 4.0.
func multiplier() -> float:
	return Rates.multiplier_for_band(_band)


func max_value() -> float:
	return Rates.HEAT_FEDERAL_MAX if _federal else Rates.HEAT_MAX


## Seconds since the last gain event (earn or loud act).
func calm_seconds() -> float:
	return _calm_timer


## True once the calm grace has elapsed and decay is running.
func is_calm() -> bool:
	return _calm_timer >= Rates.HEAT_CALM_GRACE


## Earnings still inside the rolling window, in rank-scale units. Diagnostic — this is
## the pending heat the meter has not credited yet.
func pending_units() -> float:
	return _window_units


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"value": _value,
		"federal": _federal,
		"raid_latched": _raid_latched,
		"window_units": _window_units,
		"calm_timer": _calm_timer,
	}


func from_dict(d: Dictionary) -> void:
	if d == null:
		return
	_federal = bool(d.get("federal", false))
	_raid_latched = bool(d.get("raid_latched", false))
	_window_units = clampf(float(d.get("window_units", 0.0)), 0.0, MAX_WINDOW_UNITS)
	_calm_timer = maxf(float(d.get("calm_timer", 0.0)), 0.0)
	_set_heat(float(d.get("value", 0.0)))


# --- internals ----------------------------------------------------------------


func _set_heat(v: float) -> void:
	if is_nan(v):
		return
	var clamped := clampf(v, 0.0, max_value())
	if clamped != _value:
		_value = clamped
		heat_changed.emit(_value)
	var b := Rates.band_for(_value)
	if b != _band:
		_band = b
		band_changed.emit(_band)
	if _value >= Rates.RAID_THRESHOLD and not _raid_latched:
		_raid_latched = true
		raid_triggered.emit()
