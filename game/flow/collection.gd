class_name CollectionRound
extends RefCounted
## COLLECTION ROUNDS (docs/05 §3, docs/20 §4). The first shop that pays up starts a 25 s round:
## collect the rest of the block before the clock runs out and the last one pays double and
## lights the Family Meeting. Miss the clock and the round simply lapses — a Collection Round
## costs nothing to fail, which is what makes it a tempo change rather than a threat.
##
## It used to start when every bank stood at once, which a boarded-up shop also did: every
## Night opened on a round nobody could play, owning the HUD's objective line.
##
## The ☆10 lands on the FIRST perfect round of a Night and no other (`take_respect`), the same
## way the combo's tiers do. Balance-sim ruling: paid per round it was 87% of a good player's
## whole Respect, so rank tracked how many laps you could run round three shops instead of the
## Jobs board it is supposed to track. The money is per round; the ladder is per Night.
##
## Pure logic on a fed clock. The NightController forwards the collects; `Game` pays the double.

const SECONDS := 25.0
## The FIRST perfect round of a Night is worth this; every one after it pays money and lights
## the back room, and nothing else. See `take_respect`.
const RESPECT := 10
## The last collect pays its own value again — "Double Collection" (docs/05 §3).
const LAST_PAYS_EXTRA := 1.0
## A beat of quiet after a round ends, won or lapsed, before a collect can start the next.
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


## Whether this shop has paid in the running round.
func has_collected(id: StringName) -> bool:
	return _collected.has(String(id))


## A shop paid. With no round running, this starts one — as long as the block has another shop
## to collect. With one running, it counts; the last of the block's `shops` wins it. True on
## the win.
func on_collected(id: StringName, shops: int) -> bool:
	if not active:
		if _cooldown > 0.0 or shops < 2:
			return false
		active = true
		time_left = SECONDS
		_collected.clear()
		_collected[String(id)] = true
		rounds_started += 1
		night_started += 1
		total_started += 1
		return false
	_collected[String(id)] = true
	if _collected.size() < shops:
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
