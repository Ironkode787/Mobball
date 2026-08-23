class_name Elections
extends RefCounted
## THE PUPPET MAYOR (docs/05 §8). A campaign that runs across Nights: canvass five districts
## by doing that district's job inside a Night, and the light stays on. Five lights and the
## city votes — ninety seconds where every switch on the machine is a ballot. Win it and the
## next five Nights are run from City Hall.
##
## Unlocked by the Penthouse (`CommissionChairs`): the families have to be seated before the
## city is worth buying.
##
## Pure logic on a fed clock, like every mode in this lane. The NightController tells it what
## happened, `Game` pays the frenzy's money and holds the Inspector at the door while a term
## is running.
##
## Design note on the objectives: every one of them is something flow already watches, so a
## district is canvassed by *playing that zone*, never by a bespoke counter bolted onto the
## table. That is also why the campaign needs no new hardware.

## Districts, in table order from the bottom up. `need` is how much of that district's own
## work makes a Night count as canvassed.
const DISTRICTS: Array[Dictionary] = [
	{"id": &"alley", "name": "THE ALLEY", "need": 40, "what": "hits off the bats and cans"},
	{"id": &"corner", "name": "THE CORNER", "need": 6, "what": "payphones worked"},
	{"id": &"block", "name": "THE BLOCK", "need": 1, "what": "a perfect Collection Round"},
	{"id": &"club", "name": "THE CLUB", "need": 1, "what": "a slots Jackpot"},
	{"id": &"docks", "name": "THE DOCKS", "need": 1, "what": "a shipment out"},
]

## Election Night: ninety seconds, every switch is a vote.
const ELECTION_SECONDS := 90.0
## Votes that carry the city. Sized off a good ninety seconds of play — roughly a switch
## every second with the machine lit up — so it is a real ask that a bad ball can miss.
const VOTES_TO_WIN := 100
## The frenzy pays: a vote is worth money as well as a ballot (docs/05 §8 "frenzy").
const FRENZY_MULT := 3.0
## Winning buys a term of this many Nights in office.
const TERM_NIGHTS := 5
## In office the Inspector needs a much better reason (docs/05 §8: the raid threshold moves).
const ADMIN_RAID_THRESHOLD := 120.0
## Cops on your payroll: a cop target knocked down under an Administration is worth this much
## off the meter, because they are escorts now, not a patrol.
const ADMIN_COP_HEAT := 4.0
## A lost election is a recount, not a wipe: one district keeps its light.
const RECOUNT_KEEPS := 1

## Set once the Penthouse is taken (CommissionChairs.all_claimed + a sweep). Saved.
var unlocked: bool = false
## District id -> true for every district canvassed. Persists across Nights, saved.
var lit: Dictionary = {}
## Election Night is running.
var active: bool = false
var time_left: float = 0.0
var votes: int = 0
## Nights of Administration left, decremented at roll call. Saved.
var term_left: int = 0

var terms_won: int = 0
var terms_lost: int = 0
var elections_run: int = 0

## District id -> tonight's progress toward `need`. Per Night, not saved: a district is
## canvassed in ONE Night's work or not at all.
var _progress: Dictionary = {}


func begin_night() -> void:
	active = false
	time_left = 0.0
	votes = 0
	_progress.clear()


# ==================================================================== the campaign =====


static func district(id: StringName) -> Dictionary:
	for d in DISTRICTS:
		if StringName(d["id"]) == id:
			return d
	return {}


## The Penthouse is yours: the campaign can start. True the first time.
func unlock() -> bool:
	if unlocked:
		return false
	unlocked = true
	return true


func is_lit(id: StringName) -> bool:
	return bool(lit.get(String(id), false))


func lit_count() -> int:
	return lit.size()


func all_lit() -> bool:
	return lit.size() >= DISTRICTS.size()


func progress_in(id: StringName) -> int:
	return int(_progress.get(String(id), 0))


## Work done in a district tonight. True on the report that canvasses it — the caller turns
## that into the announcement, and the fifth one calls the election.
func note(id: StringName, amount: int = 1) -> bool:
	if not unlocked or amount <= 0 or is_lit(id):
		return false
	var d := district(id)
	if d.is_empty():
		return false
	var key := String(id)
	var got := int(_progress.get(key, 0)) + amount
	_progress[key] = got
	if got < int(d["need"]):
		return false
	lit[key] = true
	return true


# ================================================================== Election Night =====


## Every district is lit: the city votes. True if this call opened the ballot.
func call_election() -> bool:
	if active or not all_lit():
		return false
	active = true
	time_left = ELECTION_SECONDS
	votes = 0
	elections_run += 1
	return true


## One switch, one vote — every switch on the machine, which is the joke.
func on_vote(count: int = 1) -> void:
	if active and count > 0:
		votes += count


## Everything dirty is worth more while the city is voting.
func dirty_multiplier() -> float:
	return FRENZY_MULT if active else 1.0


## True on the tick the polls close. Read `won` afterwards for the result.
func tick(delta: float) -> bool:
	if not active or delta <= 0.0:
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	active = false
	time_left = 0.0
	return true


## Was the last ballot carried? Only meaningful right after `tick()` reported the close.
func won() -> bool:
	return votes >= VOTES_TO_WIN


## Settle the ballot. Winning puts you in office for a term and clears the board for the next
## campaign; losing is a recount — the count is thrown out but one district keeps its light,
## so the next run starts one step in rather than from nothing (docs/05 §8, P5).
func settle(keep: StringName = &"") -> Dictionary:
	var carried := won()
	var result := {
		"won": carried,
		"votes": votes,
		"needed": VOTES_TO_WIN,
		"term": 0,
		"kept": "",
	}
	if carried:
		terms_won += 1
		# The ballot is always counted DURING a Night, and the term is spent at the end of
		# one — so the Night you won it does not count against the five you bought.
		term_left = TERM_NIGHTS + 1
		result["term"] = TERM_NIGHTS
		lit.clear()
	else:
		terms_lost += 1
		var keeper := _recount_keeper(keep)
		lit.clear()
		if not keeper.is_empty():
			lit[keeper] = true
			result["kept"] = keeper
	votes = 0
	return result


## Which light survives a recount. The caller may name one (the district whose objective was
## the hardest to get); otherwise the last one in table order stays on.
func _recount_keeper(keep: StringName) -> String:
	if RECOUNT_KEEPS <= 0:
		return ""
	if keep != &"" and is_lit(keep):
		return String(keep)
	for i in range(DISTRICTS.size() - 1, -1, -1):
		var key := String(DISTRICTS[i]["id"])
		if lit.has(key):
			return key
	return ""


# ================================================================= the Administration =====


func in_office() -> bool:
	return term_left > 0


## The Count: a Night in office is a Night off the term. Spent at the END of a Night rather
## than at roll call, so the Night the election was won is not one of the five it bought.
## True on the Night the term runs out.
func night_tick() -> bool:
	if term_left <= 0:
		return false
	term_left -= 1
	return term_left <= 0


## The Inspector's bar while City Hall is yours (docs/05 §8). The meter still latches its raid
## at 100 — that is the economy core's, and frozen — so the Administration does not lower the
## latch, it refuses to *act* on it until the number is genuinely embarrassing.
func raid_threshold() -> float:
	return ADMIN_RAID_THRESHOLD if in_office() else Rates.RAID_THRESHOLD


func night_summary() -> Dictionary:
	return {
		"lit": lit_count(),
		"districts": DISTRICTS.size(),
		"term_left": term_left,
		"votes": votes,
	}


func to_dict() -> Dictionary:
	var districts: Array = []
	for d in DISTRICTS:
		if lit.has(String(d["id"])):
			districts.append(String(d["id"]))
	return {
		"unlocked": unlocked,
		"lit": districts,
		"term": term_left,
		"won": terms_won,
		"lost": terms_lost,
		"run": elections_run,
	}


func from_dict(d: Dictionary) -> void:
	unlocked = false
	lit.clear()
	term_left = 0
	terms_won = 0
	terms_lost = 0
	elections_run = 0
	if d == null or d.is_empty():
		return
	unlocked = bool(d.get("unlocked", false))
	for raw: Variant in d.get("lit", []):
		if not district(StringName(raw)).is_empty():
			lit[String(raw)] = true
	term_left = maxi(int(d.get("term", 0)), 0)
	terms_won = maxi(int(d.get("won", 0)), 0)
	terms_lost = maxi(int(d.get("lost", 0)), 0)
	elections_run = maxi(int(d.get("run", 0)), 0)
	begin_night()
