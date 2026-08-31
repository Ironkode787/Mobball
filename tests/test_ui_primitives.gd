extends RefCounted

## Narrow contract tests for the PaperKit production authority. These assertions are
## intentionally independent of PaperKit's private constructor lists.

const STATE_NAMES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"focus", &"disabled", &"selected", &"invalid", &"confirmation",
]
const ACTION_VARIANTS: Array[StringName] = [
	&"primary", &"secondary", &"quiet", &"destructive", &"icon_only",
]
const NATIVE_ACTION_STATES: Array[StringName] = [
	&"normal", &"hover", &"pressed", &"focus", &"disabled", &"hover_pressed",
	&"checked", &"checked_disabled", &"checked_hover", &"checked_pressed", &"checked_focus",
	&"checked_hover_pressed",
]
const ACTION_FONT_SLOTS: Array[StringName] = [
	&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color",
	&"font_disabled_color", &"font_hover_pressed_color",
]
const NATIVE_SLIDER_STYLE_SLOTS: Array[StringName] = [
	&"slider", &"grabber_area", &"grabber_area_highlight",
]
const NATIVE_SLIDER_ICON_SLOTS: Array[StringName] = [
	&"grabber", &"grabber_highlight", &"grabber_disabled",
]
const SURFACE_EXPECTATIONS: Array[Dictionary] = [
	{"role": &"paper_card", "surface": &"card"},
	{"role": &"glass_panel", "surface": &"panel"},
	{"role": &"receipt_row", "surface": &"receipt"},
	{"role": &"dossier_card", "surface": &"card"},
	{"role": &"value_window", "surface": &"receipt"},
	{"role": &"section_header", "surface": &"panel"},
	{"role": &"bottom_action_bar", "surface": &"panel"},
]


func run(t: TestCtx) -> void:
	_legacy_contract(t)
	_type_label_contract(t)
	_action_contract(t)
	_toggle_contract(t)
	_slider_contract(t)
	_surface_contract(t)
	_feedback_and_icon_contract(t)


func _assert_explicit_styles(t: TestCtx, control: Control, states: Array[StringName], label: String) -> void:
	for state: StringName in states:
		t.ok(control.has_theme_stylebox_override(state),
				"%s owns an explicit %s style override" % [label, state])
		var style := control.get_theme_stylebox(state)
		t.ok(style is StyleBoxFlat, "%s exposes a concrete %s state style" % [label, state])


func _assert_explicit_icons(t: TestCtx, control: Control, slots: Array[StringName], label: String) -> void:
	for slot: StringName in slots:
		t.ok(control.has_theme_icon_override(slot),
				"%s owns an explicit %s icon override" % [label, slot])
		var icon := control.get_theme_icon(slot)
		t.ok(icon is Texture2D, "%s exposes a concrete %s texture" % [label, slot])
		if icon is Texture2D:
			t.ok(icon.get_width() >= 16 and icon.get_height() >= 16,
					"%s %s texture has a useful rendered size" % [label, slot])
		t.ok(not control.has_theme_stylebox_override(slot),
				"%s %s uses its native icon property rather than a StyleBox" % [label, slot])


func _texture_center(texture: Texture2D) -> Color:
	var image := texture.get_image()
	return image.get_pixel(image.get_width() / 2, image.get_height() / 2)


func _same_rgb(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) and is_equal_approx(a.b, b.b)


func _rgb_distance_squared(a: Color, b: Color) -> float:
	return pow(a.r - b.r, 2.0) + pow(a.g - b.g, 2.0) + pow(a.b - b.b, 2.0)


func _composited_state_fill(style: StyleBoxFlat) -> Color:
	var backdrop: Color = Presentation.theme.material_for(&"ink_glass")["fill"]
	var alpha := clampf(style.bg_color.a, 0.0, 1.0)
	return Color(
		style.bg_color.r * alpha + backdrop.r * (1.0 - alpha),
		style.bg_color.g * alpha + backdrop.g * (1.0 - alpha),
		style.bg_color.b * alpha + backdrop.b * (1.0 - alpha),
		1.0)


func _expected_action_text_color(variant: StringName, state: StringName) -> Color:
	var text := Presentation.theme.newsprint
	if variant == &"secondary":
		text = Presentation.theme.ink
	elif variant == &"quiet" or variant == &"icon_only":
		text = Presentation.theme.brass
	if variant == &"destructive":
		text = Presentation.theme.newsprint
	match state:
		&"normal":
			return text
		&"hover":
			if variant == &"secondary":
				return Presentation.theme.ink
			if variant == &"destructive":
				return Presentation.theme.newsprint
			return Presentation.theme.brass
		&"pressed":
			return Presentation.theme.brass if variant == &"quiet" else Presentation.theme.ink
		&"focus":
			return Presentation.theme.brass if variant in [&"quiet", &"icon_only"] else Presentation.theme.newsprint
		&"disabled":
			return Presentation.theme.newsprint.darkened(0.45)
		&"selected":
			if variant in [&"secondary", &"icon_only"]:
				return Presentation.theme.ink
			if variant == &"quiet":
				return Presentation.theme.brass
			return Presentation.theme.newsprint
		&"invalid", &"confirmation":
			return Presentation.theme.brass if variant in [&"quiet", &"icon_only"] else Presentation.theme.newsprint
	return text


func _is_reserved_semantic_color(color: Color) -> bool:
	for role: StringName in [&"dirty", &"clean", &"heat", &"police"]:
		if _same_rgb(color, Presentation.theme.color(role)):
			return true
	return false


func _legacy_contract(t: TestCtx) -> void:
	var legacy_label := PaperKit.label("legacy")
	t.ok(legacy_label is Label, "legacy label factory remains a Label")
	t.eq(legacy_label.text, "legacy", "legacy label text remains stable")
	var legacy_button := PaperKit.button("legacy")
	t.ok(legacy_button is Button, "legacy button factory remains a Button")
	t.eq(legacy_button.text, "legacy", "legacy button text remains stable")
	t.ok(legacy_button.custom_minimum_size.y >= Presentation.theme.touch_min,
			"legacy button keeps the 96px touch minimum")
	legacy_label.free()
	legacy_button.free()


func _type_label_contract(t: TestCtx) -> void:
	var title := PaperKit.type_label("CASE FILE", &"title")
	t.eq(title.get_meta("paperkit_type_role"), &"title", "TypeLabel retains the requested canonical role")
	t.eq(title.get_theme_font_size("font_size"), int(Presentation.theme.typography_for(&"title")["size"]),
			"TypeLabel size comes from the canonical typography token")
	t.eq(title.get_theme_font("font"), Presentation.theme.typography_for(&"title")["font"],
			"TypeLabel font comes from the canonical typography token")
	t.eq(title.mouse_filter, Control.MOUSE_FILTER_IGNORE, "TypeLabel never captures input")
	var fallback := PaperKit.type_label("fallback", &"not_a_role")
	t.eq(fallback.get_meta("paperkit_type_role"), &"body", "unknown type roles fail closed to body")
	t.eq(fallback.get_theme_font_size("font_size"), int(Presentation.theme.typography_for(&"body")["size"]),
			"fallback TypeLabel uses the body token")
	t.ok(title.autowrap_mode != TextServer.AUTOWRAP_OFF, "TypeLabel has predictable wrapping")
	title.free()
	fallback.free()


func _action_contract(t: TestCtx) -> void:
	var normal_fills: Dictionary = {}
	var normal_borders: Dictionary = {}
	for variant: StringName in ACTION_VARIANTS:
		var action := PaperKit.action_button("TAKE", variant, "*")
		t.eq(action.get_meta("paperkit_variant"), variant, "%s variant is canonical" % variant)
		t.ok(action.custom_minimum_size.x >= 96.0 and action.custom_minimum_size.y >= 96.0,
				"%s has a 96px interactive hit area" % variant)
		t.eq(action.focus_mode, Control.FOCUS_ALL, "%s participates in keyboard focus" % variant)
		t.eq(action.get_theme_font("font"), Presentation.theme.typography_for(&"button")["font"],
				"%s font consumes the canonical button typography token" % variant)
		_assert_explicit_styles(t, action, NATIVE_ACTION_STATES, "%s action" % variant)
		_assert_explicit_styles(t, action, [&"selected", &"invalid", &"confirmation"],
				"%s semantic state" % variant)
		for state: StringName in STATE_NAMES:
			var state_style := action.get_theme_stylebox(state) as StyleBoxFlat
			t.ok(not _is_reserved_semantic_color(state_style.bg_color) and
					not _is_reserved_semantic_color(state_style.border_color),
					"%s %s state stays outside reserved semantic colors" % [variant, state])
			PaperKit.apply_state(action, state)
			var expected_text := _expected_action_text_color(variant, state)
			for font_slot: StringName in ACTION_FONT_SLOTS:
				t.eq(action.get_theme_color(font_slot), expected_text,
						"%s %s uses a state-aware native %s text color" % [variant, state, font_slot])
			var rendered_text: Color = action.get_theme_color(&"font_color")
			var active_style := action.get_theme_stylebox(&"normal") as StyleBoxFlat
			t.ok(_rgb_distance_squared(rendered_text, _composited_state_fill(active_style)) > 0.03,
					"%s %s keeps rendered text distinct from its state fill" % [variant, state])
		PaperKit.apply_state(action, &"normal")
		var normal := action.get_theme_stylebox(&"normal") as StyleBoxFlat
		var selected := action.get_theme_stylebox(&"selected") as StyleBoxFlat
		var expected_fill: Color = Presentation.theme.material_for(&"ink_glass")["fill"]
		if variant == &"secondary":
			expected_fill = Presentation.theme.material_for(&"newsprint")["fill"]
		elif variant == &"quiet" or variant == &"icon_only":
			expected_fill = Color(Presentation.theme.ink, 0.0)
		t.eq(normal.bg_color, expected_fill,
				"%s normal fill consumes its canonical material token" % variant)
		normal_fills[variant] = normal.bg_color
		normal_borders[variant] = normal.border_color
		t.ok(normal.shadow_size == int(round(Presentation.theme.control_for(&"button")["elevation"])),
				"%s normal style consumes button elevation token" % variant)
		t.ok(not _is_reserved_semantic_color(selected.bg_color),
				"%s selected state stays outside reserved semantic colors" % variant)
		var confirmation := action.get_theme_stylebox(&"confirmation") as StyleBoxFlat
		var pressed := action.get_theme_stylebox(&"pressed") as StyleBoxFlat
		t.ok(confirmation.bg_color != pressed.bg_color,
				"%s confirmation is distinct from pressed" % variant)
		if variant == &"primary":
			PaperKit.apply_state(action, &"confirmation")
			t.eq((action.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color, confirmation.bg_color,
					"confirmation applies to the native button normal slot")
			var invalid := action.get_theme_stylebox(&"invalid") as StyleBoxFlat
			PaperKit.apply_state(action, &"invalid")
			t.eq((action.get_theme_stylebox(&"normal") as StyleBoxFlat).border_color, invalid.border_color,
					"invalid applies to the native button normal slot")
			PaperKit.apply_state(action, &"normal")
			t.eq((action.get_theme_stylebox(&"normal") as StyleBoxFlat).bg_color, normal.bg_color,
					"normal restores the canonical button style")
		action.free()
	t.ok(normal_fills[&"primary"] != normal_fills[&"quiet"],
			"quiet action has a distinct treatment from primary")
	t.ok(normal_fills[&"secondary"] != normal_fills[&"quiet"],
			"quiet action has a distinct treatment from secondary")
	t.ok(normal_borders[&"destructive"] != normal_borders[&"primary"],
			"destructive action has a distinct semantic border")
	var icon_only := PaperKit.action_button("", &"icon_only", "M")
	t.eq(icon_only.text, "M", "icon-only action retains its code-native mark")
	icon_only.free()
	var previous_touch_min := Presentation.theme.touch_min
	Presentation.theme.touch_min = 48.0
	var protected := PaperKit.action_button("PROTECTED", &"quiet")
	t.ok(protected.custom_minimum_size.y >= 96.0,
			"interactive minimum cannot be reduced below 96 logical px")
	protected.free()
	Presentation.theme.touch_min = previous_touch_min


func _toggle_contract(t: TestCtx) -> void:
	var row := PaperKit.toggle_row("Reduced motion", true)
	t.ok(row is PanelContainer, "ToggleRow is a deliberate surfaced row")
	t.ok(row.custom_minimum_size.y >= 96.0, "ToggleRow keeps its invariant touch minimum")
	var switch := row.get_node("Content/Switch") as Button
	t.ok(switch != null, "ToggleRow contains a compact switch control")
	t.ok(switch.custom_minimum_size.x >= 96.0 and switch.custom_minimum_size.y >= 96.0,
			"ToggleRow switch keeps a 96px hit area")
	_assert_explicit_styles(t, row, [&"panel"], "ToggleRow surface")
	_assert_explicit_styles(t, switch, NATIVE_ACTION_STATES, "ToggleRow switch")
	t.ok(switch.toggle_mode and switch.button_pressed, "ToggleRow preserves initial selected state")
	t.eq(switch.text, "ON", "ToggleRow has a readable non-color state label")
	t.eq(switch.get_meta("paperkit_role"), &"toggle", "ToggleRow switch has a semantic role")
	var selected_visual := switch.get_theme_stylebox(&"normal") as StyleBoxFlat
	var selected_contract := switch.get_theme_stylebox(&"selected") as StyleBoxFlat
	t.eq(selected_visual.bg_color, selected_contract.bg_color,
			"ToggleRow applies selected styling to the native switch slots")
	var before := switch.button_pressed
	switch.button_pressed = not before
	switch.emit_signal("toggled", not before)
	t.eq(switch.text, "OFF", "ToggleRow selected state transitions deterministically")
	t.eq(switch.get_meta("paperkit_active_state"), &"normal",
			"ToggleRow clears selected styling when switched off")
	t.ok(row.has_theme_stylebox_override(&"focus"), "ToggleRow has an explicit focus style")
	row.free()


func _slider_contract(t: TestCtx) -> void:
	var row := PaperKit.slider_row("Music", 0.5, 0.0, 1.0, 0.1)
	t.ok(row is PanelContainer, "SliderRow is a surfaced row")
	var slider := row.get_node("Content/Controls/Slider") as HSlider
	t.ok(slider != null, "SliderRow contains a real slider")
	t.near(slider.value, 0.5, 0.001, "SliderRow preserves initial value")
	t.ok(slider.custom_minimum_size.y >= 96.0 and slider.custom_minimum_size.x >= 96.0,
			"SliderRow slider keeps a 96px hit area")
	_assert_explicit_styles(t, slider, NATIVE_SLIDER_STYLE_SLOTS, "SliderRow native pieces")
	_assert_explicit_icons(t, slider, NATIVE_SLIDER_ICON_SLOTS, "SliderRow thumb")
	_assert_explicit_styles(t, slider, STATE_NAMES, "SliderRow state")
	for state: StringName in STATE_NAMES:
		var state_style := slider.get_theme_stylebox(state) as StyleBoxFlat
		t.ok(not _is_reserved_semantic_color(state_style.bg_color) and
				not _is_reserved_semantic_color(state_style.border_color),
				"SliderRow %s state stays outside reserved semantic colors" % state)
	var slider_contract := Presentation.theme.control_for(&"slider")
	var rail := slider.get_theme_stylebox(&"slider") as StyleBoxFlat
	t.eq(rail.corner_radius_top_left, int(round(float(slider_contract["radius"]))),
			"SliderRow rail consumes the slider radius token")
	t.eq(rail.shadow_size, int(round(float(slider_contract["elevation"]))),
			"SliderRow rail consumes the slider elevation token")
	var normal_thumb := slider.get_theme_icon(&"grabber") as Texture2D
	var highlight_thumb := slider.get_theme_icon(&"grabber_highlight") as Texture2D
	var disabled_thumb := slider.get_theme_icon(&"grabber_disabled") as Texture2D
	if normal_thumb != null and highlight_thumb != null and disabled_thumb != null:
		t.ok(_same_rgb(_texture_center(normal_thumb),
				Presentation.theme.material_for(&"newsprint")["fill"]),
				"SliderRow normal thumb consumes the newsprint material token")
		t.ok(_same_rgb(_texture_center(highlight_thumb),
				Presentation.theme.material_for(&"brass")["fill"]),
				"SliderRow highlighted thumb consumes the brass material token")
		t.ok(_same_rgb(_texture_center(disabled_thumb),
				Presentation.theme.material_for(&"ink_glass")["fill"]),
				"SliderRow disabled thumb consumes the ink-glass material token")
		t.ok(not _same_rgb(_texture_center(normal_thumb), _texture_center(highlight_thumb)),
				"SliderRow focused thumb is visibly distinct from normal thumb")
		t.ok(not _same_rgb(_texture_center(normal_thumb), _texture_center(disabled_thumb)),
				"SliderRow disabled thumb is visibly distinct from normal thumb")
	var mute := row.get_node("Content/Controls/Mute") as Button
	var reset := row.get_node("Content/Controls/Reset") as Button
	t.ok(mute != null, "SliderRow has a mute endpoint")
	t.ok(reset != null, "SliderRow has a reset affordance")
	for endpoint: Button in [mute, reset]:
		t.ok(endpoint.custom_minimum_size.x >= 96.0 and endpoint.custom_minimum_size.y >= 96.0,
				"SliderRow endpoint keeps a 96px hit area")
		t.ok(endpoint.has_theme_stylebox_override(&"normal"),
				"SliderRow endpoint owns explicit button styling")
	var slider_normal := rail.bg_color
	var slider_confirmation := slider.get_theme_stylebox(&"confirmation") as StyleBoxFlat
	PaperKit.apply_state(slider, &"confirmation")
	t.eq((slider.get_theme_stylebox(&"slider") as StyleBoxFlat).bg_color, slider_confirmation.bg_color,
			"SliderRow confirmation applies to native rail styling")
	t.eq(slider.get_theme_icon(&"grabber"), highlight_thumb,
			"SliderRow confirmation applies to the native thumb icon")
	PaperKit.apply_state(slider, &"disabled")
	t.eq(slider.get_theme_icon(&"grabber"), disabled_thumb,
			"SliderRow disabled applies to the native thumb icon")
	PaperKit.apply_state(slider, &"normal")
	t.eq((slider.get_theme_stylebox(&"slider") as StyleBoxFlat).bg_color, slider_normal,
			"SliderRow normal restores native rail styling")
	t.eq(slider.get_theme_icon(&"grabber"), normal_thumb,
			"SliderRow normal restores the native thumb icon")
	t.eq(row.get_node("Content/Heading/LiveValue").text, "50%",
			"SliderRow exposes a deterministic live percentage")
	row.free()


func _surface_contract(t: TestCtx) -> void:
	var paper := PaperKit.paper_card("Title", "Body")
	var glass := PaperKit.glass_panel("Title", "Body")
	var receipt := PaperKit.receipt_row("DIRTY", "$100", "earned")
	var dossier := PaperKit.dossier_card("Manny", "A trusted hand", "AVAILABLE")
	var window := PaperKit.value_window("RESPECT", "217")
	var section := PaperKit.section_header("Tonight's work", "COUNT")
	var bar := PaperKit.bottom_action_bar("NEXT", "LEDGER")
	var surfaces: Array[PanelContainer] = [paper, glass, receipt, dossier, window, section, bar]
	for i in surfaces.size():
		var control := surfaces[i]
		var expectation: Dictionary = SURFACE_EXPECTATIONS[i]
		t.eq(control.get_meta("paperkit_role"), expectation["role"], "surface constructor reports its role")
		_assert_explicit_styles(t, control, [&"panel"], "%s panel" % expectation["role"])
		_assert_explicit_styles(t, control, STATE_NAMES, "%s state" % expectation["role"])
		for state: StringName in STATE_NAMES:
			var state_style := control.get_theme_stylebox(state) as StyleBoxFlat
			t.ok(not _is_reserved_semantic_color(state_style.bg_color) and
					not _is_reserved_semantic_color(state_style.border_color),
					"%s %s state stays outside reserved semantic colors" % [expectation["role"], state])
		var surface_token: Dictionary = Presentation.theme.surface_for(expectation["surface"])
		var material_token: Dictionary = Presentation.theme.material_for(surface_token["material"])
		var panel_style := control.get_theme_stylebox(&"panel") as StyleBoxFlat
		t.eq(panel_style.bg_color, material_token["fill"],
				"%s panel consumes its canonical material fill" % expectation["role"])
		t.eq(panel_style.border_color, material_token["border"],
				"%s panel consumes its canonical material border" % expectation["role"])
		t.eq(panel_style.shadow_size, int(round(float(surface_token["elevation"]))),
				"%s panel consumes its canonical surface elevation" % expectation["role"])
		var selected := control.get_theme_stylebox(&"selected") as StyleBoxFlat
		t.ok(not _is_reserved_semantic_color(selected.bg_color),
				"surface selected state stays outside reserved semantic colors")
		PaperKit.apply_state(control, &"selected")
		t.eq((control.get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color, selected.bg_color,
				"%s selected state applies to the native panel slot" % expectation["role"])
		PaperKit.apply_state(control, &"normal")
	t.eq(paper.get_node("Content/Title").text, "Title", "PaperCard title content is wired")
	t.eq(receipt.get_node("Content/Value").text, "$100", "ReceiptRow value content is wired")
	t.eq(window.get_node("Content/Value").text, "217", "ValueWindow value content is wired")
	t.eq(bar.get_node("Actions/Primary").text, "NEXT", "BottomActionBar primary content is wired")
	for action_name: StringName in [&"Primary", &"Secondary"]:
		var action := bar.get_node("Actions/%s" % action_name) as Button
		t.ok(action != null and action.custom_minimum_size.x >= 96.0 and
				action.custom_minimum_size.y >= 96.0,
				"BottomActionBar %s keeps a 96px hit area" % action_name)
	for control: PanelContainer in surfaces:
		control.free()


func _feedback_and_icon_contract(t: TestCtx) -> void:
	var info := PaperKit.toast("Saved", &"info")
	var confirmed := PaperKit.toast("Confirmed", &"confirmation")
	var caption := PaperKit.subtitle("Manny", "Keep your head down.")
	var icon := PaperKit.icon_label("!", "Inspect the docket")
	t.eq(info.get_meta("paperkit_role"), &"toast", "Toast has a distinct role")
	t.eq(confirmed.get_meta("paperkit_kind"), &"confirmation", "Toast preserves confirmation state")
	t.eq(info.get_meta("paperkit_placement"), &"safe_feedback", "Toast exposes safe feedback placement")
	t.eq(confirmed.get_meta("paperkit_priority"), 2, "confirmation Toast has elevated priority")
	_assert_explicit_styles(t, info, [&"panel"], "info Toast")
	_assert_explicit_styles(t, confirmed, [&"panel"], "confirmation Toast")
	var info_panel := info.get_theme_stylebox(&"panel") as StyleBoxFlat
	var confirmed_panel := confirmed.get_theme_stylebox(&"panel") as StyleBoxFlat
	t.ok(info_panel.bg_color != confirmed_panel.bg_color or info_panel.border_color != confirmed_panel.border_color,
			"confirmation Toast is visibly distinct from info Toast")
	t.eq(confirmed.get_meta("paperkit_active_state"), &"confirmation",
			"confirmation Toast applies its semantic state")
	t.eq(caption.get_meta("paperkit_role"), &"subtitle", "Subtitle has a distinct role")
	t.eq(caption.get_meta("paperkit_placement"), &"safe_subtitle", "Subtitle exposes quiet safe placement")
	_assert_explicit_styles(t, caption, [&"panel"], "Subtitle panel")
	t.eq(caption.get_node("Content/Speaker").text, "Manny", "Subtitle speaker is readable")
	t.eq(caption.get_node("Content/Message").text, "Keep your head down.", "Subtitle message is readable")
	t.eq(icon.get_meta("paperkit_icon"), "!", "IconLabel keeps a code-native icon mark")
	t.eq(icon.get_node("Icon").text, "!", "IconLabel renders the mark independently of color")
	t.eq(icon.get_node("Text").text, "Inspect the docket", "IconLabel renders readable text")
	info.free()
	confirmed.free()
	caption.free()
	icon.free()
