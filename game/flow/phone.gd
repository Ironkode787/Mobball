class_name ThePhone
extends RefCounted
## THE PHONE (docs/05 §10). It rings. You have a few seconds to decide whether you are the
## kind of person who picks up.
##
## There is no backbox to tap on this machine, so the phone is the phone that is already
## bolted to it: **the Wire's payphones**. While it is ringing, a hit on that bank answers it.
## That costs the player a real shot at a real target under a real clock, which is a better
## decision than a button would be — and it means the feature needs no hardware and no UI
## beyond a line on the HUD.
##
## Four things are on the other end (docs/05 §10): a tip, a bet, a job, and your nonna.
## Answering is always worth something. Letting it ring out is free — except for the one call
## it was your grandmother, which costs a single ☆ and is, as the design intends, the joke.
##
## Pure logic on a fed clock and a seeded RNG.

const TIP := &"tip"
const BET := &"bet"
const JOB := &"job"
const NONNA := &"nonna"
const CALLERS: Array[StringName] = [TIP, BET, JOB, NONNA]

## Seconds of play between calls, and how long it rings for.
const PERIOD := 110.0
const RING_SECONDS := 12.0
## The tip: "the wagon's coming" — worth this much off the meter.
const TIP_HEAT := 15.0
## The job: a slip's worth of ☆ for picking up.
const JOB_RESPECT := 3
## Nonna: she is proud of you.
const NONNA_RESPECT := 2
## Not picking up when it was her.
const NONNA_MISS_RESPECT := 1

var ringing: bool = false
var time_left: float = 0.0
## Who is on the line right now. Never shown before it is answered — the whole decision is
## made without knowing (docs/05 §10).
var caller: StringName = &""

var answered_total: int = 0
var missed_total: int = 0
var night_answered: int = 0
var night_missed: int = 0

var _next_in: float = PERIOD
var _rng := RandomNumberGenerator.new()


func begin_night(seed_value: int = 0, night_no: int = 0) -> void:
	_rng.seed = hash("phone:%d:%d" % [seed_value, night_no])
	_next_in = PERIOD
	ringing = false
	time_left = 0.0
	caller = &""
	night_answered = 0
	night_missed = 0


## True on the tick it starts ringing.
func tick(delta: float) -> bool:
	if delta <= 0.0:
		return false
	if ringing:
		time_left -= delta
		if time_left > 0.0:
			return false
		# Rang out. Whoever it was, they have hung up.
		ringing = false
		time_left = 0.0
		missed_total += 1
		night_missed += 1
		return false
	_next_in -= delta
	if _next_in > 0.0:
		return false
	_next_in = PERIOD
	ringing = true
	time_left = RING_SECONDS
	caller = CALLERS[_rng.randi() % CALLERS.size()]
	return true


## Was the call that just rang out your grandmother? Read by the caller on the tick the ring
## ends, so the ☆ can be taken with a straight face.
func missed_nonna() -> bool:
	return caller == NONNA


## Pick up. Returns who it was, or an empty StringName if nothing was ringing.
func answer() -> StringName:
	if not ringing:
		return &""
	ringing = false
	time_left = 0.0
	answered_total += 1
	night_answered += 1
	return caller


func night_summary() -> Dictionary:
	return {"answered": night_answered, "missed": night_missed}


func to_dict() -> Dictionary:
	return {"answered": answered_total, "missed": missed_total}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	answered_total = maxi(int(d.get("answered", 0)), 0)
	missed_total = maxi(int(d.get("missed", 0)), 0)
	begin_night()
