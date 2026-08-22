class_name InputController
extends Node
## Two thumbs, portrait (docs/01 §1). Desktop keys are polled on the physics tick rather than
## read through `_input` so scripted/headless drivers can drive the exact same path via
## `Input.action_press()`. Touch adds zones on top: bottom 70 % splits into flipper halves,
## the shooter-lane column is a pull-and-release plunger, and the top strip takes nudge flicks.
##
## Hard rule from the design doc: no gesture may overlap a flipper zone during live play.

const FLIPPER_ZONE_TOP := 0.30          ## fraction of screen height where flipper zones start
const LANE_ZONE_LEFT := 940.0           ## design-space x where the shooter lane column begins
const LANE_ZONE_TOP := 1150.0
const PLUNGER_PULL_PX := 30.0
const FLICK_PX := 90.0
const FLICK_SECONDS := 0.18

var flipper_left: Flipper = null
var flipper_right: Flipper = null
var plunger: Plunger = null
var nudge: NudgeController = null
var enabled: bool = true

var _prev: Dictionary = {}
var _touches: Dictionary = {}           ## index -> { start: Vector2, at: float, role: StringName }


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
		var role := &"none"
		if ev.position.x >= LANE_ZONE_LEFT and ev.position.y >= LANE_ZONE_TOP:
			role = &"lane"
		elif ev.position.y >= size.y * FLIPPER_ZONE_TOP:
			role = &"flip_left" if ev.position.x < size.x * 0.5 else &"flip_right"
		else:
			role = &"flick"
		_touches[ev.index] = {"start": ev.position, "at": _now(), "role": role}
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
	if role == &"lane" and plunger != null and not plunger.charging:
		if delta.y >= PLUNGER_PULL_PX:
			plunger.set_pressed(true)
	elif role == &"flick" and nudge != null:
		if _now() - float(t["at"]) <= FLICK_SECONDS and absf(delta.x) >= FLICK_PX:
			nudge.nudge(&"left" if delta.x < 0.0 else &"right")
			t["role"] = &"spent"
			_touches[ev.index] = t


func _set_role(role: StringName, down: bool) -> void:
	match role:
		&"flip_left":
			if flipper_left != null:
				flipper_left.set_pressed(down)
		&"flip_right":
			if flipper_right != null:
				flipper_right.set_pressed(down)
		&"lane":
			if plunger != null and not down:
				plunger.set_pressed(false)


func _design_size() -> Vector2:
	return Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1080)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 1920))
	)


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
