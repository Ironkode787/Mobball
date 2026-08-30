class_name TelemetryStore
extends RefCounted
## Privacy-light beta funnel queue. It never owns networking and never touches the career save.

const FORMAT := "kingpin.telemetry.queue"
const SCHEMA_VERSION := 1
const MAX_EVENTS := 512
const CONSENT_UNKNOWN := &"unknown"
const CONSENT_GRANTED := &"granted"
const CONSENT_DENIED := &"denied"

const EVENT_PROPS := {
	"app_session_started": ["build"],
	"front_door_start": [],
	"roll_call_viewed": [],
	"night_started": ["night_bucket"],
	"night_first_ball_launched": [],
	"night_first_active_earn": [],
	"night_completed": ["night_bucket", "guys_lost", "tilts", "jobs_done",
			"best_combo", "rank_bucket", "raid", "rank_up"],
	"ledger_viewed": [],
	"upgrade_purchased": ["level_bucket"],
	"raid_started": [],
	"raid_completed": ["survived"],
}

var consent_path := "user://telemetry.cfg"
var queue_path := "user://telemetry_queue.json"
var export_path := "user://telemetry_export.json"
var consent: StringName = CONSENT_UNKNOWN
var build := "0.5.0-beta.1"
var _events: Array = []
var _next_order := 1
var _session_started_msec := 0
var _clock: Callable
var _read_only := false


func _init(p_queue_path: String = "user://telemetry_queue.json",
		p_consent_path: String = "user://telemetry.cfg",
		p_export_path: String = "user://telemetry_export.json",
		p_clock: Callable = Callable()) -> void:
	queue_path = p_queue_path
	consent_path = p_consent_path
	export_path = p_export_path
	_clock = p_clock


func load() -> void:
	_load_consent()
	if consent == CONSENT_GRANTED:
		_load_queue()
	else:
		_events.clear()
		_next_order = 1
		clear_data()


func set_consent(next: StringName) -> bool:
	if next not in [CONSENT_UNKNOWN, CONSENT_GRANTED, CONSENT_DENIED]:
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("beta", "telemetry", String(next))
	if next == CONSENT_GRANTED:
		# Keep the fail-closed marker until the granted choice itself is durable. If either
		# operation fails, this process and the next restart remain opted out.
		if cfg.save(consent_path) != OK:
			_write_denial_marker()
			consent = CONSENT_DENIED
			clear_data()
			return false
		if FileAccess.file_exists(denial_marker_path()) \
				and DirAccess.remove_absolute(denial_marker_path()) != OK:
			consent = CONSENT_DENIED
			clear_data()
			return false
		consent = CONSENT_GRANTED
		return true

	# Marker first, config second: either successful write is enough to make an opt-out
	# survive restart. A failed config write deliberately leaves the marker in place.
	_write_denial_marker()
	var saved := cfg.save(consent_path) == OK
	consent = next if saved else CONSENT_DENIED
	var cleared := clear_data()
	if not saved:
		return false
	if cleared and FileAccess.file_exists(denial_marker_path()):
		DirAccess.remove_absolute(denial_marker_path())
	return cleared


func begin_session() -> bool:
	_session_started_msec = _now_msec()
	return record("app_session_started", {"build": build})


func record(event_name: String, props: Dictionary = {}) -> bool:
	if consent != CONSENT_GRANTED or _read_only or not EVENT_PROPS.has(event_name):
		return false
	var clean := {}
	for key: String in EVENT_PROPS[event_name]:
		if props.has(key) and _valid_prop(event_name, key, props[key]):
			clean[key] = props[key]
	var elapsed := maxi(_now_msec() - _session_started_msec, 0)
	_events.append({
		"schema_version": SCHEMA_VERSION,
		"event": event_name,
		"order": _next_order,
		"elapsed_bucket_s": mini(int(elapsed / 30000) * 30, 3600),
		"props": clean,
	})
	_next_order += 1
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
	return _write_queue()


func report() -> Dictionary:
	return {
		"format": FORMAT,
		"schema_version": SCHEMA_VERSION,
		"build": build,
		"events": _events.duplicate(true),
	}


func report_json() -> String:
	return JSON.stringify(report(), "\t", false)


func export_report() -> bool:
	if consent != CONSENT_GRANTED or _read_only:
		return false
	return _atomic_write(export_path, report_json())


func clear_data() -> bool:
	_events.clear()
	_next_order = 1
	_read_only = false
	var ok := true
	for path: String in [queue_path, export_path, queue_path + ".tmp", export_path + ".tmp",
			queue_path + ".previous", export_path + ".previous"]:
		if FileAccess.file_exists(path):
			ok = DirAccess.remove_absolute(path) == OK and ok
		ok = not FileAccess.file_exists(path) and ok
	return ok


func event_count() -> int:
	return _events.size()


func is_read_only() -> bool:
	return _read_only


func denial_marker_path() -> String:
	return queue_path + ".denied"


func _load_consent() -> void:
	if FileAccess.file_exists(denial_marker_path()):
		consent = CONSENT_DENIED
		return
	var cfg := ConfigFile.new()
	if cfg.load(consent_path) != OK:
		consent = CONSENT_UNKNOWN
		return
	var raw := StringName(String(cfg.get_value("beta", "telemetry", "unknown")))
	consent = raw if raw in [CONSENT_UNKNOWN, CONSENT_GRANTED, CONSENT_DENIED] \
			else CONSENT_UNKNOWN


func _load_queue() -> void:
	_events.clear()
	_next_order = 1
	_read_only = false
	_recover_previous(queue_path)
	if not FileAccess.file_exists(queue_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(queue_path))
	if not (parsed is Dictionary) or String(parsed.get("format", "")) != FORMAT:
		return
	var version := int(parsed.get("schema_version", 0))
	if version > SCHEMA_VERSION:
		_read_only = true
		return
	var raw_events: Variant = parsed.get("events", [])
	if not (raw_events is Array):
		return
	for raw: Variant in raw_events:
		var clean := _sanitize_event(raw)
		if not clean.is_empty():
			_events.append(clean)
	while _events.size() > MAX_EVENTS:
		_events.pop_front()
	for event: Variant in _events:
		_next_order = maxi(_next_order, int((event as Dictionary).get("order", 0)) + 1)


func _write_queue() -> bool:
	return _atomic_write(queue_path, report_json())


func _atomic_write(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	if JSON.parse_string(FileAccess.get_file_as_string(tmp)) == null:
		return false
	var previous := path + ".previous"
	if FileAccess.file_exists(previous):
		DirAccess.remove_absolute(previous)
	if FileAccess.file_exists(path) and DirAccess.rename_absolute(path, previous) != OK:
		return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		if FileAccess.file_exists(previous) and not FileAccess.file_exists(path):
			DirAccess.rename_absolute(previous, path)
		return false
	if FileAccess.file_exists(previous):
		DirAccess.remove_absolute(previous)
	return true


func _now_msec() -> int:
	return int(_clock.call()) if _clock.is_valid() else Time.get_ticks_msec()


func _sanitize_event(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var source := raw as Dictionary
	var event_name := String(source.get("event", ""))
	if not EVENT_PROPS.has(event_name) or int(source.get("schema_version", 0)) != SCHEMA_VERSION:
		return {}
	var order := int(source.get("order", 0))
	var elapsed := int(source.get("elapsed_bucket_s", -1))
	if order < 1 or elapsed < 0 or elapsed > 3600 or elapsed % 30 != 0:
		return {}
	var clean_props := {}
	var raw_props: Variant = source.get("props", {})
	if raw_props is Dictionary:
		for key: String in EVENT_PROPS[event_name]:
			if (raw_props as Dictionary).has(key):
				var value: Variant = (raw_props as Dictionary)[key]
				if _valid_prop(event_name, key, value):
					clean_props[key] = value
	return {"schema_version": SCHEMA_VERSION, "event": event_name, "order": order,
			"elapsed_bucket_s": elapsed, "props": clean_props}


func _valid_prop(_event_name: String, key: String, value: Variant) -> bool:
	match key:
		"build": return value is String and value == build
		"night_bucket": return value is String and value in ["1", "2_3", "4_10", "11_plus"]
		"guys_lost", "tilts", "jobs_done":
			return value is String and value in ["0", "1", "2", "3", "4_plus"]
		"best_combo": return value is String and value in ["0_1", "2_4", "5_plus"]
		"rank_bucket":
			return value is String and value in ["r0", "r1", "r2", "r3", "r4", "r5", "r6", "r7"]
		"raid": return value is String and value in ["none", "survived", "lost"]
		"level_bucket": return value is String and value in ["1", "2_plus"]
		"rank_up", "survived": return value is bool
		_: return false


func _recover_previous(path: String) -> void:
	var previous := path + ".previous"
	if not FileAccess.file_exists(path) and FileAccess.file_exists(previous):
		DirAccess.rename_absolute(previous, path)
	elif FileAccess.file_exists(path) and FileAccess.file_exists(previous):
		DirAccess.remove_absolute(previous)


func _write_denial_marker() -> bool:
	var file := FileAccess.open(denial_marker_path(), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("denied")
	file.close()
	return FileAccess.file_exists(denial_marker_path())
