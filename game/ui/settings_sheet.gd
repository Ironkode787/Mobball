class_name SettingsSheet
extends CanvasLayer
## The Usual Controls: a calm, player-facing House Rules sheet.
##
## This screen owns presentation wiring only. Player preferences and beta data remain owned
## by PresentationSettings and Telemetry; this layer only provides safe controls for them.

signal closed

const TOGGLES: Array[Dictionary] = [
	{&"id": &"reduced_motion", &"label": "Reduced motion"},
	{&"id": &"reduced_flash", &"label": "Reduced flash"},
	{&"id": &"haptics_enabled", &"label": "Haptics"},
	{&"id": &"subtitles_enabled", &"label": "Subtitles"},
]

var _content: MarginContainer = null
var _scroll: ScrollContainer = null
var _toggle_buttons: Dictionary = {}
var _sliders: Dictionary = {}
var _slider_mute_buttons: Dictionary = {}
var _slider_reset_buttons: Dictionary = {}
var _telemetry_button: Button = null
var _telemetry_status: Label = null
var _clear_button: Button = null
var _clear_confirmation: PanelContainer = null
var _clear_confirm_button: Button = null
var _clear_cancel_button: Button = null
var _credits: CreditsSheet = null
var _credits_opener: Button = null


func _ready() -> void:
	layer = 90
	var shade := ColorRect.new()
	shade.name = "HouseRulesShade"
	shade.color = Color(Feel.COL_INK, Presentation.theme.overlay_opacity)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_content = MarginContainer.new()
	_content.name = "SafeContent"
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_content)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_changed)

	var outer := VBoxContainer.new()
	outer.name = "HouseRulesLayout"
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	_content.add_child(outer)

	var title := PaperKit.type_label("House Rules", &"title", Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	outer.add_child(title)
	var intro := PaperKit.type_label(
			"Make the table comfortable without losing information.", &"caption",
			Feel.COL_NEWSPRINT.darkened(0.12), HORIZONTAL_ALIGNMENT_CENTER)
	intro.name = "Intro"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(intro)
	outer.add_child(PaperKit.rule())

	_scroll = ScrollContainer.new()
	_scroll.name = "BodyScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	outer.add_child(_scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	_scroll.add_child(body)

	_build_comfort(body)
	_build_sound(body)
	_build_beta(body)
	_build_credits(body)

	# The footer is outside the scroll viewport, so it cannot cover body copy or confirmation.
	outer.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.48), Presentation.theme.rule_width))
	var footer := PaperKit.bottom_action_bar("DONE")
	footer.name = "SettingsFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var profile := _layout_profile()
	var profile_data := Presentation.theme.layout_profile(profile)
	footer.custom_minimum_size.y = float(profile_data.get("footer_height", Presentation.theme.touch_min))
	var done := footer.get_node("Actions/Primary") as Button
	if done != null:
		done.name = "SettingsDone"
		done.pressed.connect(_on_done_pressed)
	outer.add_child(footer)


func _build_comfort(body: VBoxContainer) -> void:
	var group := _group("Comfort", "Accessibility")
	body.add_child(group)
	var content := _group_content(group)
	for row_data: Dictionary in TOGGLES:
		var id: StringName = row_data[&"id"]
		var label_text := String(row_data[&"label"])
		var row := PaperKit.toggle_row(label_text, Presentation.settings.toggle_value(id))
		row.name = "ToggleRow_%s" % String(id)
		var button := row.get_node("Content/Switch") as Button
		if button == null:
			continue
		button.name = "Toggle_%s" % String(id)
		button.tooltip_text = label_text
		button.toggled.connect(func(enabled: bool) -> void:
			_on_toggle(id, enabled))
		_toggle_buttons[id] = button
		_refresh_toggle(button, enabled_from_settings(id))
		content.add_child(row)


func _build_sound(body: VBoxContainer) -> void:
	var group := _group("Sound", "Four authored buses")
	body.add_child(group)
	var content := _group_content(group)
	for bus_name: String in PresentationSettings.AUDIO_BUSES:
		content.add_child(_audio_row(bus_name))


func _build_beta(body: VBoxContainer) -> void:
	var group := _group("Beta", "Optional local testing")
	body.add_child(group)
	var content := _group_content(group)
	var privacy := PaperKit.type_label(
			"Optional. Stores coarse gameplay milestones on this device. " +
			"No name, device ID, exact balances, or automatic upload.", &"body",
			Presentation.theme.ink)
	privacy.name = "PrivacyCopy"
	privacy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	privacy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(privacy)

	var telemetry_row := PaperKit.toggle_row("Allow beta telemetry", Telemetry.enabled())
	telemetry_row.name = "BetaTelemetryRow"
	_telemetry_button = telemetry_row.get_node("Content/Switch") as Button
	if _telemetry_button != null:
		_telemetry_button.name = "Toggle_beta_telemetry"
		_telemetry_button.tooltip_text = "Allow beta telemetry"
		_telemetry_button.toggled.connect(_on_telemetry_toggled)
		_refresh_telemetry_button()
	content.add_child(telemetry_row)

	_telemetry_status = PaperKit.type_label("", &"metadata", Presentation.theme.ink,
			HORIZONTAL_ALIGNMENT_CENTER)
	_telemetry_status.name = "TelemetryStatus"
	_telemetry_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_telemetry_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_telemetry_status)
	_refresh_telemetry_status()

	var export := PaperKit.action_button("COPY + EXPORT BETA REPORT", &"secondary")
	export.name = "ExportBetaReport"
	export.pressed.connect(_on_export_telemetry)
	content.add_child(export)

	_clear_button = PaperKit.action_button("CLEAR BETA DATA", &"destructive")
	_clear_button.name = "ClearBetaData"
	_clear_button.pressed.connect(_request_clear_data)
	content.add_child(_clear_button)
	_clear_confirmation = _build_clear_confirmation()
	content.add_child(_clear_confirmation)


func _build_credits(body: VBoxContainer) -> void:
	var group := _group("Credits", "The usual suspects")
	body.add_child(group)
	var content := _group_content(group)
	var copy := PaperKit.type_label(
			"Meet the people, type, art, and sound behind this table.", &"body",
			Presentation.theme.ink)
	copy.name = "CreditsIntro"
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(copy)
	var credits := PaperKit.action_button("THE USUAL SUSPECTS", &"quiet")
	credits.name = "OpenCredits"
	_credits_opener = credits
	credits.pressed.connect(_open_credits)
	content.add_child(credits)


func _group(title: String, eyebrow: String) -> PanelContainer:
	var panel := PaperKit.paper_card()
	panel.name = "%sGroup" % title.replace(" ", "")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var content := panel.get_node("Content") as VBoxContainer
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	content.add_child(PaperKit.section_header(title, eyebrow))
	return panel


func _group_content(group: PanelContainer) -> VBoxContainer:
	return group.get_node("Content") as VBoxContainer


func _audio_row(bus_name: String) -> Control:
	var row := PaperKit.slider_row(bus_name, Presentation.settings.bus_level(bus_name), 0.0, 1.0,
			0.05)
	row.name = "SoundRow_%s" % bus_name
	var slider := row.get_node("Content/Controls/Slider") as HSlider
	var live := row.get_node("Content/Heading/LiveValue") as Label
	var mute := row.get_node("Content/Controls/Mute") as Button
	var reset := row.get_node("Content/Controls/Reset") as Button
	if slider == null:
		return row
	if live != null:
		live.custom_minimum_size.x = 80.0
		live.size_flags_horizontal = Control.SIZE_SHRINK_END
	slider.name = "Volume_%s" % bus_name
	slider.tooltip_text = "%s volume" % bus_name
	if mute != null:
		mute.name = "Mute_%s" % bus_name
		mute.tooltip_text = "Mute %s" % bus_name
		mute.pressed.connect(func() -> void: _set_bus_level(slider, bus_name, 0.0))
	if reset != null:
		reset.name = "Reset_%s" % bus_name
		reset.tooltip_text = "Reset %s" % bus_name
		reset.pressed.connect(func() -> void: _set_bus_level(slider, bus_name, 1.0))
	slider.value_changed.connect(func(value: float) -> void:
		Presentation.settings.set_bus_level(bus_name, value))
	_sliders[bus_name] = slider
	_slider_mute_buttons[bus_name] = mute
	_slider_reset_buttons[bus_name] = reset
	return row


func _set_bus_level(slider: HSlider, bus_name: String, value: float) -> void:
	if slider == null:
		return
	var next_value := clampf(value, slider.min_value, slider.max_value)
	var changed := not is_equal_approx(slider.value, next_value)
	slider.value = next_value
	# Range emits value_changed when an endpoint changes. Keep the equal-value path explicit
	# so a mute/reset tap remains persisted on every supported Godot build.
	if not changed:
		Presentation.settings.set_bus_level(bus_name, slider.value)


func _build_clear_confirmation() -> PanelContainer:
	var panel := PaperKit.glass_panel()
	panel.name = "ClearBetaConfirmation"
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content := panel.get_node("Content") as VBoxContainer
	var prompt := PaperKit.type_label(
			"Clear local beta data? This cannot be undone.", &"body", Feel.COL_NEWSPRINT)
	prompt.name = "Prompt"
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(prompt)
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	content.add_child(actions)
	_clear_cancel_button = PaperKit.action_button("CANCEL", &"secondary")
	_clear_cancel_button.name = "CancelClearBetaData"
	_clear_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_cancel_button.pressed.connect(_cancel_clear_data)
	actions.add_child(_clear_cancel_button)
	_clear_confirm_button = PaperKit.action_button("CLEAR NOW", &"destructive")
	_clear_confirm_button.name = "ConfirmClearBetaData"
	_clear_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear_confirm_button.pressed.connect(_confirm_clear_data)
	actions.add_child(_clear_confirm_button)
	return panel


func enabled_from_settings(id: StringName) -> bool:
	return Presentation.settings.toggle_value(id)


func _on_toggle(id: StringName, enabled: bool) -> void:
	Presentation.settings.set_toggle(id, enabled, Presentation.fx)
	var button := _toggle_buttons.get(id) as Button
	if button != null:
		_refresh_toggle(button, enabled)


func _refresh_toggle(button: Button, enabled: bool) -> void:
	if button == null:
		return
	button.text = "ON" if enabled else "OFF"
	button.set_meta("paperkit_selected", enabled)
	PaperKit.apply_state(button, &"selected" if enabled else &"normal")


func _on_telemetry_toggled(on: bool) -> void:
	var saved := Telemetry.set_enabled(on)
	if _telemetry_button != null:
		_telemetry_button.set_pressed_no_signal(Telemetry.enabled())
		_refresh_telemetry_button()
	if not saved:
		_refresh_telemetry_status("Couldn't save the beta choice. Collection is %s this session." %
				("on" if Telemetry.enabled() else "off"))
	else:
		_refresh_telemetry_status("Collection enabled." if on else "Collection off. Local data cleared.")


func _refresh_telemetry_button() -> void:
	if _telemetry_button == null:
		return
	_telemetry_button.text = "ON" if Telemetry.enabled() else "OFF"
	_telemetry_button.set_meta("paperkit_selected", Telemetry.enabled())
	PaperKit.apply_state(_telemetry_button, &"selected" if Telemetry.enabled() else &"normal")


func _on_export_telemetry() -> void:
	if not Telemetry.enabled():
		_refresh_telemetry_status("Allow beta telemetry before exporting.")
		return
	var copied := Telemetry.report_json()
	DisplayServer.clipboard_set(copied)
	_refresh_telemetry_status("Report copied. %s" %
			("File exported." if Telemetry.export_report() else "File export failed."))


func _request_clear_data() -> void:
	if _clear_confirmation == null:
		return
	_clear_button.visible = false
	_clear_confirmation.visible = true
	_clear_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	_clear_confirmation.set_meta("paperkit_active_state", &"confirmation")
	PaperKit.apply_state(_clear_confirmation, &"confirmation")
	call_deferred(&"_reveal_clear_confirmation")


func _reveal_clear_confirmation() -> void:
	if _scroll == null or _clear_confirmation == null or not _clear_confirmation.visible:
		return
	_scroll.ensure_control_visible(_clear_confirmation)
	if _clear_confirm_button != null:
		_clear_confirm_button.grab_focus()


func _cancel_clear_data() -> void:
	if _clear_confirmation == null:
		return
	_clear_confirmation.visible = false
	_clear_confirmation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_button.visible = true
	_refresh_telemetry_status()
	if _clear_button != null:
		_clear_button.grab_focus()


func _confirm_clear_data() -> void:
	var cleared := Telemetry.clear_data()
	_clear_confirmation.visible = false
	_clear_confirmation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_button.visible = true
	_refresh_telemetry_status("Local beta data cleared." if cleared else
			"Couldn't clear every beta file.")
	if _clear_button != null:
		_clear_button.grab_focus()


func _refresh_telemetry_status(message: String = "") -> void:
	if _telemetry_status == null:
		return
	_telemetry_status.text = message if not message.is_empty() else "%d local events" % Telemetry.event_count()


func _open_credits() -> void:
	if _credits != null and is_instance_valid(_credits):
		return
	_credits = CreditsSheet.new()
	_credits.name = "Credits"
	_credits.closed.connect(func() -> void:
		_credits.queue_free()
		call_deferred("_restore_credits_focus")
		_credits = null)
	add_child(_credits)


func _restore_credits_focus() -> void:
	if _credits == null and _credits_opener != null and is_instance_valid(_credits_opener) \
			and _credits_opener.is_inside_tree() and _credits_opener.is_visible_in_tree():
		_credits_opener.grab_focus()


func _on_done_pressed() -> void:
	closed.emit()


func _on_safe_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content, Vector4(54.0, 70.0, 54.0, 54.0))


func _layout_profile() -> StringName:
	var viewport := get_viewport()
	if viewport == null:
		return &"compact"
	return &"standard" if viewport.get_visible_rect().size.x >= 720.0 else &"compact"


func toggle_button(id: StringName) -> Button:
	return _toggle_buttons.get(id) as Button


func slider(bus_name: String) -> HSlider:
	return _sliders.get(bus_name) as HSlider


func telemetry_button() -> Button:
	return _telemetry_button
