class_name BandedPlunger
extends Plunger
## The Drop-Off, at two levels of build-out. Before `muscle.real_plunger`, the rubber band
## offers three deliberately coarse pulls — enough to feed this geometry, but not enough to
## aim a skill shot precisely. The upgrade keeps the same hardware node and turns on the real
## Plunger charge/detent path, so a player gets continuous precision rather than a fourth band.

## These are intentionally safe launch powers. The shipped geometry starts to miss the arch
## below roughly 0.90, so the starter agency is bounded to reliable feeds.
const STARTER_POWERS := [0.55, 0.58, 0.80]
## Touch pulls are mapped to these bands in 64 px steps; desktop input keeps the middle band.
const STARTER_BAND_DISTANCE_PX := 64.0
const DEFAULT_STARTER_BAND := 1

var bands_enabled: bool = false
var starter_powers: Array = STARTER_POWERS
var starter_band: int = DEFAULT_STARTER_BAND
var starter_pull_px: float = 0.0
## Kept as a scene/script compatibility field for old table fixtures. Starter launches use
## `starter_band`, not this legacy scalar.
var fixed_power: float = STARTER_POWERS[DEFAULT_STARTER_BAND]
## A starter release is meaningful only after a press saw a ball ready in the lane. This
## prevents a stale touch-up (or a release after the ball has been removed) from firing.
var _starter_press_armed: bool = false


## Feed the coarse starter agency from a touch's downward pull distance. Real-plunger users
## keep the inherited analog charge path; their touch drag never changes this value.
func set_starter_pull(distance_px: float) -> void:
	if bands_enabled or starter_powers.is_empty():
		return
	starter_pull_px = maxf(distance_px, 0.0)
	starter_band = clampi(int(floor(starter_pull_px / STARTER_BAND_DISTANCE_PX)),
			0, starter_powers.size() - 1)


func set_starter_band(index: int) -> void:
	if bands_enabled or starter_powers.is_empty():
		return
	starter_band = clampi(index, 0, starter_powers.size() - 1)


func starter_power() -> float:
	if starter_powers.is_empty():
		return 0.95
	return starter_powers[clampi(starter_band, 0, starter_powers.size() - 1)]


## The visible lane is owned by GameHUD.PlungerLane. This metadata lets that owner and evidence
## fixtures render the native plunger state without duplicating charge or changing launch logic.
func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not enabled:
		state = TableVisualState.VisualState.DISABLED
	elif charging:
		state = TableVisualState.VisualState.ACTIVE
		mods.append(&"moving")
	var token := TableVisualState.state_token(state, mods)
	token["draw_owner"] = &"hud.plunger_lane"
	token["bands_enabled"] = bands_enabled
	token["starter_band"] = clampi(starter_band, 0, maxi(starter_powers.size() - 1, 0))
	token["starter_power"] = starter_power()
	token["starter_pull_px"] = maxf(starter_pull_px, 0.0)
	token["charge"] = clampf(power, 0.0, 1.0)
	return token


func set_pressed(pressed: bool) -> void:
	if bands_enabled:
		_starter_press_armed = false
		super.set_pressed(pressed)
		return
	if not enabled:
		_starter_press_armed = false
		return
	if pressed:
		_starter_press_armed = ball_ready()
		return
	if _starter_press_armed:
		launch(starter_power())
	_starter_press_armed = false


func release() -> void:
	if bands_enabled:
		super.release()
		return
	charging = false
	if _starter_press_armed:
		launch(starter_power())
	_starter_press_armed = false


## Every launch goes through here, so the starter rubber band clamps scripted launches too —
## a bare table cannot be plunged at full power by the flow lane without selecting its top band.
func launch(p: float) -> void:
	super.launch(p if bands_enabled else starter_power())
