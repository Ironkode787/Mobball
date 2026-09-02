class_name Bumper
extends StaticBody3D
## A pop bumper: a solid post the ball bounces off and a skirt ring that fires the solenoid —
## a radial shove plus the score. The can's art rides the cap; the body is the lamp.

@export var id: StringName = &"bumper"
@export var value: int = Feel.BUMPER_VALUE
@export var group: StringName = &"bumpers"
@export var size_scale: float = 1.0

var _present: bool = true
var _cooldown: float = 0.0
var _pulse: float = 0.0
var _ring: Area3D = null
var _inside: Array[Ball] = []
var _lamp: StandardMaterial3D = null


func radius() -> float:
	return Feel.BUMPER_RADIUS * size_scale


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.RUBBER_FRICTION, Feel.RUBBER_BOUNCE)
	var r := radius()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r * 0.66
	cyl.height = 0.5
	shape.shape = cyl
	shape.position.y = 0.25
	shape.name = "Body"
	add_child(shape)

	_ring = Area3D.new()
	_ring.name = "Skirt"
	_ring.collision_layer = Feel.LAYER_ZONES
	_ring.collision_mask = Feel.LAYER_BALL
	_ring.monitorable = false
	var rs := CollisionShape3D.new()
	var ring := CylinderShape3D.new()
	ring.radius = r * 0.66 + Feel.BALL_RADIUS + 0.03
	ring.height = 0.5
	rs.shape = ring
	rs.position.y = 0.25
	_ring.add_child(rs)
	add_child(_ring)
	_ring.body_entered.connect(_on_ball_entered)
	_ring.body_exited.connect(_on_ball_exited)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	var r := radius()
	_lamp = lib.lamp(Color(1.0, 0.80, 0.42))
	var body := CylinderMesh.new()
	body.top_radius = r * 0.62
	body.bottom_radius = r * 0.66
	body.height = 0.44
	body.radial_segments = 24
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = _lamp
	bm.position.y = 0.22
	bm.name = "Lamp"
	add_child(bm)
	var st := MeshLib.begin()
	MeshLib.ring(st, Vector3.ZERO, r * 0.66, r * 1.0, 0.03, 0.10, 28)
	MeshLib.ring(st, Vector3.ZERO, r * 1.0, r * 0.96, 0.10, 0.0, 28)
	var skirt := MeshInstance3D.new()
	skirt.mesh = MeshLib.finish(st, lib.rubber_red())
	skirt.name = "SkirtRing"
	add_child(skirt)
	var cap := CylinderMesh.new()
	cap.top_radius = r * 1.06
	cap.bottom_radius = r * 1.10
	cap.height = 0.08
	cap.radial_segments = 28
	var cm := MeshInstance3D.new()
	cm.mesh = cap
	cm.material_override = lib.ink()
	cm.position.y = 0.48
	cm.name = "Cap"
	add_child(cm)
	var tex: Texture2D = null
	if Presentation != null and Presentation.art != null:
		tex = Presentation.art.resolve(&"prop.trash_can", null, false)
	if tex != null:
		# the art is a top-down lid on ink: printed on a disc the size of the cap's top, the
		# inscribed circle of the square lands on the cap and the corners are never built
		var st_lid := MeshLib.begin()
		MeshLib.disc(st_lid, Vector3(0.0, 0.522, 0.0), r * 1.06, 32)
		var dm := MeshInstance3D.new()
		dm.mesh = MeshLib.finish(st_lid, lib.decal(tex))
		dm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dm.name = "CapArt"
		add_child(dm)


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	var mods: Array[StringName] = []
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _pulse > 0.0:
		state = TableVisualState.VisualState.ACTIVE
		mods.append(&"pulse")
	elif _cooldown > 0.0:
		state = TableVisualState.VisualState.DISABLED
		mods.append(&"cooldown")
	return TableVisualState.state_token(state, mods)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 6.0, 0.0)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				0.35 + _pulse * 3.2, 1.0 - exp(-18.0 * delta))


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	if _cooldown > 0.0:
		return
	# a real pop's skirt fires on contact, not on approach: a ball resting against the cap
	# has to be thrown off again or it sits there for the rest of the night
	for b in _inside:
		if b.speed() < Feel.HARDWARE_STALL_SPEED:
			_kick(b)
			return


func _on_ball_exited(body: Node3D) -> void:
	if body is Ball:
		_inside.erase(body as Ball)


func _on_ball_entered(body: Node3D) -> void:
	if not (body is Ball):
		return
	_inside.append(body as Ball)
	if _cooldown > 0.0:
		return
	_kick(body as Ball)


func _kick(ball: Ball) -> void:
	_cooldown = Feel.BUMPER_COOLDOWN
	var away := ball.table_position() - position
	away.y = 0.0
	if away.length() < 0.001:
		away = Vector3(0.0, 0.0, 1.0)
	away = away.normalized()
	ball.kick(away * Feel.BUMPER_IMPULSE)
	_pulse = 1.0
	AudioDirector.play(&"bumper_hit")
	TableScore.earn(group, float(value), id, ball, Feel.BUMPER_IMPULSE)


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
