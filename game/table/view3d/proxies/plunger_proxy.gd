class_name PlungerProxy3D
extends Node3D
## The Drop-Off: a chrome plunger rod under the shooter lane, drawn back by the charge the
## sim reports and slammed home on release. Not a HardwareProxy3D — the plunger is a plain
## Node, so this reads the table's `plunger` property directly.

var table: Node2D = null
var lib: View3DMaterials = null
var _rod: Node3D = null
var _pull: float = 0.0


func setup_plunger(p_table: Node2D, p_lib: View3DMaterials) -> void:
	table = p_table
	lib = p_lib
	name = "P_Plunger"
	var lane_x := (ProgressionTable.LANE_LEFT + ProgressionTable.LANE_RIGHT) * 0.5
	var home := TableSpace.to3(Vector2(lane_x, ProgressionTable.LANE_FLOOR_Y + 30.0), 0.0)
	position = home
	# housing through the cabinet front
	var housing := CylinderMesh.new()
	housing.top_radius = 0.16
	housing.bottom_radius = 0.16
	housing.height = 0.36
	var hm := MeshInstance3D.new()
	hm.mesh = housing
	hm.material_override = lib.brass_dark()
	hm.rotation.x = PI * 0.5
	hm.position = Vector3(0.0, 0.28, 0.42)
	add_child(hm)
	_rod = Node3D.new()
	_rod.name = "Rod"
	add_child(_rod)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.07
	rod.bottom_radius = 0.07
	rod.height = 1.1
	var rm := MeshInstance3D.new()
	rm.mesh = rod
	rm.material_override = lib.steel()
	rm.rotation.x = PI * 0.5
	rm.position = Vector3(0.0, 0.28, 0.55)
	_rod.add_child(rm)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.12
	tip.bottom_radius = 0.12
	tip.height = 0.10
	var tm := MeshInstance3D.new()
	tm.mesh = tip
	tm.material_override = lib.rubber()
	tm.rotation.x = PI * 0.5
	tm.position = Vector3(0.0, 0.28, -0.02)
	_rod.add_child(tm)
	var knob := SphereMesh.new()
	knob.radius = 0.2
	knob.height = 0.4
	var km := MeshInstance3D.new()
	km.mesh = knob
	km.material_override = lib.plastic(Color("2A1A12"), 0.5)
	km.position = Vector3(0.0, 0.28, 1.12)
	_rod.add_child(km)


func _process(delta: float) -> void:
	if table == null or not is_instance_valid(table):
		return
	var plunger: Variant = table.get("plunger")
	var wanted := 0.0
	if plunger != null and is_instance_valid(plunger):
		var charging := bool(plunger.get("charging"))
		var power := float(plunger.get("power"))
		if charging:
			wanted = power * 0.7
		elif plunger.get("starter_pull_px") != null:
			wanted = float(plunger.get("starter_pull_px")) * TableSpace.SCALE * 0.5
	_pull = lerpf(_pull, wanted, 1.0 - exp(-(22.0 if wanted < _pull else 9.0) * delta))
	_rod.position.z = _pull
