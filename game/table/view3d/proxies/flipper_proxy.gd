class_name FlipperProxy3D
extends HardwareProxy3D
## A solenoid bat: brass body, black rubber, chrome pivot cap. Follows the kinematic body's
## interpolated rotation so the snap the sim produces is the snap the player sees.

var _body: MeshInstance3D = null
var _dead_mat: StandardMaterial3D = null


func build() -> void:
	var f := source as Flipper
	var S := TableSpace.SCALE
	var l := f.bat_length() * S
	var rp := f.pivot_radius() * S
	var rt := f.tip_radius() * S
	var outline := View3DMesh.capsule_poly(Vector2.ZERO, Vector2(l, 0.0), rp, rt, 8)
	var st := View3DMesh.begin()
	View3DMesh.prism(st, outline, 0.30, 0.10, false, 1.0)
	_body = mesh_node(View3DMesh.finish(st, lib.brass()), null, "Bat")
	var band := View3DMesh.capsule_poly(Vector2.ZERO, Vector2(l, 0.0), rp + 0.02, rt + 0.02, 8)
	var st2 := View3DMesh.begin()
	View3DMesh.prism(st2, band, 0.16, 0.14, false, 1.0)
	mesh_node(View3DMesh.finish(st2, lib.rubber()), null, "Rubber")
	var st3 := View3DMesh.begin()
	View3DMesh.post(st3, Vector2.ZERO, rp * 0.55, 0.50, 0.0, 12)
	mesh_node(View3DMesh.finish(st3, lib.chrome_dark()), null, "PivotCap")
	_dead_mat = lib.plastic(Color("3A3128"), 0.7)


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var f := source as Flipper
	_body.material_override = _dead_mat if f.dead else null
