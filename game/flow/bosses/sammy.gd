class_name SammyFight
extends BossFight
## SAMMY TWO-FLIPPERS — the R3→R4 ceremony (specs/m2-content.md §5, docs/05 §6).
##
## Sammy's whole idea is that he takes a bat off you on a schedule. Every pulse a wrench gag
## rattles the linkage for two seconds and then jams one flipper for a second and a half:
## enough to lose a cradled ball, not enough to lose the Night, and always announced. The
## right answer is to stop cradling and start planning, which is the lesson the fight exists
## to teach — one-flipper pinball on demand.
##
##   P1  his sedan crosses the waist on a rail: four panels, wrench every 8 s
##   P2  three goons stand in front of the cans (armored: the bumpers are worth nothing)
##   P3  the sedan parks in the middle: three panels, wrench every 5 s
##
## Spoil: `sammys_spare` — once a Night the next jam falls out on its own and hands back a
## Lean, and every jam after it lasts a third as long. That is spent by the NightController
## (`jam_flipper`), because the Lean belongs to the Night, not to Sammy.

## Panels per phase. Four then three: the parked car is easier to hit and the wrench is faster.
const P1_PANELS := 4
const P3_PANELS := 3
## The rail is a moving target, not a wall: slow enough to lead, fast enough to miss.
const SEDAN_SPEED := 240.0
## Wrench cadence. Eight seconds is one cradle-and-think; five is not.
const JAM_PERIOD := 8.0
const JAM_PERIOD_FAST := 5.0
## Two seconds of gag before the linkage goes (spec §5), then a second and a half of nothing.
const TELEGRAPH := 2.0
const JAM_SECONDS := 1.5

var panels_left: int = 0
var goons_left: int = 0

var _jam_in: float = 0.0
var _told: bool = false
var _side: StringName = &"left"


func _init() -> void:
	phases = 3


func _enter_phase(n: int) -> void:
	_jam_in = _period()
	_told = false
	match n:
		1:
			panels_left = P1_PANELS
			_set_sedan(&"run", P1_PANELS)
		2:
			goons_left = 3
			TableAPI.call_if(table, "set_boss_goons", [true])
			# His crew is holding the cans shut: they pay nothing, and anyone carrying Cold
			# Storage banks half of what they refuse (specs/m2-content.md §5).
			if Game != null:
				Game.set_group_armored(&"bumpers", true)
		3:
			panels_left = P3_PANELS
			_set_sedan(&"park", P3_PANELS)


func _set_sedan(mode: StringName, hits: int) -> void:
	TableAPI.call_if(table, "set_boss_target", [&"sedan", mode, hits, 0.0])
	var sedan: Variant = TableAPI.prop(table, "boss_sedan", null)
	if sedan is BossTarget:
		(sedan as BossTarget).travel_speed = SEDAN_SPEED


func _on_release() -> void:
	if Game != null:
		Game.set_group_armored(&"bumpers", false)


func _period() -> float:
	return JAM_PERIOD_FAST if phase >= 3 else JAM_PERIOD


# ===================================================================== the wrench =====


func _tick(delta: float) -> void:
	_jam_in -= delta
	if not _told and _jam_in <= TELEGRAPH:
		_told = true
		_telegraph(_side, TELEGRAPH)
		AudioDirector.play(&"wrench_telegraph")
	if _jam_in > 0.0:
		return
	_jam_in = _period()
	_told = false
	# The Spare may eat this one; either way the next wrench goes to the other bat, so a
	# player who has learned the rhythm is never surprised by which hand it takes.
	_jam(_side, JAM_SECONDS)
	_side = &"right" if _side == &"left" else &"left"
	announce()


# ===================================================================== the fight =====


func _on_hit(kind: StringName, hits_left: int, _speed: float) -> void:
	if kind == &"sedan":
		panels_left = hits_left
		announce()
	elif kind == &"goon":
		goons_left = hits_left
		announce()


func _on_down(kind: StringName) -> void:
	match kind:
		&"sedan":
			panels_left = 0
			_go_to_phase(phase + 1)
		&"goon":
			goons_left = 0
			if Game != null:
				Game.set_group_armored(&"bumpers", false)
			_go_to_phase(phase + 1)


func phase_line() -> String:
	match phase:
		1:
			return "SAMMY'S SEDAN   ·   %d PANELS   ·   WRENCH EVERY %ds" \
					% [panels_left, int(JAM_PERIOD)]
		2:
			return "HIS CREW HAS THE CANS   ·   %d GOONS STANDING" % goons_left
		3:
			return "HE'S PARKED   ·   %d PANELS   ·   WRENCH EVERY %ds" \
					% [panels_left, int(JAM_PERIOD_FAST)]
	return ""


func state() -> Dictionary:
	var s := super.state()
	s["panels"] = panels_left
	s["goons"] = goons_left
	s["jam_in"] = maxf(_jam_in, 0.0)
	return s
