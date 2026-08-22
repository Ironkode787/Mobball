class_name Offline
extends RefCounted
## Away earnings — "the Safe" (docs/03-ECONOMY.md §6, policy in docs/09-TECH.md §9).
##
## Static, pure, clock-free: the caller passes both timestamps, this file never reads
## the wall clock. Policy, straight out of docs/09 §9: **no punishment for clock
## weirdness**. A negative or nonsense delta is a no-op, never a penalty — this is a
## single-player game and the anti-cheat arms race is not worth one line of code.

## Idle income accrued over `elapsed_sec`, clamped by the Safe's capacity.
##
## `safe_cap` null means uncapped; a ZERO cap means a zero-capacity safe and yields
## zero. Negative / NaN / INF `elapsed_sec` yields zero, as does a non-positive rate.
static func accrue(rate_per_sec: BigMoney, elapsed_sec: float, safe_cap: BigMoney = null) -> BigMoney:
	if rate_per_sec == null or not rate_per_sec.is_positive():
		return BigMoney.zero()
	if not is_finite(elapsed_sec) or elapsed_sec <= 0.0:
		return BigMoney.zero()
	var raw := rate_per_sec.mul(elapsed_sec)
	if safe_cap == null:
		return raw
	if not safe_cap.is_positive():
		return BigMoney.zero()
	return BigMoney.min_of(raw, safe_cap)


## Seconds between two wall-clock stamps, clamped at zero (docs/09 §9: negative deltas
## just no-op — a phone that travelled backwards in time is not a cheater).
static func elapsed_clamped(now_unix: float, last_seen_unix: float) -> float:
	if not is_finite(now_unix) or not is_finite(last_seen_unix):
		return 0.0
	return maxf(now_unix - last_seen_unix, 0.0)


## Seconds of absence before the Safe is full — the "come back in 2h" number the HUD
## wants. INF when the rate is zero (it never fills) or the cap is uncapped.
static func seconds_to_full(rate_per_sec: BigMoney, safe_cap: BigMoney) -> float:
	if safe_cap == null:
		return INF
	if rate_per_sec == null or not rate_per_sec.is_positive():
		return INF
	if not safe_cap.is_positive():
		return 0.0
	return safe_cap.ratio_to(rate_per_sec)


## Fraction of the Safe filled after `elapsed_sec`, 0..1 — for the fill gauge.
static func fill_fraction(rate_per_sec: BigMoney, elapsed_sec: float, safe_cap: BigMoney) -> float:
	if safe_cap == null or not safe_cap.is_positive():
		return 0.0
	var got := accrue(rate_per_sec, elapsed_sec, safe_cap)
	return clampf(got.ratio_to(safe_cap), 0.0, 1.0)
