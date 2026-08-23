class_name Briefcases
extends RefCounted
## MYSTERY BRIEFCASES (docs/05 §10, odds in docs/03 §3). A man in a trench coat walks a case
## onto the field, puts it down, and waits. Hit it and it is yours; ignore it for a minute and
## he picks it up and leaves — one shrug, and that is the whole of the fear of missing out.
##
## Odds are the design's, exactly: 70% a wad of dirty, 20% a boon, 10% a setup — and the Pawn
## re-weights it to 75/20/5, which is what a fence is FOR. Two rules keep chance honest here:
##
##   * **A setup cannot fire twice in a row** (docs/03 §3). Being stung is a story; being
##     stung twice running is the game cheating.
##   * **The roll is made when the case is opened, not when it is dropped.** Nothing about a
##     case on the field can be read off it, so there is no tell to learn and no reason to
##     leave one standing.
##
## Pure logic on a fed clock and a seeded RNG: the NightController drops the cases, the table
## owns the token, and `Game` pays whatever this decides.

const WAD := &"wad"
const BOON := &"boon"
const SETUP := &"setup"

## docs/03 §3. Weights, in order, out of 100.
const ODDS := {WAD: 70, BOON: 20, SETUP: 10}
## The Pawn's re-weight (`rackets.protection_pawn`): the same boons, far less trouble.
const ODDS_FENCED := {WAD: 75, BOON: 20, SETUP: 5}
const FENCE_FLAG := &"storefront_pawn"

## Seconds of play between delivery attempts, and the chance one actually shows up. Lucky
## guys on the table add to that chance (`GuyTraits.BRIEFCASE_ODDS_ADD`).
const PERIOD := 75.0
const CHANCE := 0.55
## A case is worth this many minutes of the empire's idle rate, floored so an early career's
## first case is still a wad.
const WAD_MINUTES := 3.0
const WAD_FLOOR_MANTISSA := 5.0
const WAD_FLOOR_EXP := 3
## The setup: Heat, and somebody watching the door (docs/03 §3 — "+15 and a cop target").
const SETUP_HEAT := 15.0
## The boons, one of which is drawn when a case is a boon.
const BOON_DOUBLE := &"double"
const BOON_SAVE := &"save"
const BOON_COOL := &"cool"
const BOONS: Array[StringName] = [BOON_DOUBLE, BOON_SAVE, BOON_COOL]
## "All dirty doubles" is a temporary boon, so it is on a clock of its own.
const BOON_DOUBLE_SECONDS := 20.0
const BOON_DOUBLE_MULT := 2.0
const BOON_COOL_HEAT := 20.0

var boon: StringName = &""
var boon_left: float = 0.0

var opened_total: int = 0
var missed_total: int = 0
var night_opened: int = 0
var night_missed: int = 0
var night_setups: int = 0
var paid_total: BigMoney = BigMoney.zero()
var night_paid: BigMoney = BigMoney.zero()

## The last case was a setup: the next one cannot be (docs/03 §3).
var _stung_last: bool = false
var _next_in: float = PERIOD
var _rng := RandomNumberGenerator.new()


func begin_night(seed_value: int = 0, night_no: int = 0) -> void:
	_rng.seed = hash("briefcase:%d:%d" % [seed_value, night_no])
	_next_in = PERIOD
	boon = &""
	boon_left = 0.0
	night_opened = 0
	night_missed = 0
	night_setups = 0
	night_paid = BigMoney.zero()


# ==================================================================== the bagman =====


## True when the bagman is due to walk one on. `luck` is the fielded crew's added odds.
func tick(delta: float, luck: float = 0.0) -> bool:
	if delta <= 0.0:
		return false
	if boon_left > 0.0:
		boon_left = maxf(boon_left - delta, 0.0)
		if boon_left <= 0.0:
			boon = &""
	_next_in -= delta
	if _next_in > 0.0:
		return false
	_next_in = PERIOD
	return _rng.randf() < clampf(CHANCE + luck, 0.0, 1.0)


## He left with it. Costs nothing but the case (P5).
func on_expired() -> void:
	missed_total += 1
	night_missed += 1


# ==================================================================== the opening =====


## Roll what is in it. `fenced` is the Pawn's re-weight. The result is a dict the caller pays:
## `{kind, boon, seconds}` — the money is `Game`'s, because all money is.
func open(fenced: bool = false) -> Dictionary:
	opened_total += 1
	night_opened += 1
	var kind := _roll(fenced)
	_stung_last = kind == SETUP
	var result := {"kind": String(kind), "boon": "", "seconds": 0.0}
	if kind == SETUP:
		night_setups += 1
		return result
	if kind == BOON:
		var which: StringName = BOONS[_rng.randi() % BOONS.size()]
		result["boon"] = String(which)
		if which == BOON_DOUBLE:
			boon = which
			boon_left = BOON_DOUBLE_SECONDS
			result["seconds"] = BOON_DOUBLE_SECONDS
	return result


func _roll(fenced: bool) -> StringName:
	var weights: Dictionary = ODDS_FENCED if fenced else ODDS
	var total := 0
	for k: Variant in weights:
		# A setup cannot follow a setup, so its weight is simply not in the hat this time.
		if k == SETUP and _stung_last:
			continue
		total += int(weights[k])
	var roll := _rng.randi_range(1, maxi(total, 1))
	for k: Variant in weights:
		if k == SETUP and _stung_last:
			continue
		roll -= int(weights[k])
		if roll <= 0:
			return k
	return WAD


## What a wad is worth: minutes of the empire's idle rate, floored.
static func wad_value(idle_rate: BigMoney) -> BigMoney:
	var floor_value := BigMoney.of(WAD_FLOOR_MANTISSA, WAD_FLOOR_EXP)
	if idle_rate == null or not idle_rate.is_positive():
		return floor_value
	return BigMoney.max_of(idle_rate.mul(WAD_MINUTES * 60.0), floor_value)


## The temporary boon's fold into the money path, while one is running.
func dirty_multiplier() -> float:
	return BOON_DOUBLE_MULT if boon == BOON_DOUBLE and boon_left > 0.0 else 1.0


func book_payout(paid: BigMoney) -> void:
	if paid == null or not paid.is_positive():
		return
	paid_total = paid_total.add(paid)
	night_paid = night_paid.add(paid)


func night_summary() -> Dictionary:
	return {
		"opened": night_opened,
		"missed": night_missed,
		"setups": night_setups,
		"paid": night_paid.copy(),
	}


func to_dict() -> Dictionary:
	return {
		"opened": opened_total,
		"missed": missed_total,
		"paid": paid_total.to_dict(),
		"stung": _stung_last,
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	opened_total = maxi(int(d.get("opened", 0)), 0)
	missed_total = maxi(int(d.get("missed", 0)), 0)
	paid_total = BigMoney.from_dict(d.get("paid", {}))
	_stung_last = bool(d.get("stung", false))
	begin_night()
