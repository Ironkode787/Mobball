class_name ContainerStacks
extends Node3D
## Three stacks of two shipping-container drop targets on the docks' raked deck. Clearing a
## stack is a smuggling hit; the stack comes back after a beat.

signal state_changed(cleared_stacks: Array)
signal stack_cleared(stack: int)

const STACKS := 3
const PER_STACK := 2
const CRATE_LENGTH := 0.16
const CRATE_THICK := 0.10
const CRATE_PITCH := 0.15
const STACK_PITCH := 0.40
const DECK_RAKE_DEG := 12.0
const CRATE_RAKE_DEG := 18.0

@export var id: StringName = &"containers"

var reset_seconds: float = 6.0
var crate_value: float = TableScore.SMUGGLING_CONTAINER
var group: StringName = TableScore.GROUP_SMUGGLING

var _targets: Array[DropTarget] = []
var _reset_in: PackedFloat32Array = PackedFloat32Array()
var _present: bool = true


## `origin` is the centre of the first (up-field) crate in plan space.
func configure(p_id: StringName, origin: Vector2) -> void:
	id = p_id
	position = Layout.p3(origin)


func _ready() -> void:
	_reset_in.resize(STACKS)
	var step := tan(deg_to_rad(DECK_RAKE_DEG))
	var rake := deg_to_rad(CRATE_RAKE_DEG)
	for s in range(STACKS):
		_reset_in[s] = -1.0
		for c in range(PER_STACK):
			var along := float(s) * STACK_PITCH + float(c) * CRATE_PITCH
			var t := DropTarget.new()
			t.name = "Stack%dCrate%d" % [s + 1, c + 1]
			t.thickness = CRATE_THICK
			t.configure(StringName("%s_%d%d" % [id, s + 1, c + 1]),
					Vector2(along, along * step), Vector2(0.0, -1.0).rotated(rake), CRATE_LENGTH)
			add_child(t)
			t.dropped.connect(_on_dropped)
			_targets.append(t)


func targets() -> Array[DropTarget]:
	return _targets


func target_at(stack: int, crate: int) -> DropTarget:
	return _targets[stack * PER_STACK + crate]


func stack_down(stack: int) -> int:
	var n := 0
	for c in range(PER_STACK):
		if target_at(stack, c).down:
			n += 1
	return n


func stack_is_clear(stack: int) -> bool:
	return stack_down(stack) == PER_STACK


func cleared_stacks() -> Array:
	var out: Array = []
	for s in range(STACKS):
		if stack_is_clear(s):
			out.append(s)
	return out


func reset_now() -> void:
	if _reset_in.size() < STACKS:
		_reset_in.resize(STACKS)
	for s in range(STACKS):
		_reset_in[s] = -1.0
	for t in _targets:
		t.raise()


func _on_dropped(target: DropTarget) -> void:
	if not _present:
		return
	var stack := _targets.find(target) / PER_STACK
	TableScore.earn_quiet(group, crate_value, target.id)
	if not stack_is_clear(stack):
		return
	_reset_in[stack] = reset_seconds
	AudioDirector.play(&"container_break")
	stack_cleared.emit(stack)
	state_changed.emit(cleared_stacks())


func _physics_process(delta: float) -> void:
	for s in range(STACKS):
		if _reset_in[s] < 0.0:
			continue
		_reset_in[s] -= delta
		if _reset_in[s] > 0.0:
			continue
		_reset_in[s] = -1.0
		for c in range(PER_STACK):
			target_at(s, c).raise()
		if _present:
			AudioDirector.play(&"drop_bank_reset")
		state_changed.emit(cleared_stacks())


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active)
	if not active:
		reset_now()


func is_hardware_active() -> bool:
	return _present


func visual_state(stack: int = -1) -> Dictionary:
	var state := TableVisualState.VisualState.ARMED
	var down := false
	if not _present:
		state = TableVisualState.VisualState.DISABLED
	elif stack >= 0 and stack < STACKS:
		var count := stack_down(stack)
		down = count > 0
		if count >= PER_STACK:
			state = TableVisualState.VisualState.COMPLETED
		elif down:
			state = TableVisualState.VisualState.ACTIVE
	elif stack >= STACKS:
		state = TableVisualState.VisualState.DISABLED
	else:
		var cleared := cleared_stacks()
		down = not cleared.is_empty()
		if cleared.size() >= STACKS:
			state = TableVisualState.VisualState.COMPLETED
		elif down:
			state = TableVisualState.VisualState.ACTIVE
	return TableVisualState.state_token(state, {&"down": down})


func visual_token(stack: int = -1) -> Dictionary:
	return visual_state(stack)
