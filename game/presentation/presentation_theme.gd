class_name PresentationTheme
extends Resource
## Semantic presentation tokens. Gameplay meaning stays stable across city skins.

const FONT_OSWALD: Font = preload("res://assets/fonts/Oswald-SemiBold.ttf")
const FONT_FRANKLIN: Font = preload("res://assets/fonts/LibreFranklin-Regular.ttf")
const FONT_FRANKLIN_SEMIBOLD: Font = preload("res://assets/fonts/LibreFranklin-SemiBold.ttf")
const FONT_COURIER: Font = preload("res://assets/fonts/CourierPrime-Regular.ttf")
const FONT_COURIER_BOLD: Font = preload("res://assets/fonts/CourierPrime-Bold.ttf")

const TYPE_ROLES: Array[StringName] = [
	&"hero", &"title", &"section", &"primary_value", &"body", &"caption", &"metadata",
	&"button", &"micro",
]
const SPACING_ROLES: Array[StringName] = [
	&"space_4", &"space_8", &"space_12", &"space_16", &"space_24", &"space_32",
	&"space_40", &"space_48", &"space_64",
]
const LAYOUT_PROFILES: Array[StringName] = [&"compact", &"standard"]
const MATERIAL_ROLES: Array[StringName] = [
	&"ink_glass", &"newsprint", &"aged_paper", &"cork", &"wood", &"brass", &"felt",
]
const CONTROL_ROLES: Array[StringName] = [
	&"button", &"compact_button", &"toggle", &"slider", &"touch_target",
]
const SURFACE_ROLES: Array[StringName] = [
	&"screen", &"panel", &"card", &"receipt", &"overlay", &"control",
]
const SPACE_4: float = 4.0
const SPACE_8: float = 8.0
const SPACE_12: float = 12.0
const SPACE_16: float = 16.0
const SPACE_24: float = 24.0
const SPACE_32: float = 32.0
const SPACE_40: float = 40.0
const SPACE_48: float = 48.0
const SPACE_64: float = 64.0

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

# Semantic roles that did not have a one-to-one legacy export receive their own
# adjustable values. Existing size_* exports above remain the compatibility surface.
@export var size_section := 38
@export var size_primary_value := 44
@export var size_caption := 24
@export var size_metadata := 22
@export var size_button := 28
@export var size_micro := 20

# The semantic scale is immutable and independent of legacy spacing exports. The legacy
# fields above remain available with their authored values for serialized themes/callers.

@export var compact_safe_gutter := Vector4(32.0, 48.0, 32.0, 48.0)
@export var standard_safe_gutter := Vector4(56.0, 72.0, 56.0, 72.0)
@export var compact_content_width := 422.0
@export var standard_content_width := 968.0

@export var control_radius := 14.0
@export var control_border_width := 2.0
@export var control_elevation := 2.0
@export var panel_radius := 18.0
@export var panel_border_width := 2.0
@export var overlay_opacity := 0.92


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
		&"ui": return size_body
		&"annotation_bold": return size_body
		_: pass
	match role:
		&"hero": return size_display
		&"title": return size_title
		&"section": return size_section
		&"primary_value": return size_primary_value
		&"caption": return size_caption
		&"metadata": return size_metadata
		&"button": return size_button
		&"micro": return size_micro
		_: return size_body


## Returns the complete metadata for one of the nine canonical semantic type roles.
## `line_height` is a multiplier, `tracking` is logical pixels, and `max_width` is pixels.
func typography_for(role: StringName) -> Dictionary:
	match role:
		&"hero": return _type_token(role, 1.00, 0.0, 900.0, false)
		&"title": return _type_token(role, 1.02, 0.0, 720.0, false)
		&"section": return _type_token(role, 1.05, 0.25, 600.0, false)
		&"primary_value": return _type_token(role, 1.00, 0.0, 520.0, true)
		&"body": return _type_token(role, 1.35, 0.0, 560.0, false)
		&"caption": return _type_token(role, 1.30, 0.15, 480.0, false)
		&"metadata": return _type_token(role, 1.20, 0.50, 420.0, true)
		&"button": return _type_token(role, 1.00, 0.25, 420.0, false)
		&"micro": return _type_token(role, 1.15, 0.50, 360.0, false)
		_: return _type_token(&"body", 1.35, 0.0, 560.0, false)


## The semantic rhythm intentionally starts at 4 and then advances in 4/8-point steps.
func spacing_for(role: StringName) -> float:
	match role:
		&"space_4": return SPACE_4
		&"space_8": return SPACE_8
		&"space_12": return SPACE_12
		&"space_16": return SPACE_16
		&"space_24": return SPACE_24
		&"space_32": return SPACE_32
		&"space_40": return SPACE_40
		&"space_48": return SPACE_48
		&"space_64": return SPACE_64
		_: return 0.0


## Returns all canonical 4/8 spacing values keyed by `SPACING_ROLES`.
func spacing_tokens() -> Dictionary:
	var result: Dictionary = {}
	for role: StringName in SPACING_ROLES:
		result[role] = spacing_for(role)
	return result


func layout_profile(profile: StringName) -> Dictionary:
	var canonical := &"standard" if profile == &"standard" else &"compact"
	if canonical == &"compact":
		return {
			"id": canonical,
			"min_width": 0.0,
			"max_width": 719.0,
			"safe_gutter": compact_safe_gutter,
			"content_width": compact_content_width,
			"control_height": touch_min,
			"footer_height": 112.0,
		}
	return {
		"id": canonical,
		"min_width": 720.0,
		"max_width": 4096.0,
		"safe_gutter": standard_safe_gutter,
		"content_width": standard_content_width,
		"control_height": touch_min,
		"footer_height": 128.0,
	}


func layout_profiles() -> Dictionary:
	var result: Dictionary = {}
	for profile: StringName in LAYOUT_PROFILES:
		result[profile] = layout_profile(profile)
	return result

## Returns one neutral material contract. Gameplay-state colors are not material roles.
func material_for(role: StringName) -> Dictionary:
	match role:
		&"ink_glass": return {
			"fill": Color(ink.r, ink.g, ink.b, overlay_opacity),
			"border": Color(brass.r, brass.g, brass.b, 0.76),
			"shadow": Color(ink.r, ink.g, ink.b, 0.48),
			"opacity": overlay_opacity,
		}
		&"newsprint": return {
			"fill": newsprint,
			"border": Color(ink.r, ink.g, ink.b, 0.22),
			"shadow": Color(ink.r, ink.g, ink.b, 0.20),
			"opacity": 1.0,
		}
		&"aged_paper": return {
			"fill": newsprint.darkened(0.08),
			"border": Color(brass.r, brass.g, brass.b, 0.56),
			"shadow": Color(ink.r, ink.g, ink.b, 0.26),
			"opacity": 1.0,
		}
		&"cork": return {
			"fill": Color("704838"),
			"border": Color("9B6A48"),
			"shadow": Color(ink.r, ink.g, ink.b, 0.42),
			"opacity": 1.0,
		}
		&"wood": return {
			"fill": Color("21150F"),
			"border": Color("6D3F23"),
			"shadow": Color(ink.r, ink.g, ink.b, 0.52),
			"opacity": 1.0,
		}
		&"brass": return {
			"fill": brass,
			"border": Color("F0D77A"),
			"shadow": Color(ink.r, ink.g, ink.b, 0.32),
			"opacity": 1.0,
		}
		&"felt": return {
			"fill": felt,
			"border": Color("35674F"),
			"shadow": Color(ink.r, ink.g, ink.b, 0.40),
			"opacity": 1.0,
		}
		_: return {}


func material_tokens() -> Dictionary:
	var result: Dictionary = {}
	for role: StringName in MATERIAL_ROLES:
		result[role] = material_for(role)
	return result

## Returns one control contract. `min_height` preserves the legacy touch minimum.
func control_for(role: StringName) -> Dictionary:
	var height := touch_min
	var radius := control_radius
	var padding := Vector4(SPACE_16, SPACE_16, SPACE_16, SPACE_16)
	match role:
		&"compact_button":
			height = touch_min
			radius = 12.0
			padding = Vector4(SPACE_8, SPACE_8, SPACE_8, SPACE_8)
		&"toggle":
			height = touch_min
			radius = 20.0
		&"slider":
			height = touch_min
			radius = 10.0
		&"touch_target":
			height = touch_min
			radius = control_radius
	return {
		"id": role if CONTROL_ROLES.has(role) else &"button",
		"min_height": height,
		"radius": radius,
		"border_width": control_border_width,
		"elevation": control_elevation,
		"padding": padding,
	}


func control_tokens() -> Dictionary:
	var result: Dictionary = {}
	for role: StringName in CONTROL_ROLES:
		result[role] = control_for(role)
	return result

## Returns one surface contract that references a canonical material role.
func surface_for(role: StringName) -> Dictionary:
	match role:
		&"screen": return {"material": &"ink_glass", "radius": 0.0,
			"border_width": 0.0, "elevation": 0.0, "opacity": overlay_opacity}
		&"panel": return {"material": &"ink_glass", "radius": panel_radius,
			"border_width": panel_border_width, "elevation": 2.0, "opacity": overlay_opacity}
		&"card": return {"material": &"aged_paper", "radius": panel_radius,
			"border_width": panel_border_width, "elevation": 3.0, "opacity": 1.0}
		&"receipt": return {"material": &"newsprint", "radius": 8.0,
			"border_width": 1.0, "elevation": 1.0, "opacity": 1.0}
		&"overlay": return {"material": &"ink_glass", "radius": panel_radius,
			"border_width": panel_border_width, "elevation": 4.0, "opacity": overlay_opacity}
		&"control": return {"material": &"ink_glass", "radius": control_radius,
			"border_width": control_border_width, "elevation": control_elevation,
			"opacity": overlay_opacity}
		_: return {}


func surface_tokens() -> Dictionary:
	var result: Dictionary = {}
	for role: StringName in SURFACE_ROLES:
		result[role] = surface_for(role)
	return result

func _type_token(role: StringName, line_height: float, tracking: float,
		max_width: float, tabular_numbers: bool) -> Dictionary:
	return {
		"role": role,
		"font": _semantic_font_for(role),
		"size": size_for(role),
		"line_height": line_height,
		"tracking": tracking,
		"max_width": max_width,
		"tabular_numbers": tabular_numbers,
	}


func _semantic_font_for(role: StringName) -> Font:
	match role:
		&"hero", &"primary_value": return display_font
		&"title", &"section": return headline_font
		&"body", &"caption": return body_font
		&"metadata", &"micro": return annotation_font
		&"button": return ui_font
		_: return body_font


static func defaults() -> PresentationTheme:
	return PresentationTheme.new()
