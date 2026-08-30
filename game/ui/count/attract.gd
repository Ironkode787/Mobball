class_name AttractScreen
extends CanvasLayer
## The session's front door. Lives beside The Count because they are the same object in
## two moods: the shell you see when no guy is on the table.
##
## Boot ritual (docs/03 §6): if the Safe filled up while you were away, it is the first
## thing on screen — bag-drop sound, count, collect.

signal start_pressed
signal settings_pressed

## The attract screen is deliberately a presentation-only layer. The live table remains
## behind it (and remains the source of truth for the cabinet), while this little marquee
## gives the title state its own entrance beat without importing another image or node tree.
class _CabinetReveal extends Control:
	const BULB_COUNT := 7
	const REVEAL_SECONDS := 0.9

	var _elapsed := 0.0
	var _reveal := 0.0


	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _reduced_motion():
			_reveal = 1.0
		queue_redraw()


	func _process(delta: float) -> void:
		if _reduced_motion():
			# Reduced motion still leaves a readable, warm cabinet: no chase or entrance travel.
			_reveal = 1.0
			_elapsed = 0.0
		else:
			_elapsed += delta
			_reveal = minf(1.0, _reveal + delta / REVEAL_SECONDS)
		queue_redraw()


	func _reduced_motion() -> bool:
		return Presentation.fx != null and Presentation.fx.reduced_motion


	func _static_bulbs() -> bool:
		return Presentation.fx != null \
				and (Presentation.fx.reduced_motion or Presentation.fx.reduced_flash)


	func _draw() -> void:
		var viewport := get_viewport_rect().size
		if viewport.x <= 0.0 or viewport.y <= 0.0:
			return
		var frame := Rect2(Vector2(46.0, 46.0),
				Vector2(maxf(1.0, viewport.x - 92.0), maxf(1.0, viewport.y - 92.0)))
		var reveal := _ease(_reveal)

		# A thin cabinet outline and corner screws are enough to make the live playfield read as
		# a single object. This is decorative, so it may approach the glass edge; all copy and
		# controls still belong to AttractScreen's safe MarginContainer.
		var frame_color := Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b,
				0.30 * reveal)
		draw_rect(frame, frame_color, false, 4.0)
		draw_rect(frame.grow(-14.0), Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g,
				Feel.COL_BRASS.b, 0.11 * reveal), false, 2.0)
		for corner in [frame.position, Vector2(frame.end.x, frame.position.y),
				Vector2(frame.position.x, frame.end.y), frame.end]:
			draw_circle(corner, 7.0, Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g,
				Feel.COL_BRASS.b, 0.42 * reveal))

		# Seven bulbs on both rails echo the real backglass lamps. The bright point walks slowly,
		# with a soft neighbouring glow so the motion reads as incandescent rather than digital.
		for i in BULB_COUNT:
			var u := float(i) / float(BULB_COUNT - 1)
			var x := lerpf(frame.position.x + 62.0, frame.end.x - 62.0, u)
			_draw_bulb(Vector2(x, frame.position.y + 10.0), i, reveal)
			_draw_bulb(Vector2(x, frame.end.y - 10.0), i + BULB_COUNT, reveal)


	func _draw_bulb(at: Vector2, index: int, reveal: float) -> void:
		var hot := false
		var neighbour := false
		if _static_bulbs():
			# A static alternating pattern is the reduced-motion equivalent of the chase.
			hot = posmod(index, 2) == 0
		else:
			var chase := fmod(_elapsed * 2.25, float(BULB_COUNT))
			var slot := fmod(float(index), float(BULB_COUNT))
			var distance := absf(slot - chase)
			distance = minf(distance, float(BULB_COUNT) - distance)
			hot = distance < 0.42
			neighbour = distance < 1.25
		var pulse := 0.0
		if hot:
			pulse = 1.0
		elif neighbour:
			pulse = 0.40
		var glow_alpha := (0.05 + 0.15 * pulse) * reveal
		var glow := Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, glow_alpha)
		draw_circle(at, 25.0 if hot else 19.0, glow)
		var shell := Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b,
				(0.38 + 0.24 * pulse) * reveal)
		draw_circle(at, 10.0 if hot else 8.0, shell)
		var core := Feel.COL_NEWSPRINT if hot else Feel.COL_BRASS.darkened(0.42)
		draw_circle(at - Vector2(2.0, 2.0), 4.0 if hot else 2.5,
				Color(core.r, core.g, core.b, (0.94 if hot else 0.58) * reveal))


	func _ease(value: float) -> float:
		var t := clampf(value, 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)


var _safe_panel: PanelContainer = null
var _safe_label: Label = null
var _content_margin: MarginContainer = null
var _reveal_wash: ColorRect = null
var _reveal_progress := 0.0


func _ready() -> void:
	layer = 20
	_reveal_wash = ColorRect.new()
	_reveal_wash.name = "CabinetWash"
	_reveal_wash.color = Feel.COL_INK
	_reveal_wash.color.a = 0.88
	_reveal_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The table's illuminated backglass is the title screen now. A lighter smoked-glass wash
	# keeps it visible instead of printing a second opaque screen over the cabinet.
	add_child(_reveal_wash)

	var chrome := _CabinetReveal.new()
	chrome.name = "CabinetReveal"
	chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(chrome)

	_content_margin = MarginContainer.new()
	_content_margin.name = "SafeContent"
	_content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_margin)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_content_margin.add_child(col)

	var brand := PaperKit.label("K I N G P I N", PaperKit.FONT_HUGE, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER)
	brand.name = "BrandMark"
	brand.custom_minimum_size.y = 92.0
	col.add_child(brand)
	col.add_child(PaperKit.label("THE HOUSE IS OPEN", PaperKit.FONT_TITLE, Feel.COL_NEWSPRINT,
			HORIZONTAL_ALIGNMENT_CENTER))
	col.add_child(PaperKit.rule())
	col.add_child(PaperKit.label(
			"%s   ·   NIGHT %d   ·   RESPECT %d" % [Game.rank_title(), Game.night_no + 1, Game.respect],
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.22),
			HORIZONTAL_ALIGNMENT_CENTER))

	var money := HBoxContainer.new()
	money.add_theme_constant_override("separation", 28)
	var dirty := PaperKit.label("DIRTY  " + Game.wallet.dirty.text(), PaperKit.FONT_BODY,
			Feel.COL_DIRTY)
	dirty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(dirty)
	var clean := PaperKit.label("CLEAN  " + Game.wallet.clean.text(), PaperKit.FONT_BODY,
			Feel.COL_CLEAN, HORIZONTAL_ALIGNMENT_RIGHT)
	clean.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(clean)
	col.add_child(money)

	_build_safe(col)

	var start := PaperKit.button("ROLL CALL", PaperKit.FONT_TITLE, Feel.COL_CLEAN)
	start.name = "RollCallCTA"
	start.custom_minimum_size.y = Presentation.theme.touch_min
	start.add_theme_stylebox_override("normal", PaperKit.box(
			Feel.COL_INK.lightened(0.10), Feel.COL_CLEAN, 5.0))
	start.add_theme_stylebox_override("hover", PaperKit.box(
			Feel.COL_INK.lightened(0.18), Feel.COL_CLEAN, 5.0))
	start.add_theme_stylebox_override("pressed", PaperKit.box(Feel.COL_CLEAN,
			Feel.COL_CLEAN, 5.0))
	start.pressed.connect(func() -> void: start_pressed.emit())
	var cta := VBoxContainer.new()
	cta.name = "BrandedCTA"
	cta.add_theme_constant_override("separation", 8)
	cta.add_child(PaperKit.label("TAKE YOUR PLACE AT FIFTH STREET", PaperKit.FONT_SMALL,
			Feel.COL_BRASS, HORIZONTAL_ALIGNMENT_CENTER))
	cta.add_child(start)
	var settings_button := PaperKit.button("HOUSE RULES", PaperKit.FONT_SMALL, Feel.COL_BRASS)
	settings_button.name = "SettingsButton"
	settings_button.custom_minimum_size.y = Presentation.theme.touch_min
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	cta.add_child(settings_button)
	col.add_child(cta)

	Game.safe_changed.connect(_on_safe_changed)
	if _reduced_motion_enabled():
		_reveal_progress = 1.0
		_reveal_wash.color.a = 0.62
		_content_margin.modulate.a = 1.0
	else:
		_content_margin.modulate.a = 0.0


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content_margin,
			Vector4(60.0, 1030.0, 60.0, 120.0))


func _process(delta: float) -> void:
	if _reveal_wash == null or _content_margin == null:
		return
	if _reduced_motion_enabled():
		_reveal_progress = 1.0
	else:
		_reveal_progress = minf(1.0, _reveal_progress + delta / 0.95)
	var eased := _ease_reveal(_reveal_progress)
	_reveal_wash.color.a = lerpf(0.88, 0.62, eased)
	_content_margin.modulate.a = clampf((eased - 0.12) / 0.88, 0.0, 1.0)


func _reduced_motion_enabled() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_motion


func _ease_reveal(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _build_safe(col: VBoxContainer) -> void:
	_safe_panel = PaperKit.panel(Feel.COL_INK.lightened(0.08), Feel.COL_BRASS)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_safe_panel.add_child(row)
	_safe_label = PaperKit.label("", PaperKit.FONT_BODY, Feel.COL_BRASS)
	_safe_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_safe_label)
	var collect := PaperKit.button("COLLECT", PaperKit.FONT_BODY)
	collect.pressed.connect(func() -> void: Game.collect_safe())
	row.add_child(collect)
	col.add_child(_safe_panel)
	_on_safe_changed(Game.safe_pending)


func _on_safe_changed(amount: BigMoney) -> void:
	if _safe_panel == null or not is_instance_valid(_safe_panel):
		return
	var got := amount != null and amount.is_positive()
	_safe_panel.visible = got
	if got:
		_safe_label.text = "THE SAFE  " + amount.text()
