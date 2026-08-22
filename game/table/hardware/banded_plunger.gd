class_name BandedPlunger
extends Plunger
## The Drop-Off, at two levels of build-out. The machine as found has a rubber band where
## the plunger should be (docs/02 §2 R0): you get one launch strength, take it or leave it.
## `muscle.real_plunger` sets the `plunger_bands` flag and the real spring goes in — from
## then on this is the M0 plunger, charge bands and all, and plunge power becomes a skill.

var bands_enabled: bool = false
## Overridden by the table with ProgressionTable.PLUNGER_FIXED_POWER; hard enough to clear
## the arch on its own, because a launch that dies in the lane is not a game.
var fixed_power: float = 0.92


func set_pressed(pressed: bool) -> void:
	if bands_enabled:
		super.set_pressed(pressed)
		return
	if not enabled or pressed:
		return
	launch(fixed_power)


func release() -> void:
	if bands_enabled:
		super.release()
		return
	charging = false
	launch(fixed_power)


## Every launch goes through here, so the rubber band clamps scripted launches too — a bare
## table cannot be plunged at full power by the flow lane either.
func launch(p: float) -> void:
	super.launch(p if bands_enabled else fixed_power)
