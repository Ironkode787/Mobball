class_name EmpireMode
extends RefCounted
## EMPIRE MODE (docs/02 §2 R7). The crown, and the only thing on this table that asks for the
## whole machine in one breath: **the City Hall Circuit** — the full-table orbit, the
## staircase, the Penthouse gate and the dome loop, chained. Close it and the city is yours
## for sixty seconds: every feature lit, every stem playing, ×10 on everything dirty, and a
## clean share of the whole take paid out at the end like a dividend.
##
## Two rules make the circuit a circuit rather than a checklist:
##
##   * **In order.** A leg only counts if it follows the one before it. Taking the dome first
##     is a lovely shot and it is worth nothing toward the crown.
##   * **On the clock.** Each leg has to arrive inside `LEG_WINDOW` of the last, so the lap
##     stays one continuous piece of play instead of four errands run over a Night.
##
## Falling off the chain costs the chain and nothing else — no ball, no money, no Heat. The
## hardest shot in the game is allowed to be free to miss (P4: the skill check is the gate).
##
## Pure logic on a fed clock. The NightController feeds it the table's own signals and
## `Game` pays the dividend.

## The circuit, in the only order it can be flown.
const LEGS: Array[StringName] = [&"orbit", &"staircase", &"penthouse", &"dome"]
const SECONDS := 60.0
## docs/02 §2 R7: ×10 on everything.
const DIRTY_MULT := 10.0
## The dividend at the end: this much of what the mode earned, again, in clean. Empire Mode
## is the one moment the empire pays like an empire instead of like a racket.
const CLEAN_SHARE := 0.5
## How long a leg may take to follow the one before it.
const LEG_WINDOW := 25.0
## ☆ for closing the circuit — a career milestone, paid every time because the shot is that
## hard (docs/02 §2 R7: re-lightable).
const RESPECT_CIRCUIT := 15

var active: bool = false
var time_left: float = 0.0
## How many legs of the circuit are in hand, 0..LEGS.size().
var leg: int = 0
var leg_left: float = 0.0
## Dirty booked while the mode was running — the dividend is a share of this.
var earned: BigMoney = BigMoney.zero()

## Empire has been lit at least once tonight. The 5-ball Family Reunion hangs off this
## (docs/02 §2 R7), so it stays true after the mode ends.
var lit_tonight: bool = false
var runs_tonight: int = 0
var runs_total: int = 0
var circuits_total: int = 0
var paid_total: BigMoney = BigMoney.zero()
var night_paid: BigMoney = BigMoney.zero()


func begin_night() -> void:
	active = false
	time_left = 0.0
	leg = 0
	leg_left = 0.0
	earned = BigMoney.zero()
	lit_tonight = false
	runs_tonight = 0
	night_paid = BigMoney.zero()


# ==================================================================== the circuit =====


## The next leg the circuit wants.
func next_leg() -> StringName:
	return LEGS[leg] if leg < LEGS.size() else &""


## One leg of the circuit was flown. True when that closes it — the caller lights the mode.
## Out of order, or too late, and the lap starts again from this shot if it was the first leg.
func on_leg(id: StringName) -> bool:
	if active:
		return false
	if id == next_leg():
		leg += 1
		leg_left = LEG_WINDOW
		if leg < LEGS.size():
			return false
		leg = 0
		leg_left = 0.0
		circuits_total += 1
		return true
	# A shot that is not the one wanted breaks the chain. If it happens to be the FIRST leg,
	# it is not a mistake, it is a new lap — which is what a full-table orbit always is.
	leg = 1 if id == LEGS[0] else 0
	leg_left = LEG_WINDOW if leg > 0 else 0.0
	return false


## True on the tick the mode ends (the caller pays the dividend then).
func tick(delta: float) -> bool:
	if delta <= 0.0:
		return false
	if not active:
		if leg > 0:
			leg_left -= delta
			if leg_left <= 0.0:
				leg = 0
				leg_left = 0.0
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	active = false
	time_left = 0.0
	return true


# ====================================================================== the mode =====


func begin() -> void:
	active = true
	lit_tonight = true
	time_left = SECONDS
	leg = 0
	leg_left = 0.0
	earned = BigMoney.zero()
	runs_tonight += 1
	runs_total += 1


## The Night ended around it.
func abort() -> void:
	active = false
	time_left = 0.0


## Everything dirty is worth ten times as much while the city is yours.
func dirty_multiplier() -> float:
	return DIRTY_MULT if active else 1.0


## Book dirty earned inside the mode. Called from the one money path, so the dividend is
## measured on money that actually landed rather than on money that was promised.
func book_earned(amount: BigMoney) -> void:
	if not active or amount == null or not amount.is_positive():
		return
	earned = earned.add(amount)


## The dividend: a clean share of what the sixty seconds made.
func dividend() -> BigMoney:
	if earned == null or not earned.is_positive():
		return BigMoney.zero()
	return earned.mul(CLEAN_SHARE)


func book_payout(paid: BigMoney) -> void:
	if paid == null or not paid.is_positive():
		return
	paid_total = paid_total.add(paid)
	night_paid = night_paid.add(paid)


func state() -> Dictionary:
	return {
		"active": active,
		"time_left": time_left,
		"leg": leg,
		"legs": LEGS.size(),
		"next": String(next_leg()),
		"lit_tonight": lit_tonight,
		"earned": earned.copy(),
	}


func night_summary() -> Dictionary:
	return {
		"runs": runs_tonight,
		"paid": night_paid.copy(),
		"lit": lit_tonight,
	}


func to_dict() -> Dictionary:
	return {
		"runs": runs_total,
		"circuits": circuits_total,
		"paid": paid_total.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	runs_total = maxi(int(d.get("runs", 0)), 0)
	circuits_total = maxi(int(d.get("circuits", 0)), 0)
	paid_total = BigMoney.from_dict(d.get("paid", {}))
	begin_night()
