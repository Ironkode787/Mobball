class_name CommissionChairs
extends RefCounted
## THE FIVE FAMILIES (docs/02 §2 R6). Five chair standups around the long table upstairs, and
## the only progress bar in this game that is measured in *Nights* rather than in seconds:
## a chair you knock down is claimed for the career and stays claimed.
##
## That is the whole reason the room exists. Every other bank on this table re-arms and asks
## you to do it again; the Penthouse asks you to do it five times, once each, across as many
## Nights as it takes. Which is what "the Commission endgame" means — you are not farming the
## room, you are taking it over.
##
## Claiming all five and then putting the whole bank down in one pass lights **ELECTIONS**
## (docs/05 §8): the city is yours to run once the families are seated.
##
## Pure state, no clock. The table reports `chair_taken` / `chairs_completed`; `Game` pays the
## ☆ and lights the campaign.

const CHAIRS := 5
## A chair is a career milestone, so it pays ☆ once — the first time that seat is taken. The
## fifth one pays the room.
const RESPECT_PER_CHAIR := 5
const RESPECT_ALL_CHAIRS := 25

## Chair index -> true, for every seat claimed. Saved: this is the career's, not the Night's.
var claimed: Dictionary = {}
## How many times the whole bank has gone down in one pass. Saved for the rap sheet.
var sweeps: int = 0
var night_claimed: int = 0
var night_taken: int = 0


func begin_night() -> void:
	night_claimed = 0
	night_taken = 0


## A chair went down. True if that seat had never been taken before — the ☆ hang off this.
func on_chair_taken(index: int) -> bool:
	if index < 0 or index >= CHAIRS:
		return false
	night_taken += 1
	if claimed.has(index):
		return false
	claimed[index] = true
	night_claimed += 1
	return true


## The whole bank in one pass. True when it is also the moment the room is finally yours —
## every seat claimed AND swept — which is what lights the campaign.
func on_chairs_completed() -> bool:
	sweeps += 1
	return all_claimed()


func claimed_count() -> int:
	return claimed.size()


func all_claimed() -> bool:
	return claimed.size() >= CHAIRS


## Seats still to take, in order, for The Count and the HUD.
func open_seats() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for i in CHAIRS:
		if not claimed.has(i):
			out.append(i)
	return out


func night_summary() -> Dictionary:
	return {
		"claimed": claimed_count(),
		"chairs": CHAIRS,
		"tonight": night_claimed,
		"taken": night_taken,
	}


func to_dict() -> Dictionary:
	var seats: Array = []
	for i in CHAIRS:
		if claimed.has(i):
			seats.append(i)
	return {"claimed": seats, "sweeps": sweeps}


func from_dict(d: Dictionary) -> void:
	claimed.clear()
	sweeps = 0
	if d == null or d.is_empty():
		return
	for raw: Variant in d.get("claimed", []):
		var i := int(raw)
		if i >= 0 and i < CHAIRS:
			claimed[i] = true
	sweeps = maxi(int(d.get("sweeps", 0)), 0)
	begin_night()
