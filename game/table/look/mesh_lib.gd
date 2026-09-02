class_name MeshLib
extends RefCounted
## Mesh builders for the 3D playfield. Everything here takes metres (TableSpace) and writes
## into a SurfaceTool, so a whole StaticBody's worth of walls ends up as one draw call.
## Godot's front faces wind clockwise; `tri()` enforces that from a wanted outward direction
## so the callers can think in geometry rather than in vertex order.

## Cross-section of a rail: (u across, -1..1 of the half width; v up, 0..1 of the height).
const RAIL_PROFILE: PackedVector2Array = [
	Vector2(-1.0, 0.0), Vector2(-1.0, 0.72), Vector2(-0.88, 0.92), Vector2(-0.55, 1.0),
	Vector2(0.55, 1.0), Vector2(0.88, 0.92), Vector2(1.0, 0.72), Vector2(1.0, 0.0),
]
const CAP_STEPS := 6


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func finish(st: SurfaceTool, material: Material = null) -> ArrayMesh:
	st.generate_normals()
	if material != null:
		st.set_material(material)
	return st.commit()


## One triangle, wound so its front faces `outward`.
static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		uva: Vector2 = Vector2.ZERO, uvb: Vector2 = Vector2.ZERO, uvc: Vector2 = Vector2.ZERO) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(outward) > 0.0:
		st.set_uv(uva); st.add_vertex(a)
		st.set_uv(uvc); st.add_vertex(c)
		st.set_uv(uvb); st.add_vertex(b)
	else:
		st.set_uv(uva); st.add_vertex(a)
		st.set_uv(uvb); st.add_vertex(b)
		st.set_uv(uvc); st.add_vertex(c)


static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		uva: Vector2 = Vector2.ZERO, uvb: Vector2 = Vector2.ZERO, uvc: Vector2 = Vector2.ZERO,
		uvd: Vector2 = Vector2.ZERO) -> void:
	tri(st, a, b, c, outward, uva, uvb, uvc)
	tri(st, a, c, d, outward, uva, uvc, uvd)


## Connect consecutive rings (equal length) with quads. The outward direction of each quad
## is taken from the ring's own centre so a sweep reads correctly whichever way it turns.
static func sweep(st: SurfaceTool, rings: Array, centers: Array, uv_along: PackedFloat32Array,
		closed: bool) -> void:
	for i in range(rings.size() - 1):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[i + 1]
		var c0: Vector3 = centers[i]
		var c1: Vector3 = centers[i + 1]
		var n := r0.size()
		var last := n if closed else n - 1
		for k in range(last):
			var k2 := (k + 1) % n
			var a := r0[k]
			var b := r0[k2]
			var c := r1[k2]
			var d := r1[k]
			var mid := (a + b + c + d) * 0.25
			var out := mid - (c0 + c1) * 0.5
			if out.length_squared() < 1e-9:
				out = Vector3.UP
			var u0 := uv_along[i]
			var u1 := uv_along[i + 1]
			var v0 := float(k) / float(n)
			var v1 := float(k2 if k2 != 0 else n) / float(n)
			quad(st, a, b, c, d, out, Vector2(u0, v0), Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0))


## A wall: the rounded polyline the physics uses, extruded up from `base` by `height`. Ends
## are swept round, mirroring the capsule chain, so a lone post and a long guide both read
## as the same milled piece.
static func rail(st: SurfaceTool, points: PackedVector2Array, half_w: float, height: float,
		base: float = 0.0) -> void:
	var pts := _dedupe(points)
	if pts.size() < 2:
		if pts.size() == 1:
			post(st, pts[0], half_w, height, base)
		return
	var frames: Array = []          # [center: Vector2, right: Vector2, along: float]
	var t0 := (pts[1] - pts[0]).normalized()
	var n0 := Vector2(-t0.y, t0.x)
	for s in range(CAP_STEPS + 1):
		var a := PI * float(s) / float(CAP_STEPS)
		frames.append([pts[0], n0 * cos(a) - t0 * sin(a), -half_w * (1.0 - float(s) / float(CAP_STEPS))])
	var along := 0.0
	for i in range(pts.size()):
		var t_in := (pts[i] - pts[i - 1]).normalized() if i > 0 else t0
		var t_out := (pts[i + 1] - pts[i]).normalized() if i < pts.size() - 1 else t_in
		var t := (t_in + t_out)
		t = t.normalized() if t.length() > 0.001 else t_in
		var n := Vector2(-t.y, t.x)
		var n_seg := Vector2(-t_out.y, t_out.x)
		var scale := 1.0 / maxf(absf(n.dot(n_seg)), 0.55)
		if i > 0:
			along += pts[i].distance_to(pts[i - 1])
		frames.append([pts[i], n * scale, along])
	var last := pts.size() - 1
	var t_end := (pts[last] - pts[last - 1]).normalized()
	var n_end := Vector2(-t_end.y, t_end.x)
	for s in range(1, CAP_STEPS + 1):
		var a := PI * float(s) / float(CAP_STEPS)
		frames.append([pts[last], n_end * cos(a) + t_end * sin(a), along + half_w * float(s) / float(CAP_STEPS)])
	var rings: Array = []
	var centers: Array = []
	var uvs := PackedFloat32Array()
	for f: Array in frames:
		var c: Vector2 = f[0]
		var r: Vector2 = f[1]
		var ring := PackedVector3Array()
		for p in RAIL_PROFILE:
			var xz := c + r * (p.x * half_w)
			ring.append(Vector3(xz.x, base + p.y * height, xz.y))
		rings.append(ring)
		centers.append(Vector3(c.x, base + height * 0.35, c.y))
		uvs.append(float(f[2]) * 2.0)
	sweep(st, rings, centers, uvs, false)


## A round post (a lone capsule or circle collider).
static func post(st: SurfaceTool, at: Vector2, radius: float, height: float, base: float = 0.0,
		segments: int = 14) -> void:
	var rings: Array = []
	var centers: Array = []
	var uvs := PackedFloat32Array()
	var levels: Array = [[radius, 0.0], [radius, 0.72], [radius * 0.88, 0.92], [radius * 0.55, 1.0], [0.0, 1.0]]
	for lv: Array in levels:
		var ring := PackedVector3Array()
		var rr: float = lv[0]
		var h: float = base + float(lv[1]) * height
		for s in range(segments):
			var a := TAU * float(s) / float(segments)
			ring.append(Vector3(at.x + cos(a) * maxf(rr, 0.0005), h, at.y + sin(a) * maxf(rr, 0.0005)))
		rings.append(ring)
		centers.append(Vector3(at.x, base + height * 0.35, at.y))
		uvs.append(float(lv[1]))
	sweep(st, rings, centers, uvs, true)


## A flat-topped extrusion of a polygon (a sling body, a bank plinth, a deck slab).
static func prism(st: SurfaceTool, poly: PackedVector2Array, height: float, base: float = 0.0,
		with_bottom: bool = false, uv_scale: float = 0.5) -> void:
	if poly.size() < 3:
		return
	var centroid := Vector2.ZERO
	for p in poly:
		centroid += p
	centroid /= float(poly.size())
	var c3 := Vector3(centroid.x, base + height * 0.5, centroid.y)
	var along := 0.0
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var a0 := Vector3(a.x, base, a.y)
		var b0 := Vector3(b.x, base, b.y)
		var a1 := Vector3(a.x, base + height, a.y)
		var b1 := Vector3(b.x, base + height, b.y)
		var mid := (a0 + b1) * 0.5
		var seg := a.distance_to(b)
		quad(st, a0, b0, b1, a1, mid - c3, Vector2(along * uv_scale, 0.0),
				Vector2((along + seg) * uv_scale, 0.0), Vector2((along + seg) * uv_scale, height * uv_scale),
				Vector2(along * uv_scale, height * uv_scale))
		along += seg
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		var hull := Geometry2D.convex_hull(poly)
		if hull.size() > poly.size():
			hull.resize(hull.size() - 1)
		tris = Geometry2D.triangulate_polygon(hull)
		poly = hull
	for i in range(0, tris.size() - 2, 3):
		var p0 := poly[tris[i]]
		var p1 := poly[tris[i + 1]]
		var p2 := poly[tris[i + 2]]
		tri(st, Vector3(p0.x, base + height, p0.y), Vector3(p1.x, base + height, p1.y),
				Vector3(p2.x, base + height, p2.y), Vector3.UP, p0 * uv_scale, p1 * uv_scale, p2 * uv_scale)
		if with_bottom:
			tri(st, Vector3(p0.x, base, p0.y), Vector3(p1.x, base, p1.y),
					Vector3(p2.x, base, p2.y), Vector3.DOWN, p0 * uv_scale, p1 * uv_scale, p2 * uv_scale)


## A tube along a 3D path (wireform rails, a gate wire, a crane cable).
static func tube(st: SurfaceTool, path: PackedVector3Array, radius: float, segments: int = 6,
		cap_ends: bool = true) -> void:
	if path.size() < 2:
		return
	var rings: Array = []
	var centers: Array = []
	var uvs := PackedFloat32Array()
	var along := 0.0
	var prev_n := Vector3.ZERO
	for i in range(path.size()):
		var t_in := (path[i] - path[i - 1]).normalized() if i > 0 else (path[1] - path[0]).normalized()
		var t_out := (path[i + 1] - path[i]).normalized() if i < path.size() - 1 else t_in
		var t := (t_in + t_out).normalized()
		if t.length_squared() < 0.5:
			t = t_in
		var n: Vector3
		if prev_n == Vector3.ZERO:
			var ref := Vector3.UP if absf(t.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
			n = ref.cross(t).normalized()
		else:
			n = (prev_n - t * prev_n.dot(t)).normalized()     # parallel transport: no twist
		prev_n = n
		var b := t.cross(n).normalized()
		if i > 0:
			along += path[i].distance_to(path[i - 1])
		var ring := PackedVector3Array()
		for s in range(segments):
			var a := TAU * float(s) / float(segments)
			ring.append(path[i] + (n * cos(a) + b * sin(a)) * radius)
		rings.append(ring)
		centers.append(path[i])
		uvs.append(along)
	sweep(st, rings, centers, uvs, true)
	if cap_ends:
		_fan(st, rings[0], path[0], path[0] - path[1])
		_fan(st, rings[rings.size() - 1], path[path.size() - 1], path[path.size() - 1] - path[path.size() - 2])


static func _fan(st: SurfaceTool, ring: PackedVector3Array, center: Vector3, outward: Vector3) -> void:
	for k in range(ring.size()):
		tri(st, center, ring[k], ring[(k + 1) % ring.size()], outward)


## An axis-aligned box in metres, centred on `center`.
static func box(st: SurfaceTool, center: Vector3, size: Vector3, uv_scale: float = 0.5) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(center + Vector3(h.x * sx, h.y * sy, h.z * sz))
	# index: x*4 + y*2 + z  (0 = negative)
	var faces := [
		[0, 1, 3, 2, Vector3.LEFT], [4, 6, 7, 5, Vector3.RIGHT],
		[0, 4, 5, 1, Vector3.DOWN], [2, 3, 7, 6, Vector3.UP],
		[0, 2, 6, 4, Vector3.FORWARD], [1, 5, 7, 3, Vector3.BACK],
	]
	for f: Array in faces:
		var a: Vector3 = corners[f[0]]
		var b: Vector3 = corners[f[1]]
		var c: Vector3 = corners[f[2]]
		var d: Vector3 = corners[f[3]]
		var n: Vector3 = f[4]
		var w := (b - a).length() * uv_scale
		var hh := (d - a).length() * uv_scale
		quad(st, a, b, c, d, n, Vector2(0, 0), Vector2(w, 0), Vector2(w, hh), Vector2(0, hh))


## Flat disc lying in the XZ plane at height `y` (an insert, a saucer dish rim).
static func disc(st: SurfaceTool, center: Vector3, radius: float, segments: int = 24,
		up: bool = true) -> void:
	for s in range(segments):
		var a0 := TAU * float(s) / float(segments)
		var a1 := TAU * float(s + 1) / float(segments)
		var p0 := center + Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1 := center + Vector3(cos(a1), 0.0, sin(a1)) * radius
		tri(st, center, p0, p1, Vector3.UP if up else Vector3.DOWN, Vector2(0.5, 0.5),
				Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5), Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))


## Ring between two radii (a bumper skirt, a saucer lip).
static func ring(st: SurfaceTool, center: Vector3, r_in: float, r_out: float, y_in: float, y_out: float,
		segments: int = 24) -> void:
	for s in range(segments):
		var a0 := TAU * float(s) / float(segments)
		var a1 := TAU * float(s + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var a := center + d0 * r_in + Vector3.UP * y_in
		var b := center + d1 * r_in + Vector3.UP * y_in
		var c := center + d1 * r_out + Vector3.UP * y_out
		var d := center + d0 * r_out + Vector3.UP * y_out
		var out := ((a + b + c + d) * 0.25 - center)
		out.y = maxf(out.y, 0.001)
		quad(st, a, b, c, d, out + Vector3.UP * 0.5, Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1))


static func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.0005:
			out.append(p)
	return out


## Circle outline sampled as a polygon (metres).
static func circle_poly(center: Vector2, radius: float, segments: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	for s in range(segments):
		var a := TAU * float(s) / float(segments)
		out.append(center + Vector2(cos(a), sin(a)) * radius)
	return out


## The outline of a 2D capsule/bat (two circles joined), as a polygon: flippers, boss cars.
static func capsule_poly(a: Vector2, b: Vector2, ra: float, rb: float, steps: int = 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var d := (b - a)
	var ang := d.angle() if d.length() > 0.0001 else 0.0
	for s in range(steps + 1):
		var t := ang - PI * 0.5 + PI * float(s) / float(steps)
		out.append(b + Vector2(cos(t), sin(t)) * rb)
	for s in range(steps + 1):
		var t := ang + PI * 0.5 + PI * float(s) / float(steps)
		out.append(a + Vector2(cos(t), sin(t)) * ra)
	return out
