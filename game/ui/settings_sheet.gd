class_name SettingsSheet
extends CanvasLayer
## The Usual Controls: one modal sheet for sensory accessibility and the four authored buses.

signal closed

const TOGGLES := [
	{&"id": &"reduced_motion", &"label": "REDUCED MOTION"},
	{&"id": &"reduced_flash", &"label": "REDUCED FLASH"},
	{&"id": &"haptics_enabled", &"label": "HAPTICS"},
	{&"id": &"subtitles_enabled", &"label": "SUBTITLES"},
]

var _content: MarginContainer = null
var _toggle_buttons: Dictionary = {}
var _sliders: Dictionary = {}


func _ready() -> void:
	layer = 90
	var shade := ColorRect.new()
	shade.color = Color(Feel.COL_INK, 0.96)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_content = MarginContainer.new()
	_content.name = "SafeContent"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_changed)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_content.add_child(outer)
	outer.add_child(PaperKit.label("HOUSE RULES", PaperKit.FONT_TITLE, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER))
	var intro := PaperKit.label("MAKE THE TABLE COMFORTABLE WITHOUT LOSING INFORMATION.",
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.16),
			HORIZONTAL_ALIGNMENT_CENTER)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size.x = 0.0
	outer.add_child(intro)
	outer.add_child(PaperKit.rule())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	body.add_child(PaperKit.label("ACCESSIBILITY", PaperKit.FONT_BODY, Feel.COL_BRASS))
	for row: Dictionary in TOGGLES:
		var id: StringName = row[&"id"]
		var button := PaperKit.button("", PaperKit.FONT_BODY,
				Feel.COL_CLEAN if Presentation.settings.toggle_value(id) else Feel.COL_BRASS)
		button.name = "Toggle_%s" % String(id)
		button.clip_text = true
		button.toggle_mode = true
		button.button_pressed = Presentation.settings.toggle_value(id)
		button.toggled.connect(func(on: bool) -> void: _on_toggle(id, String(row[&"label"]), on))
		_toggle_buttons[id] = button
		body.add_child(button)
		_refresh_toggle(button, String(row[&"label"]), button.button_pressed)

	body.add_child(PaperKit.rule())
	body.add_child(PaperKit.label("MIX", PaperKit.FONT_BODY, Feel.COL_BRASS))
	for bus_name: String in PresentationSettings.AUDIO_BUSES:
		body.add_child(_audio_row(bus_name))

	var close := PaperKit.button("DONE", PaperKit.FONT_BIG, Feel.COL_CLEAN)
	close.name = "SettingsDone"
	close.pressed.connect(func() -> void: closed.emit())
	outer.add_child(close)


func _audio_row(bus_name: String) -> Control:
	var panel := PaperKit.panel(Feel.COL_INK.lightened(0.07), Feel.COL_BRASS.darkened(0.34))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)
	var title := PaperKit.label(bus_name.to_upper(), PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT)
	col.add_child(title)
	var slider := HSlider.new()
	slider.name = "Volume_%s" % bus_name
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 5.0
	slider.value = Presentation.settings.bus_level(bus_name) * 100.0
	slider.custom_minimum_size = Vector2(0.0, Presentation.theme.touch_min)
	slider.focus_mode = Control.FOCUS_ALL
	slider.value_changed.connect(func(value: float) -> void:
		Presentation.settings.set_bus_level(bus_name, value / 100.0)
		title.text = "%s  %d%%" % [bus_name.to_upper(), int(round(value))])
	title.text = "%s  %d%%" % [bus_name.to_upper(), int(round(slider.value))]
	_sliders[bus_name] = slider
	col.add_child(slider)
	return panel


func _on_toggle(id: StringName, label: String, enabled: bool) -> void:
	Presentation.settings.set_toggle(id, enabled, Presentation.fx)
	_refresh_toggle(_toggle_buttons[id] as Button, label, enabled)


func _refresh_toggle(button: Button, label: String, enabled: bool) -> void:
	button.text = "%s   ·   %s" % [label, "ON" if enabled else "OFF"]
	button.add_theme_color_override("font_hover_color", Feel.COL_CLEAN if enabled else Feel.COL_BRASS)


func _on_safe_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content, Vector4(54.0, 70.0, 54.0, 54.0))


func toggle_button(id: StringName) -> Button:
	return _toggle_buttons.get(id) as Button


func slider(bus_name: String) -> HSlider:
	return _sliders.get(bus_name) as HSlider
