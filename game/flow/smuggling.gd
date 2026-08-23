class_name SmugglingRun
extends RefCounted
## SMUGGLING RUNS (docs/02 §2 R5, specs/m3-fall-rise.md FLOW-3). The Docks' own mode: the
## ball comes in off the numbers lane with cargo standing on the quay, and the shipment is
## hot for forty seconds — clear all three container stacks inside the window and the load
## goes out.
##
## Pure logic on a fed clock, like every other mode in this lane. The yard reports (the table
## owns `docks_entered` / `container_stack_cleared` / `containers_state` / `cargo_shipped`),
## this owns the rules and the window, and `Game.smuggling_shipment()` owns the money.
##
## Two things make it a *run* rather than a drop bank with a timer:
##
##   * **The union, not the instant.** Stacks reset on their own six-second clock, so "all
##     three down at once" is not a shot anybody can take. The window remembers which stacks
##     went down inside it, and three distinct stacks is the shipment however they fell.
##   * **The truck.** Stacks 1 and 2 open onto the quay and the cargo ramp; stack 3 stands
##     over the water. So the greedy line is: break the two safe stacks, ride the ramp out
##     (`cargo_shipped` — the load reached the truck, and the shipment doubles), come back
##     in and take the third one knowing it drops you off the pier. The doubling is paid for
##     in drain risk, which is the whole design of the yard.

## Seconds the shipment stays hot once a run is armed.
const RUN_SECONDS := 40.0
## Stacks that make a load.
const STACKS := 3
## A shipment is a loud act (docs/03 §4: +5–15 per loud act).
const SHIPMENT_HEAT := 10.0
## "Got it to the truck": the cargo ramp crested inside the window.
const TRUCK_MULT := 2.0
## The load is priced the way every other big mode payout on this table is — minutes of the
## whole empire's idle rate (Casino.jackpot_value, FamilyMeeting.jackpot_value) — so it grows
## with the empire instead of needing a new constant per rank. It is then run through the
## smuggling group's own Ledger line (Night Shipments), because a shipment IS smuggling money.
const SHIPMENT_MINUTES := 6.0
## Floor for a career whose rackets idle at nothing yet: a shipment is never a shrug.
const SHIPMENT_FLOOR_MANTISSA := 2.5
const SHIPMENT_FLOOR_EXP := 4
## A lapsed run leaves the yard exactly as it was, so without a beat of quiet the next
## `docks_entered` would re-arm inside the same shot (CollectionRound.RETRIGGER_GAP's rule).
const RETRIGGER_GAP := 6.0

var active: bool = false
var time_left: float = 0.0
## The cargo ramp crested during this run — the load is on the truck and pays double.
var hot: bool = false

var runs_started: int = 0
var runs_shipped: int = 0
var night_runs: int = 0
var night_shipments: int = 0
var night_paid: BigMoney = BigMoney.zero()
var total_paid: BigMoney = BigMoney.zero()

var _cleared: Dictionary = {}
var _cooldown: float = 0.0


func begin_night() -> void:
	active = false
	time_left = 0.0
	hot = false
	_cleared.clear()
	_cooldown = 0.0
	night_runs = 0
	night_shipments = 0
	night_paid = BigMoney.zero()


# ==================================================================== the window =====


## The ball came through the dock mouth. A run arms only if there is cargo left to break —
## an empty quay is a lap of an empty yard, not a shipment. True if this armed one.
func on_docks_entered(stacks_standing: int) -> bool:
	if active or _cooldown > 0.0 or stacks_standing <= 0:
		return false
	active = true
	time_left = RUN_SECONDS
	hot = false
	_cleared.clear()
	runs_started += 1
	night_runs += 1
	return true


## One stack went down. True on the one that completes the load.
func on_stack_cleared(stack: int) -> bool:
	if not active or stack < 0:
		return false
	_cleared[stack] = true
	if _cleared.size() < STACKS:
		return false
	return _ship()


## The yard's whole cleared set, folded in — the same union from the other direction, so a
## table that only reports state (or a report that arrives while a stack is already down)
## still advances the run.
func on_containers_state(cleared_stacks: Array) -> bool:
	if not active or cleared_stacks == null:
		return false
	for s: Variant in cleared_stacks:
		_cleared[int(s)] = true
	if _cleared.size() < STACKS:
		return false
	return _ship()


## The hoist crested back onto the main field with the load on it.
func on_cargo_shipped() -> void:
	if active:
		hot = true


func cleared_count() -> int:
	return _cleared.size()


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	if _cooldown > 0.0:
		_cooldown = maxf(_cooldown - delta, 0.0)
	if not active:
		return
	time_left -= delta
	if time_left > 0.0:
		return
	_lapse()


## The ball is gone (drain, pier, the Night ended): the shipment is not going anywhere.
func abort() -> void:
	if active:
		_lapse()


func _lapse() -> void:
	active = false
	time_left = 0.0
	hot = false
	_cleared.clear()
	_cooldown = RETRIGGER_GAP


func _ship() -> bool:
	active = false
	time_left = 0.0
	_cleared.clear()
	_cooldown = RETRIGGER_GAP
	runs_shipped += 1
	night_shipments += 1
	return true


# ===================================================================== the money =====


## What a load is worth before the Ledger's smuggling line and before the truck doubling.
static func base_value(idle_rate: BigMoney) -> BigMoney:
	var floor_value := BigMoney.of(SHIPMENT_FLOOR_MANTISSA, SHIPMENT_FLOOR_EXP)
	if idle_rate == null or not idle_rate.is_positive():
		return floor_value
	return BigMoney.max_of(idle_rate.mul(SHIPMENT_MINUTES * 60.0), floor_value)


## Book what actually landed, so The Count's smuggling line is money, not a promise.
func book_payout(paid: BigMoney) -> void:
	if paid == null or not paid.is_positive():
		return
	night_paid = night_paid.add(paid)
	total_paid = total_paid.add(paid)


# ================================================================ serialization =====


func night_summary() -> Dictionary:
	return {
		"runs": night_runs,
		"shipments": night_shipments,
		"paid": night_paid.copy(),
	}


func to_dict() -> Dictionary:
	return {
		"runs": runs_started,
		"shipped": runs_shipped,
		"paid": total_paid.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	runs_started = maxi(int(d.get("runs", 0)), 0)
	runs_shipped = maxi(int(d.get("shipped", 0)), 0)
	total_paid = BigMoney.from_dict(d.get("paid", {}))
	begin_night()
