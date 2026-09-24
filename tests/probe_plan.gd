extends SimBase
## Dumps every collider's plan footprint (table space) as JSON lines, for plotting.
## PROBE_ALL=0 for the bare table.

func _ready() -> void:
	make_table(OS.get_environment("PROBE_ALL") != "0")
	await step(4)
	var b := table.spawn_ball()
	await step(2)
	var inv := (b.get_parent() as Node3D).global_transform.affine_inverse()
	table.despawn_ball()
	var out := FileAccess.open(OS.get_environment("PROBE_OUT"), FileAccess.WRITE)
	_walk(table, inv, out)
	out.close()
	get_tree().quit(0)


func _walk(n: Node, inv: Transform3D, out: FileAccess) -> void:
	if n is CollisionObject3D:
		var co := n as CollisionObject3D
		if co.collision_layer != 0:
			for c in co.get_children():
				if c is CollisionShape3D and not (c as CollisionShape3D).disabled and (c as CollisionShape3D).shape != null:
					_emit(co, c as CollisionShape3D, inv, out)
	for c in n.get_children():
		_walk(c, inv, out)


func _emit(co: CollisionObject3D, cs: CollisionShape3D, inv: Transform3D, out: FileAccess) -> void:
	var xf := inv * cs.global_transform
	var rec := {"name": String(co.get_parent().name) + "/" + String(co.name), "layer": co.collision_layer,
			"area": co is Area3D}
	var s := cs.shape
	if s is BoxShape3D:
		var h := (s as BoxShape3D).size * 0.5
		var pts := []
		for k in [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)]:
			var p: Vector3 = xf * k
			pts.append([p.x, p.z])
		rec["poly"] = pts
		rec["y"] = [(xf * Vector3(0, -h.y, 0)).y, (xf * Vector3(0, h.y, 0)).y]
	elif s is CylinderShape3D:
		var p := xf.origin
		rec["circle"] = [p.x, p.z, (s as CylinderShape3D).radius]
		rec["y"] = [p.y - (s as CylinderShape3D).height * 0.5, p.y + (s as CylinderShape3D).height * 0.5]
	elif s is SphereShape3D:
		var p := xf.origin
		rec["circle"] = [p.x, p.z, (s as SphereShape3D).radius]
		rec["y"] = [p.y - (s as SphereShape3D).radius, p.y + (s as SphereShape3D).radius]
	elif s is CapsuleShape3D:
		var p := xf.origin
		rec["circle"] = [p.x, p.z, (s as CapsuleShape3D).radius]
		rec["y"] = [p.y, p.y]
	elif s is ConcavePolygonShape3D or s is ConvexPolygonShape3D:
		var faces: PackedVector3Array = (s as ConcavePolygonShape3D).get_faces() if s is ConcavePolygonShape3D else PackedVector3Array()
		if s is ConvexPolygonShape3D:
			var hull := []
			var ymin := 1e9
			var ymax := -1e9
			for v in (s as ConvexPolygonShape3D).points:
				var p: Vector3 = xf * v
				hull.append([p.x, p.z])
				ymin = minf(ymin, p.y)
				ymax = maxf(ymax, p.y)
			rec["hull"] = hull
			rec["y"] = [ymin, ymax]
		else:
			var segs := []
			var flats := []
			for i in range(0, faces.size(), 3):
				var a: Vector3 = xf * faces[i]
				var bb: Vector3 = xf * faces[i + 1]
				var c: Vector3 = xf * faces[i + 2]
				var n := (bb - a).cross(c - a)
				if n.length() < 1e-9:
					continue
				n = n.normalized()
				if absf(n.y) < 0.3:
					# a wall face: its plan trace is the longest horizontal extent
					var pa := Vector2(a.x, a.z)
					var pb := Vector2(bb.x, bb.z)
					var pc := Vector2(c.x, c.z)
					var best := [pa, pb]
					if pb.distance_to(pc) > best[0].distance_to(best[1]):
						best = [pb, pc]
					if pa.distance_to(pc) > best[0].distance_to(best[1]):
						best = [pa, pc]
					segs.append([best[0].x, best[0].y, best[1].x, best[1].y, minf(a.y, minf(bb.y, c.y)), maxf(a.y, maxf(bb.y, c.y))])
				else:
					flats.append([a.x, a.z, bb.x, bb.z, c.x, c.z, (a.y + bb.y + c.y) / 3.0])
			rec["segs"] = segs
			rec["flats"] = flats
	else:
		rec["other"] = s.get_class()
		rec["at"] = [xf.origin.x, xf.origin.z]
	out.store_line(JSON.stringify(rec))
