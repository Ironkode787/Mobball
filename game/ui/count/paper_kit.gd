class_name PaperKit
extends RefCounted
## Paperback-noir UI primitives. Typography and controls resolve through Presentation.
##
## The M1 screens are functional, not finished: newsprint on ink, brass rules, reserved
## colors used only for what they mean. Everything is built in code so the .tscn files stay
## stubs and the layout is one source of truth.
##
## No Unicode dingbats anywhere — the default theme font has no star glyph, so ☆ is drawn
## (see `draw_star`) rather than typed.

const FONT_HUGE := 78
const FONT_TITLE := 56
const FONT_BIG := 44
const FONT_BODY := 34
const FONT_SMALL := 28

const PAD := 28.0
const RULE := 3.0


static func label(text: String, size: int = FONT_BODY, color: Color = Feel.COL_NEWSPRINT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_override("font", _font_for_label(size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A pressable slab: ink body, brass rule, newsprint type.
static func button(text: String, size: int = FONT_BIG, accent: Color = Feel.COL_BRASS) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", Presentation.theme.font_for(
			&"headline" if size >= FONT_BIG else &"ui"))
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
	b.add_theme_color_override("font_hover_color", accent)
	b.add_theme_color_override("font_pressed_color", Feel.COL_INK)
	b.add_theme_stylebox_override("normal", box(Feel.COL_INK.lightened(0.10), accent))
	b.add_theme_stylebox_override("hover", box(Feel.COL_INK.lightened(0.18), accent))
	b.add_theme_stylebox_override("pressed", box(accent, accent))
	b.add_theme_stylebox_override("disabled", box(Feel.COL_INK.lightened(0.04), accent.darkened(0.6)))
	b.custom_minimum_size = Vector2(0.0, 96.0)
	b.focus_mode = Control.FOCUS_ALL
	return b


static func _font_for_label(size: int) -> Font:
	if size >= FONT_TITLE:
		return Presentation.theme.font_for(&"headline")
	if size <= FONT_SMALL:
		return Presentation.theme.font_for(&"annotation")
	return Presentation.theme.font_for(&"body")


static func box(fill: Color, border: Color, width: float = RULE) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(int(width))
	s.set_corner_radius_all(6)
	s.content_margin_left = PAD * 0.6
	s.content_margin_right = PAD * 0.6
	s.content_margin_top = PAD * 0.35
	s.content_margin_bottom = PAD * 0.35
	return s


static func panel(fill: Color = Feel.COL_INK.lightened(0.06),
		border: Color = Feel.COL_BRASS.darkened(0.35)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(fill, border))
	return p


static func rule(color: Color = Feel.COL_BRASS.darkened(0.4), height: float = RULE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0.0, height)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0.0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## A five-point brass star, drawn because the default font has no glyph for one.
static func draw_star(on: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.44
		var a := -PI * 0.5 + float(i) * PI / 5.0
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	on.draw_colored_polygon(pts, color)


# -----------------------------------------------------------------------------
# Production primitives
#
# These constructors deliberately live beside the legacy factories.  Existing screens
# continue to call the compatibility surface above; new screens can opt into one
# canonical component API without importing a second style library.

const _INTERACTIVE_STATES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"focus", &"disabled", &"selected", &"invalid", &"confirmation",
]
const _BUTTON_NATIVE_SLOTS: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed",
	&"checked", &"checked_disabled", &"checked_hover", &"checked_pressed", &"checked_focus",
	&"checked_hover_pressed",
]
const _BUTTON_FONT_SLOTS: Array[StringName] = [
	&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
	&"font_disabled_color", &"font_hover_pressed_color",
]


static func type_label(text: String, role: StringName = &"body",
		color: Color = Color.TRANSPARENT,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var canonical_role: StringName = role if PresentationTheme.TYPE_ROLES.has(role) else &"body"
	var token: Dictionary = Presentation.theme.typography_for(canonical_role)
	var l := Label.new()
	l.name = "TypeLabel"
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", token["font"] as Font)
	l.add_theme_font_size_override("font_size", int(token["size"]))
	l.add_theme_constant_override("line_spacing", int(round(float(token["size"]) *
			(float(token["line_height"]) - 1.0))))
	l.add_theme_color_override("font_color", Presentation.theme.newsprint if color == Color.TRANSPARENT else color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.set_meta("paperkit_type_role", canonical_role)
	l.set_meta("paperkit_typography", token)
	return l


## Creates a styled, accessible action with one state vocabulary for every variant.
static func action_button(text: String = "", variant: StringName = &"primary",
		icon: String = "") -> Button:
	var canonical_variant: StringName = _action_variant(variant)
	var b := Button.new()
	b.name = "ActionButton_%s" % String(canonical_variant)
	b.text = icon if canonical_variant == &"icon_only" and not icon.is_empty() else text
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.clip_text = false
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(_touch_minimum(), _touch_minimum())
	var typography := Presentation.theme.typography_for(&"button")
	b.add_theme_font_override("font", typography["font"] as Font)
	b.add_theme_font_size_override("font_size", int(typography["size"]))
	var palette := _action_palette(canonical_variant)
	b.add_theme_color_override("font_color", palette["text"])
	b.add_theme_color_override("font_hover_color", palette["hover_text"])
	b.add_theme_color_override("font_pressed_color", palette["pressed_text"])
	b.add_theme_color_override("font_focus_color", palette["focus_text"])
	b.add_theme_color_override("font_disabled_color", palette["disabled_text"])
	b.add_theme_color_override("font_hover_pressed_color", palette["pressed_text"])
	for state: StringName in _INTERACTIVE_STATES:
		b.add_theme_stylebox_override(state, _action_state_box(canonical_variant, state))
	b.add_theme_stylebox_override("hover_pressed", _action_state_box(canonical_variant, &"pressed"))
	for checked_state: StringName in [
		&"checked", &"checked_hover", &"checked_pressed", &"checked_focus", &"checked_hover_pressed",
	]:
		b.add_theme_stylebox_override(checked_state, _action_state_box(canonical_variant, &"selected"))
	b.add_theme_stylebox_override("checked_disabled", _action_state_box(canonical_variant, &"disabled"))
	_register_state_styles(b, _BUTTON_NATIVE_SLOTS)
	var state_text_colors: Dictionary = {}
	for state: StringName in _INTERACTIVE_STATES:
		state_text_colors[state] = _action_state_text_color(canonical_variant, state)
	b.set_meta("paperkit_state_text_colors", state_text_colors)
	b.set_meta("paperkit_variant", canonical_variant)
	b.set_meta("paperkit_states", _INTERACTIVE_STATES.duplicate())
	b.set_meta("paperkit_icon", icon)
	return b


## A compact mechanical switch row. The switch remains a real focusable control.
static func toggle_row(label_text: String = "", checked: bool = false) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "ToggleRow"
	row.custom_minimum_size = Vector2(0.0, _touch_minimum())
	_apply_surface_states(row, &"control", Presentation.theme.brass)
	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	row.add_child(content)
	var label := type_label(label_text, &"body")
	label.name = "Label"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(label)
	var switch := action_button("OFF", &"secondary")
	switch.name = "Switch"
	switch.text = "ON" if checked else "OFF"
	switch.toggle_mode = true
	switch.button_pressed = checked
	apply_state(switch, &"selected" if checked else &"normal")
	switch.custom_minimum_size = Vector2(_touch_minimum(), _touch_minimum())
	switch.set_meta("paperkit_role", &"toggle")
	switch.set_meta("paperkit_selected", checked)
	switch.toggled.connect(func(value: bool) -> void:
		switch.text = "ON" if value else "OFF"
		switch.set_meta("paperkit_selected", value)
		apply_state(switch, &"selected" if value else &"normal")
		row.set_meta("paperkit_selected", value))
	content.add_child(switch)
	row.set_meta("paperkit_role", &"toggle_row")
	row.set_meta("paperkit_selected", checked)
	return row


## A token-backed slider row with a live value, mute endpoint, and reset affordance.
static func slider_row(label_text: String = "", value: float = 0.0,
		min_value: float = 0.0, max_value: float = 1.0, step: float = 0.05) -> PanelContainer:
	var row := PanelContainer.new()
	row.name = "SliderRow"
	row.custom_minimum_size = Vector2(0.0, _touch_minimum())
	_apply_surface_states(row, &"control", Presentation.theme.brass)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	row.add_child(content)
	var heading := HBoxContainer.new()
	heading.name = "Heading"
	content.add_child(heading)
	var label := type_label(label_text, &"body")
	label.name = "Label"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var live := type_label("", &"metadata", Presentation.theme.brass, HORIZONTAL_ALIGNMENT_RIGHT)
	live.name = "LiveValue"
	heading.add_child(live)
	var controls := HBoxContainer.new()
	controls.name = "Controls"
	controls.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	content.add_child(controls)
	var slider := HSlider.new()
	slider.name = "Slider"
	slider.min_value = min_value
	slider.max_value = maxf(min_value, max_value)
	slider.step = maxf(0.0, step)
	slider.value = clampf(value, slider.min_value, slider.max_value)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(_touch_minimum(), _touch_minimum())
	slider.focus_mode = Control.FOCUS_ALL
	_apply_slider_style(slider)
	live.text = _slider_value_text(slider.value, slider.min_value, slider.max_value)
	slider.value_changed.connect(func(next_value: float) -> void:
		live.text = _slider_value_text(next_value, slider.min_value, slider.max_value))
	controls.add_child(slider)
	var mute := action_button("", &"icon_only", "M")
	mute.name = "Mute"
	mute.tooltip_text = "Mute"
	controls.add_child(mute)
	var reset := action_button("", &"icon_only", "R")
	reset.name = "Reset"
	reset.tooltip_text = "Reset"
	reset.pressed.connect(func() -> void:
		slider.value = slider.max_value)
	controls.add_child(reset)
	row.set_meta("paperkit_role", &"slider_row")
	row.set_meta("paperkit_states", _INTERACTIVE_STATES.duplicate())
	return row


static func paper_card(title: String = "", body: String = "") -> PanelContainer:
	var card := _surface_container(&"card", "PaperCard")
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	card.add_child(content)
	if not title.is_empty():
		var heading := type_label(title, &"section", Presentation.theme.ink)
		heading.name = "Title"
		content.add_child(heading)
	if not body.is_empty():
		var copy := type_label(body, &"body", Presentation.theme.ink)
		copy.name = "Body"
		content.add_child(copy)
	card.set_meta("paperkit_role", &"paper_card")
	return card


static func glass_panel(title: String = "", body: String = "") -> PanelContainer:
	var panel := _surface_container(&"panel", "GlassPanel")
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	panel.add_child(content)
	if not title.is_empty():
		var heading := type_label(title, &"section", Presentation.theme.brass)
		heading.name = "Title"
		content.add_child(heading)
	if not body.is_empty():
		var copy := type_label(body, &"body")
		copy.name = "Body"
		content.add_child(copy)
	panel.set_meta("paperkit_role", &"glass_panel")
	return panel


static func receipt_row(label_text: String = "", value_text: String = "",
		annotation: String = "") -> PanelContainer:
	var row := _surface_container(&"receipt", "ReceiptRow")
	row.custom_minimum_size = Vector2(0.0, _touch_minimum())
	var content := HBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	row.add_child(content)
	var label := type_label(label_text, &"body", Presentation.theme.ink)
	label.name = "Label"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(label)
	if not annotation.is_empty():
		var note := type_label(annotation, &"metadata", Presentation.theme.ink.lightened(0.18))
		note.name = "Annotation"
		content.add_child(note)
	var value := type_label(value_text, &"primary_value", Presentation.theme.ink,
			HORIZONTAL_ALIGNMENT_RIGHT)
	value.name = "Value"
	content.add_child(value)
	row.set_meta("paperkit_role", &"receipt_row")
	return row


static func dossier_card(title: String = "", detail: String = "", status: String = "") -> PanelContainer:
	var card := _surface_container(&"card", "DossierCard")
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	card.add_child(content)
	var heading := type_label(title, &"section", Presentation.theme.ink)
	heading.name = "Title"
	content.add_child(heading)
	if not detail.is_empty():
		var copy := type_label(detail, &"body", Presentation.theme.ink)
		copy.name = "Detail"
		content.add_child(copy)
	if not status.is_empty():
		var state := type_label(status, &"metadata", Presentation.theme.brass)
		state.name = "Status"
		content.add_child(state)
	card.set_meta("paperkit_role", &"dossier_card")
	return card


static func value_window(label_text: String = "", value_text: String = "") -> PanelContainer:
	var window := _surface_container(&"receipt", "ValueWindow")
	window.custom_minimum_size = Vector2(0.0, _touch_minimum())
	var content := VBoxContainer.new()
	content.name = "Content"
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	window.add_child(content)
	var value := type_label(value_text, &"primary_value", Presentation.theme.ink,
			HORIZONTAL_ALIGNMENT_CENTER)
	value.name = "Value"
	content.add_child(value)
	var caption := type_label(label_text, &"metadata", Presentation.theme.ink,
			HORIZONTAL_ALIGNMENT_CENTER)
	caption.name = "Label"
	content.add_child(caption)
	window.set_meta("paperkit_role", &"value_window")
	return window


static func section_header(title: String = "", eyebrow: String = "") -> PanelContainer:
	var header := _surface_container(&"panel", "SectionHeader")
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	header.add_child(content)
	if not eyebrow.is_empty():
		var overline := type_label(eyebrow, &"metadata", Presentation.theme.brass)
		overline.name = "Eyebrow"
		content.add_child(overline)
	var heading := type_label(title, &"section", Presentation.theme.newsprint)
	heading.name = "Title"
	content.add_child(heading)
	header.set_meta("paperkit_role", &"section_header")
	return header


static func bottom_action_bar(primary_label: String = "", secondary_label: String = "") -> PanelContainer:
	var bar := _surface_container(&"panel", "BottomActionBar")
	bar.custom_minimum_size = Vector2(0.0, _touch_minimum())
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	bar.add_child(actions)
	if not secondary_label.is_empty():
		var secondary := action_button(secondary_label, &"secondary")
		secondary.name = "Secondary"
		secondary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(secondary)
	if not primary_label.is_empty():
		var primary := action_button(primary_label, &"primary")
		primary.name = "Primary"
		primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(primary)
	bar.set_meta("paperkit_role", &"bottom_action_bar")
	return bar


static func toast(message: String = "", kind: StringName = &"info") -> PanelContainer:
	var tone: StringName = &"confirmation" if kind == &"confirmation" else &"normal"
	var panel := _surface_container(&"overlay", "Toast")
	apply_state(panel, tone)
	var text := type_label(message, &"caption", Presentation.theme.newsprint,
			HORIZONTAL_ALIGNMENT_CENTER)
	text.name = "Message"
	panel.add_child(text)
	panel.set_meta("paperkit_role", &"toast")
	panel.set_meta("paperkit_kind", kind)
	panel.set_meta("paperkit_placement", &"safe_feedback")
	panel.set_meta("paperkit_priority", 2 if kind == &"confirmation" else 1)
	return panel


static func subtitle(speaker: String = "", message: String = "") -> PanelContainer:
	var panel := _surface_container(&"overlay", "Subtitle")
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	panel.add_child(content)
	var nameplate := type_label(speaker, &"metadata", Presentation.theme.brass)
	nameplate.name = "Speaker"
	content.add_child(nameplate)
	var text := type_label(message, &"body", Presentation.theme.newsprint)
	text.name = "Message"
	content.add_child(text)
	panel.set_meta("paperkit_role", &"subtitle")
	panel.set_meta("paperkit_placement", &"safe_subtitle")
	panel.set_meta("paperkit_priority", 0)
	return panel


## Code-native ASCII mark plus readable text keeps icon meaning available without color.
static func icon_label(icon: String = ">", text: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "IconLabel"
	row.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	var mark := type_label(icon, &"button", Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_CENTER)
	mark.name = "Icon"
	mark.custom_minimum_size = Vector2(Presentation.theme.spacing_for(&"space_32"),
			_touch_minimum())
	row.add_child(mark)
	var copy := type_label(text, &"body")
	copy.name = "Text"
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	row.custom_minimum_size = Vector2(0.0, _touch_minimum())
	row.set_meta("paperkit_role", &"icon_label")
	row.set_meta("paperkit_icon", icon)
	return row


## Applies one canonical semantic state to the native style slots of a primitive.
##
## Godot controls do not render arbitrary theme keys such as `selected` or
## `confirmation`.  Constructors register their native slots and state styles here;
## this method then swaps those native slots so the requested state is visible now.
static func apply_state(control: Control, state: StringName) -> void:
	if not is_instance_valid(control):
		return
	var canonical_state: StringName = state if _INTERACTIVE_STATES.has(state) else &"normal"
	var slots_variant: Variant = control.get_meta("paperkit_state_native_slots", null)
	var base_variant: Variant = control.get_meta("paperkit_state_base", null)
	var states_variant: Variant = control.get_meta("paperkit_state_styles", null)
	if not (slots_variant is Array and base_variant is Dictionary and states_variant is Dictionary):
		return
	var slots: Array = slots_variant
	var base: Dictionary = base_variant
	var states: Dictionary = states_variant
	if canonical_state == &"normal":
		for slot: StringName in slots:
			var normal_style: Variant = base.get(slot, null)
			if normal_style is StyleBox:
				control.add_theme_stylebox_override(slot, normal_style)
	else:
		var state_style: Variant = states.get(canonical_state, null)
		if not state_style is StyleBox:
			return
		for slot: StringName in slots:
			control.add_theme_stylebox_override(slot, state_style)
	var icon_slots_variant: Variant = control.get_meta("paperkit_state_native_icon_slots", null)
	var icon_base_variant: Variant = control.get_meta("paperkit_state_base_icons", null)
	var icon_states_variant: Variant = control.get_meta("paperkit_state_icon_styles", null)
	if icon_slots_variant is Array and icon_base_variant is Dictionary and icon_states_variant is Dictionary:
		var icon_slots: Array = icon_slots_variant
		var icon_base: Dictionary = icon_base_variant
		var icon_states: Dictionary = icon_states_variant
		if canonical_state == &"normal":
			for slot: StringName in icon_slots:
				var normal_icon: Variant = icon_base.get(slot, null)
				if normal_icon is Texture2D:
					control.add_theme_icon_override(slot, normal_icon)
		else:
			var state_icons: Variant = icon_states.get(canonical_state, null)
			if state_icons is Dictionary:
				for slot: StringName in icon_slots:
					var state_icon: Variant = state_icons.get(slot, icon_base.get(slot, null))
					if state_icon is Texture2D:
						control.add_theme_icon_override(slot, state_icon)
	_apply_action_button_text_state(control, canonical_state)
	control.set_meta("paperkit_active_state", canonical_state)


static func _register_state_styles(control: Control, native_slots: Array[StringName],
		native_icon_slots: Array[StringName] = [], icon_states: Dictionary = {}) -> void:
	var base: Dictionary = {}
	for slot: StringName in native_slots:
		base[slot] = control.get_theme_stylebox(slot)
	var states: Dictionary = {}
	for state: StringName in _INTERACTIVE_STATES:
		states[state] = control.get_theme_stylebox(state)
	var base_icons: Dictionary = {}
	for slot: StringName in native_icon_slots:
		base_icons[slot] = control.get_theme_icon(slot)
	var state_icons: Dictionary = {}
	for state: StringName in _INTERACTIVE_STATES:
		var configured: Variant = icon_states.get(state, {})
		var configured_map: Dictionary = configured if configured is Dictionary else {}
		var resolved: Dictionary = {}
		for slot: StringName in native_icon_slots:
			resolved[slot] = configured_map.get(slot, base_icons.get(slot, null))
		state_icons[state] = resolved
	control.set_meta("paperkit_state_native_slots", native_slots.duplicate())
	control.set_meta("paperkit_state_base", base)
	control.set_meta("paperkit_state_styles", states)
	control.set_meta("paperkit_state_native_icon_slots", native_icon_slots.duplicate())
	control.set_meta("paperkit_state_base_icons", base_icons)
	control.set_meta("paperkit_state_icon_styles", state_icons)


static func _action_variant(variant: StringName) -> StringName:
	return variant if [&"primary", &"secondary", &"quiet", &"destructive", &"icon_only"].has(variant) \
			else &"primary"


static func _touch_minimum() -> float:
	var touch_contract := Presentation.theme.control_for(&"touch_target")
	return maxf(96.0, float(touch_contract.get("min_height", 96.0)))


static func _action_palette(variant: StringName) -> Dictionary:
	var accent: Color = Presentation.theme.brass
	var text: Color = Presentation.theme.newsprint
	if variant == &"secondary":
		accent = Presentation.theme.brass
		text = Presentation.theme.ink
	elif variant == &"quiet":
		accent = Presentation.theme.brass
		text = Presentation.theme.brass
	elif variant == &"destructive":
		accent = Presentation.theme.neon_rose
		text = Presentation.theme.newsprint
	elif variant == &"icon_only":
		accent = Presentation.theme.brass
		text = Presentation.theme.brass
	return {
		"accent": accent,
		"text": text,
		"hover_text": accent,
		"pressed_text": Presentation.theme.ink,
		"focus_text": text,
		"disabled_text": Presentation.theme.newsprint.darkened(0.45),
	}


static func _action_state_text_color(variant: StringName, state: StringName) -> Color:
	var palette := _action_palette(variant)
	match state:
		&"normal":
			return palette["text"]
		&"hover":
			if variant == &"secondary":
				return Presentation.theme.ink
			if variant == &"destructive":
				return Presentation.theme.newsprint
			return palette["hover_text"]
		&"pressed":
			return Presentation.theme.brass if variant == &"quiet" else Presentation.theme.ink
		&"focus":
			return Presentation.theme.brass if variant in [&"quiet", &"icon_only"] else Presentation.theme.newsprint
		&"disabled":
			return palette["disabled_text"]
		&"selected":
			if variant in [&"secondary", &"icon_only"]:
				return Presentation.theme.ink
			if variant == &"quiet":
				return Presentation.theme.brass
			return Presentation.theme.newsprint
		&"invalid":
			return Presentation.theme.brass if variant in [&"quiet", &"icon_only"] else Presentation.theme.newsprint
		&"confirmation":
			return Presentation.theme.brass if variant in [&"quiet", &"icon_only"] else Presentation.theme.newsprint
	return palette["text"]


static func _apply_action_button_text_state(control: Control, state: StringName) -> void:
	if not control is Button:
		return
	var configured: Variant = control.get_meta("paperkit_state_text_colors", null)
	if not configured is Dictionary:
		return
	var colors: Dictionary = configured
	var color: Variant = colors.get(state, colors.get(&"normal", null))
	if not color is Color:
		return
	for slot: StringName in _BUTTON_FONT_SLOTS:
		control.add_theme_color_override(slot, color)


static func _action_state_box(variant: StringName, state: StringName) -> StyleBoxFlat:
	var palette := _action_palette(variant)
	var accent: Color = palette["accent"]
	var surface_role: StringName = &"control"
	var style := _state_style(surface_role, accent, state)
	if variant == &"secondary":
		if state == &"normal":
			style.bg_color = Presentation.theme.newsprint
		elif state == &"hover":
			style.bg_color = Presentation.theme.material_for(&"aged_paper")["fill"]
		elif state == &"pressed" or state == &"selected":
			style.bg_color = accent
			style.border_color = Presentation.theme.ink
	elif variant == &"quiet":
		if state == &"normal":
			style.bg_color = Color(Presentation.theme.ink, 0.0)
			style.border_color = Presentation.theme.brass.darkened(0.25)
		elif state == &"hover":
			style.bg_color = Color(Presentation.theme.ink, 0.18)
		elif state == &"pressed" or state == &"selected":
			style.bg_color = Color(Presentation.theme.brass, 0.24)
		elif state == &"confirmation":
			style.bg_color = Color(Presentation.theme.neon_teal, 0.22)
			style.border_color = Presentation.theme.neon_teal
	elif variant == &"icon_only":
		if state == &"normal":
			style.bg_color = Color(Presentation.theme.ink, 0.0)
			style.border_color = Presentation.theme.brass.darkened(0.25)
		elif state == &"hover":
			style.bg_color = Color(Presentation.theme.brass, 0.18)
		elif state == &"pressed" or state == &"selected":
			style.bg_color = Presentation.theme.brass
			style.border_color = Presentation.theme.ink
	elif variant == &"destructive":
		if state == &"normal":
			style.border_color = accent
		elif state == &"hover":
			style.bg_color = Color(accent.r, accent.g, accent.b, 0.20)
		elif state == &"confirmation":
			style.bg_color = Color(Presentation.theme.neon_teal.r, Presentation.theme.neon_teal.g,
					Presentation.theme.neon_teal.b, 0.22)
			style.border_color = Presentation.theme.neon_teal
		elif state == &"pressed" or state == &"selected":
			style.bg_color = accent
			style.border_color = accent.lightened(0.24)
	return style


static func _surface_container(surface_role: StringName, node_name: String) -> PanelContainer:
	var container := PanelContainer.new()
	container.name = node_name
	_apply_surface_states(container, surface_role, Presentation.theme.brass)
	return container


static func _apply_surface_states(control: Control, surface_role: StringName, accent: Color) -> void:
	var surface := Presentation.theme.surface_for(surface_role)
	var material_role: StringName = surface.get("material", &"ink_glass")
	var material := Presentation.theme.material_for(material_role)
	var normal := _stylebox(material.get("fill", Presentation.theme.ink),
			material.get("border", Presentation.theme.brass), float(surface.get("radius", 0.0)),
			float(surface.get("border_width", Presentation.theme.control_border_width)),
			material.get("shadow", Presentation.theme.ink),
			float(surface.get("elevation", Presentation.theme.control_elevation)))
	control.add_theme_stylebox_override("panel", normal)
	for state: StringName in _INTERACTIVE_STATES:
		control.add_theme_stylebox_override(state, _state_style(surface_role, accent, state))
	_register_state_styles(control, [&"panel"])
	control.set_meta("paperkit_surface", surface_role)
	control.set_meta("paperkit_states", _INTERACTIVE_STATES.duplicate())


static func _state_style(surface_role: StringName, accent: Color, state: StringName) -> StyleBoxFlat:
	var surface := Presentation.theme.surface_for(surface_role)
	var material_role: StringName = surface.get("material", &"ink_glass")
	var material := Presentation.theme.material_for(material_role)
	var fill: Color = material.get("fill", Presentation.theme.ink)
	var border: Color = material.get("border", Presentation.theme.brass)
	var shadow: Color = material.get("shadow", Presentation.theme.ink)
	match state:
		&"hover":
			fill = fill.lightened(0.10)
			border = accent
		&"pressed":
			fill = accent
			border = accent.lightened(0.20)
		&"focus":
			border = Presentation.theme.neon_teal
		&"disabled":
			fill = Presentation.theme.ink.darkened(0.08)
			border = Presentation.theme.brass.darkened(0.55)
		&"selected":
			fill = Color(accent.r, accent.g, accent.b, 0.24)
			border = accent
		&"invalid":
			border = Presentation.theme.neon_rose
		&"confirmation":
			fill = Color(Presentation.theme.neon_teal.r, Presentation.theme.neon_teal.g,
					Presentation.theme.neon_teal.b, 0.22)
			border = Presentation.theme.neon_teal
	return _stylebox(fill, border, float(surface.get("radius", Presentation.theme.control_radius)),
			float(surface.get("border_width", Presentation.theme.control_border_width)), shadow,
			float(surface.get("elevation", Presentation.theme.control_elevation)))


static func _stylebox(fill: Color, border: Color, radius: float, width: float, shadow: Color,
		elevation: float = -1.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(0, int(round(width))))
	style.set_corner_radius_all(maxi(0, int(round(radius))))
	style.content_margin_left = Presentation.theme.spacing_for(&"space_16")
	style.content_margin_right = Presentation.theme.spacing_for(&"space_16")
	style.content_margin_top = Presentation.theme.spacing_for(&"space_8")
	style.content_margin_bottom = Presentation.theme.spacing_for(&"space_8")
	style.shadow_color = shadow
	var resolved_elevation := elevation
	if resolved_elevation < 0.0:
		resolved_elevation = float(Presentation.theme.control_for(&"button").get("elevation", 0.0))
	style.shadow_size = maxi(0, int(round(resolved_elevation)))
	style.shadow_offset = Vector2(0.0, Presentation.theme.spacing_for(&"space_4"))
	return style


static func _apply_slider_style(slider: HSlider) -> void:
	var slider_contract := Presentation.theme.control_for(&"slider")
	var radius := float(slider_contract.get("radius", Presentation.theme.control_radius))
	var border_width := float(slider_contract.get("border_width", Presentation.theme.control_border_width))
	var elevation := float(slider_contract.get("elevation", Presentation.theme.control_elevation))
	var rail := _stylebox(Presentation.theme.ink.darkened(0.12), Presentation.theme.brass.darkened(0.35),
			radius, border_width, Presentation.theme.ink,
			elevation)
	var fill := _stylebox(Presentation.theme.brass, Presentation.theme.brass.lightened(0.20),
			radius, border_width, Presentation.theme.ink,
			elevation)
	slider.add_theme_stylebox_override("slider", rail)
	slider.add_theme_stylebox_override("grabber_area", rail)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var newsprint_material := Presentation.theme.material_for(&"newsprint")
	var brass_material := Presentation.theme.material_for(&"brass")
	var ink_glass_material := Presentation.theme.material_for(&"ink_glass")
	var normal_thumb := _slider_thumb_texture(newsprint_material["fill"], brass_material["fill"],
			ink_glass_material["shadow"], radius, border_width, elevation)
	var highlight_thumb := _slider_thumb_texture(brass_material["fill"], newsprint_material["fill"],
			ink_glass_material["shadow"], radius, border_width, elevation)
	var disabled_thumb := _slider_thumb_texture(ink_glass_material["fill"],
			brass_material["border"], ink_glass_material["shadow"], radius, border_width, elevation)
	slider.add_theme_icon_override("grabber", normal_thumb)
	slider.add_theme_icon_override("grabber_highlight", highlight_thumb)
	slider.add_theme_icon_override("grabber_disabled", disabled_thumb)
	# Slider's rail and fill are StyleBox properties; its grabber variants are Texture2D
	# properties. Keep those native maps separate so state application reaches what draws.
	var icon_states: Dictionary = {}
	icon_states[&"normal"] = {
		&"grabber": normal_thumb, &"grabber_highlight": highlight_thumb,
		&"grabber_disabled": disabled_thumb,
	}
	for state: StringName in _INTERACTIVE_STATES:
		var state_fill: Color = rail.bg_color
		var state_border: Color = rail.border_color
		if state == &"hover" or state == &"selected":
			state_fill = Presentation.theme.brass.lightened(0.08)
			state_border = Presentation.theme.brass
		elif state == &"pressed" or state == &"confirmation":
			state_fill = Presentation.theme.brass
			state_border = Presentation.theme.brass.lightened(0.20)
		elif state == &"focus":
			state_border = Presentation.theme.neon_teal
		elif state == &"disabled":
			state_fill = Presentation.theme.ink.darkened(0.08)
			state_border = Presentation.theme.brass.darkened(0.55)
		elif state == &"invalid":
			state_border = Presentation.theme.neon_rose
		slider.add_theme_stylebox_override(state, _stylebox(state_fill, state_border, radius, border_width,
				Presentation.theme.ink, elevation))
		if state != &"normal":
			var state_thumb: Texture2D = disabled_thumb if state == &"disabled" else highlight_thumb
			icon_states[state] = {
				&"grabber": state_thumb, &"grabber_highlight": state_thumb,
				&"grabber_disabled": disabled_thumb,
			}
	_register_state_styles(slider, [&"slider", &"grabber_area", &"grabber_area_highlight"],
		[&"grabber", &"grabber_highlight", &"grabber_disabled"], icon_states)
	slider.set_meta("paperkit_states", _INTERACTIVE_STATES.duplicate())


static func _slider_thumb_texture(fill: Color, border: Color, shadow: Color, radius: float,
		border_width: float, elevation: float) -> Texture2D:
	var shadow_pad := maxf(1.0, elevation)
	var core_radius := maxf(6.0, radius + maxf(1.0, border_width))
	var side := maxi(16, int(ceil(core_radius * 2.0 + shadow_pad * 2.0 +
			Presentation.theme.spacing_for(&"space_8"))))
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(side) * 0.5, float(side) * 0.5 -
			Presentation.theme.spacing_for(&"space_4") * 0.25)
	var shadow_center := center + Vector2(0.0, Presentation.theme.spacing_for(&"space_4"))
	var shadow_radius := core_radius + shadow_pad
	for y in side:
		for x in side:
			var point := Vector2(float(x) + 0.5, float(y) + 0.5)
			var shadow_distance := point.distance_to(shadow_center)
			if shadow_distance <= shadow_radius:
				var shadow_alpha := clampf(1.0 - shadow_distance / shadow_radius, 0.0, 1.0) * shadow.a
				image.set_pixel(x, y, Color(shadow.r, shadow.g, shadow.b, shadow_alpha))
			var core_distance := point.distance_to(center)
			if core_distance <= core_radius:
				var core_color := border if core_distance >= core_radius - border_width else fill
				image.set_pixel(x, y, core_color)
	return ImageTexture.create_from_image(image)


static func _slider_value_text(value: float, min_value: float, max_value: float) -> String:
	if is_zero_approx(max_value - min_value):
		return "0%"
	return "%d%%" % int(round(inverse_lerp(min_value, max_value, value) * 100.0))
