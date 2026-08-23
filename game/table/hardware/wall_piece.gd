class_name WallPiece
extends Node2D
## A named lump of wall geometry that an upgrade can switch on and off — lane guides, the
## numbers-lane channel, the getaway arc, the top-lane posts.
##
## Same discipline as WallBuilder: the collision body and the drawing come from one set of
## capsule chains, so a dormant piece can never leave a ghost outline behind, nor an
## invisible wall in front of the player.

var body: StaticBody2D = null
var walls: WallBuilder = null
var color: Color = Feel.COL_BRASS.darkened(0.42)
var rim: Color = Feel.COL_INK

var _active: bool = true


func _init() -> void:
	body = StaticBody2D.new()
	body.name = "Body"
	body.collision_layer = Feel.LAYER_WALLS
	body.collision_mask = 0
	body.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, Feel.WALL_BOUNCE)
	add_child(body)
	walls = WallBuilder.new(body)


func bar(from: Vector2, to: Vector2, thickness: float) -> void:
	walls.bar(from, to, thickness)
	queue_redraw()


func chain(points: PackedVector2Array, thickness: float) -> void:
	walls.chain(points, thickness)
	queue_redraw()


func arc(center: Vector2, radius: float, from_angle: float, to_angle: float,
		segments: int, thickness: float) -> void:
	walls.arc(center, radius, from_angle, to_angle, segments, thickness)
	queue_redraw()


func set_hardware_active(active: bool) -> void:
	_active = active
	visible = active
	body.collision_layer = Feel.LAYER_WALLS if active else 0


func is_hardware_active() -> bool:
	return _active


func _draw() -> void:
	walls.draw_into(self, color, rim)
