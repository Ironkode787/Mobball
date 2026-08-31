class_name TargetBank
extends Node2D
## The Wire: three payphone standups, one racket. Each phone pays on its first hit of the
## round; all three lit completes the bank for the big payout, then the round resets after a
## beat so the shot is available again (specs/m1-hook.md Lane 3).

signal bank_completed()
signal target_struck(index: int)

@export var id: StringName = &"wire_bank"

var reset_seconds: float = 2.0
var target_value: float = TableScore.WIRE_TARGET
var complete_value: float = TableScore.BANK_COMPLETE
var group: StringName = TableScore.GROUP_WIRE

var _targets: Array[StandupTarget] = []
var _reset_in: float = -1.0
var _present: bool = true


func add_target(t: StandupTarget) -> void:
	_targets.append(t)
	add_child(t)
	t.struck.connect(_on_struck)
	queue_redraw()


func targets() -> Array[StandupTarget]:
	return _targets


func marked_count() -> int:
	var n := 0
	for t in _targets:
		if t.marked:
			n += 1
	return n


func is_complete() -> bool:
	return not _targets.is_empty() and marked_count() == _targets.size()


func _on_struck(target: StandupTarget, ball: Ball) -> void:
	if not _present or target.marked:
		return
	target.set_marked(true)
	queue_redraw()
	AudioDirector.play(&"drop_clack")
	TableScore.earn(group, target_value, target.id, ball)
	target_struck.emit(_targets.find(target))
	if is_complete():
		_complete(ball)


## `complete_value` of 0 means the bank has no payout of its own — the boss door and the
## Commission chairs are owned by a mode that pays for them — and a zero-value earn is not a
## silent no-op: it would still close a switch, extend a combo and file a Jobs hit.
func _complete(ball: Ball) -> void:
	AudioDirector.play(&"drop_bank_down")
	if complete_value > 0.0:
		TableScore.earn_big(group, BigMoney.from_float(complete_value),
				StringName(String(id) + "_complete"), ball)
	_reset_in = reset_seconds
	bank_completed.emit()


func reset_now() -> void:
	_reset_in = -1.0
	for t in _targets:
		t.set_marked(false)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if _reset_in < 0.0:
		return
	_reset_in -= delta
	if _reset_in <= 0.0:
		reset_now()
		if _present:
			AudioDirector.play(&"drop_bank_reset")


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active)
	if not active:
		reset_now()
	queue_redraw()


## Presentation-only bank state. TargetBank's completion/reset/payout timing remains exactly
## the gameplay contract above; this classification is used solely for the parent plaque.
func _visual_state_id() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	if is_complete():
		return TableVisualState.VisualState.COMPLETED
	if marked_count() > 0:
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.IDLE


func visual_state() -> Dictionary:
	return TableVisualState.state_token(_visual_state_id(), {
		&"marked": marked_count() > 0, &"down": is_complete(),
	})


func visual_token() -> Dictionary:
	return visual_state()


func _material_fill(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.theme != null:
		var material := Presentation.theme.material_for(role)
		var fill: Variant = material.get("fill", fallback)
		if fill is Color:
			return fill as Color
	return fallback


func _draw() -> void:
	if _targets.is_empty():
		return
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for target: StandupTarget in _targets:
		var half := target.length * 0.5
		min_x = minf(min_x, target.position.x - half)
		max_x = maxf(max_x, target.position.x + half)
		min_y = minf(min_y, target.position.y)
		max_y = maxf(max_y, target.position.y)
	var token := visual_token()
	var state := StringName(token["state"])
	var ink := _material_fill(&"ink_glass", Feel.COL_INK)
	var brass := _material_fill(&"brass", Feel.COL_BRASS)
	var paper := _material_fill(&"newsprint", Feel.COL_NEWSPRINT)
	var rail_y := min_y + 31.0
	# A shallow backing rail groups the targets as one bank without introducing a collider.
	draw_line(Vector2(min_x - 12.0, rail_y), Vector2(max_x + 12.0, rail_y), ink, 12.0)
	draw_line(Vector2(min_x - 10.0, rail_y), Vector2(max_x + 10.0, rail_y),
			brass.darkened(0.50) if state != &"disabled" else ink.lightened(0.18), 5.0)
	for i in range(_targets.size()):
		var at := Vector2(lerpf(min_x, max_x, float(i) / float(maxi(_targets.size() - 1, 1))), rail_y)
		var target_marked := _targets[i].marked
		draw_circle(at, 7.0, paper if target_marked else brass.darkened(0.48))
		draw_arc(at, 10.0, 0.0, TAU, 12, ink, 2.0)
	if state == &"completed":
		draw_line(Vector2(min_x, max_y + 18.0), Vector2(max_x, max_y + 18.0), paper, 4.0)
