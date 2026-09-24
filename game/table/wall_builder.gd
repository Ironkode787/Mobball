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
	if points.size() >= 3:
		# one mitred trimesh, not a box per chord: Jolt treats its inner edges as inactive, so a
		# fast ball riding a curve is not caught on the joins between segments
		_smooth(points, t, h)
		_post(points[0], t * 0.5, h)
		_post(points[points.size() - 1], t * 0.5, h)
	else:
		for i in range(points.size() - 1):
			_segment(points[i], points[i + 1], t, h)
		for p in points:
			_post(p, t * 0.5, h)
	chains.append({"points": points, "thickness": t, "height": h, "base": base})


func _smooth(points: PackedVector2Array, t: float, h: float) -> void:
	var n := points.size()
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(n):
		var d_prev := (points[i] - points[i - 1]).normalized() if i > 0 else (points[1] - points[0]).normalized()
		var d_next := (points[i + 1] - points[i]).normalized() if i < n - 1 else d_prev
		var tangent := (d_prev + d_next).normalized()
		if tangent.length() < 0.001:
			tangent = d_next
		var normal := Vector2(-tangent.y, tangent.x)
		var seg_normal := Vector2(-d_next.y, d_next.x)
		var miter := t * 0.5 / maxf(normal.dot(seg_normal), 0.35)
		left.append(points[i] + normal * miter)
		right.append(points[i] - normal * miter)
	var faces := PackedVector3Array()
	var y0 := base
	var y1 := base + h
	for i in range(n - 1):
		for side: PackedVector2Array in [left, right]:
			var a := side[i]
			var b := side[i + 1]
			faces.append_array([Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y),
					Vector3(a.x, y0, a.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y)])
		var la := left[i]
		var lb := left[i + 1]
		var ra := right[i]
		var rb := right[i + 1]
		faces.append_array([Vector3(la.x, y1, la.y), Vector3(lb.x, y1, lb.y), Vector3(rb.x, y1, rb.y),
				Vector3(la.x, y1, la.y), Vector3(rb.x, y1, rb.y), Vector3(ra.x, y1, ra.y)])
	for i: int in [0, n - 1]:
		var l := left[i]
		var r := right[i]
		faces.append_array([Vector3(l.x, y0, l.y), Vector3(r.x, y0, r.y), Vector3(r.x, y1, r.y),
				Vector3(l.x, y0, l.y), Vector3(r.x, y1, r.y), Vector3(l.x, y1, l.y)])
	var shape := CollisionShape3D.new()
	var mesh := ConcavePolygonShape3D.new()
	mesh.backface_collision = true
	mesh.set_faces(faces)
	shape.shape = mesh
	body.add_child(shape)


## Draw a polyline with the others but give it no collider: its solid shape lives elsewhere.
func outline(points: PackedVector2Array, thickness: float, height: float = -1.0) -> void:
	var h := default_height if height <= 0.0 else height
	chains.append({"points": points, "thickness": maxf(thickness, MIN_THICKNESS), "height": h, "base": base})


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
