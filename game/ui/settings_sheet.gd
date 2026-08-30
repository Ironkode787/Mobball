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
var _telemetry_button: Button = null
var _telemetry_status: Label = null
var _credits: CreditsSheet = null


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

	body.add_child(PaperKit.rule())
	body.add_child(PaperKit.label("BETA PROGRAM", PaperKit.FONT_BODY, Feel.COL_BRASS))
	var privacy := PaperKit.label(
			"OPTIONAL. STORES COARSE GAMEPLAY MILESTONES ON THIS DEVICE. " +
			"NO NAME, DEVICE ID, EXACT BALANCES, OR AUTOMATIC UPLOAD.",
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.16))
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(privacy)
	_telemetry_button = PaperKit.button("", PaperKit.FONT_BODY,
			Feel.COL_CLEAN if Telemetry.enabled() else Feel.COL_BRASS)
	_telemetry_button.name = "Toggle_beta_telemetry"
	_telemetry_button.toggle_mode = true
	_telemetry_button.button_pressed = Telemetry.enabled()
	_telemetry_button.toggled.connect(_on_telemetry_toggled)
	body.add_child(_telemetry_button)
	_refresh_telemetry_button()
	var export := PaperKit.button("COPY + EXPORT BETA REPORT", PaperKit.FONT_SMALL, Feel.COL_BRASS)
	export.name = "ExportBetaReport"
	export.pressed.connect(_on_export_telemetry)
	body.add_child(export)
	var clear := PaperKit.button("CLEAR BETA DATA", PaperKit.FONT_SMALL, Feel.COL_DIRTY)
	clear.name = "ClearBetaData"
	clear.pressed.connect(func() -> void:
		_refresh_telemetry_status("LOCAL BETA DATA CLEARED" if Telemetry.clear_data() \
				else "COULD NOT CLEAR EVERY BETA FILE"))
	body.add_child(clear)
	_telemetry_status = PaperKit.label("", PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT,
			HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_telemetry_status)
	_refresh_telemetry_status()
	var credits := PaperKit.button("THE USUAL SUSPECTS", PaperKit.FONT_SMALL, Feel.COL_BRASS)
	credits.name = "OpenCredits"
	credits.pressed.connect(_open_credits)
	body.add_child(credits)

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


func _on_telemetry_toggled(on: bool) -> void:
	var saved := Telemetry.set_enabled(on)
	_telemetry_button.set_pressed_no_signal(Telemetry.enabled())
	_refresh_telemetry_button()
	if not saved:
		_refresh_telemetry_status("COULD NOT SAVE BETA CHOICE · COLLECTION %s THIS SESSION" %
				("ON" if Telemetry.enabled() else "OFF"))
	else:
		_refresh_telemetry_status("COLLECTION ENABLED" if on else "COLLECTION OFF · LOCAL DATA CLEARED")


func _on_export_telemetry() -> void:
	if not Telemetry.enabled():
		_refresh_telemetry_status("ALLOW BETA TELEMETRY BEFORE EXPORTING")
		return
	var copied := Telemetry.report_json()
	DisplayServer.clipboard_set(copied)
	_refresh_telemetry_status("REPORT COPIED · %s" %
			("FILE EXPORTED" if Telemetry.export_report() else "FILE EXPORT FAILED"))


func _refresh_telemetry_button() -> void:
	if _telemetry_button == null:
		return
	_telemetry_button.text = "BETA TELEMETRY   ·   %s" % ("ALLOWED" if Telemetry.enabled() else "OFF")
	_telemetry_button.add_theme_color_override("font_hover_color",
			Feel.COL_CLEAN if Telemetry.enabled() else Feel.COL_BRASS)


func _refresh_telemetry_status(message: String = "") -> void:
	if _telemetry_status == null:
		return
	_telemetry_status.text = message if not message.is_empty() else "%d LOCAL EVENTS" % Telemetry.event_count()


func _open_credits() -> void:
	if _credits != null and is_instance_valid(_credits):
		return
	_credits = CreditsSheet.new()
	_credits.name = "Credits"
	_credits.closed.connect(func() -> void:
		_credits.queue_free()
		_credits = null)
	add_child(_credits)


func _on_safe_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content, Vector4(54.0, 70.0, 54.0, 54.0))


func toggle_button(id: StringName) -> Button:
	return _toggle_buttons.get(id) as Button


func slider(bus_name: String) -> HSlider:
	return _sliders.get(bus_name) as HSlider


func telemetry_button() -> Button:
	return _telemetry_button
