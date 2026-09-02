class_name BumperProxy3D
extends HardwareProxy3D
## A pop bumper wearing its trash-can art on the cap. The body is a lamp: it flares on the
## hit the sim registers and cools back to the idle glow.

var _lamp: StandardMaterial3D = null
var _pulse: float = 0.0


func build() -> void:
	var b := source as Bumper
	var r := Feel.BUMPER_RADIUS * b.size_scale * TableSpace.SCALE
	_lamp = lib.lamp(Color(1.0, 0.80, 0.42))
	var body := CylinderMesh.new()
	body.top_radius = r * 0.62
	body.bottom_radius = r * 0.66
	body.height = 0.40
	body.radial_segments = 24
	var bm := mesh_node(body, _lamp, "Body")
	bm.position.y = 0.20
	var st := View3DMesh.begin()
	View3DMesh.ring(st, Vector3(0.0, 0.0, 0.0), r * 0.66, r * 1.0, 0.03, 0.10, 28)
	View3DMesh.ring(st, Vector3(0.0, 0.0, 0.0), r * 1.0, r * 0.96, 0.10, 0.0, 28)
	mesh_node(View3DMesh.finish(st, lib.rubber_red()), null, "Skirt")
	var cap := CylinderMesh.new()
	cap.top_radius = r * 1.06
	cap.bottom_radius = r * 1.10
	cap.height = 0.08
	cap.radial_segments = 28
	var cm := mesh_node(cap, lib.ink(), "Cap")
	cm.position.y = 0.44
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"prop.trash_can", null, false)
	if tex != null:
		var decal := PlaneMesh.new()
		decal.size = Vector2.ONE * r * 2.0
		var dm := mesh_node(decal, lib.art(tex), "CapArt")
		dm.position.y = 0.485
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func sync(delta: float) -> void:
	super.sync(delta)
	if not visible:
		return
	var tok := token()
	if state_name(tok) == &"active":
		_pulse = 1.0
	_pulse = maxf(_pulse - delta * 4.0, 0.0)
	drive_lamp(_lamp, 0.35 + _pulse * 3.2, delta, 18.0)
