class_name BossProxy3D
extends HardwareProxy3D
## Commission hardware — Sammy's sedan, the Butcher's truck — as vehicles riding their rail.
## Body colour comes from the 2D piece; a roof lamp marks the hits it still has to take.

var _lamp: StandardMaterial3D = null
var _pulse: float = 0.0


func build() -> void:
	var b := source as BossTarget
	var S := TableSpace.SCALE
	var l := b.body_length * S
	var w := b.body_thick * S
	var body := BoxMesh.new()
	body.size = Vector3(l, 0.30, w)
	var bm := mesh_node(body, lib.plastic(b.color, 0.35), "Body")
	bm.position.y = 0.19
	var cabin := BoxMesh.new()
	cabin.size = Vector3(l * 0.55, 0.20, w * 0.82)
	var cm := mesh_node(cabin, lib.plastic(Color("1A1C22"), 0.2), "Cabin")
	cm.position = Vector3(-l * 0.08, 0.44, 0.0)
	var wheels := View3DMesh.begin()
	for sx in [-0.34, 0.34]:
		for sz in [-1.0, 1.0]:
			View3DMesh.post(wheels, Vector2(l * sx, w * 0.5 * sz), 0.075, 0.09, 0.02, 10)
	mesh_node(View3DMesh.finish(wheels, lib.rubber()), null, "Wheels")
	_lamp = lib.lamp(Color("E23D3D"))
	var roof := BoxMesh.new()
	roof.size = Vector3(0.10, 0.06, 0.10)
	var rm := mesh_node(roof, _lamp, "RoofLamp")
	rm.position = Vector3(l * 0.18, 0.56, 0.0)


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var b := source as BossTarget
	var tok := token()
	if state_name(tok) == &"active" or has_mod(tok, &"pulse"):
		_pulse = 1.0
	_pulse = maxf(_pulse - delta * 4.0, 0.0)
	drive_lamp(_lamp, (1.4 if b.is_armed() else 0.0) + _pulse * 3.0, delta, 14.0)
