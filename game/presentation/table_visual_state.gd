class_name TableVisualState
extends RefCounted
## Draw-only vocabulary shared by table families and screen-space feedback.
## This resource classifies presentation; it never owns gameplay state or timing.

enum VisualState {
	IDLE,
	ARMED,
	ACTIVE,
	COMPLETED,
	DISABLED,
	DANGER,
}

enum LampChannel {
	AMBIENT_ATTRACT,
	CURRENT_OBJECTIVE,
	RECENT_HIT,
	MODE_START,
	JACKPOT,
	COOLDOWN,
}

enum FeedbackLevel {
	MICRO_HIT,
	REWARD,
	CONSEQUENCE,
	CEREMONY,
}

enum LocalModifier {
	PULSE,
	FLASH,
	COOLDOWN,
	TELEGRAPH,
	HELD,
	MARKED,
	DOWN,
	DEAD,
	JAM,
	MOVING,
	PARKED,
	RAID_PHASE,
	BOSS_PHASE,
}

const STATE_NAMES: Array[StringName] = [
	&"idle", &"armed", &"active", &"completed", &"disabled", &"danger",
]
const LOCAL_MODIFIERS: Array[StringName] = [
	&"pulse", &"flash", &"cooldown", &"telegraph", &"held", &"marked", &"down",
	&"dead", &"jam", &"moving", &"parked", &"raid_phase", &"boss_phase",
]
const LAMP_CHANNEL_NAMES: Array[StringName] = [
	&"ambient_attract", &"current_objective", &"recent_hit", &"mode_start", &"jackpot",
	&"cooldown",
]
const FEEDBACK_LEVEL_NAMES: Array[StringName] = [
	&"micro_hit", &"reward", &"consequence", &"ceremony",
]

# Larger values win. Mode start sits below danger and above a source-local recent hit.
const LAMP_PRIORITIES: Dictionary = {
	&"ambient_attract": 100,
	&"current_objective": 200,
	&"recent_hit": 300,
	&"mode_start": 350,
	&"danger": 500,
	&"jackpot": 600,
	&"cooldown": 10,
}

const STATE_MARKS: Dictionary = {
	&"idle": &"outline",
	&"armed": &"invitation_pin",
	&"active": &"contact_pulse",
	&"completed": &"check_stamp",
	&"disabled": &"lock_offline",
	&"danger": &"hazard_hatch",
}
const STATE_MATERIALS: Dictionary = {
	&"idle": &"ink_glass",
	&"armed": &"brass",
	&"active": &"brass",
	&"completed": &"newsprint",
	&"disabled": &"ink_glass",
	&"danger": &"aged_paper",
}
const STATE_PATTERNS: Dictionary = {
	&"idle": &"stable_outline",
	&"armed": &"directional_pin",
	&"active": &"bounded_pulse",
	&"completed": &"settled_stamp",
	&"disabled": &"offline_hatch",
	&"danger": &"hazard_hatch",
}
const FEEDBACK_BY_KIND: Dictionary = {
	&"impact": &"micro_hit",
	&"currency": &"reward",
	&"combo": &"reward",
	&"launder": &"reward",
	&"drain": &"consequence",
	&"pinch": &"consequence",
	&"bail": &"consequence",
	&"warning": &"consequence",
	&"mode": &"ceremony",
	&"jackpot": &"ceremony",
	&"rank": &"ceremony",
	&"boss": &"ceremony",
}

# D3 semantic feedback metadata. Priority is deliberately descriptive: D4 may use it
# when arbitrating subtitles/toasts, while GameplayFeedback keeps its existing pool
# saturation policy. These are not an eviction order.
const FEEDBACK_PRIORITY_NAMES: Array[StringName] = [
	&"P0", &"P1", &"P2", &"P3",
]
const FEEDBACK_DESTINATIONS: Array[StringName] = [
	&"source", &"reward", &"consequence", &"ceremony",
]
const FEEDBACK_SATURATION := {
	&"impact": &"same_kind_oldest_only",
	&"currency": &"same_kind_oldest_only",
}


static func state_name(state: int) -> StringName:
	return STATE_NAMES[clampi(state, 0, STATE_NAMES.size() - 1)]


static func state_from(value: Variant, fallback: int = VisualState.IDLE) -> int:
	if value is int:
		return clampi(int(value), 0, STATE_NAMES.size() - 1)
	var wanted := String(value).to_lower()
	for i in STATE_NAMES.size():
		if String(STATE_NAMES[i]) == wanted:
			return i
	return clampi(fallback, 0, STATE_NAMES.size() - 1)


static func modifiers(raw: Variant = {}) -> Dictionary:
	var out: Dictionary = {}
	for modifier: StringName in LOCAL_MODIFIERS:
		out[modifier] = false
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			var name := StringName(String(key).to_lower())
			if out.has(name):
				out[name] = bool((raw as Dictionary).get(key, false))
	elif raw is Array:
		for item: Variant in raw as Array:
			var name := StringName(String(item).to_lower())
			if out.has(name):
				out[name] = true
	elif raw is String or raw is StringName:
		var name := StringName(String(raw).to_lower())
		if out.has(name):
			out[name] = true
	return out


static func state_mark(state: int, local_modifiers: Variant = {}) -> StringName:
	var name := state_name(state)
	var mods := modifiers(local_modifiers)
	if name == &"disabled" and bool(mods[&"cooldown"]):
		return &"cooldown_clock"
	if name == &"disabled" and bool(mods[&"dead"]):
		return &"offline_cross"
	if name == &"danger" and bool(mods[&"jam"]):
		return &"jam_alert"
	if name == &"danger" and bool(mods[&"telegraph"]):
		return &"telegraph_hatch"
	if name == &"active" and bool(mods[&"held"]):
		return &"held_ring"
	if name == &"completed" and (bool(mods[&"marked"]) or bool(mods[&"down"])):
		return &"marked_stamp"
	return StringName(STATE_MARKS.get(name, &"outline"))


static func state_material(state: int, local_modifiers: Variant = {}) -> StringName:
	var name := state_name(state)
	var mods := modifiers(local_modifiers)
	if name == &"disabled" and bool(mods[&"cooldown"]):
		return &"aged_paper"
	return StringName(STATE_MATERIALS.get(name, &"ink_glass"))


static func state_pattern(state: int, local_modifiers: Variant = {}) -> StringName:
	var name := state_name(state)
	var mods := modifiers(local_modifiers)
	if name == &"disabled" and bool(mods[&"cooldown"]):
		return &"cooldown_dash"
	if name == &"active" and bool(mods[&"held"]):
		return &"held_ring"
	if name == &"danger" and bool(mods[&"telegraph"]):
		return &"telegraph_hatch"
	return StringName(STATE_PATTERNS.get(name, &"stable_outline"))


static func state_token(state: int, local_modifiers: Variant = {}) -> Dictionary:
	var mods := modifiers(local_modifiers)
	var name := state_name(state)
	return {
		"state": name,
		"state_id": clampi(state, 0, STATE_NAMES.size() - 1),
		"mark": state_mark(state, mods),
		"material": state_material(state, mods),
		"pattern": state_pattern(state, mods),
		"modifiers": mods,
		"invitation": name == &"armed" and not bool(mods[&"cooldown"]),
		"grayscale_cue": state_pattern(state, mods),
	}


static func lamp_channel(value: Variant, fallback: int = LampChannel.AMBIENT_ATTRACT) -> StringName:
	if value is int:
		var index := clampi(int(value), 0, LAMP_CHANNEL_NAMES.size() - 1)
		return LAMP_CHANNEL_NAMES[index]
	var wanted := String(value).to_lower()
	if wanted == "danger":
		return &"danger"
	return StringName(wanted) if LAMP_CHANNEL_NAMES.has(StringName(wanted)) \
			else LAMP_CHANNEL_NAMES[clampi(fallback, 0, LAMP_CHANNEL_NAMES.size() - 1)]


static func lamp_priority(channel: Variant, state: int = -1, local_modifiers: Variant = {}) -> int:
	var name := lamp_channel(channel)
	var mods := modifiers(local_modifiers)
	var state_name_value := state_name(state) if state >= 0 else &""
	# Suppression is separate from priority: callers can still audit which channel requested a cue.
	if state_name_value == &"disabled" or bool(mods[&"cooldown"]):
		if name != &"cooldown":
			return 0
	return int(LAMP_PRIORITIES.get(name, 0))


static func lamp_is_invitation(channel: Variant, state: int, local_modifiers: Variant = {}) -> bool:
	var name := lamp_channel(channel)
	var mods := modifiers(local_modifiers)
	return name == &"current_objective" and state_name(state) == &"armed" \
			and not bool(mods[&"cooldown"])


static func lamp_priority_order() -> Array[StringName]:
	return [&"jackpot", &"danger", &"mode_start", &"recent_hit", &"current_objective",
			&"ambient_attract", &"cooldown"]


static func feedback_level(kind: StringName) -> int:
	var name := StringName(FEEDBACK_BY_KIND.get(kind, &"consequence"))
	for i in FEEDBACK_LEVEL_NAMES.size():
		if FEEDBACK_LEVEL_NAMES[i] == name:
			return i
	return FeedbackLevel.CONSEQUENCE


static func feedback_level_name(level: int) -> StringName:
	return FEEDBACK_LEVEL_NAMES[clampi(level, 0, FEEDBACK_LEVEL_NAMES.size() - 1)]


static func feedback_state(kind: StringName, payload: Dictionary = {}) -> int:
	match kind:
		&"drain", &"warning":
			return VisualState.DANGER
		&"jackpot", &"rank":
			return VisualState.COMPLETED
		&"boss":
			return VisualState.ACTIVE if bool(payload.get("active", false)) \
				else VisualState.COMPLETED
		&"mode":
			return VisualState.ACTIVE if bool(payload.get("active", true)) else VisualState.COMPLETED
		&"impact", &"currency", &"combo", &"launder":
			return VisualState.ACTIVE
		&"pinch", &"bail":
			return VisualState.DANGER
	return VisualState.ACTIVE


static func _feedback_override_level(kind: StringName, payload: Dictionary) -> int:
	var raw: Variant = payload.get("_feedback_level", payload.get("feedback_level", null))
	if raw == null:
		return feedback_level(kind)
	if raw is int:
		return clampi(int(raw), 0, FeedbackLevel.CEREMONY)
	var wanted := String(raw).to_lower()
	for i in FEEDBACK_LEVEL_NAMES.size():
		if String(FEEDBACK_LEVEL_NAMES[i]) == wanted:
			return i
	return feedback_level(kind)


static func _feedback_override_state(kind: StringName, payload: Dictionary, fallback: int) -> int:
	var raw: Variant = payload.get("_feedback_state", payload.get("feedback_state", null))
	if raw == null:
		return fallback
	return state_from(raw, fallback)


static func _feedback_destination(level: int, kind: StringName, payload: Dictionary) -> StringName:
	var raw: Variant = payload.get("_feedback_destination",
			payload.get("_destination_class", payload.get("destination_class", null)))
	if raw != null and not String(raw).is_empty():
		return StringName(String(raw).to_lower())
	if kind == &"currency":
		return &"hud_clean" if StringName(payload.get("currency", &"dirty")) == &"clean" \
				else &"hud_dirty"
	if kind == &"launder":
		return &"ceremony"
	return FEEDBACK_DESTINATIONS[clampi(level, 0, FEEDBACK_DESTINATIONS.size() - 1)]


static func _feedback_priority(level: int, payload: Dictionary) -> int:
	var raw: Variant = payload.get("_feedback_priority", payload.get("priority_id", null))
	if raw == null:
		return clampi(level, 0, FEEDBACK_PRIORITY_NAMES.size() - 1)
	if raw is int:
		return clampi(int(raw), 0, FEEDBACK_PRIORITY_NAMES.size() - 1)
	var wanted := String(raw).to_upper()
	for i in FEEDBACK_PRIORITY_NAMES.size():
		if String(FEEDBACK_PRIORITY_NAMES[i]) == wanted:
			return i
	return clampi(level, 0, FEEDBACK_PRIORITY_NAMES.size() - 1)


static func reduced_effects(reduced_motion: bool, reduced_flash: bool) -> Dictionary:
	return {
		"motion_scale": 0.0 if reduced_motion else 1.0,
		"flash_scale": 0.25 if reduced_flash else 1.0,
		"travel": not reduced_motion,
		"scale": not reduced_motion,
		"rays": not reduced_motion,
		"chase": not reduced_flash,
		"telegraph": not reduced_flash,
	}


static func feedback_destination(level: int, source: Vector2, viewport_size: Vector2,
		margins: Vector4) -> Vector2:
	var min_x := clampf(margins.x, 0.0, viewport_size.x)
	var max_x := clampf(viewport_size.x - margins.z, min_x, viewport_size.x)
	var min_y := clampf(margins.y, 0.0, viewport_size.y)
	var max_y := clampf(viewport_size.y - margins.w, min_y, viewport_size.y)
	match clampi(level, 0, FeedbackLevel.CEREMONY):
		FeedbackLevel.MICRO_HIT:
			return Vector2(clampf(source.x, min_x, max_x), clampf(source.y, min_y, max_y))
		FeedbackLevel.REWARD:
			return Vector2(clampf(source.x, min_x, max_x), clampf(source.y, min_y, max_y))
		FeedbackLevel.CONSEQUENCE:
			return Vector2(max_x - minf(220.0, max_x - min_x),
				clampf(max_y - 220.0, min_y, max_y))
		FeedbackLevel.CEREMONY:
			return Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
	return Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)


static func feedback_contract(kind: StringName, payload: Dictionary = {}) -> Dictionary:
	var level := _feedback_override_level(kind, payload)
	var state := _feedback_override_state(kind, payload, feedback_state(kind, payload))
	var priority_id := _feedback_priority(level, payload)
	var priority := FEEDBACK_PRIORITY_NAMES[priority_id]
	var duration_kind: StringName = StringName(payload.get("_duration_kind", kind))
	var suppression := StringName(payload.get("_suppression", &"none"))
	var saturation := StringName(payload.get("_saturation",
			FEEDBACK_SATURATION.get(kind, &"drop_at_capacity")))
	var haptic: Dictionary = {}
	var haptic_value: Variant = payload.get("_haptic", {})
	if haptic_value is Dictionary:
		haptic = haptic_value
	return {
		"event_id": StringName(String(payload.get("_event_id", kind))),
		"event_identity": StringName(String(payload.get("_event_id", kind))),
		"kind": kind,
		"level": feedback_level_name(level),
		"level_id": level,
		"state": state_name(state),
		"state_id": state,
		"source": payload.get("screen_position", Vector2(-1.0, -1.0)),
		"destination": _feedback_destination(level, kind, payload),
		"destination_class": _feedback_destination(level, kind, payload),
		"duration_kind": duration_kind,
		"priority": priority,
		"priority_id": priority_id,
		"semantic_priority": feedback_level_name(priority_id),
		"suppression": suppression,
		"saturation": saturation,
		"replacement": saturation,
		"haptic": haptic.duplicate(true),
		"teardown": &"clear_on_state_change",
		"clear_on_state_change": true,
		"reown": &"main_route_owner",
		"reduced_motion": float(payload.get("motion_scale", 1.0)) <= 0.0,
		"reduced_flash": float(payload.get("flash_scale", 1.0)) < 1.0,
	}
