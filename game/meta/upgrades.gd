class_name Upgrades
extends RefCounted
## The Ledger catalog: loads and validates `game/content/upgrades.json`
## (schema + effects vocabulary: specs/ledger-data.md).
##
## Content is design-owned and tuned in data-only commits, so this loader is deliberately
## strict: every key, kind, target and money string is checked, an unknown key is an error
## (it catches `"requries"` before a player does), and a node that fails validation is
## SKIPPED rather than half-loaded. Errors are collected in `errors` and pushed via
## push_error so a bad tuning commit is loud at boot instead of silently free.
##
## Pure RefCounted, no autoloads, no Node — it loads under the bare test runner.

const DEFAULT_PATH := "res://game/content/upgrades.json"
const SCHEMA_VERSION := 1
const MAX_TIER := 7

## docs/04 branch letters A–F, in board column order.
const BRANCHES: PackedStringArray = [
	"rackets", "fronts", "muscle", "crew", "influence", "blackbook",
]

## Table hardware ids the table lane registers (specs/m1-hook.md "hardware visibility").
## `bumper_3` and `kickback_right` are used by content but missing from that list — the
## spec enumerates the M1 wave, the data ships the full T0–T3 set. Reported, not fixed here.
const HARDWARE_IDS: PackedStringArray = [
	"bumper_2", "bumper_3", "slingshots", "inlane_guides", "rollovers",
	"spinner_numbers", "wire_bank", "laundromat_loop",
	"storefront_laundromat", "storefront_pizzeria", "storefront_pawn",
	"orbit_left", "kickback_left", "kickback_right", "bribe_target", "cop_targets",
	# M2 Club deck (specs/m2-content.md)
	"club_deck", "staircase_ramp", "roulette_wheel", "slot_reels",
	"high_roller_saucer", "backroom_saucer", "club_flippers",
	# M3 Docks & Penthouse (specs/m3-fall-rise.md)
	"docks", "containers", "crane", "cargo_ramp", "orbit_right",
	"penthouse", "commission_chairs", "sitdown_saucer", "penthouse_stairs",
]

## Switch groups `Game.earn_switch` pays out to. `all` folds into every other group.
const VALUE_GROUPS: PackedStringArray = [
	"all", "bumpers", "slings", "spinner", "rollovers", "wire", "storefronts", "orbit",
	"ramps", "casino", "smuggling", "penthouse",
]

## Boolean gameplay flags. A new flag needs code that reads it, so adding one here is a
## deliberate act — that is the point of validating against a list.
const FEATURE_FLAGS: PackedStringArray = [
	"plunger_bands", "casino_wash",
	# M2 influence/fronts flags (specs/m2-content.md §3) — consumers land with their lanes.
	"coolers_fired", "inspector_vacation", "police_scanner", "rain_insurance",
	"wiretap_wire", "insurance_policy", "comps",
]

## Milestone marks the reveal engine understands (docs/04 "Milestone reveals").
const REVEAL_EVENTS: PackedStringArray = [
	"first_tilt", "first_double_pinch", "first_raid_survived",
	"first_briefcase_setup", "first_club", "first_skip_town",
]

const KICKBACK_SIDES: PackedStringArray = ["left", "right"]

## Specialists live on branch D — CREW becomes people (docs/04 branch D, specs/m2-content.md §2).
const SPECIALIST_BRANCH := "crew"

## One instrument per character is their voice AND their stem presence (docs/08 §5). Validating
## the word means a typo in a hire is caught here instead of failing silent in the mixer; the
## list is meta-lane owned, so a new voice is a one-line change requested via report.
const SPECIALIST_INSTRUMENTS: PackedStringArray = [
	"tuba", "clarinet", "alto_sax", "violin", "cornet", "trombone", "oboe", "cello",
	"muted_trumpet", "harmonica", "banjo", "accordion", "upright_bass", "vibraphone",
	"bicycle_bell", "whistle",
]

const NODE_KEYS: PackedStringArray = [
	"id", "branch", "tier", "name", "flavor", "cost",
	"repeat", "requires", "reveal", "effects", "table_change", "specialist",
]
const NODE_REQUIRED_KEYS: PackedStringArray = [
	"id", "branch", "tier", "name", "flavor", "cost", "effects", "table_change",
]
const EFFECT_KEYS: PackedStringArray = ["kind", "target", "value", "per_level"]
const REPEAT_KEYS: PackedStringArray = ["max", "growth"]
const REVEAL_KEYS: PackedStringArray = ["rank", "event", "purchased", "dirty_held"]
const SPECIALIST_KEYS: PackedStringArray = ["id", "instrument", "quips"]
const SPECIALIST_REQUIRED_KEYS: PackedStringArray = ["id", "instrument"]

## Per-kind shape: which vocabulary the `target` belongs to, and how `value` is read.
## value forms: `num` (float), `int` (whole float), `money` (BigMoney.parse string).
const EFFECT_SPECS := {
	&"unlock_hardware": {"target": &"hardware"},
	&"feature_flag": {"target": &"flag"},
	&"value_mult": {"target": &"group", "value": &"num", "min": 0.000001},
	&"value_add": {"target": &"group", "value": &"money"},
	&"idle_rate_add": {"target": &"racket", "value": &"money"},
	&"launder_rate_add": {"value": &"num", "min": 0.0, "max": 1.0},
	&"launder_cap_add": {"value": &"money"},
	&"pocket_money_set": {"value": &"money"},
	&"passive_wash_add": {"value": &"num", "min": 0.0, "max": 1.0},
	&"safe_hours_set": {"value": &"num", "min": 0.0},
	&"bench_slot_add": {"value": &"int", "min": 1.0},
	&"ball_save_charges": {"value": &"int", "min": 1.0},
	&"tilt_leans_add": {"value": &"int", "min": 1.0},
	&"flipper_power_mult": {"value": &"num", "min": 0.000001},
	&"kickback_unlock": {"target": &"side"},
	&"bribe_unlock": {},
	&"job_slots_set": {"value": &"int", "min": 1.0},
	&"collect_minutes_mult": {"value": &"num", "min": 0.000001},
	# --- M2 specialist powers (specs/m2-content.md §2) ---------------------------
	# Ranges are deliberately tight per kind: these are all one-number powers, so the band
	# is the only thing standing between "-10% cooldown" and "-1000% cooldown". A multiplier
	# that helps by going UP reads 1.0..3.0; one that helps by going DOWN reads 0..1.0;
	# a fraction reads as its own cap. Fold buckets live in Stats.FOLD.
	&"heat_decay_mult": {"value": &"num", "min": 1.0, "max": 3.0},
	&"bail_discount": {"value": &"num", "min": 0.000001, "max": 0.6},
	&"auto_collect_interval": {"value": &"num", "min": 1.0, "max": 600.0},
	&"casino_edge_add": {"value": &"num", "min": 0.000001, "max": 0.12},
	# Pockets are whole things and the house keeps at least one of its three, so the band is
	# 1..2 per effect and `Stats.CASINO_POCKETS_MAX` holds the ceiling however many are bought.
	&"casino_pocket_add": {"value": &"int", "min": 1.0, "max": 2.0},
	&"job_reroll_add": {"value": &"int", "min": 1.0, "max": 10.0},
	&"job_respect_mult": {"value": &"num", "min": 1.0, "max": 3.0},
	&"serve_speed_mult": {"value": &"num", "min": 1.0, "max": 3.0},
	&"auto_launder_per_sec": {"value": &"num", "min": 0.000001, "max": 0.25},
	&"kickback_cooldown_mult": {"value": &"num", "min": 0.000001, "max": 1.0},
	&"aim_line": {"value": &"int", "min": 1.0, "max": 10.0},
	&"all_dirty_mult": {"value": &"num", "min": 1.0, "max": 3.0},
	# --- M3 laundering structure (the SIM-2 findings) ----------------------------
	# The sim measured the wash cap binding on 107 of 107 late Nights, with 100% of wash
	# shots then moving nothing: `launder_cap_add` is an ADDITIVE cap chasing MULTIPLICATIVE
	# income, and additive never catches multiplicative. These two kinds are the answer.
	#
	# A cap MULTIPLIER rides the same curve income does, so a T6/T7 line can keep the wash
	# alive instead of adding a rounding error to it. Band 1.0..3.0, like every other
	# "helps by going up" multiplier; per_level compounds, so 1.5 over 6 levels is ×11.4.
	&"launder_cap_mult": {"value": &"num", "min": 1.0, "max": 3.0},
	# The other half: a fraction of each dirty payout that arrives CLEAN instead, so late
	# income never has to queue for the loop at all. Capped hard at `Stats.CLEAN_SHARE_MAX`
	# (0.25); one node may buy at most 10 of those 25 points, so the ceiling is a build
	# across branches and never a single card.
	&"clean_share": {"value": &"num", "min": 0.000001, "max": 0.10},
}

## Why a node cannot be bought right now. NONE means "take the money".
enum Block { NONE, UNKNOWN, RANK, REQUIRES, MAXED, MONEY }

const _LOG10_E := 0.4342944819032518

static var _shared: Upgrades = null

## Validated nodes in file order. Each is a normalized Dictionary — see `_read_node`.
var nodes: Array[Dictionary] = []
## Every validation failure, human readable. Empty means the file is clean.
var errors: PackedStringArray = []
var schema: int = 0
var source: String = ""

var _by_id: Dictionary = {}
var _children: Dictionary = {}


# --- loading ------------------------------------------------------------------


## The shipped catalog, parsed once per process.
static func shared() -> Upgrades:
	if _shared == null:
		_shared = Upgrades.from_file(DEFAULT_PATH)
	return _shared


## Drops the process-wide cache. Tests that swap content files call this; gameplay never has to.
static func reset_shared() -> void:
	_shared = null


static func from_file(path: String, quiet: bool = false) -> Upgrades:
	var text := ""
	if FileAccess.file_exists(path):
		text = FileAccess.get_file_as_string(path)
	else:
		var u := Upgrades.new()
		u._bad("missing content file %s" % path, quiet)
		return u
	return Upgrades.from_json(text, path, quiet)


static func from_json(text: String, source_name: String = "", quiet: bool = false) -> Upgrades:
	# JSON.new().parse() rather than JSON.parse_string(): the instance form reports a
	# syntax error through its return value instead of pushing an engine error, so a
	# deliberately-broken fixture in a test does not print like an engine fault.
	var json := JSON.new()
	if json.parse(text) != OK:
		var u := Upgrades.new()
		u.source = source_name
		u._bad("%s is not valid JSON (line %d: %s)" % [source_name, json.get_error_line(), json.get_error_message()], quiet)
		return u
	return Upgrades.from_variant(json.data, source_name, quiet)


static func from_variant(data: Variant, source_name: String = "", quiet: bool = false) -> Upgrades:
	var u := Upgrades.new()
	u.source = source_name
	u._ingest(data, quiet)
	return u


# --- queries ------------------------------------------------------------------


func is_valid() -> bool:
	return errors.is_empty() and not nodes.is_empty()


func has_id(id: String) -> bool:
	return _by_id.has(id)


## The normalized node, or an empty Dictionary. Never null, so callers can chain `.get`.
func def(id: String) -> Dictionary:
	return _by_id.get(id, {})


func ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for n in nodes:
		out.append(String(n["id"]))
	return out


## Ids that list `id` in their `requires` (the far end of the red strings).
func children_of(id: String) -> PackedStringArray:
	return _children.get(id, PackedStringArray())


func parents_of(id: String) -> PackedStringArray:
	return def(id).get("requires", PackedStringArray())


## 1 for a one-off, `repeat.max` for a repeatable.
func max_level(id: String) -> int:
	var n := def(id)
	if n.is_empty():
		return 0
	return int(n["max_level"])


func is_repeatable(id: String) -> bool:
	return max_level(id) > 1


func is_specialist(id: String) -> bool:
	var n := def(id)
	return not n.is_empty() and not (n["specialist"] as Dictionary).is_empty()


## The crew as descriptors, for the flow and audio lanes (specs/m2-content.md §2):
##   {id, node, name, branch, tier, instrument, quips, level, max_level}
##
## `owned` null asks the catalog "who is hireable" — every specialist it declares, at level 0.
## Passing the owned map asks "who works for me" — only hired ones, with the level clamped the
## same way Stats clamps it, so a corrupt save cannot hand the mixer a level-99 tuba.
## `Stats.specialists()` is the same list for the career currently loaded.
func specialists(owned: Variant = null) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in nodes:
		var specialist: Dictionary = n["specialist"]
		if specialist.is_empty():
			continue
		var level := 0
		if owned is Dictionary:
			level = int((owned as Dictionary).get(String(n["id"]), 0))
			if level < 1:
				continue
			level = mini(level, int(n["max_level"]))
		out.append({
			"id": String(specialist["id"]),
			"node": String(n["id"]),
			"name": String(n["name"]),
			"branch": String(n["branch"]),
			"tier": int(n["tier"]),
			"instrument": String(specialist["instrument"]),
			"quips": String(specialist["quips"]),
			"level": level,
			"max_level": int(n["max_level"]),
		})
	return out


## Cost of the NEXT purchase given the level already owned: `base × growth^level`.
## Evaluated in log10 space so a level-500 repeatable is arithmetic, not an overflow
## (same trick as Rates.repeatable_cost, but with the node's own growth factor).
func cost_at_level(id: String, level: int) -> BigMoney:
	var n := def(id)
	if n.is_empty():
		return BigMoney.zero()
	var base: BigMoney = n["base_cost"]
	var repeat: Variant = n["repeat"]
	if level <= 0 or repeat == null:
		return base.copy()
	var growth := float((repeat as Dictionary)["growth"])
	if growth <= 0.0 or not is_finite(growth):
		return base.copy()
	return base.mul_big(_pow10_frac(float(level) * log(growth) * _LOG10_E))


## Cost of the next level for a node, given the whole owned map.
func next_cost(id: String, owned: Dictionary) -> BigMoney:
	return cost_at_level(id, int(owned.get(id, 0)))


func requires_met(id: String, owned: Dictionary) -> bool:
	for parent in parents_of(id):
		if int(owned.get(parent, 0)) < 1:
			return false
	return true


## The single "can I buy this" verdict the docket and the compass both use.
func block_for(id: String, owned: Dictionary, rank: int, clean: BigMoney) -> Block:
	var n := def(id)
	if n.is_empty():
		return Block.UNKNOWN
	if int(owned.get(id, 0)) >= int(n["max_level"]):
		return Block.MAXED
	if rank < int(n["tier"]):
		return Block.RANK
	if not requires_met(id, owned):
		return Block.REQUIRES
	if clean != null and clean.cmp(next_cost(id, owned)) < 0:
		return Block.MONEY
	return Block.NONE


# --- ingest -------------------------------------------------------------------


func _ingest(data: Variant, quiet: bool) -> void:
	if not (data is Dictionary):
		_bad("root of %s must be an object" % _src(), quiet)
		return
	var root := data as Dictionary
	schema = int(root.get("schema", 0))
	if schema != SCHEMA_VERSION:
		_bad("%s schema %d, this loader speaks %d" % [_src(), schema, SCHEMA_VERSION], quiet)
	var raw: Variant = root.get("nodes", null)
	if not (raw is Array):
		_bad("%s has no `nodes` array" % _src(), quiet)
		return

	var index := 0
	for entry: Variant in raw as Array:
		var node := _read_node(entry, index, quiet)
		index += 1
		if node.is_empty():
			continue
		var id := String(node["id"])
		if _by_id.has(id):
			_bad("duplicate id `%s`" % id, quiet)
			continue
		_by_id[id] = node
		nodes.append(node)

	_link(quiet)


func _read_node(entry: Variant, index: int, quiet: bool) -> Dictionary:
	if not (entry is Dictionary):
		_bad("node #%d is not an object" % index, quiet)
		return {}
	var raw := entry as Dictionary
	var id := String(raw.get("id", ""))
	var where := id if id != "" else "node #%d" % index

	var fatal := false
	for key: Variant in raw:
		if not NODE_KEYS.has(String(key)):
			_bad("%s: unknown key `%s`" % [where, key], quiet)
			fatal = true
	for key in NODE_REQUIRED_KEYS:
		if not raw.has(key):
			_bad("%s: missing `%s`" % [where, key], quiet)
			fatal = true
	if fatal:
		return {}

	var branch := String(raw["branch"])
	if not BRANCHES.has(branch):
		_bad("%s: unknown branch `%s`" % [where, branch], quiet)
		fatal = true
	if id.is_empty():
		_bad("%s: empty id" % where, quiet)
		fatal = true
	elif not id.begins_with(branch + "."):
		_bad("%s: id must read `%s.<slug>`" % [where, branch], quiet)
		fatal = true

	var tier := 0
	if not _is_number(raw["tier"]):
		_bad("%s: tier must be a number" % where, quiet)
		fatal = true
	else:
		tier = int(raw["tier"])
		if tier < 0 or tier > MAX_TIER:
			_bad("%s: tier %d outside 0..%d" % [where, tier, MAX_TIER], quiet)
			fatal = true

	for key in ["name", "flavor", "table_change"]:
		if not (raw[key] is String) or String(raw[key]).strip_edges().is_empty():
			_bad("%s: `%s` must be a non-empty string" % [where, key], quiet)
			fatal = true

	var base_cost := BigMoney.zero()
	if not (raw["cost"] is String):
		_bad("%s: cost must be a BigMoney string" % where, quiet)
		fatal = true
	else:
		base_cost = BigMoney.parse(String(raw["cost"]))
		if not base_cost.is_positive():
			_bad("%s: cost `%s` does not parse to a positive amount" % [where, raw["cost"]], quiet)
			fatal = true

	var repeat := _read_repeat(raw.get("repeat", null), where, quiet)
	if repeat.get("_bad", false):
		fatal = true
	var repeat_value: Variant = null if repeat.is_empty() or repeat.has("_bad") else repeat

	var read_requires: Variant = _read_requires(raw.get("requires", []), where, quiet)
	if read_requires == null:
		fatal = true
	var requires: PackedStringArray = PackedStringArray() if read_requires == null else read_requires

	var reveal := _read_reveal(raw.get("reveal", null), where, tier, quiet)
	if reveal.has("_bad"):
		fatal = true
		reveal = {}

	var effects := _read_effects(raw["effects"], where, repeat_value != null, quiet)
	if effects.is_empty():
		fatal = true

	var specialist := _read_specialist(raw.get("specialist", null), where, branch, quiet)
	if specialist.has("_bad"):
		fatal = true
		specialist = {}

	if fatal:
		return {}

	return {
		"id": id,
		"branch": branch,
		"tier": tier,
		"name": String(raw["name"]),
		"flavor": String(raw["flavor"]),
		"cost": String(raw["cost"]),
		"base_cost": base_cost,
		"repeat": repeat_value,
		"max_level": 1 if repeat_value == null else int((repeat_value as Dictionary)["max"]),
		"requires": requires,
		"reveal": reveal,
		"effects": effects,
		"table_change": String(raw["table_change"]),
		"specialist": specialist,
	}


## A hire, not an upgrade: `{"id": "big_sal", "instrument": "tuba", "quips": "big_sal"}`.
## `quips` (the headline table this guy's one-liners come from) defaults to the specialist id.
## Empty Dictionary = an ordinary node; `_bad` = a malformed one.
func _read_specialist(raw: Variant, where: String, branch: String, quiet: bool) -> Dictionary:
	if raw == null:
		return {}
	if not (raw is Dictionary):
		_bad("%s: specialist must be null or an object" % where, quiet)
		return {"_bad": true}
	var d := raw as Dictionary
	var bad := false
	for key: Variant in d:
		if not SPECIALIST_KEYS.has(String(key)):
			_bad("%s: specialist has unknown key `%s`" % [where, key], quiet)
			bad = true
	for key in SPECIALIST_REQUIRED_KEYS:
		if not d.has(key):
			_bad("%s: specialist is missing `%s`" % [where, key], quiet)
			bad = true
	if bad:
		return {"_bad": true}
	if branch != SPECIALIST_BRANCH:
		_bad("%s: a specialist is a %s hire, not a %s node" % [where, SPECIALIST_BRANCH, branch], quiet)
		bad = true
	var sid := String(d["id"]) if d["id"] is String else ""
	if not _is_slug(sid):
		_bad("%s: specialist.id `%s` must be a lower_snake_case slug" % [where, d["id"]], quiet)
		bad = true
	if not (d["instrument"] is String) or not SPECIALIST_INSTRUMENTS.has(String(d["instrument"])):
		_bad("%s: specialist.instrument `%s` is not a voice the mixer knows" % [where, d["instrument"]], quiet)
		bad = true
	var quips := sid
	if d.has("quips"):
		quips = String(d["quips"]) if d["quips"] is String else ""
		if not _is_slug(quips):
			_bad("%s: specialist.quips `%s` must be a lower_snake_case slug" % [where, d["quips"]], quiet)
			bad = true
	if bad:
		return {"_bad": true}
	return {"id": sid, "instrument": String(d["instrument"]), "quips": quips}


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
	if not _is_number(d["max"]):
		_bad("%s: repeat.max must be a number" % where, quiet)
		bad = true
	else:
		max_lvl = int(d["max"])
		if max_lvl < 2 or not is_equal_approx(float(d["max"]), roundf(float(d["max"]))):
			_bad("%s: repeat.max %s must be a whole number >= 2" % [where, d["max"]], quiet)
			bad = true
	var growth := 0.0
	if not _is_number(d["growth"]):
		_bad("%s: repeat.growth must be a number" % where, quiet)
		bad = true
	else:
		growth = float(d["growth"])
		if growth <= 1.0:
			_bad("%s: repeat.growth %s must be > 1.0" % [where, d["growth"]], quiet)
			bad = true
	if bad:
		return {"_bad": true}
	return {"max": max_lvl, "growth": growth}


## Returns null on a shape error (distinct from a legitimately empty list).
func _read_requires(raw: Variant, where: String, quiet: bool) -> Variant:
	if raw == null:
		return PackedStringArray()
	if not (raw is Array):
		_bad("%s: requires must be an array of node ids" % where, quiet)
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


func _read_reveal(raw: Variant, where: String, tier: int, quiet: bool) -> Dictionary:
	if raw == null:
		return {}
	if not (raw is Dictionary):
		_bad("%s: reveal must be null or an object" % where, quiet)
		return {"_bad": true}
	var d := raw as Dictionary
	if d.is_empty():
		return {}
	if d.size() != 1:
		_bad("%s: reveal takes exactly one condition, got %d" % [where, d.size()], quiet)
		return {"_bad": true}
	var key := String((d.keys() as Array)[0])
	var value: Variant = d[key]
	match key:
		"rank":
			if not _is_number(value) or int(value) < 0 or int(value) > MAX_TIER:
				_bad("%s: reveal.rank %s outside 0..%d" % [where, value, MAX_TIER], quiet)
				return {"_bad": true}
			if int(value) > tier:
				_bad("%s: reveal.rank %d is past its own tier %d — it would reveal after it is already buyable" % [where, int(value), tier], quiet)
				return {"_bad": true}
			return {"rank": int(value)}
		"event":
			if not (value is String) or not REVEAL_EVENTS.has(String(value)):
				_bad("%s: reveal.event `%s` is not a known milestone" % [where, value], quiet)
				return {"_bad": true}
			return {"event": String(value)}
		"purchased":
			if not (value is String) or String(value).is_empty():
				_bad("%s: reveal.purchased must be a node id" % where, quiet)
				return {"_bad": true}
			return {"purchased": String(value)}
		"dirty_held":
			if not (value is String) or not BigMoney.parse(String(value)).is_positive():
				_bad("%s: reveal.dirty_held `%s` is not a positive amount" % [where, value], quiet)
				return {"_bad": true}
			return {"dirty_held": String(value)}
	_bad("%s: unknown reveal condition `%s`" % [where, key], quiet)
	return {"_bad": true}


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


func _read_effect(raw: Variant, where: String, repeatable: bool, quiet: bool) -> Dictionary:
	var out := Upgrades.read_effect(raw, where, repeatable)
	if out.has("error"):
		_bad(String(out["error"]), quiet)
		return {}
	return out


## Validates and normalizes ONE effect against `EFFECT_SPECS`, with no instance behind it:
## returns the normalized effect, or `{"error": "..."}` for the caller to report its own way.
##
## Static because the Black Book (`game/meta/blackbook.gd`) lets a prestige perk promise a
## Ledger effect, and it must be measured against these bands rather than a second copy of
## them — one vocabulary, one set of numbers, two loaders.
static func read_effect(raw: Variant, where: String, repeatable: bool) -> Dictionary:
	if not (raw is Dictionary):
		return {"error": "%s: an effect is not an object" % where}
	var d := raw as Dictionary
	for key: Variant in d:
		if not EFFECT_KEYS.has(String(key)):
			return {"error": "%s: effect has unknown key `%s`" % [where, key]}
	var kind := StringName(String(d.get("kind", "")))
	if not EFFECT_SPECS.has(kind):
		return {"error": "%s: unknown effect kind `%s`" % [where, kind]}
	var spec: Dictionary = EFFECT_SPECS[kind]

	var per_level := false
	if d.has("per_level"):
		if not (d["per_level"] is bool):
			return {"error": "%s: %s per_level must be a bool" % [where, kind]}
		per_level = bool(d["per_level"])
	if per_level and not repeatable:
		return {"error": "%s: %s is per_level on a node with no repeat block" % [where, kind]}

	var target := StringName("")
	if spec.has("target"):
		if not (d.get("target", null) is String):
			return {"error": "%s: %s needs a `target`" % [where, kind]}
		var t := String(d["target"])
		if not _target_ok(spec["target"], t):
			return {"error": "%s: %s target `%s` is not a known %s" % [where, kind, t, spec["target"]]}
		target = StringName(t)
	elif d.has("target"):
		return {"error": "%s: %s takes no target" % [where, kind]}

	var num := 0.0
	var money := BigMoney.zero()
	var form: StringName = spec.get("value", &"")
	if form == &"":
		if d.has("value"):
			return {"error": "%s: %s takes no value" % [where, kind]}
	elif not d.has("value"):
		return {"error": "%s: %s needs a `value`" % [where, kind]}
	elif form == &"money":
		if not (d["value"] is String):
			return {"error": "%s: %s value must be a BigMoney string, not a bare number" % [where, kind]}
		money = BigMoney.parse(String(d["value"]))
		if not money.is_positive():
			return {"error": "%s: %s value `%s` is not a positive amount" % [where, kind, d["value"]]}
	else:
		if not _is_number(d["value"]):
			return {"error": "%s: %s value must be a number" % [where, kind]}
		num = float(d["value"])
		if form == &"int" and not is_equal_approx(num, roundf(num)):
			return {"error": "%s: %s value %f must be a whole number" % [where, kind, num]}
		if spec.has("min") and num < float(spec["min"]):
			return {"error": "%s: %s value %f below minimum %f" % [where, kind, num, spec["min"]]}
		if spec.has("max") and num > float(spec["max"]):
			return {"error": "%s: %s value %f above maximum %f" % [where, kind, num, spec["max"]]}

	return {
		"kind": kind,
		"target": target,
		"num": num,
		"money": money,
		"per_level": per_level,
	}


static func _target_ok(vocab: StringName, value: String) -> bool:
	match vocab:
		&"hardware":
			return HARDWARE_IDS.has(value)
		&"flag":
			return FEATURE_FLAGS.has(value)
		&"group":
			return VALUE_GROUPS.has(value)
		&"side":
			return KICKBACK_SIDES.has(value)
		&"racket":
			# Idle rackets are free-form labels (docs/04 branch A grows them every city).
			return not value.strip_edges().is_empty()
	return false


## Second pass: cross-references only resolvable once every node is in.
func _link(quiet: bool) -> void:
	var dead: PackedStringArray = []
	var hired: Dictionary = {}
	for n in nodes:
		var id := String(n["id"])
		var specialist: Dictionary = n["specialist"]
		if not specialist.is_empty():
			var sid := String(specialist["id"])
			if hired.has(sid):
				_bad("%s: specialist `%s` is already hired by `%s`" % [id, sid, hired[sid]], quiet)
				dead.append(id)
			else:
				hired[sid] = id
		var requires: PackedStringArray = n["requires"]
		for parent in requires:
			if not _by_id.has(parent):
				_bad("%s: requires unknown node `%s`" % [id, parent], quiet)
				dead.append(id)
				continue
			var pt := int(def(parent)["tier"])
			if pt > int(n["tier"]):
				_bad("%s (T%d) requires `%s` from a later tier T%d" % [id, n["tier"], parent, pt], quiet)
				dead.append(id)
		var reveal: Dictionary = n["reveal"]
		if reveal.has("purchased") and not _by_id.has(String(reveal["purchased"])):
			_bad("%s: reveal.purchased points at unknown node `%s`" % [id, reveal["purchased"]], quiet)
			dead.append(id)

	for id in dead:
		if _by_id.erase(id):
			for i in nodes.size():
				if String(nodes[i]["id"]) == id:
					nodes.remove_at(i)
					break

	_detect_cycles(quiet)

	_children.clear()
	for n in nodes:
		var requires: PackedStringArray = n["requires"]
		for parent in requires:
			var kids: PackedStringArray = _children.get(parent, PackedStringArray())
			kids.append(String(n["id"]))
			_children[parent] = kids


## Kahn's algorithm — anything left when no node has all its parents resolved is a cycle,
## and a cycle in the requires graph is a branch nobody can ever buy into.
func _detect_cycles(quiet: bool) -> void:
	var pending := {}
	for n in nodes:
		pending[String(n["id"])] = true
	var settled := {}
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
				settled[id] = true
				progress = true
	if not pending.is_empty():
		var stuck := PackedStringArray(pending.keys())
		stuck.sort()
		_bad("requires cycle among: %s" % ", ".join(stuck), quiet)


# --- internals ----------------------------------------------------------------


func _bad(msg: String, quiet: bool) -> void:
	errors.append(msg)
	if not quiet:
		push_error("upgrades: " + msg)


func _src() -> String:
	return source if source != "" else "<upgrades>"


static func _is_number(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))


## Content-facing identifiers (specialist ids, quip tables) are lower_snake_case so they can
## be StringNames, filenames and JSON keys in the audio and writing lanes without translation.
static func _is_slug(s: String) -> bool:
	if s.is_empty() or not (s[0] >= "a" and s[0] <= "z"):
		return false
	for i in s.length():
		var c := s[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return true


## 10^x in mantissa/exponent form, for any real x.
static func _pow10_frac(x: float) -> BigMoney:
	if not is_finite(x):
		return BigMoney.zero()
	var ex := floori(x)
	return BigMoney.of(pow(10.0, x - float(ex)), ex)
