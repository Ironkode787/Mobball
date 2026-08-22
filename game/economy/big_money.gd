class_name BigMoney
extends RefCounted
## Big-number money value: `value == m * 10^e`, mantissa normalized to `1 <= |m| < 10`
## (or exactly `0`, in which case `e == 0`). Negative values are supported (deltas,
## debts); the Wallet is what refuses to go below zero, not this type.
##
## Immutable by convention: every operation returns a NEW instance and nothing mutates
## `m` / `e` after construction. Treat instances you receive (signal payloads, getters)
## as read-only.
##
## Precision contract: the mantissa is a float64 (~15–16 significant digits), so adding
## a value more than PRECISION_ORDERS magnitudes smaller than the receiver is a
## deliberate no-op — it would round away anyway, and skipping it keeps the common
## "dust" case cheap. All arithmetic is exponent-first, so 1e300 * 1e300 is routine
## rather than an overflow. Non-finite inputs never propagate: NaN collapses to zero,
## INF saturates at MAX_EXP.

## Magnitude gap at or past which `add()` / `sub_*()` ignore the smaller operand:
## adding something 15+ orders of magnitude smaller cannot survive a float64 mantissa,
## so it is a documented no-op instead of a lie.
const PRECISION_ORDERS := 15
## Exponent saturation. Far beyond any reachable game value, and small enough that
## `e1 + e2` in mul_big() cannot come near int64 overflow.
const MAX_EXP := 1_000_000_000
## Short-scale suffixes by 10^3 group. Past the last one, display goes scientific.
const SUFFIXES: PackedStringArray = [
	"", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
]
## First exponent with no suffix left (3 * SUFFIXES.size()).
const SCI_EXP := 36
## Largest exponent `approx_float()` can express in a float64.
const FLOAT_MAX_EXP := 308

const _INV_LN10 := 0.4342944819032518
const _POW10: PackedFloat64Array = [
	1.0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8,
	1e9, 1e10, 1e11, 1e12, 1e13, 1e14, 1e15,
]

var m: float = 0.0
var e: int = 0


func _init(mantissa: float = 0.0, exponent: int = 0) -> void:
	m = mantissa
	e = exponent
	_normalize()


# --- constructors -------------------------------------------------------------


static func zero() -> BigMoney:
	return BigMoney.new()


## Raw mantissa/exponent pair; normalizes, so `of(1234.0, 5)` is legal.
static func of(mantissa: float, exponent: int) -> BigMoney:
	return BigMoney.new(mantissa, exponent)


static func from_float(f: float) -> BigMoney:
	return BigMoney.new(f, 0)


static func from_dict(d: Dictionary) -> BigMoney:
	if d == null or not d.has("m") or not d.has("e"):
		return BigMoney.new()
	var raw_m: Variant = d["m"]
	var raw_e: Variant = d["e"]
	if not (raw_m is float or raw_m is int) or not (raw_e is float or raw_e is int):
		return BigMoney.new()
	return BigMoney.new(float(raw_m), int(raw_e))


## Data-file / save-file friendly text. Accepts `"1234"`, `"12.5K"`, `"3.2M"`,
## `"1e30"`, `"$1,234.50"`, `"-5"`. Anything unparseable yields zero (money code
## never crashes on bad content data; the loader can validate separately).
static func parse(s: String) -> BigMoney:
	var t := s.strip_edges().replace(",", "").replace("$", "").replace(" ", "")
	if t.is_empty():
		return BigMoney.new()
	var sign := 1.0
	if t.begins_with("-"):
		sign = -1.0
		t = t.substr(1)
	elif t.begins_with("+"):
		t = t.substr(1)
	if t.is_empty():
		return BigMoney.new()

	var ei := t.findn("e")
	if ei > 0:
		var mant := t.substr(0, ei)
		var expo := t.substr(ei + 1)
		if expo.begins_with("+"):
			expo = expo.substr(1)
		if not mant.is_valid_float() or not expo.is_valid_int():
			return BigMoney.new()
		return BigMoney.new(sign * mant.to_float(), expo.to_int())

	var lower := t.to_lower()
	# Descending so two-letter suffixes ("Qa", "Dc") match before "T"/"B"/"M"/"K".
	for i in range(SUFFIXES.size() - 1, 0, -1):
		var suf := SUFFIXES[i].to_lower()
		if lower.ends_with(suf):
			var num := t.substr(0, t.length() - suf.length())
			if not num.is_valid_float():
				return BigMoney.new()
			return BigMoney.new(sign * num.to_float(), i * 3)

	if not t.is_valid_float():
		return BigMoney.new()
	return BigMoney.new(sign * t.to_float(), 0)


func copy() -> BigMoney:
	return BigMoney.new(m, e)


# --- queries ------------------------------------------------------------------


func is_zero() -> bool:
	return m == 0.0


func is_positive() -> bool:
	return m > 0.0


func is_negative() -> bool:
	return m < 0.0


## -1 / 0 / +1 sign of the value.
func sign_of() -> int:
	if m > 0.0:
		return 1
	if m < 0.0:
		return -1
	return 0


## May be INF for values past float64 range, 0.0 for values below it. For display use
## text(); for ratios use ratio_to().
func approx_float() -> float:
	if m == 0.0:
		return 0.0
	if e > FLOAT_MAX_EXP:
		return INF if m > 0.0 else -INF
	if e < -FLOAT_MAX_EXP:
		return 0.0
	return m * pow(10.0, float(e))


## -1 if self < b, 0 if equal, 1 if self > b. Exact on the (m, e) pair.
func cmp(b: BigMoney) -> int:
	if b == null:
		return 0 if m == 0.0 else sign_of()
	var sa := sign_of()
	var sb := b.sign_of()
	if sa != sb:
		return -1 if sa < sb else 1
	if sa == 0:
		return 0
	if e != b.e:
		# For negatives the bigger exponent is the SMALLER value.
		var bigger_e := 1 if e > b.e else -1
		return bigger_e if sa > 0 else -bigger_e
	if m == b.m:
		return 0
	return 1 if m > b.m else -1


func equals(b: BigMoney) -> bool:
	return cmp(b) == 0


## Tolerant comparison for tests and float-derived values (relative epsilon on the
## mantissa, exact on the exponent once both are normalized).
func equals_approx(b: BigMoney, rel_tol: float = 1e-9) -> bool:
	if b == null:
		return false
	if m == 0.0 or b.m == 0.0:
		return m == b.m
	if e == b.e:
		return absf(m - b.m) <= rel_tol * maxf(absf(m), absf(b.m))
	# One step apart can still be equal-ish across a normalization boundary
	# (9.999999999e2 vs 1.000000000e3).
	if absi(e - b.e) == 1:
		var hi := self if e > b.e else b
		var lo := b if e > b.e else self
		return absf(hi.m * 10.0 - lo.m) <= rel_tol * 10.0 * maxf(absf(hi.m * 10.0), absf(lo.m))
	return false


## self / b as a plain float (INF if it overflows, 0.0 if b is zero). Allocation-free —
## this is the hot path for "how many rank-scales did we just earn".
func ratio_to(b: BigMoney) -> float:
	if b == null or b.m == 0.0 or m == 0.0:
		return 0.0
	var de := e - b.e
	var q := m / b.m
	if de > FLOAT_MAX_EXP:
		return INF if q > 0.0 else -INF
	if de < -FLOAT_MAX_EXP:
		return 0.0
	return q * pow(10.0, float(de))


# --- arithmetic (all return new instances) ------------------------------------


func neg() -> BigMoney:
	return BigMoney.new(-m, e)


func abs_of() -> BigMoney:
	return BigMoney.new(absf(m), e)


func add(b: BigMoney) -> BigMoney:
	if b == null or b.m == 0.0:
		return copy()
	if m == 0.0:
		return b.copy()
	var de := e - b.e
	# Documented precision rule: dust 15+ orders of magnitude down is dropped.
	if de >= PRECISION_ORDERS:
		return copy()
	if de <= -PRECISION_ORDERS:
		return b.copy()
	if de >= 0:
		return BigMoney.new(m + b.m / _POW10[de], e)
	return BigMoney.new(b.m + m / _POW10[-de], b.e)


## Subtraction clamped at zero — the gameplay default (spending, confiscation).
func sub_clamped(b: BigMoney) -> BigMoney:
	if b == null or b.m == 0.0:
		return copy() if m > 0.0 else BigMoney.new()
	var r := add(b.neg())
	if r.m < 0.0:
		return BigMoney.new()
	return r


## Subtraction that refuses to underflow: returns null when `b > self`, so purchase
## code can branch on affordability without a second compare. `sub_clamped` is the
## forgiving sibling; both exist because both call sites are real.
func sub_exact(b: BigMoney) -> BigMoney:
	if b == null or b.m == 0.0:
		return copy()
	if cmp(b) < 0:
		return null
	return add(b.neg())


func mul(scalar: float) -> BigMoney:
	if m == 0.0 or scalar == 0.0 or not is_finite(scalar):
		return BigMoney.new()
	return BigMoney.new(m * scalar, e)


func mul_big(b: BigMoney) -> BigMoney:
	if b == null or m == 0.0 or b.m == 0.0:
		return BigMoney.new()
	return BigMoney.new(m * b.m, e + b.e)


## Division by zero yields zero rather than INF — money code stays finite.
func div(scalar: float) -> BigMoney:
	if m == 0.0 or scalar == 0.0 or not is_finite(scalar):
		return BigMoney.new()
	return BigMoney.new(m / scalar, e)


func div_big(b: BigMoney) -> BigMoney:
	if b == null or b.m == 0.0 or m == 0.0:
		return BigMoney.new()
	return BigMoney.new(m / b.m, e - b.e)


## self * 10^n — free, it is just the exponent.
func shift(n: int) -> BigMoney:
	if m == 0.0:
		return BigMoney.new()
	return BigMoney.new(m, e + n)


static func min_of(a: BigMoney, b: BigMoney) -> BigMoney:
	if a == null:
		return b
	if b == null:
		return a
	return a if a.cmp(b) <= 0 else b


static func max_of(a: BigMoney, b: BigMoney) -> BigMoney:
	if a == null:
		return b
	if b == null:
		return a
	return a if a.cmp(b) >= 0 else b


# --- display ------------------------------------------------------------------


## `"$0"`, `"$482"`, `"$12.5K"`, `"$3.40M"`, `"$7.77T"`, … `"$1.2e40"`.
## Negative values read `"-$5.00"`.
func text() -> String:
	var p := text_plain()
	if p.begins_with("-"):
		return "-$" + p.substr(1)
	return "$" + p


## Same formatting without the currency mark (rates, deltas, tooltips).
##
## Format rule: three significant digits — 0 decimals at >= 100, 1 decimal at >= 10,
## 2 decimals below that ("482", "12.5K", "3.40M"). Values under $1 print as "0.50" /
## "0.05"; exact zero is the only "0". Past the suffix table it goes scientific with
## two significant digits ("1.2e40").
func text_plain() -> String:
	if m == 0.0:
		return "0"
	var sign := "-" if m < 0.0 else ""
	var a := absf(m)

	if e >= SCI_EXP:
		var sm := roundf(a * 10.0) / 10.0
		var se := e
		if sm >= 10.0:
			sm /= 10.0
			se += 1
		return "%s%.1fe%d" % [sign, sm, se]

	var group := 0
	var scaled := a
	if e >= 0:
		group = e / 3
		scaled = a * _POW10[e - group * 3]
	else:
		# Sub-dollar: no suffix, just the raw fraction.
		scaled = a * pow(10.0, float(maxi(e, -FLOAT_MAX_EXP)))

	var dec := 0 if scaled >= 100.0 else (1 if scaled >= 10.0 else 2)
	var factor := _POW10[dec]
	var r := roundf(scaled * factor) / factor
	if r >= 1000.0:
		# Rounding carried into the next suffix group (999.9K -> 1.00M).
		group += 1
		r = 1.0
		dec = 2
		if group >= SUFFIXES.size():
			return "%s1.0e%d" % [sign, group * 3]
	elif r >= 100.0:
		dec = 0
	elif r >= 10.0 and dec > 1:
		dec = 1

	var body := ""
	if dec == 0:
		body = "%.0f" % r
	elif dec == 1:
		body = "%.1f" % r
	else:
		body = "%.2f" % r
	return sign + body + SUFFIXES[group]


func _to_string() -> String:
	return text()


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	return {"m": m, "e": e}


# --- internals ----------------------------------------------------------------


func _normalize() -> void:
	if not is_finite(m):
		if is_nan(m):
			m = 0.0
			e = 0
			return
		# INF saturates instead of poisoning every downstream value.
		m = 1.0 if m > 0.0 else -1.0
		e = MAX_EXP
		return
	if m == 0.0:
		e = 0
		return
	var a := absf(m)
	if a >= 1.0 and a < 10.0:
		_clamp_exp()
		return

	var neg_m := m < 0.0
	var shift_by := floori(log(a) * _INV_LN10)
	# Chunked so a huge |shift| cannot overflow/underflow pow().
	var rem := shift_by
	while rem > 0:
		var step := mini(rem, 300)
		a /= pow(10.0, float(step))
		rem -= step
	while rem < 0:
		var step := mini(-rem, 300)
		a *= pow(10.0, float(step))
		rem += step
	# log10 rounding can leave us one order out either way.
	var guard := 0
	while a >= 10.0 and guard < 8:
		a /= 10.0
		shift_by += 1
		guard += 1
	while a < 1.0 and a > 0.0 and guard < 16:
		a *= 10.0
		shift_by -= 1
		guard += 1
	if a == 0.0 or not is_finite(a):
		m = 0.0
		e = 0
		return
	m = -a if neg_m else a
	e += shift_by
	_clamp_exp()


func _clamp_exp() -> void:
	if e > MAX_EXP:
		e = MAX_EXP
	elif e < -MAX_EXP:
		# Underflow is zero: no game value lives 10^-1e9 dollars deep.
		m = 0.0
		e = 0
