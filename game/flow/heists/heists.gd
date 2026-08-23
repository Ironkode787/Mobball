class_name Heists
extends RefCounted
## THE WAR ROOM (docs/05 §5). Which jobs are on the board, which ones you have already cased,
## what an approach costs and what a take is worth. The career's book; `HeistRun` is the Night.
##
## Three of the five targets ship in M3 (the Train wants moving container platforms and the
## Evidence Locker wants the Federal era's raid hardware to stand there passively — both are
## table work that does not exist yet). The two absent ones are listed as data with
## `shipped: false` so The Count can show the board as it will be rather than pretending the
## city only has three things worth stealing.
##
## A heist does not replace a Night the way a Commission fight does. It is *planned* at The
## Count and runs from the first serve of the next Night, with the economy on and the guys
## fielded as usual — because the fiction is a job you do on a working night, and because the
## fail-forward rule (docs/05 §5: "missing a beat degrades the take, only a drain ends it")
## needs a live ball to be meaningful.
##
## Pure rules and a little saved state: no nodes, no table, no money.

## Approaches (docs/05 §5). Quiet is tighter shots and no Heat at all; Loud is generous
## windows bought with a flat +25 on the meter.
const QUIET := &"quiet"
const LOUD := &"loud"
const APPROACHES := {
	QUIET: {"name": "QUIET", "window": 0.7, "heat": 0.0,
			"blurb": "tight windows, nobody hears a thing"},
	LOUD: {"name": "LOUD", "window": 1.5, "heat": 25.0,
			"blurb": "kick the door in — the city will know"},
}

const PAYROLL := &"payroll_truck"
const MUSEUM := &"museum_job"
const VAULT := &"casino_vault"
const TRAIN := &"the_train"
const EVIDENCE := &"evidence_locker"

## Nights between runs at the same target — "casing" (docs/05 §5), which is what keeps a
## heist an event instead of a farm.
const CASING_NIGHTS := 5

## A take is minutes of the whole empire's idle rate, like every other setpiece payout on
## this table (Casino.jackpot_value, SmugglingRun.base_value), times the target's own size.
## Paid CLEAN: a heist is the one racket whose money never has to be washed.
const TAKE_MINUTES := 10.0
const TAKE_FLOOR_MANTISSA := 5.0
const TAKE_FLOOR_EXP := 4
## The stake you put up to run the job, in dirty, as a share of the nominal take.
const STAKE_FRACTION := 0.08
## Each blown beat costs this much of the take, floored so a bad night is still a payday —
## the sequence is fail-forward, not pass/fail (docs/05 §5).
const DEGRADE_PER_MISS := 0.22
const MIN_SHARE := 0.2
## ☆ for a job that ran to the end. Not per beat: the ladder belongs to the Jobs board.
const RESPECT_CLEARED := 20

## THE BOARD. `beats` are the scripted shot sequence, each over hardware that already exists:
## a heist is choreography on your own table, never new geometry (docs/05 §5).
##
## A beat is `{id, line, group, count, seconds}` plus two optional keys:
##   `max_strength` — the hit has to be GENTLE (the Vault's walk-out is a skill check on
##                    softness, which is the one thing pinball never asks for).
##   `any`          — a list of groups, when the fiction accepts more than one shot.
const TARGETS: Array[Dictionary] = [
	{
		"id": PAYROLL,
		"shipped": true,
		"name": "THE PAYROLL TRUCK",
		"blurb": "Friday. Two guards. One route.",
		"take": 1.0,
		"relic": "",
		"beats": [
			{"id": &"stop", "line": "STOP THE TRUCK", "group": &"bumpers", "count": 3,
					"seconds": 14.0},
			{"id": &"door", "line": "CRACK THE DOOR", "group": &"storefronts", "count": 1,
					"seconds": 16.0},
			{"id": &"away", "line": "GETAWAY x2", "group": &"orbit", "count": 2,
					"seconds": 20.0},
		],
	},
	{
		"id": MUSEUM,
		"shipped": true,
		"name": "THE MUSEUM JOB",
		"blurb": "Nobody insures a rock they say is priceless.",
		"take": 1.8,
		"relic": "relic.museum",
		"beats": [
			{"id": &"sensors", "line": "KILL 3 SENSORS", "group": &"rollovers", "count": 3,
					"seconds": 18.0},
			{"id": &"case", "line": "THE GLASS CASE x4", "group": &"wire", "count": 4,
					"seconds": 20.0},
			{"id": &"roof", "line": "OUT OVER THE ROOF", "group": &"ramps", "count": 1,
					"any": [&"ramps", &"orbit"], "seconds": 18.0},
		],
	},
	{
		"id": VAULT,
		"shipped": true,
		"name": "THE CASINO VAULT",
		"blurb": "You own the tables. Own the basement.",
		"take": 3.0,
		"relic": "",
		"beats": [
			{"id": &"count", "line": "COUNT THE CARDS x5", "group": &"casino", "count": 5,
					"seconds": 20.0},
			{"id": &"wheel", "line": "THE VAULT WHEEL x20", "group": &"spinner", "count": 20,
					"seconds": 14.0},
			{"id": &"walk", "line": "WALK OUT SLOW", "group": &"rollovers", "count": 1,
					"max_strength": 0.35, "seconds": 16.0},
		],
	},
	{
		"id": TRAIN,
		"shipped": false,
		"name": "THE TRAIN",
		"blurb": "Moving platforms. Moving target. Moving on.",
		"take": 4.0,
		"relic": "",
		"beats": [],
	},
	{
		"id": EVIDENCE,
		"shipped": false,
		"name": "THE EVIDENCE LOCKER",
		"blurb": "Steal your own file back.",
		"take": 2.5,
		"relic": "",
		"beats": [],
	},
]

## The inside man (docs/05 §5): a Bench guy whose one visible trait bends the job. Read
## against `GuyTraits`, so the crew you already have is the crew you plan with.
##   `window`  — every beat's clock is this much longer.
##   `forgive` — this many blown beats do not degrade the take.
##   `take`    — a straight multiplier on the take.
##   `degrade` — scale on what a blown beat costs.
##   `drains`  — extra drains the job survives (docs/05 §5: only a drain ends it — usually).
##   `heat`    — flat Heat the job costs on top of the approach.
const INSIDE_MAN := {
	GuyTraits.FAST: {"window": 1.25, "line": "he knows the timings"},
	GuyTraits.CAREFUL: {"forgive": 1, "line": "he covers the first mistake"},
	GuyTraits.LOUD: {"take": 1.15, "heat": 10.0, "line": "he takes more and makes noise"},
	GuyTraits.OLD_TIMER: {"degrade": 0.5, "line": "he has done this before"},
	GuyTraits.SLIPPERY: {"drains": 1, "line": "he gets out either way"},
	GuyTraits.LUCKY: {"take": 1.10, "line": "things go his way"},
}

## The job the NEXT Night runs. Cleared when it starts, like `Commission.pending`.
var pending: Dictionary = {}
## Target id -> the Night it was last run. Saved: casing is a career-long clock.
var cased: Dictionary = {}
var cleared: int = 0
var attempted: int = 0
var blown_beats: int = 0
var take_total: BigMoney = BigMoney.zero()
## Museum pieces taken, in order. The gallery itself is the meta lane's (docs/06 §3).
var relics: PackedStringArray = []
## The last job's result, for The Count.
var last_result: Dictionary = {}


# ====================================================================== the board =====


static func target(id: StringName) -> Dictionary:
	for row in TARGETS:
		if StringName(row["id"]) == id:
			return row
	return {}


static func approach(id: StringName) -> Dictionary:
	var row: Variant = APPROACHES.get(id, null)
	return row if row is Dictionary else APPROACHES[QUIET]


static func inside_man_effect(guy: Dictionary) -> Dictionary:
	var row: Variant = INSIDE_MAN.get(GuyTraits.of(guy), null)
	return row if row is Dictionary else {}


## Nights until this target can be hit again, 0 when it is on the board now.
func casing_left(id: StringName, night_no: int) -> int:
	if not cased.has(String(id)):
		return 0
	var since := night_no - int(cased[String(id)])
	return maxi(CASING_NIGHTS - since, 0)


func is_available(id: StringName, night_no: int) -> bool:
	var row := target(id)
	if row.is_empty() or not bool(row.get("shipped", false)):
		return false
	return casing_left(id, night_no) <= 0


## Everything the war room can offer tonight, in board order, each with why it can or cannot
## be run. The Count renders this list and nothing else.
func board(night_no: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in TARGETS:
		var id := StringName(row["id"])
		out.append({
			"id": String(id),
			"name": String(row["name"]),
			"blurb": String(row["blurb"]),
			"shipped": bool(row.get("shipped", false)),
			"available": is_available(id, night_no),
			"casing_left": casing_left(id, night_no),
			"beats": (row["beats"] as Array).size(),
		})
	return out


# ====================================================================== the money =====


## The nominal take, before anything is blown: minutes of the empire's idle rate at the
## target's own size, floored so an early career's first job is still a payday.
static func take_for(id: StringName, idle_rate: BigMoney) -> BigMoney:
	var row := target(id)
	if row.is_empty():
		return BigMoney.zero()
	var size := float(row.get("take", 1.0))
	var floor_value := BigMoney.of(TAKE_FLOOR_MANTISSA, TAKE_FLOOR_EXP).mul(size)
	if idle_rate == null or not idle_rate.is_positive():
		return floor_value
	return BigMoney.max_of(idle_rate.mul(TAKE_MINUTES * 60.0 * size), floor_value)


## What the job costs to set up, in dirty. A stake is what makes choosing a target a decision
## rather than a free roll (docs/05 §5).
static func stake_for(id: StringName, idle_rate: BigMoney) -> BigMoney:
	return take_for(id, idle_rate).mul(STAKE_FRACTION)


## The share of the take that survives `blown` missed beats with this inside man on the crew.
static func degrade_share(blown: int, effect: Dictionary) -> float:
	var forgiven := int(effect.get("forgive", 0))
	var counted := maxi(blown - forgiven, 0)
	var per := DEGRADE_PER_MISS * float(effect.get("degrade", 1.0))
	return maxf(1.0 - per * float(counted), MIN_SHARE)


# ====================================================================== the book =====


## A job is going out on the next Night.
func plan(id: StringName, approach_id: StringName, guy: Dictionary) -> Dictionary:
	pending = {
		"target": String(id),
		"approach": String(approach_id),
		"guy": guy.duplicate() if guy != null and not guy.is_empty() else {},
	}
	return pending


func clear_pending() -> void:
	pending = {}


## The Night opened on this job.
func begin(id: StringName, night_no: int) -> void:
	pending = {}
	attempted += 1
	cased[String(id)] = night_no


## Book a finished job.
func book(result: Dictionary) -> void:
	last_result = result.duplicate()
	blown_beats += int(result.get("blown", 0))
	if bool(result.get("cleared", false)):
		cleared += 1
	var paid: Variant = result.get("paid", null)
	if paid is BigMoney:
		take_total = take_total.add(paid as BigMoney)
	var relic := String(result.get("relic", ""))
	if not relic.is_empty() and not relics.has(relic):
		relics.append(relic)


# ================================================================ serialization =====


func to_dict() -> Dictionary:
	return {
		"cased": cased.duplicate(),
		"cleared": cleared,
		"attempted": attempted,
		"blown": blown_beats,
		"take": take_total.to_dict(),
		"relics": Array(relics),
	}


func from_dict(d: Dictionary) -> void:
	cased.clear()
	cleared = 0
	attempted = 0
	blown_beats = 0
	take_total = BigMoney.zero()
	relics = PackedStringArray()
	pending = {}
	last_result = {}
	if d == null or d.is_empty():
		return
	var raw: Variant = d.get("cased", {})
	if raw is Dictionary:
		for id: Variant in raw as Dictionary:
			cased[String(id)] = int((raw as Dictionary)[id])
	cleared = maxi(int(d.get("cleared", 0)), 0)
	attempted = maxi(int(d.get("attempted", 0)), 0)
	blown_beats = maxi(int(d.get("blown", 0)), 0)
	take_total = BigMoney.from_dict(d.get("take", {}))
	for r: Variant in d.get("relics", []):
		var relic := String(r)
		if not relic.is_empty() and not relics.has(relic):
			relics.append(relic)
