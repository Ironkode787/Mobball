class_name PresentationTheme
extends Resource
## Semantic presentation tokens. Gameplay meaning stays stable across city skins.

const FONT_OSWALD: Font = preload("res://assets/fonts/Oswald-SemiBold.ttf")
const FONT_FRANKLIN: Font = preload("res://assets/fonts/LibreFranklin-Regular.ttf")
const FONT_FRANKLIN_SEMIBOLD: Font = preload("res://assets/fonts/LibreFranklin-SemiBold.ttf")
const FONT_COURIER: Font = preload("res://assets/fonts/CourierPrime-Regular.ttf")
const FONT_COURIER_BOLD: Font = preload("res://assets/fonts/CourierPrime-Bold.ttf")

@export var ink := Color("12100E")
@export var newsprint := Color("F2E8D5")
@export var felt := Color("1E3D2F")
@export var brass := Color("C9A227")
@export var dirty := Color("E23D3D")
@export var clean := Color("3FBF6F")
@export var heat := Color("FF7A2E")
@export var police := Color("3A8DFF")
@export var neon_rose := Color("FF2E63")
@export var neon_teal := Color("2EE6D6")
@export var violet := Color("8C4DFF")

@export var space_xs := 8.0
@export var space_sm := 14.0
@export var space_md := 28.0
@export var space_lg := 48.0
@export var touch_min := 96.0
@export var rule_width := 3.0

@export var display_font: Font = FONT_OSWALD
@export var headline_font: Font = FONT_OSWALD
@export var ui_font: Font = FONT_FRANKLIN_SEMIBOLD
@export var body_font: Font = FONT_FRANKLIN
@export var annotation_font: Font = FONT_COURIER

@export var size_display := 78
@export var size_headline := 56
@export var size_title := 44
@export var size_body := 34
@export var size_annotation := 28


func color(role: StringName) -> Color:
	match role:
		&"ink": return ink
		&"newsprint": return newsprint
		&"felt": return felt
		&"brass": return brass
		&"dirty": return dirty
		&"clean": return clean
		&"heat": return heat
		&"police": return police
		&"neon_rose": return neon_rose
		&"neon_teal": return neon_teal
		&"violet": return violet
		_: return Color.TRANSPARENT


func reserved_colors() -> Dictionary:
	return {&"dirty": dirty, &"clean": clean, &"heat": heat, &"police": police}


func font_for(role: StringName) -> Font:
	match role:
		&"display": return display_font
		&"headline": return headline_font
		&"ui": return ui_font
		&"body": return body_font
		&"annotation": return annotation_font
		&"annotation_bold": return FONT_COURIER_BOLD
		_: return body_font


func size_for(role: StringName) -> int:
	match role:
		&"display": return size_display
		&"headline": return size_headline
		&"title": return size_title
		&"body": return size_body
		&"annotation": return size_annotation
		_: return size_body


static func defaults() -> PresentationTheme:
	return PresentationTheme.new()
