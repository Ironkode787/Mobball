class_name Dormant
extends RefCounted
## Switching a piece of table hardware off has to mean *off*: invisible **and** physically
## absent. Half-off is the worst state a pinball machine can be in — an invisible wall a
## player cannot see but the ball can find.
##
## Hardware scripts implement `set_hardware_active(active)` and own their own rules (a
## dropped target must not come back up just because its bank got switched on). Anything
## else falls through to the generic path here, which stashes the live collision layers on
## the node the first time it is disabled so the restore is exact.


static func apply(node: Node, active: bool) -> void:
	if node.has_method(&"set_hardware_active"):
		node.call(&"set_hardware_active", active)
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = active
	set_collision(node, active)


static func set_collision(node: Node, active: bool) -> void:
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		if not co.has_meta(&"live_layer"):
			co.set_meta(&"live_layer", co.collision_layer)
			co.set_meta(&"live_mask", co.collision_mask)
		co.collision_layer = int(co.get_meta(&"live_layer")) if active else 0
		co.collision_mask = int(co.get_meta(&"live_mask")) if active else 0
	for child in node.get_children():
		set_collision(child, active)


## True when every collider under `node` is switched off. The growth sim asserts this on
## every dormant piece — "hidden" is not the same as "not there".
static func is_collision_off(node: Node) -> bool:
	if node is CollisionObject2D:
		var co := node as CollisionObject2D
		if co.collision_layer != 0 or co.collision_mask != 0:
			return false
	for child in node.get_children():
		if not is_collision_off(child):
			return false
	return true
