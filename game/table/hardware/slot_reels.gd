class_name SlotReels
extends Node2D
## Three slot reels built out of drop targets (docs/02 §2 R4): a 3×3 grid, one column per
## reel, each column stacked so the bottom target shields the two above it — knocking a reel
## down is a three-shot sequence, not one hit.
##
## Columns reset **independently**, each on its own timer from the moment it cleared, so the
## bank is never all-or-nothing and there is always something live to shoot at. Which columns
## are down right now goes out as a signal; the flow lane owns what a matching set is worth.
##
## Row pitch is deliberately smaller than a ball: the slot between two targets is a wall, not
## a route (same rule as the payphone bank in tests/test_table_geometry.gd).

## The set of cleared reels changed — a column went down, or one came back up.
signal state_changed(cleared_columns: Array)
signal column_cleared(column: int)

const COLS := 3
const ROWS := 3
const TARGET_LENGTH := 44.0
const COL_PITCH := 130.0
const ROW_PITCH := 50.0
## A drop target's roof is a flat 44 px ridge, and a flat ridge under top-down gravity is a
## shelf. Each target is tipped off square (the M1 storefront banks' fix, docs/02 §3) so a
## ball that lands on one slides off instead of sitting down on the reel.
const RAKE_DEG: PackedFloat32Array = [15.0, -15.0, 15.0]

@export var id: StringName = &"slot_reels"

var reset_seconds: float = 2.0
var target_value: float = TableScore.CASINO_REEL
var group: StringName = TableScore.GROUP_CASINO

var _targets: Array[DropTarget] = []          ## column-major: [col * ROWS + row]
var _reset_in: PackedFloat32Array = PackedFloat32Array()
var _present: bool = true


func _ready() -> void:
	_reset_in.resize(COLS)
	for c in range(COLS):
		_reset_in[c] = -1.0
		for r in range(ROWS):
			var t := DropTarget.new()
			t.name = "Reel%dSlot%d" % [c + 1, r + 1]
			# Local space: the bank's own rake (if any) rides on this node; the targets sit
			# square in it, face down, because every shot at them comes from below.
			t.configure(StringName("%s_%d%d" % [id, c + 1, r + 1]),
					Vector2((float(c) - 1.0) * COL_PITCH, (float(r) - 1.0) * ROW_PITCH),
					Vector2.DOWN.rotated(deg_to_rad(RAKE_DEG[c])), TARGET_LENGTH)
			add_child(t)
			t.dropped.connect(_on_dropped)
			_targets.append(t)


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
	AudioDirector.play(&"drop_bank_down")
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


func _draw() -> void:
	var w := COL_PITCH * 0.5 - 8.0
	var h := ROW_PITCH * float(ROWS) * 0.5 + 6.0
	for c in range(COLS):
		var x := (float(c) - 1.0) * COL_PITCH
		var lit := column_is_clear(c)
		var frame := Feel.COL_BRASS.darkened(0.55) if not lit else Feel.COL_BRASS
		draw_rect(Rect2(Vector2(x - w, -h), Vector2(w * 2.0, h * 2.0)),
				Feel.COL_INK.darkened(0.3))
		draw_rect(Rect2(Vector2(x - w, -h), Vector2(w * 2.0, h * 2.0)), frame, false, 3.0)
