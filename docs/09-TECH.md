# 09 — Tech

> **INTERNAL MEMO** — *"The machine is load-bearing. Do not let the physics guy quit."*

## 1. Engine: Godot 4.x (recommended)

| Criterion | Godot 4 | Unity | libGDX |
|-----------|---------|-------|--------|
| License / fees | MIT, zero cost, aligns with our open-asset ethos | runtime fee history, closed | Apache, but DIY everything |
| 2D physics for pinball | Good base + easy custom fixed-tick; CCD available | excellent but overkill 3D bias | Box2D solid, more glue code |
| Android export | one-click, small APKs (~35MB base) | heavier | manual but fine |
| 2D glow/shaders/particles | strong (WorldEnvironment glow, canvas shaders, GPUParticles2D) | strong | DIY |
| Layered audio | `AudioStreamSynchronized` + `AudioStreamInteractive` built-in — our music system nearly for free | plugins | DIY |
| Iteration speed | GDScript hot-reload, tiny team friendly | good | slow |

Decision: **Godot 4.5+, GDScript** (typed), C++/GDExtension reserved for the physics hot loop
*only if profiling demands it*. Risk hedge: the physics layer is isolated behind one interface
(`BallSim`) so a custom solver could replace Godot physics without touching game code.

## 2. Physics (the sacred module)

- **Fixed 120 Hz sim tick**, render 60fps with interpolation. Ball = custom integrator or
  RigidBody2D with CCD enabled + speed clamp; **swept-sphere test** against flipper surfaces at
  high relative speed (belt + suspenders vs. tunneling).
- **Flippers:** animated kinematic bodies driven by an authored angular-velocity curve (not
  motors — curves give designed, deterministic feel), with proper impulse transfer from surface
  velocity at contact point. 50ms input buffer; coyote-window on release passes.
- **Materials:** per-surface restitution/friction (steel, rubber, wood, felt); rubber gets a
  velocity-dependent restitution curve (real pinball rubbers are lively at low speed, deadish at high).
- **Nudge:** applies a table-space impulse to ball + a spring-damped cabinet offset (visual);
  Inspector suspicion consumes discrete "leans" (see [01](01-CORE-GAMEPLAY.md) §5).
- **Determinism-adjacent:** fixed tick + recorded-input replay for QA (bug repros, feel
  regression tests: golden replays must land within tolerance after physics changes).
- Magnet hardware (cranes, cop magnets) = scripted force fields with authored telegraph timing.

## 3. Project architecture

### Session state flow

The shipped host has a deliberate pre-Night state between attract and live play. The flow
model prepares the Night's data before it creates the table session:

```
attract ── tap START ──▶ roll_call ── START NIGHT ──▶ night ── last guy ──▶ count
                              │                                  ▲            │
                              │                                  │            │
                              └─ jobs + Bench + ordered          └────────────┘
                                 prepared_lineup                  NEXT NIGHT
                                                               (opens Roll Call)
count ◀──────────────────────────────────────────────────────────▶ ledger
```

`Game.open_roll_call()` rolls **Tonight's Work**, advances the Bench between Nights, and enters
`roll_call`; `RollCallScreen` renders the active job slips and available guys. The player's
selection append order is the serve order (there is no drag-reorder contract). The Start action
calls `Game.start_prepared_night()`, which resolves selected persistent guy IDs against the
free Bench, removes invalid/duplicate/held entries, and stores the ordered result in
`Game.prepared_lineup` before entering `night`. `NightController` reads that array and binds
each guy to the ball in that order. The target is `min(3, available.size())`; the Bench keeps at
least one guy available and the Night safely serves a shorter lineup. Direct test/sim callers
may still call `Game.start_night()`, which uses the first available guys and bypasses the screen.

### Ball identity data path

`BallDesign` (`game/core/ball_design.gd`) is a plain deterministic descriptor derived from a
guy's persistent numeric ID. `NightController._bind_guy()` attaches the guy to the ball and
applies that descriptor; `BallPreview` (`game/ui/ball_preview.gd`) consumes the same descriptor
for Roll Call. Both call `BallDesign.draw_ball()`, the shared live/preview renderer, so metallic
base, high-contrast band geometry, crest, and orientation cannot drift between UI and physics.
An empty guy uses the anonymous descriptor and remains the plain steel debug ball. The design
descriptor is presentation data, not save data.

```
res://
  game/
    core/           # Ball, BallDesign, flipper, nudge, camera, haptics, input
    economy/        # currencies, BigMoney, rates, Heat, offline calc (pure logic, no nodes)
    flow/           # Game state machine, Roll Call handoff, Night, jobs, Bench, modes
    content/        # upgrades.json, jobs.json, names and other data-driven content
    table/
      segments/     # one scene per zone (alley, club, docks...)
      hardware/     # bumper, spinner, storefront bank, ... (reusable, skinnable)
    ui/             # Roll Call/BallPreview, ledger corkboard, count, HUD, rapsheet
    audio/          # stem stacks, event map, buses
    sim/            # headless autoplayer + balance harness (runs in CI)
```

**Data-driven everything:** upgrades are the Ledger data set; jobs are loaded from
`game/content/jobs.json` and carry their exact objective (`desc`), Respect reward, check ID,
rank gate, and optional hardware gate. Roll Call displays those data fields and derives the
`ANY GUY` / `ONE GUY` / `FIRST GUY` / `ALL NIGHT` scope label from the check contract. Boss
phase tables, city rule-twists, and other content remain data-driven; designers (us) tune
without changing the session or renderer contracts. The economy core is engine-agnostic pure
GDScript: it runs headless in CI for balance sims (§7).

## 4. The growing table (modular segments)

The core table scene exposes **anchor sockets** (Marker2D + collision seam contracts). A zone
segment = one packed scene implementing a `TableSegment` interface: `geometry`, `shots[]`
(named shot definitions with switch sequences), `light_rig`, `music_stem_id`, `idle_rate`.
Buying/rank-up = instantiating the segment at its socket + construction animation + camera
bounds update + navmesh-for-little-guys refresh. Upgrades *within* a zone swap child scenes
(trash can → dumpster) or toggle rule plates. City remixes = same segments, different params/
skins + one `CityRules` resource (signature rule hooks: `on_earn`, `on_drain`, `on_light`...).

Shot detection: named switch sequences with time windows (real pinball logic), one `ShotEngine`
consuming switch events — combos, jobs, and bosses all subscribe to shots, not raw collisions.

## 5. Audio implementation

Stems: one `AudioStreamSynchronized` per city with 8 synced OGG stems, volumes automated by
game state; transitions via `AudioStreamInteractive` clips (raid slam, count, legit hours).
SFX: event map resource (event id → sample set + bus + priority); voice = per-character sample
banks with pitch jitter. Priority system caps simultaneous mechanics sounds (oldest-quietest
steal) — overload stays mixed (P4).

## 6. BigMoney

Mantissa+exponent struct (float64 mantissa, int exp, normalized), supporting add/mul/compare/
format ("$4.20T"). All economy math uses it from day one (retrofitting big-number types is
misery). Serialization as `{m, e}` pairs.

## 7. The autoplayer & balance CI

A headless bot plays Nights at three skill profiles (duffer/decent/shark: shot-success
probabilities + decision policies) over the full economy sim. CI runs 1,000 simulated
player-days nightly and reports: time-to-rank curve, first-prestige day, active:idle ratio,
skilled:unskilled ratio, currency inflation, dead upgrades (never bought), dominant strategies
(one build >70% optimal = nerf flag). The tuning targets in [03](03-ECONOMY.md) §9 are CI
assertions with tolerance bands — balance regressions fail the build like bugs. This is the
single highest-leverage tool for an incremental game and it's cheap because the economy core
is headless by construction.

## 8. Performance budget (min spec: 2019 mid-ranger, e.g. Snapdragon 660/4GB)

| System | Budget |
|--------|--------|
| Physics tick | ≤ 2.0 ms (single ball) / ≤ 4.5 ms (5-ball reunion) |
| Draw calls | ≤ 120 (atlas everything; segments share materials) |
| Live Light2D | ≤ 8 real lights; all other "neon" = emissive sprites + baked glow |
| Particles | pooled GPUParticles2D, ≤ 12 live emitters, LOD by device tier |
| Audio voices | ≤ 24, priority-stolen |
| Memory | ≤ 900 MB RSS; stems streamed |
| Battery | thermal test: 30 min endgame session without clock-down on min spec |

Sensory-overload mode is a *content* promise, not a perf exception — the audit script counts
live emitters/lights/voices per state and fails if over budget. Device tiers auto-detected
(glow quality, particle LOD, haptics richness).

## 9. Save system

- JSON snapshot (versioned, migration functions per version bump), atomic write + rolling
  3-slot backup; checksum to detect corruption (restore newest valid).
- Offline earnings computed from wall-clock delta, clamped by Safe cap; **no punishment for
  clock weirdness** — negative deltas just no-op (P5, and it kills a whole cheating arms race:
  single-player, let them).
- Cloud save via Google Play Games Services v2 (post-MVP milestone); autosave at Count, rank-up,
  purchase, app-pause.

## 10. Android specifics

Target API level per current Play requirements at ship; portrait locked; `immersive` fullscreen;
haptics via `Input.vibrate_handheld` patterns (fallback: simple); notch/cutout-safe HUD zones;
Play Games achievements mapped to milestone reveals; APK/AAB with texture-tier asset packs if
size demands. Analytics: privacy-light, on-device funnel counters + opt-in crash reporting
only (P5 extends to data).

## 11. Testing strategy

Golden-replay physics regressions (§2) · economy CI (§7) · segment smoke tests (each zone
loads, all shots completable by scripted bot) · soak test (4h autoplay, memory/thermal) ·
device lab: min/mid/flagship trio. Manual feel reviews are scheduled work (M0 gate & every
physics PR): feel is a feature with an owner.
