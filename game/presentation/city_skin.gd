class_name CitySkin
extends Resource
## Ambient matter may change by city. Reserved gameplay colors never live in this resource.

@export var id: StringName = &"eastport"
@export var display_name := "EASTPORT"
@export var felt := Color("1E3D2F")
@export var wood := Color("21150F")
@export var wood_dark := Color("0B0908")
@export var brass := Color("C9A227")
@export var paper := Color("F2E8D5")
@export var ambient := Color("12100E")
@export var earned_neon := Color("FF2E63")
@export_range(0.0, 2.0, 0.05) var grain_strength := 0.18
@export_range(0.0, 2.0, 0.05) var vignette_strength := 0.30
@export_range(0.0, 2.0, 0.05) var glow_strength := 0.55


static func eastport() -> CitySkin:
	return CitySkin.new()
