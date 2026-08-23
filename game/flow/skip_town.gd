class_name SkipTown
extends RefCounted
## SKIP TOWN (docs/06 §1–2). The prestige act, from the flow lane's side: what a career is
## worth on the way out, what gets on the train with you, and what the new city starts with.
##
## The scoring itself belongs to the meta lane (`game/meta/prestige.gd` — Juice, the Black
## Book, what the perks promise). This file is the doorway to it: it is loaded BY PATH and
## every call is guarded, so a flow lane booting without the meta lane still runs the act
## with the formula out of docs/06 §2 rather than refusing to leave town.
##
## What you keep (docs/06 §1): Juice, the Black Book, Museum relics, boss spoils as
## re-earnable "old friends", cosmetics, rap-sheet stats — and **one guy**, whom you name.
## What you lose: cash both colours, the table, rank and Respect, the rest of the Bench, the
## Heat, and every Ledger node you ever bought.

const PRESTIGE_PATH := "res://game/meta/prestige.gd"

## Rank the act is offered from (docs/06 §1). It is also offered after a failed RICO raid,
## which is the only time this game suggests anything.
const RANK := 7
## docs/06 §2 — the fallback formula, used only when the meta lane is not there to score it.
## TODO(META-3): delete this branch once `Prestige` is a hard dependency of the flow lane.
const JUICE_CLEAN_UNIT_EXP := 9
const JUICE_RESPECT_PER := 500


## The meta lane's Prestige singleton, or null. Loaded by path for the same reason
## `LedgerState` is: a missing meta lane costs the Black Book, never the boot.
static func prestige() -> Object:
	if not ResourceLoader.exists(PRESTIGE_PATH):
		return null
	var script: GDScript = load(PRESTIGE_PATH)
	if script == null or not script.has_method("shared"):
		return null
	return script.call("shared")


## What this career is worth in Juice. Prefers the meta lane's own scoring — it owns the
## formula, the caps and the breakdown the screen shows — and falls back to docs/06 §2.
static func juice_for(career: Dictionary) -> int:
	var p := prestige()
	if p != null and p.get_script() != null and p.get_script().has_method("juice_for"):
		return int(p.get_script().call("juice_for", career))
	return _fallback_juice(career)


## The receipt, when the meta lane can produce one. Without it the total is all there is.
static func breakdown(career: Dictionary) -> Dictionary:
	var p := prestige()
	if p != null and p.get_script() != null and p.get_script().has_method("juice_breakdown"):
		var d: Variant = p.get_script().call("juice_breakdown", career)
		if d is Dictionary:
			return d
	return {"total": _fallback_juice(career)}


## docs/06 §2, verbatim, in doubles. Good to about 15 digits of lifetime clean, which is
## further than a career gets before the meta lane lands.
static func _fallback_juice(career: Dictionary) -> int:
	var clean: Variant = career.get("lifetime_clean", null)
	var wealth := 0
	if clean is BigMoney and (clean as BigMoney).is_positive():
		var unit := BigMoney.of(1.0, JUICE_CLEAN_UNIT_EXP)
		wealth = int(floorf(sqrt(maxf((clean as BigMoney).ratio_to(unit), 0.0))))
	return maxi(wealth
			+ int(career.get("bosses_beaten", 0))
			+ int(career.get("heists_cleared", 0))
			+ int(career.get("raids_survived", 0))
			+ int(career.get("excess_respect", career.get("respect", 0))) / JUICE_RESPECT_PER,
			0)


# ================================================================ the Black Book =====
##
## Perks are read ONCE, here, at the moment a city begins — that is the whole reason they are
## not `Stats` effects (see the header of game/meta/blackbook.gd). Every getter is optional.


static func _perk(name: String, fallback: Variant) -> Variant:
	var p := prestige()
	if p == null or not p.has_method(name):
		return fallback
	var v: Variant = p.call(name)
	return fallback if v == null else v


## ★ Old Contacts: the new city starts you at this rank instead of nothing.
static func start_rank() -> int:
	return maxi(int(_perk("start_rank", 0)), 0)


## ★ Everybody Knows Somebody: leveled guys already on the new Bench.
static func bench_starters() -> int:
	return maxi(int(_perk("bench_starters", 0)), 0)


## ★ The Stash: this much of the city you left, carried as dirty into the next one.
static func stash_fraction() -> float:
	return maxf(float(_perk("stash_fraction", 0.0)), 0.0)


## Which city this is: 1 before the first Skip Town.
static func city_number() -> int:
	return maxi(int(_perk("city_number", 1)), 1)


## Bank the Juice and count the city as left behind. Returns what it paid.
static func award(career: Dictionary) -> int:
	var p := prestige()
	if p != null and p.has_method("skip_town"):
		return int(p.call("skip_town", career))
	return juice_for(career)


# ==================================================================== the farewell =====


## docs/08 §1 — the band packs up, one player at a time, and a train takes the city away.
## Returns the sequence's length in seconds so a screen can time itself against it.
##
## The audio lane owns the scripted version (`play_farewell`). Without it this still sheds
## the stack, just bluntly: the level goes to zero and the last thing you hear is the train.
static func play_farewell() -> float:
	if AudioDirector.has_method("play_farewell"):
		var seconds: Variant = AudioDirector.call("play_farewell")
		if seconds is float and (seconds as float) > 0.0:
			return seconds
	AudioDirector.music_set_level(0)
	AudioDirector.play(&"skip_town")
	AudioDirector.play(&"train_away")
	return 0.0
