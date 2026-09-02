class_name OrbitProxy3D
extends HardwareProxy3D
## An orbit is two switches and the wall between them; this puts a lit arrow insert at each
## end so the loop reads as a shot from the flippers.

var _lamps: Array[StandardMaterial3D] = []


func build() -> void:
	follow_transform = false
	var o := source as OrbitLane
	for at in [o.entry_position(), o.exit_position()]:
		var lamp := lib.lamp(Color(1.0, 0.80, 0.38))
		_lamps.append(lamp)
		var st := View3DMesh.begin()
		var c := TableSpace.to3(at, TableSpace.floor_height(at) + 0.008)
		# a chevron pointing up the lane (toward the exit)
		var d := (o.exit_position() - o.entry_position()).normalized()
		var d3 := Vector3(d.x, 0.0, d.y)
		var side := Vector3(-d3.z, 0.0, d3.x)
		var tip := c + d3 * 0.22
		var tail_l := c - d3 * 0.12 + side * 0.20
		var tail_r := c - d3 * 0.12 - side * 0.20
		var notch := c - d3 * 0.02
		View3DMesh.tri(st, tip, tail_l, notch, Vector3.UP)
		View3DMesh.tri(st, tip, notch, tail_r, Vector3.UP)
		mesh_node(View3DMesh.finish(st, lamp), null, "Arrow")


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var o := source as OrbitLane
	var flash := float(peek(&"_flash", 0.0))
	var armed := bool(o.call(&"armed")) if o.has_method(&"armed") else false
	for l in _lamps:
		drive_lamp(l, (1.5 if armed else 0.35) + flash * 2.5, delta, 10.0)
