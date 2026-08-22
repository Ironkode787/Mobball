class_name FlipperCurve
extends RefCounted
## Pure rotation-curve math for the flipper bat. Node-free so it can be unit tested.
##
## `progress` is 0 at rest, 1 at full extension. The up-stroke is ease-OUT (violent start,
## settling into the stop) which is what makes a solenoid read as a solenoid; the return is
## ease-IN (the bat falls back rather than snapping).


## Ease-out: f(0)=0, f(1)=1, f'(0) = ease (so `ease` is the opening speed multiplier).
static func ease_up(t: float, ease_power: float = Feel.FLIPPER_UP_EASE) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, maxf(ease_power, 0.01))


## Ease-in: f(0)=0, f(1)=1, slow start. Drives how much of the return stroke is done.
static func ease_down(t: float, ease_power: float = Feel.FLIPPER_DOWN_EASE) -> float:
	var x := clampf(t, 0.0, 1.0)
	return pow(x, maxf(ease_power, 0.01))


## Progress along the up-stroke after `elapsed` seconds.
static func up_progress(elapsed: float, duration: float = Feel.FLIPPER_UP_TIME) -> float:
	if duration <= 0.0:
		return 1.0
	return ease_up(elapsed / duration)


## Progress on the way back down, starting from `from_progress` (a release mid-stroke keeps
## its height and only spends the matching slice of the full return time).
static func down_progress(
	elapsed: float, from_progress: float, duration: float = Feel.FLIPPER_DOWN_TIME
) -> float:
	var span := maxf(duration * from_progress, 0.0001)
	return from_progress * (1.0 - ease_down(elapsed / span))


## Seconds still owed on a return stroke that began at `from_progress`.
static func down_remaining(elapsed: float, from_progress: float,
		duration: float = Feel.FLIPPER_DOWN_TIME) -> float:
	return maxf(duration * from_progress - elapsed, 0.0)


## Bat rotation for a progress value, in radians.
static func rotation_for(side: StringName, progress: float) -> float:
	var rest := Feel.flipper_rest_rotation(side)
	var up := Feel.flipper_up_rotation(side)
	return rest + (up - rest) * clampf(progress, 0.0, 1.0)
