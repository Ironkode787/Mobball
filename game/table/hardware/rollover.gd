class_name Rollover
extends Area3D
## A lane rollover: a chrome wire over a lit insert. Lit lanes are the Drop-Off's moving
## window, so the insert is the loudest thing in the top lanes when it is on.

signal rolled(index: int, was_lit: bool)

const RADIUS := 0.16
const COOLDOWN := 0.35

@export var id: StringName = &"rollover"

var index: int = 0
var lit: bool = false
var _present: bool = true
var _cooldown: float = 0.0
var _flash: float = 0.0
var _lamp: StandardMaterial3D = null


func configure(p_id: StringName, p_index: int, center: Vector2) -> void:
	id = p_id
	index = p_index
	position = Layout.p3(center)


func _ready() -> void:
	collision_layer = Feel.LAYER_ZONES
	collision_mask = Feel.LAYER_BALL
	monitorable = false
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = RADIUS
	cyl.height = 0.4
	cs.shape = cyl
	cs.position.y = 0.2
	add_child(cs)
	body_entered.connect(_on_ball_entered)
	_build_look()
	_apply_collision()


func _build_look() -> void:
	var lib := MaterialLib.shared()
	_lamp = lib.lamp(Color(1.0, 0.78, 0.36))
	var st := MeshLib.begin()
	MeshLib.disc(st, Vector3(0.0, 0.006, 0.0), RADIUS * 0.75, 22)
	var insert := MeshInstance3D.new()
	insert.mesh = MeshLib.finish(st, _lamp)
	insert.name = "Insert"
	add_child(insert)
	var wire := MeshLib.begin()
	var r := RADIUS
	MeshLib.tube(wire, PackedVector3Array([
		Vector3(0.0, 0.0, -r * 1.4), Vector3(0.0, 0.10, -r * 0.9), Vector3(0.0, 0.14, 0.0),
		Vector3(0.0, 0.10, r * 0.9), Vector3(0.0, 0.0, r * 1.4),
	]), 0.014, 6, false)
	var wm := MeshInstance3D.new()
	wm.mesh = MeshLib.finish(wire, lib.steel())
	wm.name = "Wire"
	add_child(wm)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.0, 0.0)
	if _lamp != null:
		_lamp.emission_energy_multiplier = lerpf(_lamp.emission_energy_multiplier,
				(1.6 if lit else 0.10) + _flash * 3.0, 1.0 - exp(-14.0 * delta))


func _on_ball_entered(body: Node3D) -> void:
	if not (body is Ball) or not _present or _cooldown > 0.0:
		return
	_cooldown = COOLDOWN
	_flash = 1.0
	AudioDirector.play(&"rollover_click")
	TableScore.earn(TableScore.GROUP_ROLLOVERS, TableScore.ROLLOVER, id, body as Ball)
	rolled.emit(index, lit)


func set_lit(on: bool) -> void:
	lit = on


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_apply_collision()


func is_hardware_active() -> bool:
	return _present


func _apply_collision() -> void:
	collision_layer = Feel.LAYER_ZONES if _present else 0
	collision_mask = Feel.LAYER_BALL if _present else 0


func visual_state() -> Dictionary:
	var state := TableVisualState.VisualState.IDLE
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif _flash > 0.0:
		state = TableVisualState.VisualState.ACTIVE
	elif lit:
		state = TableVisualState.VisualState.ARMED
	return TableVisualState.state_token(state, {&"flash": _flash > 0.0})


func visual_token() -> Dictionary:
	return visual_state()
