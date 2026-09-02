class_name StorefrontProxy3D
extends HardwareProxy3D
## A storefront bank: the drop targets are their own proxies; this is the building behind
## them — authored façade art on a block, a neon sign over the door, a lit doorway that
## invites the shot when the bank is down.

const ART := {
	&"storefront_laundromat": &"front.laundromat",
	&"storefront_pizzeria": &"front.pizzeria",
	&"storefront_pawn": &"front.pawn",
}
const NEON := {
	&"storefront_laundromat": Color("2EE6D6"),
	&"storefront_pizzeria": Color("FF2E63"),
	&"storefront_pawn": Color("FFC341"),
}

var _door_lamp: StandardMaterial3D = null
var _light: OmniLight3D = null
var _neon_color: Color = Color("FF2E63")


func build() -> void:
	var s := source as Storefront
	var S := TableSpace.SCALE
	var span := (s.half_span() * 2.0 + 34.0) * S
	var depth := 0.42
	var front_z := -(Storefront.DOOR_DEPTH + 14.0 + 22.0) * S     # behind the doorway
	var height := 0.95
	_neon_color = NEON.get(s.id, Color("FF2E63"))
	var st := View3DMesh.begin()
	View3DMesh.box(st, Vector3(0.0, height * 0.5, front_z - depth * 0.5), Vector3(span, height, depth), 0.6)
	mesh_node(View3DMesh.finish(st, lib.wood()), null, "Building")
	var tex: Texture2D = null
	var art_key: StringName = ART.get(s.id, &"")
	if art_key != &"" and Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(art_key, null, false)
	if tex != null:
		var quad := PlaneMesh.new()
		var w := span * 0.94
		quad.size = Vector2(w, w * float(tex.get_height()) / float(tex.get_width()))
		quad.orientation = PlaneMesh.FACE_Z
		var mi := mesh_node(quad, lib.art(tex, 0.35), "Facade")
		mi.position = Vector3(0.0, quad.size.y * 0.5 + 0.02, front_z + 0.012)
	# the doorway: a lit threshold the ball rolls over when the shutters are down
	_door_lamp = lib.lamp(_neon_color.lerp(Color.WHITE, 0.25))
	var door := BoxMesh.new()
	door.size = Vector3(span * 0.5, 0.012, (Storefront.DOOR_DEPTH - 30.0) * S)
	var dm := mesh_node(door, _door_lamp, "Threshold")
	dm.position = Vector3(0.0, 0.01, -(Storefront.DOOR_DEPTH * 0.5 + 14.0) * S)
	# neon over the door
	var sign := TextMesh.new()
	sign.text = String(s.sign_text)
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 64
	sign.pixel_size = 0.0075
	sign.depth = 0.03
	sign.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sm := mesh_node(sign, lib.neon(_neon_color, 2.8), "Neon")
	sm.position = Vector3(0.0, height + 0.26, front_z - 0.04)
	var backer := BoxMesh.new()
	backer.size = Vector3(span * 0.9, 0.46, 0.04)
	var bk := mesh_node(backer, lib.ink(), "SignBacker")
	bk.position = Vector3(0.0, height + 0.26, front_z - 0.08)
	var at := TableSpace.to3(source.global_position, floor_height()) + Vector3(0.0, height + 0.6, 0.0)
	_light = view.call(&"request_lamp", at, _neon_color, 0.0, 3.6)


func sync(delta: float) -> void:
	super.sync(delta)
	var s := source as Storefront
	var tok := token()
	var state := state_name(tok)
	var wanted := 0.0
	if s.is_open():
		wanted = 0.9
	elif state == &"disabled" or has_mod(tok, &"cooldown"):
		wanted = 0.0
	drive_lamp(_door_lamp, wanted, delta, 10.0)
	if _light != null:
		_light.visible = visible
		var flicker := 0.92 + 0.08 * sin(Time.get_ticks_msec() * 0.021 + float(source.get_instance_id() % 97))
		_light.light_energy = (1.1 if visible else 0.0) * flicker
