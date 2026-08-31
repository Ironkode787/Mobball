extends Node2D
## Deterministic A1-only typography specimen. Capture through tools/shot_capture.tscn with
## SHOT_SCENE=res://tests/token_specimen.tscn and a unique SHOT_PATH.

const ROLE_SAMPLES: Dictionary = {
	&"hero": "KINGPIN",
	&"title": "THE NIGHT",
	&"section": "ROLL CALL",
	&"primary_value": "$12,500",
	&"body": "House remembers.",
	&"caption": "Quiet words travel.",
	&"metadata": "CASE 07  /  03:14",
	&"button": "START NIGHT",
	&"micro": "LIVE · VERIFIED",
}

var theme: PresentationTheme = PresentationTheme.defaults()
var profile: Dictionary = {}
var profile_id: StringName = &"compact"
var unit_scale: float = 1.0
var content_rect := Rect2()


func _ready() -> void:
	var output := OS.get_environment("TOKEN_OUTPUT")
	if not output.is_empty():
		await get_tree().process_frame
		await _capture_offscreen(output)
		return
	_configure(get_viewport_rect().size)
	queue_redraw()


func _configure(viewport_size: Vector2) -> void:
	var requested_profile := OS.get_environment("TOKEN_PROFILE")
	if requested_profile == "compact" or requested_profile == "standard":
		profile_id = StringName(requested_profile)
	else:
		profile_id = &"standard" if viewport_size.x >= 720.0 else &"compact"
	profile = theme.layout_profile(profile_id)
	var gutter: Vector4 = profile["safe_gutter"]
	var logical_width := float(profile["content_width"]) + gutter.x + gutter.z
	unit_scale = viewport_size.x / logical_width
	content_rect = Rect2(gutter.x * unit_scale, gutter.y * unit_scale,
			float(profile["content_width"]) * unit_scale,
			viewport_size.y - (gutter.y + gutter.w) * unit_scale)
	print("TOKEN SPECIMEN: profile=%s viewport=%dx%d roles=%d content=%dx%d" % [
		profile_id, int(viewport_size.x), int(viewport_size.y), PresentationTheme.TYPE_ROLES.size(),
		int(content_rect.size.x), int(content_rect.size.y),
	])


func _capture_offscreen(output: String) -> void:
	var width := int(OS.get_environment("TOKEN_WIDTH"))
	var height := int(OS.get_environment("TOKEN_HEIGHT"))
	if width <= 0 or height <= 0:
		printerr("TOKEN SPECIMEN: invalid target dimensions")
		get_tree().quit(2)
		return
	var host := get_parent()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(width, height)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.remove_child(self)
	host.add_child(viewport)
	viewport.add_child(self)
	_configure(Vector2(width, height))
	queue_redraw()
	for _i in 6:
		await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	var err := image.save_png(output)
	print("TOKEN SPECIMEN SAVED: profile=%s viewport=%dx%d roles=%d path=%s err=%d" % [
		profile_id, width, height, PresentationTheme.TYPE_ROLES.size(), output, err,
	])
	get_tree().quit(0 if err == OK else 1)


func _draw() -> void:
	if profile.is_empty():
		return
	var viewport_size := get_viewport_rect().size
	var paper := theme.material_for(&"newsprint")
	var card := theme.material_for(&"aged_paper")
	draw_rect(Rect2(Vector2.ZERO, viewport_size), paper["fill"])
	draw_rect(content_rect, Color(theme.ink, 0.04), true)

	var title_font: Font = theme.typography_for(&"hero")["font"]
	var title_size := mini(_px(float(theme.typography_for(&"hero")["size"])),
			_px(40.0 if profile_id == &"compact" else 78.0))
	draw_string(title_font, content_rect.position + Vector2(0.0, _px(54.0)),
		"A1 / TYPE TOKENS", HORIZONTAL_ALIGNMENT_LEFT, content_rect.size.x, title_size, theme.ink)
	var profile_font: Font = theme.typography_for(&"metadata")["font"]
	var gutter_label := "32·48·32·48" if profile_id == &"compact" else str(profile["safe_gutter"])
	draw_string(profile_font, content_rect.position + Vector2(0.0, _px(76.0)),
		"PROFILE %s / GUTTER %s" % [String(profile_id).to_upper(), gutter_label],
		HORIZONTAL_ALIGNMENT_LEFT, content_rect.size.x, _px(11.0 if profile_id == &"compact" else 14.0), theme.brass)
	draw_line(content_rect.position + Vector2(0.0, _px(90.0)),
		content_rect.position + Vector2(content_rect.size.x, _px(90.0)), theme.brass, _px(2.0))

	var row_height := _px(64.0 if profile_id == &"compact" else 116.0)
	var row_gap := _px(6.0 if profile_id == &"compact" else 8.0)
	var top := content_rect.position.y + _px(104.0)
	for role: StringName in PresentationTheme.TYPE_ROLES:
		_draw_role(role, Vector2(content_rect.position.x, top),
			Vector2(content_rect.size.x, row_height), card)
		top += row_height + row_gap

	var footer_font: Font = theme.typography_for(&"caption")["font"]
	var footer := "%d ROLES / CONTENT %.0f / RHYTHM 4·8" % [
		PresentationTheme.TYPE_ROLES.size(), float(profile["content_width"]),
	]
	draw_string(footer_font, content_rect.position + Vector2(0.0, content_rect.size.y), footer,
		HORIZONTAL_ALIGNMENT_LEFT, content_rect.size.x, _px(15.0), theme.ink)


func _draw_role(role: StringName, at: Vector2, row_size: Vector2, card: Dictionary) -> void:
	var token := theme.typography_for(role)
	draw_rect(Rect2(at, row_size), card["fill"], true)
	draw_rect(Rect2(at, row_size), card["border"], false, _px(1.0))
	var role_font: Font = theme.typography_for(&"metadata")["font"]
	draw_string(role_font, at + Vector2(_px(14.0), _px(21.0)), String(role).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, row_size.x * 0.31, _px(13.0), theme.brass)
	var sample_font: Font = token["font"]
	var sample := String(ROLE_SAMPLES.get(role, String(role)))
	var sample_width := row_size.x * 0.67
	var sample_size := mini(_px(float(token["size"])), _px(18.0 if profile_id == &"compact" else 36.0))
	draw_string(sample_font, at + Vector2(row_size.x * 0.32, _px(31.0)), sample,
		HORIZONTAL_ALIGNMENT_LEFT, sample_width, sample_size, theme.ink)
	var meta := "lh %.2f  tr %.2f  max %.0f  tab %s" % [
		float(token["line_height"]), float(token["tracking"]), float(token["max_width"]),
		"yes" if bool(token["tabular_numbers"]) else "no",
	]
	draw_string(role_font, at + Vector2(_px(14.0), row_size.y - _px(10.0)), meta,
		HORIZONTAL_ALIGNMENT_LEFT, row_size.x - _px(28.0), _px(11.0), theme.ink.darkened(0.18))


func _px(value: float) -> int:
	return maxi(1, int(round(value * unit_scale)))
