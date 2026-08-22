class_name Casino
extends RefCounted
## THE CLUB'S BOOK (specs/m2-content.md §1, docs/03 §3 "chance, priced honestly").
##
## Pure logic. It holds the odds, the streaks and the Night's book, and it decides what a
## spin is worth — it never touches a wallet. `Game` stakes the bet, calls `resolve()` and
## pays the answer down the single money path, which is the same discipline the rest of the
## deck follows: hardware reports outcomes, flow owns money (specs/m2-empire.md).
##
## The edge is real and legible. Five of the wheel's eight pockets are the player's and a win
## pays 1.48× the stake, so a spin returns 5/8 × 1.48 = 0.925 of what it costs — a −7.5%
## house edge. Influence upgrades buy pockets and payout, never outcomes (P2), so every knob
## below moves the EV honestly and `expected_value()` will tell you what it moved it to.
##
## Casino money is the *wash*, not hot money: wins never feed the Heat window (`Game` sends
## the dirty branch through `earn_switch(..., {"no_heat": true})`). The High Roller ladder and
## the Jackpot add flat Heat instead — the deck is where you go to cool the wallet and warm
## the meter.

## Every tuning knob for the deck, in one block, data-like — nothing else in the casino code
## may hard-code a rate (the same rule `Rates` holds the rest of the economy to).
class CasinoRules:
	extends RefCounted

	## Table stakes: each landing auto-bets this fraction of held dirty, capped.
	const STAKE_FRACTION := 0.05
	## A player pocket pays this × the stake. 5/8 × 1.48 = −7.5% EV.
	const PAYOUT := 1.48
	## Loaded Dice ↻ at max level, per specs/m2-content.md §1.
	const PAYOUT_MAX := 1.55
	## Stake cap at R0, ×3.5 per rank — the same income curve `Rates.rank_scale` tracks, so a
	## capped stake is worth the same slice of a Night at every rank.
	const STAKE_CAP_MANTISSA := 5.0
	const STAKE_CAP_EXP := 3
	const STAKE_CAP_PER_RANK := 3.5
	## The wheel as built (game/table/hardware/roulette_wheel.gd): 8 pockets, 3 of them the
	## house's. Loaded Dice converts one house pocket at max level.
	const POCKETS := 8
	const PLAYER_POCKETS := 5
	const PLAYER_POCKETS_MAX := 6
	## The Cooler: five straight losing spins and the next win pays +50% ("the cooler got
	## fired"); the `coolers_fired` node doubles the apology.
	const COOLER_STREAK := 5
	const COOLER_BONUS := 0.5
	const COOLER_BONUS_FIRED := 1.0
	## Comps: the house buys this many stakes a Night once `fronts.comps` is owned.
	const COMPS_PER_NIGHT := 1
	## High Roller ladder, indexed by the rungs the hold climbed (0 = no hold).
	const HIGH_ROLLER_MULT: PackedFloat32Array = [1.0, 2.0, 3.0, 5.0]
	const HIGH_ROLLER_HEAT: PackedFloat32Array = [0.0, 3.0, 6.0, 12.0]
	## Slots: all three columns cleared inside one deck visit.
	const JACKPOT_COLUMNS := 3
	const JACKPOT_MINUTES := 8.0
	const JACKPOT_HEAT := 8.0

## Ledger flag that turns casino payouts clean (fronts.casino_wash). Until it is bought the
## house pays you in the same dirty money you gave it — the wash is a purchase, not a given.
const WASH_FLAG := &"casino_wash"
const COOLERS_FIRED_FLAG := &"coolers_fired"
const COMPS_FLAG := &"comps"

# --- tonight's book -----------------------------------------------------------
var night_staked: BigMoney = BigMoney.zero()
var night_won: BigMoney = BigMoney.zero()
var night_washed: BigMoney = BigMoney.zero()
var night_spins: int = 0
var night_wins: int = 0
var night_jackpots: int = 0
## Stakes the house is still buying tonight (`fronts.comps`).
var comps_left: int = 0

# --- the career book (saved) --------------------------------------------------
var total_staked: BigMoney = BigMoney.zero()
var total_won: BigMoney = BigMoney.zero()
var total_washed: BigMoney = BigMoney.zero()
var total_spins: int = 0
var total_wins: int = 0
var total_jackpots: int = 0
## Consecutive losing spins. Survives a save: the Cooler owes you across Nights.
var loss_streak: int = 0
## The High Roller's ladder, waiting on the NEXT payout. 1.0 = nothing armed.
var armed: float = 1.0

var _visit: bool = false
var _visit_columns: Dictionary = {}
var _visit_jackpot: bool = false


# ================================================================== the odds =====


## Stake ceiling at a given rank.
static func stake_cap(rank: int) -> BigMoney:
	var r := maxi(rank, 0)
	return BigMoney.of(CasinoRules.STAKE_CAP_MANTISSA, CasinoRules.STAKE_CAP_EXP).mul(
			pow(CasinoRules.STAKE_CAP_PER_RANK, float(r)))


## What the next landing bets: 5% of held dirty, capped by rank.
static func stake_for(held_dirty: BigMoney, rank: int) -> BigMoney:
	if held_dirty == null or not held_dirty.is_positive():
		return BigMoney.zero()
	return BigMoney.min_of(held_dirty.mul(CasinoRules.STAKE_FRACTION), stake_cap(rank))


## Payout multiple on a player pocket. `casino_edge_add` is META-2's specialist/Influence
## vocabulary (Eddie Odds, Loaded Dice); it is read through `has_method` because that lane is
## extending `Stats` in parallel and a missing getter has to mean "no edge bought yet", never
## a crash.
static func payout_rate(stats: Object) -> float:
	var edge := 0.0
	if stats != null and stats.has_method("casino_edge_add"):
		edge = float(stats.call("casino_edge_add"))
	if not is_finite(edge):
		edge = 0.0
	return clampf(CasinoRules.PAYOUT + edge, 1.0, CasinoRules.PAYOUT_MAX)


## How many of the eight pockets pay. Loaded Dice buys the sixth (META-2 hook, same rule).
static func player_pockets(stats: Object) -> int:
	var n := CasinoRules.PLAYER_POCKETS
	if stats != null and stats.has_method("casino_player_pockets"):
		n = int(stats.call("casino_player_pockets"))
	return clampi(n, 1, CasinoRules.PLAYER_POCKETS_MAX)


## Has the Casino Wash been bought? Until it has, wins pay DIRTY (specs/m2-content.md §3).
static func wash_active(stats: Object) -> bool:
	return stats != null and stats.has_method("flag") and bool(stats.call("flag", WASH_FLAG))


## The Cooler's apology, doubled once `coolers_fired` is owned.
static func cooler_bonus(stats: Object) -> float:
	if stats != null and stats.has_method("flag") and bool(stats.call("flag", COOLERS_FIRED_FLAG)):
		return CasinoRules.COOLER_BONUS_FIRED
	return CasinoRules.COOLER_BONUS


## Free stakes a Night: the house comps a regular (`fronts.comps`, specs/m2-content.md §3).
static func comps_for(stats: Object) -> int:
	if stats != null and stats.has_method("flag") and bool(stats.call("flag", COMPS_FLAG)):
		return CasinoRules.COMPS_PER_NIGHT
	return 0


## Is the house buying this one? Consumes the comp, so ask once per bet.
func take_comp(stake: BigMoney) -> bool:
	if comps_left <= 0 or stake == null or not stake.is_positive():
		return false
	comps_left -= 1
	return true


## Return per unit staked, minus the unit: −0.075 on a bare wheel. Positive means the house
## is losing, which is exactly what full Influence investment is supposed to buy.
static func expected_value(stats: Object) -> float:
	return float(player_pockets(stats)) / float(CasinoRules.POCKETS) * payout_rate(stats) - 1.0


# =============================================================== the High Roller =====


## A hold ended `steps` rungs up the ladder: arm the NEXT payout and return the flat Heat the
## greed cost. Steps outside the ladder are clamped, so a table that grows a longer ladder
## cannot index this off the end.
func arm(steps: int) -> float:
	var i := clampi(steps, 0, CasinoRules.HIGH_ROLLER_MULT.size() - 1)
	var mult := CasinoRules.HIGH_ROLLER_MULT[i]
	if mult <= 1.0:
		return 0.0
	armed = maxf(armed, mult)
	return CasinoRules.HIGH_ROLLER_HEAT[i]


func armed_multiplier() -> float:
	return armed


# ==================================================================== the wheel =====


## Resolve one auto-bet. Pure: everything it needs is an argument, so a unit test can walk the
## whole EV curve without a wallet. `stake` is what the caller ALREADY took out of the wallet
## (zero = the player had nothing to bet with, which is not a spin at all).
##
## Order of multipliers on a win: base payout → Cooler apology → the armed High Roller ladder.
## The ladder is consumed whether or not the Cooler fired; the streak resets on any win.
##
## A `comped` spin is the same bet with the house's money: it plays and pays exactly like any
## other, but it is not booked as staked, because The Count's staked line is what came out of
## the player's pocket.
func resolve(pocket: int, house: bool, stake: BigMoney, payout: float,
		wash: bool, pity: float = CasinoRules.COOLER_BONUS, comped: bool = false) -> Dictionary:
	var out := {
		"pocket": pocket,
		"house": house,
		"bet": false,
		"staked": BigMoney.zero(),
		"won": BigMoney.zero(),
		"clean": wash,
		"cooler": false,
		"comped": comped,
		"multiplier": 1.0,
		"payout": payout,
		"streak": loss_streak,
	}
	if stake == null or not stake.is_positive():
		return out

	out["bet"] = true
	out["staked"] = BigMoney.zero() if comped else stake
	if not comped:
		night_staked = night_staked.add(stake)
		total_staked = total_staked.add(stake)
	night_spins += 1
	total_spins += 1

	if house:
		# The ladder is NOT burned by a loss: the High Roller bought the next PAYOUT, and a
		# pocket that pays nothing is not one.
		loss_streak += 1
		out["streak"] = loss_streak
		return out

	var mult := payout
	if loss_streak >= CasinoRules.COOLER_STREAK:
		out["cooler"] = true
		mult *= 1.0 + maxf(pity, 0.0)
	mult *= armed
	armed = 1.0
	loss_streak = 0
	night_wins += 1
	total_wins += 1
	out["multiplier"] = mult
	out["won"] = stake.mul(mult)
	out["streak"] = 0
	return out


## Book what actually landed in the wallet (post-multiplier), so The Count's casino line is
## the money the player got rather than the money the wheel promised.
func book_payout(paid: BigMoney, clean: bool) -> void:
	if paid == null or not paid.is_positive():
		return
	night_won = night_won.add(paid)
	total_won = total_won.add(paid)
	if clean:
		night_washed = night_washed.add(paid)
		total_washed = total_washed.add(paid)


# ===================================================================== the slots =====


## A deck visit runs from a completed Staircase climb until the ball is back downstairs (or
## gone). Clearing all three reels inside ONE visit is the Jackpot; the reels re-arm on their
## own clock, so the union across the visit is what counts.
func open_visit() -> void:
	_visit = true
	_visit_columns.clear()
	_visit_jackpot = false


func close_visit() -> void:
	_visit = false
	_visit_columns.clear()
	_visit_jackpot = false


func visit_open() -> bool:
	return _visit


func visit_columns() -> int:
	return _visit_columns.size()


## Fold a `reels_state` report into this visit. True exactly once, on the report that
## completes the set.
func on_reels(cleared_columns: Array) -> bool:
	if not _visit or _visit_jackpot:
		return false
	for c: Variant in cleared_columns:
		_visit_columns[int(c)] = true
	if _visit_columns.size() < CasinoRules.JACKPOT_COLUMNS:
		return false
	_visit_jackpot = true
	night_jackpots += 1
	total_jackpots += 1
	return true


## JACKPOT_MINUTES of the whole empire's idle rate, paid clean.
static func jackpot_value(idle_rate: BigMoney) -> BigMoney:
	if idle_rate == null or not idle_rate.is_positive():
		return BigMoney.zero()
	return idle_rate.mul(CasinoRules.JACKPOT_MINUTES * 60.0)


# ====================================================================== the book =====


func begin_night(free_stakes: int = 0) -> void:
	night_staked = BigMoney.zero()
	night_won = BigMoney.zero()
	night_washed = BigMoney.zero()
	night_spins = 0
	night_wins = 0
	night_jackpots = 0
	comps_left = maxi(free_stakes, 0)
	armed = 1.0
	close_visit()


## Net for The Count: won minus staked, which is the only number a gambler actually reads.
func night_net() -> BigMoney:
	return night_won.add(night_staked.neg())


func night_summary() -> Dictionary:
	return {
		"staked": night_staked.copy(),
		"won": night_won.copy(),
		"washed": night_washed.copy(),
		"net": night_net(),
		"spins": night_spins,
		"wins": night_wins,
		"jackpots": night_jackpots,
		"streak": loss_streak,
	}


func to_dict() -> Dictionary:
	return {
		"staked": total_staked.to_dict(),
		"won": total_won.to_dict(),
		"washed": total_washed.to_dict(),
		"spins": total_spins,
		"wins": total_wins,
		"jackpots": total_jackpots,
		"streak": loss_streak,
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	total_staked = BigMoney.from_dict(d.get("staked", {}))
	total_won = BigMoney.from_dict(d.get("won", {}))
	total_washed = BigMoney.from_dict(d.get("washed", {}))
	total_spins = maxi(int(d.get("spins", 0)), 0)
	total_wins = maxi(int(d.get("wins", 0)), 0)
	total_jackpots = maxi(int(d.get("jackpots", 0)), 0)
	loss_streak = maxi(int(d.get("streak", 0)), 0)
	begin_night()
