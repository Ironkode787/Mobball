class_name InputController
extends Node
## Two thumbs, portrait (docs/01 §1). Desktop keys are polled on the physics tick rather than
## read through `_input` so scripted/headless drivers can drive the exact same path via
## `Input.action_press()`. Touch adds zones on top: bottom 70 % splits into flipper halves,
## the shooter-lane column is a pull-and-release plunger, and the upper field takes nudge
## flicks (with generous corner tap targets).
##
## Flipper touches remain authoritative: a horizontal nudge intent is additive and never
## cancels the held bat or its eventual release.

const FLIPPER_ZONE_TOP := 0.30          ## fraction of screen height where flipper zones start
const LANE_ZONE_LEFT := 940.0           ## design-space x where the shooter lane column begins
const LANE_ZONE_TOP := 1150.0
const NUDGE_CORNER_WIDTH := 360.0       ## broad, thumb-sized top-corner target in design px
const NUDGE_CORNER_HEIGHT := 420.0
const PLUNGER_PULL_PX := 30.0
const FLICK_PX := 90.0
const FLICK_SECONDS := 0.18

var flipper_left: Flipper = null
var flipper_right: Flipper = null
var plunger: Plunger = null
var nudge: NudgeController = null
var enabled: bool = true

var _prev: Dictionary = {}
var _touches: Dictionary = {}           ## index -> start/at/role/nudged touch state


func _ready() -> void:
	process_priority = -20
	process_physics_priority = -20
	set_process_unhandled_input(true)


func bind(p_left: Flipper, p_right: Flipper, p_plunger: Plunger, p_nudge: NudgeController) -> void:
	flipper_left = p_left
	flipper_right = p_right
	plunger = p_plunger
	nudge = p_nudge


func _physics_process(_delta: float) -> void:
	if not enabled:
		return
	_poll(&"flipper_left")
	_poll(&"flipper_right")
	_poll(&"plunger")
	for d: StringName in [&"nudge_left", &"nudge_right", &"nudge_up"]:
		if _edge(d) == 1 and nudge != null:
			nudge.nudge(StringName(String(d).substr(6)))


func _poll(action: StringName) -> void:
	var e := _edge(action)
	if e == 0:
		return
	var down := e == 1
	match action:
		&"flipper_left":
			if flipper_left != null:
				flipper_left.set_pressed(down)
		&"flipper_right":
			if flipper_right != null:
				flipper_right.set_pressed(down)
		&"plunger":
			if plunger != null:
				# Desktop has no pull distance; use the middle coarse band as its stable
				# default. Touch lanes set their band from drag distance instead.
				if e == 1 and plunger is BandedPlunger \
						and not (plunger as BandedPlunger).bands_enabled:
					(plunger as BandedPlunger).set_starter_band(BandedPlunger.DEFAULT_STARTER_BAND)
				plunger.set_pressed(down)


## 1 = pressed this tick, -1 = released this tick, 0 = unchanged.
func _edge(action: StringName) -> int:
	if not InputMap.has_action(action):
		return 0
	var now := Input.is_action_pressed(action)
	var was: bool = _prev.get(action, false)
	_prev[action] = now
	if now == was:
		return 0
	return 1 if now else -1


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)


func _on_touch(ev: InputEventScreenTouch) -> void:
	var size := _design_size()
	if ev.pressed:
		var role := classify_touch_role(ev.position, size)
		var t := {"start": ev.position, "at": _now(), "role": role, "nudged": false}
		var corner_dir := corner_nudge_direction(role)
		if corner_dir != &"":
			_issue_touch_nudge(t, corner_dir)
		_touches[ev.index] = t
		_set_role(role, true)
	else:
		var t: Dictionary = _touches.get(ev.index, {})
		if not t.is_empty():
			_set_role(t["role"], false)
			_touches.erase(ev.index)


func _on_drag(ev: InputEventScreenDrag) -> void:
	var t: Dictionary = _touches.get(ev.index, {})
	if t.is_empty():
		return
	var start: Vector2 = t["start"]
	var delta := ev.position - start
	var role: StringName = t["role"]
	var direction := drag_nudge_direction(role, delta, _now() - float(t["at"]))
	if direction != &"":
		_issue_touch_nudge(t, direction)
		_touches[ev.index] = t
	elif role == &"lane" and plunger != null:
		# A bare table has three coarse rubber-band pulls. Keep this branch local to the
		# lane drag: real plungers still use their inherited continuous charge, while the
		# nudge flick path above remains unchanged.
		if plunger is BandedPlunger and not (plunger as BandedPlunger).bands_enabled:
			(plunger as BandedPlunger).set_starter_pull(maxf(delta.y, 0.0))
		if not plunger.charging and delta.y >= PLUNGER_PULL_PX:
			plunger.set_pressed(true)


## Return the touch role at a screen point. Lane precedence is deliberate: a shooter-lane
## touch can never become a corner nudge, even if a future viewport moves the lane upward.
static func classify_touch_role(position: Vector2, size: Vector2) -> StringName:
	if position.x >= LANE_ZONE_LEFT and position.y >= LANE_ZONE_TOP:
		return &"lane"
	if position.y < NUDGE_CORNER_HEIGHT:
		if position.x < NUDGE_CORNER_WIDTH:
			return &"nudge_left"
		if position.x >= size.x - NUDGE_CORNER_WIDTH:
			return &"nudge_right"
	if position.y >= size.y * FLIPPER_ZONE_TOP:
		return &"flip_left" if position.x < size.x * 0.5 else &"flip_right"
	return &"flick"


static func corner_nudge_direction(role: StringName) -> StringName:
	if role == &"nudge_left":
		return &"left"
	if role == &"nudge_right":
		return &"right"
	return &""


## Classify one quick drag without consulting wall-clock state. Flippers accept horizontal
## nudges as an additive intent; they stay in their original role so release always drops the
## bat. The lane is intentionally excluded before any axis test.
static func drag_nudge_direction(role: StringName, delta: Vector2, elapsed: float) -> StringName:
	if role == &"lane" or role == &"nudge_left" or role == &"nudge_right":
		return &""
	if elapsed > FLICK_SECONDS:
		return &""
	if role == &"flick":
		if delta.y <= -FLICK_PX and absf(delta.y) >= absf(delta.x):
			return &"up"
		if absf(delta.x) >= FLICK_PX:
			return &"left" if delta.x < 0.0 else &"right"
	elif role == &"flip_left" or role == &"flip_right":
		if absf(delta.x) >= FLICK_PX:
			return &"left" if delta.x < 0.0 else &"right"
	return &""


func _issue_touch_nudge(t: Dictionary, direction: StringName) -> void:
	if bool(t.get("nudged", false)):
		return
	t["nudged"] = true
	if nudge != null:
		nudge.nudge(direction)


func _set_role(role: StringName, down: bool) -> void:
	match role:
		&"flip_left":
			if flipper_left != null:
				flipper_left.set_pressed(down)
		&"flip_right":
			if flipper_right != null:
				flipper_right.set_pressed(down)
		&"lane":
			if plunger != null:
				if down and plunger is BandedPlunger \
						and not (plunger as BandedPlunger).bands_enabled:
					(plunger as BandedPlunger).set_starter_band(BandedPlunger.DEFAULT_STARTER_BAND)
				# Starter plungers latch a touch-down only when a ball is ready; real plungers
				# begin their continuous charge here. Both paths release through the same edge.
				plunger.set_pressed(down)


func _design_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
