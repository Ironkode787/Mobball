class_name CollectionRound
extends RefCounted
## COLLECTION ROUNDS (docs/05 §3). All three storefront banks armed at once starts a 25 s
## round: collect all three in any order and the last one pays double, worth ☆10, and it
## lights the Family Meeting. Miss the clock and the round simply lapses — a Collection Round
## costs nothing to fail, which is what makes it a tempo change rather than a threat.
##
## Pure logic on a fed clock. The NightController watches the storefronts and forwards the
## collects; `Game` pays the double.

const SECONDS := 25.0
const RESPECT := 10
## The last collect pays its own value again — "Double Collection" (docs/05 §3).
const LAST_PAYS_EXTRA := 1.0
## After a lapsed round the three banks are usually still armed. Without a beat of quiet the
## round would immediately re-arm and the HUD timer would never stop moving.
const RETRIGGER_GAP := 8.0

var active: bool = false
var time_left: float = 0.0
var rounds_started: int = 0
var rounds_won: int = 0
var night_started: int = 0
var night_won: int = 0
var total_started: int = 0
var total_won: int = 0

var _collected: Dictionary = {}
var _cooldown: float = 0.0


func begin_night() -> void:
	active = false
	time_left = 0.0
	_collected.clear()
	_cooldown = 0.0
	night_started = 0
	night_won = 0


func collected_count() -> int:
	return _collected.size()


## The whole block is armed. True if this actually started a round.
func on_all_armed() -> bool:
	if active or _cooldown > 0.0:
		return false
	active = true
	time_left = SECONDS
	_collected.clear()
	rounds_started += 1
	night_started += 1
	total_started += 1
	return true


## One storefront collected. True on the third — the round is won.
func on_collected(id: StringName) -> bool:
	if not active:
		return false
	_collected[String(id)] = true
	if _collected.size() < int(Switches.COVER_SIZE.get(&"storefronts", 3)):
		return false
	active = false
	time_left = 0.0
	_cooldown = RETRIGGER_GAP
	rounds_won += 1
	night_won += 1
	total_won += 1
	return true


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
	active = false
	time_left = 0.0
	_collected.clear()
	_cooldown = RETRIGGER_GAP


func night_summary() -> Dictionary:
	return {"rounds": night_started, "won": night_won}


func to_dict() -> Dictionary:
	return {"started": total_started, "won": total_won}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	total_started = maxi(int(d.get("started", 0)), 0)
	total_won = maxi(int(d.get("won", 0)), 0)
