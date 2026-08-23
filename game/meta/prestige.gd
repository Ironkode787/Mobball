class_name Prestige
extends RefCounted
## SKIP TOWN (docs/06): the Juice you leave a city with, the Black Book you spend it on, and
## the handful of promises that Book makes to the NEXT city.
##
## This is the only object in the game that outlives a career. A `Stats` is the fold of what
## THIS career bought and dies with it; a `Prestige` is the fold of what every career before
## it earned, and the flow lane carries it across the cutscene and into the save file.
##
## Shape, for the lane that persists it:
##
##     var p := Prestige.shared()                  # one per process
##     var got := p.skip_town(career)              # scores the career, banks the Juice
##     p.buy("blackbook.old_contacts")             # spends it
##     save["prestige"] = p.to_dict()              # {juice, earned, cities, owned}
##     p.from_dict(save.get("prestige", {}))       # on boot
##
## …and then, when the new city opens, the getters below answer "what did the Book buy me":
## `start_rank()`, `kept_specialists()`, `stash_fraction()`, `bench_starters()`,
## `boss_start_phase()`, `pocket_scales_with_city()`, `star_requirement_mult()`. Each one is
## identity — 0, 1, false — for a player who has never skipped town, so every consumer can
## read it unconditionally on the very first career.
##
## Deferred (★) perks are readable through their own getters too, and every one of them is
## identity today: their systems land in M4+, `BlackBook.block_for` refuses to sell them, and
## the board shows them face-down. Nothing has to change here when they come alive.
##
## Pure RefCounted, no autoloads, no Node — it loads under the bare test runner, which is why
## `Prestige` and not `Game` is where the Juice formula lives.

## docs/06 §2: the sqrt is taken on lifetime clean measured in BILLIONS.
const JUICE_CLEAN_UNIT_EXP := 9
## …and every 500 ☆ past the last rank you actually reached is one more point.
const JUICE_RESPECT_PER := 500
## A ceiling, not a balance number. A career at $1e300 clean would score 1e145 Juice, which is
## not an int; a corrupt save should not be able to hand the Black Book infinity either. Ten
## million is ~400,000 completed cities at docs/06's "25–60 a loop".
const JUICE_MAX := 10_000_000

## docs/06 §3 "max R3 start" — Old Contacts cannot seat you higher however many levels of it
## you own, and the Book cannot start you past the ranks that teach the game.
const START_RANK_MAX := 3
## Kept Man is one slot a level; three men is the whole Bench's worth of continuity.
const KEPT_MEN_MAX := 3
## The Stash is 5% in docs/06; the ceiling is where "a head start" would become "the same
## career again", since a city's whole first Night is worth far less than this.
const STASH_FRACTION_MAX := 0.25
## Everybody Knows Somebody seats 2; the Bench itself only has `Stats.BASE_BENCH_SLOTS`.
const BENCH_STARTERS_MAX := 4
## Fast Learner is −20%; no stack of perks may cut a ☆ ladder by more than half, or the rank
## ladder stops being the thing that paces a city.
const STAR_REQUIREMENT_MIN := 0.5
## ★ Double Life / ★ Silent Empire ceilings, held here so the deferred systems inherit a
## sane band the day they land.
const IDLE_CARRYOVER_MAX := 0.25
const SAFE_CLEAN_SHARE_MAX := 0.25
const SAINTS_MAX := 3
## The Golden Ball's home tier when nobody has bought ★ The Golden Era (docs/04 branch C T7).
const GOLDEN_BALL_TIER := 7

static var _shared: Prestige = null

## The Black Book the owned ids are resolved against. Null uses the shipped file; tests inject
## a fixture instead of editing content.
var catalog: BlackBook = null

## Unspent Juice. Never resets — not on Skip Town, not on a new city, not ever (docs/06 §1).
var juice: int = 0
## Every point of Juice this player has ever been paid, spent or not. The Skip Town screen
## reads it ("careers: 3 · Juice earned: 41") and it is the honest denominator for a "how far
## in is this player" question that `juice` alone cannot answer once it is spent.
var juice_earned: int = 0
## Cities left behind. `city_number()` is this plus one, which is the city being played now.
var cities_finished: int = 0

var _owned: Dictionary = {}
## Folded perk buckets, rebuilt from `_owned` by `_recompute()` — same discipline as `Stats`:
## a full rebuild, never an incremental mutation, so load, buy and respec are one code path.
var _sum: Dictionary = {}
var _product: Dictionary = {}
var _max: Dictionary = {}
var _min: Dictionary = {}
var _flags: Dictionary = {}
var _stats_effects: Array[Dictionary] = []


# --- the process-wide Book ----------------------------------------------------


## The prestige state for this process. The flow lane loads it at boot and saves it with the
## career; the Ledger's Black Book page reads it to paint owned perks.
static func shared() -> Prestige:
	if _shared == null:
		_shared = Prestige.new()
	return _shared


static func reset_shared() -> void:
	_shared = null


func _init(from_catalog: BlackBook = null) -> void:
	catalog = from_catalog


# =================================================================== JUICE =====


## docs/06 §2, exactly:
##
##     Juice = floor(sqrt(lifetime_clean / 1e9)) + bosses_beaten + heists_cleared
##             + raids_survived + floor(excess_respect / 500)
##
## `career` is a plain dictionary so the flow lane can assemble it from wherever those tallies
## live without this file reaching into `Game`:
##
##   `lifetime_clean`  — BigMoney, a `{m, e}` dict, a "12.5B" string or a number. Every clean
##                       dollar the career ever EARNED, not the balance it happens to hold:
##                       spending it in the Ledger is playing, and playing must never lower
##                       the Juice a city is worth.
##   `bosses_beaten`   — Commission fights won.
##   `heists_cleared`  — heists completed (docs/05 §5).
##   `raids_survived`  — raids ridden out, busts not included.
##   `excess_respect`  — ☆ earned PAST the threshold of the last rank actually reached, so
##                       the stars that bought a promotion are not paid for twice. `respect`
##                       is accepted as an alias for a career that never ranked.
##
## The sqrt is what keeps grinding sane (doubling wealth is not doubling Juice) and the flat
## adds are what pay for doing things instead of farming. Anything missing counts as zero, so
## a partial career dictionary scores what it can rather than failing.
static func juice_for(career: Dictionary) -> int:
	var b := juice_breakdown(career)
	return int(b["total"])


## The same number with its receipt, for the Skip Town screen (docs/06 §1 wants the player to
## see WHY the number is what it is) and for tests that need to know which term moved.
## Keys: `clean`, `bosses`, `heists`, `raids`, `respect`, `total`.
static func juice_breakdown(career: Dictionary) -> Dictionary:
	var clean := juice_from_clean(_as_money(career.get("lifetime_clean", null)))
	var bosses := _as_count(career.get("bosses_beaten", 0))
	var heists := _as_count(career.get("heists_cleared", 0))
	var raids := _as_count(career.get("raids_survived", 0))
	var stars: int = _as_count(career.get("excess_respect", career.get("respect", 0)))
	var respect := stars / JUICE_RESPECT_PER
	var total := clampi(clean + bosses + heists + raids + respect, 0, JUICE_MAX)
	return {
		"clean": clean,
		"bosses": bosses,
		"heists": heists,
		"raids": raids,
		"respect": respect,
		"total": total,
	}


## `floor(sqrt(lifetime_clean / 1e9))`, done in BigMoney's own mantissa/exponent space so a
## career at $1e40 is arithmetic rather than an overflow: sqrt(m × 10^e) is sqrt(m) × 10^(e/2),
## and an odd exponent borrows one order from the mantissa first.
##
## Precision: the mantissa is a float64, so past ~15 digits the floor is the nearest float's
## floor. A player who has earned 10^15 Juice has other problems.
static func juice_from_clean(lifetime_clean: BigMoney) -> int:
	if lifetime_clean == null or not lifetime_clean.is_positive():
		return 0
	var m := lifetime_clean.m
	var e := lifetime_clean.e - JUICE_CLEAN_UNIT_EXP
	if e % 2 != 0:
		# Godot's % keeps the sign of the dividend, so this handles negative exponents too.
		m *= 10.0
		e -= 1
	var root_m := sqrt(m)
	var root_e := e / 2
	if root_e >= 16:
		# Past a float64's exact-integer range there is nothing left to floor precisely, and
		# the answer is "more Juice than the Book can spend" either way.
		return JUICE_MAX
	# A negative exponent lands here too: under a billion of lifetime clean the root is less
	# than 1, and flooring it is how docs/06 §2 says the first city pays nothing for wealth.
	return clampi(int(floorf(root_m * pow(10.0, float(root_e)))), 0, JUICE_MAX)


# --- the wallet ---------------------------------------------------------------


## Pays Juice in. Negative and zero are ignored — Juice is never taken away (docs/06 §1),
## and the only thing that lowers `juice` is buying something with it.
func award(amount: int) -> int:
	if amount <= 0:
		return 0
	var paid := mini(amount, JUICE_MAX - juice_earned)
	if paid <= 0:
		return 0
	juice += paid
	juice_earned += paid
	return paid


## THE prestige act. Scores the career per docs/06 §2, banks the Juice, and counts the city
## as left behind. Returns what it paid, so the cutscene can count it up on screen.
##
## What a career KEEPS is this object; what it loses is everything else, and dropping it is
## the flow lane's job (docs/06 §1: cash, table, ranks, Respect, the Bench except one guy).
func skip_town(career: Dictionary) -> int:
	var paid := award(juice_for(career))
	cities_finished += 1
	return paid


## Which city is being played now: 1 before the first Skip Town, 2 after it, and so on.
## ★ Traveling Light scales Pocket Money by this number.
func city_number() -> int:
	return cities_finished + 1


# --- the Black Book -----------------------------------------------------------


func level_of(id: String) -> int:
	return int(_owned.get(id, 0))


func has(id: String) -> bool:
	return level_of(id) >= 1


## A copy of the owned map — perk id -> level. The save file takes this whole.
func owned() -> Dictionary:
	return _owned.duplicate()


## Replaces the whole owned map (a save load). Non-positive levels, unknown ids and levels
## past a perk's max are dropped, so a hand-edited save cannot promise what the Book does not
## sell. Deferred perks are dropped too: they were never buyable, so owning one is corruption.
func set_owned(map: Dictionary) -> void:
	_owned.clear()
	if map != null:
		var cat := _catalog()
		for id: Variant in map:
			if not (id is String):
				continue
			var level := int(map[id])
			if level < 1 or not cat.has_id(String(id)) or cat.is_deferred(String(id)):
				continue
			_owned[String(id)] = mini(level, cat.max_level(String(id)))
	_recompute()


func block_for(id: String) -> BlackBook.Block:
	return _catalog().block_for(id, _owned, juice)


func can_buy(id: String) -> bool:
	return block_for(id) == BlackBook.Block.NONE


## Buys one level of a perk with Juice. Returns the new level, or 0 if nothing was bought —
## and when it returns 0, no Juice moved.
func buy(id: String) -> int:
	if not can_buy(id):
		return 0
	var cost := _catalog().next_cost(id, _owned)
	if cost > juice:
		return 0
	juice -= cost
	var level := level_of(id) + 1
	_owned[id] = level
	_recompute()
	return level


## What the next level of a perk costs right now.
func cost_of(id: String) -> int:
	return _catalog().next_cost(id, _owned)


# --- what the Book bought (live perks) ----------------------------------------
# Every getter here is read ONCE, by the lane named, at the moment a city opens. None of them
# folds into `Stats`: a perk is a promise about the career you are starting, not a number on
# the table you are playing.


## Rank the next city starts at (Old Contacts ↻). 0 = the bare alley, as it always was.
## Read by the flow lane when it begins a city.
func start_rank() -> int:
	return clampi(_sum_of(&"start_rank"), 0, START_RANK_MAX)


## How many specialists may be carried through Skip Town (Kept Man ↻). The flow lane offers
## the player exactly this many names to keep.
func kept_specialists() -> int:
	return clampi(_sum_of(&"kept_specialist"), 0, KEPT_MEN_MAX)


## Traveling Light: Pocket Money multiplies by `city_number()`. The flow lane applies it where
## it reads `Stats.pocket_money()` at The Count.
func pocket_scales_with_city() -> bool:
	return _flags.has(&"pocket_city_scale")


## Pocket Money multiplier for the city being played — 1.0 without the perk, and exactly the
## city number with it. Here rather than in the caller so "scales with city #" has one meaning.
func pocket_money_mult() -> float:
	return float(city_number()) if pocket_scales_with_city() else 1.0


## Fraction of the last city's CLEAN cash that arrives (as dirty) in the new one — The Stash.
func stash_fraction() -> float:
	return minf(_sum_of_f(&"stash_fraction"), STASH_FRACTION_MAX)


## Guys already on the Bench when a city opens — Everybody Knows Somebody.
func bench_starters() -> int:
	return clampi(_sum_of(&"bench_starters"), 0, BENCH_STARTERS_MAX)


## Phase the city's FIRST Commission fight opens at — Reputation Precedes You. 1 is a fight
## that starts at the beginning, which is what every fight does today.
func boss_start_phase() -> int:
	return maxi(_max_of(&"boss_start_phase", 1), 1)


## Multiplier on a rank's ☆ requirement in a city this player has already beaten — Fast
## Learner. 1.0 for a first visit, or with the perk unbought.
func star_requirement_mult() -> float:
	return maxf(_product_of(&"star_requirement_mult"), STAR_REQUIREMENT_MIN)


# --- what the Book will buy (★ deferred perks) --------------------------------
# The systems behind these land in M4+. They are all identity today and none of them can be
# bought yet (`BlackBook.block_for` returns DEFERRED), so a consumer written now still works.


## ★ Double Life — the previous city's idle rate that keeps paying, as a fraction.
func idle_carryover() -> float:
	return minf(_sum_of_f(&"idle_carryover"), IDLE_CARRYOVER_MAX)


## ★ The Big Sleep — how many retired specialists stand as aura statues on future tables.
func saint_statues() -> int:
	return clampi(_sum_of(&"saint_statue"), 0, SAINTS_MAX)


## ★ Museum of Crime — the relic gallery and its set bonuses are open.
func museum_unlocked() -> bool:
	return _flags.has(&"museum")


## ★ The Golden Era — the tier the Golden Ball unlocks at, T7 without it.
func golden_ball_tier() -> int:
	return _min_of(&"golden_ball_tier", GOLDEN_BALL_TIER)


## ★ Silent Empire — offline Safe cap multiplier (1.0 without it)…
func safe_cap_mult() -> float:
	return maxf(_product_of(&"safe_cap_mult"), 1.0)


## …and the fraction of the Safe that arrives already clean.
func safe_clean_share() -> float:
	return minf(_sum_of_f(&"safe_clean_share"), SAFE_CLEAN_SHARE_MAX)


## ★ The Sixth Family — the five-Commission gauntlet table.
func gauntlet_unlocked() -> bool:
	return _flags.has(&"gauntlet")


# --- perks that speak the Ledger's vocabulary ---------------------------------


## Owned perk effects that name a LEDGER kind (`Upgrades.EFFECT_SPECS`) rather than a perk
## kind, normalized and already folded to their owned level — the exact shape `Stats._apply`
## consumes. Nothing in the shipped Black Book uses one; the door is open so a future
## "all idle rates +25%, forever" perk is a data commit instead of a new kind, and so the
## flow lane has one place to ask "does the Book change the table itself?".
func stats_effects() -> Array[Dictionary]:
	return _stats_effects.duplicate(true)


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	return {
		"juice": juice,
		"earned": juice_earned,
		"cities": cities_finished,
		"owned": _owned.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	juice = 0
	juice_earned = 0
	cities_finished = 0
	_owned.clear()
	_recompute()
	if d == null or d.is_empty():
		return
	juice = clampi(int(d.get("juice", 0)), 0, JUICE_MAX)
	juice_earned = clampi(int(d.get("earned", juice)), juice, JUICE_MAX)
	cities_finished = maxi(int(d.get("cities", 0)), 0)
	var raw: Variant = d.get("owned", {})
	if raw is Dictionary:
		set_owned(raw as Dictionary)


# --- internals ----------------------------------------------------------------


func _catalog() -> BlackBook:
	return catalog if catalog != null else BlackBook.shared()


## Full rebuild of every bucket from the owned map (see `Stats.recompute` — same contract).
func _recompute() -> void:
	_sum.clear()
	_product.clear()
	_max.clear()
	_min.clear()
	_flags.clear()
	_stats_effects.clear()
	var cat := _catalog()
	for id: Variant in _owned:
		var level := int(_owned[id])
		if level < 1:
			continue
		var perk := cat.def(String(id))
		if perk.is_empty():
			continue
		level = mini(level, int(perk["max_level"]))
		var effects: Array = perk["effects"]
		for e: Variant in effects:
			var effect := e as Dictionary
			var kind: StringName = effect["kind"]
			if not bool(effect.get("perk_kind", false)):
				# A Ledger kind riding in a perk: folded by whoever applies it, not here.
				_stats_effects.append(_at_level(effect, level))
				continue
			var value := Stats.scaled_value(effect, level)
			match BlackBook.fold_of(kind):
				Stats.Fold.SUM:
					_sum[kind] = float(_sum.get(kind, 0.0)) + value
				Stats.Fold.PRODUCT:
					_product[kind] = float(_product.get(kind, 1.0)) * value
				Stats.Fold.MAX:
					_max[kind] = maxf(float(_max.get(kind, value)), value)
				Stats.Fold.MIN:
					_min[kind] = minf(float(_min.get(kind, value)), value)
				_:
					_flags[kind] = true


## An effect with its level already folded in and `per_level` spent — so a consumer of
## `stats_effects()` applies it once, at level 1, whatever level bought it.
static func _at_level(effect: Dictionary, level: int) -> Dictionary:
	var out := effect.duplicate()
	out["num"] = Stats.scaled_value(effect, level)
	out["money"] = Stats.scaled_money(effect, level)
	out["per_level"] = false
	return out


func _sum_of(kind: StringName) -> int:
	return int(roundf(float(_sum.get(kind, 0.0))))


func _sum_of_f(kind: StringName) -> float:
	return float(_sum.get(kind, 0.0))


func _product_of(kind: StringName) -> float:
	return float(_product.get(kind, 1.0))


func _max_of(kind: StringName, fallback: int) -> int:
	return int(roundf(float(_max.get(kind, float(fallback)))))


func _min_of(kind: StringName, fallback: int) -> int:
	return int(roundf(float(_min.get(kind, float(fallback)))))


## Money, a count or a string, whichever the career dictionary happens to carry.
static func _as_money(raw: Variant) -> BigMoney:
	if raw is BigMoney:
		return raw as BigMoney
	if raw is Dictionary:
		return BigMoney.from_dict(raw as Dictionary)
	if raw is String:
		return BigMoney.parse(raw as String)
	if raw is float or raw is int:
		return BigMoney.from_float(float(raw))
	return BigMoney.zero()


## A tally that must be a whole, non-negative count however the save wrote it.
static func _as_count(raw: Variant) -> int:
	if raw is bool:
		return 1 if raw else 0
	if not (raw is float or raw is int):
		return 0
	var v := float(raw)
	if not is_finite(v) or v <= 0.0:
		return 0
	return int(minf(v, float(JUICE_MAX)))
