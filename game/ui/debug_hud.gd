class_name DebugHUD
extends CanvasLayer
## M0 instrumentation strip. Plain Labels, default font, zero styling effort — this exists to
## make the physics legible while tuning, not to look like anything.

const ROW_H := 34.0

var dirty_cash: int = 0

var _table: AlleyDebugTable = null
var _nudge: NudgeController = null
var _left: Label = null
var _right: Label = null
var _charge: ProgressBar = null


func _ready() -> void:
	layer = 10
	var panel := ColorRect.new()
	panel.color = Color(0.07, 0.06, 0.05, 0.72)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = ROW_H * 3.0 + 12.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_left = _make_label(HORIZONTAL_ALIGNMENT_LEFT)
	_right = _make_label(HORIZONTAL_ALIGNMENT_RIGHT)

	_charge = ProgressBar.new()
	_charge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_charge.offset_left = 620.0
	_charge.offset_right = -40.0
	_charge.offset_top = -46.0
	_charge.offset_bottom = -14.0
	_charge.max_value = 1.0
	_charge.step = 0.001
	_charge.show_percentage = false
	_charge.value = 0.0
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_charge)

	Events.scored.connect(_on_scored)
	Events.plunger_charge_changed.connect(_on_charge)


func _make_label(align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_left = 18.0
	l.offset_right = -18.0
	l.offset_top = 8.0
	l.offset_bottom = 8.0 + ROW_H * 3.0
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
	l.add_theme_font_size_override("font_size", 26)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func bind(table: AlleyDebugTable, nudge: NudgeController) -> void:
	_table = table
	_nudge = nudge


func _on_scored(_id: StringName, value: int) -> void:
	dirty_cash += value


func _on_charge(power: float) -> void:
	if _charge != null:
		_charge.value = power


func _process(_delta: float) -> void:
	if _left == null:
		return
	var speed := 0.0
	var top := 0.0
	var pos := Vector2.ZERO
	var balls := 0
	if _table != null and is_instance_valid(_table):
		balls = _table.balls_served
		if _table.ball != null and is_instance_valid(_table.ball):
			speed = _table.ball.speed()
			top = _table.ball.top_speed
			pos = _table.ball.global_position
	var warn := 0
	var tilted := false
	if _nudge != null:
		warn = _nudge.warnings()
		tilted = _nudge.tilted()

	_left.text = "DIRTY $%d\nGUY %d   %s\nSPEED %4.0f  (max %4.0f)" % [
		dirty_cash, balls, "TILT" if tilted else "LEANS %d/%d" % [warn, Feel.TILT_MAX_WARNINGS], speed, top
	]
	_right.text = "FPS %d\nPHYS %d Hz\nBALL %4.0f,%4.0f" % [
		int(Engine.get_frames_per_second()), Engine.physics_ticks_per_second, pos.x, pos.y
	]
