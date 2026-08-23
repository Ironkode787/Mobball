class_name SitDown
extends RefCounted
## THE SIT-DOWN (docs/02 §2 R6). The Penthouse saucer holds the ball for a beat and the room
## negotiates: for sixty seconds the Heat meter does not move at all, and the block opens up —
## every storefront re-arms so the collection round is there for the taking.
##
## The freeze is a real freeze, not a decay bonus: while a negotiation is running `Game` does
## not tick the meter and does not feed it earnings, so money made in that minute never warms
## it, even later. That is the point of the room — it is the calmest place on the table and
## the most dangerous, because the meter you stopped watching is exactly where you left it.
##
## Pure logic on a fed clock. The table reports `sitdown_entered`, the NightController feeds
## the clock and asks the table to re-arm the block, and `Game` reads `active` on the one
## question it decides.

const SECONDS := 60.0
## The Silent Don's spoil (docs/05 §6 "The Quiet Word") stretches it to 90 s. His fight is
## BOSS-2's; the id is here so the day it lands the room already honours it.
const SPOIL_QUIET_WORD := "spoil.the_quiet_word"
const SECONDS_QUIET_WORD := 90.0

var active: bool = false
var time_left: float = 0.0
var sitdowns_total: int = 0
var night_sitdowns: int = 0


func begin_night() -> void:
	active = false
	time_left = 0.0
	night_sitdowns = 0


## Start (or restart — walking back into the saucer refreshes the room) a negotiation.
## Returns true if this call actually opened one.
func begin(seconds: float = SECONDS) -> bool:
	var was := active
	active = true
	time_left = maxf(seconds, 0.0)
	if was:
		return false
	sitdowns_total += 1
	night_sitdowns += 1
	return true


## True on the tick the negotiation runs out.
func tick(delta: float) -> bool:
	if not active or delta <= 0.0:
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	active = false
	time_left = 0.0
	return true


## The Night is over / the room was torn down: no freeze outlives its Night.
func abort() -> void:
	active = false
	time_left = 0.0


func night_summary() -> Dictionary:
	return {"sitdowns": night_sitdowns}


func to_dict() -> Dictionary:
	return {"total": sitdowns_total}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	sitdowns_total = maxi(int(d.get("total", 0)), 0)
	begin_night()
