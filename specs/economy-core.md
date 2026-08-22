# SPEC — Economy core (economy workstream)

Owner lane: `game/economy/`, `tests/test_economy*.gd` (+ `tests/test_bigmoney.gd`,
`tests/test_heat.gd`, `tests/test_offline.gd`). Design context: `docs/03-ECONOMY.md`.

**Pure logic only.** Everything here is `RefCounted` (or static) with zero Node/scene
dependencies, so it runs in the plain headless test harness and, later, in the balance-sim
CI (`docs/09-TECH.md` §7). Godot signals on RefCounted are fine. No autoloads here — the
feel/integration workstream will own the `Economy` autoload wrapper later.

## 1. `big_money.gd` — `class_name BigMoney`

Mantissa (float, 1 ≤ |m| < 10 or 0) + exponent (int). Immutable-style: operations return new
instances.

- Constructors: `BigMoney.zero()`, `BigMoney.from_float(f)`, `BigMoney.of(m, e)`,
  `BigMoney.parse(s)` accepting `"1234"`, `"12.5K"`, `"3.2M"`, `"1e30"` (for data files).
- Ops: `add(b)`, `sub_clamped(b)` (never below zero; also `sub_exact` returning null if
  insufficient — pick one style and document), `mul(scalar: float)`, `mul_big(b)`,
  `cmp(b) -> int`, `is_zero()`, `approx_float()` (may be INF for huge).
- Display: `text()` → `"$0"`, `"$482"`, `"$12.5K"`, `"$3.40M"`, `"$7.77T"` … suffixes
  `K M B T Qa Qi Sx Sp Oc No Dc`, then `"$1.2e40"`. Two significant decimals below 3 digits
  of mantissa, none at ≥100 (e.g. `$482K` not `$482.00K`). Also `text_plain()` without `$`.
- Serialization: `to_dict()` → `{"m": float, "e": int}`, `BigMoney.from_dict(d)`.
- Precision rule: adding a value ≥ 15 orders of magnitude smaller is a documented no-op.
  Normalization after every op; handle zero cleanly.

## 2. `wallet.gd` — `class_name Wallet`

Holds `dirty: BigMoney`, `clean: BigMoney`. Signals: `dirty_changed`, `clean_changed`,
`laundered(amount)`. Methods: `earn_dirty(a)`, `launder_fraction(fraction: float,
cap: BigMoney) -> BigMoney` (moves min(dirty×fraction, cap) dirty→clean, returns moved),
`spend_clean(a) -> bool`, `spend_dirty(a) -> bool`, `confiscate_dirty(fraction) -> BigMoney`.

## 3. `heat.gd` — `class_name HeatMeter`

Float 0–100 (+ federal 100–200 flag for later; clamp at 100 for now, expose
`federal_enabled` toggle already). Time is fed, never read (`tick(delta)`) so tests and the
future balance sim control the clock.

- Velocity-based gain: `on_dirty_earned(amount: BigMoney, rank_scale: BigMoney)` — gain
  `HEAT_PER_UNIT` per `rank_scale` of dirty earned inside a rolling 10 s window (keep a
  small ring buffer of windowed earnings; implementation may approximate with exponential
  decay of an "earn rate" accumulator — document the approximation).
- `add_flat(n)` for loud acts; `bribe()` applies −20 with an escalating dirty cost getter
  `bribe_cost(uses_this_night)`.
- Decay: −0.5/s while `calm` (no gain events for 8 s); `lay_low_night()` applies −10.
- Bands per docs/03 §4: expose `band() -> int` (0..4), `multiplier() -> float`
  (1.0/1.5/2.5/4.0), signals `band_changed(band)`, `raid_triggered` at 100 (fire once,
  latch until `reset_after_raid(survived: bool)` → 30 on survive, 0 on bust).

## 4. `rates.gd` — `class_name Rates` (static/consts)

The tuning tables from docs/03 in one place: band thresholds & multipliers, launder rates
(v0 pocket-money $200/night, v1 loop 8%), safe caps (2h base), bail/bribe base costs and
escalators, rank value scale (×10 per rank as the placeholder curve), upgrade cost curve
helper `repeatable_cost(base: BigMoney, level: int)` = base × 1.15^level (use exponent math,
not naive pow on floats when level is large — pow in log10 space).

## 5. `offline.gd` — static helper

`accrue(rate_per_sec: BigMoney, elapsed_sec: float, safe_cap: BigMoney) -> BigMoney` —
clamped, negative elapsed → zero. (Wall-clock policy per docs/09 §9.)

## 6. Tests (be thorough — this is money code)

- BigMoney: normalization, add/sub across magnitudes (incl. the 15-order no-op rule), mul,
  cmp ordering, parse↔text round-trips, display table (write ~20 exact expected strings),
  zero edge cases, serialization round-trip, 1.15^500 cost growth sanity (no overflow/NaN).
- Wallet: launder cap vs fraction, spend failures don't mutate, confiscate math.
- Heat: scripted timeline test — earn burst → band climbs & multiplier matches table; calm
  → decay after 8 s grace; bribe floors at 0; raid latch fires exactly once; reset paths.
- Offline: cap clamp, zero/negative elapsed.

Acceptance: `bash tools/check.sh` green; tests cover every public method; zero Node usage
(grep yourself: no `extends Node`, no `get_tree`, no autoload references).
