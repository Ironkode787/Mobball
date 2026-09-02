class_name TableDressing
extends Node3D
## The machine's set dressing: lamp rows along the rails, translucent plastics with the
## authored art, rooftop toys over the shops, apron cards, general illumination. Nothing here
## is a collider; the root builds it once after the hardware so it can read positions off
## the Layout and the segments.

var _lib: MaterialLib = null
var _bulbs: StandardMaterial3D = null
var _clock: float = 0.0
var _toys: Array[Node3D] = []
var _drums: Array[Node3D] = []
## Dressing that belongs to a piece of hardware shows only while that piece stands.
var _tied: Array[Dictionary] = []      ## { node: Node3D, hardware: Node }
var _root: Node3D = null


func build(root: Node3D) -> void:
	_lib = MaterialLib.shared()
	_root = root
	_build_lamp_rows()
	_build_plastics()
	_build_toys()
	_build_apron()
	_build_gi(root)


func _tie(node: Node3D, hardware: Node) -> void:
	if hardware != null:
		_tied.append({"node": node, "hardware": hardware})


func _hardware(prop: String, index: int = -1) -> Node:
	if _root == null:
		return null
	var v: Variant = _root.get(prop)
	if v is Array and index >= 0 and index < (v as Array).size():
		return (v as Array)[index]
	return v if v is Node else null


# ------------------------------------------------------------------- lamp rows -----


func _build_lamp_rows() -> void:
	_bulbs = _lib.lamp(Color(1.0, 0.86, 0.6))
	_bulbs.emission_energy_multiplier = 1.6
	var st := MeshLib.begin()
	var count := 0
	# along the arch
	for i in range(19):
		var deg := lerpf(186.0, 354.0, float(i) / 18.0)
		var p := Layout.arch_point(deg, Layout.ARCH_RADIUS - Layout.OUTER_THICK * 0.5 - 0.06)
		MeshLib.post(st, p, 0.032, 0.05, Layout.WALL_HEIGHT * 1.6 - 0.02, 8)
		count += 1
	# down both sides
	for z in range(-2, 5):
		for x in [Layout.PLAY_LEFT + Layout.OUTER_THICK * 0.5 + 0.06, Layout.PLAY_RIGHT - Layout.OUTER_THICK * 0.5 - 0.06]:
			MeshLib.post(st, Vector2(x, float(z) * 1.0 + 0.4), 0.032, 0.05, Layout.WALL_HEIGHT * 1.6 - 0.02, 8)
			count += 1
	# inserts up the centre alley: the "shoot here" chevrons that light in sequence
	var mi := MeshInstance3D.new()
	mi.mesh = MeshLib.finish(st, _bulbs)
	mi.name = "LampRows"
	add_child(mi)


# ------------------------------------------------------------------- plastics -----


func _plastic(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _build_plastics() -> void:
	# sling plastics: a translucent triangle floating over each sling
	for s: float in [1.0, -1.0]:
		var a := Layout.mx(Layout.SLING_OUTER_BOTTOM, s)
		var b := Layout.mx(Layout.SLING_INNER, s)
		var c := Layout.mx(Layout.SLING_OUTER_TOP, s)
		var centroid := (a + b + c) / 3.0
		var poly := PackedVector2Array()
		for p in [a, b, c]:
			poly.append(centroid + (p - centroid) * 1.35)
		var st := MeshLib.begin()
		MeshLib.prism(st, poly, 0.02, 0.44, true, 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, _plastic(Feel.COL_NEON_ROSE if s < 0.0 else Feel.COL_NEON_TEAL, 0.42))
		mi.name = "SlingPlastic"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# the payphone bank: a pedestal phone behind each wire target, or the flat art if the
	# toy is missing
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"prop.payphone_bank", null, false)
	if ToyLib.has(&"payphone"):
		var face_yaw := Layout.yaw_facing(Layout.WIRE_FACE)
		for i in range(Layout.WIRE_AT.size()):
			var phone := ToyLib.instance(&"payphone")
			var at: Vector2 = Layout.WIRE_AT[i]
			phone.position = Layout.p3(at - Layout.WIRE_FACE * 0.17, 0.0)
			phone.rotation.y = face_yaw
			phone.scale = Vector3.ONE * 0.85
			var face := _lib.lamp(Color(1.0, 0.86, 0.55))
			face.emission_energy_multiplier = 0.9
			ToyLib.bind(phone, "Lamp", face)
			phone.name = "Payphone%d" % (i + 1)
			add_child(phone)
			_tie(phone, _hardware("wire_bank"))
	elif tex != null:
		var quad := PlaneMesh.new()
		var w := 1.0
		quad.size = Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
		quad.orientation = PlaneMesh.FACE_Z
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = _lib.art(tex, 0.5)
		var mid: Vector2 = Layout.WIRE_AT[1]
		mi.position = Layout.p3(mid + Vector2(0.28, -0.05), 0.5 + quad.size.y * 0.5)
		mi.rotation.y = Layout.yaw_facing(Layout.WIRE_FACE) + PI
		mi.name = "PayphonePlastic"
		add_child(mi)
		_tie(mi, _hardware("wire_bank"))
	# pop nest plastic: a translucent rose ring plate over the three cans
	var nest := Vector2.ZERO
	for p in Layout.BUMPER_AT:
		nest += p
	nest /= float(Layout.BUMPER_AT.size())
	var ring := MeshLib.begin()
	MeshLib.ring(ring, Layout.p3(nest, 0.62), 0.55, 0.95, 0.0, 0.0, 32)
	var rm := MeshInstance3D.new()
	rm.mesh = MeshLib.finish(ring, _plastic(Feel.COL_BRASS, 0.35))
	rm.name = "PopPlastic"
	rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rm)
	var nest_owner: Variant = _root.get("_bumpers") if _root != null else null
	if nest_owner is Array and (nest_owner as Array).size() > 1:
		_tie(rm, (nest_owner as Array)[1])


# ------------------------------------------------------------------- toys -----


func _build_toys() -> void:
	if ToyLib.has(&"pizza_sign") and ToyLib.has(&"washing_machine") and ToyLib.has(&"safe"):
		_build_toy_meshes()
		return
	_build_toy_primitives()


## The generated toys (specs/meshes.md): each stands where its primitive stood.
func _build_toy_meshes() -> void:
	var pizza := ToyLib.instance(&"pizza_sign")
	var nonna: Vector2 = Layout.STOREFRONT_AT[1]
	pizza.position = Layout.p3(nonna + Vector2(0.0, -0.75), 0.60)
	add_child(pizza)
	var spin := ToyLib.find(pizza, "Spin")
	if spin != null:
		_toys.append(spin)
	_tie(pizza, _hardware("storefronts", 1))

	var washer := ToyLib.instance(&"washing_machine")
	var lucky: Vector2 = Layout.STOREFRONT_AT[0]
	washer.position = Layout.p3(lucky + Vector2(-0.35, -0.85), 0.66)
	washer.rotation.y = Layout.yaw_facing(Layout.STOREFRONT_FACING[0])
	add_child(washer)
	var door := ToyLib.find(washer, "Door")
	if door != null:
		_drums.append(door)
	_tie(washer, _hardware("storefronts", 0))

	var safe := ToyLib.instance(&"safe")
	var tony: Vector2 = Layout.STOREFRONT_AT[2]
	safe.position = Layout.p3(tony + Vector2(0.3, -0.85), 0.62)
	safe.rotation.y = Layout.yaw_facing(Layout.STOREFRONT_FACING[2])
	add_child(safe)
	_tie(safe, _hardware("storefronts", 2))


func _build_toy_primitives() -> void:
	# Nonna's: a slowly turning pizza on a pole over the pizzeria
	var pizza := Node3D.new()
	pizza.name = "PizzaSign"
	var nonna: Vector2 = Layout.STOREFRONT_AT[1]
	pizza.position = Layout.p3(nonna + Vector2(0.0, -0.75), 1.15)
	add_child(pizza)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.02
	pole.bottom_radius = 0.02
	pole.height = 0.55
	var pm := MeshInstance3D.new()
	pm.mesh = pole
	pm.material_override = _lib.brass_dark()
	pm.position.y = -0.27
	pizza.add_child(pm)
	var pie := CylinderMesh.new()
	pie.top_radius = 0.26
	pie.bottom_radius = 0.26
	pie.height = 0.05
	pie.radial_segments = 24
	var pie_mi := MeshInstance3D.new()
	pie_mi.mesh = pie
	var crust := _lib.lamp(Color("F0B040"))
	crust.emission_energy_multiplier = 0.6
	crust.albedo_color = Color("C98A3A")
	pie_mi.material_override = crust
	pizza.add_child(pie_mi)
	var slices := MeshLib.begin()
	for i in range(8):
		var a := TAU * float(i) / 8.0
		MeshLib.post(slices, Vector2(cos(a) * 0.14, sin(a) * 0.14), 0.035, 0.02, 0.025, 8)
	var sm := MeshInstance3D.new()
	sm.mesh = MeshLib.finish(slices, _lib.plastic(Color("8A1E1E"), 0.5))
	pizza.add_child(sm)
	_toys.append(pizza)
	_tie(pizza, _hardware("storefronts", 1))

	# Lucky's: a washing-machine drum on the roof, chrome door, turning
	var drum := Node3D.new()
	drum.name = "WashDrum"
	var lucky: Vector2 = Layout.STOREFRONT_AT[0]
	drum.position = Layout.p3(lucky + Vector2(-0.35, -0.85), 0.86)
	drum.rotation.y = Layout.yaw_facing(Layout.STOREFRONT_FACING[0])
	add_child(drum)
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 0.4, 0.34)
	var bm := MeshInstance3D.new()
	bm.mesh = box
	bm.material_override = _lib.paper()
	drum.add_child(bm)
	var door := Node3D.new()
	door.position = Vector3(0.0, 0.0, 0.17)
	drum.add_child(door)
	var porthole := CylinderMesh.new()
	porthole.top_radius = 0.14
	porthole.bottom_radius = 0.14
	porthole.height = 0.03
	var ph := MeshInstance3D.new()
	ph.mesh = porthole
	ph.material_override = _lib.chrome_dark()
	ph.rotation.x = PI * 0.5
	door.add_child(ph)
	var inner := MeshLib.begin()
	for i in range(3):
		var a := TAU * float(i) / 3.0
		MeshLib.post(inner, Vector2(cos(a) * 0.07, sin(a) * 0.07), 0.025, 0.02, 0.0, 6)
	var im := MeshInstance3D.new()
	im.mesh = MeshLib.finish(inner, _plastic(Feel.COL_NEON_TEAL, 0.9))
	im.rotation.x = PI * 0.5
	im.position.z = 0.02
	door.add_child(im)
	_toys.append(door)
	_tie(drum, _hardware("storefronts", 0))

	# Fat Tony's: a brass safe with a dial on the roof
	var safe := Node3D.new()
	safe.name = "PawnSafe"
	var tony: Vector2 = Layout.STOREFRONT_AT[2]
	safe.position = Layout.p3(tony + Vector2(0.3, -0.85), 0.82)
	safe.rotation.y = Layout.yaw_facing(Layout.STOREFRONT_FACING[2])
	add_child(safe)
	var sbox := BoxMesh.new()
	sbox.size = Vector3(0.36, 0.4, 0.3)
	var sbm := MeshInstance3D.new()
	sbm.mesh = sbox
	sbm.material_override = _lib.plastic(Color("2A2E36"), 0.35)
	safe.add_child(sbm)
	var dial := CylinderMesh.new()
	dial.top_radius = 0.07
	dial.bottom_radius = 0.07
	dial.height = 0.03
	var dm := MeshInstance3D.new()
	dm.mesh = dial
	dm.material_override = _lib.brass()
	dm.rotation.x = PI * 0.5
	dm.position = Vector3(0.0, 0.04, 0.165)
	safe.add_child(dm)
	var handle := BoxMesh.new()
	handle.size = Vector3(0.14, 0.03, 0.03)
	var hm := MeshInstance3D.new()
	hm.mesh = handle
	hm.material_override = _lib.brass()
	hm.position = Vector3(0.0, -0.08, 0.165)
	safe.add_child(hm)
	_tie(safe, _hardware("storefronts", 2))


# ------------------------------------------------------------------- apron -----


func _build_apron() -> void:
	var font: Font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	var cards := [
		[Layout.MIRROR_X - 1.55, "HOW TO PLAY", ["HIT BANKS TO OPEN THE SHOPS", "SHOOT THE STAIRCASE FOR THE CLUB", "LEAN, BUT MIND THE INSPECTOR"]],
		[Layout.MIRROR_X + 1.55, "KINGPIN", ["3 GUYS PER NIGHT", "POINTS ARE MONEY", "THE FAMILY RUNS THIS TOWN"]],
	]
	for card: Array in cards:
		var x: float = card[0]
		var st := MeshLib.begin()
		MeshLib.box(st, Vector3(x, 0.04, 4.95), Vector3(0.82, 0.06, 0.58))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, _lib.paper())
		add_child(mi)
		var frame := MeshLib.begin()
		MeshLib.box(frame, Vector3(x, 0.075, 4.95), Vector3(0.86, 0.01, 0.62))
		var fm := MeshInstance3D.new()
		fm.mesh = MeshLib.finish(frame, _lib.brass_dark())
		fm.position.y = -0.006
		add_child(fm)
		var title := TextMesh.new()
		title.text = String(card[1])
		title.font = font
		title.font_size = 40
		title.pixel_size = 0.0028
		title.depth = 0.004
		var tm := MeshInstance3D.new()
		tm.mesh = title
		tm.material_override = _lib.plastic(Color("2A1E14"), 0.8)
		tm.position = Vector3(x, 0.074, 4.76)
		tm.rotation.x = -PI * 0.5
		add_child(tm)
		var lines: Array = card[2]
		for i in range(lines.size()):
			var line := TextMesh.new()
			line.text = String(lines[i])
			line.font = font
			line.font_size = 24
			line.pixel_size = 0.0024
			line.depth = 0.003
			var lm := MeshInstance3D.new()
			lm.mesh = line
			lm.material_override = _lib.plastic(Color("3A2A1C"), 0.8)
			lm.position = Vector3(x, 0.074, 4.88 + float(i) * 0.1)
			lm.rotation.x = -PI * 0.5
			add_child(lm)


# ------------------------------------------------------------------- GI -----


func _build_gi(_root: Node3D) -> void:
	for at in [Vector3(-1.4, 2.3, 1.2), Vector3(1.4, 2.3, 1.2)]:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.9, 0.74)
		l.light_energy = 0.7
		l.omni_range = 5.5
		l.omni_attenuation = 1.5
		l.shadow_enabled = false
		l.position = at
		add_child(l)


func _process(delta: float) -> void:
	_clock += delta
	for t in _tied:
		var node: Node3D = t["node"]
		var hw: Node = t["hardware"]
		if is_instance_valid(node) and is_instance_valid(hw):
			var on := true
			if hw.has_method(&"is_hardware_active"):
				on = bool(hw.call(&"is_hardware_active"))
			elif hw is Node3D:
				on = (hw as Node3D).visible
			node.visible = on
	for t in _toys:
		if is_instance_valid(t):
			t.rotation.y += delta * 0.6
	for d in _drums:
		if is_instance_valid(d):
			d.rotation.z += delta * 1.4
	if _bulbs != null:
		_bulbs.emission_energy_multiplier = 1.5 + 0.15 * sin(_clock * 2.3)
