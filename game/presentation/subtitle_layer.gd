class_name SubtitleLayer
extends Control
## Safe, non-interactive captions for the muted-brass specialist voices.

const HOLD_SECONDS := 3.2

var _safe: PresentationSafeArea = null
var _panel: PanelContainer = null
var _speaker: Label = null
var _line: Label = null
var _left := 0.0


func configure(bus: EffectBus, safe_area: PresentationSafeArea) -> void:
	_safe = safe_area
	if bus != null and not bus.subtitle_requested.is_connected(_on_subtitle):
		bus.subtitle_requested.connect(_on_subtitle)


func _ready() -> void:
	# A CanvasLayer is not a Control parent, so anchors alone resolve against no rectangle.
	# Mirror the logical viewport explicitly, just like the gameplay-feedback overlay.
	position = Vector2.ZERO
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PaperKit.panel(Color(Feel.COL_INK, 0.92), Feel.COL_BRASS.darkened(0.12))
	_panel.name = "SubtitlePanel"
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	_speaker = PaperKit.label("", PaperKit.FONT_SMALL, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER)
	_line = PaperKit.label("", PaperKit.FONT_BODY, Feel.COL_NEWSPRINT,
			HORIZONTAL_ALIGNMENT_CENTER)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_speaker)
	col.add_child(_line)
	_panel.visible = false
	if _safe != null:
		_safe.margins_changed.connect(_on_safe_changed)
	get_viewport().size_changed.connect(_on_viewport_changed)
	_apply_safe()


func _process(delta: float) -> void:
	if _left <= 0.0:
		return
	_left = maxf(0.0, _left - delta)
	if _left <= 0.0 and _panel != null:
		_panel.visible = false


func _on_subtitle(text: String, speaker: StringName) -> void:
	if _panel == null or text.is_empty():
		return
	_speaker.text = String(speaker).replace("_", " ").to_upper()
	_speaker.visible = not speaker.is_empty()
	_line.text = text
	_panel.visible = true
	_left = HOLD_SECONDS


func _on_safe_changed(_margins: Vector4) -> void:
	_apply_safe()


func _on_viewport_changed() -> void:
	size = get_viewport_rect().size
	_apply_safe()


func _apply_safe() -> void:
	if _panel == null:
		return
	var m := _safe.margins() if _safe != null else Vector4.ZERO
	_panel.offset_left = m.x + 42.0
	_panel.offset_right = -(m.z + 42.0)
	# Keep the caption above the persistent bottom action row used by The Count and Ledger.
	# Dialogue normally happens on the live table, but an accessibility surface must remain
	# usable even when a line arrives during a screen handoff.
	_panel.offset_top = -(m.w + 548.0)
	_panel.offset_bottom = -(m.w + 384.0)


func snapshot() -> Dictionary:
	return {
		"visible": _panel != null and _panel.visible,
		"text": _line.text if _line != null else "",
		"speaker": _speaker.text if _speaker != null else "",
		"rect": _panel.get_rect() if _panel != null else Rect2(),
	}
