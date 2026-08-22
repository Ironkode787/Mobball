class_name TableSegment
extends Node2D
## The contract every table zone implements (docs/09 §4). M0 ships exactly one segment, but
## every later milestone bolts zones onto anchor sockets, so the shape of the interface is
## fixed now: geometry builds itself in code, hardware announces itself through Events, and
## the segment owns nothing about scoring.

## Stable id used by save data, music stems and shot definitions.
func segment_id() -> StringName:
	return &"segment"


## Playfield extents in table space — camera bounds and out-of-bounds asserts read this.
func bounds() -> Rect2:
	return Rect2()


## Where a fresh ball appears.
func spawn_point() -> Vector2:
	return Vector2.ZERO


## Marker2D-style anchor lookup for future segments docking onto this one.
func socket(_id: StringName) -> Vector2:
	return Vector2.ZERO
