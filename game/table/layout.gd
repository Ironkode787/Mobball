class_name Layout
extends RefCounted
## The machine's blueprint (docs/19): every position on the board in table units (1 unit =
## 10 cm; x right, z toward the player, y up off the felt; the origin is the playfield's
## centre). Hardware reads its place from here, the sims aim at these numbers.
##
## Bands, bottom to top: the Gutter (bats, slings, lanes), the Street (the insert field),
## the Block (the shot line), Uptown inside the ring road (the Club, the Alley, Lucky's Tower)
## and the crown outside the arch (City Hall, Pier 9).
##
## The shot map follows the bats (measured by tests/probe_shots.tscn): a flip from mid-bat leaves
## at ~30° cross-field, one off the tip at 11–22°, so each bat's shots fan across the far side:
##   left bat,  mid → tip:  Truck Route (+30°) · Beat Cop (+22°) · Lucky's (+15°) · Fat Tony's (+11°)
##   right bat, mid → tip:  Getaway (−30°) · the Wire (−22°) · Staircase (−15°) · Nonna's (−11°)
## and the Alley, between the two banks, takes what comes up the middle.

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
const WALL_HEIGHT := 0.40
const GUIDE_HEIGHT := 0.32
const CABINET_HEIGHT := 0.9
const GLASS_HEIGHT := 1.9

# ------------------------------------------------------------------ shooter lane -----
const DIVIDER_X := 2.17
const DIVIDER_THICK := 0.06
const DIVIDER_TOP := -2.8               ## above this the divider curves: the Truck Route's outer rail
const DIVIDER_BOTTOM := 5.05
const LANE_FLOOR_Z := 5.15              ## the plunger rests the ball against this
## THE TRUCK ROUTE'S OUTER RAIL: the divider curves on round the ring road — concentric with the
## ring where it leaves the divider, then easing out to run into the arch at the apex — so a ball
## up the right lane rides round instead of meeting the arch head-on, and a Getaway coming down
## rides onto it off the arch. The plunge joins the ring road through a one-way flap in the rail
## (Space Cadet's launch lane): every plunge travels the Truck Route's path.
const RAIL_RADIUS := DIVIDER_X - (-0.185)   ## about RING_CENTER, where it leaves the divider
const RAIL_EASE_FROM_DEG := 345.0           ## concentric below this (toward 360°)
const RAIL_TOP_DEG := 270.0                 ## meets the arch here
const RAIL_GATE_FROM_DEG := 305.0           ## the launch flaps span the rail between these
const RAIL_GATE_TO_DEG := 345.0
const RAIL_GATE_FLAPS := 5
## The top of the shooter lane runs round beside the rail at the lane's own width (a narrower
## start is a step the plunge clips), then its outer wall closes along the flaps until its face
## is flush with the rail's inside: a long, even squeeze that hands the plunge onto the ring
## road riding the rail. Stopping short of that left the ball overlapping the rail where it
## resumes, and the plunge hit the rail's end head on.
const LAUNCH_LANE_WIDTH := PLAY_RIGHT - OUTER_THICK * 0.5 - DIVIDER_X - DIVIDER_THICK * 0.5
const SPAWN := Vector2(2.37, 4.975)

# ------------------------------------------------------------------ the ring road -----
## The orbit channel's inner guide is a ring whose ends meet the lane guides tangentially;
## the three Drop-Off lanes hang off its top, so a slow ball peels into them and a fast one
## rides the outer wall round to the far lane.
## The orbit lanes are 1.6 balls wide. Their guides stop short of the Street: a cross-field
## flip reaches the outer wall below the guide's post and rides the throat up past it, where a
## lower post stood in the shot line and turned the Truck Route's own flips away.
const RING_CENTER := Vector2(-0.185, -2.8)
const RING_RADIUS := 1.895
const LANE_GUIDE_L_X := -2.08
const LANE_GUIDE_L_BOTTOM := -0.45
const LANE_GUIDE_R_X := 1.71
const LANE_GUIDE_R_BOTTOM := -0.45
const LANE_WIDTH_L := 0.40
const LANE_L_X := -2.32                 ## the lanes' centre lines
const LANE_R_X := 1.94
const SPINNER_AT := Vector2(-2.32, -1.20)
const ORBIT_L_ENTRY := Vector2(-2.32, -0.65)   ## above the guide posts: only a ball in the lane
const ORBIT_R_ENTRY := Vector2(1.94, -0.65)
## The orbit lanes' throats (LaneMouth): where the curve comes vertical against the outer
## wall, placed so a ball riding it passes the guide post on the lane side.
const LANE_MOUTH_TOP_Z := -0.53
const ORBIT_EXIT_L := Vector2(-2.32, -1.95)   ## the Truck Route finishes high in the left lane
const ORBIT_EXIT_R := Vector2(1.94, -1.95)    ## the Getaway finishes high in the right lane
const CHANNEL_MID_RADIUS := 2.28

# ------------------------------------------------------------------ the Alley (the nest) -----
## Space Cadet's attack bumpers (docs/19 §2): two cans up, one down, walled in on both sides,
## with the three Drop-Off lanes directly above. Gaps between cans are ~1.5 balls, the side
## walls a hair more than one ball off the outer cans: the ball rattles, it does not park.
const MIRROR_X := -0.185
const CAN_RADIUS := 0.25
## The first can (the machine as found) is the bottom one, the one the plaza looks at; the
## Ledger's second and third trash cans are the two up top.
const BUMPER_AT: Array = [Vector2(-0.185, -3.27), Vector2(-0.655, -3.95), Vector2(0.285, -3.95)]
const NEST_HALF := 1.08                 ## side walls at MIRROR_X ± this
const NEST_TOP := -4.29                 ## where the lane block ends
const NEST_BOTTOM := -2.95              ## the side walls stop; below is the open plaza
## The shoulders from the outer lane guides meet the side walls this low, so no ball can sit
## against a side wall above an upper can's middle: up there every kick sent it back into the
## corner under the lane block, off the wall and onto the can again, for good.
const NEST_SHOULDER_Z := -3.93
const DROPOFF_X: PackedFloat32Array = [-0.585, -0.185, 0.215]
const DROPOFF_GUIDE_X: PackedFloat32Array = [-0.785, -0.385, 0.015, 0.415]
const DROPOFF_ROLLOVER_Z := -4.45

# ------------------------------------------------------------------ the Block (shot line) -----
## Islands are storefront plinths; the plaza behind Nonna's and Fat Tony's is open so the
## Alley spills out between them. Each shop's back falls toward the Alley: a ball behind it
## rolls off the inner end into the plaza, where a back parallel to the raked front sloped
## the other way, into the dead corner against Lucky's lane (or under the Staircase).
const ISLAND_WIRE: PackedVector2Array = [Vector2(-2.05, -0.60), Vector2(-1.70, -0.84), Vector2(-1.70, -2.30), Vector2(-2.05, -2.30)]
const ISLAND_NONNA: PackedVector2Array = [Vector2(-1.25, -1.74), Vector2(-0.73, -1.86), Vector2(-0.73, -2.10), Vector2(-1.25, -2.26)]
const ISLAND_TONY: PackedVector2Array = [Vector2(0.36, -1.86), Vector2(0.88, -1.74), Vector2(0.88, -2.26), Vector2(0.36, -2.10)]
## The Beat Cop's island: between Lucky's lane and the Truck Route guide, its face square to a
## +22° shot off the left bat.
const ISLAND_COP: PackedVector2Array = [Vector2(1.36, -0.95), Vector2(1.685, -0.82), Vector2(1.685, -2.45),
		Vector2(1.62, -2.55), Vector2(1.40, -1.40)]
## THE WIRE: three payphones on the left island's face, one per line of Tonight's Work.
const WIRE_AT: Array = [Vector2(-1.99, -0.64), Vector2(-1.875, -0.72), Vector2(-1.76, -0.80)]
const WIRE_FACE := Vector2(0.566, 0.824)
const WIRE_LENGTHS: PackedFloat32Array = [0.13, 0.13, 0.13]
## The storefront banks (Storefront: three drops in front of a doorway).
const STOREFRONT_AT: Array = [Vector2(-0.99, -1.80), Vector2(0.62, -1.80)]
const STOREFRONT_FACING: Array = [Vector2(0.225, 0.974), Vector2(-0.225, 0.974)]
const STOREFRONT_RAKE_DEG: PackedFloat32Array = [0.0, 0.0]
const STOREFRONT_ISLANDS: Array[PackedVector2Array] = [ISLAND_NONNA, ISLAND_TONY]
const STOREFRONT_IDS: Array[StringName] = [&"storefront_pizzeria", &"storefront_pawn"]
const STOREFRONT_SIGNS: Array[StringName] = [&"NONNA'S", &"FAT TONY'S"]
## The Beat Cop: the bribe standup on the right island.
const BRIBE_AT := Vector2(1.52, -0.885)
const BRIBE_FACE := Vector2(-0.371, 0.928)
const BRIBE_LENGTH := 0.22
const TARGET_LENGTH := 0.34
const TARGET_THICK := 0.06

# ------------------------------------------------------------------ the Staircase & the Club -----
## The left ramp rises from the shot line onto the Club's raised deck (segments/club_deck.gd).
## Its mouth faces a −15° tip flip off the right bat and the channel bends straight as it
## climbs; it reaches the deck's height before the deck's front edge, so the ball rolls on flat.
const STAIR_MOUTH := Vector2(-1.30, -0.85)
const STAIR_MOUTH_SIZE := Vector2(0.46, 0.30)
const STAIR_PATH: PackedVector3Array = [
	Vector3(-1.30, 0.0, -0.85), Vector3(-1.42, 0.13, -1.28), Vector3(-1.50, 0.31, -1.70),
	Vector3(-1.52, 0.47, -2.08), Vector3(-1.50, 0.515, -2.36), Vector3(-1.48, 0.515, -2.72),
]

# ------------------------------------------------------------------ Lucky's Tower -----
## Lucky's lane funnels a +15° tip flip off the left bat into the scoop at the tower's foot.
const LUCKY_LANE_L: PackedVector2Array = [Vector2(0.92, -1.40), Vector2(1.02, -3.14)]
const LUCKY_LANE_R: PackedVector2Array = [Vector2(1.40, -1.40), Vector2(1.62, -2.55), Vector2(1.45, -3.14)]
const SCOOP_AT := Vector2(1.235, -2.96)
const TOWER_RECT := Rect2(1.02, -3.76, 0.43, 0.62)   ## x, z, width, depth (front at z -3.14)

# ------------------------------------------------------------------ the Sewer -----
## Three manholes: the lit one is open; the Alley's is always a destination.
const MANHOLE_AT: Array = [Vector2(-1.30, 0.55), Vector2(0.90, 0.55), Vector2(-0.185, -3.72)]

# ------------------------------------------------------------------ the Gutter -----
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
const LANE_RETURN_R: Array = [Vector2(2.12, 1.20), Vector2(1.90, 1.70)]
const LANE_RETURN_L: Array = [Vector2(-2.52, 1.22), Vector2(-2.26, 1.62)]
const KICKBACK_AT := Vector2(-2.345, 3.5)
const KICKBACK_R_AT := Vector2(1.975, 3.5)
const KICKBACK_SIZE := Vector2(0.32, 0.30)
const CENTRE_DRAIN_AT := Vector2(MIRROR_X, 5.15)
const CENTRE_DRAIN_SIZE := Vector2(1.2, 0.35)
const DRAIN_Z := 5.4
const MAGNET_AT := Vector2(MIRROR_X, 4.55)
const DIRECTOR_AT := Vector2(0.2, 2.9)

# ------------------------------------------------------------------ the insert field -----
const WHEEL_CENTER := Vector2(MIRROR_X, 1.35)
const WHEEL_RADIUS := 0.62
const FUSE_AT: Array = [Vector2(MIRROR_X, 0.35), Vector2(MIRROR_X, 0.19), Vector2(MIRROR_X, 0.03),
		Vector2(MIRROR_X, -0.13), Vector2(MIRROR_X, -0.29), Vector2(MIRROR_X, -0.45)]
const TAKE_AT: Array = [Vector2(-0.845, 2.35), Vector2(-0.515, 2.35), Vector2(-0.185, 2.35),
		Vector2(0.145, 2.35), Vector2(0.475, 2.35)]
const CAN_LEVEL_AT: Array = [Vector2(-0.635, -2.40), Vector2(-0.335, -2.40), Vector2(-0.035, -2.40),
		Vector2(0.265, -2.40)]

# ------------------------------------------------------------------ the Commission -----
## Sammy's sedan rides a rail across the Street in front of the Block.
const SEDAN_RAIL_Z := -0.35
const SEDAN_RAIL_FROM_X := -1.10
const SEDAN_RAIL_TO_X := 0.80
const SEDAN_PARK := Vector2(-0.185, -0.35)
const SEDAN_LENGTH := 0.72
const SEDAN_THICK := 0.24
const GOON_AT: Array = [Vector2(-1.30, -0.10), Vector2(0.90, -0.10), Vector2(-0.185, -1.20)]
const GOON_RAKE_DEG: PackedFloat32Array = [18.0, -18.0, 0.0]
const TRUCK_PARK := Vector2(-0.185, 0.35)
const TRUCK_LENGTH := 0.64
const TRUCK_THICK := 0.28
const DOOR_FRONT_Z := 0.95
const DOOR_BACK_Z := 0.60
const DOOR_FRONT_X: PackedFloat32Array = [-0.95, -0.185, 0.58]
const DOOR_BACK_X: PackedFloat32Array = [-0.60, 0.23, 0.95]
const DOOR_RAKE_DEG := 12.0

# ------------------------------------------------------------------ the raid -----
## Cops stand in front of the shots they block.
const COP_AT: Array = [
	Vector2(-1.42, -0.55), Vector2(-0.185, -1.55), Vector2(1.08, -1.10), Vector2(-0.80, 0.95),
]
const COP_RAKE_DEG: PackedFloat32Array = [0.0, 0.0, 0.0, 15.0]
const BRIEFCASE_SPOTS: Array = [Vector2(-0.95, 0.35), Vector2(0.60, 0.35), Vector2(-0.185, -0.85)]
const BRIEFCASE_CLEAR := 0.5
const BRIEFCASE_CLEAR_VEHICLE := 0.9

# ------------------------------------------------------------------ helpers -----


static func p3(plan_point: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(plan_point.x, h, plan_point.y)


static func plan(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Yaw about +Y that turns a node's local +Z onto the plan direction `d` (x, z).
static func yaw_facing(d: Vector2) -> float:
	return atan2(d.x, d.y)


## The arch's centre line, as a radius from the ring's centre along `deg`.
static func arch_radius_from_ring(deg: float) -> float:
	var a := deg_to_rad(deg)
	var d := Vector2(cos(a), sin(a))
	var o := RING_CENTER - ARCH_CENTER
	var b := o.dot(d)
	var c := o.length_squared() - ARCH_RADIUS * ARCH_RADIUS
	return -b + sqrt(maxf(b * b - c, 0.0))


## The rail's centre line radius about the ring's centre at `deg` (270..360).
static func rail_radius(deg: float) -> float:
	var d := clampf(deg, RAIL_TOP_DEG, 360.0)
	if d >= RAIL_EASE_FROM_DEG:
		return RAIL_RADIUS
	var f := smoothstep(RAIL_TOP_DEG, RAIL_EASE_FROM_DEG, d)
	return lerpf(arch_radius_from_ring(d), RAIL_RADIUS, f)


## The shooter lane's outer wall above the divider, from 360° round to `to_deg` (by default
## the last flap, where its face is flush with the rail's inside).
static func launch_wall_points(steps: int, to_deg: float = RAIL_GATE_FROM_DEG) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var deg := lerpf(360.0, to_deg, float(i) / float(steps))
		var w := LAUNCH_LANE_WIDTH
		if deg < RAIL_GATE_TO_DEG:
			w = lerpf(-DIVIDER_THICK, LAUNCH_LANE_WIDTH,
					(deg - RAIL_GATE_FROM_DEG) / (RAIL_GATE_TO_DEG - RAIL_GATE_FROM_DEG))
		pts.append(ring_point(deg, rail_radius(deg) + DIVIDER_THICK + w))
	return pts


## Where the closing shooter lane's wall reaches the back of the rail.
static func launch_wall_meets_rail_deg() -> float:
	return lerpf(RAIL_GATE_FROM_DEG, RAIL_GATE_TO_DEG, DIVIDER_THICK / (LAUNCH_LANE_WIDTH + DIVIDER_THICK))


static func rail_point(deg: float) -> Vector2:
	return ring_point(deg, rail_radius(deg))


## The rail as a polyline between two angles (270..360), `steps` segments.
static func rail_points(from_deg: float, to_deg: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		pts.append(rail_point(lerpf(from_deg, to_deg, float(i) / float(steps))))
	return pts


static func ring_point(deg: float, radius: float = RING_RADIUS) -> Vector2:
	var a := deg_to_rad(deg)
	return RING_CENTER + Vector2(cos(a), sin(a)) * radius


## The arch as a polyline from 180° to 360°, `steps` segments.
static func arch_points(steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		pts.append(arch_point(lerpf(180.0, 360.0, float(i) / float(steps))))
	return pts


static func arch_point(deg: float, radius: float = ARCH_RADIUS) -> Vector2:
	var a := deg_to_rad(deg)
	return ARCH_CENTER + Vector2(cos(a), sin(a)) * radius


## The ring's angle (degrees, upper half) at a given x.
static func ring_deg_at_x(x: float) -> float:
	var c := clampf((x - RING_CENTER.x) / RING_RADIUS, -1.0, 1.0)
	return 360.0 - rad_to_deg(acos(c))


## The middle of the ring road along the ray from the ring's centre at `deg`: halfway between
## the ring guide's outer face and the arch's inner face (the channel is not concentric).
static func channel_mid(deg: float) -> Vector2:
	var a := deg_to_rad(deg)
	var d := Vector2(cos(a), sin(a))
	var o := RING_CENTER - ARCH_CENTER
	var b := o.dot(d)
	var c := o.length_squared() - ARCH_RADIUS * ARCH_RADIUS
	var t := -b + sqrt(maxf(b * b - c, 0.0))
	var inner := RING_RADIUS + GUIDE_THICK * 0.5
	var outer := t - OUTER_THICK * 0.5
	var wrapped := fposmod(deg, 360.0)
	if wrapped >= RAIL_TOP_DEG:
		outer = minf(outer, rail_radius(wrapped) - DIVIDER_THICK * 0.5)
	return RING_CENTER + d * ((inner + outer) * 0.5)


## z of the ring's upper edge at x.
static func ring_top_z(x: float) -> float:
	var dx := x - RING_CENTER.x
	return RING_CENTER.y - sqrt(maxf(RING_RADIUS * RING_RADIUS - dx * dx, 0.0))


static func mirror(p: Vector2) -> Vector2:
	return Vector2(MIRROR_X * 2.0 - p.x, p.y)


## A bottom-assembly point given as an offset from the mirror line: s = +1 right, -1 left.
static func mx(offset: Vector2, s: float) -> Vector2:
	return Vector2(MIRROR_X + s * offset.x, offset.y)


static func inlane_guide_x(s: float) -> float:
	return MIRROR_X + s * INLANE_GUIDE_DX
