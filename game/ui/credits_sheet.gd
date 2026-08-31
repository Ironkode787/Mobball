class_name CreditsSheet
extends CanvasLayer
## Player-facing license and provenance screen required by the release gate.
##
## Credits owns its complete presentation locally. The section table below is the only source
## for both the visible case file and the compatibility `credits_text()` API.

signal closed

const SECTION_DATA: Array[Dictionary] = [
	{
		"id": &"engine",
		"title": "ENGINE",
		"eyebrow": "THE MACHINE",
		"body": "Made with Godot Engine. Godot is licensed under the MIT License.\nCopyright © 2014-present Godot Engine contributors.",
		"paths": [],
	},
	{
		"id": &"type",
		"title": "TYPE",
		"eyebrow": "THE LETTERPRESS",
		"body": "Oswald, Libre Franklin, and Courier Prime are licensed under the SIL Open Font License 1.1.",
		"paths": [],
	},
	{
		"id": &"art",
		"title": "ART",
		"eyebrow": "THE SCENE OF THE CRIME",
		"body": "Original project artwork and built-in ImageGen artwork. No recognizable real-person likenesses.",
		"paths": [],
	},
	{
		"id": &"audio",
		"title": "AUDIO",
		"eyebrow": "THE SOUNDTRACK",
		"body": "Original synthesized music, effects, and muted-brass voices produced in-house.",
		"paths": [],
	},
	{
		"id": &"thanks",
		"title": "THANKS",
		"eyebrow": "THE WITNESSES",
		"body": "The closed-beta players who shook down every table, cutout, curved corner, and bad alibi.",
		"paths": [],
	},
	{
		"id": &"provenance",
		"title": "PROVENANCE & LICENSES",
		"eyebrow": "THE PAPER TRAIL",
		"body": "Source, license, and attribution records accompany the project. They remain discoverable here as supporting case-file material.",
		"paths": [
			"assets/ASSETS.md",
			"assets/fonts/OFL-Oswald.txt",
			"assets/fonts/OFL-LibreFranklin.txt",
			"assets/fonts/OFL-CourierPrime.txt",
			"assets/audio/MANIFEST.txt",
		],
	},
]

const MASTHEAD_STANDFIRST := "An original game designed and built for this project."
const BASE_SAFE_MARGINS := Vector4(54.0, 70.0, 54.0, 54.0)

var _content: MarginContainer = null
var _scroll: ScrollContainer = null
var _body: VBoxContainer = null
var _masthead: VBoxContainer = null
var _provenance: Control = null
var _back: Button = null
var _closed := false


func _ready() -> void:
	layer = 95

	var shade := ColorRect.new()
	shade.name = "CreditsShade"
	shade.color = Color(Feel.COL_INK, 1.0)
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
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var layout := VBoxContainer.new()
	layout.name = "CreditsLayout"
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	_content.add_child(layout)

	_masthead = VBoxContainer.new()
	_masthead.name = "CaseMasthead"
	_masthead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_masthead.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	layout.add_child(_masthead)
	_masthead.add_child(_type_label("KP // CASE FILE", &"metadata", Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_CENTER, "ProjectMark"))
	_masthead.add_child(_type_label("KINGPIN — A PINBALL RACKET", &"hero", Presentation.theme.brass,
			HORIZONTAL_ALIGNMENT_CENTER, "HeroTitle"))
	_masthead.add_child(_type_label("THE USUAL SUSPECTS", &"title", Presentation.theme.newsprint,
			HORIZONTAL_ALIGNMENT_CENTER, "SectionMasthead"))
	var standfirst := _type_label(MASTHEAD_STANDFIRST, &"caption",
			Presentation.theme.newsprint.darkened(0.08), HORIZONTAL_ALIGNMENT_CENTER, "Standfirst")
	_masthead.add_child(standfirst)
	layout.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.42), Presentation.theme.rule_width))

	_scroll = ScrollContainer.new()
	_scroll.name = "CreditsScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.clip_contents = true
	layout.add_child(_scroll)

	_body = VBoxContainer.new()
	_body.name = "CaseFileBody"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_body.custom_minimum_size.x = 0.0
	_body.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_24")))
	_body.set_meta("width_expanding", true)
	_scroll.add_child(_body)
	_build_sections()

	layout.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.42), Presentation.theme.rule_width))
	var footer := PaperKit.bottom_action_bar("", "BACK TO HOUSE RULES")
	footer.name = "CreditsFooter"
	footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.custom_minimum_size.y = Presentation.theme.touch_min
	_back = footer.get_node_or_null("Actions/Secondary") as Button
	if _back != null:
		_back.name = "CreditsBack"
		_back.pressed.connect(_on_back_pressed)
		PaperKit.apply_state(_back, &"focus")
	layout.add_child(footer)
	call_deferred("_focus_back")


func _build_sections() -> void:
	for section_data: Dictionary in SECTION_DATA:
		var id := String(section_data["id"])
		var section := VBoxContainer.new()
		section.name = "%sSection" % id.capitalize()
		section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
		_body.add_child(section)

		var header := PaperKit.section_header(String(section_data["title"]),
				String(section_data["eyebrow"]))
		header.name = "SectionHeader"
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		section.add_child(header)

		var card := PaperKit.paper_card()
		card.name = "PaperCard"
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var card_content := card.get_node("Content") as VBoxContainer
		card_content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
		var copy := _type_label(String(section_data["body"]), &"body", Presentation.theme.ink,
				HORIZONTAL_ALIGNMENT_LEFT, "Copy")
		card_content.add_child(copy)
		var paths: Array = section_data.get("paths", [])
		if not paths.is_empty():
			_provenance = section
			var path_text := "RECORD PATHS\n" + "\n".join(PackedStringArray(paths))
			var path_label := _type_label(path_text, &"metadata", Presentation.theme.ink.lightened(0.16),
					HORIZONTAL_ALIGNMENT_LEFT, "RecordPaths")
			card_content.add_child(path_label)
		section.add_child(card)
		section.set_meta("credits_section_id", section_data["id"])
		section.set_meta("credits_body", String(section_data["body"]))


func _type_label(text: String, role: StringName, color: Color,
		align: HorizontalAlignment, node_name: String) -> Label:
	var label := PaperKit.type_label(text, role, color, align)
	label.name = node_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 0.0
	label.clip_text = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _on_back_pressed() -> void:
	if _closed:
		return
	_closed = true
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		var focus := viewport.gui_get_focus_owner()
		if focus == self or is_ancestor_of(focus):
			viewport.gui_release_focus()
	closed.emit()


func _focus_back() -> void:
	if _back != null and is_instance_valid(_back) and _back.is_inside_tree() and _back.visible:
		_back.grab_focus()


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content, BASE_SAFE_MARGINS)


func scroll_container() -> ScrollContainer:
	return _scroll


func back_button() -> Button:
	return _back


func provenance_section() -> Control:
	return _provenance


static func credits_sections() -> Array[Dictionary]:
	return SECTION_DATA.duplicate(true)


static func credits_text() -> String:
	var lines: PackedStringArray = ["KINGPIN — A PINBALL RACKET", "", MASTHEAD_STANDFIRST, ""]
	for section_data: Dictionary in SECTION_DATA:
		lines.append(String(section_data["title"]))
		lines.append(String(section_data["body"]))
		var paths: Array = section_data.get("paths", [])
		if not paths.is_empty():
			lines.append("RECORD PATHS")
			for path: String in paths:
				lines.append(path)
		lines.append("")
	return "\n".join(lines).strip_edges()
