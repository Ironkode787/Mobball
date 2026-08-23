class_name HeistRun
extends RefCounted
## ONE HEIST, live (docs/05 §5). A scripted shot-sequence checklist over hardware the table
## already has: each beat wants `count` hits of one shot group inside its own window, and the
## windows are what the approach and the inside man actually bend.
##
## **Fail-forward.** A beat whose clock runs out is not a failure, it is a worse payday: the
## sequence moves on and the take is degraded. The only thing that ends a heist early is a
## drain — which is why a heist runs on a live Night with a real guy on the ball rather than
## inside a paused boss-fight frame.
##
## Pure logic on a fed clock, like every mode in this lane: the NightController hands it
## switches, seconds and drains, and `Game` pays what it decides. That also means the whole
## thing can be walked in a unit test with no table under it.

const HIT_OK := &"ok"
const HIT_GENTLE := &"too_hard"
const HIT_NONE := &"none"

var target: StringName = &""
var target_name: String = ""
var approach: StringName = Heists.QUIET
var guy: Dictionary = {}
var effect: Dictionary = {}

var active: bool = false
var cleared: bool = false
## 0-based index of the beat being worked; == beats.size() once the sequence is done.
var beat_index: int = 0
var beat_hits: int = 0
var time_left: float = 0.0
var blown: int = 0
## Drains this job can still shrug off (the Slippery inside man buys one).
var spare_drains: int = 0

var _beats: Array = []


## Build a run. `guy` is the inside man off the Bench — his trait is the whole of his effect.
static func make(target_id: StringName, approach_id: StringName, inside_man: Dictionary) -> HeistRun:
	var row := Heists.target(target_id)
	if row.is_empty() or not bool(row.get("shipped", false)):
		return null
	var beats: Array = row["beats"]
	if beats.is_empty():
		return null
	var run := HeistRun.new()
	run.target = target_id
	run.target_name = String(row["name"])
	run.approach = approach_id if Heists.APPROACHES.has(approach_id) else Heists.QUIET
	run.guy = inside_man.duplicate() if inside_man != null and not inside_man.is_empty() else {}
	run.effect = Heists.inside_man_effect(run.guy)
	run._beats = beats
	return run


func beats() -> Array:
	return _beats


func beat() -> Dictionary:
	if beat_index < 0 or beat_index >= _beats.size():
		return {}
	return _beats[beat_index]


## Seconds this beat gets: its own clock, stretched by the approach and by the inside man.
func window_for(index: int) -> float:
	if index < 0 or index >= _beats.size():
		return 0.0
	var base := float((_beats[index] as Dictionary).get("seconds", 15.0))
	return base * float(Heists.approach(approach).get("window", 1.0)) \
			* float(effect.get("window", 1.0))


func begin() -> void:
	active = true
	cleared = false
	blown = 0
	beat_index = 0
	beat_hits = 0
	spare_drains = int(effect.get("drains", 0))
	time_left = window_for(0)


## Flat Heat the job costs at the door: the approach's, plus whatever the inside man adds.
func heat_cost() -> float:
	return float(Heists.approach(approach).get("heat", 0.0)) + float(effect.get("heat", 0.0))


# ====================================================================== the beats =====


## One switch. `strength` is the impact the table reported — the Vault's walk-out is the one
## beat in the game that wants a SOFT hit, and this is where that is judged.
## Returns HIT_OK (the beat advanced), HIT_GENTLE (right shot, too hard) or HIT_NONE.
func on_switch(group: StringName, strength: float = 0.0) -> StringName:
	if not active:
		return HIT_NONE
	var b := beat()
	if b.is_empty() or not _matches(b, group):
		return HIT_NONE
	if b.has("max_strength") and strength > float(b["max_strength"]):
		return HIT_GENTLE
	beat_hits += 1
	if beat_hits < int(b.get("count", 1)):
		return HIT_OK
	_advance(false)
	return HIT_OK


func _matches(b: Dictionary, group: StringName) -> bool:
	var any: Variant = b.get("any", null)
	if any is Array:
		for g: Variant in any as Array:
			if StringName(g) == group:
				return true
		return false
	return StringName(b.get("group", &"")) == group


## True on the tick a beat's window runs out (the caller turns that into the noise).
func tick(delta: float) -> bool:
	if not active or delta <= 0.0:
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	_advance(true)
	return true


func _advance(missed: bool) -> void:
	if missed:
		blown += 1
	beat_index += 1
	beat_hits = 0
	if beat_index >= _beats.size():
		_finish(true)
		return
	time_left = window_for(beat_index)


## A ball went down. Usually that is the job — unless the inside man had a way out.
## True if the heist is over because of it.
func on_ball_lost() -> bool:
	if not active:
		return false
	if spare_drains > 0:
		spare_drains -= 1
		return false
	_finish(false)
	return true


## The Night ended around it (or the run was torn down).
func abort() -> void:
	if active:
		_finish(false)


func _finish(ran_to_the_end: bool) -> void:
	active = false
	cleared = ran_to_the_end
	time_left = 0.0


# ====================================================================== the take =====


## The share of the nominal take this run earned. A cleared job with nothing blown is 1.0;
## a job that ended in a drain pays only for the beats that were actually finished. While the
## job is still live this is the preview — what it is worth if the crew gets out from here.
func take_share() -> float:
	var share := Heists.degrade_share(blown, effect) * float(effect.get("take", 1.0))
	if cleared or active:
		return share
	# Blown out mid-sequence: the crew gets out with what they had, pro-rata on the beats
	# that were closed. Nothing at all is not a setback, it is an erasure (P5).
	var done := float(beat_index) / float(maxi(_beats.size(), 1))
	return share * done


func state() -> Dictionary:
	var b := beat()
	return {
		"target": String(target),
		"name": target_name,
		"approach": String(approach),
		"active": active,
		"cleared": cleared,
		"beat": beat_index,
		"beats": _beats.size(),
		"line": String(b.get("line", "")) if not b.is_empty() else "",
		"need": int(b.get("count", 0)) if not b.is_empty() else 0,
		"hits": beat_hits,
		"time_left": time_left,
		"blown": blown,
		"guy": String(guy.get("name", "")),
	}
