class_name CountScreen
extends CanvasLayer
## THE COUNT — the tally room (docs/01 §3). The dopamine ritual and the natural stopping
## point: the numbers roll up with the bill counter, the paper prints the night's headline,
## and the "one more Night" button sits right there lit like a jukebox.
##
## Reads `Game.last_night` (built by NightController + Game.end_night) and renders it. It
## decides nothing — money, respect and laundering are already settled by the time this
## screen exists.

signal ledger_pressed
signal next_night_pressed
signal settings_pressed
## The Commission is asking (specs/m2-content.md §5). The next Night is the fight.
signal boss_pressed
## The war room booked a job for the next Night (docs/05 §5): target, approach, inside man.
signal heist_pressed(target: StringName, approach: StringName, guy: Dictionary)
## The player is getting on the train (docs/06 §1). `keep` is the one guy who comes along.
signal skip_town_pressed(keep: Dictionary)

## Seconds each line takes to roll up, and the gap between the bill-counter ticks.
const LINE_TIME := 0.55
const TICK_INTERVAL := 0.07
const LINE_GAP := 0.12
const HEADLINE_DELAY := 0.18
const HEADLINE_CHAR_TIME := 0.022
## Jobs offered on the page at once. The board holds five targets; a Count screen that is
## mostly heist buttons is a menu, not a newspaper.
const HEIST_SLOTS := 2


## The number window on the adding machine. It remains a Label for the count logic, but the
## parent paints the little mechanical windows behind it so each line reads as a physical
## odometer rather than a value floating over the room plate.
class CountOdometerFace extends Control:
	var tint := Feel.COL_BRASS

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func set_tint(value: Color) -> void:
		tint = value
		queue_redraw()

	func _draw() -> void:
		if size.x < 2.0 or size.y < 2.0:
			return
		var outer := Rect2(0.0, 5.0, size.x, maxf(size.y - 10.0, 1.0))
		draw_rect(Rect2(3.0, 8.0, size.x, outer.size.y), Color(0.0, 0.0, 0.0, 0.24))
		draw_rect(outer, Color(Feel.COL_INK, 0.86))
		draw_rect(outer, Color(tint, 0.58), false, 2.0)
		var slot_count := 6
		var gap := 3.0
		var slot_w := (size.x - gap * float(slot_count + 1)) / float(slot_count)
		for i in slot_count:
			var x := gap + float(i) * (slot_w + gap)
			var slot := Rect2(x, 12.0, slot_w, maxf(size.y - 24.0, 1.0))
			draw_rect(slot, Color(Feel.COL_NEWSPRINT, 0.07))
			draw_line(slot.position + Vector2(0.0, 4.0),
				slot.position + Vector2(slot.size.x, 4.0), Color(tint, 0.32), 1.0)
			draw_line(slot.position + Vector2(0.0, slot.size.y - 4.0),
				slot.position + Vector2(slot.size.x, slot.size.y - 4.0),
				Color(0.0, 0.0, 0.0, 0.30), 1.0)
			if i > 0:
				draw_line(Vector2(x - gap * 0.5, 9.0), Vector2(x - gap * 0.5, size.y - 9.0),
					Color(tint, 0.48), 1.0)


## A narrow adding-machine receipt and the counted bills. The generated room plate stays the
## hero image; this layer gives the live values a physical surface without adding an asset or
## changing the gameplay layout. It is deliberately mouse-transparent.
class CountSetPiece extends Control:
	var summary: Dictionary = {}
	var roll_progress := 0.0:
		set(value):
			roll_progress = clampf(value, 0.0, 1.0)
			queue_redraw()

	var _font: Font = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = Presentation.theme.font_for(&"annotation_bold")

	func _draw() -> void:
		if size.x < 2.0 or size.y < 2.0:
			return
		var paper := Rect2(size.x * 0.075, size.y * 0.115, size.x * 0.85, size.y * 0.59)
		# The machine receipt is not a flat panel: a drop shadow and a torn feed edge make it
		# read as the paper coming out of the photographed adding machine.
		draw_rect(Rect2(paper.position + Vector2(10.0, 16.0), paper.size),
			Color(0.0, 0.0, 0.0, 0.28))
		draw_rect(paper, Color(Feel.COL_NEWSPRINT, 0.82))
		draw_rect(paper, Color(Feel.COL_INK, 0.30), false, 2.0)
		var header_y := paper.position.y + 72.0
		draw_line(Vector2(paper.position.x + 32.0, header_y),
			Vector2(paper.end.x - 32.0, header_y), Color(Feel.COL_INK, 0.26), 2.0)
		var ruled_y := header_y + 76.0
		while ruled_y < paper.end.y - 80.0:
			draw_line(Vector2(paper.position.x + 32.0, ruled_y),
				Vector2(paper.end.x - 32.0, ruled_y), Color(Feel.COL_INK, 0.095), 1.0)
			ruled_y += 78.0
		if _font != null:
			draw_string(_font, paper.position + Vector2(34.0, 52.0), "EASTPORT · NIGHTLY TALLY",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(Feel.COL_INK, 0.62))
		# Feed holes and the torn bottom edge sell the receipt silhouette at phone scale.
		for x in range(int(paper.position.x + 18.0), int(paper.end.x - 18.0), 30):
			draw_circle(Vector2(float(x), paper.position.y + 13.0), 3.0, Color(Feel.COL_INK, 0.23))
			draw_circle(Vector2(float(x), paper.end.y - 13.0), 3.0, Color(Feel.COL_INK, 0.23))
		var teeth := PackedVector2Array()
		for i in 25:
			var x := paper.position.x + float(i) / 24.0 * paper.size.x
			teeth.append(Vector2(x, paper.end.y + (7.0 if i % 2 == 0 else 0.0)))
		draw_polyline(teeth, Color(Feel.COL_INK, 0.30), 1.5)

		var bill_alpha := 0.32 + roll_progress * 0.48
		_draw_bill_stack(Vector2(size.x * 0.14, size.y * 0.84), Feel.COL_DIRTY, 6,
			deg_to_rad(-8.0), bill_alpha, "D")
		_draw_bill_stack(Vector2(size.x * 0.69, size.y * 0.85), Feel.COL_CLEAN, 5,
			deg_to_rad(7.0), bill_alpha, "C")

	func _draw_bill_stack(origin: Vector2, color: Color, count: int, angle: float,
			alpha: float, mark: String) -> void:
		if _font == null:
			return
		var visible_count := maxi(1, int(roundf(float(count) * maxf(roll_progress, 0.18))))
		for i in visible_count:
			var lift := float(i) * -4.0
			draw_set_transform(origin + Vector2(0.0, lift), angle, Vector2.ONE)
			var note := Rect2(-118.0, -31.0, 236.0, 62.0)
			draw_rect(Rect2(note.position + Vector2(5.0, 7.0), note.size), Color(0.0, 0.0, 0.0, 0.22))
			draw_rect(note, Color(color, alpha))
			draw_rect(note, Color(Feel.COL_NEWSPRINT, alpha * 0.72), false, 2.0)
			draw_line(Vector2(-78.0, -22.0), Vector2(-78.0, 22.0), Color(Feel.COL_NEWSPRINT, alpha * 0.48), 1.0)
			draw_line(Vector2(78.0, -22.0), Vector2(78.0, 22.0), Color(Feel.COL_NEWSPRINT, alpha * 0.48), 1.0)
			draw_circle(Vector2.ZERO, 14.0, Color(Feel.COL_NEWSPRINT, alpha * 0.42))
			draw_string(_font, Vector2(-7.0, 7.0), mark, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16,
				Color(color.darkened(0.42), alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

var summary: Dictionary = {}

var _rows: Array[Dictionary] = []
var _row_index: int = -1
var _row_time: float = 0.0
var _tick_time: float = 0.0
var _headline: Label = null
var _headline_shown: bool = false
var _headline_revealing: bool = false
var _headline_stung: bool = false
var _headline_elapsed: float = 0.0
var _headline_target := ""
var _headline_placeholder: Label = null
var _tally_indicator: Label = null
var _buttons: PanelContainer = null
var _roster: VBoxContainer = null
var _safe: PanelContainer = null
var _body: VBoxContainer = null
var _counter: AudioStreamPlayer = null
var _board: VBoxContainer = null
var _content_margin: MarginContainer = null
var _set_piece: CountSetPiece = null
var _paper: PanelContainer = null
var _scroll: ScrollContainer = null
var _headline_paper: PanelContainer = null
var _crew_section: VBoxContainer = null
var _holding_section: VBoxContainer = null
var _holding_count: int = 0
var _profile: Dictionary = {}
var _geometry: Dictionary = {}
var _logical_viewport := Vector2.ZERO
var _requested_window := Vector2i.ZERO
var _actual_window := Vector2i.ZERO


func _ready() -> void:
	layer = 20
	summary = Game.last_night.duplicate() if not Game.last_night.is_empty() else {}
	_build()
	_row_index = 0
	_row_time = 0.0
	# The counter runs under the tally and stops when the last line lands (audio-wave2 §1).
	_counter = AudioDirector.play(&"bill_counter", {"loop": true})


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content_margin,
			Vector4(48.0, 60.0, 48.0, 48.0))
	_logical_viewport = get_viewport().get_visible_rect().size
	_actual_window = DisplayServer.window_get_size()
	if _actual_window.x <= 0 or _actual_window.y <= 0:
		_actual_window = Vector2i(maxi(1, int(_logical_viewport.x)),
				maxi(1, int(_logical_viewport.y)))
	_requested_window = _requested_capture_size(_actual_window)
	_profile = _layout_profile()
	# Container sizes settle on the next layout pass. Publish after that pass so D4 receives
	# rectangles in the same logical coordinate space as the Count controls.
	call_deferred(&"_publish_geometry")


## Stable presentation anchors for subtitle/toast arbitration and capture tooling. The Count
## owns these reservations, but never decides where the global subtitle is drawn.
func geometry_contract() -> Dictionary:
	_publish_geometry()
	return _geometry.duplicate(true)


func geometry_snapshot() -> Dictionary:
	return geometry_contract()


func content_reservations() -> Dictionary:
	var snapshot := geometry_contract()
	return (snapshot.get("reservations", {}) as Dictionary).duplicate(true)


func profile_id() -> StringName:
	return _profile.get("id", &"compact") as StringName


func safe_content_rect() -> Rect2:
	var viewport := get_viewport().get_visible_rect().size
	return Presentation.safe.content_rect().intersection(Rect2(Vector2.ZERO, viewport))


func logical_viewport_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func requested_physical_size() -> Vector2i:
	return _requested_window if _requested_window != Vector2i.ZERO else DisplayServer.window_get_size()


func actual_physical_size() -> Vector2i:
	return _actual_window if _actual_window != Vector2i.ZERO else DisplayServer.window_get_size()


func _publish_geometry() -> void:
	if not is_inside_tree():
		return
	if _profile.is_empty():
		_profile = _layout_profile()
	var viewport_size := get_viewport().get_visible_rect().size
	_logical_viewport = viewport_size
	var safe := Presentation.safe.content_rect().intersection(Rect2(Vector2.ZERO, viewport_size))
	var paper_rect := _control_rect(_paper)
	var headline_rect := _control_rect(_headline_paper)
	var crew_rect := _control_rect(_crew_section)
	var holding_rect := _control_rect(_holding_section)
	var footer_rect := _control_rect(_buttons)
	var settings_rect := _control_rect(get_node_or_null("SafeContent/SettingsButton") as Control)
	# SettingsButton is nested below the outer VBox and therefore is not a direct child of the
	# CanvasLayer in the normal tree; resolve it by name when the direct path is unavailable.
	if settings_rect == Rect2():
		var settings := find_child("SettingsButton", true, false) as Control
		settings_rect = _control_rect(settings)
	var row_rects: Array[Rect2] = []
	for row: Dictionary in _rows:
		var row_node := row.get("node", null) as Control
		row_rects.append(_control_rect(row_node))
	var body_rect := _control_rect(_body)
	var exclusions: Array[Rect2] = []
	if body_rect.size.x > 0.0 and body_rect.size.y > 0.0:
		exclusions.append(body_rect)
	for rect: Rect2 in row_rects:
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			exclusions.append(rect)
	for rect: Rect2 in [headline_rect, crew_rect, holding_rect, footer_rect, settings_rect]:
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			exclusions.append(rect)
	var subtitle_bottom := footer_rect.position.y - 16.0 if footer_rect.size.y > 0.0 else safe.end.y
	var subtitle_top := headline_rect.end.y + 16.0 if headline_rect.size.y > 0.0 else safe.position.y
	var subtitle_region := Rect2(safe.position.x, subtitle_top, safe.size.x,
			maxf(0.0, subtitle_bottom - subtitle_top))
	_geometry = {
			"schema": "kingpin.count.geometry.v1",
			"profile": _profile.get("id", &"compact"),
			"profile_config": _profile.duplicate(true),
			"requested_physical_size": requested_physical_size(),
			"actual_physical_size": actual_physical_size(),
			"logical_viewport": viewport_size,
			"safe_margins": Presentation.safe.margins(),
			"safe_content": safe,
			"state": "finished" if finished() else "rolling",
			"holding_count": _holding_count,
			"headline_state": "final" if _headline_shown and not _headline_revealing else (
				"printing" if _headline_revealing else "pending"),
			"reservations": {
				"paper": paper_rect,
				"scroll_body": body_rect,
				"rows": row_rects,
				"headline": headline_rect,
				"roster": {
					"crew": crew_rect,
					"holding": holding_rect,
				},
				"crew": crew_rect,
				"holding": holding_rect,
				"footer": footer_rect,
				"settings": settings_rect,
				"footer_actions": _footer_action_rects(),
				"subtitle_safe_region": subtitle_region,
				"subtitle_exclusion_rects": exclusions,
			},
		}


func _control_rect(control: Control) -> Rect2:
	if control == null or not is_instance_valid(control) or not control.is_inside_tree():
		return Rect2()
	return control.get_global_rect()


func _requested_capture_size(actual: Vector2i) -> Vector2i:
	var raw := OS.get_environment("KINGPIN_REQUESTED_SIZE")
	if raw.is_empty():
		raw = OS.get_environment("KINGPIN_CAPTURE_REQUESTED_SIZE")
	if raw.is_empty():
		return actual
	var parts := raw.to_lower().replace(" ", "").split("x")
	if parts.size() != 2:
		return actual
	var width := int(parts[0])
	var height := int(parts[1])
	return Vector2i(width, height) if width > 0 and height > 0 else actual


func _footer_action_rects() -> Dictionary:
	if _buttons == null or not is_instance_valid(_buttons):
		return {}
	var actions := _buttons.get_node_or_null("Actions") as Control
	if actions == null:
		return {}
	var result := {}
	for child in actions.get_children():
		if child is Control:
			result[(child as Control).name.to_snake_case()] = (child as Control).get_global_rect()
	return result


func _paper_style() -> StyleBoxFlat:
	var material := Presentation.theme.material_for(&"aged_paper")
	var surface := Presentation.theme.surface_for(&"card")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(material["fill"] as Color, 1.0)
	style.border_color = material["border"] as Color
	style.set_border_width_all(int(surface["border_width"]))
	style.set_corner_radius_all(int(surface["radius"]))
	style.shadow_color = material["shadow"] as Color
	style.shadow_size = int(surface["elevation"]) * 3
	style.shadow_offset = Vector2(0.0, 4.0)
	style.content_margin_left = 28.0
	style.content_margin_right = 28.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	return style


func _receipt_style() -> StyleBoxFlat:
	var material := Presentation.theme.material_for(&"newsprint")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(material["fill"] as Color, 0.22)
	style.border_color = Color(Feel.COL_INK, 0.16)
	style.border_width_bottom = 1
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	return style


func _layout_profile() -> Dictionary:
	var actual := _actual_window
	if actual.x <= 0:
		actual = DisplayServer.window_get_size()
	var requested_profile := OS.get_environment("KINGPIN_COUNT_PROFILE").to_lower()
	var profile_id := &"compact" if actual.x < 720 else &"standard"
	if ReleaseChannel.allow_development_hooks() \
			and requested_profile in ["compact", "standard"]:
		profile_id = StringName(requested_profile)
	return Presentation.theme.layout_profile(profile_id)


func _build() -> void:
	_profile = _layout_profile()
	var bg := ColorRect.new()
	bg.color = Feel.COL_NEWSPRINT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var room := TextureRect.new()
	room.name = "CountRoomPlate"
	room.texture = Presentation.art.resolve(&"ui.count_room_plate", null, false)
	room.set_anchors_preset(Control.PRESET_FULL_RECT)
	room.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(room)
	var paper_wash := ColorRect.new()
	paper_wash.color = Color(Feel.COL_NEWSPRINT, 0.34)
	paper_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper_wash)
	_set_piece = CountSetPiece.new()
	_set_piece.name = "CountSetPiece"
	_set_piece.summary = summary
	_set_piece.set_anchors_preset(Control.PRESET_FULL_RECT)
	_set_piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_set_piece)

	_content_margin = MarginContainer.new()
	_content_margin.name = "SafeContent"
	_content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_margin)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	_content_margin.add_child(outer)

	var paper := PanelContainer.new()
	paper.name = "CountPaper"
	paper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	paper.clip_contents = true
	paper.add_theme_stylebox_override("panel", _paper_style())
	_paper = paper
	outer.add_child(paper)

	var scroll := ScrollContainer.new()
	scroll.name = "CountScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll = scroll
	paper.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	scroll.add_child(_body)

	var masthead := VBoxContainer.new()
	masthead.name = "Masthead"
	masthead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	var title := PaperKit.type_label("THE COUNT", &"title", Presentation.theme.ink)
	title.name = "Title"
	masthead.add_child(title)
	var details := HBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	var night := PaperKit.type_label(
			"NIGHT %02d" % int(summary.get("night", Game.night_no)), &"metadata",
			Presentation.theme.ink)
	night.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_child(night)
	var rank := PaperKit.type_label(String(Game.rank_title()).to_upper(), &"metadata",
			Presentation.theme.ink.lightened(0.18), HORIZONTAL_ALIGNMENT_RIGHT)
	rank.custom_minimum_size = Vector2(140.0, 0.0)
	details.add_child(rank)
	_tally_indicator = PaperKit.type_label("TALLY 00 / 00", &"micro",
			Presentation.theme.ink.lightened(0.18), HORIZONTAL_ALIGNMENT_RIGHT)
	_tally_indicator.custom_minimum_size = Vector2(190.0, 0.0)
	details.add_child(_tally_indicator)
	masthead.add_child(details)
	_body.add_child(masthead)
	_body.add_child(PaperKit.rule(Feel.COL_INK, 4.0))

	_build_safe_banner()
	_build_lines()

	_body.add_child(PaperKit.rule(Feel.COL_INK, 4.0))
	var headline_paper := PanelContainer.new()
	headline_paper.name = "HeadlineClipping"
	headline_paper.clip_contents = true
	headline_paper.custom_minimum_size = Vector2(0.0, 190.0)
	headline_paper.add_theme_stylebox_override("panel", _headline_style())
	_headline_paper = headline_paper
	var headline_column := VBoxContainer.new()
	headline_column.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	headline_paper.add_child(headline_column)
	var headline_kicker := PaperKit.type_label("TONIGHT'S EDITION", &"micro",
			Presentation.theme.ink.lightened(0.18))
	headline_kicker.name = "Kicker"
	headline_column.add_child(headline_kicker)
	_headline_placeholder = PaperKit.type_label("THE STORY IS DEVELOPING", &"section",
			Presentation.theme.ink.lightened(0.20))
	_headline_placeholder.name = "Pending"
	_headline_placeholder.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline_placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	headline_column.add_child(_headline_placeholder)
	_headline = PaperKit.type_label("", &"section", Presentation.theme.ink)
	_headline.name = "Headline"
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_headline.visible = false
	headline_column.add_child(_headline)
	_body.add_child(headline_paper)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 8)
	_body.add_child(_roster)
	_build_roster()

	_board = VBoxContainer.new()
	_board.add_theme_constant_override("separation", 6)
	_body.add_child(_board)
	_build_board()

	# The Commission's call sits above the spacer, so it is always on the page: below the
	# buttons it could be pushed off the bottom of a tall tally.
	_build_boss_call()
	_build_war_room()
	_build_train()

	_buttons = PaperKit.bottom_action_bar("NEXT NIGHT", "THE LEDGER")
	_buttons.name = "BottomActionBar"
	_buttons.custom_minimum_size = Vector2(0.0, float(_layout_profile().get("footer_height", 112.0)))
	outer.add_child(_buttons)
	var actions := _buttons.get_node("Actions") as HBoxContainer
	var ledger := actions.get_node("Secondary") as Button
	ledger.pressed.connect(func() -> void: ledger_pressed.emit())
	var next := actions.get_node("Primary") as Button
	next.pressed.connect(func() -> void: next_night_pressed.emit())

	var settings_button := PaperKit.action_button("HOUSE RULES", &"quiet")
	settings_button.name = "SettingsButton"
	settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	outer.add_child(settings_button)
	_update_tally_indicator()
	call_deferred(&"_publish_geometry")


func _headline_style() -> StyleBoxFlat:
	var material := Presentation.theme.material_for(&"newsprint")
	var style := StyleBoxFlat.new()
	style.bg_color = Color(material["fill"] as Color, 1.0)
	style.border_color = Color(Feel.COL_INK, 0.34)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 18.0
	style.content_margin_bottom = 18.0
	return style


## THE COMMISSION. The ☆ are in the bank and a rival family wants a word: the next Night is
## the fight, and it stands apart from the ordinary buttons in his own colour so it can never
## be pressed by muscle memory (docs/05 §6 — the fight is a decision, not a step).
func _build_boss_call() -> void:
	var f := Game.boss_waiting()
	if f.is_empty():
		return
	var again := Game.commission.attempts_at(StringName(f["id"])) > 0
	var call_text := String(f.get("call", "THE COMMISSION IS ASKING"))
	if again:
		call_text = "%s   ·   AGAIN" % call_text
	var b := PaperKit.button(call_text, PaperKit.FONT_BIG, Feel.COL_DIRTY)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: boss_pressed.emit())
	_body.add_child(b)
	_body.add_child(PaperKit.label(
			"NO EARNING. NO CLOCK. BEAT HIM AND THE RANK IS YOURS.",
			PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))


## THE WAR ROOM (docs/05 §5). One button per job that is actually on the board tonight, each
## with what it will cost to set up; the approach and the inside man are picked for you until
## the planning screen lands (TODO(UI): target + approach + crew picker).
func _build_war_room() -> void:
	if not Game.heists_unlocked():
		return
	var offered := 0
	for row in Game.heists.board(Game.night_no):
		if not bool(row["available"]) or offered >= HEIST_SLOTS:
			continue
		offered += 1
		var target := StringName(row["id"])
		var stake := Heists.stake_for(target, Game.stats.idle_rate_total())
		var guy := _inside_man()
		var b := PaperKit.button("%s   ·   %s" % [String(row["name"]), stake.text()],
				PaperKit.FONT_BODY, Feel.COL_CLEAN)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not Game.wallet.can_afford_dirty(stake)
		b.pressed.connect(func() -> void:
			heist_pressed.emit(target, Heists.QUIET, guy))
		_body.add_child(b)
		var who := "" if guy.is_empty() else "   ·   INSIDE MAN: %s" % String(guy.get("name", ""))
		_body.add_child(PaperKit.label("%s%s" % [String(row["blurb"]), who],
				PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))


## The best man for the job: whoever on the Bench has a trait the war room can use.
func _inside_man() -> Dictionary:
	if Game.bench == null:
		return {}
	var free := Game.bench.available()
	for g in free:
		if not Heists.inside_man_effect(g).is_empty():
			return g
	return free[0] if not free.is_empty() else {}


## SKIP TOWN (docs/06 §1). Never a step, never in the flow of the ordinary buttons, and it
## says out loud what it costs — a player has to be able to read this and still want it.
func _build_train() -> void:
	if not Game.skip_town_available():
		return
	var preview := Game.skip_town_preview()
	var keep := _inside_man()
	var b := PaperKit.button("SKIP TOWN   ·   %d JUICE" % int(preview["juice"]),
			PaperKit.FONT_BIG, Feel.COL_BRASS)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: skip_town_pressed.emit(keep))
	_body.add_child(b)
	var line := "EVERYTHING GOES. THE BOOK, THE JUICE AND ONE GUY COME WITH YOU"
	if not keep.is_empty():
		line += "   ·   %s" % String(keep.get("name", ""))
	if Game.federal.raids_lost > 0:
		line = "THE CITY IS CLOSING IN.   " + line
	_body.add_child(PaperKit.label(line, PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))


## Tonight's work, and the Consigliere's rerolls (`job_reroll_add`). Only drawn when there is
## a reroll to spend — an un-hired career sees the board it always saw.
func _build_board() -> void:
	for c in _board.get_children():
		c.queue_free()
	if Game.night_rerolls <= 0:
		return
	var slips := Game.jobs.active_jobs()
	if slips.is_empty():
		return
	_board.add_child(PaperKit.label("THE BOARD   ·   %d REROLL%s" % [Game.night_rerolls,
			"" if Game.night_rerolls == 1 else "S"], PaperKit.FONT_SMALL,
			Feel.COL_INK.lightened(0.35)))
	for i in range(slips.size()):
		var slip: Dictionary = slips[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label := PaperKit.label(String(slip.get("name", slip.get("id", "job"))),
				PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var b := PaperKit.button("REROLL", PaperKit.FONT_SMALL, Feel.COL_BRASS.darkened(0.2))
		b.pressed.connect(_on_reroll.bind(i))
		row.add_child(b)
		_board.add_child(row)


func _on_reroll(index: int) -> void:
	if not Game.reroll_job(index).is_empty():
		_build_board()


## The Safe: offline earnings waiting since last session (docs/03 §6).
func _build_safe_banner() -> void:
	if Game.safe_pending == null or not Game.safe_pending.is_positive():
		return
	_safe = PaperKit.panel(Feel.COL_INK, Feel.COL_BRASS)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_safe.add_child(row)
	var text := PaperKit.label("THE SAFE  " + Game.safe_pending.text(),
			PaperKit.FONT_BODY, Feel.COL_BRASS)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var collect := PaperKit.button("COLLECT", PaperKit.FONT_BODY)
	collect.pressed.connect(_on_collect_safe)
	row.add_child(collect)
	_body.add_child(_safe)


func _on_collect_safe() -> void:
	Game.collect_safe()
	if _safe != null and is_instance_valid(_safe):
		_safe.queue_free()
		_safe = null


func _build_lines() -> void:
	_rows.clear()
	_add_money_row("DIRTY EARNED", summary.get("dirty", BigMoney.zero()), Feel.COL_DIRTY)
	_add_money_row("LAUNDERED TONIGHT", summary.get("laundered", BigMoney.zero()), Feel.COL_CLEAN)
	if _money(summary.get("pocket", null)).is_positive():
		_add_money_row("   incl. pocket money", summary.get("pocket", BigMoney.zero()),
				Feel.COL_INK.lightened(0.35), PaperKit.FONT_SMALL)
	# Teach the wash where the player feels it (device feedback: "how do I get clean
	# cash?"). Only until the first washer is bought; then the machine speaks for itself.
	if Game.stats.launder_rate() <= 0.0:
		var tip := "the first %s washes itself each night — the rest needs a front" \
				% Game.pocket_money().text()
		if Game.wallet.dirty.cmp(BigMoney.parse("1K")) > 0:
			tip = "word around the block: Lucky's coin-op washer takes dirty money — check THE LEDGER"
		var tip_label := PaperKit.label(tip, PaperKit.FONT_SMALL, Feel.COL_CLEAN.darkened(0.15))
		tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_body.add_child(tip_label)
	if _money(summary.get("raid_payout", null)).is_positive():
		_add_money_row("BEAT THE RAP", summary.get("raid_payout", BigMoney.zero()), Feel.COL_CLEAN)
	if _money(summary.get("confiscated", null)).is_positive():
		_add_money_row("CONFISCATED", summary.get("confiscated", BigMoney.zero()), Feel.COL_DIRTY)
	if bool(summary.get("insured", false)):
		_body.add_child(PaperKit.label("THE POLICY COVERED IT — NOTHING WAS TAKEN",
				PaperKit.FONT_SMALL, Feel.COL_CLEAN))
	_build_boss_lines()
	_build_club_lines()
	_build_endgame_lines()
	_add_money_row("CLEAN BALANCE", summary.get("clean", Game.wallet.clean), Feel.COL_CLEAN)
	_add_int_row("RESPECT GAINED", int(summary.get("respect", 0)), Feel.COL_BRASS.darkened(0.25))
	_add_int_row("JOBS DONE", int(summary.get("jobs_done", 0)), Feel.COL_INK)
	for name: Variant in summary.get("jobs", []):
		_body.add_child(PaperKit.label("   " + String(name), PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))


## The Commission's night, when there was one. A win is the loudest line on the page: the
## purse, the spoil that cannot be bought, and the rank it just unlocked. A loss is one line
## and no scolding — the rematch is on the button below (docs/05 §6).
func _build_boss_lines() -> void:
	var boss: Dictionary = summary.get("boss", {})
	if boss.is_empty() or String(boss.get("id", "")).is_empty():
		return
	var who := String(boss.get("name", "THE COMMISSION"))
	if bool(boss.get("won", false)):
		_add_money_row("%s — BEATEN" % who, boss.get("purse", null), Feel.COL_CLEAN)
		var spoil := String(boss.get("spoil_name", ""))
		if not spoil.is_empty():
			_body.add_child(PaperKit.label("   TOOK HIS %s" % spoil, PaperKit.FONT_SMALL,
					Feel.COL_BRASS))
		if _money(summary.get("boss_paid", null)).cmp(_money(boss.get("purse", null))) > 0:
			_add_money_row("   incl. cold storage", summary.get("boss_paid", null),
					Feel.COL_CLEAN, PaperKit.FONT_SMALL)
	else:
		_body.add_child(PaperKit.label("%s IS STILL STANDING" % who, PaperKit.FONT_BODY,
				Feel.COL_DIRTY))


## The M2 modes, each only when it happened. The casino gets three numbers because a
## gambler reads all three: what went in, what came out, and how much of it came out clean.
func _build_club_lines() -> void:
	var casino: Dictionary = summary.get("casino", {})
	if int(casino.get("spins", 0)) > 0:
		_add_money_row("CASINO STAKED", casino.get("staked", null), Feel.COL_DIRTY)
		_add_money_row("   won  (%d of %d spins)" % [int(casino.get("wins", 0)),
				int(casino.get("spins", 0))], casino.get("won", null), Feel.COL_BRASS,
				PaperKit.FONT_SMALL)
		if _money(casino.get("washed", null)).is_positive():
			_add_money_row("   washed clean", casino.get("washed", null), Feel.COL_CLEAN,
					PaperKit.FONT_SMALL)
		if int(casino.get("jackpots", 0)) > 0:
			_add_int_row("   JACKPOTS", int(casino.get("jackpots", 0)), Feel.COL_BRASS,
					PaperKit.FONT_SMALL)

	var meeting: Dictionary = summary.get("meeting", {})
	if int(meeting.get("meetings", 0)) > 0:
		_add_int_row("FAMILY MEETINGS", int(meeting.get("meetings", 0)), Feel.COL_BRASS)
		if _money(meeting.get("paid", null)).is_positive():
			_add_money_row("   back room", meeting.get("paid", null), Feel.COL_CLEAN,
					PaperKit.FONT_SMALL)
	elif bool(meeting.get("lit", false)):
		_body.add_child(PaperKit.label("BACK ROOM STILL LIT", PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))

	var wire: Dictionary = summary.get("wire", {})
	if int(wire.get("draws", 0)) > 0:
		_add_int_row("WIRE DRAWS", int(wire.get("draws", 0)), Feel.COL_INK)
		if int(wire.get("hits", 0)) > 0:
			_add_money_row("   %d hit%s (%d exact)" % [int(wire.get("hits", 0)),
					"" if int(wire.get("hits", 0)) == 1 else "s", int(wire.get("exacts", 0))],
					wire.get("won", null), Feel.COL_BRASS, PaperKit.FONT_SMALL)

	var rounds: Dictionary = summary.get("collection", {})
	if int(rounds.get("rounds", 0)) > 0:
		_add_int_row("COLLECTION ROUNDS RUN", int(rounds.get("rounds", 0)), Feel.COL_INK)
		_add_int_row("   perfect", int(rounds.get("won", 0)), Feel.COL_CLEAN,
				PaperKit.FONT_SMALL)


## The M3 lines, each only when it happened. Same rule as the Club's: a mode that did not
## run does not get a row saying it did not run.
func _build_endgame_lines() -> void:
	var docks: Dictionary = summary.get("smuggling", {})
	if int(docks.get("shipments", 0)) > 0:
		_add_money_row("SHIPMENTS OUT   ·   %d" % int(docks.get("shipments", 0)),
				docks.get("paid", null), Feel.COL_DIRTY)
	elif int(docks.get("runs", 0)) > 0:
		_body.add_child(PaperKit.label("THE SHIPMENT DID NOT MAKE IT", PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))

	var job: Dictionary = summary.get("heist", {})
	if not job.is_empty() and not String(job.get("name", "")).is_empty():
		var line := "%s — %s" % [String(job["name"]),
				"CLEARED" if bool(job.get("cleared", false)) else "BLOWN OUT"]
		_add_money_row(line, job.get("paid", null), Feel.COL_CLEAN)
		if int(job.get("blown", 0)) > 0:
			_body.add_child(PaperKit.label("   %d beat%s got away" % [int(job["blown"]),
					"" if int(job["blown"]) == 1 else "s"], PaperKit.FONT_SMALL,
					Feel.COL_INK.lightened(0.35)))
		if not String(job.get("relic", "")).is_empty():
			_body.add_child(PaperKit.label("   SOMETHING FOR THE COLLECTION",
					PaperKit.FONT_SMALL, Feel.COL_BRASS))

	var chairs: Dictionary = summary.get("chairs", {})
	if int(chairs.get("tonight", 0)) > 0:
		_add_int_row("CHAIRS CLAIMED   ·   %d of %d" % [int(chairs.get("claimed", 0)),
				int(chairs.get("chairs", CommissionChairs.CHAIRS))],
				int(chairs.get("tonight", 0)), Feel.COL_BRASS)

	var election: Dictionary = summary.get("election", {})
	if int(election.get("term_left", 0)) > 0:
		_add_int_row("CITY HALL   ·   NIGHTS LEFT IN THE TERM",
				int(election["term_left"]), Feel.COL_BRASS)
	elif int(election.get("lit", 0)) > 0:
		_add_int_row("DISTRICTS CANVASSED   ·   of %d" % int(election.get("districts", 5)),
				int(election["lit"]), Feel.COL_INK)

	var crown: Dictionary = summary.get("empire", {})
	if int(crown.get("runs", 0)) > 0:
		_add_money_row("EMPIRE MODE   ·   %d" % int(crown["runs"]), crown.get("paid", null),
				Feel.COL_BRASS)

	if _money(summary.get("rico_payout", null)).is_positive():
		_add_money_row("UNTOUCHABLE", summary.get("rico_payout", null), Feel.COL_CLEAN)
	elif String(summary.get("rico", "")) == "lost":
		_body.add_child(PaperKit.label("THE CASE STICKS", PaperKit.FONT_BODY, Feel.COL_DIRTY))

	var cases: Dictionary = summary.get("briefcases", {})
	if int(cases.get("opened", 0)) > 0:
		_add_money_row("BRIEFCASES   ·   %d" % int(cases["opened"]), cases.get("paid", null),
				Feel.COL_DIRTY)
		if int(cases.get("setups", 0)) > 0:
			_body.add_child(PaperKit.label("   %d of them were a setup"
					% int(cases["setups"]), PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))
	if int(cases.get("missed", 0)) > 0:
		_body.add_child(PaperKit.label("HE LEFT WITH IT", PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))

	var calls: Dictionary = summary.get("phone", {})
	if int(calls.get("answered", 0)) > 0:
		_add_int_row("CALLS TAKEN", int(calls["answered"]), Feel.COL_INK)

	var rat: Dictionary = summary.get("rat", {})
	if bool(rat.get("caught", false)):
		_body.add_child(PaperKit.label("THE RAT IS FLIPPED", PaperKit.FONT_BODY, Feel.COL_CLEAN))
	elif _money(rat.get("skimmed", null)).is_positive():
		_add_money_row("SOMEBODY IS SKIMMING", rat.get("skimmed", null), Feel.COL_DIRTY)

	var fbi: Dictionary = summary.get("federal", {})
	if bool(fbi.get("enabled", false)) and float(fbi.get("value", 0.0)) > 0.0:
		_add_int_row("FEDERAL HEAT   ·   of 200", int(round(float(fbi.get("meter", 100.0)))),
				Color("6EA8FF"))


func _add_money_row(text: String, value: Variant, color: Color, size: int = PaperKit.FONT_BODY) -> void:
	_rows.append(_row(text, color, size, _money(value), 0))


func _add_int_row(text: String, value: int, color: Color, size: int = PaperKit.FONT_BODY) -> void:
	_rows.append(_row(text, color, size, null, value))


static func _money(v: Variant) -> BigMoney:
	return v if v is BigMoney else BigMoney.zero()


func _row(text: String, color: Color, size: int, money: BigMoney, count: int) -> Dictionary:
	# Every tally line receives its final footprint while the sheet is built. Empty windows
	# therefore never cause the headline, crew or footer to jump when the count finishes.
	var line := PanelContainer.new()
	line.name = "ReceiptRow_%d" % _rows.size()
	line.custom_minimum_size = Vector2(0.0, 84.0 if size <= PaperKit.FONT_SMALL else 92.0)
	line.set_meta("count_row_index", _rows.size())
	line.set_meta("count_row_value_kind", "money" if money != null else "count")
	line.set_meta("count_row_final_height", line.custom_minimum_size.y)
	line.add_theme_stylebox_override("panel", _receipt_style())
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation",
			int(Presentation.theme.spacing_for(&"space_16")))
	line.add_child(content)
	var left := PaperKit.type_label(text.strip_edges(), &"body", Presentation.theme.ink)
	if size <= PaperKit.FONT_SMALL:
		left = PaperKit.type_label(text.strip_edges(), &"caption", Presentation.theme.ink)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left.clip_text = false
	content.add_child(left)
	var right := PaperKit.type_label("", &"primary_value", color, HORIZONTAL_ALIGNMENT_RIGHT)
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	right.clip_text = false
	var meter := CountOdometerFace.new()
	meter.name = "Odometer"
	meter.custom_minimum_size = Vector2(300.0, 72.0)
	meter.size_flags_horizontal = Control.SIZE_SHRINK_END
	meter.set_tint(color)
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	meter.add_child(right)
	content.add_child(meter)
	_body.add_child(line)
	return {"node": line, "label": right, "money": money, "count": count}


func _build_roster() -> void:
	_crew_section = null
	_holding_section = null
	_holding_count = 0
	while _roster.get_child_count() > 0:
		var old := _roster.get_child(0)
		_roster.remove_child(old)
		old.queue_free()
	_build_crew_strip()
	var held: Array[Dictionary] = []
	if Game.bench != null:
		held = Game.bench.holding()
	if held.is_empty():
		call_deferred(&"_publish_geometry")
		return
	_holding_section = VBoxContainer.new()
	_holding_count = held.size()
	_holding_section.name = "HoldingSection"
	_holding_section.add_theme_constant_override("separation", int(
			Presentation.theme.spacing_for(&"space_8")))
	_roster.add_child(_holding_section)
	var holding_header := PaperKit.type_label("IN HOLDING", &"metadata",
			Presentation.theme.ink.lightened(0.18))
	holding_header.name = "HoldingHeader"
	_holding_section.add_child(holding_header)
	var holding_hint := PaperKit.type_label("DIRTY CASH ONLY · BAIL NOW OR WAIT",
			&"caption", Presentation.theme.ink.lightened(0.18))
	holding_hint.name = "HoldingHint"
	holding_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_holding_section.add_child(holding_hint)
	for index in held.size():
		var guy: Dictionary = held[index]
		var row := HBoxContainer.new()
		row.name = "HoldingRow_%d" % index
		row.custom_minimum_size = Vector2(0.0, 96.0)
		row.add_theme_constant_override("separation", 16)
		# Waiting is normal, not a fail state (device feedback): every held guy says when
		# he walks on his own, so bail reads as the impatience tax it is.
		var nights := maxi(int(guy.get("sit_out", 1)), 1)
		var walks := "walks next night" if nights <= 1 else "walks in %d nights" % nights
		var name_label := PaperKit.label("%s   ·  %s" % [String(guy["name"]), walks],
				PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.clip_text = false
		row.add_child(name_label)
		# Through `Game`, not the Bench: Cohen's discount is the session's, not the roster's.
		var cost := Game.bail_cost(guy)
		var affordable := Game.wallet.can_afford_dirty(cost)
		var b := PaperKit.button("BAIL " + cost.text(), PaperKit.FONT_SMALL, Feel.COL_DIRTY)
		b.name = "BailButton_%d" % index
		b.custom_minimum_size = Vector2(190.0, 96.0)
		b.disabled = not affordable
		if not affordable:
			b.tooltip_text = "dirty cash only — you're short"
		b.pressed.connect(_on_bail.bind(guy))
		row.add_child(b)
		_holding_section.add_child(row)
		if not affordable:
			var short := PaperKit.type_label("SHORT ON DIRTY CASH", &"caption", Feel.COL_DIRTY)
			short.name = "BailStatus_%d" % index
			_holding_section.add_child(short)
	call_deferred(&"_publish_geometry")


## Who was out tonight, with the one line each of them has (docs/01 §4: one visible trait
## line, never a menu). A guy who came in through the back room is marked as such — he was
## not on the card at roll call.
func _build_crew_strip() -> void:
	var crew: Variant = summary.get("guys", [])
	if not (crew is Array) or (crew as Array).is_empty():
		return
	_crew_section = VBoxContainer.new()
	_crew_section.name = "CrewSection"
	_crew_section.add_theme_constant_override("separation", int(
			Presentation.theme.spacing_for(&"space_4")))
	_roster.add_child(_crew_section)
	var crew_header := PaperKit.type_label("TONIGHT'S CREW", &"metadata",
			Presentation.theme.ink.lightened(0.18))
	crew_header.name = "CrewHeader"
	_crew_section.add_child(crew_header)
	for index in crew.size():
		var raw: Variant = (crew as Array)[index]
		if not (raw is Dictionary):
			continue
		var g: Dictionary = raw
		var row := HBoxContainer.new()
		row.name = "CrewRow_%d" % index
		row.add_theme_constant_override("separation", 16)
		var who := String(g.get("name", ""))
		if bool(g.get("meeting", false)):
			who += "  (family meeting)"
		var name_label := PaperKit.label(who, PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.clip_text = false
		row.add_child(name_label)
		var trait_id := String(g.get("trait", ""))
		var trait_label := PaperKit.type_label(GuyTraits.label(trait_id).to_upper(), &"caption",
				Feel.COL_BRASS.darkened(0.2),
				HORIZONTAL_ALIGNMENT_RIGHT)
		trait_label.name = "Trait"
		row.add_child(trait_label)
		_crew_section.add_child(row)
	_crew_section.add_child(PaperKit.spacer(10.0))


func _on_bail(guy: Dictionary) -> void:
	if Game.bail_guy(guy):
		_build_roster()


# --- the roll-up --------------------------------------------------------------


func _process(delta: float) -> void:
	if _reduced_motion() and not finished():
		skip()
		return
	if _headline_revealing:
		_advance_headline(delta)
		return
	if _row_index < 0 or _row_index >= _rows.size():
		if not _headline_shown:
			_show_headline()
		return
	_row_time += delta
	_tick_time += delta
	var t := clampf(_row_time / LINE_TIME, 0.0, 1.0)
	_paint_row(_rows[_row_index], t)
	_update_tally_indicator()
	if _tick_time >= TICK_INTERVAL and t < 1.0:
		_tick_time = 0.0
		AudioDirector.play(&"cash_tick")
	if _row_time >= LINE_TIME + LINE_GAP:
		_row_index += 1
		_row_time = 0.0
		AudioDirector.play(&"coin_drop")


func _paint_row(row: Dictionary, t: float) -> void:
	var l: Label = row["label"]
	if not is_instance_valid(l):
		return
	var money: Variant = row["money"]
	if money is BigMoney:
		l.text = (money as BigMoney).mul(t).text()
	else:
		l.text = str(int(round(float(int(row["count"])) * t)))
	if _set_piece != null:
		_set_piece.roll_progress = clampf((float(_row_index) + t) / maxf(float(_rows.size()), 1.0), 0.0, 1.0)


## True once every line has rolled up and the paper has printed.
func finished() -> bool:
	return _headline_shown and not _headline_revealing


## Tap anywhere to stop the theatre and see the numbers — the ritual is a gift, not a toll.
func _input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not tapped:
		return
	if _headline_revealing:
		_finish_headline()
		return
	if _row_index >= 0 and _row_index < _rows.size():
		skip()


## Finish every roll-up now.
func skip() -> void:
	if _headline_revealing:
		_finish_headline()
		return
	for row in _rows:
		_paint_row(row, 1.0)
	_row_index = _rows.size()
	_update_tally_indicator()
	_show_headline(true)
	# A deliberate tap is the old skip gesture: it still finishes the entire ceremony in the
	# same frame, while an unattended Count gets the staged typewriter reveal.
	_finish_headline()


func _show_headline(force_immediate: bool = false) -> void:
	if _headline_shown:
		return
	_headline_shown = true
	_stop_counter()
	for row in _rows:
		_paint_row(row, 1.0)
	_headline_target = String(summary.get("headline", ""))
	_headline_elapsed = 0.0
	_headline_stung = false
	if _set_piece != null:
		_set_piece.roll_progress = 1.0
	if _headline_placeholder != null:
		_headline_placeholder.visible = false
	if force_immediate or _reduced_motion() or _headline_target.is_empty():
		_finish_headline()
		return
	_headline.text = ""
	_headline.visible = true
	_headline.modulate.a = 0.0
	_headline_revealing = true
	AudioDirector.play(&"paper_slip")
	call_deferred(&"_publish_geometry")


func _advance_headline(delta: float) -> void:
	_headline_elapsed += delta
	var print_time := _headline_elapsed - HEADLINE_DELAY
	if print_time <= 0.0:
		return
	var count := mini(_headline_target.length(), maxi(1, int(floor(print_time / HEADLINE_CHAR_TIME))))
	_headline.text = _headline_target.left(count)
	_headline.modulate.a = clampf(print_time / 0.12, 0.0, 1.0)
	if count >= _headline_target.length():
		_finish_headline()


func _finish_headline() -> void:
	if not _headline_shown:
		return
	_headline_revealing = false
	_headline.visible = true
	_headline.text = _headline_target
	_headline.modulate.a = 1.0
	if not _headline_stung:
		_headline_stung = true
		AudioDirector.play(&"headline_sting")
	call_deferred(&"_publish_geometry")


func _update_tally_indicator() -> void:
	if _tally_indicator == null:
		return
	var total := _rows.size()
	var done := total if _headline_shown else clampi(_row_index, 0, total)
	_tally_indicator.text = "TALLY %02d / %02d" % [done, total]


func _reduced_motion() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_motion


func _stop_counter() -> void:
	if _counter != null and is_instance_valid(_counter):
		_counter.stop()
	_counter = null


## The screen can be torn down mid-tally (NEXT NIGHT on the first frame).
func _exit_tree() -> void:
	_stop_counter()
