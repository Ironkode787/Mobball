class_name Stats
extends RefCounted
## CONTRACT (specs/m1-hook.md): the pure recompute of everything the Ledger has bought.
## This stub returns baseline defaults; the meta workstream owns the real implementation.
## The API below is LAW — gameplay and table code compile against it.

var _owned: Dictionary = {}


## owned: node id (String) -> level (int, >= 1). Recompute is a full rebuild, never
## incremental, so save/load and respec stay trivial.
func recompute(owned: Dictionary) -> void:
	_owned = owned.duplicate()


func owned_level(id: String) -> int:
	return int(_owned.get(id, 0))


func value_mult(_group: StringName) -> float:
	return 1.0


func value_add(_group: StringName) -> BigMoney:
	return BigMoney.zero()


func hardware_unlocked(_id: StringName) -> bool:
	return false


func flag(_id: StringName) -> bool:
	return false


func idle_rate_total() -> BigMoney:
	return BigMoney.zero()


func launder_rate() -> float:
	return 0.0


func launder_cap() -> BigMoney:
	return BigMoney.zero()


func passive_wash_per_sec() -> float:
	return 0.0


func pocket_money() -> BigMoney:
	return Rates.pocket_money_per_night()


func safe_hours() -> float:
	return 2.0


func bench_slots() -> int:
	return 4


func ball_saves() -> int:
	return 0


## Base 3 mirrors Feel.TILT_MAX_WARNINGS — kept literal here so this RefCounted stays
## loadable under the bare test runner, where autoload singletons do not exist.
func tilt_leans() -> int:
	return 3


func flipper_power() -> float:
	return 1.0


func collect_minutes() -> float:
	return 5.0


func job_slots() -> int:
	return 2


func kickbacks() -> Array[StringName]:
	return []


func bribe_unlocked() -> bool:
	return false
