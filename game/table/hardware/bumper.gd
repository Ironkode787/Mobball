class_name Bumper
extends StaticBody3D
## A pop bumper: in the Alley, a trash can. The post is the can's full body; a real contact
## closes the skirt switch and the solenoid throws the ball out along the contact normal at its
## own pace (Feel.BUMPER_KICK_*), the same model as the slingshots, so every hit is lively and
## none is a dud. A ball that comes to rest against the can is thrown off again.
##
## `level` is the Alley's development (docs/19 §3.2): Trash Can → Dumpster → Armored Truck →
## Vault. Each level doubles the value and relights the lid band.

signal popped(bumper: Bumper, ball: Ball)

const LEVEL_COLORS: Array[Color] = [
	Color(0.86, 0.80, 0.66), Color(1.0, 0.72, 0.26), Color(0.18, 0.90, 0.84), Color(1.0, 0.84, 0.30),
]
const LEVEL_NAMES: Array[StringName] = [&"TRASH CAN", &"DUMPSTER", &"ARMORED TRUCK", &"VAULT"]
const MESH_RADIUS := 0.29               ## the bumper_can mesh is modelled at this radius

@export var id: StringName = &"bumper"
@export var value: int = Feel.BUMPER_VALUE
@export var group: StringName = &"bumpers"
@export var size_scale: float = 1.0

var level: int = 0
var _present: bool = true
var _cooldown: float = 0.0
var _pulse: float = 0.0
var _ring: Area3D = null
var _inside: Array[Ball] = []
var _lamp: StandardMaterial3D = null
var _level_ring: StandardMaterial3D = null


func radius() -> float:
	return Feel.BUMPER_RADIUS * size_scale


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, Feel.RUBBER_BOUNCE)
	var r := radius()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = 0.5
	shape.shape = cyl
	shape.position.y = 0.25
	shape.name = "Body"
	add_child(shape)

	# the skirt: only used to find a ball parked against the can
	_ring = Area3D.new()
	_ring.name = "Skirt"
	_ring.collision_layer = Feel.LAYER_ZONES
	_ring.collision_mask = Feel.LAYER_BALL
	_ring.monitorable = false
	var rs := CollisionShape3D.new()
	var ring := CylinderShape3D.new()
	ring.radius = r + Feel.BALL_RADIUS + 0.02
	ring.height = 0.5
	rs.shape = ring
	rs.position.y = 0.25
	_ring.add_child(rs)
	add_child(_ring)
	_ring.body_entered.connect(func(b: Node3D) -> void:
		if b is Ball:
			_inside.append(b as Ball))
	_ring.body_exited.connect(func(b: Node3D) -> void:
		if b is Ball:
			_inside.erase(b as Ball))
	_build_look()
	_apply_collision()
	set_level(level)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var r := radius()
	_lamp = lib.lamp(LEVEL_COLORS[0])
	_level_ring = lib.lamp(LEVEL_COLORS[0])
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"prop.trash_can", null, false)
	var can := ToyLib.instance(&"bumper_can")
	if can != null:
		can.scale = Vector3.ONE * (r / MESH_RADIUS)
		ToyLib.bind(can, "Lamp", _lamp)
		if tex != null:
			ToyLib.bind(can, "Art", lib.decal(tex))
		add_child(can)
	else:
		var body := CylinderMesh.new()
		body.top_radius = r * 0.94
		body.bottom_radius = r
		body.height = 0.44
		body.radial_segments = 24
		var bm := MeshInstance3D.new()
		bm.mesh = body
		bm.material_override = lib.steel()
		bm.position.y = 0.22
		bm.name = "Body"
		add_child(bm)
		var cap := CylinderMesh.new()
		cap.top_radius = r * 1.04
		cap.bottom_radius = r * 1.06
		cap.height = 0.06
		cap.radial_segments = 28
		var cm := MeshInstance3D.new()
		cm.mesh = cap
		cm.material_override = _lamp
		cm.position.y = 0.47
		cm.name = "Lamp"
		add_child(cm)
	# the level ring round the foot: the Alley's upgrade reads from any angle
	var st := MeshLib.begin()
	MeshLib.ring(st, Vector3.ZERO, r + 0.012, r + 0.055, 0.012, 0.012, 32)
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = MeshLib.finish(st, _level_ring)
	ring_mi.name = "LevelRing"
	ring_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring_mi)


## 0..Feel.CAN_LEVEL_MAX. Value doubles per level.
func set_level(l: int) -> void:
	level = clampi(l, 0, Feel.CAN_LEVEL_MAX)
	var c := LEVEL_COLORS[level]
	if _lamp != null:
		_lamp.albedo_color = c.darkened(0.25)
		_lamp.emission = c
	if _level_ring != null:
		_level_ring.albedo_color = c.darkened(0.4)
		_level_ring.emission = c
		_level_ring.emission_energy_multiplier = 0.25 + 0.55 * float(level)


func level_name() -> StringName:
	return LEVEL_NAMES[level]


func scaled_value() -> int:
	return value * (1 << level)


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _pulse > 0.0:
		state = TableVisualState.VisualState.ACTIVE
		mods.append(&"pulse")
	if level > 0:
		mods.append(StringName("level_%d" % level))
	return TableVisualState.state_token(state, mods)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 6.0, 0.0)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				0.3 + 0.35 * float(level) + _pulse * 3.2, 1.0 - exp(-18.0 * delta))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _inside.is_empty() or _cooldown > 0.0:
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	# a ball resting against the can has to be thrown off, or it sits there all night
	for b in _inside:
		if b.speed() < Feel.HARDWARE_STALL_SPEED:
			_fire(b, Vector3.ZERO)
			return


## Ball.gd forwards every real contact here.
func on_ball_contact(ball: Ball) -> void:
	if not _present or _cooldown > 0.0:
		return
	_fire(ball, ball.approach_velocity())


func _fire(ball: Ball, approach: Vector3) -> void:
	_cooldown = Feel.BUMPER_COOLDOWN
	var n := ball.table_position() - position
	n.y = 0.0
	if n.length() < 0.001:
		n = Vector3(0.0, 0.0, 1.0)
	n = n.normalized()
	var a := approach
	a.y = 0.0
	var into := maxf(-a.dot(n), 0.0)
	var slide := a - n * a.dot(n)
	var out := n * (Feel.BUMPER_KICK_SPEED + Feel.BUMPER_KICK_GAIN * into) + slide * Feel.BUMPER_TANGENT_KEEP
	ball.set_velocity(out.limit_length(Feel.BUMPER_OUT_MAX))
	_pulse = 1.0
	AudioDirector.play(&"bumper_hit")
	TableScore.earn(group, float(scaled_value()), id, ball, out.length())
	popped.emit(self, ball)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_inside.clear()
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _ring != null:
		_ring.collision_layer = Feel.LAYER_ZONES if _present else 0
		_ring.collision_mask = Feel.LAYER_BALL if _present else 0
