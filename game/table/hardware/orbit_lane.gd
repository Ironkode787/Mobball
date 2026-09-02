class_name OrbitLane
extends Node3D
## An orbit is two switches and the wall between them: an entry gate low in the lane and an
## exit gate at the top of the channel. Both within WINDOW seconds is a lap.

signal orbit_completed()

const WINDOW := 3.0

@export var id: StringName = &"orbit_left"

var _entry: Area3D = null
var _exit: Area3D = null
var _entered_at: float = -1000.0
var _clock: float = 0.0
var _present: bool = true
var _flash: float = 0.0
var _lamps: Array[StandardMaterial3D] = []


func configure(p_id: StringName, entry_at: Vector2, entry_size: Vector2, exit_at: Vector2,
		exit_radius: float) -> void:
	id = p_id
	_entry = _make_gate("Entry", entry_at, entry_size, 0.0)
	_exit = _make_gate("Exit", exit_at, Vector2.ZERO, exit_radius)
	_entry.body_entered.connect(_on_entry)
	_exit.body_entered.connect(_on_exit)
	_build_look(entry_at, exit_at)


func _make_gate(gate_name: String, at: Vector2, size: Vector2, radius: float) -> Area3D:
	var area := Area3D.new()
	area.name = gate_name
	area.position = Layout.p3(at)
	area.collision_layer = Feel.LAYER_ZONES
	area.collision_mask = Feel.LAYER_BALL
	area.monitorable = false
	var cs := CollisionShape3D.new()
	if radius > 0.0:
		var cyl := CylinderShape3D.new()
		cyl.radius = radius
		cyl.height = 0.5
		cs.shape = cyl
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(size.x, 0.5, size.y)
		cs.shape = box
	cs.position.y = 0.25
	area.add_child(cs)
	add_child(area)
	return area


func _build_look(entry_at: Vector2, exit_at: Vector2) -> void:
	var lib := MaterialLib.shared()
	var d := (exit_at - entry_at).normalized()
	for at in [entry_at, exit_at]:
		var lamp := lib.lamp(Color(1.0, 0.80, 0.38))
		_lamps.append(lamp)
		var st := MeshLib.begin()
		var c := Layout.p3(at, 0.006)
		var d3 := Vector3(d.x, 0.0, d.y)
		var side := Vector3(-d3.z, 0.0, d3.x)
		MeshLib.tri(st, c + d3 * 0.16, c - d3 * 0.08 + side * 0.13, c - d3 * 0.02, Vector3.UP)
		MeshLib.tri(st, c + d3 * 0.16, c - d3 * 0.02, c - d3 * 0.08 - side * 0.13, Vector3.UP)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshLib.finish(st, lamp)
		mi.name = "Arrow"
		add_child(mi)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)


func _process(delta: float) -> void:
	for l in _lamps:
		l.emission_energy_multiplier = lerpf(l.emission_energy_multiplier,
				(1.5 if armed() else 0.35) + _flash * 2.5, 1.0 - exp(-10.0 * delta))


func _on_entry(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	_entered_at = _clock
	TableScore.hit(StringName(String(id) + "_entry"), body as Ball)


func _on_exit(body: Node3D) -> void:
	if not (body is Ball) or not _present:
		return
	if _clock - _entered_at > WINDOW:
		return
	_entered_at = -1000.0
	_flash = 1.0
	AudioDirector.play(&"orbit_whoosh")
	TableScore.earn(TableScore.GROUP_ORBIT, TableScore.ORBIT, id, body as Ball)
	orbit_completed.emit()


func armed() -> bool:
	return _clock - _entered_at <= WINDOW


func entry_position() -> Vector2:
	return Layout.plan(_entry.position) if _entry != null else Layout.plan(position)


func exit_position() -> Vector2:
	return Layout.plan(_exit.position) if _exit != null else Layout.plan(position)


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_entered_at = -1000.0
	for gate: Node in [_entry, _exit]:
		if gate == null:
			continue
		var area := gate as Area3D
		area.collision_layer = Feel.LAYER_ZONES if active else 0
		area.collision_mask = Feel.LAYER_BALL if active else 0


func is_hardware_active() -> bool:
	return _present


func _visual_state_id() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if _flash > 0.0:
		return TableVisualState.VisualState.COMPLETED
	if armed():
		return TableVisualState.VisualState.ARMED
	return TableVisualState.VisualState.IDLE


func visual_state() -> Dictionary:
	return TableVisualState.state_token(_visual_state_id(), {&"flash": _flash > 0.0})


func visual_token() -> Dictionary:
	return visual_state()
