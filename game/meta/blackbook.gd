class_name BlackBook
extends RefCounted
## The Black Book catalog: loads and validates `game/content/blackbook.json` (docs/06 §3).
##
## Same job as `Upgrades`, one shelf up. A Ledger node is bought with clean cash inside a
## career; a Black Book perk is bought with **Juice** and survives Skip Town, so its data
## file is separate, its currency is a plain int, and its effects speak a vocabulary the
## flow lane reads at the START of a city rather than one `Stats` folds during one.
##
## The loader is deliberately as strict as the Ledger's: unknown key, unknown kind, a value
## outside its band or a cost that is not a whole positive number is an error, and a perk
## that fails validation is SKIPPED rather than half-loaded. Perks marked `deferred` (the ★
## rows of docs/06 §3, which need systems M4+ has not built) load like any other perk but can
## never be bought — the board shows them face-down, which is the honest thing to sell.
##
## An effect may also name a kind from the LEDGER's vocabulary (`Upgrades.EFFECT_SPECS`); it
## is validated against the same bands, and `Prestige.stats_effects()` hands the owned ones
## out for the flow lane to fold. Nothing in the shipped file needs one yet — the door is
## open so a future "all idle rates +25%, forever" perk is data, not a new kind.
##
## Pure RefCounted, no autoloads, no Node — it loads under the bare test runner.

const DEFAULT_PATH := "res://game/content/blackbook.json"
const SCHEMA_VERSION := 1
## Every perk id reads `blackbook.<slug>`, so a Black Book id can never collide with a Ledger
## node id or a `spoil.` pseudo-id inside one owned map.
const ID_PREFIX := "blackbook."
## docs/06 §3 tops out at 25 Juice and a first Skip Town pays 8–15. A three-digit price would
## be a perk nobody reaches this side of five cities — almost certainly a typo.
const MAX_COST := 100

## Why a perk cannot be bought right now. NONE means "take the Juice".
enum Block { NONE, UNKNOWN, DEFERRED, REQUIRES, MAXED, JUICE }

const PERK_KEYS: PackedStringArray = [
	"id", "name", "flavor", "note", "cost", "repeat", "requires", "deferred", "effects",
]
const PERK_REQUIRED_KEYS: PackedStringArray = ["id", "name", "flavor", "note", "cost", "effects"]
## Juice is small and countable, so a repeat ladder is `cost + step × level` — integer exact,
## legible on a card ("1 · 2 · 3"), and nothing like the `1.15^level` curve clean cash needs.
const REPEAT_KEYS: PackedStringArray = ["max", "step"]

## The prestige-perk vocabulary: what a perk may promise, and the band it may promise it in.
##
## These are NOT Stats kinds. Every one of them is read once, by the lane named in the
## comment, at the moment a city begins (or when the system it belongs to opens) — which is
## exactly why they cannot be `Stats` effects: `Stats` is the fold of what THIS career bought.
##
## value forms mirror the Ledger's: `num` (float), `int` (whole float), absent (a flag).
const PERK_SPECS := {
	# --- live: the systems behind these exist in M3 -------------------------------
	## Old Contacts — flow reads it when a new city starts and seats the career at R`n`.
	&"start_rank": {"value": &"int", "min": 1.0, "max": 3.0},
	## Kept Man — how many specialists may be carried through Skip Town.
	&"kept_specialist": {"value": &"int", "min": 1.0, "max": 3.0},
	## Traveling Light — Pocket Money multiplies by the city number.
	&"pocket_city_scale": {},
	## Reputation Precedes You — the city's first Commission fight opens at this phase.
	&"boss_start_phase": {"value": &"int", "min": 2.0, "max": 3.0},
	## The Stash — this fraction of the last city's CLEAN arrives as dirty in the new one.
	&"stash_fraction": {"value": &"num", "min": 0.000001, "max": 0.25},
	## Everybody Knows Somebody — guys already on the Bench when the city opens.
	&"bench_starters": {"value": &"int", "min": 1.0, "max": 4.0},
	## Fast Learner — ☆ thresholds multiply by this in a city you have already beaten.
	&"star_requirement_mult": {"value": &"num", "min": 0.5, "max": 1.0},
	# --- deferred: the ★ rows, whose systems land in M4+ --------------------------
	## Double Life — the previous city's idle rate keeps paying at this fraction.
	&"idle_carryover": {"value": &"num", "min": 0.000001, "max": 0.25},
	## The Big Sleep — retired specialists standing as aura statues on every future table.
	&"saint_statue": {"value": &"int", "min": 1.0, "max": 3.0},
	## Museum of Crime — the relic gallery and its set bonuses.
	&"museum": {},
	## The Golden Era — the tier the Golden Ball unlocks at, instead of T7.
	&"golden_ball_tier": {"value": &"int", "min": 4.0, "max": 7.0},
	## Silent Empire — the offline Safe cap multiplies by this…
	&"safe_cap_mult": {"value": &"num", "min": 1.0, "max": 4.0},
	## …and this fraction of what it holds arrives already clean.
	&"safe_clean_share": {"value": &"num", "min": 0.000001, "max": 0.25},
	## The Sixth Family — the five-Commission gauntlet table.
	&"gauntlet": {},
}

## Which bucket each perk kind folds into when several perks (or several levels) promise the
## same thing. The buckets are `Stats.Fold` — one fold vocabulary in the codebase, so a reader
## who knows how the Ledger stacks knows how the Black Book stacks.
const FOLD := {
	&"start_rank": Stats.Fold.SUM,
	&"kept_specialist": Stats.Fold.SUM,
	&"pocket_city_scale": Stats.Fold.UNION,
	&"boss_start_phase": Stats.Fold.MAX,
	&"stash_fraction": Stats.Fold.SUM,
	&"bench_starters": Stats.Fold.SUM,
	&"star_requirement_mult": Stats.Fold.PRODUCT,
	&"idle_carryover": Stats.Fold.SUM,
	&"saint_statue": Stats.Fold.SUM,
	&"museum": Stats.Fold.UNION,
	&"golden_ball_tier": Stats.Fold.MIN,
	&"safe_cap_mult": Stats.Fold.PRODUCT,
	&"safe_clean_share": Stats.Fold.SUM,
	&"gauntlet": Stats.Fold.UNION,
}

static var _shared: BlackBook = null

## Validated perks in file order (which is cost order — that is the board's spine).
var perks: Array[Dictionary] = []
## Every validation failure, human readable. Empty means the file is clean.
var errors: PackedStringArray = []
var schema: int = 0
var source: String = ""

var _by_id: Dictionary = {}
var _children: Dictionary = {}


# --- loading ------------------------------------------------------------------


## The shipped Black Book, parsed once per process.
static func shared() -> BlackBook:
	if _shared == null:
		_shared = BlackBook.from_file(DEFAULT_PATH)
	return _shared


static func reset_shared() -> void:
	_shared = null


static func from_file(path: String, quiet: bool = false) -> BlackBook:
	if not FileAccess.file_exists(path):
		var b := BlackBook.new()
		b.source = path
		b._bad("missing content file %s" % path, quiet)
		return b
	return BlackBook.from_json(FileAccess.get_file_as_string(path), path, quiet)


static func from_json(text: String, source_name: String = "", quiet: bool = false) -> BlackBook:
	var json := JSON.new()
	if json.parse(text) != OK:
		var b := BlackBook.new()
		b.source = source_name
		b._bad("%s is not valid JSON (line %d: %s)"
				% [source_name, json.get_error_line(), json.get_error_message()], quiet)
		return b
	return BlackBook.from_variant(json.data, source_name, quiet)


static func from_variant(data: Variant, source_name: String = "", quiet: bool = false) -> BlackBook:
	var b := BlackBook.new()
	b.source = source_name
	b._ingest(data, quiet)
	return b


# --- queries ------------------------------------------------------------------


func is_valid() -> bool:
	return errors.is_empty() and not perks.is_empty()


func has_id(id: String) -> bool:
	return _by_id.has(id)


## The normalized perk, or an empty Dictionary. Never null, so callers can chain `.get`.
func def(id: String) -> Dictionary:
	return _by_id.get(id, {})


func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for p in perks:
		out.append(String(p["id"]))
	return out


func parents_of(id: String) -> PackedStringArray:
	return def(id).get("requires", PackedStringArray())


func children_of(id: String) -> PackedStringArray:
	return _children.get(id, PackedStringArray())


## 1 for a one-off, `repeat.max` for a ↻ perk.
func max_level(id: String) -> int:
	var p := def(id)
	return 0 if p.is_empty() else int(p["max_level"])


func is_repeatable(id: String) -> bool:
	return max_level(id) > 1


## A ★ perk whose system does not exist yet: it loads, it shows, it cannot be bought.
func is_deferred(id: String) -> bool:
	return bool(def(id).get("deferred", false))


## Juice price of the NEXT level given the level already owned: `cost + step × level`.
func cost_at_level(id: String, level: int) -> int:
	var p := def(id)
	if p.is_empty():
		return 0
	var base := int(p["cost"])
	var repeat: Variant = p["repeat"]
	if level <= 0 or repeat == null:
		return base
	var step := int((repeat as Dictionary)["step"])
	return base + step * maxi(level, 0)


func next_cost(id: String, owned: Dictionary) -> int:
	return cost_at_level(id, int(owned.get(id, 0)))


## What every level of a perk costs together — the board's "all three for 6" line.
func total_cost(id: String) -> int:
	var sum := 0
	for level in max_level(id):
		sum += cost_at_level(id, level)
	return sum


func requires_met(id: String, owned: Dictionary) -> bool:
	for parent in parents_of(id):
		if int(owned.get(parent, 0)) < 1:
			return false
	return true


## The single "can I buy this" verdict the Black Book page and `Prestige.buy` both use.
func block_for(id: String, owned: Dictionary, juice: int) -> Block:
	var p := def(id)
	if p.is_empty():
		return Block.UNKNOWN
	if bool(p["deferred"]):
		return Block.DEFERRED
	if int(owned.get(id, 0)) >= int(p["max_level"]):
		return Block.MAXED
	if not requires_met(id, owned):
		return Block.REQUIRES
	if juice < next_cost(id, owned):
		return Block.JUICE
	return Block.NONE


## Which bucket a perk kind folds into; UNION for anything the vocabulary does not name.
static func fold_of(kind: StringName) -> int:
	return int(FOLD.get(kind, Stats.Fold.UNION))


## True for a kind this file owns, false for a Ledger kind riding in a perk.
static func is_perk_kind(kind: StringName) -> bool:
	return PERK_SPECS.has(kind)


# --- ingest -------------------------------------------------------------------


func _ingest(data: Variant, quiet: bool) -> void:
	if not (data is Dictionary):
		_bad("root of %s must be an object" % _src(), quiet)
		return
	var root := data as Dictionary
	schema = int(root.get("schema", 0))
	if schema != SCHEMA_VERSION:
		_bad("%s schema %d, this loader speaks %d" % [_src(), schema, SCHEMA_VERSION], quiet)
	var raw: Variant = root.get("perks", null)
	if not (raw is Array):
		_bad("%s has no `perks` array" % _src(), quiet)
		return

	var index := 0
	for entry: Variant in raw as Array:
		var perk := _read_perk(entry, index, quiet)
		index += 1
		if perk.is_empty():
			continue
		var id := String(perk["id"])
		if _by_id.has(id):
			_bad("duplicate id `%s`" % id, quiet)
			continue
		_by_id[id] = perk
		perks.append(perk)

	_link(quiet)


func _read_perk(entry: Variant, index: int, quiet: bool) -> Dictionary:
	if not (entry is Dictionary):
		_bad("perk #%d is not an object" % index, quiet)
		return {}
	var raw := entry as Dictionary
	var id := String(raw.get("id", ""))
	var where := id if id != "" else "perk #%d" % index

	var fatal := false
	for key: Variant in raw:
		if not PERK_KEYS.has(String(key)):
			_bad("%s: unknown key `%s`" % [where, key], quiet)
			fatal = true
	for key in PERK_REQUIRED_KEYS:
		if not raw.has(key):
			_bad("%s: missing `%s`" % [where, key], quiet)
			fatal = true
	if fatal:
		return {}

	if not id.begins_with(ID_PREFIX) or id.length() <= ID_PREFIX.length():
		_bad("%s: id must read `%s<slug>`" % [where, ID_PREFIX], quiet)
		fatal = true
	elif not _is_slug(id.substr(ID_PREFIX.length())):
		_bad("%s: id slug must be lower_snake_case" % where, quiet)
		fatal = true

	for key in ["name", "flavor", "note"]:
		if not (raw[key] is String) or String(raw[key]).strip_edges().is_empty():
			_bad("%s: `%s` must be a non-empty string" % [where, key], quiet)
			fatal = true

	var cost := 0
	if not _is_number(raw["cost"]):
		_bad("%s: cost must be a whole number of Juice, not %s" % [where, raw["cost"]], quiet)
		fatal = true
	else:
		var c := float(raw["cost"])
		if not is_equal_approx(c, roundf(c)) or int(c) < 1 or int(c) > MAX_COST:
			_bad("%s: cost %s must be a whole 1..%d Juice" % [where, raw["cost"], MAX_COST], quiet)
			fatal = true
		else:
			cost = int(c)

	var deferred := false
	if raw.has("deferred"):
		if not (raw["deferred"] is bool):
			_bad("%s: deferred must be true or false" % where, quiet)
			fatal = true
		else:
			deferred = bool(raw["deferred"])

	var repeat := _read_repeat(raw.get("repeat", null), where, quiet)
	if repeat.has("_bad"):
		fatal = true
	var repeat_value: Variant = null if repeat.is_empty() or repeat.has("_bad") else repeat

	var read_requires: Variant = _read_requires(raw.get("requires", []), where, quiet)
	if read_requires == null:
		fatal = true
	var requires: PackedStringArray = PackedStringArray() if read_requires == null else read_requires

	var effects := _read_effects(raw["effects"], where, repeat_value != null, quiet)
	if effects.is_empty():
		fatal = true

	if fatal:
		return {}

	return {
		"id": id,
		"name": String(raw["name"]),
		"flavor": String(raw["flavor"]),
		"note": String(raw["note"]),
		"cost": cost,
		"repeat": repeat_value,
		"max_level": 1 if repeat_value == null else int((repeat_value as Dictionary)["max"]),
		"requires": requires,
		"deferred": deferred,
		"effects": effects,
	}


func _read_repeat(raw: Variant, where: String, quiet: bool) -> Dictionary:
	if raw == null:
		return {}
	if not (raw is Dictionary):
		_bad("%s: repeat must be null or an object" % where, quiet)
		return {"_bad": true}
	var d := raw as Dictionary
	var bad := false
	for key: Variant in d:
		if not REPEAT_KEYS.has(String(key)):
			_bad("%s: repeat has unknown key `%s`" % [where, key], quiet)
			bad = true
	for key in REPEAT_KEYS:
		if not d.has(key):
			_bad("%s: repeat is missing `%s`" % [where, key], quiet)
			bad = true
	if bad:
		return {"_bad": true}
	var max_lvl := 0
	if not _is_number(d["max"]) or not is_equal_approx(float(d["max"]), roundf(float(d["max"]))):
		_bad("%s: repeat.max must be a whole number" % where, quiet)
		bad = true
	else:
		max_lvl = int(d["max"])
		if max_lvl < 2:
			_bad("%s: repeat.max %d is not worth repeating" % [where, max_lvl], quiet)
			bad = true
	var step := 0
	if not _is_number(d["step"]) or not is_equal_approx(float(d["step"]), roundf(float(d["step"]))):
		_bad("%s: repeat.step must be a whole number of Juice" % where, quiet)
		bad = true
	else:
		step = int(d["step"])
		if step < 1:
			# A free second level is a level nobody chooses; it is a bigger first level.
			_bad("%s: repeat.step %d must add at least 1 Juice a level" % [where, step], quiet)
			bad = true
	if bad:
		return {"_bad": true}
	return {"max": max_lvl, "step": step}


## Returns null on a shape error (distinct from a legitimately empty list).
func _read_requires(raw: Variant, where: String, quiet: bool) -> Variant:
	if raw == null:
		return PackedStringArray()
	if not (raw is Array):
		_bad("%s: requires must be an array of perk ids" % where, quiet)
		return null
	var out: PackedStringArray = []
	for item: Variant in raw as Array:
		if not (item is String) or String(item).is_empty():
			_bad("%s: requires holds a non-id entry" % where, quiet)
			return null
		if String(item) == where:
			_bad("%s: requires itself" % where, quiet)
			return null
		if out.has(String(item)):
			_bad("%s: requires `%s` twice" % [where, item], quiet)
			return null
		out.append(String(item))
	return out


func _read_effects(raw: Variant, where: String, repeatable: bool, quiet: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array) or (raw as Array).is_empty():
		_bad("%s: effects must be a non-empty array" % where, quiet)
		return out
	var per_level_seen := false
	for item: Variant in raw as Array:
		var eff := _read_effect(item, where, repeatable, quiet)
		if eff.is_empty():
			out.clear()
			return out
		per_level_seen = per_level_seen or bool(eff["per_level"])
		out.append(eff)
	if repeatable and not per_level_seen:
		_bad("%s: repeatable but no effect is per_level — levels 2+ would buy nothing" % where, quiet)
		out.clear()
	return out


## A perk effect is either one of this file's own kinds or a Ledger kind — and a Ledger kind
## is validated by the Ledger's own reader, so there is exactly one copy of those bands.
func _read_effect(raw: Variant, where: String, repeatable: bool, quiet: bool) -> Dictionary:
	if not (raw is Dictionary):
		_bad("%s: an effect is not an object" % where, quiet)
		return {}
	var d := raw as Dictionary
	var kind := StringName(String(d.get("kind", "")))
	if not PERK_SPECS.has(kind):
		if Upgrades.EFFECT_SPECS.has(kind):
			var borrowed := Upgrades.read_effect(d, where, repeatable)
			if borrowed.has("error"):
				_bad(String(borrowed["error"]), quiet)
				return {}
			borrowed["perk_kind"] = false
			return borrowed
		_bad("%s: unknown effect kind `%s`" % [where, kind], quiet)
		return {}

	for key: Variant in d:
		if not Upgrades.EFFECT_KEYS.has(String(key)):
			_bad("%s: effect has unknown key `%s`" % [where, key], quiet)
			return {}
	var spec: Dictionary = PERK_SPECS[kind]

	var per_level := false
	if d.has("per_level"):
		if not (d["per_level"] is bool):
			_bad("%s: %s per_level must be a bool" % [where, kind], quiet)
			return {}
		per_level = bool(d["per_level"])
	if per_level and not repeatable:
		_bad("%s: %s is per_level on a perk with no repeat block" % [where, kind], quiet)
		return {}

	# No perk kind takes a target: a perk is a promise about the whole career, not about one
	# switch group or one piece of hardware.
	if d.has("target"):
		_bad("%s: %s takes no target" % [where, kind], quiet)
		return {}

	var num := 0.0
	var form: StringName = spec.get("value", &"")
	if form == &"":
		if d.has("value"):
			_bad("%s: %s takes no value" % [where, kind], quiet)
			return {}
	elif not d.has("value"):
		_bad("%s: %s needs a `value`" % [where, kind], quiet)
		return {}
	else:
		if not _is_number(d["value"]):
			_bad("%s: %s value must be a number" % [where, kind], quiet)
			return {}
		num = float(d["value"])
		if form == &"int" and not is_equal_approx(num, roundf(num)):
			_bad("%s: %s value %f must be a whole number" % [where, kind, num], quiet)
			return {}
		if spec.has("min") and num < float(spec["min"]):
			_bad("%s: %s value %f below minimum %f" % [where, kind, num, spec["min"]], quiet)
			return {}
		if spec.has("max") and num > float(spec["max"]):
			_bad("%s: %s value %f above maximum %f" % [where, kind, num, spec["max"]], quiet)
			return {}

	return {
		"kind": kind,
		"target": StringName(""),
		"num": num,
		"money": BigMoney.zero(),
		"per_level": per_level,
		"perk_kind": true,
	}


## Second pass: cross-references only resolvable once every perk is in.
func _link(quiet: bool) -> void:
	var dead: PackedStringArray = []
	for p in perks:
		var id := String(p["id"])
		var requires: PackedStringArray = p["requires"]
		for parent in requires:
			if not _by_id.has(parent):
				_bad("%s: requires unknown perk `%s`" % [id, parent], quiet)
				dead.append(id)
				continue
			# A live perk behind a deferred one is a live perk nobody can reach.
			if bool(def(parent)["deferred"]) and not bool(p["deferred"]):
				_bad("%s: requires `%s`, which is deferred — it could never be bought"
						% [id, parent], quiet)
				dead.append(id)

	for id in dead:
		if _by_id.erase(id):
			for i in perks.size():
				if String(perks[i]["id"]) == id:
					perks.remove_at(i)
					break

	_detect_cycles(quiet)

	_children.clear()
	for p in perks:
		var requires: PackedStringArray = p["requires"]
		for parent in requires:
			var kids: PackedStringArray = _children.get(parent, PackedStringArray())
			kids.append(String(p["id"]))
			_children[parent] = kids


## Kahn's algorithm, same as the Ledger's: anything still pending when nothing can settle is
## a cycle, and a cycle is a perk nobody can ever buy into.
func _detect_cycles(quiet: bool) -> void:
	var pending := {}
	for p in perks:
		pending[String(p["id"])] = true
	var progress := true
	while progress:
		progress = false
		for id: String in pending.keys():
			var ready := true
			for parent in parents_of(id):
				if pending.has(parent):
					ready = false
					break
			if ready:
				pending.erase(id)
				progress = true
	if not pending.is_empty():
		var stuck := PackedStringArray(pending.keys())
		stuck.sort()
		_bad("requires cycle among: %s" % ", ".join(stuck), quiet)


# --- internals ----------------------------------------------------------------


func _bad(msg: String, quiet: bool) -> void:
	errors.append(msg)
	if not quiet:
		push_error("blackbook: " + msg)


func _src() -> String:
	return source if source != "" else "<blackbook>"


static func _is_number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


static func _is_slug(s: String) -> bool:
	if s.is_empty() or not (s[0] >= "a" and s[0] <= "z"):
		return false
	for i in s.length():
		var c := s[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true
