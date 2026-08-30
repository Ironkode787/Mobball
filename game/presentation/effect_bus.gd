class_name EffectBus
extends Node
## Semantic effect traffic. Gameplay asks for meaning; renderers decide how to show it.

signal effect_requested(kind: StringName, payload: Dictionary)
signal subtitle_requested(text: String, speaker: StringName)
signal haptic_requested(pattern: StringName, strength: float)

var reduced_motion := false
var reduced_flash := false
var haptics_enabled := true
var subtitles_enabled := true


func motion_scale() -> float:
	return 0.0 if reduced_motion else 1.0


func flash_scale() -> float:
	return 0.25 if reduced_flash else 1.0


func request(kind: StringName, payload: Dictionary = {}) -> bool:
	if kind == &"":
		return false
	var p := payload.duplicate(true)
	if reduced_motion:
		p["motion_scale"] = 0.0
	if reduced_flash:
		p["flash_scale"] = minf(float(p.get("flash_scale", 1.0)), 0.25)
	p["kind"] = kind
	effect_requested.emit(kind, p)
	return true


func subtitle(text: String, speaker: StringName = &"") -> bool:
	if not subtitles_enabled or text.is_empty():
		return false
	subtitle_requested.emit(text, speaker)
	return true


func haptic(pattern: StringName, strength: float = 1.0) -> bool:
	if not haptics_enabled or pattern == &"":
		return false
	haptic_requested.emit(pattern, clampf(strength, 0.0, 1.0))
	return true
