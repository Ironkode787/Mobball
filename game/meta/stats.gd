class_name Stats
extends RefCounted
## CONTRACT (specs/m1-hook.md): the pure recompute of everything the Ledger has bought.
## The public API is LAW — gameplay and table code compile against it.
##
## `recompute(owned)` is a full rebuild from the owned map, never an incremental mutation,
## so save/load, respec and "what would this look like at level 7" are all the same code
## path. Everything below the API is a folded bucket filled by that one pass.
##
## How the effects fold (specs/ledger-data.md, specs/m2-content.md §2) — the `FOLD` table
## below is the machine-readable copy of this list, and the Ledger docket reads the same
## table to preview a level, so the two can never drift:
##   * PRODUCT — value_mult / flipper_power_mult / collect_minutes_mult / heat_decay_mult /
##     job_respect_mult / serve_speed_mult / kickback_cooldown_mult / launder_cap_mult /
##     all_dirty_mult (which lands in the `all` value_mult bucket); a per_level effect
##     contributes value^level.
##   * SUM — value_add / idle_rate_add / launder_cap_add / launder_rate_add /
##     passive_wash_add / bench_slot_add / tilt_leans_add / ball_save_charges /
##     bail_discount / casino_edge_add / casino_pocket_add / job_reroll_add /
##     auto_launder_per_sec / clean_share; a per_level effect contributes value × level.
##   * MAX — safe_hours_set / pocket_money_set / job_slots_set / aim_line: the highest owned
##     wins (they are tiers, not stacks); per_level scales the value by level first.
##   * MIN — auto_collect_interval: the shortest owned wins, and 0 means nobody is collecting.
##     per_level DIVIDES by level, which is the mirror of MAX and reads as "one more award
##     collected in the same window": 45 s at level 3 is one every 15 s.
##   * UNION — unlock_hardware / feature_flag / kickback_unlock / bribe_unlock.
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

## Cohen can talk the bondsman down, never to nothing (docs/04 branch D).
const BAIL_DISCOUNT_MAX := 0.6
## docs/03 §3 and specs/m2-content.md §1: influence buys the edge, never the outcome. The
## opening bid is a −7.5% house edge and every point is worth 5/8 of itself, so this is the
## whole distance from −7.5% to exactly +5.0% — and it is exactly what full investment owns
## (Eddie Odds ×12 + Loaded Dice ×8, at a point each). Balance-sim ruling: the casino's entire
## edge is bought here, in payout, one legible line.
const CASINO_EDGE_MAX := 0.20
## The wheel as built: five of its eight pockets pay (game/table/hardware/roulette_wheel.gd,
## Casino.CasinoRules.PLAYER_POCKETS). The ceiling is the base for now — a whole pocket is a
## +18.5% jump in EV against a payout point's +0.625%, so no shipped node may buy one. The
## `casino_pocket_add` kind and the getter below stay in the vocabulary for the content that
## raises this line deliberately; the house always keeps at least one pocket either way.
const CASINO_POCKETS_BASE := 5
const CASINO_POCKETS_MAX := 5

## The most of every dirty payout that may arrive already clean (`clean_share`). A quarter is
## the ceiling on purpose: past it the Night stops being "earn dirty, then decide when and how
## to wash it" and becomes a straight clean faucet, which is the one shape docs/03 §2 refuses.
## The share is still drawn against the per-Night wash cap, so this is a convenience ceiling
## on top of a volume ceiling, not a way around it.
const CLEAN_SHARE_MAX := 0.25

## Which bucket an effect kind folds into. Public because the Ledger docket previews a level
## with `scaled_value` and must use the engine's own shape, not a second copy of it.
enum Fold { PRODUCT, SUM, MAX, MIN, UNION }

const FOLD := {
	&"unlock_hardware": Fold.UNION,
	&"feature_flag": Fold.UNION,
	&"kickback_unlock": Fold.UNION,
	&"bribe_unlock": Fold.UNION,
	&"value_mult": Fold.PRODUCT,
	&"flipper_power_mult": Fold.PRODUCT,
	&"collect_minutes_mult": Fold.PRODUCT,
	&"heat_decay_mult": Fold.PRODUCT,
	&"job_respect_mult": Fold.PRODUCT,
	&"serve_speed_mult": Fold.PRODUCT,
	&"kickback_cooldown_mult": Fold.PRODUCT,
	&"launder_cap_mult": Fold.PRODUCT,
	&"all_dirty_mult": Fold.PRODUCT,
	&"value_add": Fold.SUM,
	&"idle_rate_add": Fold.SUM,
	&"launder_rate_add": Fold.SUM,
	&"launder_cap_add": Fold.SUM,
	&"passive_wash_add": Fold.SUM,
	&"bench_slot_add": Fold.SUM,
	&"ball_save_charges": Fold.SUM,
	&"tilt_leans_add": Fold.SUM,
	&"bail_discount": Fold.SUM,
	&"casino_edge_add": Fold.SUM,
	&"casino_pocket_add": Fold.SUM,
	&"job_reroll_add": Fold.SUM,
	&"auto_launder_per_sec": Fold.SUM,
	&"clean_share": Fold.SUM,
	&"pocket_money_set": Fold.MAX,
	&"safe_hours_set": Fold.MAX,
	&"job_slots_set": Fold.MAX,
	&"aim_line": Fold.MAX,
	&"auto_collect_interval": Fold.MIN,
}

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
var _heat_decay: float = 1.0
var _bail_discount: float = 0.0
var _auto_collect: float = 0.0
var _casino_edge: float = 0.0
var _casino_pockets: int = 0
var _job_respect: float = 1.0
var _serve_speed: float = 1.0
var _auto_launder: float = 0.0
var _kickback_cooldown: float = 1.0
var _job_rerolls: int = 0
var _aim_line: int = 0
var _launder_cap_mult: float = 1.0
var _clean_share: float = 0.0


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


## The per-Night wash cap (docs/03 §2): everything `launder_cap_add` bought, times everything
## `launder_cap_mult` bought. The multiplier is inside this getter deliberately — every caller
## that already asks "how much may I wash tonight" gets the whole answer, and nobody has to
## remember to multiply. `launder_cap_mult()` below exposes the second half on its own, for
## the docket line and the balance report.
func launder_cap() -> BigMoney:
	if is_equal_approx(_launder_cap_mult, 1.0):
		return _launder_cap.copy()
	return _launder_cap.mul(_launder_cap_mult)


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


# --- M2 specialist powers (specs/m2-content.md §2) ----------------------------
# Appended, never edited: the M1 surface above is what the flow and table lanes compile
# against. Every one of these is identity when nobody is hired — a career with no crew must
# behave exactly like the M1 build.


## Multiplies the Heat decay rate: 1.0 is the docs/03 baseline, 1.2 cools 20% faster.
func heat_decay_mult() -> float:
	return _heat_decay


## Fraction knocked off a bail bill, capped so the bondsman always gets paid something.
func bail_discount() -> float:
	return minf(_bail_discount, BAIL_DISCOUNT_MAX)


## Seconds between free collections of one lit award. 0 = nobody is on it; the shortest
## interval owned wins, so hiring a faster fixer never makes the slower one the answer.
func auto_collect_interval() -> float:
	return _auto_collect


## Points of casino edge handed back to the player, capped (docs/03 §3: influence buys the
## odds, never the outcome).
func casino_edge_add() -> float:
	return minf(_casino_edge, CASINO_EDGE_MAX)


## How many of the wheel's eight pockets pay the player. Loaded Dice's pocket half
## (specs/m2-content.md §1 "Open vocabulary item") — capped so the house always keeps one.
func casino_player_pockets() -> int:
	return clampi(CASINO_POCKETS_BASE + _casino_pockets, 1, CASINO_POCKETS_MAX)


## Extra Job rerolls a Night.
func job_rerolls() -> int:
	return _job_rerolls


## Multiplies Respect paid by a completed Job.
func job_respect_mult() -> float:
	return _job_respect


## Ball service/respawn speed: the table divides its serve duration by this.
func serve_speed_mult() -> float:
	return _serve_speed


## Fraction of held dirty that launders itself per second, no loop pass required.
func auto_launder_per_sec() -> float:
	return _auto_launder


## Multiplies outlane kickback cooldown — a discount, so it runs 1.0 down toward 0.
func kickback_cooldown_mult() -> float:
	return _kickback_cooldown


## Case-the-Joint ghost aim line: 0 = none, higher = longer and steadier.
func aim_line_level() -> int:
	return _aim_line


## The hired crew as descriptors (see `Upgrades.specialists`), for the flow and audio lanes.
func specialists() -> Array[Dictionary]:
	return _catalog().specialists(_owned)


# --- M3 laundering structure (the SIM-2 findings) -----------------------------
# Appended, never edited, same rule as the M2 block above. Both are identity on a career
# that has bought neither, so every consumer can apply them unconditionally.


## How much the per-Night wash cap has been MULTIPLIED — 1.0 when nothing bought it.
##
## `launder_cap()` already includes this; the getter exists so the docket can print the two
## halves of the cap separately ("$40M base, ×3.4") and so the balance sim can attribute a
## cap that outgrew its adds. SIM-2 measured the additive cap binding on 107 of 107 late
## Nights, which is what an additive cap does against multiplicative income.
func launder_cap_mult() -> float:
	return _launder_cap_mult


## Fraction of every dirty payout that arrives CLEAN instead of dirty, capped at
## `CLEAN_SHARE_MAX`. 0.0 means every dollar the table pays is dirty, exactly as M1 shipped.
##
## INTENDED CONSUMPTION POINT (the flow lane owns this; it is not applied here):
## inside `Game.earn_switch`, after the payout `v` is final — base × Ledger × Heat band ×
## mode × combo — and after the wallet, Heat and Jobs have already seen the whole of it:
##
##     var share := Game.stats.clean_share()
##     if share > 0.0:
##         var slice := BigMoney.min_of(v.mul(share), Game.launder_cap_left())
##         # move `slice` dirty -> clean, booked as laundered
##
## Three properties that make this safe, and that a consumer must not quietly drop:
##   1. It is drawn AGAINST the per-Night wash cap (`Game.launder_cap_left()`), so it cannot
##      outrun docs/03 §2 — with the cap spent, the share pays nothing and the money stays
##      dirty. That is the whole reason it is a share of a payout rather than a second faucet.
##   2. The switch is still HOT MONEY: Heat sees the full payout, because the shot was dirty
##      when it landed and the wash happens on the way to the pocket. A clean share that
##      dodged the Heat meter would be a stealth risk-nerf sold as a convenience.
##   3. It books as LAUNDERED, not as `earn_clean`: dirty really did become clean, so The
##      Count's wash line tells the truth and the sims' `night_dirty − night_laundered ==
##      held dirty` invariant survives.
func clean_share() -> float:
	return minf(_clean_share, CLEAN_SHARE_MAX)


# --- fold shapes --------------------------------------------------------------


## Which bucket a kind folds into; UNION for anything the vocabulary does not name.
static func fold_of(kind: StringName) -> int:
	return int(FOLD.get(kind, Fold.UNION))


## What one effect contributes at `level`, in the shape its bucket folds with: PRODUCT
## compounds (v^level), MIN divides (v/level), everything else scales linearly (v × level).
## A one-off effect ignores level entirely.
static func scaled_value(effect: Dictionary, level: int) -> float:
	var v := float(effect["num"])
	if not bool(effect["per_level"]) or level <= 1:
		return v
	match fold_of(effect["kind"]):
		Fold.PRODUCT:
			return pow(v, float(level))
		Fold.MIN:
			return v / float(level)
	return v * float(level)


## Money effects only ever sum or take the highest, so a level is always linear.
static func scaled_money(effect: Dictionary, level: int) -> BigMoney:
	var v: BigMoney = effect["money"]
	return v.mul(float(level)) if bool(effect["per_level"]) and level > 1 else v.copy()


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
	_heat_decay = 1.0
	_bail_discount = 0.0
	_auto_collect = 0.0
	_casino_edge = 0.0
	_casino_pockets = 0
	_job_respect = 1.0
	_serve_speed = 1.0
	_auto_launder = 0.0
	_kickback_cooldown = 1.0
	_job_rerolls = 0
	_aim_line = 0
	_launder_cap_mult = 1.0
	_clean_share = 0.0


func _apply(effect: Dictionary, level: int) -> void:
	var kind: StringName = effect["kind"]
	var target: StringName = effect["target"]
	match kind:
		&"unlock_hardware":
			_hardware[target] = true
		&"feature_flag":
			_flags[target] = true
		&"value_mult":
			_value_mult[target] = float(_value_mult.get(target, 1.0)) * scaled_value(effect, level)
		&"value_add":
			var add: BigMoney = _value_add.get(target, null)
			var v := scaled_money(effect, level)
			_value_add[target] = v if add == null else add.add(v)
		&"idle_rate_add":
			_idle_total = _idle_total.add(scaled_money(effect, level))
		&"launder_rate_add":
			_launder_rate += scaled_value(effect, level)
		&"launder_cap_add":
			_launder_cap = _launder_cap.add(scaled_money(effect, level))
		&"pocket_money_set":
			_pocket = BigMoney.max_of(_pocket, scaled_money(effect, level))
		&"passive_wash_add":
			_passive_wash += scaled_value(effect, level)
		&"safe_hours_set":
			_safe_hours = maxf(_safe_hours, scaled_value(effect, level))
		&"bench_slot_add":
			_bench_slots += int(scaled_value(effect, level))
		&"ball_save_charges":
			_ball_saves += int(scaled_value(effect, level))
		&"tilt_leans_add":
			_tilt_leans += int(scaled_value(effect, level))
		&"flipper_power_mult":
			_flipper_power *= scaled_value(effect, level)
		&"kickback_unlock":
			_kickbacks[target] = true
			# The table shows an outlane kicker by hardware id (specs/m1-hook.md); the
			# content vocabulary unlocks it by side, so this is the bridge between them.
			_hardware[StringName("kickback_" + String(target))] = true
		&"bribe_unlock":
			_bribe = true
			_hardware[&"bribe_target"] = true
		&"job_slots_set":
			_job_slots = maxi(_job_slots, int(scaled_value(effect, level)))
		&"collect_minutes_mult":
			_collect_minutes *= scaled_value(effect, level)
		&"heat_decay_mult":
			_heat_decay *= scaled_value(effect, level)
		&"bail_discount":
			_bail_discount += scaled_value(effect, level)
		&"auto_collect_interval":
			var secs := scaled_value(effect, level)
			_auto_collect = secs if _auto_collect <= 0.0 else minf(_auto_collect, secs)
		&"casino_edge_add":
			_casino_edge += scaled_value(effect, level)
		&"casino_pocket_add":
			_casino_pockets += int(scaled_value(effect, level))
		&"job_reroll_add":
			_job_rerolls += int(scaled_value(effect, level))
		&"job_respect_mult":
			_job_respect *= scaled_value(effect, level)
		&"serve_speed_mult":
			_serve_speed *= scaled_value(effect, level)
		&"auto_launder_per_sec":
			_auto_launder += scaled_value(effect, level)
		&"kickback_cooldown_mult":
			_kickback_cooldown *= scaled_value(effect, level)
		&"aim_line":
			_aim_line = maxi(_aim_line, int(scaled_value(effect, level)))
		&"launder_cap_mult":
			_launder_cap_mult *= scaled_value(effect, level)
		&"clean_share":
			_clean_share += scaled_value(effect, level)
		&"all_dirty_mult":
			_value_mult[&"all"] = float(_value_mult.get(&"all", 1.0)) * scaled_value(effect, level)
