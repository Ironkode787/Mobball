class_name GateProxy3D
extends HardwareProxy3D
## A one-way wire gate hinged from a bar across the lane; it swings toward the side the ball
## passes to and hangs shut otherwise.

var _flap: Node3D = null
var _swing_sign: float = 1.0
var _angle: float = 0.0


func build() -> void:
	follow_transform = false
	var g := source as OneWayGate
	var S := TableSpace.SCALE
	var fh := TableSpace.floor_height(g.from_point)
	var a := TableSpace.to3(g.from_point, fh)
	var b := TableSpace.to3(g.to_point, fh)
	var top := 0.34
	var st := View3DMesh.begin()
	View3DMesh.tube(st, PackedVector3Array([a + Vector3(0, top, 0), b + Vector3(0, top, 0)]), 0.014, 6)
	View3DMesh.post(st, Vector2(a.x, a.z), 0.03, top + 0.04, fh, 8)
	View3DMesh.post(st, Vector2(b.x, b.z), 0.03, top + 0.04, fh, 8)
	mesh_node(View3DMesh.finish(st, lib.chrome_dark()), null, "Frame")
	_flap = Node3D.new()
	_flap.name = "Flap"
	_flap.position = (a + b) * 0.5
	_flap.position.y = top + fh
	add_child(_flap)
	var axis := (b - a)
	var len_m := axis.length()
	var yaw := atan2(-axis.z, axis.x)
	_flap.rotation.y = yaw
	var st2 := View3DMesh.begin()
	var n := 4
	for i in range(n):
		var x := lerpf(-len_m * 0.5 + 0.05, len_m * 0.5 - 0.05, float(i) / float(n - 1))
		View3DMesh.tube(st2, PackedVector3Array([Vector3(x, 0.0, 0.0), Vector3(x, -(top - 0.06), 0.0)]), 0.011, 5)
	View3DMesh.tube(st2, PackedVector3Array([Vector3(-len_m * 0.5 + 0.05, -(top - 0.06), 0.0), Vector3(len_m * 0.5 - 0.05, -(top - 0.06), 0.0)]), 0.011, 5)
	var fm := MeshInstance3D.new()
	fm.mesh = View3DMesh.finish(st2, lib.steel())
	_flap.add_child(fm)
	# which way it swings: toward the passing side, in the flap's local frame
	var pass3 := Vector3(g.pass_from.x, 0.0, g.pass_from.y)
	var local_pass := Basis(Vector3.UP, -yaw) * pass3
	_swing_sign = -1.0 if local_pass.z < 0.0 else 1.0


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var open := bool(peek(&"_open", false))
	var wanted := deg_to_rad(62.0) * _swing_sign if open else 0.0
	_angle = wanted if delta <= 0.0 else lerpf(_angle, wanted, 1.0 - exp(-12.0 * delta))
	_flap.rotation.x = _angle
