# SPEC — M3 "The Fall & The Rise"

Goal (docs/10 §M3): ranks R5–R7 playable and the first prestige loop closed — Docks and
smuggling, heists, the Penthouse and the remaining Commission, Elections, Federal Heat +
the RICO raid, Empire Mode, the 5-ball Family Reunion, The Rat, and Skip Town → Juice →
Black Book → city 2 (New Carthage, 1927). Design context: docs/02 §2 R5–R7, docs/05 §5–9,
docs/06 (whole), specs/m2-content.md patterns.

## Sub-wave A (launch first — independent)

**SIM-2** (`game/sim/`): model M2 — casino (stakes/wash/jackpots per Casino.CasinoRules,
read the knobs, don't re-guess), Family Meeting frequency and x2 windows, Commission gates
(a fight costs a Night; win probability per profile — duffer 0.25/0.55, decent 0.6/0.8,
shark 0.9/0.95 per fight as opening bids), specialists and traits in the purchase policy,
the club-era SimTable rows (ramps/casino weights). Re-sweep 14 days × 3 profiles × 3 seeds.
Report: docs/03 §9 targets again, dead nodes over the 54-node catalog, casino EV in
practice (design target: max Influence investment lands +2–5% EV — if the shipped
+16.3%-at-cap breaks the economy, propose the knob change), heat liveliness post-rulings,
and T6–T7 cost-band recommendations for the content I author next.

**TABLE-3** (`game/table/`, camera bounds auto-extend): the next growth ring.
- **THE DOCKS** (docs/02 §2 R5): lower-LEFT mini-field in the space left of the shooter
  lane's mirror — concretely: carve the region x∈[40,420], y∈[1150,1440] as a gated
  sub-area behind a one-way gate off the left channel (geometry freedom, but the sacred
  lower third and the orbit/spinner channel stay). Inside: three container drop stacks
  (raked, per the anti-park rules), a crane magnet on a gantry (scripted force field with
  telegraph, reusing DrainMagnet patterns), the cargo ramp back to midfield (RampLane),
  and a pier edge — a SECOND outlane-grade drain risk unique to the zone (drains there
  pinch like any drain; kickback never covers it). Hardware ids: `docks`, `containers`,
  `crane`, `cargo_ramp`. Groups: containers pay `smuggling` (new group, base 400).
- **THE PENTHOUSE shell** (R6, docs/02 §2): the negative-y space LEFT of the Club
  (sky_left socket): full-width room y∈[-880,-460] with FIVE chair standup targets around
  a long table (`commission_chairs`, group `penthouse`, base 2K each), a Sit-Down saucer
  (capture 1s, signal `sitdown_entered`), and a second staircase/ramp from the deck.
  Modes come in FLOW-3; you ship geometry + switches + signals.
- **Truck Route**: right orbit (mirror of getaway where the divider allows — if the
  shooter lane blocks a full right orbit, a partial upper-right loop is acceptable; id
  `orbit_right`, group `orbit`).
- **Construction animation v1**: when hardware flips dormant→active, play a 1.2s build-in
  (scaffold rect + hammer-tap particles + rising fade) instead of popping in. Table-side
  only, no Count dependency.
- Sims: extend growth sim fixtures with T5/T6 sets; docks no-tunnel soak incl. crane
  active; pier drain pinches correctly; penthouse chair switches; camera reaches the
  penthouse and never shows void. ALL existing sims stay green.

## Sub-wave B (after A lands + orchestrator authors T5-docks/T6/T7 content)

**FLOW-3**: smuggling runs (timed container sequences, hot cargo = big dirty + flat heat),
HEISTS (docs/05 §5 — the five targets as scripted shot-sequence modes with quiet/loud
approach and inside-man traits; fail-forward), Commission chairs persistence (claiming
chairs across Nights), ELECTIONS (docs/05 §8 — district objectives → Election Night frenzy
→ Administration term), Federal Heat (docs/03 §4: meter stage 2, accrues from empire size)
+ the RICO raid (docs/05 §9 — 3 phases incl. the wiretap audio-dropout phase), EMPIRE MODE
(City Hall circuit → everything lit ×10, 60s), 5-ball Family Reunion, Mystery Briefcases
(table drop support now exists via docks?), The Rat arc (docs/05 §7 — clue Nights, accuse
via target choice).

**META-3**: the BLACK BOOK — Juice currency (never resets), the prestige-permanent tree
(docs/06 §3 — new branch "blackbook" costing juice ints), Skip Town flow support
(what carries over), Museum relic schema, spoil trophies rendered on the board.

**BOSS-2**: Madame Fortuna (rule-reversal phases), The Silent Don (audio-mute phase with
full visual/haptic redundancy), The Old Kingpin (your build armed against you — reuses
jam/armored/tunnel-eats-ball hooks).

**AUDIO-4**: boss audio backlog (boss_start/boss_phase/boss_beaten/wrench_telegraph),
heist/election/empire stingers, RICO wiretap dropout automation, Skip Town's stem-shedding
sequence (the reverse-growth moment — docs/08 §1), city-2 1927 arrangement (hot jazz combo
+ Victrola crackle per docs/08 §7) as a second stem set the director can swap.

**CITY-2** (last): New Carthage remix — the booze-crate rule (docs/06 §4), sepia palette
swap, era masthead. Rides on everything above; likely the M4 boundary.

## Orchestrator pre-work for sub-wave B

- Author docks/penthouse content nodes (T5–T6) + T6/T7 economy after SIM-2 reports.
- Prestige data: `game/content/blackbook.json` (docs/06 §3 table) + Juice formula in Rates.
- Rulings queue: casino EV ceiling (await SIM-2), FROZEN_SCALE stands at 1.0, frenzy
  forfeit stands, spinner-visit dead zone (plunger skill window) revisit on device.
