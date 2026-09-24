class_name Manhole
extends Node3D
## A sewer manhole (docs/19 §3.4): an iron lid in the felt. Lit, its lid is off and a ball that
## rolls over it drops in (`swallowed`); the Sewer carries it underground and brings it up at
## another manhole (`surface`). A destination-only manhole never swallows.

signal swallowed(manhole: Manhole, ball: Ball)

const LID_R := 0.13
const SINK_R := 0.10
const MAX_SINK_SPEED := 16.0

@export var id: StringName = &"manhole"

var index: int = 0
var destination_only: bool = false
var open: bool = false

var _present: bool = true
var _area: Area3D = null
var _lamp: StandardMaterial3D = null
var _lid: MeshInstance3D = null
var _flash: float = 0.0


func configure(p_id: StringName, p_index: int, at: Vector2, p_destination_only: bool) -> void:
	id = p_id
	index = p_index
	destination_only = p_destination_only
	position = Layout.p3(at)


func _ready() -> void:
	var lib := MaterialLib.shared()
	_area = Area3D.new()
	_area.name = "Mouth"
	_area.collision_layer = Feel.LAYER_ZONES
	_area.collision_mask = Feel.LAYER_BALL
	_area.monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = SINK_R
	cyl.height = 0.3
	cs.shape = cyl
	cs.position.y = 0.15
	_area.add_child(cs)
	add_child(_area)
	_area.body_entered.connect(_on_body)
	# the lamp ring round the lid: lit means open
	_lamp = lib.lamp(Color(0.95, 0.72, 0.3))
	var st := MeshLib.begin()
	MeshLib.ring(st, Vector3.ZERO, LID_R + 0.005, LID_R + 0.04, 0.004, 0.004, 28)
	var ring := MeshInstance3D.new()
	ring.mesh = MeshLib.finish(st, _lamp)
	ring.name = "Ring"
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	var hole := CylinderMesh.new()
	hole.top_radius = LID_R
	hole.bottom_radius = LID_R
	hole.height = 0.004
	var hm := MeshInstance3D.new()
	hm.mesh = hole
	hm.material_override = lib.plastic(Color("050505"), 1.0)
	hm.position.y = 0.002
	hm.name = "Hole"
	add_child(hm)
	var lid := CylinderMesh.new()
	lid.top_radius = LID_R - 0.005
	lid.bottom_radius = LID_R - 0.005
	lid.height = 0.012
	lid.radial_segments = 20
	_lid = MeshInstance3D.new()
	_lid.mesh = lid
	var iron := StandardMaterial3D.new()
	iron.albedo_texture = lib.grate_texture()
	iron.albedo_color = Color(0.55, 0.5, 0.45)
	iron.metallic = 0.7
	iron.roughness = 0.55
	_lid.material_override = iron
	_lid.position.y = 0.006
	_lid.name = "Lid"
	add_child(_lid)


func set_open(on: bool) -> void:
	open = on


func flash() -> void:
	_flash = 1.0


func _on_body(body: Node3D) -> void:
	if not _present or not open or destination_only or not (body is Ball):
		return
	var b := body as Ball
	if BallHold.is_held(b) or b.speed() > MAX_SINK_SPEED:
		return
	swallowed.emit(self, b)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	var t := Time.get_ticks_msec() * 0.001
	var e := 0.05
	if open and not destination_only:
		e = 1.6 if fmod(t * 1.8 + float(index) * 0.5, 1.0) < 0.55 else 0.35
	elif destination_only and open:
		e = 0.6
	_lamp.emission_energy_multiplier = e + _flash * 3.0
	# the lid slides aside while the manhole is open
	var want := Vector3(LID_R * 1.25, 0.006, 0.0) if open and not destination_only else Vector3(0.0, 0.006, 0.0)
	_lid.position = _lid.position.lerp(want, 1.0 - exp(-8.0 * delta))


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	if _area != null:
		_area.collision_layer = Feel.LAYER_ZONES if active else 0
		_area.collision_mask = Feel.LAYER_BALL if active else 0


func is_hardware_active() -> bool:
	return _present
