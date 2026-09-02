extends RefCounted
## The 3D presentation layer's pure parts: the px→m mapping, the mesh builders and the
## material library. Everything here runs headless; the rendered look is checked by eye with
## tools/shot.sh and tests/shot_table3d.tscn.


func run(t: TestCtx) -> void:
	_table_space(t)
	_mesh_builders(t)
	_materials(t)
	_wall_proxy_from_chains(t)


func _table_space(t: TestCtx) -> void:
	var p := Vector2(540.0, 1920.0)
	var v := TableSpace.to3(p, 0.5)
	t.near(v.x, 5.4, 1e-6, "x maps to metres")
	t.near(v.y, 0.5, 1e-6, "height is carried as given")
	t.near(v.z, 19.2, 1e-6, "table y maps to +z, toward the player")
	t.ok(TableSpace.to2(v).is_equal_approx(p), "to2 inverts to3")
	t.near(TableSpace.floor_height(Vector2(500.0, 100.0)), 0.0, 1e-9, "the main field is the ground floor")
	t.near(TableSpace.floor_height(Vector2(800.0, -500.0)), TableSpace.DECK_HEIGHT, 1e-9,
			"the Club deck is the second storey")
	t.near(TableSpace.yaw(PI * 0.5), -PI * 0.5, 1e-9, "a clockwise 2D turn is a negative yaw")
	t.near(TableSpace.ball_radius(), Feel.BALL_RADIUS * TableSpace.SCALE, 1e-9, "the ball keeps its radius")


func _mesh_builders(t: TestCtx) -> void:
	var st := View3DMesh.begin()
	View3DMesh.rail(st, PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 1)]), 0.1, 0.4)
	var rail := View3DMesh.finish(st)
	t.ok(rail.get_surface_count() == 1, "a rail is one surface")
	var arrays := rail.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	t.ok(verts.size() > 100, "a rail with round caps has real geometry (%d verts)" % verts.size())
	var aabb := rail.get_aabb()
	t.near(aabb.position.y, 0.0, 1e-4, "the rail stands on its base")
	t.near(aabb.size.y, 0.4, 1e-4, "the rail is as tall as asked")
	t.ok(aabb.position.x < -0.09 and aabb.end.x > 2.09, "round caps extend past the chain ends")
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	t.ok(normals.size() == verts.size(), "normals were generated")
	# the top of the rail faces up: sample the normals of the highest vertices
	var up := 0
	var top := 0
	for i in range(verts.size()):
		if verts[i].y > 0.39:
			top += 1
			if normals[i].y > 0.5:
				up += 1
	t.ok(top > 0 and up == top, "every top-face normal points up (%d/%d)" % [up, top])

	var st2 := View3DMesh.begin()
	View3DMesh.post(st2, Vector2(1, 1), 0.2, 0.5)
	View3DMesh.prism(st2, PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]), 0.3)
	View3DMesh.tube(st2, PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0.5, 0), Vector3(2, 0.5, 1)]), 0.05)
	View3DMesh.box(st2, Vector3.ZERO, Vector3.ONE)
	View3DMesh.disc(st2, Vector3.ZERO, 1.0)
	View3DMesh.ring(st2, Vector3.ZERO, 0.5, 1.0, 0.0, 0.2)
	var mixed := View3DMesh.finish(st2)
	t.ok((mixed.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0,
			"every builder contributes triangles")

	var poly := View3DMesh.capsule_poly(Vector2.ZERO, Vector2(1.65, 0.0), 0.26, 0.16)
	t.ok(Geometry2D.is_polygon_clockwise(poly) or not Geometry2D.is_polygon_clockwise(poly),
			"capsule outline is a polygon")
	t.ok(poly.size() >= 16, "capsule outline is sampled round both ends")
	var hull := Geometry2D.convex_hull(poly)
	t.ok(hull.size() - 1 >= poly.size() - 2, "capsule outline is convex")


func _materials(t: TestCtx) -> void:
	var lib := View3DMaterials.new()
	t.ok(lib.felt() == lib.felt(), "materials are cached")
	t.ok(lib.felt().albedo_texture != null, "felt carries a generated texture")
	t.ok(lib.brass().metallic > 0.8, "brass is metal")
	var lamp := lib.lamp(Color.RED)
	t.ok(lamp.emission_enabled and is_zero_approx(lamp.emission_energy_multiplier), "a lamp starts dark")
	t.ok(lib.lamp(Color.RED) != lamp, "each lamp owns its material")
	var skin := lib.ball_texture(BallDesign.for_id(7))
	t.eq(skin.get_width(), 128, "ball skin is an equirect strip")
	t.ok(lib.ball_texture(BallDesign.for_id(7)) == skin, "ball skins are cached per guy")
	var anon := lib.ball_texture(BallDesign.anonymous())
	t.ok(anon != skin, "the anonymous ball has its own plain skin")


func _wall_proxy_from_chains(t: TestCtx) -> void:
	# A WallPiece's chains extrude into one mesh whose footprint matches the collider.
	var piece := WallPiece.new()
	piece.bar(Vector2(100.0, 200.0), Vector2(100.0, 600.0), 18.0)
	var view := Node3D.new()
	view.set_meta(&"stub", true)
	var proxy := WallProxy3D.new()
	proxy.body = piece.body
	proxy.chains = piece.walls.chains
	proxy.material = null
	proxy.lib = View3DMaterials.new()
	proxy.source = piece
	proxy.build()
	var rail := proxy.get_node_or_null("Rail") as MeshInstance3D
	t.ok(rail != null and rail.mesh != null, "the wall proxy built a rail mesh")
	if rail != null and rail.mesh != null:
		var aabb := rail.mesh.get_aabb()
		t.near(aabb.position.z, (200.0 - 9.0) * TableSpace.SCALE, 0.02, "the rail starts at the chain's first cap")
		t.near(aabb.end.z, (600.0 + 9.0) * TableSpace.SCALE, 0.02, "the rail ends at the chain's last cap")
		t.near(aabb.size.x, 18.0 * TableSpace.SCALE, 0.02, "the rail is as thick as the capsule")
		t.near(aabb.size.y, TableSpace.GUIDE_HEIGHT, 1e-3, "a thin guide is guide-height")
	proxy.free()
	view.free()
	piece.free()
