class_name DropTarget
extends StaticBody3D
## A drop target: a plate that drops into the playfield when the ball hits its face and
## comes back up when its bank resets. Down, it is out of the ball's way entirely.

signal dropped(target: DropTarget)
signal raised(target: DropTarget)

const PLATE_HEIGHT := 0.40

@export var id: StringName = &"drop_target"

var down: bool = false
var length: float = 0.22
var thickness: float = 0.06
## A ToyLib id to dress the plate with (the containers on the docks); empty = ink plate.
var mesh_id: StringName = &""
## Native footprint of the toy, (length, thickness): the plate scales it to its own size.
var mesh_footprint: Vector2 = Vector2(0.16, 0.10)
var facing: Vector2 = Vector2(0.0, 1.0)
var _present: bool = true
var _face: Area3D = null
var _pulse: float = 0.0
var _plate: Node3D = null
var _sink: float = 0.0
var _lamp: StandardMaterial3D = null


func configure(p_id: StringName, center: Vector2, p_facing: Vector2, p_length: float) -> void:
	id = p_id
	position = Layout.p3(center)
	facing = p_facing.normalized()
	length = p_length
	rotation.y = Layout.yaw_facing(facing)


func _ready() -> void:
	collision_layer = Feel.LAYER_HARDWARE
	collision_mask = 0
	physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.22)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, PLATE_HEIGHT, thickness)
	shape.shape = box
	shape.position.y = PLATE_HEIGHT * 0.5
	shape.name = "Body"
	add_child(shape)
	_face = Area3D.new()
	_face.name = "Face"
	_face.collision_layer = Feel.LAYER_ZONES
	_face.collision_mask = Feel.LAYER_BALL
	_face.monitorable = false
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(length, PLATE_HEIGHT, Feel.BALL_RADIUS * 0.8)
	fs.shape = fb
	fs.position = Vector3(0.0, PLATE_HEIGHT * 0.5, thickness * 0.5 + Feel.BALL_RADIUS * 0.4)
	_face.add_child(fs)
	add_child(_face)
	_face.body_entered.connect(_on_face_entered)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_plate = Node3D.new()
	_plate.name = "Plate"
	add_child(_plate)
	_lamp = lib.lamp(Color(1.0, 0.86, 0.55))
	if mesh_id != &"":
		var toy := ToyLib.instance(mesh_id)
		if toy != null:
			toy.scale = Vector3(length / mesh_footprint.x, 1.0, thickness / mesh_footprint.y)
			ToyLib.bind(toy, "Lamp", _lamp)
			_plate.add_child(toy)
			return
	var body := BoxMesh.new()
	body.size = Vector3(length, PLATE_HEIGHT, thickness)
	var bm := MeshInstance3D.new()
	bm.mesh = body
	bm.material_override = lib.ink()
	bm.position.y = PLATE_HEIGHT * 0.5
	_plate.add_child(bm)
	var face := BoxMesh.new()
	face.size = Vector3(length * 0.78, PLATE_HEIGHT * 0.55, 0.012)
	var fm := MeshInstance3D.new()
	fm.mesh = face
	fm.material_override = _lamp
	fm.position = Vector3(0.0, PLATE_HEIGHT * 0.55, thickness * 0.5 + 0.006)
	_plate.add_child(fm)


func _process(delta: float) -> void:
	if _pulse > 0.0:
		_pulse = maxf(_pulse - delta * 5.0, 0.0)
	var target_sink := PLATE_HEIGHT + 0.02 if down else 0.0
	_sink = lerpf(_sink, target_sink, 1.0 - exp(-16.0 * delta))
	if _plate != null:
		_plate.position.y = -_sink
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				0.9 + _pulse * 2.5, 1.0 - exp(-12.0 * delta))


func _on_face_entered(body: Node3D) -> void:
	if not (body is Ball) or down or not _present:
		return
	drop(body as Ball)


func drop(ball: Ball = null) -> void:
	if down:
		return
	down = true
	_pulse = 1.0
	_apply_collision()
	AudioDirector.play(&"drop_clack")
	TableScore.hit(id, ball)
	dropped.emit(self)


func raise() -> void:
	if not down:
		return
	down = false
	_apply_collision()
	raised.emit(self)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	var live := _present and not down
	collision_layer = Feel.LAYER_HARDWARE if live else 0
	if _face != null:
		_face.collision_layer = Feel.LAYER_ZONES if live else 0
		_face.collision_mask = Feel.LAYER_BALL if live else 0


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif down:
		state = TableVisualState.VisualState.COMPLETED
	elif _pulse > 0.0:
		state = TableVisualState.VisualState.ACTIVE
	return TableVisualState.state_token(state, {&"down": down, &"pulse": _pulse > 0.0})


func visual_token() -> Dictionary:
	return visual_state()
