class_name Wallet
extends RefCounted
## The two cash currencies (docs/03-ECONOMY.md §1): the table pays in dirty, the Ledger
## only takes clean, and the conversion is a gameplay act.
##
## Pure logic — `RefCounted`, no Node, no autoload. Neither balance can go negative:
## every mutation routes through the setters below, so a listener can trust that a
## `dirty_changed` payload is the whole truth. BigMoney values handed out (signals,
## getters, returns) are immutable by convention — do not write to their `m`/`e`.

signal dirty_changed(value: BigMoney)
signal clean_changed(value: BigMoney)
## Emitted only for a non-zero wash, with the amount moved dirty → clean.
signal laundered(amount: BigMoney)

var _dirty: BigMoney = BigMoney.zero()
var _clean: BigMoney = BigMoney.zero()

## Held dirty cash — what raids confiscate. Assigning clamps negatives/nulls to zero
## and emits `dirty_changed`.
var dirty: BigMoney:
	get:
		return _dirty
	set(v):
		_set_dirty(v)

## Clean cash — the only thing the Ledger accepts.
var clean: BigMoney:
	get:
		return _clean
	set(v):
		_set_clean(v)


func _init(start_dirty: BigMoney = null, start_clean: BigMoney = null) -> void:
	_dirty = _sanitize(start_dirty)
	_clean = _sanitize(start_clean)


# --- income -------------------------------------------------------------------


## Every table payout lands here. Null / zero / negative amounts are ignored.
func earn_dirty(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	_set_dirty(_dirty.add(amount))


## Heists, bonds and Empire Mode pay clean directly (docs/03 §2 tiers v3–v5).
func earn_clean(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	_set_clean(_clean.add(amount))


# --- laundering ---------------------------------------------------------------


## Wash `fraction` of held dirty, capped: moves `min(dirty × fraction, cap)` from dirty
## to clean and returns what actually moved (zero if nothing did).
##
## `fraction` is clamped to [0, 1]. A null `cap` means uncapped; a ZERO cap means a
## cap of zero — nothing washes. That distinction is deliberate: "no cap configured"
## and "your Night's cap is used up" are different states.
func launder_fraction(fraction: float, cap: BigMoney = null) -> BigMoney:
	if _dirty.is_zero() or not is_finite(fraction):
		return BigMoney.zero()
	var f := clampf(fraction, 0.0, 1.0)
	if f <= 0.0:
		return BigMoney.zero()
	var moved := _dirty.mul(f)
	if cap != null:
		if not cap.is_positive():
			return BigMoney.zero()
		moved = BigMoney.min_of(moved, cap)
	# Guard the float-rounding case where fraction 1.0 rounds a hair over the balance.
	moved = BigMoney.min_of(moved, _dirty)
	if moved == null or not moved.is_positive():
		return BigMoney.zero()
	_set_dirty(_dirty.sub_clamped(moved))
	_set_clean(_clean.add(moved))
	laundered.emit(moved)
	return moved


# --- spending -----------------------------------------------------------------


func can_afford_clean(amount: BigMoney) -> bool:
	return amount == null or not amount.is_positive() or _clean.cmp(amount) >= 0


func can_afford_dirty(amount: BigMoney) -> bool:
	return amount == null or not amount.is_positive() or _dirty.cmp(amount) >= 0


## Ledger purchases. Returns false and leaves the wallet untouched if it cannot pay.
func spend_clean(amount: BigMoney) -> bool:
	if amount == null or not amount.is_positive():
		return true
	var rest := _clean.sub_exact(amount)
	if rest == null:
		return false
	_set_clean(rest)
	return true


## Bail, bribes, casino stakes, pawn consumables (docs/03 §8).
func spend_dirty(amount: BigMoney) -> bool:
	if amount == null or not amount.is_positive():
		return true
	var rest := _dirty.sub_exact(amount)
	if rest == null:
		return false
	_set_dirty(rest)
	return true


# --- losses -------------------------------------------------------------------


## A busted raid takes a slice of held dirty (docs/05 §2). `fraction` is clamped to
## [0, 1]; returns the amount taken. Clean cash is never touched (P5: setbacks sting,
## they never erase).
func confiscate_dirty(fraction: float) -> BigMoney:
	if _dirty.is_zero() or not is_finite(fraction):
		return BigMoney.zero()
	var f := clampf(fraction, 0.0, 1.0)
	if f <= 0.0:
		return BigMoney.zero()
	var taken := BigMoney.min_of(_dirty.mul(f), _dirty)
	if taken == null or not taken.is_positive():
		return BigMoney.zero()
	_set_dirty(_dirty.sub_clamped(taken))
	return taken


## Skipping Town: dirty is confiscated wholesale, clean converts to Juice elsewhere.
func reset() -> void:
	_set_dirty(BigMoney.zero())
	_set_clean(BigMoney.zero())


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	return {"dirty": _dirty.to_dict(), "clean": _clean.to_dict()}


func from_dict(d: Dictionary) -> void:
	if d == null:
		return
	var raw_dirty: Variant = d.get("dirty", null)
	var raw_clean: Variant = d.get("clean", null)
	_set_dirty(BigMoney.from_dict(raw_dirty) if raw_dirty is Dictionary else BigMoney.zero())
	_set_clean(BigMoney.from_dict(raw_clean) if raw_clean is Dictionary else BigMoney.zero())


# --- internals ----------------------------------------------------------------


func _set_dirty(v: BigMoney) -> void:
	var next := _sanitize(v)
	if next.cmp(_dirty) == 0:
		return
	_dirty = next
	dirty_changed.emit(_dirty)


func _set_clean(v: BigMoney) -> void:
	var next := _sanitize(v)
	if next.cmp(_clean) == 0:
		return
	_clean = next
	clean_changed.emit(_clean)


func _sanitize(v: BigMoney) -> BigMoney:
	if v == null or v.is_negative():
		return BigMoney.zero()
	return v
