class_name Commission
extends RefCounted
## THE COMMISSION (docs/05 §6, specs/m2-content.md §5). Which rival family is waiting, whether
## you are allowed past him yet, and what beating him is worth.
##
## Pure rules and a little saved state — no nodes, no table, no money. The fight itself is a
## mode node (game/flow/bosses/boss_fight.gd); `Game` pays the purse and hands out the spoil;
## this is the ladder they both read.
##
## The rule that makes a boss a boss: **respect alone does not promote you past a gated rank**.
## The stars get you the meeting, the fight gets you the chair. R3→R4 is Sammy's, R4→R5 is the
## Butcher's, and every other step on the ladder promotes the moment the stars land, exactly as
## it did in M1. (M2 simplification, spec §5: the rank's story job is not implemented yet, so
## respect is the whole invitation.)

const SAMMY := &"sammy"
const BUTCHER := &"butcher"

## Ledger ids the spoils are filed under. They are not purchasable — `Game.owned` carries
## them as pseudo-nodes so one save file holds everything a career owns, bought or taken.
const SPOIL_PREFIX := "spoil."
const SPOIL_SAMMY := "spoil.sammys_spare"
const SPOIL_BUTCHER := "spoil.cold_storage"

## The ladder. `gates` is the rank you cannot leave until this fight is won; the purse is
## fixed and clean (spec §5 — the economy is paused, so the fight pays exactly this and the
## player's own table pays nothing at all).
const FIGHTS: Array[Dictionary] = [
	{
		"id": SAMMY,
		"gates": 3,
		"name": "SAMMY TWO-FLIPPERS",
		"call": "SAMMY'S WAITING",
		"spoil": SPOIL_SAMMY,
		"spoil_name": "SAMMY'S SPARE",
		"purse": [5.0, 5],
		"respect": 100,
	},
	{
		"id": BUTCHER,
		"gates": 4,
		"name": "THE BUTCHER",
		"call": "THE BUTCHER IS ASKING",
		"spoil": SPOIL_BUTCHER,
		"spoil_name": "COLD STORAGE",
		"purse": [5.0, 6],
		"respect": 200,
	},
]

## Fight id -> true, for every fight already won. Saved.
var beaten: Dictionary = {}
## Fight id -> how many Nights have been spent on it. Saved: a fight you lost is a fight you
## have been to, and The Count says so when it offers the rematch.
var attempts: Dictionary = {}
## The fight the NEXT Night runs instead of an ordinary Night. Cleared when it starts.
var pending: StringName = &""
## The last fight's result, for The Count: {"id", "won", "purse", "spoil"}.
var last_result: Dictionary = {}


# ==================================================================== the ladder =====


static func fight(id: StringName) -> Dictionary:
	for f in FIGHTS:
		if StringName(f["id"]) == id:
			return f
	return {}


## The fight standing between `rank` and the next one, or empty for an ungated rank.
static func fight_gating(rank: int) -> Dictionary:
	for f in FIGHTS:
		if int(f["gates"]) == rank:
			return f
	return {}


static func purse_for(f: Dictionary) -> BigMoney:
	if f.is_empty():
		return BigMoney.zero()
	var p: Array = f["purse"]
	return BigMoney.of(float(p[0]), int(p[1]))


func is_beaten(id: StringName) -> bool:
	return bool(beaten.get(String(id), false))


func attempts_at(id: StringName) -> int:
	return int(attempts.get(String(id), 0))


## Whoever is waiting for this career right now: the fight that gates this rank, once the ☆
## for the next rank are in the bank and he has not been put away already. Empty otherwise —
## and empty is the common case, which is why The Count only grows the button some Nights.
func waiting(rank: int, respect: int, ladder: PackedInt32Array) -> Dictionary:
	var f := fight_gating(rank)
	if f.is_empty() or is_beaten(StringName(f["id"])):
		return {}
	var next := rank + 1
	if next >= ladder.size() or respect < ladder[next]:
		return {}
	return f


## The rank ladder's own gate. `want` is what the ☆ say; this is what the Commission allows,
## which is the same number until a fight is owed. Never lowers a rank already held.
func rank_cap(current: int, want: int) -> int:
	var capped := current
	for step in range(current, want):
		var f := fight_gating(step)
		if not f.is_empty() and not is_beaten(StringName(f["id"])):
			return capped
		capped = step + 1
	return maxi(capped, current)


## A Night is being spent on this fight.
func begin_fight(id: StringName) -> void:
	pending = &""
	attempts[String(id)] = attempts_at(id) + 1


func mark_beaten(id: StringName) -> void:
	beaten[String(id)] = true


# ================================================================ serialization =====


func to_dict() -> Dictionary:
	var won: Array = beaten.keys()
	won.sort()
	return {
		"beaten": won,
		"attempts": attempts.duplicate(),
		"pending": String(pending),
	}


func from_dict(d: Dictionary) -> void:
	beaten.clear()
	attempts.clear()
	pending = &""
	last_result = {}
	if d == null or d.is_empty():
		return
	for id: Variant in d.get("beaten", []):
		beaten[String(id)] = true
	var raw: Variant = d.get("attempts", {})
	if raw is Dictionary:
		for id: Variant in raw as Dictionary:
			attempts[String(id)] = int((raw as Dictionary)[id])
	# A fight that was pending when the app died is still owed: the Count offers it again
	# rather than the next Night silently becoming one.
	pending = &""
