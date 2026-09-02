class_name WallBuilder
extends RefCounted
## Builds table geometry as rounded polylines: each segment is a box collider with a round
## post at every vertex, so the collision surface has no seams for a fast ball to catch on,
## and the same chain drives the mesh, so geometry and art can never drift apart.

const MIN_THICKNESS := 0.04

var body: StaticBody3D
var chains: Array[Dictionary] = []      ## { points: PackedVector2Array, thickness, height, base }
var default_height: float = Layout.WALL_HEIGHT
var base: float = 0.0


func _init(p_body: StaticBody3D, p_height: float = Layout.WALL_HEIGHT, p_base: float = 0.0) -> void:
	body = p_body
	default_height = p_height
	base = p_base


## Add one rounded polyline in plan coordinates (x, z).
func chain(points: PackedVector2Array, thickness: float, height: float = -1.0) -> void:
	if points.size() < 2:
		return
	var t := maxf(thickness, MIN_THICKNESS)
	var h := default_height if height <= 0.0 else height
	for i in range(points.size() - 1):
		_segment(points[i], points[i + 1], t, h)
	for p in points:
		_post(p, t * 0.5, h)
	chains.append({"points": points, "thickness": t, "height": h, "base": base})


func bar(from: Vector2, to: Vector2, thickness: float, height: float = -1.0) -> void:
	chain(PackedVector2Array([from, to]), thickness, height)


## Circular arc sampled into a rounded polyline. Angles in degrees, plan space (x, z).
func arc(center: Vector2, radius: float, from_deg: float, to_deg: float,
		segments: int, thickness: float, height: float = -1.0) -> void:
	var pts := PackedVector2Array()
	var steps := maxi(segments, 2)
	for i in range(steps + 1):
		var a := deg_to_rad(lerpf(from_deg, to_deg, float(i) / float(steps)))
		pts.append(center + Vector2(cos(a), sin(a)) * radius)
	chain(pts, thickness, height)


func post(at: Vector2, radius: float, height: float = -1.0) -> void:
	var h := default_height if height <= 0.0 else height
	_post(at, radius, h)
	chains.append({"points": PackedVector2Array([at]), "thickness": radius * 2.0, "height": h, "base": base})


func _segment(a: Vector2, b: Vector2, t: float, h: float) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.0001:
		return
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(len, h, t)
	shape.shape = box
	var mid := (a + b) * 0.5
	shape.position = Vector3(mid.x, base + h * 0.5, mid.y)
	shape.rotation.y = atan2(-d.y, d.x)
	body.add_child(shape)


func _post(at: Vector2, radius: float, h: float) -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = h
	shape.shape = cyl
	shape.position = Vector3(at.x, base + h * 0.5, at.y)
	body.add_child(shape)


## One mesh for every chain: rounded rails in `material`, optional brass cap on top.
func build_mesh(material: Material, cap_material: Material = null) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var st := MeshLib.begin()
	var cap := MeshLib.begin()
	var any_cap := false
	for c in chains:
		var pts: PackedVector2Array = c["points"]
		var t: float = c["thickness"]
		var h: float = c["height"]
		var b: float = c["base"]
		if pts.size() == 1:
			MeshLib.post(st, pts[0], t * 0.5, h, b)
			continue
		MeshLib.rail(st, pts, t * 0.5, h, b)
		if cap_material != null:
			MeshLib.rail(cap, pts, t * 0.28, 0.02, b + h - 0.004)
			any_cap = true
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, material)
	mi.name = "Rails"
	body.add_child(mi)
	out.append(mi)
	if any_cap:
		var cm := MeshInstance3D.new()
		cm.mesh = MeshLib.finish(cap, cap_material)
		cm.name = "Caps"
		body.add_child(cm)
		out.append(cm)
	return out


static func make_body(p_name: String, layer: int = Feel.LAYER_WALLS,
		material: PhysicsMaterial = null) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = p_name
	b.collision_layer = layer
	b.collision_mask = 0
	b.physics_material_override = material if material != null \
			else Feel.make_material(Feel.WALL_FRICTION, Feel.WALL_BOUNCE)
	return b
