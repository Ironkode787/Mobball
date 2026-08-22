# SPEC — M0 "The Feel" (feel/table workstream)

Owner lane: `game/core/`, `game/table/`, `game/ui/`, `game/main.tscn`, `tests/sim/`,
plus feel-related `tests/test_*.gd`. Design context: `docs/01-CORE-GAMEPLAY.md` §1–2, §5;
`docs/09-TECH.md` §2. The deliverable is a **playable single-screen debug table** where the
ball, flippers, plunger and nudge feel like an expensive mechanical object.

## Scene architecture

```
game/main.tscn            Main (Node2D)
  ├─ Table (alley debug table — game/table/segments/alley_debug.tscn)
  ├─ CameraRig (game/core/camera_rig.gd — static for M0, follow code present but locked)
  ├─ InputController (game/core/input_controller.gd)
  └─ HUD (CanvasLayer — game/ui/debug_hud.gd)
```

- **Ball** `game/core/ball.tscn/.gd` — RigidBody2D, circle radius `Feel.BALL_RADIUS`,
  `continuous_cd = CCD_MODE_CAST_SHAPE`, speed clamped to `Feel.BALL_MAX_SPEED` in
  `_integrate_forces`. Layer 2; masks walls/flippers/hardware. Draw a plain circle with
  `_draw` (light gray, darker rim) — no textures in M0.
- **Flipper** `game/table/hardware/flipper.tscn/.gd` — AnimatableBody2D
  (`sync_to_physics = true`), capsule-ish polygon of length `Feel.FLIPPER_LENGTH`, wide at
  pivot (r≈26) tapering to tip (r≈16). Rotation driven in `_physics_process` along an
  authored ease curve from `FLIPPER_REST_DEG` to `FLIPPER_UP_DEG` in `FLIPPER_UP_TIME`
  (ease-out: fast start), back in `FLIPPER_DOWN_TIME`. Mirrored for right side.
  Emits `Events.flipper_fired`; calls `AudioDirector.play(&"flipper_up")` / `&"flipper_down"`.
  Honor `Feel.INPUT_BUFFER`: a press up to 50 ms before the flipper becomes actionable
  still fires.
- **Plunger** — ball spawns in the shooter lane; holding `plunger` charges 0→1 over
  `PLUNGER_CHARGE_TIME` (with 4 audible ratchet detents via `&"plunger_pull"`), release
  applies up-impulse `power * PLUNGER_MAX_IMPULSE` (`&"plunger_launch"`). HUD shows charge.
- **Nudge/tilt** `game/core/nudge.gd` — nudge actions apply `Feel.NUDGE_IMPULSE` to the
  ball (direction: left nudge pushes ball right/up-ish, etc.) plus a 6 px spring-damped
  visual offset of the whole Table node. Each nudge adds a tilt warning; warnings decay one
  per `TILT_DECAY_SECONDS`. Exceeding `TILT_MAX_WARNINGS` → `Events.tilted`: flippers dead
  until ball drains, `&"tilt"` plays. Warnings emit `Events.tilt_warning` + `&"tilt_warning"`.
- **InputController** — desktop keys (registered by Feel) AND touch: left/right halves of the
  bottom 70 % of screen are flipper zones (multi-touch), swipe-down-hold-release in the
  shooter-lane region is the plunger, quick horizontal flick is a nudge.
- **CameraRig** — Camera2D; M0: fixed framing of 1080×1920. Keep a `follow_enabled` flag +
  vertical-follow-with-lookahead code path ready for M1 but off.
- **Debug HUD** — top strip: dirty-cash debug counter (increments from `Events.switch_hit`
  by hardware value), ball count, tilt warnings, FPS, and current ball speed. Plain
  `Label`s, default font, no styling effort.

## The M0 debug table (single screen, 1080×1920)

Static walls are `StaticBody2D` polygons/segments, layer 1. Layout (px, y down):

- Playfield: x ∈ [40, 940]; shooter lane x ∈ [946, 1040] (wall at x=940–946 from y=340 to
  y=1840); top arch: circular arc from (40, 460) over (490, 60) to (1040, 460) — the lane
  feeds the arch; a one-way gate flap at (940, 350) lets the ball into the playfield, not back.
- Bumpers (layer 4), `game/table/hardware/bumper.tscn`: centers (490, 460), (368, 640),
  (612, 640), radius 46. On contact: impulse ~900 away from center, brief scale-pulse of the
  drawn circle, `Events.switch_hit(&"bumper_N", ball, strength)`, `&"bumper_hit"`, value 10.
- Slingshots, `game/table/hardware/slingshot.tscn`: triangles left (196,1450)-(300,1450)-
  (196,1640) and mirrored right; kicker face fires impulse ~750 on hit, cooldown 80 ms,
  `&"sling_hit"`, `Events.switch_hit(&"sling_l"/&"sling_r")`, value 5.
- Flippers: pivots left (312, 1700), right (668, 1700) (tips gap ≈ 66 px).
- Inlane/outlane guides: vertical walls x=150 and x=830 from y=1450 to y=1650, and short
  guides x=252 / x=728 from y=1520 to y=1660 forming in/out lanes.
- Drain: Area2D across y=1870, x ∈ [40,940] → `Events.ball_drained`, `&"drain"`, ball
  despawns; auto-respawn in shooter lane after 1 s (`&"ball_spawn"`).
- Draw everything with `_draw()` primitives: felt-green playfield rect (#1E3D2F), ink walls,
  brass-ish flippers (#C9A227), dark bumper circles with brass rims. Placeholder aesthetics,
  real palette (docs/07 §1).

All hardware emits through `Events.switch_hit` with a per-piece `value: int` — the debug HUD
sums it. No economy code in this workstream.

## Acceptance — tests/sim/feel_sim.tscn (+ script)

A scripted scenario runner stepping real physics headless; prints each scenario PASS/FAIL,
quits 0 only if all pass:

1. **No-tunnel soak**: spawn ball, auto-launch full power, then 30 s of scripted chaotic
   flipping (both flippers every 0.3–0.7 s) + a nudge every 3 s. Assert every physics tick:
   ball stays inside table bounds (40−4 ≤ x ≤ 1040+4, −4 ≤ y ≤ 1930); on drain, respawn and
   continue. Zero escapes required.
2. **Cradle**: place ball at rest 40 px above the left flipper mid-bat; let it settle 2 s
   with flipper held up? No — flipper at REST. Assert ball comes to rest ON the flipper
   (speed < 20 px/s, position within bat AABB) and stays 2 s without falling through.
3. **Flip strength**: from that cradle, fire the flipper; assert ball's upward speed within
   [1400, 3600] px/s within 100 ms, and ball reaches y < 1000 before falling back.
4. **Plunger bands**: launch at power 0.35 / 0.7 / 1.0; assert three distinct apex heights,
   monotonically higher, and full power reaches the top arch region (y < 300).
5. **Tilt**: 4 rapid nudges → `tilted` fired; flippers refuse input until drain; after
   respawn flippers work again.
6. **Input buffer**: queue a flip 30 ms before (simulated) actionability — flipper must fire.
   (Actionability in M0 = always, so simulate by pressing during the *down-stroke* within
   buffer of reaching rest: it must re-fire immediately on arrival.)

Also add plain unit tests where logic is node-free (e.g. `tests/test_flipper_curve.gd` for
the rotation-curve math, `tests/test_tilt.gd` for warning decay logic if factored purely).

## Hard rules

- `bash tools/check.sh` green before you're done; the sim scenarios above are the deal.
- Every tuning value used must come from `game/core/feel.gd` — extend it as needed.
- You may adjust layout coordinates ±10 % where physics demands (e.g. sling geometry), but
  keep the topology (lanes, gaps, arch, one-way gate) exactly as specified.
- No textures, no fonts, no art assets in this milestone. `_draw()` primitives only.
- Do not touch `project.godot`, `docs/`, `specs/`, `game/economy/`, `game/audio/`,
  `tools/audiogen/`. Call `AudioDirector.play()` freely per the event names in
  `specs/audio-pipeline.md` §4 — it fail-silents until the audio lands.
