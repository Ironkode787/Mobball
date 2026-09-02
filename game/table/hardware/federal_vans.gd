class_name FederalVans
extends Node3D
## The Bureau's vans parked at the bottom corners during a federal raid, sweeping the field
## with searchlights. Paint only: no collider, no gameplay side effects.

const VAN_AT: Array = [Vector2(-2.1, 3.9), Vector2(2.0, 3.9)]
const SWEEP_PERIOD := 5.5
const SWEEP_DEG := 26.0

var _active: bool = false
var _sweep: float = 0.0
var _beams: Array[SpotLight3D] = []


func _ready() -> void:
	var lib := MaterialLib.shared()
	for i in range(VAN_AT.size()):
		var van := Node3D.new()
		van.position = Layout.p3(VAN_AT[i], 0.0)
		add_child(van)
		var toy := ToyLib.instance(&"van")
		if toy != null:
			# nose up-field, angled in toward the flippers
			toy.rotation.y = PI * 0.5 + (-0.35 if i == 0 else 0.35)
			var bar := lib.lamp(Feel.COL_COP)
			bar.emission_energy_multiplier = 2.0
			ToyLib.bind(toy, "Lamp", bar)
			van.add_child(toy)
		else:
			var body := BoxMesh.new()
			body.size = Vector3(0.5, 0.26, 0.26)
			var bm := MeshInstance3D.new()
			bm.mesh = body
			bm.material_override = lib.plastic(Color("1E2634"), 0.4)
			bm.position.y = 0.18
			van.add_child(bm)
		var beam := SpotLight3D.new()
		beam.light_color = Feel.COL_COP
		beam.light_energy = 3.0
		beam.spot_range = 7.0
		beam.spot_angle = 10.0
		beam.position = Vector3(0.0, 0.5, 0.0)
		beam.shadow_enabled = false
		van.add_child(beam)
		_beams.append(beam)
	visible = false
	set_process(false)


func set_active(on: bool) -> void:
	if _active == on:
		return
	_active = on
	visible = on
	_sweep = 0.0
	set_process(on)


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	_sweep += delta
	var a := sin(_sweep * TAU / SWEEP_PERIOD) * deg_to_rad(SWEEP_DEG)
	for i in range(_beams.size()):
		var side := -1.0 if i == 0 else 1.0
		_beams[i].rotation = Vector3(deg_to_rad(-22.0), PI + side * (deg_to_rad(30.0) + a), 0.0)


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.ACTIVE if _active else TableVisualState.VisualState.DISABLED
	var mods: Array[StringName] = []
	if _active:
		mods.append(&"raid_phase")
		if _sweep > 0.001:
			mods.append(&"moving")
	return TableVisualState.state_token(state, mods)


func visual_token() -> Dictionary:
	return visual_state()
