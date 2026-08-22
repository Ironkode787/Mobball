class_name CollectionRound
extends RefCounted
## COLLECTION ROUNDS (docs/05 §3). All three storefront banks armed at once starts a 25 s
## round: collect all three in any order and the last one pays double and lights the Family
## Meeting. Miss the clock and the round simply lapses — a Collection Round costs nothing to
## fail, which is what makes it a tempo change rather than a threat.
##
## The ☆10 lands on the FIRST perfect round of a Night and no other (`take_respect`), the same
## way the combo's tiers do. Balance-sim ruling: paid per round it was 87% of a good player's
## whole Respect, so rank tracked how many laps you could run round three shops instead of the
## Jobs board it is supposed to track. The money is per round; the ladder is per Night.
##
## Pure logic on a fed clock. The NightController watches the storefronts and forwards the
## collects; `Game` pays the double.

const SECONDS := 25.0
## The FIRST perfect round of a Night is worth this; every one after it pays money and lights
## the back room, and nothing else. See `take_respect`.
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
## Tonight's ☆10 is still on the table. See `take_respect`.
var _respect_left: bool = true


func begin_night() -> void:
	active = false
	time_left = 0.0
	_collected.clear()
	_cooldown = 0.0
	night_started = 0
	night_won = 0
	_respect_left = true


## The ☆ a won round pays, and it is once a Night (balance-sim ruling: a repeatable ☆10 made
## the block 87% of a career's Respect, and rank is supposed to track the Jobs board, not the
## number of laps you can run round three shops). Consumed on the first perfect round; every
## round after it still pays double and still lights the back room, and returns 0 here.
func take_respect() -> int:
	if not _respect_left:
		return 0
	_respect_left = false
	return RESPECT


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
