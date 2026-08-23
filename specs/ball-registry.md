# SPEC — BallRegistry (multiball core plumbing, orchestrator-implemented)

Everything single-ball in M0/M1 assumed exactly one live ball (M0 report audit:
`AlleyDebugTable.ball`, the one-way gate latch, `Flipper.set_ball`, `nudge.set_ball`,
`camera.set_target`). Family Meeting (specs/m2-content.md §4) needs collections. One new
core autoload, minimal diffs elsewhere.

## `Balls` autoload (`game/core/ball_registry.gd`)

- `register(ball: Ball, guy: Dictionary = {}) -> void` / `unregister(ball) -> void`
  (idempotent; unregister on drain AND on `tree_exiting` as a leak guard).
- `live() -> Array[Ball]` (valid instances only), `count() -> int`,
  `primary() -> Ball` — the **lowest** live ball (highest y): the one nearest danger.
  Pinball convention: the camera and the player's attention belong to the ball that can
  die next.
- `guy_for(ball) -> Dictionary` — the Bench guy riding that ball (multiball = named guys).
- Signals: `ball_registered(ball)`, `ball_unregistered(ball)`, `count_changed(n)`,
  `last_ball(ball)` (emitted when count falls back to 1 — ends multiball modes).

## Consumer diffs (kept small on purpose)

- **NudgeController**: `set_ball(ball)` stays as the compat path; when the registry is
  non-empty it applies the impulse to ALL live balls and ignores the single ref. Tilt
  logic unchanged (per-cabinet, not per-ball).
- **CameraRig**: `set_target(ball)` stays; each physics tick it retargets
  `Balls.primary()` when count ≥ 1. When count > 1: zoom out one step (docs/01 §2's
  multiball framing) and frame the centroid, weighted 70/30 toward primary; restore on
  `last_ball`.
- **Tables**: `spawn_ball()` grows `spawn_ball(guy := {})`; every spawn registers, drain
  area unregisters before `ball_lost`. The one-way gate latch and any per-ball state key
  by ball instance id (Dictionary), not a single field.
- **Flipper**: cradle/`set_ball` becomes nearest-live-ball queries via the registry
  (only used for cradle detection — verify with feel_sim scenario 2 unchanged).
- **NightController**: a drained ball pinches ITS guy (`Balls.guy_for`); the Night ends
  only when the LAST live ball drains with no guys left to serve; ball-save windows are
  per-ball (spawn time stamped per instance). Guy binding also calls `ball.apply_guy_design(guy)`
  so the persistent guy ID selects the same deterministic `BallDesign` face used by Roll Call's
  `BallPreview`; empty/anonymous bindings retain the plain steel debug face.

## Timing contracts (learned in M2 integration — binding)

- `guy_for(ball)` stays valid THROUGH every unregister signal (`ball_unregistered`,
  `count_changed`, `last_ball`); the guy entry is erased only after they all fire.
- `last_ball` fires from inside `unregister`, i.e. possibly BEFORE the table's `ball_lost`
  reaches gameplay and before a ball-save has decided anything. Consumers ending a mode on
  `last_ball` must settle one physics tick before acting (a save may repopulate the count).
- Spawning during a physics callback (`body_entered` etc.) throws
  "Can't change this state while flushing queries" — queue `spawn_extra_ball`/re-serves
  to the next physics tick, as the table's own auto-respawn does.

## Invariants & acceptance

- All existing sims green unchanged (single-ball behavior must be bit-identical: with
  count == 1, `primary()` IS the one ball and every compat path routes as before).
- New sim scenario (goes in the flow lane's night sim when Family Meeting lands): two
  registered balls → nudge moves both; camera zooms out; draining one pinches the right
  guy and continues the Night; draining the last ends it; `last_ball` fires exactly once.
- Registry is pure bookkeeping: it never moves, spawns, or frees a ball itself.
