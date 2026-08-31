class_name OnboardingCoach
extends CanvasLayer
## The first Night teaches with the live table, never a modal. The card is touch-transparent,
## leaves on its own, and uses the same dirty/clean vocabulary the player will keep forever.

const EARN_CONFIRM_SECONDS := 4.5
const SHOOTER_LANE_GAP := 16.0
const FLIPPER_GAP := 24.0
const CARD_GUTTER := 24.0
const NARROW_CARD_GUTTER := 16.0
const STANDARD_CARD_WIDTH := 840.0
const STANDARD_CARD_HEIGHT := 140.0
const NARROW_CARD_HEIGHT := 118.0

var _panel: PanelContainer = null
var _eyebrow: Label = null
var _message: Label = null
var _stage: StringName = &"launch"
var _left := 0.0
var _layout_narrow := false


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
	get_viewport().size_changed.connect(_on_viewport_resized)
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
	_layout_narrow = _is_narrow_layout()
	match _stage:
		&"launch":
			_eyebrow.text = "THE FIRST JOB"
			_message.text = "PULL TO LAUNCH" if _layout_narrow \
					else "PULL DOWN IN THE RIGHT LANE · RELEASE TO LAUNCH"
			_message.add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
			_left = 0.0
			_panel.visible = true
		&"flip":
			_eyebrow.text = "KEEP HIM WORKING"
			_message.text = "FLIP LEFT OR RIGHT · HOLD TO TRAP" if _layout_narrow \
					else "TAP LEFT OR RIGHT TO FLIP · HOLD TO TRAP"
			_message.add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
			_left = 0.0
			_panel.visible = true
		&"earn":
			_eyebrow.text = "FIRST TAKE"
			_message.text = "SPEND DIRTY CASH IN THE COUNT" if _layout_narrow \
					else "RED IS DIRTY CASH · THE COUNT SHOWS WHAT YOU CAN SPEND"
			_message.add_theme_color_override("font_color", Feel.COL_DIRTY.lightened(0.18))
			_left = EARN_CONFIRM_SECONDS
			_panel.visible = true
		_:
			_left = 0.0
			_panel.visible = false


func _on_safe_changed(_margins: Vector4) -> void:
	_refresh_layout()


func _on_viewport_resized() -> void:
	_refresh_layout()


func _refresh_layout() -> void:
	var was_narrow := _layout_narrow
	_apply_safe()
	if _panel == null or was_narrow == _layout_narrow:
		return
	var remaining := _left
	_show_stage(_stage)
	_left = remaining


func _apply_safe() -> void:
	if _panel == null:
		return
	_layout_narrow = _is_narrow_layout()
	var layout := _layout_contract()
	var safe: Rect2 = layout["safe_content"]
	var viewport_size: Vector2 = layout["logical_viewport"]
	var shooter_left: float = layout["shooter_lane_left"]
	var flipper_top: float = layout["flipper_region_top"]
	var gutter := NARROW_CARD_GUTTER if _is_narrow_layout() else CARD_GUTTER
	var left := safe.position.x + gutter
	var right := minf(safe.end.x - gutter, shooter_left - SHOOTER_LANE_GAP)
	# A positive fallback keeps the node measurable while a viewport is settling. Normal
	# supported profiles always have enough width for the readable copy and both gaps.
	if right <= left:
		left = safe.position.x
		right = minf(safe.end.x, shooter_left - 4.0)
	var width := maxf(1.0, minf(STANDARD_CARD_WIDTH if not _layout_narrow else 680.0,
			right - left))
	var height := NARROW_CARD_HEIGHT if _layout_narrow else STANDARD_CARD_HEIGHT
	var bottom := minf(safe.end.y - gutter, flipper_top - FLIPPER_GAP)
	var top := bottom - height
	if top < safe.position.y + gutter:
		top = safe.position.y + gutter
		height = maxf(1.0, bottom - top)
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	# Top-left anchors make card_rect() a direct logical-coordinate contract. No bottom-wide
	# anchor offsets may import the host-clamped window height into the coach geometry.
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.position = Vector2(left, top)
	_panel.size = Vector2(width, height)
	_panel.custom_minimum_size = Vector2(width, height)
	_eyebrow.add_theme_font_size_override("font_size", 22 if _layout_narrow else 24)
	_message.add_theme_font_size_override("font_size", 27 if _layout_narrow else 30)
	_message.custom_minimum_size = Vector2(maxf(1.0, width - 40.0), 0.0)
	# Reduced motion/flash are intentionally static: stage changes remain immediate and the
	# earn confirmation keeps its authored 4.5-second information window.
	_panel.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _layout_contract() -> Dictionary:
	var viewport_size := get_viewport().get_visible_rect().size
	var safe := Presentation.safe.content_rect()
	var shooter_left := 940.0
	var flipper_top := 1520.0
	var parent := get_parent()
	if parent != null:
		var candidate: Variant = parent.get("hud")
		if candidate is GameHUD and is_instance_valid(candidate) and candidate.is_inside_tree():
			var contract := (candidate as GameHUD).geometry_contract()
			var contract_safe: Variant = contract.get("safe_content", Rect2())
			var contract_viewport: Variant = contract.get("logical_viewport", Vector2.ZERO)
			if contract_safe is Rect2 and (contract_safe as Rect2).size.x > 0.0 \
					and (contract_safe as Rect2).size.y > 0.0:
				safe = contract_safe
			if contract_viewport is Vector2 and (contract_viewport as Vector2).x > 0.0 \
					and (contract_viewport as Vector2).y > 0.0:
				viewport_size = contract_viewport
			shooter_left = float(contract.get("shooter_lane_left", shooter_left))
			flipper_top = float(contract.get("flipper_region_top", flipper_top))
	var viewport_rect := Rect2(Vector2.ZERO, viewport_size)
	safe = safe.intersection(viewport_rect)
	if safe.size.x <= 0.0 or safe.size.y <= 0.0:
		safe = viewport_rect
	return {
			"safe_content": safe,
			"logical_viewport": viewport_size,
			"shooter_lane_left": shooter_left,
			"flipper_region_top": flipper_top,
	}


func _is_narrow_layout() -> bool:
	var layout := _layout_contract()
	var safe: Rect2 = layout["safe_content"]
	var available := minf(safe.end.x - NARROW_CARD_GUTTER,
			float(layout["shooter_lane_left"]) - SHOOTER_LANE_GAP) \
			- safe.position.x - NARROW_CARD_GUTTER
	return available < 720.0


func stage() -> StringName:
	return _stage


func card_rect() -> Rect2:
	return _panel.get_rect() if _panel != null else Rect2()


func touch_transparent() -> bool:
	return _panel != null and _panel.mouse_filter == Control.MOUSE_FILTER_IGNORE


func message() -> String:
	return _message.text if _message != null else ""
