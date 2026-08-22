class_name Rates
extends RefCounted
## Every economy tuning number from docs/03-ECONOMY.md, in one place, as statics.
##
## These are the opening bids the balance sim (docs/09-TECH.md §7) will argue with —
## nothing else in the economy may hard-code a threshold, rate or cost. Values marked
## PLACEHOLDER are not pinned by the design docs; they are first drafts sized to the
## bands the docs do pin (§7 cost bands, §9 tuning targets).

# --- Heat: bands (docs/03 §4) -------------------------------------------------

## Lower edge of bands 1..4. Band 4 (heat 100) is the RAID.
const BAND_THRESHOLDS: PackedFloat64Array = [40.0, 70.0, 90.0, 100.0]
## Dirty-cash multiplier per band. Index 4 (raid) keeps the ×4.0 of the band below —
## the sirens do not pay less than the anticipation did.
const BAND_MULTIPLIERS: PackedFloat64Array = [1.0, 1.5, 2.5, 4.0, 4.0]

const HEAT_MAX := 100.0
## Federal stage (R7, docs/03 §4). Off until the FBI content lands.
const HEAT_FEDERAL_MAX := 200.0
const RAID_THRESHOLD := 100.0

# --- Heat: dynamics (docs/03 §4) ----------------------------------------------

## +1 heat per `rank_scale` of dirty earned inside the window.
const HEAT_PER_UNIT := 1.0
## Rolling earn window, seconds ("+1 per $50k earned within 10s").
const HEAT_WINDOW_SEC := 10.0
const HEAT_DECAY_PER_SEC := 0.5
## Seconds without a gain event before decay starts ("nothing loud for 8s").
const HEAT_CALM_GRACE := 8.0
const BRIBE_HEAT := 20.0
const LAY_LOW_HEAT := 10.0
## Post-raid heat: survive keeps you warm, a bust wipes the slate (docs/05 §2).
const RAID_SURVIVE_HEAT := 30.0
const RAID_BUST_HEAT := 0.0
## Held dirty lost on a busted raid (docs/05 §2, upgrade-reducible).
const RAID_CONFISCATE_FRACTION := 0.30

# --- Rank value scale (docs/03 §7) --------------------------------------------

## $50k of dirty per +1 heat at R0; ×10 per rank is the placeholder curve for the
## docs' "~×8–12 per rank".
## Balance-sim ruling (specs/m2 wave): $2K of dirty per +1 heat at R0. The original $50K
## placeholder left peak heat at 5/100 over whole simulated careers — the entire risk
## system never fired. ×3.5 per rank tracks measured income growth (~×3–4/rank from
## Ledger multipliers) so heat stays live at every rank instead of re-dying above R2.
const RANK_SCALE_BASE_MANTISSA := 2.0
const RANK_SCALE_BASE_EXP := 3
const RANK_SCALE_PER_RANK_FACTOR := 3.5
const RANK_MAX := 7

# --- Laundering (docs/03 §2) --------------------------------------------------

## v0 Pocket Money: the first $200 of a Night wash themselves.
const POCKET_MONEY_PER_NIGHT_MANTISSA := 2.0
const POCKET_MONEY_PER_NIGHT_EXP := 2
## v1 Laundromat loop: each pass washes 8% of held dirty.
const LAUNDER_LOOP_FRACTION := 0.08
## Industrial Washers cap the loop at 24% (docs/04 branch B, T2).
const LAUNDER_LOOP_FRACTION_MAX := 0.24

# --- The Safe / idle (docs/03 §6) ---------------------------------------------

const SAFE_CAP_HOURS_BASE := 2.0
## Bigger Safe ↻ tiers (docs/04 branch B, T1).
const SAFE_CAP_HOURS_TIERS: PackedFloat64Array = [2.0, 4.0, 8.0, 12.0, 24.0]

# --- Sinks (docs/03 §8) — PLACEHOLDER costs -----------------------------------

## Beat Cop bribe: dirty cost, doubling per use within one Night.
const BRIBE_COST_BASE_MANTISSA := 5.0
const BRIBE_COST_BASE_EXP := 3
const BRIBE_COST_ESCALATOR := 2.0
## Bail: dirty, scales with the guy's level and his rap sheet; ×3 out of a busted raid.
const BAIL_COST_BASE_MANTISSA := 2.5
const BAIL_COST_BASE_EXP := 2
const BAIL_PER_GUY_LEVEL := 0.5
const BAIL_RAP_ESCALATOR := 1.6
const BAIL_RAID_MULTIPLIER := 3.0

# --- The Ledger cost curve (docs/03 §7, docs/04) ------------------------------

## Repeatable nodes: base × 1.15^level.
const REPEATABLE_GROWTH := 1.15
## log10(1.15). The curve is evaluated in log10 space so level 500 is arithmetic,
## not an overflow.
const REPEATABLE_GROWTH_LOG10 := 0.06069784035361165

## Clean-cash cost band per Ledger tier T0..T7 as [lo_m, lo_e, hi_m, hi_e].
const TIER_BANDS: Array = [
	[5.0, 1, 5.0, 2],      # T0  $50 – $500
	[1.0, 3, 1.0, 4],      # T1  $1k – $10k
	[1.0, 4, 1.0, 5],      # T2  $10k – $100k
	[1.0, 5, 1.0, 6],      # T3  $100k – $1M
	[1.0, 6, 2.0, 7],      # T4  $1M – $20M
	[2.0, 7, 5.0, 8],      # T5  $20M – $500M
	[5.0, 8, 2.0, 10],     # T6  $500M – $20B
	[2.0, 10, 5.0, 12],    # T7  $20B – $5T
]


# --- Heat helpers -------------------------------------------------------------


## 0..4 for a heat value; 4 is the raid band.
static func band_for(heat: float) -> int:
	var b := 0
	for i in BAND_THRESHOLDS.size():
		if heat >= BAND_THRESHOLDS[i]:
			b = i + 1
		else:
			break
	return b


## Dirty-cash multiplier for a heat value (docs/03 §4 table).
static func heat_multiplier(heat: float) -> float:
	return BAND_MULTIPLIERS[band_for(heat)]


static func multiplier_for_band(band: int) -> float:
	return BAND_MULTIPLIERS[clampi(band, 0, BAND_MULTIPLIERS.size() - 1)]


# --- Scale helpers ------------------------------------------------------------


## Dirty earned per +1 heat at a given career rank: $2K at R0, ×3.5 per rank.
static func rank_scale(rank: int) -> BigMoney:
	var r := maxi(rank, 0)
	return BigMoney.of(RANK_SCALE_BASE_MANTISSA, RANK_SCALE_BASE_EXP).mul(
			pow(RANK_SCALE_PER_RANK_FACTOR, float(r)))


static func pocket_money_per_night() -> BigMoney:
	return BigMoney.of(POCKET_MONEY_PER_NIGHT_MANTISSA, POCKET_MONEY_PER_NIGHT_EXP)


## Safe capacity for an idle rate: `hours` of income, base 2h.
static func safe_cap(rate_per_sec: BigMoney, hours: float = SAFE_CAP_HOURS_BASE) -> BigMoney:
	if rate_per_sec == null or hours <= 0.0 or not is_finite(hours):
		return BigMoney.zero()
	return rate_per_sec.mul(hours * 3600.0)


static func safe_cap_hours_for_tier(tier: int) -> float:
	return SAFE_CAP_HOURS_TIERS[clampi(tier, 0, SAFE_CAP_HOURS_TIERS.size() - 1)]


# --- Sinks --------------------------------------------------------------------


## Dirty cost of the next bribe shot, given how many were already bought this Night.
static func bribe_cost(uses_this_night: int) -> BigMoney:
	var uses := maxi(uses_this_night, 0)
	var base := BigMoney.of(BRIBE_COST_BASE_MANTISSA, BRIBE_COST_BASE_EXP)
	return base.mul_big(_pow_big(BRIBE_COST_ESCALATOR, uses))


## Dirty cost to bail a guy out: base × (1 + 0.5·level) × 1.6^prior_pinches, ×3 if the
## stretch came out of a busted raid (docs/05 §2).
static func bail_cost(guy_level: int, prior_pinches: int = 0, from_raid: bool = false) -> BigMoney:
	var lvl := maxi(guy_level, 0)
	var priors := maxi(prior_pinches, 0)
	var base := BigMoney.of(BAIL_COST_BASE_MANTISSA, BAIL_COST_BASE_EXP)
	var cost := base.mul(1.0 + BAIL_PER_GUY_LEVEL * float(lvl))
	cost = cost.mul_big(_pow_big(BAIL_RAP_ESCALATOR, priors))
	if from_raid:
		cost = cost.mul(BAIL_RAID_MULTIPLIER)
	return cost


# --- The Ledger ---------------------------------------------------------------


## Classic incremental curve: `base × 1.15^level`, evaluated in log10 space so that
## level 500 (≈ ×2.2e30) is exact-enough arithmetic instead of a float64 overflow.
static func repeatable_cost(base: BigMoney, level: int) -> BigMoney:
	if base == null:
		return BigMoney.zero()
	if level <= 0 or base.is_zero():
		return base.copy()
	return base.mul_big(_pow10_frac(float(level) * REPEATABLE_GROWTH_LOG10))


static func tier_cost_low(tier: int) -> BigMoney:
	var band: Array = TIER_BANDS[clampi(tier, 0, TIER_BANDS.size() - 1)]
	return BigMoney.of(float(band[0]), int(band[1]))


static func tier_cost_high(tier: int) -> BigMoney:
	var band: Array = TIER_BANDS[clampi(tier, 0, TIER_BANDS.size() - 1)]
	return BigMoney.of(float(band[2]), int(band[3]))


# --- internals ----------------------------------------------------------------


## 10^x for any real x, kept in mantissa/exponent form (never a float overflow).
static func _pow10_frac(x: float) -> BigMoney:
	if not is_finite(x):
		return BigMoney.zero()
	var ex := floori(x)
	return BigMoney.of(pow(10.0, x - float(ex)), ex)


## base^n via log10 space, for the escalating cost ladders.
static func _pow_big(base: float, n: int) -> BigMoney:
	if n <= 0:
		return BigMoney.of(1.0, 0)
	if base <= 0.0 or not is_finite(base):
		return BigMoney.zero()
	return _pow10_frac(float(n) * (log(base) * 0.4342944819032518))
