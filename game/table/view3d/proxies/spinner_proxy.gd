class_name SpinnerProxy3D
extends HardwareProxy3D
## The numbers wheel: a bicycle wheel on an axle across the lane, turning with the sim's own
## blade angle. Two chrome posts carry the axle.

var _blade: Node3D = null


func build() -> void:
	var s := source as Spinner
	var w := s.lane_width * TableSpace.SCALE
	var axle_h := 0.40
	var st := View3DMesh.begin()
	View3DMesh.tube(st, PackedVector3Array([Vector3(-w * 0.5, axle_h, 0.0), Vector3(w * 0.5, axle_h, 0.0)]), 0.014, 6)
	View3DMesh.post(st, Vector2(-w * 0.5 - 0.02, 0.0), 0.035, axle_h + 0.05, 0.0, 8)
	View3DMesh.post(st, Vector2(w * 0.5 + 0.02, 0.0), 0.035, axle_h + 0.05, 0.0, 8)
	mesh_node(View3DMesh.finish(st, lib.chrome_dark()), null, "Axle")
	_blade = Node3D.new()
	_blade.name = "Blade"
	_blade.position.y = axle_h
	add_child(_blade)
	var radius := s.blade_length * TableSpace.SCALE * 0.5
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"prop.bicycle_spinner", null, false)
	if tex != null:
		var quad := PlaneMesh.new()
		quad.size = Vector2(radius * 2.0, radius * 2.0)
		quad.orientation = PlaneMesh.FACE_Z
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = lib.art(tex)
		_blade.add_child(mi)
	else:
		var plate := BoxMesh.new()
		plate.size = Vector3(radius * 2.0, radius * 1.4, 0.012)
		var mi := MeshInstance3D.new()
		mi.mesh = plate
		mi.material_override = lib.brass_dark()
		_blade.add_child(mi)


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	_blade.rotation = Vector3(float(peek(&"_angle", 0.0)), 0.0, 0.0)
