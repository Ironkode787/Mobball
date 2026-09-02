class_name RolloverProxy3D
extends HardwareProxy3D
## A lane rollover: a chrome wire over a lit insert. Lit lanes are the Drop-Off skill shot's
## moving window, so the insert is the loudest thing in the top lanes when it is on.

var _lamp: StandardMaterial3D = null


func build() -> void:
	var r := Rollover.RADIUS * TableSpace.SCALE * 0.72
	_lamp = lib.lamp(Color(1.0, 0.78, 0.36))
	var st := View3DMesh.begin()
	View3DMesh.disc(st, Vector3(0.0, 0.008, 0.0), r, 22)
	mesh_node(View3DMesh.finish(st, _lamp), null, "Insert")
	var wire := View3DMesh.begin()
	var path := PackedVector3Array([
		Vector3(0.0, 0.0, -r * 1.3), Vector3(0.0, 0.10, -r * 0.9), Vector3(0.0, 0.14, 0.0),
		Vector3(0.0, 0.10, r * 0.9), Vector3(0.0, 0.0, r * 1.3),
	])
	View3DMesh.tube(wire, path, 0.016, 6, false)
	mesh_node(View3DMesh.finish(wire, lib.steel()), null, "Wire")


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var r := source as Rollover
	var flash := float(peek(&"_flash", 0.0))
	drive_lamp(_lamp, (1.6 if r.lit else 0.10) + flash * 3.0, delta, 14.0)
