class_name WallProxy3D
extends HardwareProxy3D
## Any StaticBody2D the ball can hit becomes milled rail. Bodies built by WallBuilder hand
## over their capsule chains (one clean extrusion per chain); anything else is rebuilt from
## its collision shapes one by one. Either way the 3D wall is derived from the collider the
## sim uses, never from a drawing.

var body: CollisionObject2D = null
var chains: Array = []               ## WallBuilder chains, if the builder is known
var height: float = TableSpace.WALL_HEIGHT
var material: Material = null
var tall: bool = false               ## outer cabinet walls


## Called before the proxy enters the tree; `setup()` runs the build once it has.
func setup_body_deferred(p_body: CollisionObject2D, p_chains: Array, _p_view: Node,
		p_material: Material, p_tall: bool) -> void:
	body = p_body
	chains = p_chains
	material = p_material
	tall = p_tall


func build() -> void:
	follow_transform = false
	var st := View3DMesh.begin()
	var cap := View3DMesh.begin()
	var xf := body.global_transform
	if not chains.is_empty():
		for c: Dictionary in chains:
			var pts: PackedVector2Array = c["points"]
			var thick: float = c["thickness"]
			var mp := PackedVector2Array()
			for p in pts:
				mp.append((xf * p) * TableSpace.SCALE)
			# the storey is read off the geometry, not the node: WallPieces sit at the origin
			var base := TableSpace.floor_height(xf * pts[0])
			var h := _height_for(thick)
			View3DMesh.rail(st, mp, thick * 0.5 * TableSpace.SCALE, h, base)
			if tall:
				View3DMesh.rail(cap, mp, thick * 0.5 * TableSpace.SCALE * 0.55, 0.05, base + h - 0.01)
	else:
		for child in body.get_children():
			var cs := child as CollisionShape2D
			if cs == null or cs.shape == null:
				continue
			_shape_mesh(st, cs, xf, TableSpace.floor_height(xf * cs.position))
	mesh_node(View3DMesh.finish(st, material), null, "Rail")
	if tall:
		mesh_node(View3DMesh.finish(cap, lib.brass()), null, "Cap")


func _height_for(thick_px: float) -> float:
	if tall:
		return TableSpace.WALL_HEIGHT * 2.1
	return TableSpace.WALL_HEIGHT if thick_px >= 30.0 else TableSpace.GUIDE_HEIGHT


func _shape_mesh(st: SurfaceTool, cs: CollisionShape2D, xf: Transform2D, base: float) -> void:
	var local := xf * cs.transform
	var shape := cs.shape
	var S := TableSpace.SCALE
	if shape is CapsuleShape2D:
		var cap := shape as CapsuleShape2D
		var half := maxf(cap.height * 0.5 - cap.radius, 0.0)
		var a := local * Vector2(0.0, -half)
		var b := local * Vector2(0.0, half)
		View3DMesh.rail(st, PackedVector2Array([a * S, b * S]), cap.radius * S, _height_for(cap.radius * 2.0), base)
	elif shape is CircleShape2D:
		var circ := shape as CircleShape2D
		View3DMesh.post(st, (local * Vector2.ZERO) * S, circ.radius * S, _height_for(circ.radius * 2.0), base)
	elif shape is SegmentShape2D:
		var seg := shape as SegmentShape2D
		View3DMesh.rail(st, PackedVector2Array([(local * seg.a) * S, (local * seg.b) * S]), 0.06,
				TableSpace.GUIDE_HEIGHT, base)
	elif shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		var h := rect.size * 0.5
		var poly := PackedVector2Array([
			(local * Vector2(-h.x, -h.y)) * S, (local * Vector2(h.x, -h.y)) * S,
			(local * Vector2(h.x, h.y)) * S, (local * Vector2(-h.x, h.y)) * S,
		])
		View3DMesh.prism(st, poly, TableSpace.WALL_HEIGHT, base)
	elif shape is ConvexPolygonShape2D:
		var poly := PackedVector2Array()
		for p in (shape as ConvexPolygonShape2D).points:
			poly.append((local * p) * S)
		View3DMesh.prism(st, poly, TableSpace.WALL_HEIGHT, base)


func sync(delta: float) -> void:
	super.sync(delta)
