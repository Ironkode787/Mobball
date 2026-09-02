class_name TargetProxy3D
extends HardwareProxy3D
## Standup and drop targets: a plate on a post with a lit face. A dropped target sinks into
## the playfield; a marked one holds a settled glow; a cop (danger) burns police blue.

const COL_LAMP := Color(1.0, 0.86, 0.55)
const COL_COP := Color("3A8DFF")
const COL_DONE := Color("F2E8D5")

var _lamp: StandardMaterial3D = null
var _plate: Node3D = null
var _sink: float = 0.0
var _pulse: float = 0.0


func build() -> void:
	var length: float = float(source.get("length")) * TableSpace.SCALE
	var thick: float = float(source.get("thickness")) * TableSpace.SCALE
	_plate = Node3D.new()
	_plate.name = "Plate"
	add_child(_plate)
	var body := BoxMesh.new()
	body.size = Vector3(length, 0.40, thick)
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = lib.ink()
	bm.position.y = 0.20
	_plate.add_child(bm)
	_lamp = lib.lamp(COL_LAMP)
	var face := BoxMesh.new()
	face.size = Vector3(length * 0.78, 0.24, 0.012)
	var fm := MeshInstance3D.new()
	fm.mesh = face
	fm.material_override = _lamp
	fm.position = Vector3(0.0, 0.24, thick * 0.5 + 0.006)     # local +y (2D) = +z: the ball's side
	_plate.add_child(fm)
	var st := View3DMesh.begin()
	View3DMesh.post(st, Vector2(0.0, -thick * 0.5 - 0.03), 0.03, 0.30, 0.0, 8)
	var pm := MeshInstance3D.new()
	pm.mesh = View3DMesh.finish(st, lib.chrome_dark())
	_plate.add_child(pm)


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var tok := token()
	var state := state_name(tok)
	var color := COL_LAMP
	var wanted := 0.12
	match state:
		&"armed": wanted = 1.1
		&"active": wanted = 1.1
		&"completed":
			wanted = 0.7
			color = COL_DONE
		&"danger":
			wanted = 2.2
			color = COL_COP
		&"disabled": wanted = 0.0
	if has_mod(tok, &"pulse") or has_mod(tok, &"flash"):
		_pulse = 1.0
	_pulse = maxf(_pulse - delta * 4.5, 0.0)
	if _lamp.emission != color:
		_lamp.emission = color
		_lamp.albedo_color = color.darkened(0.55)
	drive_lamp(_lamp, wanted + _pulse * 3.0, delta, 16.0)
	var down := bool(source.get("down")) if source is DropTarget else false
	var target_sink := 0.42 if down else 0.0
	_sink = target_sink if delta <= 0.0 else lerpf(_sink, target_sink, 1.0 - exp(-14.0 * delta))
	_plate.position.y = -_sink
