class_name TheRat
extends RefCounted
## THE RAT (docs/05 §7). Somebody in the crew is talking, and the game will not tell you who.
##
## The arc is theatre built entirely out of systems that already exist, which is the design's
## own instruction — "pure theatre built from existing systems; the design cost is dialogue
## and a clue table". So:
##
##   * **The cost is real and it is visible in the wrong place.** While he is loose he skims
##     the wash. The laundromat total being short IS the first clue, and it is also the reason
##     to care. Nothing else on the table changes.
##   * **The clues are ordinary play.** A wash pass, a collection, a payphone ringing — three
##     things a Night does anyway. Each one narrows the three suspects by one name.
##   * **The accusation is a shot.** With the clues in hand the three top lanes ARE the three
##     suspects: rolling a lane points at a man. There is no menu and no confirm button, which
##     means the accusation costs a real shot and can be made by mistake, and both of those
##     are the point.
##
## Right, and he is flipped: the skim stops, the risk is gone, ☆50. Wrong, and the real rat
## makes one phone call — a half-strength raid, right now — and you may try again in three
## Nights. Never a wipe, never a lock (P5).
##
## Pure logic on a seeded RNG. `Game` pays and the NightController feeds it play.

## The arc opens here (docs/05 §7: "once The Rat specialist has been hired, or R6 reached,
## whichever first" — there is no Rat specialist in the shipped catalog, so it is the rank).
const ARC_RANK := 6
const SUSPECTS := 3
## Clues needed before an accusation may be made. Two of three narrows it to one name, so the
## third clue is the confirmation rather than the answer.
const CLUES_TO_ACCUSE := 2
## What he takes off every wash while he is loose.
const SKIM := 0.10
const RESPECT_CAUGHT := 50
## Nights before the backglass fills up again after a wrong name (docs/05 §7).
const RETRY_NIGHTS := 3
## The call he makes: a raid at half strength.
const RAID_STRENGTH := 0.5

## The clue vocabulary — each is something a Night does anyway.
const CLUE_LAUNDROMAT := &"laundromat"
const CLUE_COLLECTION := &"collection"
const CLUE_PAYPHONE := &"payphone"
const CLUES: Array[StringName] = [CLUE_LAUNDROMAT, CLUE_COLLECTION, CLUE_PAYPHONE]

const CLUE_LINES := {
	CLUE_LAUNDROMAT: "THE LAUNDROMAT TOTAL IS SHORT",
	CLUE_COLLECTION: "SOMEBODY POCKETED PART OF THE COLLECTION",
	CLUE_PAYPHONE: "A PAYPHONE RANG AND NOBODY WAS THERE",
}

## The arc has started; he is out there.
var armed: bool = false
## He has been named. The arc is over for this career.
var caught: bool = false
## Tonight is flagged "Something's Off": three names in the backglass.
var active: bool = false
## The three names, as Bench guy dicts.
var suspects: Array[Dictionary] = []
## Index into `suspects`. Never published while the Night is live.
var culprit: int = -1
## Clue ids surfaced tonight, in the order they landed.
var clues: PackedStringArray = PackedStringArray()
## Suspect indices the clues have ruled out.
var cleared: PackedInt32Array = PackedInt32Array()
var accusations: int = 0
var wrong_calls: int = 0
## The earliest Night the backglass may fill again.
var next_night: int = 0
## What he has taken off the wash, career-long. The Count reads it and it stings.
var skimmed: BigMoney = BigMoney.zero()

var _rng := RandomNumberGenerator.new()


## Roll call. Returns true if TONIGHT is a clue Night. `roster` is who is available to be
## suspected — three of them, because three names is a backglass and four is a spreadsheet.
func begin_night(night_no: int, rank: int, roster: Array, seed_value: int = 0) -> bool:
	active = false
	clues = PackedStringArray()
	cleared = PackedInt32Array()
	if caught:
		return false
	if not armed and rank >= ARC_RANK:
		armed = true
		# He does not show himself the Night he starts talking.
		next_night = night_no + 1
		return false
	if not armed or night_no < next_night or roster.size() < SUSPECTS:
		return false
	_rng.seed = hash("rat:%d:%d" % [seed_value, night_no])
	suspects = []
	var pool: Array = roster.duplicate()
	for i in SUSPECTS:
		var pick := _rng.randi_range(0, pool.size() - 1)
		suspects.append(pool[pick])
		pool.remove_at(pick)
	culprit = _rng.randi_range(0, SUSPECTS - 1)
	active = true
	return true


## While he is loose, every wash is short. This is both the cost and the first clue.
func skim_fraction() -> float:
	return SKIM if armed and not caught else 0.0


func book_skim(amount: BigMoney) -> void:
	if amount != null and amount.is_positive():
		skimmed = skimmed.add(amount)


# ====================================================================== the clues =====


## Something happened that says something. True the first time this clue lands tonight —
## each one rules out one of the innocent men.
func note_clue(id: StringName) -> bool:
	if not active or not CLUES.has(id) or clues.has(String(id)):
		return false
	clues.append(String(id))
	# Rule out an innocent name, deterministically from the clue's own position, so the same
	# Night always reads the same way and the third clue can never contradict the first two.
	for i in SUSPECTS:
		var index := (culprit + 1 + i) % SUSPECTS
		if index != culprit and not cleared.has(index):
			cleared.append(index)
			break
	return true


static func clue_line(id: StringName) -> String:
	return String(CLUE_LINES.get(id, ""))


func can_accuse() -> bool:
	return active and clues.size() >= CLUES_TO_ACCUSE


## Is this suspect still in the frame?
func is_cleared(index: int) -> bool:
	return cleared.has(index)


func suspect_name(index: int) -> String:
	if index < 0 or index >= suspects.size():
		return ""
	return String((suspects[index] as Dictionary).get("name", ""))


# ================================================================= the accusation =====


## Name him. Returns `{made, right, name, guy}`; `made` false means the accusation was not
## available (no clues yet, no clue Night, or a lane that is not a suspect).
func accuse(index: int) -> Dictionary:
	var result := {"made": false, "right": false, "name": "", "guy": {}}
	if not can_accuse() or index < 0 or index >= suspects.size():
		return result
	accusations += 1
	active = false
	result["made"] = true
	result["name"] = suspect_name(index)
	result["guy"] = suspects[index]
	if index == culprit:
		caught = true
		armed = false
		result["right"] = true
		return result
	wrong_calls += 1
	return result


## After a wrong name, the backglass stays dark for three Nights (docs/05 §7).
func stand_down(night_no: int) -> void:
	next_night = night_no + RETRY_NIGHTS


func state() -> Dictionary:
	var names: Array = []
	for i in suspects.size():
		names.append({"name": suspect_name(i), "cleared": is_cleared(i)})
	return {
		"armed": armed,
		"caught": caught,
		"active": active,
		"suspects": names,
		"clues": Array(clues),
		"can_accuse": can_accuse(),
	}


func night_summary() -> Dictionary:
	return {
		"active": active,
		"clues": clues.size(),
		"caught": caught,
		"skimmed": skimmed.copy(),
	}


func to_dict() -> Dictionary:
	return {
		"armed": armed,
		"caught": caught,
		"next": next_night,
		"accusations": accusations,
		"wrong": wrong_calls,
		"skimmed": skimmed.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	armed = false
	caught = false
	next_night = 0
	accusations = 0
	wrong_calls = 0
	skimmed = BigMoney.zero()
	active = false
	suspects = []
	culprit = -1
	clues = PackedStringArray()
	cleared = PackedInt32Array()
	if d == null or d.is_empty():
		return
	armed = bool(d.get("armed", false))
	caught = bool(d.get("caught", false))
	next_night = maxi(int(d.get("next", 0)), 0)
	accusations = maxi(int(d.get("accusations", 0)), 0)
	wrong_calls = maxi(int(d.get("wrong", 0)), 0)
	skimmed = BigMoney.from_dict(d.get("skimmed", {}))
