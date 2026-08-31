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


func visual_state() -> int:
	if not _present:
		return TableVisualState.VisualState.DISABLED
	var cleared := cleared_columns().size() if _targets.size() >= COLS * ROWS else 0
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
	return {
		&"down": _any_down(),
		&"marked": _targets.size() >= COLS * ROWS and cleared_columns().size() > 0,
		&"cooldown": reset,
	}


func visual_token() -> Dictionary:
	return TableVisualState.state_token(visual_state(), visual_modifiers())


func _any_down() -> bool:
	for target: DropTarget in _targets:
		if target != null and is_instance_valid(target) and target.down:
			return true
	return false


func _ambient(role: StringName, fallback: Color) -> Color:
	if Presentation != null and Presentation.city != null:
		var candidate := Presentation.city.material_for(role)
		if candidate.a > 0.0:
			return candidate
	return fallback


func _draw_hatch(rect: Rect2, color: Color) -> void:
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		draw_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), color, 2.0)
		x += 14.0


func _draw_state_cue(center: Vector2, radius: float, token: Dictionary, color: Color) -> void:
	var mark := String(token["mark"])
	if mark == "invitation_pin":
		draw_circle(center, radius * 0.72, color)
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(-radius * 0.32, radius * 0.32),
			center + Vector2(radius * 0.32, radius * 0.32),
			center + Vector2(0.0, radius * 1.10),
		]), color)
	elif mark == "marked_stamp":
		draw_rect(Rect2(center - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
				color, false, 3.0)
		draw_line(center + Vector2(-radius * 0.5, 0.0), center + Vector2(-radius * 0.08, radius * 0.42), color, 3.0)
		draw_line(center + Vector2(-radius * 0.08, radius * 0.42), center + Vector2(radius * 0.58, -radius * 0.48), color, 3.0)
	elif mark == "lock_offline":
		draw_rect(Rect2(center - Vector2(radius * 0.72, radius * 0.38), Vector2(radius * 1.44, radius)),
				color, false, 3.0)
		draw_arc(center + Vector2(0.0, -radius * 0.26), radius * 0.42, PI, TAU, 12, color, 3.0)
	else:
		draw_arc(center, radius, 0.0, TAU, 20, color, 3.0)
	if String(token["pattern"]) == "offline_hatch" or String(token["pattern"]) == "cooldown_dash":
		for i in range(3):
			var y := center.y - radius * 0.35 + float(i) * radius * 0.35
			draw_line(Vector2(center.x - radius * 0.42, y), Vector2(center.x + radius * 0.42, y), color, 2.0)


func _draw() -> void:
	var token := visual_token()
	var state := String(token["state"])
	var ink := _ambient(&"ink_glass", Feel.COL_INK)
	var brass := _ambient(&"brass", Feel.COL_BRASS)
	var paper := _ambient(&"paper", Feel.COL_NEWSPRINT)
	var violet := Feel.COL_VIOLET
	var w := COL_PITCH * 0.5 - 8.0
	var h := ROW_PITCH * float(ROWS) * 0.5 + 6.0
	var state_col := brass if state == "armed" else paper
	if state == "active":
		state_col = violet.lightened(0.22)
	if state == "completed":
		state_col = paper
	if state == "disabled":
		state_col = paper.darkened(0.35)
	for c in range(COLS):
		var x := (float(c) - 1.0) * COL_PITCH
		var lit := _targets.size() >= COLS * ROWS and column_is_clear(c)
		var frame := brass.darkened(0.55) if not lit else brass
		if state == "disabled":
			frame = paper.darkened(0.42)
		draw_rect(Rect2(Vector2(x - w, -h), Vector2(w * 2.0, h * 2.0)),
				Color(ink.r, ink.g, ink.b, 0.88))
		draw_rect(Rect2(Vector2(x - w, -h), Vector2(w * 2.0, h * 2.0)), frame, false, 5.0)
		# The nine windows make the column pitch legible without painting another route.
		for r in range(ROWS):
			var y := (float(r) - 1.0) * ROW_PITCH
			var target := target_at(c, r) if _targets.size() >= COLS * ROWS else null
			var down := target != null and is_instance_valid(target) and target.down
			var slot := Rect2(Vector2(x - w + 8.0, y - 18.0), Vector2(w * 2.0 - 16.0, 36.0))
			draw_rect(slot, Color(violet.r, violet.g, violet.b, 0.13) if not down else
					Color(paper.r, paper.g, paper.b, 0.15))
			draw_rect(slot, paper.darkened(0.18) if down else brass.darkened(0.46), false, 2.0)
			if down:
				draw_line(slot.position + Vector2(8.0, 18.0), slot.end - Vector2(8.0, 18.0), paper, 3.0)
				draw_line(slot.position + Vector2(8.0, 26.0), slot.end - Vector2(8.0, 10.0), paper, 3.0)
		# A tiny reel index keeps the three columns distinct in a dense Club frame.
		var label_font := Presentation.theme.font_for(&"annotation")
		if label_font != null:
			draw_string(label_font, Vector2(x - w + 8.0, -h - 8.0), "R%d" % (c + 1),
					HORIZONTAL_ALIGNMENT_LEFT, 30.0, 15, state_col)
		if lit:
			draw_arc(Vector2(x, 0.0), w - 5.0, -PI * 0.5, PI * 0.5, 14, paper, 3.0)
	if state == "disabled":
		_draw_hatch(Rect2(Vector2(-COL_PITCH - w, -h), Vector2(COL_PITCH * 2.0 + w * 2.0, h * 2.0)),
				Color(paper.r, paper.g, paper.b, 0.18))
	_draw_state_cue(Vector2(COL_PITCH + 17.0, -h + 12.0), 11.0, token, state_col)
