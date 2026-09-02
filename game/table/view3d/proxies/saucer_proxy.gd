class_name SaucerProxy3D
extends HardwareProxy3D
## A hold saucer: a dish sunk into the field with a lamp at the bottom that steps up the
## multiplier while the ball sits in it.

var _lamp: StandardMaterial3D = null


func build() -> void:
	var s := source as HoldSaucer
	var r := s.radius * TableSpace.SCALE
	var st := View3DMesh.begin()
	View3DMesh.ring(st, Vector3.ZERO, r * 0.30, r * 1.05, -0.10, 0.0, 26)
	View3DMesh.ring(st, Vector3.ZERO, r * 1.05, r * 1.22, 0.0, 0.03, 26)
	mesh_node(View3DMesh.finish(st, lib.ink()), null, "Dish")
	_lamp = lib.lamp(Color("8C4DFF").lerp(Color.WHITE, 0.3))
	var st2 := View3DMesh.begin()
	View3DMesh.disc(st2, Vector3(0.0, -0.095, 0.0), r * 0.30, 16)
	mesh_node(View3DMesh.finish(st2, _lamp), null, "Lamp")


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var s := source as HoldSaucer
	var tok := token()
	var wanted := 0.4
	if s.holds_ball():
		wanted = 1.5 + float(s.step_index()) * 0.9
	elif state_name(tok) == &"armed":
		wanted = 1.2
	elif state_name(tok) == &"disabled":
		wanted = 0.0
	drive_lamp(_lamp, wanted, delta, 8.0)
