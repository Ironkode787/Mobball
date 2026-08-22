class_name ButcherFight
extends BossFight
## THE BUTCHER — the R4→R5 ceremony (specs/m2-content.md §5, docs/05 §6).
##
## Sammy taught you to play without a bat. The Butcher teaches you the Getaway Loop as a
## weapon: his refrigerated truck rides the orbit channel and only a hit that arrives with
## real orbit pace does anything to it. Everything else rattles off the panel.
##
## Meanwhile the cans are cold storage — armored, worth nothing — and every payout they refuse
## is banked in a frost meter you can watch fill. Break the truck, break its door twice, and
## the last phase hands the whole freezer back through the bumpers you were not allowed to
## use. Lighting all three top lanes on the way through doubles it, which is the thing repeat
## fighters know and first-timers do not (spec §5: "hidden depth for repeat fights").
##
##   P1  the truck circles the orbit: three panels, ORBIT-SPEED hits only
##   P2  its back door, a six-panel bank, broken twice
##   P3  25 s of bumper frenzy paying the freezer out, doubled if all three lanes were lit
##
## Spoil: `cold_storage` — from then on any armored hardware banks half of what it denies and
## pays it out when the armor comes off (`Game.set_group_armored`).

## Panels in the truck, and how many times its door has to go down.
const TRUCK_PANELS := 3
const DOOR_BREAKS := 2
## Orbit pace, px/s at contact. A ball that came round the loop carries three or four times
## this; a dribble off a bumper does not. Tuned as the line between "arrived" and "leaked in".
const ORBIT_SPEED := 700.0
const TRUCK_SPEED := 250.0
## The frenzy: how long, and how many hits the freezer is cut into. Twelve pops in 25 s is a
## real race on a bumper nest — miss them and the rest of the freezer stays his.
const FRENZY_SECONDS := 25.0
const FRENZY_HITS := 12
## All three top lanes lit before the frenzy doubles every slice.
const ALL_LANES_MULT := 2.0
## Design knob: what fraction of a denied payout the freezer keeps. 1.0 is the honest reading
## of spec §5 ("every would-be payout banks"); it is a constant so tuning is a data change.
const FROZEN_SCALE := 1.0

var frozen: BigMoney = BigMoney.zero()
var frozen_paid: BigMoney = BigMoney.zero()
var panels_left: int = 0
var doors_broken: int = 0
var frenzy_left: float = 0.0
## Distinct top lanes rolled during P1–P2.
var lanes: Dictionary = {}

var _slice: BigMoney = BigMoney.zero()


func _init() -> void:
	phases = 3


func _enter_phase(n: int) -> void:
	match n:
		1:
			frozen = BigMoney.zero()
			frozen_paid = BigMoney.zero()
			lanes = {}
			panels_left = TRUCK_PANELS
			TableAPI.call_if(table, "set_boss_target",
					[&"truck", &"run", TRUCK_PANELS, ORBIT_SPEED])
			var truck: Variant = TableAPI.prop(table, "boss_truck", null)
			if truck is BossTarget:
				(truck as BossTarget).travel_speed = TRUCK_SPEED
			_freeze_cans(true)
		2:
			doors_broken = 0
			TableAPI.call_if(table, "set_boss_target", [&"truck", &"park", 0, 0.0])
			TableAPI.call_if(table, "set_boss_door", [true])
			_freeze_cans(true)
		3:
			# He is beaten the moment the door goes the second time; this phase is the payout.
			secured = true
			_freeze_cans(false)
			frenzy_left = FRENZY_SECONDS
			_slice = _slice_value()
	_show_meter()


## Cold storage on or off. The armor is real state on the money path, not a fiction — while
## it is on the cans pay nothing, and a career carrying the Butcher's own spoil banks half of
## what they refuse on top of the freezer.
func _freeze_cans(on: bool) -> void:
	if Game != null:
		Game.set_group_armored(&"bumpers", on)


func _on_release() -> void:
	_freeze_cans(false)
	TableAPI.call_if(table, "set_boss_meter", ["", 0.0])


# ================================================================== the freezer =====


## Every payout the paused economy refused. The cans are the only ones that bank.
func on_denied(group: StringName, value: BigMoney) -> void:
	if group != &"bumpers" or value == null or not value.is_positive():
		return
	if phase < 3:
		frozen = frozen.add(value.mul(FROZEN_SCALE))
		_show_meter()
		return
	if frenzy_left <= 0.0:
		return
	_pay_slice()


## What one frenzy pop is worth: the freezer cut into twelve, doubled if all three lanes were
## lit on the way here.
func _slice_value() -> BigMoney:
	if not frozen.is_positive():
		return BigMoney.zero()
	var mult := 1.0 / float(FRENZY_HITS)
	if lanes_all_lit():
		mult *= ALL_LANES_MULT
	return frozen.mul(mult)


func lanes_all_lit() -> bool:
	return lanes.size() >= int(Switches.COVER_SIZE.get(&"rollovers", 3))


func frozen_left() -> BigMoney:
	return frozen.sub_clamped(frozen_paid)


func _pay_slice() -> void:
	var left := frozen_left()
	if not left.is_positive():
		return
	var pay := BigMoney.min_of(_slice, left)
	if not pay.is_positive():
		return
	frozen_paid = frozen_paid.add(pay)
	if Game != null:
		Game.boss_payout(pay, id)
	AudioDirector.play(&"cash_tick")
	_show_meter()
	announce()


func _show_meter() -> void:
	var total := frozen
	if not total.is_positive():
		TableAPI.call_if(table, "set_boss_meter", ["COLD STORAGE   $0", 0.0])
		return
	var left := frozen_left()
	var label := "COLD STORAGE   %s" % left.text()
	if phase >= 3 and lanes_all_lit():
		label += "   x2"
	TableAPI.call_if(table, "set_boss_meter", [label, left.ratio_to(total)])


# ==================================================================== the fight =====


func _tick(delta: float) -> void:
	if phase < 3:
		return
	frenzy_left = maxf(frenzy_left - delta, 0.0)
	if frenzy_left <= 0.0:
		# Whatever is still frozen stays his: the frenzy is a race, not a receipt.
		_go_to_phase(phase + 1)


func _on_hit(kind: StringName, hits_left: int, _speed: float) -> void:
	if kind == &"truck":
		panels_left = hits_left
		announce()
	elif kind == &"door":
		announce()


func _on_shrug(kind: StringName, _speed: float) -> void:
	if kind == &"truck":
		AudioDirector.play(&"wall_tap")


func _on_down(kind: StringName) -> void:
	match kind:
		&"truck":
			panels_left = 0
			_go_to_phase(phase + 1)
		&"door":
			doors_broken += 1
			announce()
			if doors_broken >= DOOR_BREAKS:
				_go_to_phase(phase + 1)


func on_rollover(index: int, _was_lit: bool) -> void:
	if phase >= 3 or index < 0:
		return
	lanes[index] = true
	announce()


func phase_line() -> String:
	match phase:
		1:
			return "THE MEAT TRUCK   ·   %d PANELS   ·   ORBIT SPEED ONLY   ·   %s" \
					% [panels_left, _lanes_text()]
		2:
			return "THE BACK DOOR   ·   %d/%d   ·   %s" % [doors_broken, DOOR_BREAKS, _lanes_text()]
		3:
			return "BUMPER FRENZY   ·   %0.1fs   ·   %s%s" % [frenzy_left, frozen_left().text(),
					"   x2" if lanes_all_lit() else ""]
	return ""


func _lanes_text() -> String:
	return "LANES %d/3" % lanes.size()


func state() -> Dictionary:
	var s := super.state()
	s["panels"] = panels_left
	s["doors"] = doors_broken
	s["frozen"] = frozen.copy()
	s["frozen_left"] = frozen_left()
	s["frozen_paid"] = frozen_paid.copy()
	s["lanes"] = lanes.size()
	s["frenzy_left"] = frenzy_left
	return s
