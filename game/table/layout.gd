class_name Layout
extends RefCounted
## The machine's blueprint: every position on the main playfield, in table units (1 unit =
## 10 cm; x right, z toward the player, y up off the felt; the origin is the playfield's
## centre). Hardware reads its place from here, the sims aim at these numbers, and the
## geometry test proves the routes between them pass a ball.
##
## The shot map (from the flippers, steep to shallow):
##   left bat  → bribe notch · Staircase ramp · Fat Tony's bank · payphones · right orbit
##   right bat → left orbit (spinner) · Lucky's bank · docks (R5) · bribe notch
##   both      → the centre alley into Nonna's and the pop nest under the top lanes

# ------------------------------------------------------------------ the cabinet -----
const PLAY_LEFT := -2.6                 ## outer wall centre lines
const PLAY_RIGHT := 2.6
const PLAY_TOP := -5.4                  ## apex of the arch
const PLAY_BOTTOM := 5.4                ## the drain lip
const OUTER_THICK := 0.12
const GUIDE_THICK := 0.05
const POST_RADIUS := 0.035
const ARCH_CENTER := Vector2(0.0, -2.8)
const ARCH_RADIUS := 2.6
## Wall heights above the felt.
const WALL_HEIGHT := 0.40
const GUIDE_HEIGHT := 0.32
const CABINET_HEIGHT := 0.9
const GLASS_HEIGHT := 1.9

# ------------------------------------------------------------------ shooter lane -----
const DIVIDER_X := 2.17
const DIVIDER_THICK := 0.06
const DIVIDER_TOP := -2.9
const DIVIDER_BOTTOM := 5.05
const LANE_FLOOR_Z := 5.15              ## the plunger rests the ball against this
const GATE_TOP := -4.15                 ## the one-way flap between the lane and the field
const GATE_BOTTOM := -2.95
const SPAWN := Vector2(2.37, 4.975)

# ------------------------------------------------------------------ orbits -----
## The channel's inner guide is a ring whose ends meet the lane guides tangentially.
const RING_CENTER := Vector2(-0.175, -2.8)
const RING_RADIUS := 1.975
const RING_LEFT_FROM_DEG := 180.0
const RING_LEFT_TO_DEG := 250.0
const RING_RIGHT_FROM_DEG := 320.0
const RING_RIGHT_TO_DEG := 360.0
const LANE_GUIDE_L_X := -2.15
const LANE_GUIDE_L_BOTTOM := -0.10
const LANE_GUIDE_R_X := 1.77
const LANE_GUIDE_R_BOTTOM := -0.50
const SPINNER_AT := Vector2(-2.36, -1.7)
const LANE_WIDTH_L := 0.36
const ORBIT_L_ENTRY := Vector2(-2.36, -0.9)
const ORBIT_L_EXIT_DEG := 225.0         ## on the channel's centre line, from the ring centre
const ORBIT_R_ENTRY := Vector2(1.96, -1.2)
const ORBIT_R_EXIT_DEG := 315.0
const CHANNEL_MID_RADIUS := 2.28

# ------------------------------------------------------------------ top lanes -----
## The Drop-Off ladder is a physics ladder: a ball climbing the arch from the shooter gate
## peels off the outer wall the moment it drops under ~5 u/s, and falls into whichever
## funnel is under it. Two funnel lanes hang from the ring on the ascending (right) side —
## a soft plunge dies early into lane 3, a medium one carries to lane 2 at the apex — and a
## hard plunge never peels: it laps the arch and comes down the left orbit lane over
## rollover 1. Every plunge lands in exactly one of the three.
const TOP_POST_DEG: PackedFloat32Array = [320.0, 285.0, 250.0]
const TOP_POST_BOTTOM: Array = [
	Vector2(0.83, -4.05), Vector2(0.10, -4.05), Vector2(-0.62, -4.05),
]
const ROLLOVER_AT: Array = [Vector2(-2.36, -3.30), Vector2(-0.30, -4.42), Vector2(0.50, -4.38)]

# ------------------------------------------------------------------ pops -----
## Offset from the lane exits so a lane ball meets a can on its shoulder, never its crown.
const BUMPER_AT: Array = [Vector2(0.05, -2.85), Vector2(-0.62, -3.42), Vector2(0.78, -3.40)]
const BUMPER_SCALE: PackedFloat32Array = [1.08, 1.0, 0.92]

# ------------------------------------------------------------------ targets -----
const BRIBE_AT := Vector2(1.32, -3.85)
const BRIBE_FACE := Vector2(-0.55, 0.835)
const BRIBE_LENGTH := 0.36
const WIRE_AT: Array = [Vector2(1.42, -2.35), Vector2(1.53, -1.90), Vector2(1.64, -1.45)]
const WIRE_FACE := Vector2(-0.366, 0.930)
const WIRE_LENGTHS: PackedFloat32Array = [0.36, 0.34, 0.32]
const TARGET_LENGTH := 0.34
const TARGET_THICK := 0.06

# ------------------------------------------------------------------ the Block -----
const STOREFRONT_AT: Array = [
	Vector2(-1.25, -0.55),     # Lucky's Laundromat: left, off the right flipper
	Vector2(0.0, -1.55),       # Nonna's Pizzeria: centre, under the pop nest
	Vector2(1.30, 0.10),       # Fat Tony's Pawn: right, off the left flipper
]
const STOREFRONT_FACING: Array = [Vector2(0.435, 0.900), Vector2(0.0, 1.0), Vector2(-0.464, 0.886)]
const STOREFRONT_RAKE_DEG: PackedFloat32Array = [0.0, 12.0, 0.0]
const STOREFRONT_IDS: Array[StringName] = [
	&"storefront_laundromat", &"storefront_pizzeria", &"storefront_pawn",
]
const STOREFRONT_SIGNS: Array[StringName] = [&"LUCKY'S", &"NONNA'S", &"FAT TONY'S"]

# ------------------------------------------------------------------ bottom -----
## The shooter lane lives inside the arch, so the playable field runs from the left wall to
## the divider and its centre line is left of the cabinet's. The bottom assembly — flippers,
## slings, inlanes, outlanes, drain — is symmetric about MIRROR_X (`mx()`).
const MIRROR_X := -0.185
const FLIPPER_SPREAD := 0.95            ## pivots at MIRROR_X ± this
const FLIPPER_Z := 4.40
const FLIPPER_PIVOT_L := Vector2(MIRROR_X - FLIPPER_SPREAD, FLIPPER_Z)
const FLIPPER_PIVOT_R := Vector2(MIRROR_X + FLIPPER_SPREAD, FLIPPER_Z)
const INLANE_GUIDE_DX := 1.965          ## MIRROR_X ± : -2.15 on the left, 1.78 on the right
const INLANE_GUIDE_TOP := 2.15
const INLANE_GUIDE_BOTTOM := 3.15
const INLANE_END := Vector2(1.05, 4.10) ## the return sweep lands here (offset from MIRROR_X)
const SLING_OUTER_TOP := Vector2(1.535, 2.55)
const SLING_OUTER_BOTTOM := Vector2(1.535, 2.98)
const SLING_INNER := Vector2(0.865, 3.42)
const OUTLANE_DRAIN_Z := 3.6
const KICKBACK_AT := Vector2(-2.345, 3.5)
const KICKBACK_SIZE := Vector2(0.32, 0.30)
const CENTRE_DRAIN_AT := Vector2(MIRROR_X, 5.15)
const CENTRE_DRAIN_SIZE := Vector2(1.2, 0.35)
const DRAIN_Z := 5.4
const MAGNET_AT := Vector2(MIRROR_X, 4.55)
const DIRECTOR_AT := Vector2(0.2, 2.9)

# ------------------------------------------------------------------ the Staircase -----
## Mouth on the left flipper's line; the wireform climbs the right side, over the right
## orbit lane and the shooter gate, onto the Club deck (segments/club_deck.gd owns the deck).
const STAIR_MOUTH := Vector2(0.60, 0.95)
const STAIR_MOUTH_SIZE := Vector2(0.46, 0.30)
const STAIR_PATH: PackedVector3Array = [
	Vector3(0.60, 0.0, 0.95), Vector3(0.65, 0.12, 0.40), Vector3(0.85, 0.30, -0.30),
	Vector3(1.15, 0.46, -0.90), Vector3(1.55, 0.60, -1.50), Vector3(1.95, 0.70, -2.05),
	Vector3(2.32, 0.80, -2.60), Vector3(2.44, 0.88, -3.20), Vector3(2.44, 0.92, -3.60),
	Vector3(2.36, 0.94, -3.95), Vector3(2.15, 0.95, -4.18), Vector3(1.85, 0.94, -4.28),
	Vector3(1.55, 0.92, -4.25),
]

# ------------------------------------------------------------------ the Commission -----
const SEDAN_RAIL_Z := -0.95
const SEDAN_RAIL_FROM_X := -0.7
const SEDAN_RAIL_TO_X := 0.85
const SEDAN_PARK := Vector2(0.1, -0.95)
const SEDAN_LENGTH := 0.72
const SEDAN_THICK := 0.24
const GOON_AT: Array = [Vector2(-0.95, -2.2), Vector2(0.95, -2.35), Vector2(0.0, -0.55)]
const GOON_RAKE_DEG: PackedFloat32Array = [18.0, -18.0, -12.0]
const TRUCK_PARK := Vector2(0.0, 0.35)
const TRUCK_LENGTH := 0.64
const TRUCK_THICK := 0.28
const DOOR_FRONT_Z := 1.25
const DOOR_BACK_Z := 0.85
const DOOR_FRONT_X: PackedFloat32Array = [-0.75, 0.0, 0.75]
const DOOR_BACK_X: PackedFloat32Array = [-0.40, 0.40, 1.10]
const DOOR_RAKE_DEG := 12.0

# ------------------------------------------------------------------ the raid -----
const COP_AT: Array = [
	Vector2(-1.55, -1.25), Vector2(1.05, -0.75), Vector2(0.75, 1.75), Vector2(-0.25, 2.6),
]
const COP_RAKE_DEG: PackedFloat32Array = [22.0, -22.0, 22.0, -22.0]
const BRIEFCASE_SPOTS: Array = [Vector2(-0.35, 1.6), Vector2(0.0, 0.35), Vector2(0.25, 2.7)]
const BRIEFCASE_CLEAR := 0.5
const BRIEFCASE_CLEAR_VEHICLE := 0.9

# ------------------------------------------------------------------ helpers -----


static func p3(plan: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(plan.x, h, plan.y)


static func plan(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Yaw about +Y that turns a node's local +Z onto the plan direction `d` (x, z).
static func yaw_facing(d: Vector2) -> float:
	return atan2(d.x, d.y)


static func ring_point(deg: float, radius: float = RING_RADIUS) -> Vector2:
	var a := deg_to_rad(deg)
	return RING_CENTER + Vector2(cos(a), sin(a)) * radius


static func arch_point(deg: float, radius: float = ARCH_RADIUS) -> Vector2:
	var a := deg_to_rad(deg)
	return ARCH_CENTER + Vector2(cos(a), sin(a)) * radius


static func mirror(p: Vector2) -> Vector2:
	return Vector2(MIRROR_X * 2.0 - p.x, p.y)


## A bottom-assembly point given as an offset from the mirror line: s = +1 right, -1 left.
static func mx(offset: Vector2, s: float) -> Vector2:
	return Vector2(MIRROR_X + s * offset.x, offset.y)


static func inlane_guide_x(s: float) -> float:
	return MIRROR_X + s * INLANE_GUIDE_DX
