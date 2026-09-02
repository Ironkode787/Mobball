class_name TargetBank
extends Node3D
## A bank of standups: mark them all to complete, hold the bonus, reset after a beat.

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
	AudioDirector.play(&"drop_clack")
	TableScore.earn(group, target_value, target.id, ball)
	target_struck.emit(_targets.find(target))
	if is_complete():
		_complete(ball)


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


func is_hardware_active() -> bool:
	return _present


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
