class_name SlotReels
extends Node3D
## Three reels of three drop targets on the Club deck: clear a column and the reel stops.

signal state_changed(cleared_columns: Array)
signal column_cleared(column: int)

const COLS := 3
const ROWS := 3
const TARGET_LENGTH := 0.14
const COL_PITCH := 0.22
const ROW_PITCH := 0.13
const RAKE_DEG: PackedFloat32Array = [15.0, -15.0, 15.0]

@export var id: StringName = &"slot_reels"

var reset_seconds: float = 2.0
var target_value: float = TableScore.CASINO_REEL
var group: StringName = TableScore.GROUP_CASINO

var _targets: Array[DropTarget] = []
var _reset_in: PackedFloat32Array = PackedFloat32Array()
var _present: bool = true


func configure(p_id: StringName, at: Vector2, base: float) -> void:
	id = p_id
	position = Layout.p3(at, base)


func _ready() -> void:
	_reset_in.resize(COLS)
	for c in range(COLS):
		_reset_in[c] = -1.0
		for r in range(ROWS):
			var t := DropTarget.new()
			t.name = "Reel%dSlot%d" % [c + 1, r + 1]
			t.thickness = 0.05
			t.configure(StringName("%s_%d%d" % [id, c + 1, r + 1]),
					Vector2((float(c) - 1.0) * COL_PITCH, (float(r) - 1.0) * ROW_PITCH),
					Vector2(0.0, 1.0).rotated(deg_to_rad(RAKE_DEG[c])), TARGET_LENGTH)
			add_child(t)
			t.dropped.connect(_on_dropped)
			_targets.append(t)
	# a cabinet behind the reels
	var lib := MaterialLib.shared()
	var cab := BoxMesh.new()
	cab.size = Vector3(COL_PITCH * 3.0 + 0.1, 0.55, 0.12)
	var cm := MeshInstance3D.new()
	cm.mesh = cab
	cm.material_override = lib.plastic(Color("3A1F3F"), 0.35)
	cm.position = Vector3(0.0, 0.275, -ROW_PITCH * 1.5 - 0.12)
	cm.name = "Cabinet"
	add_child(cm)
	var sign := TextMesh.new()
	sign.text = "SLOTS"
	sign.font = load("res://assets/fonts/Oswald-SemiBold.ttf")
	sign.font_size = 48
	sign.pixel_size = 0.005
	sign.depth = 0.02
	var sm := MeshInstance3D.new()
	sm.mesh = sign
	sm.material_override = lib.neon(Feel.COL_NEON_ROSE, 2.4)
	sm.position = Vector3(0.0, 0.62, -ROW_PITCH * 1.5 - 0.10)
	add_child(sm)


func targets() -> Array[DropTarget]:
	return _targets


func target_at(col: int, row: int) -> DropTarget:
	return _targets[col * ROWS + row]


func column_down(col: int) -> int:
	var n := 0
	for r in range(ROWS):
		if target_at(col, r).down:
			n += 1
	return n


func column_is_clear(col: int) -> bool:
	return column_down(col) == ROWS


func cleared_columns() -> Array:
	var out: Array = []
	for c in range(COLS):
		if column_is_clear(c):
			out.append(c)
	return out


func reset_now() -> void:
	for c in range(COLS):
		_reset_in[c] = -1.0
	for t in _targets:
		t.raise()


func _on_dropped(target: DropTarget) -> void:
	if not _present:
		return
	var col := _targets.find(target) / ROWS
	TableScore.earn_quiet(group, target_value, target.id)
	if not column_is_clear(col):
		return
	_reset_in[col] = reset_seconds
	AudioDirector.play(&"reel_stop")
	column_cleared.emit(col)
	state_changed.emit(cleared_columns())


func _physics_process(delta: float) -> void:
	for c in range(COLS):
		if _reset_in[c] < 0.0:
			continue
		_reset_in[c] -= delta
		if _reset_in[c] > 0.0:
			continue
		_reset_in[c] = -1.0
		for r in range(ROWS):
			target_at(c, r).raise()
		if _present:
			AudioDirector.play(&"drop_bank_reset")
		state_changed.emit(cleared_columns())


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for t in _targets:
		t.set_hardware_active(active)
	if not active:
		reset_now()


func is_hardware_active() -> bool:
	return _present


func _any_down() -> bool:
	for target: DropTarget in _targets:
		if target != null and is_instance_valid(target) and target.down:
			return true
	return false


func visual_state() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	var cleared := cleared_columns().size()
	if cleared >= COLS:
		return TableVisualState.VisualState.COMPLETED
	if cleared > 0 or _any_down():
		return TableVisualState.VisualState.ACTIVE
	return TableVisualState.VisualState.ARMED


func visual_modifiers() -> Dictionary:
	var reset := false
	for value: float in _reset_in:
		if value >= 0.0:
			reset = true
			break
	return {&"down": _any_down(), &"marked": cleared_columns().size() > 0, &"cooldown": reset}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())
