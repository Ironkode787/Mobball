# SPEC — M2 "The Empire" (DRAFT — lanes launch after M1 integration sign-off)

Goal (docs/10 §M2): ranks R4–R5 playable — the Club deck with real casino games and the
Casino Wash, the Docks with smuggling, crew specialists, guy traits, Collection Rounds,
the Wire draws, mystery briefcases, the first two Commission bosses, and the Ledger grown
to ~80 nodes. Plus the **balance simulator** that turns placeholder numbers into tuned ones.

Design context: docs/02 §2 (R4–R5), docs/03 (casino EV rules), docs/04 (branches C/D/E
tiers 4–5), docs/05 §3–6 (rounds, draws, briefcases, heists, bosses).

## Lane split (five, launched in two sub-waves)

### Sub-wave 1 (parallel)

**TABLE-2 — vertical growth + the Club deck** (`game/table/`)
- Segment socket system per docs/09 §4: the playfield grows UPWARD — table height becomes
  1920→~2800 px with the Club deck top-right; CameraRig vertical follow finally turns ON
  (it exists, untested — budget time for tuning look-ahead at 120 Hz).
- Club hardware: the Staircase ramp (right ramp with a Clean-Hit gate), roulette pocket
  wheel (spinning hole-set the ball physically drops into — the flagship physics toy),
  slot drop-target reels (3×3), High Roller saucer (hold-to-raise-multiplier), Club
  mini-flipper pair riding the same side inputs, back-room saucer (Family Meeting starter).
- Construction animation v1: scaffolding fade-in + little-guys hammer loop when a zone
  or major hardware arrives (data: `table_change` strings already ship per node).

**FLOW-2 — modes & chance** (`game/flow/`, `game/ui/`)
- Casino game logic (odds per docs/03 §3, house edge 8% → Influence-reducible; the Cooler
  pity rule), **Casino Wash**: bets stake dirty, wins pay clean.
- The Wire draws every 90 s against the spinner-count ticket; Collection Rounds (all 3
  storefronts armed → 25 s frenzy); mystery briefcases (70/20/10, trench-coat delivery guy,
  leaves after 60 s); Family Meeting 2-ball multiball (needs multiball plumbing — the M0
  single-ball assumptions in table/nudge/camera get their collections pass here).
- Guy traits v1 (the 7 in names.json) + guy leveling; Fight Night stays T4-gated data.

**SIM — the balance autoplayer** (`game/sim/`, new lane)
- Headless bot playing full Nights at three skill profiles (shot-success probabilities +
  policy: earn/wash/risk allocation), driving the REAL Game/Stats/economy stack at big
  time steps; nightly CI target table from docs/03 §9 asserted with tolerances.
- First deliverable: a tuning report on current data (R0 first-purchase time, rank pacing,
  active:idle ratio, dead nodes) + a proposed data-only patch to upgrades.json/rates.gd
  PLACEHOLDER numbers for design review.

### Sub-wave 2 (after sub-wave 1 integrates)

**META-2 — content growth** (design authors data; meta lane extends systems)
- Ledger tiers 4–5 (~50 new nodes incl. ★ Juice Loans wiring, Two Books toggle UI,
  Fight Night, The Tunnel), specialists as CREW-branch hires with per-specialist powers
  (Skids, Nussbaum, Big Sal, The Professor, Rosa, Whispers Cohen at T4; Manny, Eddie Odds
  at T5), reveal clusters + the mid-Count stinger flip.

**BOSS-1 — the Commission encounters** (`game/flow/bosses/`, table hooks)
- Sammy Two-Flippers (R3→R4 gate): flipper-jam pulses with wrench telegraph; spoil:
  Sammy's Spare. The Butcher (R4→R5): armored bumpers + circling meat truck; spoil:
  Cold Storage. Economy paused during fights (pure skill, docs/05 §6).

**AUDIO-3** — casino soundscape (chips, cards, wheel clatter — synthesized), specialist
instrument voices (tuba/clarinet/alto sax/violin/oboe/cello phrase banks — the
muted-trumpet-mob system, docs/08 §5), velocity layers for mechanical events (impact opt),
radio_squelch telegraph cue, `legit` state exotica (if Going Legit lands in meta scope).

## Contracts to pin before launch (orchestrator)

- Multiball: Ball ownership moves from single refs to collections — audit list from M0
  report (AlleyDebugTable.ball, one-way gate latch, Flipper.set_ball, nudge.set_ball,
  camera target). Define `BallRegistry` in core (orchestrator patch, core is frozen).
- Segment socket interface (`TableSegment` grows `socket_id`, `music_stem`, `light_rig`).
- Casino game API between table hardware (physical results: pocket index, reels state)
  and flow logic (bets, payouts): hardware reports outcomes, flow owns money — same
  single-money-path discipline as earn_switch.
- Specialist powers touch core systems (Enforcer kickback cooldown, Planner aim line):
  effects vocabulary grows `specialist_*` kinds; core patches by orchestrator only.

## Explicitly deferred to M3

Docks/smuggling geometry (if M2 scope tightens, Docks slips — Club is the retention beat),
heists, elections, the Rat, federal heat, prestige.
