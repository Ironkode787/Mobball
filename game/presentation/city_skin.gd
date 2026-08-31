class_name CitySkin
extends Resource
## Ambient matter may change by city. Reserved gameplay colors never live in this resource.

const AMBIENT_MATERIAL_ROLES: Array[StringName] = [
	&"felt", &"wood", &"wood_dark", &"wood_edge", &"brass", &"paper",
	&"aged_paper", &"cork", &"ink_glass", &"earned_neon",
]

@export var id: StringName = &"eastport"
@export var display_name := "EASTPORT"
@export var felt := Color("1E3D2F")
@export var wood := Color("21150F")
@export var wood_dark := Color("0B0908")
@export var brass := Color("C9A227")
@export var paper := Color("F2E8D5")
@export var ambient := Color("12100E")
@export var earned_neon := Color("FF2E63")
@export var aged_paper := Color("E0D3BB")
@export var cork := Color("704838")
@export var ink_glass := Color("12100E")
@export var wood_edge := Color("6D3F23")
@export_range(0.0, 2.0, 0.05) var grain_strength := 0.18
@export_range(0.0, 2.0, 0.05) var vignette_strength := 0.30
@export_range(0.0, 2.0, 0.05) var glow_strength := 0.55


static func eastport() -> CitySkin:
	return CitySkin.new()


## City skins provide ambient material color only. Gameplay state colors remain in
## PresentationTheme and Feel, so a skin cannot redefine dirty, clean, heat, or police.
func material_for(role: StringName) -> Color:
	match role:
		&"felt": return felt
		&"wood": return wood
		&"wood_dark": return wood_dark
		&"wood_edge": return wood_edge
		&"brass": return brass
		&"paper": return paper
		&"aged_paper": return aged_paper
		&"cork": return cork
		&"ink_glass": return ink_glass
		&"earned_neon": return earned_neon
		_: return Color.TRANSPARENT


func ambient_materials() -> Dictionary:
	var result: Dictionary = {}
	for role: StringName in AMBIENT_MATERIAL_ROLES:
		result[role] = material_for(role)
	return result
