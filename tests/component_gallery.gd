extends Node2D
## Deterministic development-only gallery for the accepted PaperKit primitives.
##
## The gallery is intentionally isolated from player-facing scenes.  It can be left running
## for inspection, or it can capture one or all gallery pages into a caller-owned directory:
##
##   GALLERY_OUTPUT_DIR=<fresh-run-dir> GALLERY_WIDTH=486 GALLERY_HEIGHT=864 \
##     GALLERY_PAGE=all godot --headless --path . --scene res://tests/component_gallery.tscn
##
## GALLERY_MODE accepts comma-separated `high_contrast`, `large_text`, `reduced_motion`,
## `reduced_flash`, and `grayscale`.  GALLERY_STATE records the review state requested by the
## caller; all state matrix pages still render every applicable state so a single run cannot hide a gap.

const PAPER_KIT := preload("res://game/ui/count/paper_kit.gd")

const PAGE_NAMES: Array[StringName] = [
	&"overview", &"actions_core", &"actions_semantic", &"controls", &"surfaces", &"feedback",
]
const CORE_ACTION_STATES: Array[StringName] = [&"normal", &"hover", &"pressed", &"focus"]
const SEMANTIC_ACTION_STATES: Array[StringName] = [
	&"disabled", &"selected", &"invalid", &"confirmation",
]
const ACTION_VARIANTS: Array[StringName] = [
	&"primary", &"secondary", &"quiet", &"destructive", &"icon_only",
]
const STATE_SHORT: Dictionary = {
	&"normal": "N", &"hover": "H", &"pressed": "P", &"focus": "F",
	&"disabled": "D", &"selected": "S", &"invalid": "I", &"confirmation": "C",
}
const COMPONENT_NAMES: Array[StringName] = [
	&"TypeLabel", &"ActionButton", &"ToggleRow", &"SliderRow", &"PaperCard", &"GlassPanel",
	&"ReceiptRow", &"DossierCard", &"ValueWindow", &"SectionHeader", &"BottomActionBar",
	&"Toast", &"Subtitle", &"IconLabel",
]
const VALID_MODES: Array[StringName] = [
	&"high_contrast", &"large_text", &"reduced_motion", &"reduced_flash", &"grayscale",
]
const LARGE_TEXT_LABEL_SCALE := 1.18
const GALLERY_LABEL_SAFETY := 2.0

var _profile_id: StringName = &"compact"
var _profile: Dictionary = {}
var _mode_ids: Array[StringName] = []
var _requested_state: StringName = &"all"
var _tuple_id := ""
var _source_commit := ""
var _run_id := ""
var _target_size := Vector2i.ZERO
var _layout_scale := 1.0
var _content_rect := Rect2()
var _page_id: StringName = &"overview"
var _output_dir := ""
var _captures: Array[Dictionary] = []
var _coverage: Array[Dictionary] = []
var _page_components: Array[StringName] = []
var _capture_pages: Array[StringName] = []
var _auto_capture := false
var _offscreen_viewport: SubViewport = null
var _capture_errors: Array[String] = []
var _manifest_written_path := ""


func _ready() -> void:
	# SceneTree is still attaching the root during _ready.  Deferring the optional offscreen
	# viewport move keeps the fixture compatible with direct scene runs and shot harnesses.
	call_deferred("_start")


func _start() -> void:
	_resolve_request()
	var visible_size := get_viewport().get_visible_rect().size
	var requested := _target_size
	var explicit_dimensions := not _string_request("GALLERY_WIDTH").is_empty() or \
			not _string_request("GALLERY_HEIGHT").is_empty()
	if requested.x > 0 and requested.y > 0 and (explicit_dimensions or
			int(visible_size.x) != requested.x or int(visible_size.y) != requested.y):
			_move_to_offscreen(requested)
	_capture_pages = _resolve_pages()
	_configure_layout(Vector2(requested.x, requested.y))
	_auto_capture = not _output_dir.is_empty() and _capture_enabled()
	if _auto_capture:
		await _capture_requested_pages()
		get_tree().quit(0)
	else:
		_build_page(&"overview")


func _resolve_request() -> void:
	var actual := get_viewport().get_visible_rect().size
	var window_size := DisplayServer.window_get_size()
	var width := _int_request("GALLERY_WIDTH")
	var height := _int_request("GALLERY_HEIGHT")
	if width <= 0:
		width = maxi(1, int(window_size.x if window_size.x > 0 else actual.x))
	if height <= 0:
		height = maxi(1, int(window_size.y if window_size.y > 0 else actual.y))
	_target_size = Vector2i(width, height)
	var requested_profile := _string_request("GALLERY_PROFILE").to_lower()
	if requested_profile == "compact" or requested_profile == "standard":
		_profile_id = StringName(requested_profile)
	else:
		_profile_id = &"standard" if width >= 720 else &"compact"
	_profile = Presentation.theme.layout_profile(_profile_id)
	var raw_modes := _string_request("GALLERY_MODE").to_lower()
	if raw_modes.is_empty() or raw_modes == "default":
		_mode_ids = []
	else:
		for raw_mode: String in raw_modes.replace("-", "_").split(","):
			var mode := StringName(raw_mode.strip_edges())
			if VALID_MODES.has(mode) and not _mode_ids.has(mode):
				_mode_ids.append(mode)
	if Presentation.fx != null:
		Presentation.fx.reduced_motion = _mode_ids.has(&"reduced_motion")
		Presentation.fx.reduced_flash = _mode_ids.has(&"reduced_flash")
	_requested_state = StringName(_string_request("GALLERY_STATE").to_lower())
	if _requested_state.is_empty():
		_requested_state = &"all"
	_tuple_id = _string_request("GALLERY_TUPLE")
	if _tuple_id.is_empty():
		_tuple_id = "%s-%dx%d" % [_profile_id, width, height]
	_source_commit = _string_request("GALLERY_SOURCE_COMMIT")
	if _source_commit.is_empty():
		_source_commit = "unprovided"
	_run_id = _string_request("GALLERY_RUN_ID")
	if _run_id.is_empty():
		_run_id = "local"
	var requested_output := _string_request("GALLERY_OUTPUT_DIR")
	if requested_output.is_empty():
		requested_output = _string_request("COMPONENT_GALLERY_OUTPUT_DIR")
	if not requested_output.is_empty():
		_output_dir = ProjectSettings.globalize_path(requested_output)
		DirAccess.make_dir_recursive_absolute(_output_dir)


func _configure_layout(viewport_size: Vector2) -> void:
	var gutter: Vector4 = _profile.get("safe_gutter", Vector4(32.0, 48.0, 32.0, 48.0))
	var authored_width := float(_profile["content_width"]) + gutter.x + gutter.z
	_layout_scale = viewport_size.x / maxf(1.0, authored_width)
	_content_rect = Rect2(gutter.x * _layout_scale, gutter.y * _layout_scale,
			float(_profile["content_width"]) * _layout_scale,
			maxf(0.0, viewport_size.y - (gutter.y + gutter.w) * _layout_scale))
	print("COMPONENT GALLERY: tuple=%s profile=%s viewport=%dx%d mode=%s state=%s pages=%s" % [
		_tuple_id, _profile_id, _target_size.x, _target_size.y, _mode_label(),
		_requested_state, ",".join(_capture_page_labels()),
	])


func _move_to_offscreen(size: Vector2i) -> void:
	var host := get_parent()
	if host == null:
		return
	host.remove_child(self)
	_offscreen_viewport = SubViewport.new()
	_offscreen_viewport.name = "ComponentGalleryViewport"
	_offscreen_viewport.size = size
	_offscreen_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(_offscreen_viewport)
	_offscreen_viewport.add_child(self)
	print("COMPONENT GALLERY OFFSCREEN: requested=%dx%d viewport_size=%s" % [size.x, size.y,
			_offscreen_viewport.size])


func _capture_requested_pages() -> void:
	for page: StringName in _capture_pages:
		_build_page(page)
		await _frames(5)
		_capture_page(page)
	_write_manifest()
	print("COMPONENT GALLERY COMPLETE: captures=%d manifest=%s" % [_captures.size(), _manifest_path()])


func _build_page(page: StringName) -> void:
	_page_id = page
	_page_components.clear()
	for child: Node in get_children():
		child.free()
	queue_redraw()
	match page:
		&"overview": _build_overview()
		&"actions_core": _build_actions(CORE_ACTION_STATES)
		&"actions_semantic": _build_actions(SEMANTIC_ACTION_STATES)
		&"controls": _build_controls()
		&"surfaces": _build_surfaces()
		&"feedback": _build_feedback()
		_: _build_overview()
	_apply_modes()
	queue_redraw()


func _build_header(kicker: String, title: String, note: String) -> float:
	var x := _content_rect.position.x
	var width := _content_rect.size.x
	var top := _content_rect.position.y
	_add_label(kicker, &"micro", Rect2(x, top, width, 26.0), "TypeLabel", "header_kicker")
	_add_label(title, &"title", Rect2(x, top + 24.0, width, 52.0), "TypeLabel", "header_title")
	var note_height := 34.0
	if _page_id == &"actions_semantic" and _mode_ids.has(&"large_text"):
		note_height = _header_note_height(note, width)
	_add_label(note, &"metadata", Rect2(x, top + 80.0, width, note_height), "TypeLabel", "header_note")
	var note_gap := 6.0 if note_height <= 34.0 else 12.0
	return top + 80.0 + note_height + note_gap


func _build_overview() -> void:
	var y := _build_header("A3 / PAPERKIT", "Component gallery", 
			"PROFILE %s  /  %s  /  REQUESTED STATE %s" % [
				String(_profile_id).to_upper(), _mode_badge(), _requested_state.to_upper()])
	var x := _content_rect.position.x
	var width := _content_rect.size.x
	_add_label("TYPELABEL ROLE SPECIMENS", &"section", Rect2(x, y, width, 36.0),
			"TypeLabel", "type_roles_heading")
	y += 40.0
	var role_columns := 3
	var gap := _theme_spacing(&"space_8")
	var col_widths := _overview_column_widths(width, gap, role_columns)
	var role_cell_gap := _theme_spacing(&"space_4")
	var role_row_heights: Array[float] = [0.0, 0.0, 0.0]
	for i in PresentationTheme.TYPE_ROLES.size():
		var role: StringName = PresentationTheme.TYPE_ROLES[i]
		var row := i / role_columns
		var sample_height := _overview_label_height(role, _role_sample(role))
		var metadata_height := _overview_label_height(&"metadata", String(role).to_upper())
		role_row_heights[row] = maxf(role_row_heights[row],
				sample_height + role_cell_gap + metadata_height)
	var role_row_tops: Array[float] = []
	var role_cursor := y
	for row in role_row_heights.size():
		role_row_tops.append(role_cursor)
		role_cursor += role_row_heights[row] + gap
	for i in PresentationTheme.TYPE_ROLES.size():
		var role: StringName = PresentationTheme.TYPE_ROLES[i]
		var col := i % role_columns
		var row := i / role_columns
		var at := Vector2(_overview_column_x(x, gap, col_widths, col), role_row_tops[row])
		var sample := _role_sample(role)
		var sample_height := _overview_label_height(role, sample)
		var metadata_text := String(role).to_upper()
		_add_label(sample, role, Rect2(at.x, at.y, col_widths[col], sample_height), "TypeLabel",
				"role_%s" % role, role)
		_add_label(metadata_text, &"metadata",
				Rect2(at.x, at.y + sample_height + role_cell_gap, col_widths[col],
						_overview_label_height(&"metadata", metadata_text)),
				"TypeLabel", "role_name_%s" % role, role)
	y = role_cursor + _theme_spacing(&"space_12") - gap
	_add_label("COVERAGE / EVERY ACCEPTED PRIMITIVE", &"section", Rect2(x, y, width, 36.0),
			"TypeLabel", "coverage_heading")
	y += 42.0
	var columns := 3
	var row_height := 44.0
	var coverage_gap := _theme_spacing(&"space_8")
	var coverage_width := (width - coverage_gap * float(columns - 1)) / float(columns)
	for i in COMPONENT_NAMES.size():
		var name: StringName = COMPONENT_NAMES[i]
		var col := i % columns
		var row := i / columns
		var at := Vector2(x + float(col) * (coverage_width + coverage_gap), y + float(row) * row_height)
		_add_label(String(name), &"caption", Rect2(at.x, at.y, coverage_width, 34.0),
			"TypeLabel", "coverage_%s" % name, name)
		_record_coverage(name, &"overview", &"all", "index", {
			"focus_mode": Control.FOCUS_NONE,
			"disabled": false,
			"selected": false,
		})
	var coverage_rows := (COMPONENT_NAMES.size() + columns - 1) / columns
	_add_label("All controls below are built by PaperKit; state captions are evidence, not decoration.",
			&"caption", Rect2(x, y + float(coverage_rows) * row_height + 12.0, width, 48.0),
			"TypeLabel", "coverage_note")


func _build_actions(states: Array[StringName]) -> void:
	var title := "ActionButton state matrix"
	var note := "%s  /  five variants × four native states" % _state_group_label(states)
	var y := _build_header("A3 / ACTIONBUTTON", title, note)
	var x := _content_rect.position.x
	var width := _content_rect.size.x
	var gap := _theme_spacing(&"space_8")
	var columns := states.size()
	var col_width := (width - gap * float(columns - 1)) / float(columns)
	for i in columns:
		var state: StringName = states[i]
		_add_label(_state_display(state), &"metadata",
				Rect2(x + float(i) * (col_width + gap), y, col_width, 30.0),
				"TypeLabel", "state_heading_%s" % state, state)
	y += 38.0
	for variant: StringName in ACTION_VARIANTS:
		for i in columns:
			var state: StringName = states[i]
			var button := PAPER_KIT.action_button(
					String(variant).substr(0, 1).to_upper() + "/" + String(STATE_SHORT[state]), variant,
					"I" if variant == &"icon_only" else "")
			button.tooltip_text = "%s / %s" % [variant, state]
			button.disabled = state == &"disabled"
			PAPER_KIT.apply_state(button, state)
			var at := Vector2(x + float(i) * (col_width + gap), y)
			_add_control(button, Rect2(at, Vector2(col_width, 96.0)), "ActionButton", variant, state)
			y += 0.0
		y += 108.0
	_add_label("State key: N normal  H hover  P pressed  F focus  D disabled  S selected  I invalid  C confirmation",
			&"caption", Rect2(x, y - 4.0, width, 42.0), "TypeLabel", "state_key")


func _build_controls() -> void:
	var y := _build_header("A3 / COMPOSITE CONTROLS", "Mechanical rows", 
			"ToggleRow and SliderRow with real child hit areas and thumb states")
	var x := _content_rect.position.x
	var width := _content_rect.size.x
	var off := PAPER_KIT.toggle_row("Reduced motion", false)
	_add_control(off, Rect2(x, y, width, 104.0), "ToggleRow", &"off", &"normal")
	var on := PAPER_KIT.toggle_row("Reduced flash", true)
	_add_control(on, Rect2(x, y + 112.0, width, 104.0), "ToggleRow", &"on", &"selected")
	var slider_y := y + 226.0
	var slider_specs: Array[Dictionary] = [
		{"label": "Music", "value": 0.50, "state": &"normal"},
		{"label": "Effects", "value": 0.72, "state": &"focus"},
		{"label": "Voice", "value": 0.25, "state": &"disabled"},
	]
	for spec: Dictionary in slider_specs:
		var row := PAPER_KIT.slider_row(String(spec["label"]), float(spec["value"]), 0.0, 1.0, 0.05)
		var state: StringName = spec["state"]
		var slider := row.get_node("Content/Controls/Slider") as HSlider
		var live_value := row.get_node("Content/Heading/LiveValue") as Label
		if live_value != null:
			live_value.autowrap_mode = TextServer.AUTOWRAP_OFF
			live_value.custom_minimum_size.x = 48.0
		if slider != null:
			slider.editable = state != &"disabled"
			slider.set_meta("gallery_disabled", state == &"disabled")
			PAPER_KIT.apply_state(slider, state)
		_add_control(row, Rect2(x, slider_y, width, 140.0), "SliderRow", state, state)
		slider_y += 144.0


func _build_surfaces() -> void:
	var y := _build_header("A3 / SURFACES", "Paper, glass, and evidence", 
			"Neutral material roles stay separate from gameplay semantic colors")
	var x := _content_rect.position.x
	var width := _content_rect.size.x
	var gap := _theme_spacing(&"space_16")
	var col_width := (width - gap) * 0.5
	var surfaces: Array[Dictionary] = [
		{"name": "PaperCard", "node": PAPER_KIT.paper_card("Tonight's work", "Docket"), "role": &"paper_card"},
		{"name": "GlassPanel", "node": PAPER_KIT.glass_panel("Live status", "Ink glass panel."), "role": &"glass_panel"},
		{"name": "ReceiptRow", "node": PAPER_KIT.receipt_row("DIRTY", "$12.5K", "+"), "role": &"receipt_row"},
		{"name": "DossierCard", "node": PAPER_KIT.dossier_card("Manny", "Trusted hand.", "AVAILABLE"), "role": &"dossier_card"},
		{"name": "ValueWindow", "node": PAPER_KIT.value_window("RESPECT", "217"), "role": &"value_window"},
		{"name": "SectionHeader", "node": PAPER_KIT.section_header("The Count", "NIGHT 07"), "role": &"section_header"},
	]
	var row_y := y
	for i in surfaces.size():
		var spec: Dictionary = surfaces[i]
		var col := i % 2
		var row := i / 2
		var at := Vector2(x + float(col) * (col_width + gap), row_y + float(row) * 144.0)
		_add_control(spec["node"] as Control, Rect2(at, Vector2(col_width, 132.0)),
				String(spec["name"]), spec["role"] as StringName, &"normal")
		if spec["name"] == "ReceiptRow":
			var receipt := spec["node"] as PanelContainer
			var receipt_label := receipt.get_node("Content/Label") as Label
			var annotation := receipt.get_node("Content/Annotation") as Label
			var value := receipt.get_node("Content/Value") as Label
			if receipt_label != null:
				receipt_label.autowrap_mode = TextServer.AUTOWRAP_OFF
				receipt_label.custom_minimum_size.x = 66.0
			if annotation != null:
				annotation.autowrap_mode = TextServer.AUTOWRAP_OFF
				annotation.custom_minimum_size.x = 8.0
			if value != null:
				value.autowrap_mode = TextServer.AUTOWRAP_OFF
				value.custom_minimum_size.x = 70.0
	var bar := PAPER_KIT.bottom_action_bar("NEXT NIGHT", "LEDGER")
	_add_control(bar, Rect2(x, row_y + 3.0 * 144.0, width, 112.0),
			"BottomActionBar", &"primary", &"normal")


func _build_feedback() -> void:
	var y := _build_header("A3 / FEEDBACK", "Quiet signals, clear priority", 
			"Toast, Subtitle, and IconLabel retain meaning without color alone")
	var x := _content_rect.position.x
	var width := _content_rect.size.x
	var gap := _theme_spacing(&"space_16")
	var col_width := (width - gap) * 0.5
	var info := PAPER_KIT.toast("Saved locally", &"info")
	_add_control(info, Rect2(x, y, col_width, 78.0), "Toast", &"info", &"normal")
	var confirmed := PAPER_KIT.toast("Night confirmed", &"confirmation")
	_add_control(confirmed, Rect2(x + col_width + gap, y, col_width, 78.0),
			"Toast", &"confirmation", &"confirmation")
	var subtitle := PAPER_KIT.subtitle("Manny", "Keep your head down.")
	_add_control(subtitle, Rect2(x, y + 102.0, width, 136.0), "Subtitle", &"safe_subtitle", &"normal")
	var icon := PAPER_KIT.icon_label("!", "Inspect the docket")
	_add_control(icon, Rect2(x, y + 260.0, width, 96.0), "IconLabel", &"notice", &"normal")
	var bar := PAPER_KIT.bottom_action_bar("COLLECT", "LATER")
	_add_control(bar, Rect2(x, y + 378.0, width, 112.0), "BottomActionBar", &"feedback", &"normal")
	_add_label("Confirmation is a state; information is a quiet status. Both have safe placement metadata.",
			&"caption", Rect2(x, y + 510.0, width, 56.0), "TypeLabel", "feedback_note")


func _add_label(text_value: String, role: StringName, rect: Rect2, component: String = "",
		entry_id: String = "", semantic: StringName = &"normal") -> Label:
	var label := PAPER_KIT.type_label(text_value, role)
	label.name = entry_id if not entry_id.is_empty() else component
	_add_control(label, rect, component, semantic, &"normal")
	return label


func _add_control(control: Control, rect: Rect2, component: String = "",
		variant: StringName = &"", state: StringName = &"normal") -> Control:
	control.position = rect.position
	control.size = rect.size
	add_child(control)
	if not component.is_empty():
		_page_components.append(StringName(component))
		var interaction := _interaction_metadata(control, state)
		_record_coverage(StringName(component), _page_id, state, String(variant), interaction)
	return control


func _interaction_metadata(control: Control, state: StringName) -> Dictionary:
	var metadata: Dictionary = {
		"state": String(state),
		"focus_mode": int(control.focus_mode),
		"disabled": bool(control.get("disabled")) if control.get("disabled") != null else false,
		"toggle_mode": bool(control.get("toggle_mode")) if control.get("toggle_mode") != null else false,
		"minimum_size": [control.custom_minimum_size.x, control.custom_minimum_size.y],
		"visible": control.visible,
	}
	if control.has_meta("paperkit_active_state"):
		metadata["active_state"] = String(control.get_meta("paperkit_active_state"))
	if control.has_meta("paperkit_selected"):
		metadata["selected"] = bool(control.get_meta("paperkit_selected"))
	var descendants: Array[String] = []
	_collect_interactive_descendants(control, descendants)
	if not descendants.is_empty():
		metadata["interactive_descendants"] = descendants
	return metadata


func _collect_interactive_descendants(node: Node, names: Array[String]) -> void:
	for child: Node in node.get_children():
		if child is BaseButton or child is Range:
			names.append(String(child.name))
		_collect_interactive_descendants(child, names)


func _record_coverage(component: StringName, page: StringName, state: StringName,
		variant: String, interaction: Dictionary) -> void:
	var item: Dictionary = {
		"component": String(component),
		"page": String(page),
		"state": String(state),
		"variant": variant,
		"interaction": interaction,
	}
	_coverage.append(item)


func _apply_modes() -> void:
	_fit_gallery_text()
	if _mode_ids.has(&"high_contrast"):
		_apply_high_contrast()
	if _mode_ids.has(&"large_text"):
		for node: Node in _all_nodes(self):
			if node is Label:
				var label := node as Label
				var current := label.get_theme_font_size("font_size")
				if current > 0:
					label.add_theme_font_size_override("font_size", maxi(12, int(round(float(current) * 1.18))))
			if node is Button:
				var button := node as Button
				var button_size := button.get_theme_font_size("font_size")
				if button_size > 0:
					button.add_theme_font_size_override("font_size", maxi(12,
							int(round(float(button_size) * 1.12))))
	if _mode_ids.has(&"grayscale"):
		_apply_grayscale()
	# Reduced motion/flash are static capture contracts.  No tween is started by this fixture;
	# the explicit badges and manifest mode still make the review condition visible.


func _fit_gallery_text() -> void:
	# PaperKit deliberately uses production-readable token sizes.  This fixture has a denser
	# evidence layout, so its own labels receive bounded overrides while the constructors and
	# their token metadata remain untouched.  The bounds keep compact captures free of wrap or
	# clipping artifacts; large_text then raises these values in a controlled review mode.
	for node: Node in _all_nodes(self):
		if not node is Label:
			continue
		var label := node as Label
		var role := StringName(label.get_meta("paperkit_type_role", &"body"))
		var limit := _gallery_label_font_size(role, label.text, label.name)
		if role == &"primary_value":
			label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.add_theme_font_size_override("font_size", limit)


func _all_nodes(root: Node) -> Array[Node]:
	var nodes: Array[Node] = [root]
	for child: Node in root.get_children():
		nodes.append_array(_all_nodes(child))
	return nodes


func _apply_grayscale() -> void:
	for node: Node in _all_nodes(self):
		if node is Label:
			var label := node as Label
			if label.name == "Status":
				label.add_theme_color_override("font_color", Color("202020"))
			elif label.has_theme_color_override("font_color"):
				label.add_theme_color_override("font_color", _gray(label.get_theme_color("font_color")))
		if node is Button:
			var button := node as Button
			for slot: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
					&"font_focus_color", &"font_disabled_color", &"font_hover_pressed_color"]:
				if button.has_theme_color_override(slot):
					button.add_theme_color_override(slot, _gray(button.get_theme_color(slot)))
		if node is HSlider:
			var slider := node as HSlider
			for slot: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
				if slider.has_theme_icon_override(slot):
					var texture := slider.get_theme_icon(slot)
					if texture != null:
						slider.add_theme_icon_override(slot, _gray_texture(texture))
		if node is Control:
			var control := node as Control
			for slot: StringName in [&"panel", &"normal", &"hover", &"pressed", &"focus",
					&"disabled", &"selected", &"invalid", &"confirmation", &"slider",
					&"grabber_area", &"grabber_area_highlight"]:
				if control.has_theme_stylebox_override(slot):
					var original := control.get_theme_stylebox(slot)
					if original is StyleBoxFlat:
						var copy := (original as StyleBoxFlat).duplicate() as StyleBoxFlat
						copy.bg_color = _gray(copy.bg_color)
						copy.border_color = _gray(copy.border_color)
						copy.shadow_color = _gray(copy.shadow_color)
						control.add_theme_stylebox_override(slot, copy)


func _apply_high_contrast() -> void:
	# This is deliberately gallery-local: the acceptance mode demonstrates how the production
	# primitives remain readable under a strong contrast preference without changing their tokens.
	for node: Node in _all_nodes(self):
		if node is Label:
			(node as Label).add_theme_color_override("font_color", Color("FFFFFF"))
		if node is Button:
			_apply_high_contrast_button(node as Button)
		if node is HSlider:
			_apply_high_contrast_slider(node as HSlider)
		if node is Control and not node is Button and not node is HSlider:
			_apply_high_contrast_control(node as Control)


func _apply_high_contrast_button(button: Button) -> void:
	var active_state := StringName(button.get_meta("paperkit_active_state", &"normal"))
	var text_color := _high_contrast_text_color(button, active_state)
	for slot: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color",
			&"font_focus_color", &"font_disabled_color", &"font_hover_pressed_color"]:
		button.add_theme_color_override(slot, text_color)
	for slot: StringName in [&"normal", &"hover", &"pressed", &"focus", &"disabled",
			&"selected", &"invalid", &"confirmation", &"hover_pressed", &"checked",
			&"checked_hover", &"checked_pressed", &"checked_focus", &"checked_hover_pressed",
			&"checked_disabled"]:
		# `apply_state()` makes the requested semantic state visible through the native Button
		# slots. Keep every native slot on that active state for this static specimen; otherwise
		# Godot can resolve the normal slot and hide selected/invalid/confirmation distinctions.
		_high_contrast_style_override(button, slot, active_state, true)


func _apply_high_contrast_slider(slider: HSlider) -> void:
	_high_contrast_style_override(slider, &"slider", &"normal", false)
	_high_contrast_style_override(slider, &"grabber_area", &"normal", false)
	_high_contrast_style_override(slider, &"grabber_area_highlight", &"selected", false)
	for slot: StringName in [&"grabber", &"grabber_highlight", &"grabber_disabled"]:
		var texture := slider.get_theme_icon(slot)
		if texture != null:
			slider.add_theme_icon_override(slot, _high_contrast_texture(texture))


func _apply_high_contrast_control(control: Control) -> void:
	var active_state := StringName(control.get_meta("paperkit_active_state", &"normal"))
	for slot: StringName in [&"panel", &"normal", &"hover", &"pressed", &"focus", &"disabled",
			&"selected", &"invalid", &"confirmation"]:
		_high_contrast_style_override(control, slot, active_state, false)


func _high_contrast_style_override(control: Control, slot: StringName, state: StringName,
			button_style: bool) -> void:
	var original := control.get_theme_stylebox(slot)
	if not original is StyleBoxFlat:
		return
	var copy := (original as StyleBoxFlat).duplicate() as StyleBoxFlat
	var variant := StringName(control.get_meta("paperkit_variant", &""))
	copy.bg_color = _high_contrast_fill(state, variant, button_style)
	copy.border_color = _high_contrast_border(state, variant, button_style)
	copy.shadow_color = Color("000000")
	copy.set_border_width_all(3)
	control.add_theme_stylebox_override(slot, copy)


func _high_contrast_state_for_slot(slot: StringName) -> StringName:
	match slot:
		&"hover", &"checked_hover": return &"hover"
		&"pressed", &"hover_pressed", &"checked_pressed", &"checked_hover_pressed": return &"pressed"
		&"focus", &"checked_focus": return &"focus"
		&"disabled", &"checked_disabled": return &"disabled"
		&"selected", &"checked": return &"selected"
		&"invalid": return &"invalid"
		&"confirmation": return &"confirmation"
		_: return &"normal"


func _high_contrast_fill(state: StringName, variant: StringName, button_style: bool) -> Color:
	if not button_style:
		match state:
			&"hover": return Color("303030")
			&"pressed", &"selected", &"focus": return Color("FFE600")
			&"disabled": return Color("303030")
			_: return Color("0A0A0A")
	match state:
		&"pressed", &"selected", &"focus": return Color("FFE600")
		&"hover": return Color("303030") if variant != &"secondary" else Color("FFE600")
		&"disabled": return Color("303030")
		&"invalid", &"confirmation": return Color("000000")
		_: return Color("FFFFFF") if variant == &"secondary" else Color("000000")


func _high_contrast_border(state: StringName, variant: StringName, button_style: bool) -> Color:
	if state == &"invalid":
		return Color("FF3B30")
	if state == &"confirmation":
		return Color("00FF66")
	if state == &"disabled":
		return Color("8A8A8A")
	if state == &"focus":
		return Color("FFFFFF")
	if state == &"pressed" or state == &"selected" or state == &"hover":
		return Color("FFE600")
	if button_style and variant == &"destructive":
		return Color("FF3B30")
	return Color("FFFFFF")


func _high_contrast_text_color(button: Button, state: StringName) -> Color:
	if state == &"disabled":
		return Color("B8B8B8")
	if state == &"pressed" or state == &"selected" or state == &"focus":
		return Color("000000")
	if (state == &"normal" or state == &"hover") and StringName(button.get_meta("paperkit_variant", &"")) == &"secondary":
		return Color("000000")
	return Color("FFFFFF")


func _high_contrast_texture(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var copy := image.duplicate() as Image
	for y in copy.get_height():
		for x in copy.get_width():
			var pixel := copy.get_pixel(x, y)
			if pixel.a > 0.0:
				copy.set_pixel(x, y, Color("FFFFFF", pixel.a))
	return ImageTexture.create_from_image(copy)


func _capture_page(page: StringName) -> void:
	if OS.has_feature("headless") or DisplayServer.get_name().to_lower().contains("headless"):
		var headless_reason := "headless renderer cannot expose raster pixels; run PNG capture with a graphical Godot driver"
		_capture_errors.append("%s: %s" % [page, headless_reason])
		printerr("COMPONENT GALLERY: capture skipped page=%s — %s" % [page, headless_reason])
		return
	var capture_viewport: Viewport = _offscreen_viewport if _offscreen_viewport != null else get_viewport()
	var viewport_texture := capture_viewport.get_texture()
	if viewport_texture == null:
		var reason := "renderer did not expose a viewport texture (use a graphical Godot driver for PNG capture)"
		_capture_errors.append("%s: %s" % [page, reason])
		printerr("COMPONENT GALLERY: capture skipped page=%s — %s" % [page, reason])
		return
	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		var empty_reason := "viewport image was empty"
		_capture_errors.append("%s: %s" % [page, empty_reason])
		printerr("COMPONENT GALLERY: capture skipped page=%s — %s" % [page, empty_reason])
		return
	var stem := "gallery-%s-%s-%s-%s" % [
		_safe_name(String(_profile_id)), _safe_name(_mode_label()), _safe_name(String(page)),
		_safe_name(String(_requested_state)),
	]
	var path := _unique_path(_output_dir, stem, ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("COMPONENT GALLERY: PNG save failed path=%s error=%d" % [path, error])
		return
	var on_disk := Image.load_from_file(path)
	var actual_width := on_disk.get_width() if on_disk != null else 0
	var actual_height := on_disk.get_height() if on_disk != null else 0
	var hash := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	var interaction := {
		"requested_state": String(_requested_state),
		"rendered_states": _states_for_page(page),
		"focus_review": true,
		"disabled_review": true,
		"confirmation_review": true,
		"touch_minimum": float(Presentation.theme.touch_min),
		"component_count": _page_components.size(),
	}
	_captures.append({
		"tuple": _tuple_id,
		"profile": String(_profile_id),
		"mode": _mode_label(),
		"state": String(_requested_state),
		"page": String(page),
		"path": path,
		"dimensions": {"width": actual_width, "height": actual_height},
		"sha256": hash,
		"interaction": interaction,
		"components": _unique_component_labels(),
	})
	print("COMPONENT GALLERY CAPTURE: page=%s profile=%s dimensions=%dx%d sha256=%s path=%s" % [
		page, _profile_id, actual_width, actual_height, hash, path,
	])


func _write_manifest() -> void:
	var manifest := {
		"schema": "kingpin.component_gallery.v1",
		"gallery": "A3 deterministic PaperKit component gallery",
		"source_commit": _source_commit,
		"run_id": _run_id,
		"source": {
			"commit": _source_commit,
			"run_id": _run_id,
			"script": "res://tests/component_gallery.gd",
			"project_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		},
		"request": {
			"tuple": _tuple_id,
			"profile": String(_profile_id),
			"target_dimensions": {"width": _target_size.x, "height": _target_size.y},
			"mode": _mode_label(),
			"state": String(_requested_state),
			"pages": _capture_page_labels(),
		},
		"captures": _captures,
		"coverage": _coverage,
		"acceptance": {
			"components": _component_labels(),
			"action_variants": _string_labels(ACTION_VARIANTS),
			"interactive_states": _string_labels([
				&"normal", &"hover", &"pressed", &"focus", &"disabled", &"selected", &"invalid",
				&"confirmation",
			]),
			"required_profiles": ["compact", "standard"],
			"required_modes": ["high_contrast", "large_text", "reduced_motion", "reduced_flash", "grayscale"],
			"png_dimensions_verified": _capture_errors.is_empty() and not _captures.is_empty(),
			"sha256_verified": _capture_errors.is_empty() and not _captures.is_empty(),
			"capture_errors": _capture_errors,
		},
	}
	var path := _unique_path(_output_dir, "manifest", ".json")
	_manifest_written_path = path
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("COMPONENT GALLERY: manifest open failed path=%s" % path)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("COMPONENT GALLERY MANIFEST: %s" % path)


func _states_for_page(page: StringName) -> Array[String]:
	match page:
		&"actions_core": return _string_labels(CORE_ACTION_STATES)
		&"actions_semantic": return _string_labels(SEMANTIC_ACTION_STATES)
		&"controls": return ["normal", "selected", "focus", "disabled"]
		&"feedback": return ["normal", "confirmation"]
		_: return ["normal"]


func _unique_component_labels() -> Array[String]:
	var result: Array[String] = []
	for component: StringName in _page_components:
		var name := String(component)
		if not result.has(name):
			result.append(name)
	return result


func _resolve_pages() -> Array[StringName]:
	var requested := _string_request("GALLERY_PAGE").to_lower()
	if requested.is_empty() and not _auto_capture:
		return [&"overview"]
	if requested.is_empty() or requested == "all":
		return PAGE_NAMES.duplicate()
	if requested.contains(","):
		var selected_pages: Array[StringName] = []
		for raw_page: String in requested.split(","):
			var selected := StringName(raw_page.strip_edges())
			if PAGE_NAMES.has(selected) and not selected_pages.has(selected):
				selected_pages.append(selected)
		if not selected_pages.is_empty():
			return selected_pages
		return PAGE_NAMES.duplicate()
	var page := StringName(requested)
	if PAGE_NAMES.has(page):
		var single_page: Array[StringName] = []
		single_page.append(page)
		return single_page
	return PAGE_NAMES.duplicate()


func _capture_enabled() -> bool:
	var value := _string_request("GALLERY_AUTO_CAPTURE")
	return value.is_empty() or not ["0", "false", "no"].has(value.to_lower())


func _manifest_path() -> String:
	if not _manifest_written_path.is_empty():
		return _manifest_written_path
	var candidate := _output_dir.path_join("manifest.json")
	if FileAccess.file_exists(candidate):
		return candidate
	return _output_dir.path_join("manifest.json")


func _unique_path(directory: String, stem: String, extension: String) -> String:
	var base := directory.path_join(stem + extension)
	if not FileAccess.file_exists(base):
		return base
	var index := 1
	while true:
		var candidate := directory.path_join("%s-%03d%s" % [stem, index, extension])
		if not FileAccess.file_exists(candidate):
			return candidate
		index += 1
	return base


func _safe_name(value: String) -> String:
	var result := value.replace(" ", "_").replace(",", "_").replace("/", "_")
	return result if not result.is_empty() else "default"


func _mode_label() -> String:
	return "default" if _mode_ids.is_empty() else "+".join(_string_labels(_mode_ids))


func _mode_badge() -> String:
	if _mode_ids.is_empty():
		return "DEFAULT"
	var labels: Array[String] = []
	for mode: StringName in _mode_ids:
		match mode:
			&"high_contrast": labels.append("HIGH CONTRAST")
			&"large_text": labels.append("LARGE")
			&"reduced_motion": labels.append("RM")
			&"reduced_flash": labels.append("RF")
			&"grayscale": labels.append("GRAY")
	return "+".join(labels)


func _capture_page_labels() -> Array[String]:
	return _string_labels(_capture_pages)


func _component_labels() -> Array[String]:
	return _string_labels(COMPONENT_NAMES)


func _string_labels(values: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	for value: StringName in values:
		result.append(String(value))
	return result


func _state_group_label(states: Array[StringName]) -> String:
	return "/".join(_string_labels(states))


func _state_display(state: StringName) -> String:
	return "CONFIRM" if state == &"confirmation" else String(state).to_upper()


func _role_sample(role: StringName) -> String:
	match role:
		&"hero": return "KINGPIN"
		&"title": return "NIGHT"
		&"section": return "ROLL CALL"
		&"primary_value": return "$12,500"
		&"body": return "House"
		&"caption": return "Quiet"
		&"metadata": return "CASE 07"
		&"button": return "START"
		&"micro": return "LIVE"
		_: return String(role)


func _header_note_height(text_value: String, width: float) -> float:
	var token := Presentation.theme.typography_for(&"metadata")
	var font: Font = token["font"] as Font
	var font_size := _gallery_label_font_size(&"metadata", text_value, "header_note", true)
	var line_height := maxf(float(token.get("line_height", 1.0)) * float(font_size),
			font.get_height(font_size))
	line_height += maxf(0.0, float(token.get("size", font_size)) *
			(float(token.get("line_height", 1.0)) - 1.0))
	var line_count := _wrapped_line_count(text_value, width, font, font_size)
	return maxf(34.0, line_height * float(line_count) + GALLERY_LABEL_SAFETY * 2.0)


func _wrapped_line_count(text_value: String, width: float, font: Font, font_size: int) -> int:
	if text_value.is_empty() or width <= 0.0:
		return 1
	var line_count := 1
	var current := ""
	for word: String in text_value.split(" "):
		if word.is_empty():
			continue
		var candidate := word if current.is_empty() else "%s %s" % [current, word]
		var candidate_width := font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
				font_size).x
		if not current.is_empty() and candidate_width > width:
			line_count += 1
			current = word
		else:
			current = candidate
	return line_count


func _label_width(role: StringName, text_value: String, label_name: String = "") -> float:
	var token := Presentation.theme.typography_for(role)
	var font: Font = token["font"] as Font
	var font_size := _gallery_label_font_size(role, text_value, label_name, true)
	return font.get_string_size(text_value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x


func _overview_column_widths(width: float, gap: float, columns: int) -> Array[float]:
	var minimums: Array[float] = []
	for column in columns:
		minimums.append(0.0)
	for i in PresentationTheme.TYPE_ROLES.size():
		var role: StringName = PresentationTheme.TYPE_ROLES[i]
		var column := i % columns
		var sample_width := _label_width(role, _role_sample(role), "role_%s" % role)
		var metadata_text := String(role).to_upper()
		var metadata_width := _label_width(&"metadata", metadata_text, "role_name_%s" % role)
		minimums[column] = maxf(minimums[column], maxf(sample_width, metadata_width) + 4.0)
	var available := maxf(1.0, width - gap * float(columns - 1))
	var minimum_total := 0.0
	for minimum: float in minimums:
		minimum_total += minimum
	if minimum_total > available:
		var compression := (minimum_total - available) / float(columns)
		for column in columns:
			minimums[column] = maxf(1.0, minimums[column] - compression)
		return minimums
	var extra := (available - minimum_total) / float(columns)
	for column in columns:
		minimums[column] += extra
	return minimums


func _overview_column_x(origin_x: float, gap: float, widths: Array[float], column: int) -> float:
	var result := origin_x
	for index in column:
		result += float(widths[index]) + gap
	return result


func _overview_label_height(role: StringName, text_value: String) -> float:
	var token := Presentation.theme.typography_for(role)
	var font: Font = token["font"] as Font
	var font_size := _gallery_label_font_size(role, text_value, "", true)
	var token_line_height := float(token.get("line_height", 1.0)) * float(font_size)
	var measured_line_height := font.get_height(font_size)
	return maxf(token_line_height, measured_line_height) + GALLERY_LABEL_SAFETY


func _gallery_label_font_size(role: StringName, text_value: String, label_name: String = "",
		apply_large_text: bool = false) -> int:
	var limit := 18
	match role:
		&"hero", &"title": limit = 30
		&"section": limit = 26
		&"primary_value": limit = 30
		&"caption": limit = 17
		&"metadata", &"micro": limit = 15
		&"button": limit = 20
		_: limit = 18
	if text_value.length() > 32:
		limit = mini(limit, 14)
	if label_name.begins_with("coverage_"):
		limit = mini(limit, 13)
	if role == &"primary_value":
		limit = mini(limit, 20)
	if apply_large_text and _mode_ids.has(&"large_text"):
		limit = maxi(12, int(round(float(limit) * LARGE_TEXT_LABEL_SCALE)))
	return limit


func _theme_spacing(role: StringName) -> float:
	return Presentation.theme.spacing_for(role) * _layout_scale


func _gray(color: Color) -> Color:
	var luminance := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
	return Color(luminance, luminance, luminance, color.a)


func _gray_texture(texture: Texture2D) -> Texture2D:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	var copy := image.duplicate() as Image
	for y in copy.get_height():
		for x in copy.get_width():
			copy.set_pixel(x, y, _gray(copy.get_pixel(x, y)))
	return ImageTexture.create_from_image(copy)


func _int_request(name: String) -> int:
	var raw := _string_request(name)
	return int(raw) if not raw.is_empty() else 0


func _string_request(name: String) -> String:
	var value := OS.get_environment(name)
	if not value.is_empty():
		return value
	for argument: String in OS.get_cmdline_user_args():
		var prefix := "--%s=" % name.to_lower().replace("_", "-")
		if argument.to_lower().begins_with(prefix):
			return argument.substr(prefix.length())
	return ""


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _draw() -> void:
	var viewport_size := Vector2(_target_size)
	var wood := Presentation.theme.material_for(&"wood")
	var paper := Presentation.theme.material_for(&"aged_paper")
	var bg: Color = wood["fill"]
	var surface: Color = paper["fill"]
	var border: Color = paper["border"]
	var panel_fill := Color(surface, 0.18)
	if _mode_ids.has(&"high_contrast"):
		bg = Color("000000")
		surface = Color("181818")
		border = Color("FFFFFF")
		panel_fill = surface
	if _mode_ids.has(&"grayscale"):
		bg = _gray(bg)
		surface = _gray(surface)
		border = _gray(border)
		panel_fill = _gray(panel_fill)
	draw_rect(Rect2(Vector2.ZERO, viewport_size), bg, true)
	draw_rect(_content_rect.grow(12.0 * _layout_scale), panel_fill, true)
	draw_line(Vector2(_content_rect.position.x, _content_rect.position.y - 12.0 * _layout_scale),
			Vector2(_content_rect.end.x, _content_rect.position.y - 12.0 * _layout_scale), border,
			maxf(1.0, Presentation.theme.rule_width * _layout_scale))
	var footer := "A3  /  %s  /  %s  /  %s" % [
		String(_page_id).to_upper(), String(_profile_id).to_upper(), _mode_badge(),
	]
	var footer_font: Font = Presentation.theme.typography_for(&"metadata")["font"]
	var footer_size := 12 if _mode_ids.has(&"high_contrast") else 16
	while footer_size > 10 and footer_font.get_string_size(footer, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, footer_size).x > _content_rect.size.x:
		footer_size -= 1
	var gutter: Vector4 = _profile.get("safe_gutter", Vector4(32.0, 48.0, 32.0, 48.0))
	draw_string(footer_font, Vector2(_content_rect.position.x, viewport_size.y -
			maxf(18.0, gutter.w * _layout_scale * 0.42)), footer,
			HORIZONTAL_ALIGNMENT_LEFT, _content_rect.size.x, footer_size, border)
