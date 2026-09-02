class_name TableSegment
extends Node3D
## The contract the table root implements for the session (docs/09 §4): geometry builds
## itself in code, hardware announces itself through Events, and the segment owns nothing
## about scoring.


func segment_id() -> StringName:
	return &"segment"


## Playfield extents in table space — camera bounds and out-of-bounds asserts read this.
func bounds() -> AABB:
	return AABB()


## Where a fresh ball appears (table space).
func spawn_point() -> Vector3:
	return Vector3.ZERO


## Anchor lookup for the flow lane, in plan space (x, z).
func socket(_id: StringName) -> Vector2:
	return Vector2.ZERO
