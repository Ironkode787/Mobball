# KINGPIN — engineering conventions

Godot 4.5 game (GDScript), Android-first portrait pinball × incremental. Design lives in
`docs/` (00–11) — **read the doc relevant to your task before coding**. Specs for active
workstreams live in `specs/`.

## Build & verify

- Godot binary (this environment): `/workspace/tools/godot/godot`
- **Before declaring any work done, run `bash tools/check.sh`** — it imports the project,
  runs the headless test suite, and boot-smokes the main scene. All three must pass.
- Tests live in `tests/test_*.gd`; each defines `func run(t: TestCtx) -> void` and uses
  `t.ok / t.eq / t.near / t.almost`. Run alone via
  `/workspace/tools/godot/godot --headless --path . --script tests/run_tests.gd`.
- Shipping the closed beta: `bash tools/ship.sh`. It runs the source and device gates, creates
  a signed Play AAB with the operator-supplied upload key, then installs a Bundletool-generated
  universal APK on the connected release-test device for a packaged-runtime smoke test. The
  build has no debug-key fallback; see `release/CLOSED_BETA.md` for required credentials.

## Code style

- Typed GDScript everywhere (`var x: float`, typed params & returns). Tabs for indentation
  (Godot convention). Files snake_case. One class per file; `class_name` for shared types.
- Signals over polling; cross-system events go through the `Events` autoload (signal bus).
- Tuning constants live in `game/core/feel.gd` (the `Feel` autoload) — never scatter magic
  numbers through gameplay code.
- Keep `.tscn` files minimal; build dynamic content in code. Reusable table hardware is a
  scene; one-off wiring is code.
- Comments: only for constraints code can't express. No changelog comments.

## Ownership map (parallel workstreams — stay in your lane)

| Area | Owner (M1 wave) |
|------|-------|
| `project.godot`, `CLAUDE.md`, `docs/`, `specs/`, `game/content/`, `tests/run_tests.gd`, `tests/t.gd`, `game/core/` (frozen — request changes via report), `game/economy/` (frozen) | orchestrator only |
| `game/flow/` (public surface of `game.gd` is contract-locked), `game/ui/count/`, `game/ui/hud*`, `game/main.gd`, `game/main.tscn`, `tests/sim/night_sim*`, flow tests | flow workstream |
| `game/meta/` (`stats.gd` API contract-locked), `game/ui/ledger/`, `tests/test_stats.gd`, `tests/test_upgrades_data.gd` | meta workstream |
| `game/table/` (keep `tests/sim/feel_sim` green; `table_main.tscn` path is contract), `tests/sim/table_growth_sim*` | table workstream |
| `tools/audiogen/`, `assets/audio/`, `game/audio/`, `tests/test_audio_assets.gd` | audio workstream |

Do not edit outside your lane; if you need a change elsewhere (a new Events signal, a Feel
constant, a check.sh tweak), note it in your final report instead.

## Git

Workstream agents do **not** commit or push — the orchestrator reviews, commits, pushes.

## Physics & display invariants (do not change without design sign-off)

- 120 Hz physics tick, physics interpolation ON, gravity via `project.godot`.
- Base viewport 1080×1920 portrait, `canvas_items` stretch, expand aspect.
- Physics layers: 1 walls · 2 ball · 3 flippers · 4 hardware · 5 zones.
- Renderer: GL Compatibility (low-end Android target).
- Input actions are registered **in code** (see `game/core/feel.gd`), not in `project.godot`.

## Audio contract

Gameplay code never loads audio files directly — it calls
`AudioDirector.play(event: StringName, opts: Dictionary = {})`. The event vocabulary is
defined in `specs/audio-pipeline.md`; the audio workstream maps events to synthesized assets
in `assets/audio/`. Missing assets must fail silent (log once), never crash.
