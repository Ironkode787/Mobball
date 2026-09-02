class_name TableSpace
extends RefCounted
## Maps the 2D simulation's table space (pixels, +y down the table) onto the 3D presentation
## (metres, +y up, +z toward the player). The physics never knows this file exists: every
## 3D proxy reads the 2D node it mirrors and converts through here, so geometry and art can
## never disagree about where a wall is.
##
## The main field lies at height zero. Everything the career builds above the arch — the
## Club, the Penthouse, City Hall — is the second storey and sits DECK_HEIGHT above it;
## ramps are the only way between the two levels, exactly as in the 2D layout.

const SCALE := 0.01
## Table px: anything above (smaller y than) this line is upstairs.
const UPPER_STOREY_Y := -35.0
const DECK_HEIGHT := 1.15
## Real pinball walls are about three quarters of a ball high; the cabinet is much taller.
const WALL_HEIGHT := 0.44
const GUIDE_HEIGHT := 0.36
const CABINET_HEIGHT := 1.6


static func to3(p: Vector2, h: float = 0.0) -> Vector3:
	return Vector3(p.x * SCALE, h, p.y * SCALE)


static func to2(v: Vector3) -> Vector2:
	return Vector2(v.x / SCALE, v.z / SCALE)


static func m(px: float) -> float:
	return px * SCALE


static func floor_height(p: Vector2) -> float:
	return DECK_HEIGHT if p.y < UPPER_STOREY_Y else 0.0


## A 2D rotation (radians, clockwise on a y-down canvas) as the matching yaw about +Y.
static func yaw(rot2d: float) -> float:
	return -rot2d


static func ball_radius() -> float:
	return Feel.BALL_RADIUS * SCALE
