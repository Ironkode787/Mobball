class_name SaveGame
extends RefCounted
## The save file (specs/m1-hook.md Lane 1). JSON at `user://save1.json`, written atomically
## (temp file + rename) with two rolling backups, so a kill -9 mid-write costs at most the
## last Night and never the career.
##
## Load salvages: the newest file that parses wins, so a truncated `save1.json` falls back
## to `bak1` rather than to a new game. `version` + `migrate()` carry old saves forward.

## v2 (M3): the endgame's sections were added — `smuggling` `sitdown` `chairs` `elections`
## `heists` `federal` `empire` `briefcases` `phone` `rat` `career`, and `prestige` (the meta
## lane's Black Book, which outlives a career). Every one of them defaults to empty, so a v1
## file loads as a career that simply has not reached the endgame yet — which is exactly what
## it is. Nothing had to move, so `migrate` only stamps the version forward.
## v3 (M5): new writes carry a SHA-256 integrity field. Older saves remain readable and are
## upgraded on their next ordinary save; a damaged/tampered v3 candidate falls through to
## the rolling backups exactly like malformed JSON.
const VERSION := 3
const FORMAT := "kingpin.save.envelope"
const DEFAULT_PATH := "user://save1.json"

var path: String = DEFAULT_PATH
## Set when the last read() had to fall back to a backup — the boot code logs it.
var salvaged_from: String = ""
var last_error: String = ""


func _init(p_path: String = DEFAULT_PATH) -> void:
	path = p_path


func backup1() -> String:
	return path.get_basename() + ".bak1.json"


func backup2() -> String:
	return path.get_basename() + ".bak2.json"


func temp_path() -> String:
	return path.get_basename() + ".tmp.json"


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(backup1()) \
			or FileAccess.file_exists(backup2())


## Atomic write: temp file first, verified by reading it back, then the rotation. If any
## step fails the previous save is still whole.
func write(payload: Dictionary) -> bool:
	last_error = ""
	var d := payload.duplicate(true)
	d["version"] = VERSION
	d["saved_at"] = Time.get_unix_time_from_system()
	# Keep the historical JSON precision so a v1/v2 career round-trips identically. Integrity
	# hashes the exact serialized payload string, so it does not require numeric re-canonicalizing.
	var payload_json := JSON.stringify(d, "\t")
	var envelope := {
		"format": FORMAT,
		"version": VERSION,
		"checksum": payload_json.sha256_text(),
		"payload_json": payload_json,
	}

	var tmp := temp_path()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "cannot open %s (%d)" % [tmp, FileAccess.get_open_error()]
		return false
	f.store_string(JSON.stringify(envelope, "\t", true, true))
	f.close()

	var verify: Variant = _parse(_read_text(tmp))
	if not (verify is Dictionary) or _decode_candidate(verify as Dictionary).is_empty():
		last_error = "temp file did not read back as JSON"
		return false

	if FileAccess.file_exists(backup1()):
		_replace(backup1(), backup2())
	if FileAccess.file_exists(path):
		_replace(path, backup1())
	if not _replace(tmp, path):
		last_error = "could not move %s onto %s" % [tmp, path]
		return false
	return true


## Newest valid save, or an empty dict for a fresh career.
func read() -> Dictionary:
	salvaged_from = ""
	last_error = ""
	var tried := 0
	for candidate: String in [path, backup1(), backup2()]:
		if not FileAccess.file_exists(candidate):
			continue
		tried += 1
		var parsed: Variant = _parse(_read_text(candidate))
		if not (parsed is Dictionary):
			continue
		var d := _decode_candidate(parsed as Dictionary)
		if d.is_empty():
			continue
		if candidate != path:
			salvaged_from = candidate
		return migrate(d)
	if tried > 0:
		last_error = "no readable save among %d file(s)" % tried
	return {}


## Version hook. v1 → v2 added sections and moved nothing (see VERSION), so the migration is
## the version stamp itself: every M3 reader defaults its own section to empty. The branch
## stays here so the next format change that DOES move a field is a data edit, not a redesign.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v == VERSION:
		return d
	if v > VERSION:
		# A save from a newer build (a downgrade): load what we understand rather than
		# wiping it. A log line, not a warning — it is a supported situation, not a fault.
		print("[save] file version %d is newer than %d; loading what this build knows"
				% [v, VERSION])
		return d
	d["version"] = VERSION
	return d


## Wipe the save and its backups (new game / tests).
func erase() -> void:
	for p: String in [path, backup1(), backup2(), temp_path()]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p) if p.begins_with("res://") else p)


func _replace(from: String, to: String) -> bool:
	if FileAccess.file_exists(to):
		DirAccess.remove_absolute(to)
	return DirAccess.rename_absolute(from, to) == OK


## uint64 save fields (RNG seeds and states) travel as text: JSON would round-trip them
## through a double and lose the bottom bits. Older/hand-edited files may carry a number.
static func to_i64(raw: Variant, fallback: int) -> int:
	if raw is String:
		return (raw as String).to_int()
	if raw is int or raw is float:
		return int(raw)
	return fallback


## A damaged save is an expected event here, not a bug: the instance API reports the parse
## failure as a return value instead of pushing an engine error into the log.
static func _parse(text: String) -> Variant:
	if text.is_empty():
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data


static func _decode_candidate(raw: Dictionary) -> Dictionary:
	if String(raw.get("format", "")) == FORMAT:
		var payload_json := String(raw.get("payload_json", ""))
		var expected := String(raw.get("checksum", ""))
		if payload_json.is_empty() or expected.is_empty() or payload_json.sha256_text() != expected:
			return {}
		var decoded: Variant = _parse(payload_json)
		if not (decoded is Dictionary) or not (decoded as Dictionary).has("version"):
			return {}
		return decoded as Dictionary
	# v1/v2 were plain dictionaries without integrity metadata. They remain readable and are
	# wrapped the next time the game saves. A plain v3 must never bypass the checksum envelope.
	if not raw.has("version") or int(raw.get("version", 0)) >= 3:
		return {}
	return raw


static func _read_text(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s
