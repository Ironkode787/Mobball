class_name FamilyMeeting
extends RefCounted
## FAMILY MEETING — the two-ball multiball (specs/m2-content.md §4, docs/01 §4 "the crew out
## together"). Pure state: what lights it, whether it is running, and what the growing
## back-room jackpot is worth. The NightController owns the balls and the table; `Game` owns
## the money. This owns the rules.
##
## The second ball is a REAL guy off the Bench, not a spare sphere — if he drains he is
## pinched like anyone, which is the whole reason multiball has stakes here.

## ALL dirty doubles while two guys are working (spec §4).
const DIRTY_MULT := 2.0
## THE FAMILY REUNION (docs/02 §2 R7): at R7, with Empire lit once tonight, the back room
## puts the whole crew on the table instead of one spare man. Every Meeting rule scales with
## the count — five guys working is ×5 on all dirty, because five guys working IS the mode.
const REUNION_GUYS := 5
## Graces are staggered so five balls do not all come off the save window on the same frame,
## which is how a Reunion turns into an empty table in one second.
const REUNION_SAVE_STAGGER := 1.6
## Grace after the second ball joins. Spec §4 gives it to BOTH balls: the player did not ask
## for the extra ball to arrive mid-shot.
const BALL_SAVE_SECONDS := 8.0
## Back-room re-entry during the Meeting: 4 minutes of the empire's idle rate, clean, and
## half as much again every time.
const JACKPOT_MINUTES := 4.0
const JACKPOT_GROWTH := 1.5
## Two Jackpots on the slots, or one perfect Collection Round, lights the back room.
const JACKPOTS_TO_LIGHT := 2

## Lit and waiting for a back-room shot. Persisted: a Meeting you lit and did not spend is
## still owed to you next Night.
var lit: bool = false
var active: bool = false
## The second guy, while the Meeting runs.
var guy: Dictionary = {}
## Everybody out there for this Meeting, the guy on the primary ball included. One entry for
## an ordinary two-ball Meeting (the spare man); four for a Reunion.
var extra_guys: Array[Dictionary] = []
## How many guys the Meeting was called for: 2 normally, REUNION_GUYS for a Reunion.
var size: int = 2
var reunions_total: int = 0
var night_reunions: int = 0
## Casino Jackpots so far tonight (the lighting condition re-arms every Night).
var jackpots_tonight: int = 0
## Back-room jackpots paid inside the CURRENT meeting — the growth exponent.
var payouts: int = 0

var meetings_total: int = 0
var jackpots_total: int = 0
var jackpot_paid_total: BigMoney = BigMoney.zero()
var night_meetings: int = 0
var night_jackpots: int = 0
var night_paid: BigMoney = BigMoney.zero()


func begin_night() -> void:
	active = false
	guy = {}
	extra_guys = []
	size = 2
	payouts = 0
	jackpots_tonight = 0
	night_meetings = 0
	night_jackpots = 0
	night_reunions = 0
	night_paid = BigMoney.zero()


# =================================================================== lighting =====


## A slots Jackpot landed. True if this is the one that lit the back room.
func note_casino_jackpot() -> bool:
	jackpots_tonight += 1
	if lit or jackpots_tonight < JACKPOTS_TO_LIGHT:
		return false
	lit = true
	return true


## A Collection Round was completed. One perfect round is worth two Jackpots (docs/05 §3).
func note_collection_round() -> bool:
	if lit:
		return false
	lit = true
	return true


## `backroom_entered` fired: may the Meeting start? The deck has to be bought — the back room
## is a piece of the Club, and a Meeting without a Club is a Meeting in the street.
func can_start(club_owned: bool) -> bool:
	return lit and not active and club_owned


# =================================================================== the meeting =====


func start(second_guy: Dictionary) -> void:
	start_with([second_guy])


## The general form: every guy who joins the table for this Meeting. One of them is an
## ordinary Family Meeting; four of them is the Reunion (docs/02 §2 R7).
func start_with(guys: Array) -> void:
	active = true
	lit = false
	payouts = 0
	extra_guys = []
	for g: Variant in guys:
		if g is Dictionary and not (g as Dictionary).is_empty():
			extra_guys.append((g as Dictionary).duplicate())
	guy = extra_guys[0] if not extra_guys.is_empty() else {}
	# The man already on the table is working too, so the crew is one more than the joiners.
	size = maxi(extra_guys.size() + 1, 2)
	meetings_total += 1
	night_meetings += 1
	if size >= REUNION_GUYS:
		reunions_total += 1
		night_reunions += 1


func is_reunion() -> bool:
	return active and size >= REUNION_GUYS


## One ball left: the crew is not out together any more.
func end() -> void:
	active = false
	guy = {}
	extra_guys = []
	size = 2
	payouts = 0


## The multiplier `Game.earn_switch` folds into every dirty payout. Two guys is the shipped
## ×2; a Reunion is worth exactly as many guys as are out there.
func dirty_multiplier() -> float:
	return maxf(float(size), DIRTY_MULT) if active else 1.0


## What the next back-room re-entry is worth, without taking it.
func jackpot_value(idle_rate: BigMoney) -> BigMoney:
	if not active or idle_rate == null or not idle_rate.is_positive():
		return BigMoney.zero()
	return idle_rate.mul(JACKPOT_MINUTES * 60.0 * pow(JACKPOT_GROWTH, float(payouts)))


## Take it: returns the value and grows the next one.
func take_jackpot(idle_rate: BigMoney) -> BigMoney:
	var v := jackpot_value(idle_rate)
	if not v.is_positive():
		return BigMoney.zero()
	payouts += 1
	jackpots_total += 1
	night_jackpots += 1
	jackpot_paid_total = jackpot_paid_total.add(v)
	night_paid = night_paid.add(v)
	return v


func night_summary() -> Dictionary:
	return {
		"lit": lit,
		"meetings": night_meetings,
		"jackpots": night_jackpots,
		"paid": night_paid.copy(),
		"casino_jackpots": jackpots_tonight,
		"reunions": night_reunions,
	}


# ================================================================ serialization =====


func to_dict() -> Dictionary:
	return {
		"lit": lit,
		"meetings": meetings_total,
		"jackpots": jackpots_total,
		"paid": jackpot_paid_total.to_dict(),
		"reunions": reunions_total,
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	lit = bool(d.get("lit", false))
	meetings_total = maxi(int(d.get("meetings", 0)), 0)
	jackpots_total = maxi(int(d.get("jackpots", 0)), 0)
	jackpot_paid_total = BigMoney.from_dict(d.get("paid", {}))
	reunions_total = maxi(int(d.get("reunions", 0)), 0)
	begin_night()
