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

## Meshes & Blender

- Table toys are generated meshes: `tools/meshgen/toys.py` (bpy) → `bash tools/meshgen/build.sh`
  → `assets/meshes/*.glb` (+ `tools/meshgen/preview/*.png`). Pieces load them through
  `ToyLib` and keep their primitive look as the fallback; see `specs/meshes.md` for the list,
  the node contract (`Lamp*`, `Art*`) and the budgets. Never hand-edit a `.glb`.
- Blender binary (this environment): `/workspace/tools/blender/blender` (4.2 LTS). For
  interactive modelling, `tools/blender/serve.sh` starts Blender (under Xvfb when headless)
  with the MCP for Blender addon listening on 9876; `.mcp.json` registers the `blender` MCP
  server (`uvx blender-mcp`) that drives it.

## Textures

- Surface textures are CC0 PBR sets from Poly Haven, fetched by `python3 tools/texgen/fetch.py`
  into `assets/textures/<id>/` (diffuse / nor_gl / rough JPG + `.import` with mipmaps). The
  playfield shader (`game/table/look/playfield.gdshader`) and `MaterialLib.pbr()` use them
  when present and fall back to the procedural look when not; new sets go in `SET` in the
  fetch script and get a row in `assets/ASSETS.md`.

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
| `game/table/` (keep `tests/sim/feel_sim` and `tests/sim/machine_sim` green; `table_main.tscn` path is contract — see `specs/table-3d-flow.md`), `tests/shot_machine*`, `tests/probe_machine*` | table workstream |
| `tools/audiogen/`, `assets/audio/`, `game/audio/`, `tests/test_audio_assets.gd` | audio workstream |

Do not edit outside your lane; if you need a change elsewhere (a new Events signal, a Feel
constant, a check.sh tweak), note it in your final report instead.

## Git

Workstream agents do **not** commit or push — the orchestrator reviews, commits, pushes.

## Physics & display invariants (do not change without design sign-off)

- The table is a real 3D machine (specs/table-3d-flow.md): Jolt physics at 240 Hz, physics
  interpolation ON, 1 unit = 10 cm, the playfield root inclined `Feel.PLAYFIELD_PITCH_DEG`
  under the project's 98.1 u/s² gravity. Every position lives in `game/table/layout.gd`,
  every tuning number in `game/core/feel.gd`; the ball API is table-space (`Ball.kick`,
  `set_velocity`, `place`, `table_position`).
- Base viewport 1080×1920 portrait, `canvas_items` stretch, expand aspect.
- Physics layers (3D): 1 walls · 2 ball · 3 flippers · 4 hardware · 5 zones. Dormant hardware
  is invisible **and** collision-free (`Dormant`, `set_hardware_active`).
- Renderer: GL Compatibility (low-end Android target). Colliders come first; every mesh is
  built from the same numbers (`WallBuilder`, `RampLane`), never the other way round.
- Screenshots: `tools/shot.sh out.png res://tests/shot_machine.tscn` (Xvfb + software GL);
  `SHOT_VIEW=bare|block|full`, `SHOT_CAM=high|deck`, `SHOT_BALL=x,z`. Physics probe:
  `godot --headless --fixed-fps 60 --path . res://tests/probe_machine.tscn`.
- Input actions are registered **in code** (see `game/core/feel.gd`), not in `project.godot`.

## Audio contract

Gameplay code never loads audio files directly — it calls
`AudioDirector.play(event: StringName, opts: Dictionary = {})`. The event vocabulary is
defined in `specs/audio-pipeline.md`; the audio workstream maps events to synthesized assets
in `assets/audio/`. Missing assets must fail silent (log once), never crash.
