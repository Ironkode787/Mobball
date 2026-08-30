class_name ArtCatalog
extends Resource
## Optional semantic texture lookup. A missing texture is a valid state because every visual
## system keeps a procedural fallback during the production-art rollout.

signal missing_requested(id: StringName)

@export var fallback: Texture2D = null
var _textures: Dictionary = {}
var _missing: Dictionary = {}


func register(id: StringName, texture: Texture2D) -> void:
	if id == &"":
		return
	if texture == null:
		_textures.erase(id)
	else:
		_textures[id] = texture
	_missing.erase(id)


func unregister(id: StringName) -> void:
	_textures.erase(id)


func has(id: StringName) -> bool:
	return _textures.has(id) and _textures[id] is Texture2D


func resolve(id: StringName, local_fallback: Texture2D = null,
		report_missing: bool = true) -> Texture2D:
	if has(id):
		return _textures[id] as Texture2D
	if report_missing and id != &"" and not _missing.has(id):
		_missing[id] = true
		missing_requested.emit(id)
	return local_fallback if local_fallback != null else fallback


func missing_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: Variant in _missing.keys():
		out.append(StringName(id))
	out.sort()
	return out


func clear_missing() -> void:
	_missing.clear()
