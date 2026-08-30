class_name OnboardingCoach
extends CanvasLayer
## The first Night teaches with the live table, never a modal. The card is touch-transparent,
## leaves on its own, and uses the same dirty/clean vocabulary the player will keep forever.

const EARN_CONFIRM_SECONDS := 4.5

var _panel: PanelContainer = null
var _eyebrow: Label = null
var _message: Label = null
var _stage: StringName = &"launch"
var _left := 0.0


func _ready() -> void:
	layer = 60
	_panel = PaperKit.panel(Color(Feel.COL_INK, 0.90), Feel.COL_BRASS)
	_panel.name = "CoachCard"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 3)
	_panel.add_child(col)
	_eyebrow = PaperKit.label("THE FIRST JOB", PaperKit.FONT_SMALL, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER)
	_message = PaperKit.label("", PaperKit.FONT_BODY, Feel.COL_NEWSPRINT,
			HORIZONTAL_ALIGNMENT_CENTER)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_eyebrow)
	col.add_child(_message)
	Presentation.safe.margins_changed.connect(_on_safe_changed)
	Events.ball_launched.connect(_on_ball_launched)
	Events.dirty_earned.connect(_on_dirty_earned)
	_apply_safe()
	_show_stage(&"launch")


func _process(delta: float) -> void:
	if _stage != &"earn":
		return
	_left = maxf(0.0, _left - delta)
	if _left > 0.0:
		return
	_show_stage(&"done")


func _on_ball_launched(_ball: Node2D, _power: float) -> void:
	if _stage == &"launch":
		_show_stage(&"flip")


func _on_dirty_earned(_amount: BigMoney, group: StringName) -> void:
	if _stage == &"flip" and group != &"idle":
		_show_stage(&"earn")


func _show_stage(next: StringName) -> void:
	_stage = next
	match _stage:
		&"launch":
			_eyebrow.text = "THE FIRST JOB"
			_message.text = "PULL DOWN IN THE RIGHT LANE · RELEASE TO LAUNCH"
			_left = 0.0
			_panel.visible = true
		&"flip":
			_eyebrow.text = "KEEP HIM WORKING"
			_message.text = "TAP LEFT OR RIGHT TO FLIP · HOLD TO TRAP"
			_left = 0.0
			_panel.visible = true
		&"earn":
			_eyebrow.text = "FIRST TAKE"
			_message.text = "RED IS DIRTY CASH · THE COUNT SHOWS WHAT YOU CAN SPEND"
			_message.add_theme_color_override("font_color", Feel.COL_DIRTY.lightened(0.18))
			_left = EARN_CONFIRM_SECONDS
			_panel.visible = true
		_:
			_left = 0.0
			_panel.visible = false


func _on_safe_changed(_margins: Vector4) -> void:
	_apply_safe()


func _apply_safe() -> void:
	if _panel == null:
		return
	var m := Presentation.safe.margins()
	# One slim card above the flipper line, ending before the x=940 shooter-lane contract.
	# It teaches on the live table without becoming another header or hiding either control.
	_panel.offset_left = m.x + 52.0
	_panel.offset_right = -(maxf(m.z, 140.0) + 40.0)
	_panel.offset_top = -(m.w + 432.0)
	_panel.offset_bottom = -(m.w + 312.0)


func stage() -> StringName:
	return _stage


func card_rect() -> Rect2:
	return _panel.get_rect() if _panel != null else Rect2()


func touch_transparent() -> bool:
	return _panel != null and _panel.mouse_filter == Control.MOUSE_FILTER_IGNORE


func message() -> String:
	return _message.text if _message != null else ""
