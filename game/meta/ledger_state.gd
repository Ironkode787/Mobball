class_name LedgerState
extends RefCounted
## The authoritative owned-upgrades map: node id (String) -> level (int, >= 1).
##
## It lives here, in the meta layer, rather than on the Ledger UI node, because the Ledger
## is instantiated lazily and freed again while the levels have to survive both — the save
## system reads them at boot (before any UI exists) and `Stats.recompute` wants them on the
## first frame. The Ledger scene proxies `get_owned()` / `set_owned()` to these statics, so
## the flow lane can call either surface.
##
## Static storage is deliberate: there is exactly one career at a time, and making it an
## instance would just mean inventing a place to hang the instance.

static var _levels: Dictionary = {}


## A copy — callers may keep it, sort it, hand it to the save file.
static func get_owned() -> Dictionary:
	return _levels.duplicate()


## Replaces the whole map (save load / respec). Non-positive levels and non-string ids are
## dropped, so a corrupt save cannot poison Stats.
static func set_owned(owned: Dictionary) -> void:
	_levels.clear()
	if owned == null:
		return
	for id: Variant in owned:
		if not (id is String):
			continue
		var level := int(owned[id])
		if level >= 1:
			_levels[String(id)] = level


static func level_of(id: String) -> int:
	return int(_levels.get(id, 0))


static func set_level(id: String, level: int) -> void:
	if level >= 1:
		_levels[id] = level
	else:
		_levels.erase(id)


## Buys one level and returns the new level.
static func add_level(id: String) -> int:
	var next := level_of(id) + 1
	_levels[id] = next
	return next


static func clear() -> void:
	_levels.clear()
