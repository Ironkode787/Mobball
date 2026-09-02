class_name BossTarget
extends AnimatableBody3D
## Commission hardware: Sammy's sedan and the Butcher's truck, cars that ride a rail across
## the field and take a number of hits before they break. A ring around the body fires the
## hit and shoves the ball off; a speed gate lets a boss shrug off a soft tap.

signal struck(kind: StringName, hits_left: int, speed: float)
signal broken(kind: StringName)
signal shrugged(kind: StringName, speed: float)

const COOLDOWN := 0.30
const BOUNCE_IMPULSE := 7.0
const STALL_IMPULSE := 8.0

@export var kind: StringName = &"sedan"

var hits_left: int = 0
var min_speed: float = 0.0
var travel_speed: float = 1.4
var body_length: float = 0.72
var body_thick: float = 0.24
var color: Color = Feel.COL_INK.lightened(0.10)

var _present: bool = false
var _path: PackedVector2Array = PackedVector2Array()
var _lengths: PackedFloat32Array = PackedFloat32Array()
var _total: float = 0.0
var _along: float = 0.0
var _dir: float = 1.0
var _moving: bool = false
var _cooldown: float = 0.0
var _pulse: float = 0.0
var _shape: CollisionShape3D = null
var _ring: Area3D = null
var _ring_shape: CollisionShape3D = null
var _inside: Array[Ball] = []
var _lamp: StandardMaterial3D = null
var _look: Node3D = null


func _ready() -> void:
	process_physics_priority = 10
	sync_to_physics = false
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.24)
	_shape = CollisionShape3D.new()
	_shape.name = "Panel"
	_shape.shape = BoxShape3D.new()
	_shape.position.y = 0.2
	add_child(_shape)
	_ring = Area3D.new()
	_ring.name = "Ring"
	_ring.collision_layer = Feel.LAYER_ZONES
	_ring.collision_mask = Feel.LAYER_BALL
	_ring.monitorable = false
	_ring_shape = CollisionShape3D.new()
	_ring_shape.shape = BoxShape3D.new()
	_ring_shape.position.y = 0.2
	_ring.add_child(_ring_shape)
	add_child(_ring)
	_ring.body_entered.connect(_on_ring_entered)
	_ring.body_exited.connect(_on_ring_exited)
	_apply_size()
	_build_look()
	_apply_collision()


func size_to(length: float, thick: float) -> void:
	body_length = length
	body_thick = thick
	_apply_size()
	if _look != null:
		_look.queue_free()
		_look = null
		_build_look()


func _apply_size() -> void:
	if _shape != null:
		(_shape.shape as BoxShape3D).size = Vector3(body_length, 0.4, body_thick)
	if _ring_shape != null:
		(_ring_shape.shape as BoxShape3D).size = Vector3(body_length + Feel.BALL_RADIUS * 2.0, 0.4,
				body_thick + Feel.BALL_RADIUS * 2.0)


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_look = Node3D.new()
	_look.name = "Look"
	add_child(_look)
	var l := body_length
	var w := body_thick
	var body := BoxMesh.new()
	body.size = Vector3(l, 0.24, w)
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = lib.plastic(color, 0.35)
	bm.position.y = 0.17
	_look.add_child(bm)
	var cabin := BoxMesh.new()
	cabin.size = Vector3(l * 0.55, 0.16, w * 0.82)
	var cm := MeshInstance3D.new()
	cm.mesh = cabin
	cm.material_override = lib.plastic(Color("1A1C22"), 0.2)
	cm.position = Vector3(-l * 0.08, 0.37, 0.0)
	_look.add_child(cm)
	var wheels := MeshLib.begin()
	for sx in [-0.34, 0.34]:
		for sz in [-1.0, 1.0]:
			MeshLib.post(wheels, Vector2(l * sx, w * 0.5 * sz), 0.055, 0.08, 0.01, 10)
	var wm := MeshInstance3D.new()
	wm.mesh = MeshLib.finish(wheels, lib.rubber())
	_look.add_child(wm)
	_lamp = lib.lamp(Feel.COL_DIRTY)
	var roof := BoxMesh.new()
	roof.size = Vector3(0.08, 0.05, 0.08)
	var rm := MeshInstance3D.new()
	rm.mesh = roof
	rm.material_override = _lamp
	rm.position = Vector3(l * 0.18, 0.47, 0.0)
	_look.add_child(rm)


func set_path(points: PackedVector2Array) -> void:
	_path = points
	_lengths = PackedFloat32Array()
	_total = 0.0
	for i in range(1, _path.size()):
		var seg := _path[i].distance_to(_path[i - 1])
		_lengths.append(seg)
		_total += seg
	_along = 0.0
	_dir = 1.0
	_moving = _total > 0.0
	if _path.size() > 0:
		_place_along(0.0)


func park_at(at: Vector2, facing: float = 0.0) -> void:
	_moving = false
	position = Layout.p3(at)
	rotation.y = facing


func arm(hits: int, speed_gate: float = 0.0) -> void:
	hits_left = maxi(hits, 0)
	min_speed = maxf(speed_gate, 0.0)
	_cooldown = 0.0
	_inside.clear()


func is_armed() -> bool:
	return _present and hits_left > 0


func set_moving(on: bool) -> void:
	_moving = on and _total > 0.0


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_inside.clear()
	_cooldown = 0.0
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_HARDWARE if _present else 0
	if _ring != null:
		_ring.collision_layer = Feel.LAYER_ZONES if _present else 0
		_ring.collision_mask = Feel.LAYER_BALL if _present else 0


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _present and _moving and _total > 0.0:
		_along += _dir * travel_speed * delta
		if _along >= _total:
			_along = _total
			_dir = -1.0
		elif _along <= 0.0:
			_along = 0.0
			_dir = 1.0
		_place_along(_along)
	_pop_stalled()


func _place_along(distance: float) -> void:
	if _path.size() < 2:
		if _path.size() == 1:
			position = Layout.p3(_path[0])
		return
	var left := clampf(distance, 0.0, _total)
	for i in range(_lengths.size()):
		var seg := _lengths[i]
		if left <= seg or i == _lengths.size() - 1:
			var t := 0.0 if seg <= 0.0 else clampf(left / seg, 0.0, 1.0)
			var a := _path[i]
			var b := _path[i + 1]
			position = Layout.p3(a.lerp(b, t))
			var heading := b - a
			if heading.length_squared() > 0.0001:
				rotation.y = atan2(-heading.y, heading.x)
			return
		left -= seg


func _pop_stalled() -> void:
	if not _present or _inside.is_empty():
		return
	for i in range(_inside.size() - 1, -1, -1):
		if not is_instance_valid(_inside[i]):
			_inside.remove_at(i)
	for b in _inside:
		if b.speed() < Feel.HARDWARE_STALL_SPEED:
			b.kick(_away_from(b) * STALL_IMPULSE)
			return


func _on_ring_exited(body: Node3D) -> void:
	if body is Ball:
		_inside.erase(body as Ball)


func _on_ring_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	var ball: Ball = body
	_inside.append(ball)
	if _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	var speed := ball.speed()
	ball.kick(_away_from(ball) * BOUNCE_IMPULSE)
	_pulse = 1.0
	if hits_left <= 0:
		AudioDirector.play(&"wall_tap")
		return
	if min_speed > 0.0 and speed < min_speed:
		AudioDirector.play(&"wall_tap")
		shrugged.emit(kind, speed)
		return
	hits_left -= 1
	AudioDirector.play(&"drop_bank_down" if hits_left <= 0 else &"drop_clack")
	TableScore.hit(StringName("boss_%s" % kind), ball, speed)
	struck.emit(kind, hits_left, speed)
	if hits_left <= 0:
		broken.emit(kind)


func _away_from(ball: Ball) -> Vector3:
	var away := ball.table_position() - position
	away.y = 0.0
	var normal := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, rotation.y)
	var side := 1.0 if away.dot(normal) >= 0.0 else -1.0
	var mixed := normal * side * 1.4 + away.normalized() * 0.6
	return mixed.normalized() if mixed.length() > 0.001 else Vector3(0, 0, 1)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 4.0, 0.0)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				(1.4 if is_armed() else 0.0) + _pulse * 3.0, 1.0 - exp(-14.0 * delta))


func visual_state() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if hits_left <= 0:
		return TableVisualState.VisualState.COMPLETED
	if _pulse > 0.02 or _moving:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	return {&"moving": _moving, &"parked": not _moving, &"pulse": _pulse > 0.02}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
