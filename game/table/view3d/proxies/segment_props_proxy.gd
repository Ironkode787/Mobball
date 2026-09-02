class_name SegmentPropsProxy3D
extends HardwareProxy3D
## The landmark architecture each career segment paints in 2D, rebuilt as furniture: City
## Hall's drum, dome and finial; the Commission's long table; the Docks' water, quay boards
## and gantry; the Club's marquee. Pure set dressing — nothing here is a collider — but it is
## what makes the upper storeys read as rooms rather than as felt with rails on it.

func build() -> void:
	follow_transform = false
	if source is CityHall:
		_build_city_hall()
	elif source is Penthouse:
		_build_penthouse()
	elif source is Docks:
		_build_docks()
	elif source is ClubDeck:
		_build_club()


func _build_city_hall() -> void:
	var S := TableSpace.SCALE
	var c := TableSpace.to3(CityHall.DOME_CENTER, TableSpace.DECK_HEIGHT)
	var r := CityHall.DOME_R * S
	# steps, drum, dome, finial
	var st := View3DMesh.begin()
	View3DMesh.post(st, Vector2(c.x, c.z), r * 1.35, 0.10, c.y, 40)
	View3DMesh.post(st, Vector2(c.x, c.z), r * 1.18, 0.10, c.y + 0.10, 40)
	mesh_node(View3DMesh.finish(st, lib.paper()), null, "Steps")
	var drum := CylinderMesh.new()
	drum.top_radius = r
	drum.bottom_radius = r
	drum.height = 1.4
	drum.radial_segments = 40
	var dm := mesh_node(drum, lib.paper(), "Drum")
	dm.position = c + Vector3(0.0, 0.2 + 0.7, 0.0)
	var cols := View3DMesh.begin()
	for i in range(12):
		var a := TAU * float(i) / 12.0
		View3DMesh.post(cols, Vector2(c.x + cos(a) * r * 1.08, c.z + sin(a) * r * 1.08), 0.07, 1.3, c.y + 0.2, 8)
	mesh_node(View3DMesh.finish(cols, lib.paper()), null, "Colonnade")
	var dome := SphereMesh.new()
	dome.radius = r * 0.96
	dome.height = r * 0.96
	dome.is_hemisphere = true
	dome.radial_segments = 40
	dome.rings = 16
	var dome_mi := mesh_node(dome, lib.brass(), "Dome")
	dome_mi.position = c + Vector3(0.0, 1.6, 0.0)
	var finial := CylinderMesh.new()
	finial.top_radius = 0.0
	finial.bottom_radius = 0.10
	finial.height = 0.7
	var fm := mesh_node(finial, lib.brass(), "Finial")
	fm.position = c + Vector3(0.0, 1.6 + r * 0.96 + 0.3, 0.0)
	# the golden sign over the mouth
	var sign := TextMesh.new()
	sign.text = "CITY HALL"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 72
	sign.pixel_size = 0.009
	sign.depth = 0.04
	var sm := mesh_node(sign, lib.neon(Color("E8C64A"), 2.2), "Sign")
	sm.position = c + Vector3(0.0, 0.9, r * 1.02 + 0.05)


func _build_penthouse() -> void:
	var S := TableSpace.SCALE
	var at := TableSpace.to3(Penthouse.TABLE_AT, TableSpace.DECK_HEIGHT)
	var size := Penthouse.TABLE_SIZE * S
	var top := BoxMesh.new()
	top.size = Vector3(size.x, 0.06, size.y)
	var tm := mesh_node(top, lib.wood(), "LongTable")
	tm.position = at + Vector3(0.0, 0.40, 0.0)
	var legs := View3DMesh.begin()
	for sx in [-0.45, 0.45]:
		for sz in [-0.35, 0.35]:
			View3DMesh.post(legs, Vector2(at.x + size.x * sx, at.z + size.y * sz), 0.03, 0.38, at.y, 6)
	mesh_node(View3DMesh.finish(legs, lib.wood_dark()), null, "Legs")
	# a low glass parapet along the room's front edge, violet velvet inside
	var b: Rect2 = (source as Penthouse).bounds()
	var carpet := PlaneMesh.new()
	carpet.size = Vector2(b.size.x * S * 0.8, b.size.y * S * 0.55)
	var cm := mesh_node(carpet, lib.plastic(Color("2A2440"), 0.95), "Carpet")
	cm.position = TableSpace.to3(b.get_center() + Vector2(0.0, -30.0), TableSpace.DECK_HEIGHT + 0.004)
	var sign := TextMesh.new()
	sign.text = "THE PENTHOUSE"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 56
	sign.pixel_size = 0.008
	sign.depth = 0.03
	var sm := mesh_node(sign, lib.neon(Color("8C4DFF"), 2.4), "Sign")
	sm.position = TableSpace.to3(Vector2(b.get_center().x, b.position.y + 10.0), TableSpace.DECK_HEIGHT + 0.6)


func _build_docks() -> void:
	var S := TableSpace.SCALE
	var water := PlaneMesh.new()
	water.size = Docks.WATER_SIZE * S * 1.15
	var wm := mesh_node(water, lib.water(), "Harbour")
	wm.position = TableSpace.to3(Docks.WATER_AT, 0.003)
	# quay boards
	var st := View3DMesh.begin()
	var q0 := Docks.QUAY_FROM * S
	var q1 := Docks.QUAY_TO * S
	var n := 6
	for i in range(n):
		var a := q0.lerp(q1, float(i) / float(n))
		var b := q0.lerp(q1, float(i + 1) / float(n) - 0.02)
		View3DMesh.prism(st, PackedVector2Array([a + Vector2(0, -0.02), b + Vector2(0, -0.02), b + Vector2(0, 0.14), a + Vector2(0, 0.14)]), 0.02, 0.0)
	mesh_node(View3DMesh.finish(st, lib.wood()), null, "Quay")
	# gantry crane: two legs and a beam along the rail
	var g0 := TableSpace.to3(Docks.GANTRY_FROM, 0.0)
	var g1 := TableSpace.to3(Docks.GANTRY_TO, 0.0)
	var h := 1.1
	var gantry := View3DMesh.begin()
	View3DMesh.post(gantry, Vector2(g0.x, g0.z), 0.05, h, 0.0, 8)
	View3DMesh.post(gantry, Vector2(g1.x, g1.z), 0.05, h, 0.0, 8)
	View3DMesh.tube(gantry, PackedVector3Array([g0 + Vector3(0, h, 0), g1 + Vector3(0, h, 0)]), 0.05, 6)
	View3DMesh.tube(gantry, PackedVector3Array([g0 + Vector3(0, h - 0.18, 0), g1 + Vector3(0, h - 0.18, 0)]), 0.03, 6)
	mesh_node(View3DMesh.finish(gantry, lib.plastic(Color("A9552E"), 0.6)), null, "Gantry")
	var sign := TextMesh.new()
	sign.text = "THE DOCKS"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 44
	sign.pixel_size = 0.0075
	sign.depth = 0.03
	var sm := mesh_node(sign, lib.neon(Color("2EE6D6"), 2.4), "Sign")
	sm.position = (g0 + g1) * 0.5 + Vector3(0.0, h + 0.28, 0.0)


func _build_club() -> void:
	var S := TableSpace.SCALE
	var b: Rect2 = (source as ClubDeck).bounds()
	var sign := TextMesh.new()
	sign.text = "THE CLUB"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 64
	sign.pixel_size = 0.009
	sign.depth = 0.04
	var sm := mesh_node(sign, lib.neon(Color("FF2E63"), 2.6), "Sign")
	sm.position = TableSpace.to3(Vector2(b.get_center().x, b.position.y + 12.0), TableSpace.DECK_HEIGHT + 0.7)
	# a velvet rope along the deck's front lip: brass posts, red rope
	var st := View3DMesh.begin()
	var z := (b.end.y - 26.0) * S
	var posts := 5
	var pts := PackedVector3Array()
	for i in range(posts):
		var x := lerpf(b.position.x + 40.0, b.end.x - 40.0, float(i) / float(posts - 1)) * S
		View3DMesh.post(st, Vector2(x, z), 0.03, 0.42, TableSpace.DECK_HEIGHT, 8)
		pts.append(Vector3(x, TableSpace.DECK_HEIGHT + 0.40, z))
		if i < posts - 1:
			var nx := lerpf(b.position.x + 40.0, b.end.x - 40.0, float(i + 1) / float(posts - 1)) * S
			pts.append(Vector3((x + nx) * 0.5, TableSpace.DECK_HEIGHT + 0.30, z))
	mesh_node(View3DMesh.finish(st, lib.brass()), null, "RopePosts")
	var rope := View3DMesh.begin()
	View3DMesh.tube(rope, pts, 0.018, 6)
	mesh_node(View3DMesh.finish(rope, lib.plastic(Color("8A1E2E"), 0.8)), null, "Rope")
