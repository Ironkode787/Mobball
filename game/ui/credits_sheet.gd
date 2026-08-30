class_name CreditsSheet
extends CanvasLayer
## Player-facing license and provenance screen required by the release gate.

signal closed

var _content: MarginContainer = null


func _ready() -> void:
	layer = 95
	var shade := ColorRect.new()
	shade.color = Color(Feel.COL_INK, 0.98)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_content = MarginContainer.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(func(_margins: Vector4) -> void: _apply_safe_area())
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	_content.add_child(outer)
	outer.add_child(PaperKit.label("THE USUAL SUSPECTS", PaperKit.FONT_TITLE, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var copy := PaperKit.label(credits_text(), PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.custom_minimum_size.x = 0.0
	scroll.add_child(copy)
	var done := PaperKit.button("BACK TO HOUSE RULES", PaperKit.FONT_BIG, Feel.COL_CLEAN)
	done.name = "CreditsDone"
	done.pressed.connect(func() -> void: closed.emit())
	outer.add_child(done)


static func credits_text() -> String:
	return """KINGPIN — A PINBALL RACKET

An original game designed and built for this project.

ENGINE
Made with Godot Engine. Godot is licensed under the MIT License.
Copyright © 2014-present Godot Engine contributors.

TYPE
Oswald, Libre Franklin, and Courier Prime are licensed under the SIL Open Font License 1.1.

ART
Original project artwork and built-in ImageGen artwork. No recognizable real-person likenesses.

AUDIO
Original synthesized music, effects, and muted-brass voices produced in-house.

THANKS
The closed-beta players who shook down every table, cutout, curved corner, and bad alibi.

Full asset provenance and license texts accompany the project source."""


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content, Vector4(54.0, 70.0, 54.0, 54.0))
