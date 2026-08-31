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
var _safe_heading: Label = null
var _safe_label: Label = null
var _safe_annotation: Label = null
var _content_margin: MarginContainer = null
var _content_column: VBoxContainer = null
var _reveal_wash: ColorRect = null
var _reveal_progress := 0.0


func _ready() -> void:
	layer = 20
	_reveal_wash = ColorRect.new()
	_reveal_wash.name = "CabinetWash"
	_reveal_wash.color = Feel.COL_INK
	_reveal_wash.color.a = 0.62
	_reveal_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reveal_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The table's illuminated backglass is the title screen now. Keep the wash restrained so the
	# authored lockup and cabinet material remain visible behind the safe-area invitation.
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
	col.name = "FrontDoorContent"
	col.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	_content_column = col
	_content_margin.add_child(col)

	# The backglass already carries the only KINGPIN lockup. Safe content starts with one short
	# invitation, then gives the player two useful wallet facts before the next action. A saved
	# career changes only the invitation copy, never the action hierarchy.
	var resumed := _is_resumed_career()
	var invitation := PaperKit.type_label("WELCOME BACK" if resumed else "THE HOUSE IS OPEN",
			&"title", Feel.COL_NEWSPRINT,
			HORIZONTAL_ALIGNMENT_CENTER)
	invitation.name = "Invitation"
	col.add_child(invitation)
	var prompt := PaperKit.type_label("Pick up where you left off." if resumed \
			else "Choose your crew for tonight.", &"body",
			Feel.COL_NEWSPRINT.darkened(0.08), HORIZONTAL_ALIGNMENT_CENTER)
	prompt.name = "InvitationCopy"
	col.add_child(prompt)

	var status_panel := PaperKit.glass_panel()
	status_panel.name = "CareerStatus"
	status_panel.custom_minimum_size.y = Presentation.theme.spacing_for(&"space_64") * 2.0
	var status_content := VBoxContainer.new()
	status_content.add_theme_constant_override("separation",
			int(Presentation.theme.spacing_for(&"space_8")))
	status_panel.add_child(status_content)
	var status_heading := PaperKit.type_label("BACK ON THE BOOKS" if resumed else "ON THE BOOKS",
			&"micro", Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER)
	status_heading.name = "StatusHeading"
	status_content.add_child(status_heading)
	var money := HBoxContainer.new()
	money.name = "WalletFacts"
	money.add_theme_constant_override("separation",
			int(Presentation.theme.spacing_for(&"space_24")))
	status_content.add_child(money)
	var dirty_fact := _wallet_fact("DIRTY", Game.wallet.dirty.text(), Feel.COL_DIRTY)
	dirty_fact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(dirty_fact)
	var clean_fact := _wallet_fact("CLEAN", Game.wallet.clean.text(), Feel.COL_CLEAN)
	clean_fact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	money.add_child(clean_fact)
	var context := PaperKit.type_label(
			"NIGHT %d  ·  %s  ·  RESPECT %d" % [Game.night_no + 1, Game.rank_title(), Game.respect],
			&"metadata", Feel.COL_NEWSPRINT.darkened(0.18), HORIZONTAL_ALIGNMENT_CENTER)
	context.name = "CareerContext"
	status_content.add_child(context)
	col.add_child(status_panel)

	_build_safe(col)

	var start := PaperKit.action_button("ROLL CALL", &"primary")
	start.name = "RollCallCTA"
	var cta_type := Presentation.theme.typography_for(&"title")
	start.add_theme_font_override("font", cta_type["font"] as Font)
	start.add_theme_font_size_override("font_size", int(cta_type["size"]))
	start.custom_minimum_size.y = maxf(
			float(Presentation.theme.control_for(&"button").get("min_height", Presentation.theme.touch_min)),
			Presentation.theme.spacing_for(&"space_64") * 2.0)
	start.pressed.connect(func() -> void: start_pressed.emit())
	col.add_child(start)
	var settings_button := PaperKit.action_button("HOUSE RULES", &"quiet")
	settings_button.name = "SettingsButton"
	settings_button.custom_minimum_size.y = float(Presentation.theme.control_for(&"compact_button").get(
			"min_height", Presentation.theme.touch_min))
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	col.add_child(settings_button)

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
	if _content_margin == null:
		return
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	# The base canvas is 1920 logical pixels tall. Keep the invitation/action cluster in the
	# lower half on extra-tall canvases while retaining enough room for large-text capture.
	var scale := maxf(viewport_height / 1920.0, 0.82)
	var top := 1030.0 * scale
	var bottom := 120.0 * scale
	if _content_column != null:
		var required_height := _content_column.get_combined_minimum_size().y
		var available_bottom := viewport_height - bottom
		if top + required_height > available_bottom:
			top = maxf(0.0, available_bottom - required_height)
	Presentation.safe.apply_to_margin_container(_content_margin,
			Vector4(60.0, top, 60.0, bottom))


func _process(delta: float) -> void:
	if _reveal_wash == null or _content_margin == null:
		return
	if _reduced_motion_enabled():
		_reveal_progress = 1.0
	else:
		_reveal_progress = minf(1.0, _reveal_progress + delta / 0.95)
	var eased := _ease_reveal(_reveal_progress)
	_reveal_wash.color.a = lerpf(0.62, 0.42, eased)
	_content_margin.modulate.a = clampf((eased - 0.12) / 0.88, 0.0, 1.0)
	# Container minimums settle after the first layout pass (and change when the Safe appears),
	# so keep the cluster inside the available safe height without moving it every frame once fit.
	_apply_safe_area()


func _reduced_motion_enabled() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_motion


func _ease_reveal(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _build_safe(col: VBoxContainer) -> void:
	_safe_panel = PaperKit.glass_panel()
	_safe_panel.name = "PendingSafeInterruption"
	_safe_panel.set_meta("paperkit_role", &"safe_interruption")
	_safe_panel.set_meta("presentation_state", &"earned_interrupt")
	_safe_panel.custom_minimum_size.y = Presentation.theme.spacing_for(&"space_64") * 2.0
	var row := HBoxContainer.new()
	row.name = "SafeDropRow"
	row.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	_safe_panel.add_child(row)
	var copy := VBoxContainer.new()
	copy.name = "SafeDropCopy"
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	_safe_heading = PaperKit.type_label("SAFE DROP", &"micro", Feel.COL_BRASS)
	_safe_heading.name = "Heading"
	copy.add_child(_safe_heading)
	_safe_label = PaperKit.type_label("", &"primary_value", Feel.COL_NEWSPRINT)
	_safe_label.name = "Amount"
	copy.add_child(_safe_label)
	_safe_annotation = PaperKit.type_label("Offline earnings · dirty cash", &"caption",
			Feel.COL_NEWSPRINT.darkened(0.12))
	_safe_annotation.name = "Annotation"
	copy.add_child(_safe_annotation)
	var collect := PaperKit.action_button("COLLECT", &"secondary")
	collect.name = "CollectSafe"
	collect.tooltip_text = "Collect the Safe drop"
	collect.pressed.connect(func() -> void: Game.collect_safe())
	row.add_child(collect)
	col.add_child(_safe_panel)
	_on_safe_changed(Game.safe_pending)


func _wallet_fact(label_text: String, value_text: String, color: Color) -> VBoxContainer:
	var fact := VBoxContainer.new()
	fact.alignment = BoxContainer.ALIGNMENT_CENTER
	var label := PaperKit.type_label(label_text, &"metadata", color, HORIZONTAL_ALIGNMENT_CENTER)
	fact.add_child(label)
	var value := PaperKit.type_label(value_text, &"primary_value", color,
			HORIZONTAL_ALIGNMENT_CENTER)
	fact.add_child(value)
	return fact


func _on_safe_changed(amount: BigMoney) -> void:
	if _safe_panel == null or not is_instance_valid(_safe_panel):
		return
	var got := amount != null and amount.is_positive()
	_safe_panel.visible = got
	if got:
		_safe_label.text = amount.text()


func _is_resumed_career() -> bool:
	if Game == null or not Game.is_booted():
		return false
	if Game.night_no > 0 or Game.rank > 0 or Game.respect > 0:
		return true
	if Game.safe_pending != null and Game.safe_pending.is_positive():
		return true
	return (Game.wallet.dirty != null and Game.wallet.dirty.is_positive()) \
			or (Game.wallet.clean != null and Game.wallet.clean.is_positive())
