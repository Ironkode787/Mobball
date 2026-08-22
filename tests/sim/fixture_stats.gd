class_name FixtureStats
extends Stats
## A staged owned-set for tests/sim/table_growth_sim: a list of Ledger node ids in, the
## Stats answers the table asks for out. It resolves the ids against the shipped
## `game/content/upgrades.json` (including their `requires` closure), so the fixtures are
## real career states rather than hand-written unlock lists — if a node's effects change,
## this sim notices.
##
## It is deliberately its own small resolver rather than the meta lane's engine: the growth
## sim is about what the *table* does with an owned set, and it should not go red because
## the Ledger's arithmetic is mid-rewrite next door. Everything here is `_fx_`-prefixed so
## nothing shadows the real Stats it stands in for.

const FIXTURE_UPGRADES_PATH := "res://game/content/upgrades.json"

var owned_ids: Dictionary = {}          ## node id -> level
var missing_ids: PackedStringArray = [] ## ids the content file does not have

var _fx_hardware: Dictionary = {}
var _fx_flags: Dictionary = {}
var _fx_mult: Dictionary = {}
var _fx_add: Dictionary = {}
var _fx_flipper: float = 1.0
var _fx_collect: float = 5.0
var _fx_bribe: bool = false

static var _fx_catalog: Dictionary = {}


## `ids` is either an Array of node ids (level 1 each) or a Dictionary id -> level.
func _init(ids: Variant = []) -> void:
	_fx_load_catalog()
	if ids is Array:
		for id: Variant in ids as Array:
			owned_ids[String(id)] = 1
	elif ids is Dictionary:
		for id: Variant in ids as Dictionary:
			owned_ids[String(id)] = int((ids as Dictionary)[id])
	_fx_close_requires()
	_fx_apply_all()


## The fixture is the truth here; the session's own recompute must not wash it away.
func recompute(_owned: Dictionary) -> void:
	pass


func owned_level(id: String) -> int:
	return int(owned_ids.get(id, 0))


func hardware_unlocked(id: StringName) -> bool:
	return _fx_hardware.has(id)


func flag(id: StringName) -> bool:
	return _fx_flags.has(id)


func value_mult(group: StringName) -> float:
	return float(_fx_mult.get(group, 1.0))


func value_add(group: StringName) -> BigMoney:
	var v: Variant = _fx_add.get(group)
	return (v as BigMoney).copy() if v is BigMoney else BigMoney.zero()


func flipper_power() -> float:
	return _fx_flipper


func collect_minutes() -> float:
	return _fx_collect


func bribe_unlocked() -> bool:
	return _fx_bribe


# ------------------------------------------------------------------ resolver

static func _fx_load_catalog() -> void:
	if not _fx_catalog.is_empty():
		return
	var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(FIXTURE_UPGRADES_PATH))
	if not (parsed is Dictionary):
		return
	for entry: Variant in (parsed as Dictionary).get("nodes", []):
		if entry is Dictionary:
			_fx_catalog[String((entry as Dictionary).get("id", ""))] = entry


func _fx_close_requires() -> void:
	var queue: Array = owned_ids.keys()
	while not queue.is_empty():
		var id: String = String(queue.pop_back())
		var node: Dictionary = _fx_catalog.get(id, {})
		if node.is_empty():
			missing_ids.append(id)
			continue
		for req: Variant in node.get("requires", []):
			var r := String(req)
			if not owned_ids.has(r):
				owned_ids[r] = 1
				queue.append(r)


func _fx_apply_all() -> void:
	for id: Variant in owned_ids:
		var node: Dictionary = _fx_catalog.get(String(id), {})
		if node.is_empty():
			continue
		var level := int(owned_ids[id])
		for effect: Variant in node.get("effects", []):
			if effect is Dictionary:
				_fx_apply(effect as Dictionary, level)


func _fx_apply(e: Dictionary, level: int) -> void:
	var target := StringName(String(e.get("target", "")))
	var reps := level if bool(e.get("per_level", false)) else 1
	match String(e.get("kind", "")):
		"unlock_hardware":
			_fx_hardware[target] = true
		"feature_flag":
			_fx_flags[target] = true
		"kickback_unlock":
			_fx_hardware[StringName("kickback_" + String(target))] = true
		"bribe_unlock":
			_fx_bribe = true
			_fx_hardware[&"bribe_target"] = true
		"value_mult":
			_fx_mult[target] = float(_fx_mult.get(target, 1.0)) \
					* pow(float(e.get("value", 1.0)), float(reps))
		"value_add":
			var add := BigMoney.parse(str(e.get("value", "0"))).mul(float(reps))
			var have: Variant = _fx_add.get(target)
			_fx_add[target] = (have as BigMoney).add(add) if have is BigMoney else add
		"flipper_power_mult":
			_fx_flipper *= pow(float(e.get("value", 1.0)), float(reps))
		"collect_minutes_mult":
			_fx_collect *= pow(float(e.get("value", 1.0)), float(reps))
