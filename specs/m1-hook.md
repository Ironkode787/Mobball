# SPEC — M1 "The Hook"

Goal (docs/10 §M1): ranks R0→R3 playable as a progression game — bare alley grows via
purchases, dirty/clean laundering works, Nights end in The Count, the Bench exists (lite),
Heat leads to a survivable Raid, everything saves. Three lanes; interfaces below are LAW —
if an interface is wrong, report to the orchestrator, don't redesign unilaterally.

Design context: docs/01 (sessions, Bench, tilt), docs/02 §2 R0–R3, docs/03 (economy),
docs/04 + specs/ledger-data.md (upgrades), docs/05 §1–2 (jobs, raids).

## Shared architecture

- **`Game` autoload** (`game/flow/game.gd`, flow lane; orchestrator wires it into
  project.godot): owns the session. Members: `wallet: Wallet`, `heat: HeatMeter`,
  `stats: Stats`, `respect: int`, `rank: int`, `bench: Bench`, `night_no: int`,
  `state: StringName` (&"attract" &"night" &"count" &"ledger"), `save: SaveGame`.
  **Single money path:** all table scoring calls
  `Game.earn_switch(group: StringName, base_value: BigMoney, meta: Dictionary = {})`
  which applies `stats.value_add/value_mult`, heat multiplier, combo multiplier, emits
  `Events.dirty_earned(amount, group)`, feeds `heat.on_dirty_earned`, updates jobs/combo.
- **`Stats`** (`game/meta/stats.gd`, meta lane): pure recompute from
  `owned: Dictionary[String, int]` (node id → level). API (exact):
  `recompute(owned)`, `value_mult(group) -> float`, `value_add(group) -> BigMoney`,
  `hardware_unlocked(id) -> bool`, `flag(id) -> bool`, `idle_rate_total() -> BigMoney`,
  `launder_rate() -> float`, `launder_cap() -> BigMoney`, `passive_wash_per_sec() -> float`,
  `pocket_money() -> BigMoney`, `safe_hours() -> float`, `bench_slots() -> int`,
  `ball_saves() -> int`, `tilt_leans() -> int`, `flipper_power() -> float`,
  `collect_minutes() -> float`, `job_slots() -> int`, `kickbacks() -> Array[StringName]`,
  `bribe_unlocked() -> bool`. `value_mult(&"all")` folds into every group.
- **Events additions** (orchestrator will merge; propose in reports if more needed):
  `night_started(night_no)`, `night_ended(summary: Dictionary)`, `upgrade_purchased(id, level)`,
  `rank_changed(rank)`, `respect_changed(total)`, `raid_started`, `raid_ended(survived)`,
  `job_assigned(id)`, `job_completed(id, respect)`, `laundered(amount)`, `combo_changed(n)`,
  `skill_shot`, `guy_pinched(guy)`, `guy_bailed(guy)`, `dirty_earned(amount, group)`.
- **Hardware visibility contract:** every optional hardware node in the table registers an id
  (`bumper_2`, `bumper_3`, `slingshots`, `inlane_guides`, `rollovers`, `spinner_numbers`,
  `wire_bank`, `laundromat_loop`, `storefront_laundromat/pizzeria/pawn`, `orbit_left`,
  `kickback_left`, `bribe_target`; `kickback_unlock`/`bribe_unlock` effects bridge to the
  `kickback_left`/`bribe_target` hardware ids inside Stats) and shows/enables itself iff
  `Game.stats.hardware_unlocked(id)`
  (re-checked on `Events.upgrade_purchased`). The M0 debug table + feel sims keep working
  via a `debug_all_hardware` flag that bypasses the check.

## Lane 1 — FLOW (`game/flow/`, `game/ui/count/`, `game/ui/hud`, flow tests/sims)

- **State machine:** attract (tap to start) → night → count → (ledger ↔ count) → night…
- **Night:** field up to 3 available guys sequentially from the Bench; ball serve via existing
  spawn; drain = `guy_pinched`; ball_saves from Stats give an 8 s save window after launch;
  after last guy → count. Idle trickle: `stats.idle_rate_total()` accrues to dirty each
  second during a night.
- **Bench lite** (`bench.gd`, pure logic + tests): roster starts 4 guys (names from
  `game/content/names.json`, seeded RNG); `available()`, `pinch(guy)`, `bail(guy) -> cost`
  (dirty, `Rates` escalator), `night_tick()` (pinched guys walk after sitting out 1 night);
  auto-hire free nobody when roster short. No traits in M1.
- **The Count** (plain Control UI, palette colors, default font): count-up lines — dirty
  earned, laundered tonight (incl. pocket money auto-clean), clean balance, respect gained,
  jobs done, headline (from `game/content/headlines.json` — first matching condition,
  random variant, placeholder substitution); roster strip with
  bail buttons; buttons: THE LEDGER / NEXT NIGHT. Safe collect banner on boot if offline
  earnings > 0.
- **Laundering wiring:** laundromat loop pass → `wallet.launder_fraction(stats.launder_rate(),
  remaining_cap)`; passive wash per second while storefront armed; pocket money at count.
- **Respect & ranks:** sources — skill shot ☆1, combo ≥3 ☆2, jobs per data; thresholds
  R1=10 R2=50 R3=150 (`rank_changed`, knocker sound, headline). Rank gates tier purchase
  (meta lane checks `Game.rank`).
- **Combos:** chaining hits of *different* groups within 4 s: chain n multiplies those hits
  ×1.5^(n−1), cap ×8; `combo_changed`.
- **Skill shot:** when `rollovers` unlocked: one lit lane cycles 1.5 s; entering through lit
  lane at ball-entry = ☆1 + $200 × rank-scale, `skill_shot`.
- **Raid v1:** on `heat.raid_triggered`: 45 s mode — table darkens (modulate), 4 cop standup
  targets spawn near lanes (table lane exposes spawn API — coordinate via hardware contract
  `cop_targets`), magnet pull toward drain every 6 s (1.2 s audio+visual telegraph,
  `AudioDirector.play(&"siren")`). Survive current guy 45 s → `raid_ended(true)`, payout
  +25 % of held dirty as clean, heat reset 30. Guy drains → `raid_ended(false)`,
  `wallet.confiscate_dirty(0.3)`, heat 0. Either way targets despawn.
- **Save** (`save.gd`): JSON at `user://save1.json`, atomic (temp+rename), 2 rolling backups,
  `version` field + migration hook; saves on count/purchase/rank/app-pause; loads on boot
  (salvage newest valid). Contents: wallet, respect, rank, night_no, owned upgrades, bench
  roster state, heat value, safe timestamp + collected flag, jobs progress, rng seeds.
  Offline accrual on load via `Offline.accrue(stats.idle_rate_total(), elapsed,
  cap = rate × safe_hours × 3600)`.
- **Jobs v1** (`jobs.gd`): load `game/content/jobs.json`; `job_slots()` active slips chosen
  seeded-random from eligible (rank + hardware); checks implemented for the ids in the data
  file; completed → respect, replace next night.
- **HUD (real):** top strip — dirty (red), clean (green), heat bar with band ticks, respect
  ☆, night #, combo flash. Palette hexes from docs/07 §1, default font, no art.
- **Sims:** `tests/sim/night_sim.tscn` — scripted full night on the progression table with
  a purchased-set fixture: launch/score/drain ×3, assert count summary math, respect, bench
  states; raid path: force heat 100, survive branch + fail branch assertions; save/load
  round-trip equality of the whole Game state dict.

## Lane 2 — META (`game/meta/`, `game/ui/ledger/`, meta tests)

- **Loader** (`upgrades.gd`): parse/validate `game/content/upgrades.json` per
  specs/ledger-data.md (unique ids, known kinds, requires exist, costs parse, tier 0–7).
  Invalid data = loud failure at boot in dev (push_error + safe skip in release).
- **Stats** as specified above; pure, tested (`tests/test_stats.gd` with a fixture owned-set
  asserting every getter, incl. per_level stacking and &"all" folding).
- **Reveal engine** (`reveal.gd`): tracks reveal conditions (rank / event / purchased /
  dirty_held) from Events; a node is `hidden | facedown | revealed`; facedown when its
  reveal is unmet but any `requires` parent is revealed.
- **Ledger UI v1** (functional, palette-styled, no art): full-screen overlay; board pans
  (drag) over a dark cork-toned ground; nodes laid out by (branch column × tier row) with
  a deterministic auto-layout; red string lines (quadratic bezier with midpoint sag)
  between requires pairs; card states: facedown (back pattern), revealed (name+cost),
  affordable (pushpin glint = simple pulse), owned (stamp + level badge for repeatables).
  Tap card → docket panel: name, flavor, cost, table_change, effect summary, BUY / MAXED /
  locked reason (rank too low / needs X). Buying: spend clean, level up, `Stats.recompute`,
  `Events.upgrade_purchased`, `AudioDirector.play(&"stamp_thunk")` (fail-silent for now).
  "Next affordable" compass button scrolls to cheapest buyable.
- **Data tests** (`tests/test_upgrades_data.gd`): validate the shipped JSON thoroughly —
  this is the guard rail for all future data-only tuning commits.

## Lane 3 — TABLE (`game/table/`, table tests/sims)

- Convert the M0 layout into the progression table `game/table/table_main.tscn`: base =
  walls, flippers, drain, ONE bumper, plunger (fixed 0.75 power until `plunger_bands` flag).
  All other hardware present-but-dormant behind `hardware_unlocked` (hidden, collision off).
- New hardware (all emit via `Game.earn_switch` groups, values from specs/ledger-data.md
  economics: bumper 10, sling 5 base, spinner 25/spin-segment, rollover 25, wire target 150,
  bank complete 1K, storefront collect = `collect_minutes` × its idle rate, orbit 500,
  laundromat pass = launder event not dirty):
  - `spinner_numbers` — left lane spinner: rotation-driven repeat switch (spin decays with
    friction), spin count tracked for future Wire draws.
  - `rollovers` — 3 top-arch lanes with lit-state API for the skill shot (flow drives which
    is lit).
  - `wire_bank` — 3 standup targets; all-down = bank complete + reset after 2 s.
  - storefronts ×3 — 3-target drop banks across the midfield; bank down = "door open" 6 s:
    ball through door = collect (emits `storefront_collected(id)`) then re-arm 20 s.
    Laundromat's door doubles as the `laundromat_loop` wash pass.
  - `orbit_left` — left orbit lane with entry/exit gates (switch sequence = orbit complete).
  - `kickback_left` — outlane kicker, 60 s cooldown, fires once per unlock rules.
  - `bribe_target` — donut-shop standup, active only when `bribe_unlocked()` and affordable;
    hit = `Game.heat.bribe()` flow callback (expose signal, flow wires cost).
  - `cop_targets` — 4 dormant standups + a drain-ward magnet impulse API for Raid mode
    (flow drives; table provides `set_raid_active(bool)` and telegraph visuals).
- Keep `alley_debug.tscn` + feel sims green (debug_all_hardware). Layout may rearrange the
  M0 midfield to fit storefronts; keep flipper/sling/lane geometry identical.
- **Sim:** `tests/sim/table_growth_sim.tscn` — boot table with staged owned-sets (bare / T1 /
  T2 / T3 fixtures): assert hardware presence/absence, collision actually disabled when
  dormant, a scripted ball hitting each unlocked piece produces the right
  `Events.switch_hit`/`dirty_earned` amounts (spot-check stats multipliers), storefront
  collect/re-arm cycle, orbit sequence detection.

## Acceptance (all lanes)

`bash tools/check.sh` fully green (existing feel sims included). A scripted "first 10
minutes" happy path must work headless end-to-end (flow lane owns this sim): boot fresh →
attract → night 1 → earn → count shows pocket-money clean → buy `muscle.real_plunger` +
`rackets.trash_2` in ledger → night 2 has bumper 2 live and chargeable plunger → save →
reload → state intact.
