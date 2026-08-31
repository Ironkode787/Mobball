extends Node2D
## Evidence-only C2 vocabulary specimen. It draws semantic marks, lamps, and feedback levels
## without instantiating table hardware or touching gameplay state.

const MODES: Array[StringName] = [
	&"color", &"grayscale", &"reduced_flash", &"reduced_motion", &"haptics_off", &"subtitles_off",
	&"subtitles_on",
]
const PROFILES: Array[Dictionary] = [
	{"id": &"compact", "size": Vector2i(486, 864), "safe": Vector4(22.0, 48.0, 22.0, 48.0)},
	{"id": &"standard", "size": Vector2i(1080, 1920), "safe": Vector4(48.0, 64.0, 48.0, 64.0)},
	{"id": &"narrow", "size": Vector2i(720, 1280), "safe": Vector4(34.0, 54.0, 34.0, 54.0)},
	{"id": &"extra_tall", "size": Vector2i(1080, 2400), "safe": Vector4(48.0, 64.0, 48.0, 80.0)},
]

var _mode: StringName = &"color"
var _profile: StringName = &"compact"
var _safe_margins := Vector4(22.0, 48.0, 22.0, 48.0)
var _scale := 1.0
var _origin := Vector2.ZERO
var _output_dir := ""
var _captures: Array[Dictionary] = []
var _host: Node = null


func _ready() -> void:
	_host = get_parent()
	_output_dir = OS.get_environment("C2_OUTPUT_DIR")
	if OS.get_environment("C2_BATCH") == "1" and not _output_dir.is_empty():
		await get_tree().process_frame
		await _capture_batch()
		get_tree().quit(0)
		return
	_configure(get_viewport_rect().size, _safe_margins)
	queue_redraw()


func _capture_batch() -> void:
	DirAccess.make_dir_recursive_absolute(_output_dir)
	for profile: Dictionary in PROFILES:
		var id: StringName = profile["id"]
		var dimensions: Vector2i = profile["size"]
		var safe: Vector4 = profile["safe"]
		for mode: StringName in MODES:
			await _capture_variant(id, dimensions, safe, mode)
	_write_manifest()


func _capture_variant(profile: StringName, dimensions: Vector2i, safe: Vector4,
		mode: StringName) -> void:
	_profile = profile
	_mode = mode
	_safe_margins = safe
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_host.remove_child(self)
	_host.add_child(viewport)
	viewport.add_child(self)
	_configure(Vector2(dimensions), safe)
	queue_redraw()
	for _i in 8:
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	var stem := "c2-%s-%s" % [String(profile), String(mode)]
	var path := _output_dir.path_join(stem + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_error("C2 SPECIMEN: PNG save failed path=%s error=%d" % [path, error])
	else:
		var actual := Image.load_from_file(path)
		var actual_size := Vector2i(actual.get_width(), actual.get_height()) if actual != null else Vector2i.ZERO
		_captures.append({
			"unit": "C2",
			"profile": String(profile),
			"mode": String(mode),
			"state_tokens": ["idle", "armed", "active", "completed", "disabled", "danger"],
			"lamp_channels": ["ambient_attract", "current_objective", "recent_hit", "mode_start", "jackpot", "cooldown"],
			"feedback_levels": ["micro_hit", "reward", "consequence", "ceremony"],
			"requested_physical_size": {"width": dimensions.x, "height": dimensions.y},
			"actual_physical_size": {
				"width": DisplayServer.window_get_size().x,
				"height": DisplayServer.window_get_size().y,
			},
			"logical_viewport": {"width": dimensions.x, "height": dimensions.y},
			"safe_margins": {"left": safe.x, "top": safe.y, "right": safe.z, "bottom": safe.w},
			"corner_guard": 48.0,
			"interaction": "draw-only specimen; no gameplay or hardware interaction",
			"path": path,
			"dimensions": {"width": actual_size.x, "height": actual_size.y},
			"sha256": FileAccess.get_sha256(path),
		})
	viewport.remove_child(self)
	_host.add_child(self)
	viewport.queue_free()
	await get_tree().process_frame


func _configure(viewport_size: Vector2, safe: Vector4) -> void:
	var design := Vector2(960.0, 1600.0)
	_scale = minf(viewport_size.x / design.x, viewport_size.y / design.y)
	_origin = (viewport_size - design * _scale) * 0.5
	_safe_margins = safe


func _draw() -> void:
	var viewport_size := get_viewport_rect().size
	var paper := _color(Presentation.theme.material_for(&"newsprint")["fill"])
	var ink := _color(Presentation.theme.ink)
	var brass := _color(Presentation.theme.brass)
	var card := _color(Presentation.theme.material_for(&"aged_paper")["fill"])
	draw_rect(Rect2(Vector2.ZERO, viewport_size), paper, true)
	draw_rect(Rect2(_p(Vector2.ZERO), _s(Vector2(960.0, 1600.0))), Color(ink, 0.04), true)
	_text("C2 / STATE + FEEDBACK", Vector2(56.0, 66.0), 30.0, ink)
	_text("%s  ·  SAFE %.0f / %.0f / %.0f / %.0f" % [
		String(_mode).to_upper(), _safe_margins.x, _safe_margins.y, _safe_margins.z, _safe_margins.w,
	], Vector2(56.0, 96.0), 16.0, brass)
	draw_line(_p(Vector2(56.0, 114.0)), _p(Vector2(904.0, 114.0)), brass, _stroke(2.0))

	_text("BASE STATE / NON-COLOR CUE", Vector2(56.0, 156.0), 18.0, ink)
	for i in TableVisualState.STATE_NAMES.size():
		_draw_state_row(i, Vector2(56.0, 176.0 + float(i) * 116.0), card, ink, brass)

	_text("LAMP CHANNEL / DETERMINISTIC PRIORITY", Vector2(56.0, 892.0), 18.0, ink)
	for i in TableVisualState.LAMP_CHANNEL_NAMES.size():
		var channel: StringName = TableVisualState.LAMP_CHANNEL_NAMES[i]
		var y := 918.0 + float(i) * 38.0
		var priority := TableVisualState.lamp_priority(channel)
		_text(String(channel).replace("_", " ").to_upper(), Vector2(56.0, y), 16.0, ink)
		_text("%03d" % priority, Vector2(706.0, y), 16.0, brass)
		draw_rect(Rect2(_p(Vector2(770.0, y - 15.0)), _s(Vector2(float(priority) * 0.18, 10.0))),
			Color(brass, 0.86), true)

	_text("FEEDBACK LEVEL / SOURCE + DESTINATION RULE", Vector2(56.0, 1178.0), 18.0, ink)
	for i in TableVisualState.FEEDBACK_LEVEL_NAMES.size():
		var level := TableVisualState.FEEDBACK_LEVEL_NAMES[i]
		var y := 1210.0 + float(i) * 62.0
		_text(String(level).replace("_", " ").to_upper(), Vector2(56.0, y), 18.0, ink)
		var cue: String = ["RING / RAYS", "AMOUNT → HUD", "SIDE / LOWER", "SAFE CENTER"][i]
		_text(cue, Vector2(430.0, y), 16.0, brass)
		_draw_glyph(Vector2(838.0, y - 9.0), i, brass)

	_text("HAPTICS %s   ·   SUBTITLES %s   ·   %s" % [
		"OFF" if _mode == &"haptics_off" else "ON",
		"OFF" if _mode == &"subtitles_off" else "ON",
		"MOTION REDUCED" if _mode == &"reduced_motion" else (
			"FLASH REDUCED" if _mode == &"reduced_flash" else "CAUSALITY RETAINED"),
	], Vector2(56.0, 1518.0), 16.0, brass)
	_text("Every cue remains named and patterned in grayscale.", Vector2(56.0, 1552.0), 15.0, ink)


func _draw_state_row(index: int, at: Vector2, card: Color, ink: Color, brass: Color) -> void:
	var token := TableVisualState.state_token(index)
	draw_rect(Rect2(_p(at), _s(Vector2(848.0, 94.0))), card, true)
	draw_rect(Rect2(_p(at), _s(Vector2(848.0, 94.0))), Color(ink, 0.35), false, _stroke(2.0))
	_text(String(token["state"]).to_upper(), at + Vector2(18.0, 30.0), 21.0, ink)
	_text(String(token["material"]).to_upper(), at + Vector2(18.0, 58.0), 14.0, brass)
	_draw_glyph(at + Vector2(292.0, 42.0), index, brass)
	_text(String(token["mark"]).replace("_", " ").to_upper(), at + Vector2(356.0, 37.0), 16.0, ink)
	_text(String(token["pattern"]).replace("_", " ").to_upper(), at + Vector2(356.0, 65.0), 14.0, brass)
	_text("INVITE" if bool(token["invitation"]) else "NO INVITE", at + Vector2(700.0, 52.0), 14.0,
			brass if bool(token["invitation"]) else ink)


func _draw_glyph(at: Vector2, index: int, color: Color) -> void:
	var center := _p(at)
	var radius := _s(Vector2(16.0, 16.0)).x
	match index:
		0:
			draw_arc(center, radius, 0.0, TAU, 16, color, _stroke(3.0))
		1:
			draw_line(center + _s(Vector2(-12.0, 0.0)), center + _s(Vector2(10.0, 0.0)), color, _stroke(4.0))
			draw_line(center + _s(Vector2(10.0, 0.0)), center + _s(Vector2(2.0, -8.0)), color, _stroke(4.0))
			draw_line(center + _s(Vector2(10.0, 0.0)), center + _s(Vector2(2.0, 8.0)), color, _stroke(4.0))
		2:
			draw_circle(center, radius * 0.5, Color(color, 0.65))
			draw_arc(center, radius, 0.0, TAU, 16, color, _stroke(3.0))
		3:
			draw_line(center + _s(Vector2(-10.0, -8.0)), center + _s(Vector2(10.0, 8.0)), color, _stroke(4.0))
			draw_line(center + _s(Vector2(-10.0, 8.0)), center + _s(Vector2(10.0, -8.0)), color, _stroke(4.0))


func _text(value: String, at: Vector2, size: float, color: Color) -> void:
	var font: Font = Presentation.theme.font_for(&"ui")
	draw_string(font, _p(at), value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size(size), color)


func _color(value: Color) -> Color:
	if _mode != &"grayscale":
		return value
	var luma := value.r * 0.2126 + value.g * 0.7152 + value.b * 0.0722
	return Color(luma, luma, luma, value.a)


func _p(value: Vector2) -> Vector2:
	return _origin + value * _scale


func _s(value: Vector2) -> Vector2:
	return value * _scale


func _stroke(value: float) -> float:
	return maxf(1.0, value * _scale)


func _font_size(value: float) -> int:
	return maxi(10, int(round(value * _scale)))


func _write_manifest() -> void:
	var manifest := {
		"schema": "kingpin.c2_state_feedback.v1",
		"unit": "C2 shared state, lamp, and feedback contract",
		"source": {
			"specimen": "res://tests/c2_state_specimen.gd",
			"state_authority": "res://game/presentation/table_visual_state.gd",
			"state_sha256": FileAccess.get_sha256("res://game/presentation/table_visual_state.gd"),
		},
		"coverage": {
			"states": TableVisualState.STATE_NAMES,
			"local_modifiers": TableVisualState.LOCAL_MODIFIERS,
			"lamp_channels": TableVisualState.LAMP_CHANNEL_NAMES,
			"feedback_levels": TableVisualState.FEEDBACK_LEVEL_NAMES,
			"modes": MODES,
		},
		"captures": _captures,
		"acceptance": {
			"draw_only": true,
			"non_color_cues": true,
			"safe_clamp_recorded": true,
			"payloads_unchanged": true,
			"subtitle_layer": "read-only D4 anchor; not modified",
		},
	}
	var path := _output_dir.path_join("manifest.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("C2 SPECIMEN: manifest open failed path=%s" % path)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("C2 SPECIMEN MANIFEST: %s captures=%d" % [path, _captures.size()])
