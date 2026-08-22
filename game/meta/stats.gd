class_name Stats
extends RefCounted
## CONTRACT (specs/m1-hook.md): the pure recompute of everything the Ledger has bought.
## The public API is LAW — gameplay and table code compile against it.
##
## `recompute(owned)` is a full rebuild from the owned map, never an incremental mutation,
## so save/load, respec and "what would this look like at level 7" are all the same code
## path. Everything below the API is a folded bucket filled by that one pass.
##
## How the effects fold (specs/ledger-data.md):
##   * value_mult / flipper_power_mult / collect_minutes_mult — multiplicative; a per_level
##     effect contributes value^level.
##   * value_add / idle_rate_add / launder_cap_add / launder_rate_add / passive_wash_add /
##     bench_slot_add / tilt_leans_add / ball_save_charges — additive; a per_level effect
##     contributes value × level.
##   * safe_hours_set / pocket_money_set / job_slots_set — the highest owned wins (they are
##     tiers, not stacks); per_level scales the value by level first.
##   * unlock_hardware / feature_flag / kickback_unlock / bribe_unlock — unions.
##
## RefCounted, no Node, and no autoload reference at parse time (Feel/Game/Events are not
## guaranteed to exist wherever this loads) — that is why the base numbers below are
## literals with their source named instead of `Feel.X` lookups.

## Mirrors Feel.TILT_MAX_WARNINGS.
const BASE_TILT_LEANS := 3
## docs/01 §4: the Bench opens with four guys.
const BASE_BENCH_SLOTS := 4
## docs/05 §1: two job slips until Paper Route.
const BASE_JOB_SLOTS := 2
## specs/m1-hook.md Lane 3: a storefront collect pays `collect_minutes` of its idle rate.
const BASE_COLLECT_MINUTES := 5.0

## Catalog the owned ids are resolved against. Null uses the shipped file; tests inject
## their own fixture instead of editing content.
var catalog: Upgrades = null

var _owned: Dictionary = {}
var _value_mult: Dictionary = {}
var _value_add: Dictionary = {}
var _hardware: Dictionary = {}
var _flags: Dictionary = {}
var _kickbacks: Dictionary = {}
var _idle_total: BigMoney = BigMoney.zero()
var _launder_cap: BigMoney = BigMoney.zero()
var _pocket: BigMoney = Rates.pocket_money_per_night()
var _launder_rate: float = 0.0
var _passive_wash: float = 0.0
var _safe_hours: float = Rates.SAFE_CAP_HOURS_BASE
var _flipper_power: float = 1.0
var _collect_minutes: float = BASE_COLLECT_MINUTES
var _bench_slots: int = BASE_BENCH_SLOTS
var _tilt_leans: int = BASE_TILT_LEANS
var _job_slots: int = BASE_JOB_SLOTS
var _ball_saves: int = 0
var _bribe: bool = false


## owned: node id (String) -> level (int, >= 1). Recompute is a full rebuild, never
## incremental, so save/load and respec stay trivial.
func recompute(owned: Dictionary) -> void:
	_owned = owned.duplicate()
	_reset()
	var cat := _catalog()
	for id: Variant in _owned:
		var level := int(_owned[id])
		if level < 1:
			continue
		var node := cat.def(String(id))
		if node.is_empty():
			# Unknown id: a renamed or removed node in an old save. Skipping keeps the
			# save loadable; the Ledger is the place that reports content problems.
			continue
		level = mini(level, int(node["max_level"]))
		var effects: Array = node["effects"]
		for effect: Variant in effects:
			_apply(effect, level)


func owned_level(id: String) -> int:
	return int(_owned.get(id, 0))


## Group multiplier including the `all` fold — `value_mult(&"all")` is the fold itself,
## so asking for it does not multiply it in twice.
func value_mult(group: StringName) -> float:
	var g := float(_value_mult.get(group, 1.0))
	if group == &"all":
		return g
	return g * float(_value_mult.get(&"all", 1.0))


func value_add(group: StringName) -> BigMoney:
	var all: BigMoney = _value_add.get(&"all", null)
	var own: BigMoney = _value_add.get(group, null)
	if group == &"all":
		return all.copy() if all != null else BigMoney.zero()
	if own == null:
		return all.copy() if all != null else BigMoney.zero()
	return own.add(all) if all != null else own.copy()


func hardware_unlocked(id: StringName) -> bool:
	return _hardware.has(id)


func flag(id: StringName) -> bool:
	return _flags.has(id)


func idle_rate_total() -> BigMoney:
	return _idle_total.copy()


## Fraction of held dirty washed per laundromat-loop pass, capped by docs/03 §2.
func launder_rate() -> float:
	return minf(_launder_rate, Rates.LAUNDER_LOOP_FRACTION_MAX)


func launder_cap() -> BigMoney:
	return _launder_cap.copy()


func passive_wash_per_sec() -> float:
	return _passive_wash


func pocket_money() -> BigMoney:
	return _pocket.copy()


func safe_hours() -> float:
	return _safe_hours


func bench_slots() -> int:
	return _bench_slots


func ball_saves() -> int:
	return _ball_saves


func tilt_leans() -> int:
	return _tilt_leans


func flipper_power() -> float:
	return _flipper_power


func collect_minutes() -> float:
	return _collect_minutes


func job_slots() -> int:
	return _job_slots


func kickbacks() -> Array[StringName]:
	var out: Array[StringName] = []
	for side: StringName in [&"left", &"right"]:
		if _kickbacks.has(side):
			out.append(side)
	return out


func bribe_unlocked() -> bool:
	return _bribe


# --- internals ----------------------------------------------------------------


func _catalog() -> Upgrades:
	return catalog if catalog != null else Upgrades.shared()


func _reset() -> void:
	_value_mult.clear()
	_value_add.clear()
	_hardware.clear()
	_flags.clear()
	_kickbacks.clear()
	_idle_total = BigMoney.zero()
	_launder_cap = BigMoney.zero()
	_pocket = Rates.pocket_money_per_night()
	_launder_rate = 0.0
	_passive_wash = 0.0
	_safe_hours = Rates.SAFE_CAP_HOURS_BASE
	_flipper_power = 1.0
	_collect_minutes = BASE_COLLECT_MINUTES
	_bench_slots = BASE_BENCH_SLOTS
	_tilt_leans = BASE_TILT_LEANS
	_job_slots = BASE_JOB_SLOTS
	_ball_saves = 0
	_bribe = false


func _apply(effect: Dictionary, level: int) -> void:
	var kind: StringName = effect["kind"]
	var target: StringName = effect["target"]
	match kind:
		&"unlock_hardware":
			_hardware[target] = true
		&"feature_flag":
			_flags[target] = true
		&"value_mult":
			_value_mult[target] = float(_value_mult.get(target, 1.0)) * _scaled_mult(effect, level)
		&"value_add":
			var add: BigMoney = _value_add.get(target, null)
			var v := _scaled_money(effect, level)
			_value_add[target] = v if add == null else add.add(v)
		&"idle_rate_add":
			_idle_total = _idle_total.add(_scaled_money(effect, level))
		&"launder_rate_add":
			_launder_rate += _scaled_num(effect, level)
		&"launder_cap_add":
			_launder_cap = _launder_cap.add(_scaled_money(effect, level))
		&"pocket_money_set":
			_pocket = BigMoney.max_of(_pocket, _scaled_money(effect, level))
		&"passive_wash_add":
			_passive_wash += _scaled_num(effect, level)
		&"safe_hours_set":
			_safe_hours = maxf(_safe_hours, _scaled_num(effect, level))
		&"bench_slot_add":
			_bench_slots += int(_scaled_num(effect, level))
		&"ball_save_charges":
			_ball_saves += int(_scaled_num(effect, level))
		&"tilt_leans_add":
			_tilt_leans += int(_scaled_num(effect, level))
		&"flipper_power_mult":
			_flipper_power *= _scaled_mult(effect, level)
		&"kickback_unlock":
			_kickbacks[target] = true
			# The table shows an outlane kicker by hardware id (specs/m1-hook.md); the
			# content vocabulary unlocks it by side, so this is the bridge between them.
			_hardware[StringName("kickback_" + String(target))] = true
		&"bribe_unlock":
			_bribe = true
			_hardware[&"bribe_target"] = true
		&"job_slots_set":
			_job_slots = maxi(_job_slots, int(_scaled_num(effect, level)))
		&"collect_minutes_mult":
			_collect_minutes *= _scaled_mult(effect, level)


## Additive/`set` effects scale linearly with level; +4h of safe at level 2 is 8h.
func _scaled_num(effect: Dictionary, level: int) -> float:
	var v := float(effect["num"])
	return v * float(level) if bool(effect["per_level"]) else v


## Multiplicative effects compound: +25%/level at level 3 is 1.25^3, not 3.75.
func _scaled_mult(effect: Dictionary, level: int) -> float:
	var v := float(effect["num"])
	return pow(v, float(level)) if bool(effect["per_level"]) else v


func _scaled_money(effect: Dictionary, level: int) -> BigMoney:
	var v: BigMoney = effect["money"]
	return v.mul(float(level)) if bool(effect["per_level"]) else v.copy()
