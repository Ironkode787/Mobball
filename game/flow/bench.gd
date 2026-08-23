class_name Bench
extends RefCounted
## The Bench — pinball's three balls, as named goons (docs/01 §4, specs/m1-hook.md Lane 1).
##
## Pure logic: no nodes, no wallet, no clock. The RNG is seeded and every mutation is a
## method, so a Night can be replayed exactly by the sims and the whole roster round-trips
## through `to_dict()` for the save file.
##
## A guy is a plain Dictionary with String keys (JSON-native — the save file writes it
## verbatim). `level` prices bail; `trait` is his one visible line (docs/01 §4), handed out
## from `GuyTraits` once the career is worth naming a crew for.

## Guys start free, sit in holding after a pinch, and walk after sitting a Night out.
const STATE_FREE := "free"
const STATE_HOLDING := "holding"

const NAMES_PATH := "res://game/content/names.json"
const START_SLOTS := 4
## Nights survived per experience level (level prices bail, docs/03 §8).
const NIGHTS_PER_LEVEL := 3
## Nights in holding: a normal pinch is one Night off, a raid stretch is two (docs/05 §2).
## Balance-sim ruling: at 1 Night the bail sink never fired (0 short line-ups in 1,596
## simulated Nights) — a stretch has to outlast the roster's slack to make bail a decision.
const SIT_OUT_NIGHTS := 2
const SIT_OUT_NIGHTS_RAID := 3

var guys: Array[Dictionary] = []
var slots: int = START_SLOTS
## Career rank new hires are recruited at — it decides whether they come with a trait
## (GuyTraits.MIN_RANK). Set by `Game` before every `night_tick`; the four guys the career
## opens with are hired at R0 and are traitless by construction.
var trait_rank: int = 0

var _rng := RandomNumberGenerator.new()
var _next_id: int = 1
var _first: PackedStringArray = PackedStringArray()
var _nick: PackedStringArray = PackedStringArray()
var _last: PackedStringArray = PackedStringArray()
var _nick_chance: float = 0.35


func _init(p_seed: int = 0, p_slots: int = START_SLOTS) -> void:
	_rng.seed = p_seed
	slots = maxi(p_slots, 1)
	_load_names()
	for i in slots:
		hire()


# --- roster -------------------------------------------------------------------


## Guys who can be fielded tonight.
func available() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in guys:
		if g["state"] == STATE_FREE:
			out.append(g)
	return out


## Guys sitting in holding.
func holding() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in guys:
		if g["state"] == STATE_HOLDING:
			out.append(g)
	return out


func find_by_id(id: int) -> Dictionary:
	for g in guys:
		if int(g["id"]) == id:
			return g
	return {}


## A fresh body: level 0, free, and one trait if the career is past `GuyTraits.MIN_RANK`.
## Never fails — bankruptcy of the roster is impossible by construction (docs/01 §8).
func hire() -> Dictionary:
	var g := {
		"id": _next_id,
		"name": _make_name(),
		"level": 0,
		"pinches": 0,
		"state": STATE_FREE,
		"sit_out": 0,
		"nights": 0,
		"from_raid": false,
		"trait": GuyTraits.pick(_rng, trait_rank),
	}
	_next_id += 1
	guys.append(g)
	return g


# --- Night beats --------------------------------------------------------------


## A drained guy. `from_raid` hands out the longer stretch and the ×3 bail (docs/05 §2).
func pinch(guy: Dictionary, from_raid: bool = false) -> void:
	if guy.is_empty():
		return
	guy["state"] = STATE_HOLDING
	guy["pinches"] = int(guy["pinches"]) + 1
	guy["sit_out"] = SIT_OUT_NIGHTS_RAID if from_raid else SIT_OUT_NIGHTS
	guy["from_raid"] = from_raid


## He made it home: experience ticks up (levels are slow on purpose, docs/01 §4).
func survived_night(guy: Dictionary) -> void:
	if guy.is_empty():
		return
	guy["nights"] = int(guy["nights"]) + 1
	guy["level"] = int(guy["nights"]) / NIGHTS_PER_LEVEL


## Dirty cost to spring him right now. Zero if he is not inside.
func bail_cost(guy: Dictionary, rank: int = 0) -> BigMoney:
	if guy.is_empty() or guy["state"] != STATE_HOLDING:
		return BigMoney.zero()
	var priors := maxi(int(guy["pinches"]) - 1, 0)
	return Rates.bail_cost(int(guy["level"]), priors, bool(guy["from_raid"]), rank)


## Spring him. Returns the cost that was owed (the caller does the paying — this class
## never touches a wallet) or zero if there was nothing to bail.
func bail(guy: Dictionary) -> BigMoney:
	var cost := bail_cost(guy)
	if guy.is_empty() or guy["state"] != STATE_HOLDING:
		return BigMoney.zero()
	guy["state"] = STATE_FREE
	guy["sit_out"] = 0
	guy["from_raid"] = false
	return cost


## Between Nights: holding guys serve a Night, then walk. Tops the roster back up to
## `slots` and guarantees at least one guy is fieldable, so the game never hard-locks.
func night_tick(p_slots: int = -1, p_rank: int = -1) -> void:
	if p_slots > 0:
		slots = p_slots
	if p_rank >= 0:
		trait_rank = p_rank
	for g in guys:
		if g["state"] != STATE_HOLDING:
			continue
		g["sit_out"] = int(g["sit_out"]) - 1
		if int(g["sit_out"]) <= 0:
			g["state"] = STATE_FREE
			g["sit_out"] = 0
			g["from_raid"] = false
	while guys.size() < slots:
		hire()
	if available().is_empty():
		hire()


# --- names --------------------------------------------------------------------


func _load_names() -> void:
	var raw := _read_json(NAMES_PATH)
	if raw.is_empty():
		_first = PackedStringArray(["Nobody"])
		_last = PackedStringArray(["Smith"])
		return
	_first = PackedStringArray(raw.get("first", ["Nobody"]))
	_nick = PackedStringArray(raw.get("nick", []))
	_last = PackedStringArray(raw.get("last", ["Smith"]))
	_nick_chance = float(raw.get("nick_chance", 0.35))


func _make_name() -> String:
	var first := _pick(_first, "Nobody")
	var last := _pick(_last, "Smith")
	if _nick.size() > 0 and _rng.randf() < _nick_chance:
		return "%s \"%s\" %s" % [first, _pick(_nick, "the Guy"), last]
	return "%s %s" % [first, last]


func _pick(pool: PackedStringArray, fallback: String) -> String:
	if pool.is_empty():
		return fallback
	return pool[_rng.randi() % pool.size()]


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	var list: Array = []
	for g in guys:
		list.append(g.duplicate())
	# The RNG state is a uint64: JSON would round-trip it through a double and lose the
	# bottom bits, so it travels as text and comes back exact.
	return {
		"slots": slots,
		"next_id": _next_id,
		"trait_rank": trait_rank,
		"seed": str(_rng.seed),
		"state": str(_rng.state),
		"guys": list,
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	slots = maxi(int(d.get("slots", START_SLOTS)), 1)
	_next_id = maxi(int(d.get("next_id", 1)), 1)
	trait_rank = maxi(int(d.get("trait_rank", 0)), 0)
	_rng.seed = SaveGame.to_i64(d.get("seed", 0), 0)
	_rng.state = SaveGame.to_i64(d.get("state", null), int(_rng.state))
	guys.clear()
	for raw: Variant in d.get("guys", []):
		if raw is Dictionary:
			guys.append(_sanitize(raw as Dictionary))
	if guys.is_empty():
		for i in slots:
			hire()


## Save data is the one input this class does not control; a half-written guy becomes a
## whole one rather than a crash.
func _sanitize(raw: Dictionary) -> Dictionary:
	var state := String(raw.get("state", STATE_FREE))
	if state != STATE_FREE and state != STATE_HOLDING:
		state = STATE_FREE
	return {
		"id": int(raw.get("id", _next_id)),
		"name": String(raw.get("name", "Nobody")),
		"level": maxi(int(raw.get("level", 0)), 0),
		"pinches": maxi(int(raw.get("pinches", 0)), 0),
		"state": state,
		"sit_out": maxi(int(raw.get("sit_out", 0)), 0),
		"nights": maxi(int(raw.get("nights", 0)), 0),
		"from_raid": bool(raw.get("from_raid", false)),
		"trait": String(raw.get("trait", "")),
	}
