class_name SlingshotProxy3D
extends HardwareProxy3D
## The sling triangle: rubber band around a lit plastic plinth. Dead rubber on the starter
## table stays dark until Corner Boys power it.

var _lamp: StandardMaterial3D = null
var _pulse: float = 0.0


func build() -> void:
	var s := source as Slingshot
	var poly := PackedVector2Array()
	var inner := PackedVector2Array()
	for p in s.points:
		poly.append(p * TableSpace.SCALE)
		inner.append(p * TableSpace.SCALE * 0.62)
	var st := View3DMesh.begin()
	View3DMesh.prism(st, poly, 0.26, 0.04, false, 1.0)
	mesh_node(View3DMesh.finish(st, lib.rubber()), null, "Band")
	_lamp = lib.lamp(Color(1.0, 0.72, 0.30))
	var st2 := View3DMesh.begin()
	View3DMesh.prism(st2, inner, 0.36, 0.0, false, 1.0)
	mesh_node(View3DMesh.finish(st2, _lamp), null, "Plinth")
	# three posts at the corners, the way a real sling is pinned
	var st3 := View3DMesh.begin()
	for p in poly:
		View3DMesh.post(st3, p, 0.045, 0.40, 0.0, 10)
	mesh_node(View3DMesh.finish(st3, lib.chrome_dark()), null, "Posts")


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var s := source as Slingshot
	var tok := token()
	if state_name(tok) == &"active":
		_pulse = 1.0
	_pulse = maxf(_pulse - delta * 4.0, 0.0)
	var powered := s.is_powered() if s.has_method(&"is_powered") else true
	drive_lamp(_lamp, (0.25 if powered else 0.0) + _pulse * 3.0, delta, 18.0)
