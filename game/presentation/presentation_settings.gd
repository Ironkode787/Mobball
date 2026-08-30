class_name PresentationSettings
extends RefCounted
## Player-owned presentation preferences. These live outside the career save so a damaged
## or restarted run can never silently turn accessibility choices back on.

const DEFAULT_PATH := "user://presentation.cfg"
const SECTION := "accessibility"
const AUDIO_SECTION := "audio"
const AUDIO_BUSES: PackedStringArray = ["Music", "Mechanics", "Fiction", "UI"]

var path := DEFAULT_PATH
var reduced_motion := false
var reduced_flash := false
var haptics_enabled := true
var subtitles_enabled := true
var bus_levels := {
	"Music": 1.0,
	"Mechanics": 1.0,
	"Fiction": 1.0,
	"UI": 1.0,
}


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


func load_into(bus: EffectBus) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		reduced_motion = bool(cfg.get_value(SECTION, "reduced_motion", false))
		reduced_flash = bool(cfg.get_value(SECTION, "reduced_flash", false))
		haptics_enabled = bool(cfg.get_value(SECTION, "haptics_enabled", true))
		subtitles_enabled = bool(cfg.get_value(SECTION, "subtitles_enabled", true))
		for bus_name: String in AUDIO_BUSES:
			bus_levels[bus_name] = clampf(float(cfg.get_value(
					AUDIO_SECTION, bus_name.to_lower(), 1.0)), 0.0, 1.0)
	apply(bus)


func save() -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "reduced_motion", reduced_motion)
	cfg.set_value(SECTION, "reduced_flash", reduced_flash)
	cfg.set_value(SECTION, "haptics_enabled", haptics_enabled)
	cfg.set_value(SECTION, "subtitles_enabled", subtitles_enabled)
	for bus_name: String in AUDIO_BUSES:
		cfg.set_value(AUDIO_SECTION, bus_name.to_lower(), bus_level(bus_name))
	return cfg.save(path) == OK


func apply(bus: EffectBus) -> void:
	if bus != null:
		bus.reduced_motion = reduced_motion
		bus.reduced_flash = reduced_flash
		bus.haptics_enabled = haptics_enabled
		bus.subtitles_enabled = subtitles_enabled
	for bus_name: String in AUDIO_BUSES:
		_apply_bus_level(bus_name, bus_level(bus_name))


func set_toggle(id: StringName, enabled: bool, bus: EffectBus) -> bool:
	match id:
		&"reduced_motion": reduced_motion = enabled
		&"reduced_flash": reduced_flash = enabled
		&"haptics_enabled": haptics_enabled = enabled
		&"subtitles_enabled": subtitles_enabled = enabled
		_: return false
	apply(bus)
	return save()


func toggle_value(id: StringName) -> bool:
	match id:
		&"reduced_motion": return reduced_motion
		&"reduced_flash": return reduced_flash
		&"haptics_enabled": return haptics_enabled
		&"subtitles_enabled": return subtitles_enabled
		_: return false


func set_bus_level(bus_name: String, level: float) -> bool:
	if not AUDIO_BUSES.has(bus_name):
		return false
	bus_levels[bus_name] = clampf(level, 0.0, 1.0)
	_apply_bus_level(bus_name, bus_level(bus_name))
	return save()


func bus_level(bus_name: String) -> float:
	return clampf(float(bus_levels.get(bus_name, 1.0)), 0.0, 1.0)


func snapshot() -> Dictionary:
	return {
		"reduced_motion": reduced_motion,
		"reduced_flash": reduced_flash,
		"haptics_enabled": haptics_enabled,
		"subtitles_enabled": subtitles_enabled,
		"bus_levels": bus_levels.duplicate(true),
	}


func _apply_bus_level(bus_name: String, level: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, -80.0 if level <= 0.001 else linear_to_db(level))
