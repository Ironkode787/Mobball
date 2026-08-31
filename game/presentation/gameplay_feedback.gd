class_name GameplayFeedback
extends Control
## Pooled, screen-space gameplay feedback. This node never owns or mutates table, camera,
## collider, or timer state: it consumes immutable event payloads and draws one overlay.

const TABLE_VISUAL_STATE := preload("res://game/presentation/table_visual_state.gd")
const MAX_EFFECTS := 12
const MOBILE_PLATFORMS: PackedStringArray = ["Android", "iOS"]
const HAPTIC_COOLDOWN_MS := 55

const DURATIONS := {
	&"impact": 0.34,
	&"currency": 0.72,
	&"launder": 0.9,
	&"combo": 0.82,
	&"drain": 0.72,
	&"pinch": 1.0,
	&"bail": 0.88,
	&"mode": 1.08,
	&"jackpot": 1.48,
	&"rank": 1.28,
	&"boss": 1.18,
	&"warning": 0.92,
}

const HAPTIC_DURATIONS := {
	&"impact": 26,
	&"combo": 54,
	&"currency": 32,
	&"launder": 58,
	&"drain": 110,
	&"pinch": 92,
	&"bail": 48,
	&"mode": 86,
	&"jackpot": 175,
	&"rank": 135,
	&"boss": 105,
	&"warning": 72,
}

var _bus: EffectBus = null
var _budget: PresentationBudget = null
var _safe: PresentationSafeArea = null
var _slots: Array[Dictionary] = []
var _serial := 0
var _last_haptic_ms := -HAPTIC_COOLDOWN_MS
var _last_haptic: Dictionary = {}
var emitted_count := 0
var dropped_count := 0
var haptic_count := 0


func _init() -> void:
	for i in MAX_EFFECTS:
		_slots.append({"active": false})


func _ready() -> void:
	# A CanvasLayer is not a Control parent, so viewport-root anchors resolve to zero size.
	# Keep top-left anchors and explicitly mirror the logical viewport instead.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_resize_to_viewport()
	get_viewport().size_changed.connect(_resize_to_viewport)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 500
	set_process(true)


func _resize_to_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size
	queue_redraw()


func configure(bus: EffectBus, budget: PresentationBudget,
		safe_area: PresentationSafeArea) -> void:
	if _bus != null:
		var old_effect := Callable(self, "_on_effect")
		var old_haptic := Callable(self, "_on_haptic")
		if _bus.effect_requested.is_connected(old_effect):
			_bus.effect_requested.disconnect(old_effect)
		if _bus.haptic_requested.is_connected(old_haptic):
			_bus.haptic_requested.disconnect(old_haptic)
	_bus = bus
	_budget = budget
	_safe = safe_area
	if _bus != null:
		_bus.effect_requested.connect(_on_effect)
		_bus.haptic_requested.connect(_on_haptic)


func _exit_tree() -> void:
	clear()


func _process(delta: float) -> void:
	var changed := false
	for slot in _slots:
		if not bool(slot.get("active", false)):
			continue
		slot["elapsed"] = float(slot.get("elapsed", 0.0)) + maxf(delta, 0.0)
		if float(slot["elapsed"]) >= float(slot.get("duration", 0.1)):
			_release(slot)
		changed = true
	if changed:
		queue_redraw()


func _on_effect(kind: StringName, payload: Dictionary) -> void:
	if kind == &"combo" and int(payload.get("count", 0)) < 2:
		return
	var slot := _acquire(kind)
	if slot.is_empty():
		dropped_count += 1
		return
	_serial += 1
	slot["active"] = true
	slot["kind"] = kind
	slot["payload"] = payload.duplicate(true)
	slot["elapsed"] = 0.0
	slot["duration"] = float(DURATIONS.get(kind, 0.8))
	slot["serial"] = _serial
	slot["motion_scale"] = clampf(float(payload.get("motion_scale", 1.0)), 0.0, 1.0)
	slot["flash_scale"] = clampf(float(payload.get("flash_scale", 1.0)), 0.0, 1.0)
	var contract: Dictionary = payload.get("_presentation", {})
	if contract.is_empty():
		contract = TABLE_VISUAL_STATE.feedback_contract(kind, payload)
	var level := TABLE_VISUAL_STATE.feedback_level(kind)
	var state := TABLE_VISUAL_STATE.feedback_state(kind, payload)
	if contract.has("level_id"):
		level = int(contract["level_id"])
	if contract.has("state"):
		state = TABLE_VISUAL_STATE.state_from(contract["state"], state)
	slot["feedback_level"] = level
	slot["level"] = TABLE_VISUAL_STATE.feedback_level_name(level)
	slot["state"] = TABLE_VISUAL_STATE.state_name(state)
	slot["event_id"] = contract.get("event_id", kind)
	slot["event_identity"] = contract.get("event_identity", slot["event_id"])
	slot["state_id"] = state
	slot["destination"] = contract.get("destination", contract.get("destination_class", &"source"))
	slot["destination_class"] = contract.get("destination_class", slot["destination"])
	slot["duration_kind"] = contract.get("duration_kind", kind)
	slot["priority"] = contract.get("priority", &"P0")
	slot["priority_id"] = int(contract.get("priority_id", level))
	slot["semantic_priority"] = contract.get("semantic_priority", slot["level"])
	slot["suppression"] = contract.get("suppression", &"none")
	slot["saturation"] = contract.get("saturation", contract.get("replacement", &"drop_at_capacity"))
	slot["replacement"] = contract.get("replacement", slot["saturation"])
	slot["haptic"] = contract.get("haptic", {})
	slot["teardown"] = contract.get("teardown", &"clear_on_state_change")
	slot["reown"] = contract.get("reown", &"main_route_owner")
	slot["clear_on_state_change"] = bool(contract.get("clear_on_state_change", true))
	slot["mark"] = TABLE_VISUAL_STATE.state_mark(state, _feedback_modifiers(kind, payload))
	slot["pattern"] = TABLE_VISUAL_STATE.state_pattern(state, _feedback_modifiers(kind, payload))
	slot["source"] = contract.get("source", payload.get("screen_position", Vector2(-1.0, -1.0)))
	slot["text"] = _effect_text(kind, payload)
	emitted_count += 1
	queue_redraw()


func _on_haptic(pattern: StringName, strength: float) -> void:
	var now := Time.get_ticks_msec()
	var clamped := clampf(strength, 0.0, 1.0)
	var duration := int(HAPTIC_DURATIONS.get(pattern, 45))
	# Let a ceremony replace a same-frame switch tick; never let the tick mask the ceremony.
	if now - _last_haptic_ms < HAPTIC_COOLDOWN_MS \
			and duration <= int(_last_haptic.get("duration_ms", 0)):
		return
	_last_haptic_ms = now
	_last_haptic = {"pattern": pattern, "strength": clamped, "duration_ms": duration}
	haptic_count += 1
	if MOBILE_PLATFORMS.has(OS.get_name()):
		Input.vibrate_handheld(duration, clamped)


func _acquire(kind: StringName) -> Dictionary:
	for slot in _slots:
		if not bool(slot.get("active", false)):
			return _activate_budget(slot)
	# Frequent sparks and cash trails yield to ceremony, but replace their own oldest peer.
	if kind == &"impact" or kind == &"currency":
		var oldest: Dictionary = {}
		for slot in _slots:
			if StringName(slot.get("kind", &"")) != kind:
				continue
			if oldest.is_empty() or int(slot.get("serial", 0)) < int(oldest.get("serial", 0)):
				oldest = slot
		if not oldest.is_empty():
			_release(oldest)
			return _activate_budget(oldest)
	return {}


func _activate_budget(slot: Dictionary) -> Dictionary:
	if _budget != null and not _budget.register(&"emitters"):
		_budget.release(&"emitters")
		return {}
	slot["budgeted"] = _budget != null
	return slot


func _release(slot: Dictionary) -> void:
	if not bool(slot.get("active", false)):
		return
	if bool(slot.get("budgeted", false)) and _budget != null:
		_budget.release(&"emitters")
	slot.clear()
	slot["active"] = false


func clear() -> void:
	for slot in _slots:
		_release(slot)
	queue_redraw()


func active_count() -> int:
	var total := 0
	for slot in _slots:
		if bool(slot.get("active", false)):
			total += 1
	return total


func snapshot() -> Dictionary:
	var active: Array[Dictionary] = []
	for slot in _slots:
		if bool(slot.get("active", false)):
			active.append(slot.duplicate(true))
	return {
		"active": active,
		"active_count": active.size(),
		"emitted": emitted_count,
		"dropped": dropped_count,
		"haptics": haptic_count,
		"last_haptic": _last_haptic.duplicate(true),
	}


static func destination_for(currency: StringName, viewport_size: Vector2,
		margins: Vector4) -> Vector2:
	var min_x := clampf(margins.x, 0.0, viewport_size.x)
	var max_x := clampf(viewport_size.x - margins.z, min_x, viewport_size.x)
	var min_y := clampf(margins.y, 0.0, viewport_size.y)
	var max_y := clampf(viewport_size.y - margins.w, min_y, viewport_size.y)
	var left := clampf(maxf(margins.x, 48.0) + 176.0, min_x, max_x)
	var y := maxf(margins.y, 48.0) + (106.0 if currency == &"clean" else 46.0)
	return Vector2(left, clampf(y, min_y, max_y))


static func destination_for_level(level: int, source: Vector2, viewport_size: Vector2,
		margins: Vector4) -> Vector2:
	return TABLE_VISUAL_STATE.feedback_destination(level, source, viewport_size, margins)


static func feedback_level_for(kind: StringName) -> StringName:
	return TABLE_VISUAL_STATE.feedback_level_name(TABLE_VISUAL_STATE.feedback_level(kind))


static func visual_state_for(kind: StringName, payload: Dictionary = {}) -> StringName:
	return TABLE_VISUAL_STATE.state_name(TABLE_VISUAL_STATE.feedback_state(kind, payload))


func _effect_text(kind: StringName, payload: Dictionary) -> String:
	match kind:
		&"currency": return "+$" + _money_text(payload.get("amount", null))
		&"launder": return "WASHED CLEAN  ·  $%s" % _money_text(payload.get("amount", null))
		&"combo": return "x%d CLEAN WORK" % int(payload.get("count", 0))
		&"drain": return "DRAIN"
		&"pinch":
			var name := String(payload.get("name", "A GUY"))
			return "%s GOT PINCHED" % (name.to_upper() if not name.is_empty() else "A GUY")
		&"bail":
			var name := String(payload.get("name", "GUY"))
			return "%s BAILED OUT" % (name.to_upper() if not name.is_empty() else "GUY")
		&"mode": return String(payload.get("title", String(payload.get("id", "MODE")))).to_upper()
		&"jackpot": return "JACKPOT  +$%s" % _money_text(payload.get("amount", null))
		&"rank": return "RANK UP  ·  %s" % String(payload.get("title", "MADE MAN")).to_upper()
		&"boss":
			if bool(payload.get("won", false)):
				return "BOSS DOWN"
			var boss := String(payload.get("name", "THE COMMISSION")).to_upper()
			var phase := int(payload.get("phase", 1))
			var phases := maxi(int(payload.get("phases", phase)), phase)
			return "%s  ·  PHASE %d/%d" % [boss, phase, phases]
		&"warning": return String(payload.get("title", "WARNING")).to_upper()
		_: return String(payload.get("title", ""))


func _money_text(value: Variant) -> String:
	if value is BigMoney:
		return (value as BigMoney).text().trim_prefix("$")
	return String(value) if value != null else "0"


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	for slot in _slots:
		if not bool(slot.get("active", false)):
			continue
		var duration := maxf(float(slot.get("duration", 0.8)), 0.001)
		var p := clampf(float(slot.get("elapsed", 0.0)) / duration, 0.0, 1.0)
		var alpha := _envelope(p) * float(slot.get("flash_scale", 1.0))
		match StringName(slot.get("kind", &"")):
			&"impact": _draw_impact(slot, p, alpha)
			&"currency": _draw_currency(slot, p, alpha)
			&"combo": _draw_combo(slot, p, alpha)
			&"drain": _draw_drain(slot, p, alpha)
			&"pinch", &"bail", &"mode", &"jackpot", &"rank", &"boss", &"launder", &"warning":
				_draw_banner(slot, p, alpha)


func _envelope(p: float) -> float:
	return clampf(minf(p / 0.12, (1.0 - p) / 0.28), 0.0, 1.0)


func _safe_rect() -> Rect2:
	if _safe != null and _safe.is_inside_tree():
		return _safe.content_rect()
	return Rect2(Vector2(48.0, 48.0), Vector2(maxf(size.x - 96.0, 0.0),
			maxf(size.y - 96.0, 0.0)))


func _position(payload: Dictionary) -> Vector2:
	var at: Variant = payload.get("screen_position", size * 0.5)
	var p := at as Vector2 if at is Vector2 else size * 0.5
	return Vector2(clampf(p.x, 12.0, size.x - 12.0), clampf(p.y, 12.0, size.y - 12.0))


func _draw_impact(slot: Dictionary, p: float, alpha: float) -> void:
	var payload: Dictionary = slot["payload"]
	var at := _position(payload)
	var strength := clampf(float(payload.get("strength", 900.0)) / 1500.0, 0.25, 1.0)
	var motion := float(slot.get("motion_scale", 1.0))
	var radius := 16.0 + 56.0 * p * strength * motion
	var col := Color(Presentation.theme.brass, alpha * 0.78)
	draw_arc(at, radius, 0.0, TAU, 28, col, 4.0)
	draw_circle(at, 8.0 + 8.0 * (1.0 - p) * motion,
			Color(Presentation.theme.newsprint, alpha * 0.62))
	if motion <= 0.0:
		return
	var spin := float(int(slot.get("serial", 0)) % 8) * 0.27
	for i in 6:
		var angle := spin + TAU * float(i) / 6.0
		var a := at + Vector2.from_angle(angle) * (radius + 6.0)
		var b := at + Vector2.from_angle(angle) * (radius + 22.0 + 18.0 * strength)
		draw_line(a, b, col, 3.0)


func _draw_currency(slot: Dictionary, p: float, alpha: float) -> void:
	var payload: Dictionary = slot["payload"]
	var currency := StringName(payload.get("currency", &"dirty"))
	var target := destination_for(currency, size, _safe.margins() if _safe != null else Vector4(48, 48, 48, 48))
	var source := _position(payload)
	var motion := float(slot.get("motion_scale", 1.0))
	var eased := 1.0 - pow(1.0 - p, 3.0)
	var at := target if motion <= 0.0 else source.lerp(target, eased)
	var col := Presentation.theme.clean if currency == &"clean" else Presentation.theme.dirty
	if motion > 0.0:
		var lane := 38.0 if currency == &"clean" else -38.0
		at += Vector2(lane * sin(eased * PI), -58.0 * sin(eased * PI))
		draw_line(source.lerp(target, maxf(eased - 0.12, 0.0)), at, Color(col, alpha * 0.44), 5.0)
		draw_circle(at, 10.0, Color(col, alpha * 0.9))
	var text := String(slot.get("text", ""))
	var font := Presentation.theme.font_for(&"ui")
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28).x
	# The decorative trail may begin at a switch under curved glass. Its readable number may
	# not: clamp the label independently while the dot and trail retain the real hit position.
	var safe := _safe_rect()
	var min_x := safe.position.x + tw * 0.5 + 10.0
	var max_x := safe.end.x - tw * 0.5 - 10.0
	var text_at := Vector2(safe.get_center().x if min_x > max_x else clampf(at.x, min_x, max_x),
			clampf(at.y, safe.position.y + 34.0, safe.end.y - 8.0))
	draw_rect(Rect2(text_at + Vector2(-tw * 0.5 - 10.0, -34.0), Vector2(tw + 20.0, 42.0)),
			Color(Presentation.theme.ink, alpha * 0.72), true)
	draw_string(font, text_at + Vector2(-tw * 0.5, -2.0), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 28, Color(col, alpha))


func _draw_combo(slot: Dictionary, p: float, alpha: float) -> void:
	var safe := _safe_rect()
	var at := Vector2(safe.get_center().x, safe.position.y + safe.size.y * 0.22)
	var pulse := 1.0 + sin(p * PI) * 0.08 * float(slot.get("motion_scale", 1.0))
	var text := String(slot.get("text", ""))
	var font := Presentation.theme.font_for(&"headline")
	var px := int(46.0 * pulse)
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	draw_line(Vector2(maxf(safe.position.x, at.x - tw * 0.7), at.y + 13.0),
			Vector2(minf(safe.end.x, at.x + tw * 0.7), at.y + 13.0),
			Color(Presentation.theme.brass, alpha * 0.42), 4.0)
	draw_string(font, at + Vector2(-tw * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, px, Color(Presentation.theme.newsprint, alpha))


func _draw_drain(slot: Dictionary, p: float, alpha: float) -> void:
	var payload: Dictionary = slot["payload"]
	var at := _position(payload)
	var motion := float(slot.get("motion_scale", 1.0))
	var fall := 130.0 * p * motion
	var radius := 32.0 + 20.0 * p * motion
	draw_circle(at + Vector2(0.0, fall), radius,
			Color(Presentation.theme.dirty, alpha * 0.16))
	draw_arc(at + Vector2(0.0, fall), radius, 0.0, TAU, 28,
			Color(Presentation.theme.dirty, alpha * 0.82), 5.0)
	var safe := _safe_rect()
	var font := Presentation.theme.font_for(&"headline")
	var text := String(slot.get("text", "DRAIN"))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 40).x
	draw_string(font, Vector2(safe.get_center().x - tw * 0.5, safe.end.y - 84.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 40, Color(Presentation.theme.dirty, alpha))


func _draw_banner(slot: Dictionary, p: float, alpha: float) -> void:
	var kind := StringName(slot.get("kind", &"mode"))
	var safe := _safe_rect()
	var level := int(slot.get("feedback_level", TABLE_VISUAL_STATE.feedback_level(kind)))
	var source: Variant = slot.get("source", safe.get_center())
	var source_at := source as Vector2 if source is Vector2 else safe.get_center()
	var margins := _safe.margins() if _safe != null else Vector4(48.0, 48.0, 48.0, 48.0)
	# Laundering keeps its existing named ceremony while the clean flight remains a reward.
	var destination_class := StringName(slot.get("destination_class", &""))
	var destination_level := level
	if destination_class == &"ceremony" or destination_class == &"safe_center":
		destination_level = TABLE_VISUAL_STATE.FeedbackLevel.CEREMONY
	elif destination_class == &"consequence" or destination_class == &"safe_bottom_right":
		destination_level = TABLE_VISUAL_STATE.FeedbackLevel.CONSEQUENCE
	elif destination_class == &"reward":
		destination_level = TABLE_VISUAL_STATE.FeedbackLevel.REWARD
	# Laundering keeps its existing named ceremony while the clean flight remains a reward.
	if kind == &"launder":
		destination_level = TABLE_VISUAL_STATE.FeedbackLevel.CEREMONY
	var center := destination_for_level(destination_level, source_at, size, margins)
	var col := _banner_color(kind, slot["payload"])
	var major := destination_level == TABLE_VISUAL_STATE.FeedbackLevel.CEREMONY
	# Full-bleed atmosphere can enter rounded corners; the readable banner cannot.
	if major:
		draw_rect(Rect2(0.0, center.y - 124.0, size.x, 248.0), Color(col, alpha * 0.10), true)
	var width := minf(safe.size.x, 900.0)
	var lift := (1.0 - p) * 24.0 * float(slot.get("motion_scale", 1.0))
	var panel := Rect2(Vector2(center.x - width * 0.5, center.y - 74.0 - lift), Vector2(width, 148.0))
	draw_rect(panel, Color(Presentation.theme.ink, alpha * 0.86), true)
	draw_line(panel.position, Vector2(panel.end.x, panel.position.y), Color(col, alpha), 5.0)
	draw_line(Vector2(panel.position.x, panel.end.y), panel.end, Color(col, alpha), 5.0)
	var text := String(slot.get("text", ""))
	var font := Presentation.theme.font_for(&"headline")
	var px := 46 if text.length() <= 28 else 34
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	if tw > panel.size.x - 40.0:
		px = maxi(24, int(float(px) * (panel.size.x - 40.0) / maxf(tw, 1.0)))
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, px).x
	draw_string(font, Vector2(center.x - tw * 0.5, center.y + float(px) * 0.34 - lift), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, px, Color(Presentation.theme.newsprint, alpha))


func _feedback_modifiers(kind: StringName, payload: Dictionary) -> Dictionary:
	var raw: Variant = payload.get("local_modifiers", {})
	var modifiers: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	if modifiers.is_empty():
		if kind == &"drain" or kind == &"warning":
			modifiers[&"telegraph"] = true
		if kind == &"boss":
			modifiers[&"boss_phase"] = int(payload.get("phase", 0)) > 0
	return modifiers


func _banner_color(kind: StringName, payload: Dictionary) -> Color:
	match kind:
		&"pinch": return Presentation.theme.police
		&"bail": return Presentation.theme.clean
		&"launder": return Presentation.theme.clean
		&"jackpot", &"rank": return Presentation.theme.brass
		&"boss": return Presentation.theme.neon_rose
		&"mode":
			return Presentation.theme.police if StringName(payload.get("id", &"")) == &"raid" \
					else Presentation.theme.brass
		_: return Presentation.theme.dirty
