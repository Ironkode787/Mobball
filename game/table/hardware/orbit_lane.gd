class_name OrbitLane
extends Node2D
## The Getaway Loop (docs/02 §2 R3). An orbit is not a switch, it is a *sequence*: the ball
## has to enter the channel at the bottom and still be in it at the top. Two gate switches
## and a window; anything else — a ball that dribbles in and falls back out, or one that
## comes down the channel from a plunge — is not an escape and does not pay.

signal orbit_completed()

const WINDOW := 3.0

@export var id: StringName = &"orbit_left"

var _entry: Area2D = null
var _exit: Area2D = null
var _entered_at: float = -1000.0
var _clock: float = 0.0
var _present: bool = true
var _flash: float = 0.0


func configure(p_id: StringName, entry_at: Vector2, entry_size: Vector2,
		exit_at: Vector2, exit_radius: float) -> void:
	id = p_id
	_entry = _make_gate("Entry", entry_at, entry_size, 0.0)
	_exit = _make_gate("Exit", exit_at, Vector2.ZERO, exit_radius)
	_entry.body_entered.connect(_on_entry)
	_exit.body_entered.connect(_on_exit)


func _make_gate(gate_name: String, at: Vector2, size: Vector2, radius: float) -> Area2D:
	var area := Area2D.new()
	area.name = gate_name
	area.position = at
	area.collision_layer = Feel.LAYER_ZONES
	area.collision_mask = Feel.LAYER_BALL
	area.monitorable = false
	var cs := CollisionShape2D.new()
	if radius > 0.0:
		var circle := CircleShape2D.new()
		circle.radius = radius
		cs.shape = circle
	else:
		var rect := RectangleShape2D.new()
		rect.size = size
		cs.shape = rect
	area.add_child(cs)
	add_child(area)
	return area


func _physics_process(delta: float) -> void:
	_clock += delta
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 2.0, 0.0)
		queue_redraw()


func _on_entry(body: Node2D) -> void:
	if not (body is Ball) or not _present:
		return
	_entered_at = _clock
	TableScore.hit(StringName(String(id) + "_entry"), body as Ball)


func _on_exit(body: Node2D) -> void:
	if not (body is Ball) or not _present:
		return
	if _clock - _entered_at > WINDOW:
		return                                  # came the other way, or crawled: no escape
	_entered_at = -1000.0
	_flash = 1.0
	AudioDirector.play(&"orbit_whoosh")
	TableScore.earn(TableScore.GROUP_ORBIT, TableScore.ORBIT, id, body as Ball)
	orbit_completed.emit()
	queue_redraw()


## Test/flow hook: is the lane part-way through a run right now?
func armed() -> bool:
	return _clock - _entered_at <= WINDOW


func entry_position() -> Vector2:
	return _entry.global_position if _entry != null else global_position


func exit_position() -> Vector2:
	return _exit.global_position if _exit != null else global_position


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_entered_at = -1000.0
	for gate: Node in [_entry, _exit]:
		if gate == null:
			continue
		var area := gate as Area2D
		area.collision_layer = Feel.LAYER_ZONES if active else 0
		area.collision_mask = Feel.LAYER_BALL if active else 0


func _draw() -> void:
	if _entry == null or _exit == null:
		return
	var col := Feel.COL_BRASS.darkened(0.55).lerp(Feel.COL_NEWSPRINT, _flash)
	draw_arc(_entry.position, 26.0, 0.0, TAU, 20, col, 4.0)
	draw_arc(_exit.position, 26.0, 0.0, TAU, 20, col, 4.0)
