# The machine — a real 3D pinball table

> Status: shipped on `claude/table-layout-visuals-v9c9sy`. Replaces the 2D simulation and the
> earlier "3D mirror of the 2D table" entirely.

## 1. What this is

KINGPIN's table is now simulated in 3D with Jolt at real pinball scale and dressed as a 90s
Bally/Williams-style machine. The ball is a rigid sphere that rolls on a waxed, inclined
playfield; flippers are kinematic bats swept along an authored curve; ramps are steel channels
the ball climbs or rolls back out of under its own energy; the Club and the Penthouse are
raised playfields inside the same cabinet; City Hall is the crowning wireform loop over the
back. Nothing is scripted about where the ball goes — every switch is an `Area3D` reading a
real trajectory.

The career (ranks, upgrade ids, jobs, modes, economy) is unchanged: the table still publishes
the same properties, methods and signals to the flow lane through `TableAPI`, and every
Ledger id still owns a piece of hardware that stands up when bought.

## 2. Units and physics

| Thing | Value |
|---|---|
| Unit | 1 unit = 10 cm (a 20.25" × 42" playfield is 5.14 × 10.7 units) |
| Ball | radius 0.135 (27 mm), mass 1, CCD on, never sleeps |
| Incline | 6.5° — the playfield root is rotated; gravity is the project's 98.1 u/s² |
| Physics | Jolt, 240 Hz, penetration slop 0.004, speculative contact 0.02 |
| Surfaces | playfield friction 0.09 (waxed wood), walls 0.14/bounce 0.18, rubber 0.40/0.58, steel rails 0.08/0.15 |
| Flippers | length 0.78, 45 ms to full extension, curve in `FlipperCurve`; the Club's pair is half size |
| Plunger | 34 u/s at full pull; starter bands 0.55 / 0.58 / 0.80 |

All constants live in `game/core/feel.gd`; all positions in `game/table/layout.gd`.

## 3. The shot map (plan coordinates: x right, z toward the player)

```
        ┌──────────────── arch (r 2.6 about (0,-2.8)) ───────────────┐
        │  orbit channel between the arch and the RING (r 1.975)     │
        │  funnel lanes 3 (320°→285°) and 2 (285°→250°) hang off it   │
   left │      spinner   ● pops (-0.62,-3.42) (0.78,-3.40)  bribe   │ right lane
   lane │      rollover1 (0.05,-2.85)  ▬ payphones ▤▤▤ (1.4..1.6)   │ x 1.80–2.14
 x -2.54│              NONNA'S (0,-1.55) faces down                  │ shooter lane
  –2.18 │  LUCKY'S (-1.25,-0.55)              FAT TONY'S (1.30,0.10) │ x 2.20–2.54
        │  docks yard (R5)             Staircase mouth (0.60,0.95)   │
        │  x -2.5..-1.35 z 0..2         ramp up the right side       │
        │  kickback │ sling            alley            sling │       │
        │           ╲ ◢ bat (-1.135,4.4)   bat (0.765,4.4) ◣ ╱       │
        └──────────────────────── drain ─────────────────────────────┘
   upper storey (0.9 u up): PENTHOUSE x -2.45..-0.55 | CLUB x 0.55..2.20, z -5.25..-3.35
```

The play axis is `Layout.MIRROR_X = -0.185` because the shooter lane lives inside the arch;
the bottom assembly is symmetric about it.

Both side lanes end in a **lane-return rail** that turns a ball coming down the lane in toward
the inlane, so an orbit comes back to the flipper; the outlanes stay open to balls arriving
from the middle. On the left the same rail fences the Docks' water from the lane.

**From the left bat (steep → shallow):** bribe notch · Staircase mouth · Fat Tony's · payphones
· right orbit (Truck Route). **From the right bat:** left orbit (Getaway Loop, spinner,
rollover 1) · Lucky's · the docks gate (R5) · bribe notch. **Both:** the centre alley into
Nonna's and the pops.

**The Drop-Off** is a physics ladder: a plunged ball climbs the arch and peels off the outer
wall the moment it drops under ~5 u/s, into whichever funnel is under it. Soft (0.55) dies
into lane 3, medium (0.58) carries to lane 2 at the apex, hard (≥0.68) never peels — it laps
the arch and comes down the left lane over rollover 1. Measured with
`tests/probe_machine.tscn`; asserted by `tests/sim/machine_sim.tscn`.

**Upstairs.** The Staircase (mouth on the left bat's line) climbs the right edge over the
payphones, the right lane and the shooter gate, and enters the Club deck through its right
wall; a shot under ~24 u/s rolls back out of the mouth. The deck holds the roulette bowl, the
slot reels, the High Roller and back-room saucers and two mini flippers; its exit chute at the
bottom-left drops into a wireform down the left-centre corridor to the left inlane. The
Penthouse stairs leave the deck diagonally through its top-left corner (a mini-flipper shot),
sweep along the back of the machine in one arc at deck height and come into the Penthouse
through the open corner behind its back wall, so a 20 u/s shot arrives with pace. The stairs'
exit points straight at the City Hall ring's funnel mouth: with enough speed the ball climbs
out over the room's left wall, sweeps round the outside of the room and comes back in over
the front wall to land at the right; a ball that fails rolls back out onto the room floor,
slides off the raked backs of the two chair targets and leaves by the front-left chute into
the left lane above the spinner.

**The Docks** (R5) are a walled yard low on the left behind a one-way gate off the left lane.
A gangway slides arrivals off the wall, the bed beam falls away to the right, and everything
ends in the cargo scoop: a kicker that lifts the ball into a wireform soaring over the crane's
gantry and dropping it into the left lane above the Getaway Loop entry. The quay is a one-way
flap so the outlane kickback throws a ball up into the yard. The water off the pier's left
corner is fenced from rolling balls by a bollard rail; only the crane puts a ball in it.

## 4. Code map

| Path | Role |
|---|---|
| `game/core/feel.gd`, `ball.gd`, `plunger.gd`, `banded_plunger.gd`, `nudge.gd`, `camera_rig.gd` | physics core (all vectors in table space) |
| `game/table/layout.gd` | every position |
| `game/table/segments/progression_table.gd` | the machine: cabinet, walls, hardware, drains, career unlocking, flow API |
| `game/table/segments/club_deck.gd`, `penthouse.gd`, `city_hall.gd`, `docks.gd` | the four career segments |
| `game/table/hardware/*.gd` | flipper, bumper, slingshot, standup/drop target, target bank, storefront, rollover, spinner, orbit lane, one-way gate, kickback, hold saucer, drain/crane magnet, roulette, slot reels, containers, boss target, briefcase, build-in, wall piece, ramp lane |
| `game/table/wall_builder.gd` | polylines → box + post colliders + rail mesh |
| `game/table/hardware/ramp_lane.gd` | swept steel channel (trimesh, flared mouth, inward lips) + mouth/crest sensors |
| `game/table/look/` | material library, mesh builders, the cobblestone playfield shader, dressing (lamp rows, plastics, toys, apron cards, GI) |

Conventions: a piece is a `Node3D` placed with `Layout.p3()`; targets face their local +Z
(`Layout.yaw_facing`); `set_hardware_active()` makes a piece invisible **and** collision-free;
`visual_state()` publishes the lamp state; balls are addressed in table space through
`Ball.kick / set_velocity / place / table_position`.

## 5. Gate

`tools/check.sh` imports, runs `tests/test_*.gd`, boot-smokes `main.tscn`, then runs every
`tests/sim/*.tscn` with `--fixed-fps 60` (240 Hz physics, four ticks a frame, no wall-clock
pacing): `feel_sim` (roll, serve, flip pace, trap, 25 s soak), `machine_sim` (ladder,
Staircase, both orbits, kickback and outlanes, docks, Penthouse and dome, dormancy),
`night_sim_first10` (the first ten minutes end to end) and `night_sim` (Nights, raids, bench,
save, Safe). Screenshots: `tools/shot.sh out.png res://tests/shot_machine.tscn` with
`SHOT_VIEW=bare|block|full`, `SHOT_CAM=high|deck`, `SHOT_BALL=x,z`.

## 6. Known limits and next

- The continuous Real Plunger's lane-2 window is a few percent wide: a genuine skill shot.
- The bosses' cars ride their rails and the raid's cops and magnets work, but their fights have
  not yet been re-tuned to 3D speeds; `BossTarget.min_speed` gates are in u/s now.
- Build-in scaffolding is a lift-and-tarp animation; the little guys with hammers are gone.
- The Club's roulette bowl is a functional primitive; the slot cabinet, pops, cars, vans and
  storefront toys are generated meshes now (specs/meshes.md), the bowl and crane are next.
