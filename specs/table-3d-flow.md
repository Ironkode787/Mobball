# Table redesign — 3D presentation and the 90s shot map

> Status: shipped in the `claude/table-layout-visuals-v9c9sy` branch. Owner: table workstream.

## 1. What changed and why

The M1–M3 playfield was a flat vector drawing of a prototype: hairline walls, banks scattered at
odd angles, a right "orbit" with no lane, ramps meandering across the middle. Two things were
done together, because one without the other would still read as a prototype:

1. **The playfield is rendered in 3D.** The 2D simulation under `game/table/` is unchanged in
   kind — every collider, sensor, rule and sim still lives there — and `game/table/view3d/`
   renders it as a lit, perspective, multi-storey machine. The 2D table hides its own drawing
   (`table.visible = false`), the `Camera3D` is slaved to the 2D `CameraRig`, and every
   `CanvasLayer` (HUD, screens, feedback) keeps painting on top. `KINGPIN_TABLE_2D=1` restores
   the flat renderer for debugging.
2. **The layout was redrawn as a 90s Williams-style machine** (`progression_table.gd` constants).
   The physics constants in `Feel` are untouched except `PLUNGER_MAX_IMPULSE` (3900 → 4000, the
   ball speed cap) so the Drop-Off can reach the far top lane.

## 2. The shot map (table px, +y down)

```
        ┌──────────────── arch (outer wall, r≈512) ─────────────────┐
        │   orbit channel: 104–165 px between the arch and the RING │
        │  ring r=320 @ (500,569): left arm 180°→235°, right 305°→0°│
        │        ╲ post  post  post  post ╱   ← 3 TOP LANES hang    │
        │  spinner ╲ [1] [2] [3] ╱  bribe   off the ring (y 255→400)│
   left lane│      (440,600)(560,600)  ● ●    payphones ▤ ▤ ▤ right lane
   x 58–171 │          (500,690) ●  pops        (735–775, 640–840) │ x 829–933
        │                  NONNA'S (490,890) ▬▬▬  faces down        │
        │   LUCKY'S (345,1030) ▬▬▬                Staircase mouth   │
        │   faces the right flipper           (625,1160) ⌒ ramp up  │
        │   docks (R5) ┌────┐            FAT TONY'S (745,1085) ▬▬▬ │
        │              └────┘            faces the left flipper     │
        │     kickback │ sling      open centre alley      sling │  │
        │              ╲  ◢ flipper L        flipper R ◣  ╱       │
        └──────────────────── drain (storm grate) ──────────────────┘
```

**From the left flipper (steep → shallow):** the bribe notch (700,470) threading the Wire and
Fat Tony's · the Staircase mouth · Fat Tony's bank · the payphone bank · the right orbit
("Truck Route", lane guide x=820, y 569→1000).

**From the right flipper:** the left orbit/spinner lane ("Getaway Loop", guide x=180) ·
Lucky's bank · the docks entrance (down the left lane, R5) · the bribe notch.

**Both flippers:** the centre alley up into Nonna's and the pop nest; the pops feed the top
lanes' exits back onto the flippers.

**The Drop-Off (skill shot).** The plunger exits the one-way gate onto the arch and rides the
channel. Its power picks the outcome, probed headless with `tests/probe_plunger.tscn`:

| starter band | power | lands in |
|---|---|---|
| short pull | 0.945 | lane 3 (right) |
| middle pull | 0.970 | lane 2 (centre) |
| long pull | 0.990 | lane 1 (left) |
| Real Plunger, full | 1.000 | the whole orbit, down the spinner lane |

## 3. Layout rules the geometry test enforces (`tests/test_table_geometry.gd`)

- Lanes pass a 56 px ball with 20 px to spare: both orbit lanes, the channel over the lanes,
  every top lane at its narrow end, the route between the left guide and the Block, the
  route between Lucky's lower end and the docks roof.
- Gaps are routes or walls, never ball-sized: the notch beside each outer post, Fat Tony's
  against the right guide, each payphone's back against the guide.
- Bank ends stay 40 px off an 80 px centre alley; bank rows keep 76 px between them.
- No pop bumper sits under a lane exit (a ball would pogo in the lane); the nest is offset so
  a lane ball meets a can on its shoulder.
- Banks face their flipper; Nonna's is raked 12° so nothing parks on its roof.

## 4. The 3D presentation (`game/table/view3d/`)

| File | Role |
|---|---|
| `table_space.gd` | px→m (×0.01), storey heights: main field 0, Club/Penthouse/City Hall +1.15 m |
| `view3d_mesh.gd` | SurfaceTool builders: rail (rounded polyline), post, prism, tube, box, disc, ring |
| `view3d_materials.gd` | procedural felt/wood/brass/steel/rubber/lamp/neon materials, ball skins from `BallDesign` |
| `table_view_3d.gd` | environment, key/fill light, lamp budget (6 omni), camera slaving, room (cabinet, backbox, storey slabs), proxy registry, screen projector |
| `proxies/*.gd` | one proxy per hardware class; `wall_proxy.gd` is the catch-all for any `StaticBody2D` |

Rules:

- **Geometry comes from colliders.** Walls are extruded from `WallBuilder` chains or the
  body's `CollisionShape2D`s; a proxy never invents a surface the ball cannot touch.
- **State comes from `visual_state()`.** Lamps read the hardware's own token: armed lights an
  invitation, active flashes, disabled is dark, danger is police blue. Dropped targets sink.
- **The ball rides ramps for real.** `RampProxy3D.height_at()` is the wireform's profile and the
  lift `BallProxy3D` applies, so what climbs is what shows.
- **Feedback stays anchored.** `Presentation.projector` is this view; `_screen_position()`
  projects through the 3D camera, so hit numbers still land on the ball.
- **Budget.** ≤ 6 real omni lights (storefront neon, flipper GI); everything else is emissive.
  One draw call per wall body. Shadows: one directional light.

## 5. Sims re-tuned to the new geometry

Only fixture constants changed: parking spots (`SAFE_POINT`s) moved into the open centre
alley, the first-ten coaching point sits over the starter can, the plunger band expectations
follow the new bands, and the club sim's refused-ramp check accepts a ball that has already
come back below the mouth. `feel_sim` (the M0 alley) is untouched and still green.

## 6. Next

- Bench identity on the 3D ball uses a generated equirect skin; a crest decal pass would make
  the guys as recognisable as in Roll Call.
- The Docks, Penthouse and City Hall get landmark props now; the Club deck still wants its
  roulette bowl and slot-reel cabinet dressed.
- Build-in (the little guys with hammers) is still 2D-only and therefore hidden in 3D.
- Camera: a slightly lower pitch during multiball and a nudge kick in 3D (the 2D offset
  carries through the canvas transform already).
