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


## The orbit window is presentation state only. The authoritative three-second window remains
## `_entered_at`/`WINDOW`; no visual classification changes scoring or entry/exit sensors.
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


func _material_fill(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _reduced_flash() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_flash


func _draw() -> void:
	if _entry == null or _exit == null:
		return
	var token := visual_token()
	var state := StringName(token["state"])
	var ink := _material_fill(&"ink_glass", Feel.COL_INK)
	var brass := _material_fill(&"brass", Feel.COL_BRASS)
	var paper := _material_fill(&"newsprint", Feel.COL_NEWSPRINT)
	var flash_strength := _flash * (0.25 if _reduced_flash() else 1.0)
	var col := brass.darkened(0.55)
	if state == &"armed":
		col = brass
	elif state == &"completed":
		col = brass.lerp(paper, 0.42 + flash_strength * 0.58)
	elif state == &"disabled":
		col = ink.lightened(0.18)
	# Entry and exit are the only switch marks; the actual curved rail remains WallBuilder-owned.
	draw_circle(_entry.position, 27.0, Color(col.r, col.g, col.b, 0.12))
	draw_circle(_exit.position, 27.0, Color(col.r, col.g, col.b, 0.12))
	draw_arc(_entry.position, 26.0, 0.0, TAU, 20, col, 5.0)
	draw_arc(_exit.position, 26.0, 0.0, TAU, 20, col, 5.0)
	if state == &"armed":
		var direction := (_exit.position - _entry.position).normalized()
		var side := Vector2(-direction.y, direction.x) * 9.0
		var tip := _entry.position + direction * 20.0
		draw_line(tip - direction * 12.0 + side, tip + direction * 9.0, col, 4.0)
		draw_line(tip - direction * 12.0 - side, tip + direction * 9.0, col, 4.0)
	elif state == &"completed":
		draw_line(_exit.position + Vector2(-11.0, 1.0), _exit.position + Vector2(-2.0, 10.0), paper, 4.0)
		draw_line(_exit.position + Vector2(-2.0, 10.0), _exit.position + Vector2(14.0, -12.0), paper, 4.0)
	elif state == &"disabled":
		draw_line(_entry.position - Vector2(13.0, 13.0), _exit.position + Vector2(13.0, 13.0),
			Color(paper.r, paper.g, paper.b, 0.28), 3.0)
