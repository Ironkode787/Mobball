class_name PresentationTheme
extends Resource
## Semantic presentation tokens. Gameplay meaning stays stable across city skins.

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

@export var display_font: Font = null
@export var headline_font: Font = null
@export var ui_font: Font = null
@export var body_font: Font = null
@export var annotation_font: Font = null


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


static func defaults() -> PresentationTheme:
	return PresentationTheme.new()
