class_name WireDraws
extends RefCounted
## THE WIRE — the numbers draws (docs/05 §4, docs/03 §3). Every 90 s of play the tote board
## draws 00–99. Your ticket is the last two digits of the spinner's session spin count, so
## **the spinner is the bet slip**: grinding the numbers lane both earns and re-rolls your
## number. Last digit pays ×6 dirty; the exact number pays ×80 CLEAN.
##
## Pure logic on a fed clock, seeded per Night, so a replayed Night draws the same numbers.
## The next number is rolled the moment the last one lands — that is what makes the T5
## Wiretap ("see the next draw 15 s early") a read of state rather than a peek at an RNG.

## Seconds of night time between draws.
const PERIOD := 90.0
const NUMBERS := 100
const LAST_DIGIT_MULT := 6.0
const EXACT_MULT := 80.0
## Floor under the base a draw multiplies: a Night with a cold spinner still pays something.
const MIN_BASE_MANTISSA := 5.0
const MIN_BASE_EXP := 2

const HIT_NONE := &"none"
const HIT_LAST := &"last"
const HIT_EXACT := &"exact"

var time_left: float = PERIOD
var draws: int = 0
var hits: int = 0
var exacts: int = 0
var last_number: int = -1
var last_ticket: int = -1
var last_hit: StringName = HIT_NONE
var night_won: BigMoney = BigMoney.zero()
var total_won: BigMoney = BigMoney.zero()
var total_draws: int = 0
var total_hits: int = 0
var total_exacts: int = 0

var _rng := RandomNumberGenerator.new()
var _next: int = 0


## Seeded off the career seed AND the Night, so Night 7 always draws Night 7's numbers.
func begin_night(seed_value: int, night_no: int) -> void:
	_rng.seed = seed_value ^ (night_no * 0x9E3779B1)
	time_left = PERIOD
	draws = 0
	hits = 0
	exacts = 0
	last_number = -1
	last_ticket = -1
	last_hit = HIT_NONE
	night_won = BigMoney.zero()
	_next = _rng.randi() % NUMBERS


## The number that is coming (the Wiretap's whole product). Never consumed by reading it.
func peek() -> int:
	return _next


## Feed the night clock. True on the tick a draw comes due; the caller then calls `draw()`.
func tick(delta: float) -> bool:
	if delta <= 0.0:
		return false
	time_left -= delta
	if time_left > 0.0:
		return false
	time_left += PERIOD
	return true


## The base a hit multiplies: what the spinner has earned tonight, floored.
static func base_for(spinner_dirty: BigMoney) -> BigMoney:
	var floor_amount := BigMoney.of(MIN_BASE_MANTISSA, MIN_BASE_EXP)
	if spinner_dirty == null:
		return floor_amount
	return BigMoney.max_of(spinner_dirty, floor_amount)


## Roll the drawn number against a ticket. `ticket` is the last two digits of the spinner's
## count; anything else is taken modulo 100 so a caller cannot hand in a three-digit slip.
func draw(ticket: int, spinner_dirty: BigMoney) -> Dictionary:
	var number := _next
	_next = _rng.randi() % NUMBERS
	var slip := posmod(ticket, NUMBERS)
	draws += 1
	total_draws += 1
	last_number = number
	last_ticket = slip

	var hit := HIT_NONE
	var mult := 0.0
	if slip == number:
		hit = HIT_EXACT
		mult = EXACT_MULT
		hits += 1
		exacts += 1
		total_hits += 1
		total_exacts += 1
	elif slip % 10 == number % 10:
		hit = HIT_LAST
		mult = LAST_DIGIT_MULT
		hits += 1
		total_hits += 1
	last_hit = hit

	var base := base_for(spinner_dirty)
	return {
		"number": number,
		"ticket": slip,
		"hit": hit,
		"mult": mult,
		"base": base,
		"won": base.mul(mult) if mult > 0.0 else BigMoney.zero(),
		# The exact number is the one the house cannot afford to pay in cash.
		"clean": hit == HIT_EXACT,
		"next": _next,
	}


## Book what actually landed (post-multiplier), for The Count.
func book_payout(paid: BigMoney) -> void:
	if paid == null or not paid.is_positive():
		return
	night_won = night_won.add(paid)
	total_won = total_won.add(paid)


func night_summary() -> Dictionary:
	return {
		"draws": draws,
		"hits": hits,
		"exacts": exacts,
		"won": night_won.copy(),
		"number": last_number,
		"ticket": last_ticket,
	}


func to_dict() -> Dictionary:
	return {
		"draws": total_draws,
		"hits": total_hits,
		"exacts": total_exacts,
		"won": total_won.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	total_draws = maxi(int(d.get("draws", 0)), 0)
	total_hits = maxi(int(d.get("hits", 0)), 0)
	total_exacts = maxi(int(d.get("exacts", 0)), 0)
	total_won = BigMoney.from_dict(d.get("won", {}))
