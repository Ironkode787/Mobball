class_name RollCallScreen
extends CanvasLayer
## PRE-NIGHT ROLL CALL — the player chooses the ordered balls for the Night. This is a
## screen, not a pause menu: once Start is pressed it is torn down with the usual flow state.

signal start_pressed(lineup: Array[Dictionary])
## Hook for the ball-design lane. A preview renderer may listen and replace the slot Control,
## or callers may provide a factory taking one guy Dictionary and returning a Control.
signal ball_preview_requested(guy: Dictionary)

const MAX_GUYS := 3

var available: Array[Dictionary] = []
var selected: Array[Dictionary] = []
var ball_preview_factory: Callable = Callable()

var _crew: VBoxContainer = null
var _crew_buttons: Array[Button] = []
var _crew_cards: Array[PanelContainer] = []
var _crew_status_labels: Array[Label] = []
var _crew_order_badges: Array[Label] = []
var _crew_order_badge_panels: Array[PanelContainer] = []
var _selection_label: Label = null
var _serve_order_slots: Array[PanelContainer] = []
var _serve_order_names: Array[Label] = []
var _serve_order_states: Array[Label] = []
var _start: Button = null
var _content_margin: MarginContainer = null


func _ready() -> void:
	layer = 20
	available = Game.bench.available() if Game.bench != null else []
	var want := mini(MAX_GUYS, available.size())
	selected = []
	for i in want:
		selected.append(available[i])
	_build()


## The ball-design lane can install its renderer without owning this screen's selection or
## layout. The factory is called once for each visible guy on rebuild.
func set_ball_preview_factory(factory: Callable) -> void:
	ball_preview_factory = factory
	if is_node_ready():
		_build_crew()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Feel.COL_INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_content_margin = MarginContainer.new()
	_content_margin.name = "SafeContent"
	_content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_margin)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	_content_margin.add_child(outer)
	outer.add_child(PaperKit.label("ROLL CALL", PaperKit.FONT_TITLE, Feel.COL_BRASS))
	outer.add_child(PaperKit.rule())
	var explain := PaperKit.label(
		"EACH GUY IS ONE BALL. A DRAIN PUTS HIM IN HOLDING.\nPICK THE ORDER THEY SERVE TONIGHT.",
		PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT)
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(explain)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)

	body.add_child(PaperKit.label("TONIGHT'S WORK", PaperKit.FONT_BIG, Feel.COL_BRASS))
	var board_plate := TextureRect.new()
	board_plate.name = "JobBoardPlate"
	board_plate.texture = Presentation.art.resolve(&"ui.job_board", null, false)
	board_plate.custom_minimum_size = Vector2(0.0, 130.0)
	board_plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board_plate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	board_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(board_plate)
	for job: Dictionary in Game.jobs.active_jobs():
		body.add_child(_job_slip(job))
	body.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.4)))
	body.add_child(PaperKit.label("TONIGHT'S CREW", PaperKit.FONT_BIG, Feel.COL_BRASS))
	_build_serve_order(body)
	_crew = VBoxContainer.new()
	_crew.add_theme_constant_override("separation", 10)
	body.add_child(_crew)
	_build_crew()
	_build_specialists(body)

	_start = PaperKit.button("START NIGHT", PaperKit.FONT_BIG, Feel.COL_CLEAN)
	_start.pressed.connect(_on_start)
	outer.add_child(_start)
	_refresh()


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content_margin,
			Vector4(42.0, 42.0, 42.0, 34.0))


func _job_slip(job: Dictionary) -> PanelContainer:
	var slip := PaperKit.panel(Feel.COL_NEWSPRINT.darkened(0.07), Feel.COL_BRASS)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	slip.add_child(col)
	var title := PaperKit.label(String(job.get("name", "")), PaperKit.FONT_BODY, Feel.COL_INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var desc := PaperKit.label(String(job.get("desc", "")), PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.12))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc)
	var meta := PaperKit.label("RESPECT +%d    SCOPE: %s" % [int(job.get("respect", 0)), scope_for_job(job)],
		PaperKit.FONT_SMALL, Feel.COL_BRASS.darkened(0.3))
	col.add_child(meta)
	return slip


## The hand is an authored part of the roll-call ceremony. Three fixed slots make the
## append-only selection rule legible before a player ever touches a crew card.
func _build_serve_order(body: VBoxContainer) -> void:
	var panel := PaperKit.panel(Feel.COL_INK.lightened(0.06), Feel.COL_BRASS.darkened(0.25))
	panel.name = "ServeOrder"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel.add_child(col)
	_selection_label = PaperKit.label("SERVE ORDER", PaperKit.FONT_BODY, Feel.COL_BRASS)
	col.add_child(_selection_label)
	var order_hint := PaperKit.label("LEFT TO RIGHT · SELECTIONS SERVE IN THIS ORDER",
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.16))
	order_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	order_hint.clip_text = true
	col.add_child(order_hint)
	var rail := HBoxContainer.new()
	rail.name = "ServeOrderRail"
	rail.add_theme_constant_override("separation", 8)
	col.add_child(rail)
	_serve_order_slots.clear()
	_serve_order_names.clear()
	_serve_order_states.clear()
	for i in MAX_GUYS:
		var slot := PanelContainer.new()
		slot.name = "ServeSlot%d" % (i + 1)
		slot.custom_minimum_size = Vector2(0.0, 94.0)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel", _serve_slot_box(false))
		var slot_col := VBoxContainer.new()
		slot_col.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_col.add_theme_constant_override("separation", 2)
		slot.add_child(slot_col)
		var number := PaperKit.label(str(i + 1), PaperKit.FONT_TITLE, Feel.COL_BRASS,
				HORIZONTAL_ALIGNMENT_CENTER)
		number.custom_minimum_size = Vector2(0.0, 55.0)
		slot_col.add_child(number)
		var name_label := PaperKit.label("OPEN", PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT,
				HORIZONTAL_ALIGNMENT_CENTER)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size = Vector2(0.0, 32.0)
		slot_col.add_child(name_label)
		var state_label := PaperKit.label("PICK A GUY", PaperKit.FONT_SMALL,
				Feel.COL_NEWSPRINT.darkened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
		state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot_col.add_child(state_label)
		rail.add_child(slot)
		_serve_order_slots.append(slot)
		_serve_order_names.append(name_label)
		_serve_order_states.append(state_label)
	body.add_child(panel)


func _serve_slot_box(occupied: bool) -> StyleBoxFlat:
	var fill := Feel.COL_CLEAN.darkened(0.62) if occupied else Feel.COL_INK.lightened(0.12)
	var border := Feel.COL_CLEAN if occupied else Feel.COL_BRASS.darkened(0.35)
	return PaperKit.box(fill, border, 3.0 if occupied else 2.0)


func _build_crew() -> void:
	if _crew == null:
		return
	for child in _crew.get_children():
		child.queue_free()
	_crew_buttons.clear()
	_crew_cards.clear()
	_crew_status_labels.clear()
	_crew_order_badges.clear()
	_crew_order_badge_panels.clear()
	for i in available.size():
		var guy: Dictionary = available[i]
		var card := _make_crew_card(i, guy)
		_crew_cards.append(card)
		_crew.add_child(card)
	_refresh()


func _make_crew_card(index: int, guy: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "CrewCard_%02d" % (index + 1)
	card.custom_minimum_size = Vector2(0.0, 190.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_meta("guy_id", int(guy.get("id", -1)))
	card.add_theme_stylebox_override("panel", _crew_card_box(false))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)

	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.custom_minimum_size = Vector2(128.0, 158.0)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override("panel", PaperKit.box(
			Feel.COL_INK.lightened(0.03), Feel.COL_BRASS.darkened(0.3), 2.0))
	portrait_frame.add_child(_make_portrait(index, guy))
	row.add_child(portrait_frame)

	var ball_col := VBoxContainer.new()
	ball_col.name = "BallIdentity"
	ball_col.custom_minimum_size = Vector2(96.0, 0.0)
	ball_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ball_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ball_col.alignment = BoxContainer.ALIGNMENT_CENTER
	ball_col.add_theme_constant_override("separation", 2)
	ball_col.add_child(PaperKit.label("BALL", PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.3),
			HORIZONTAL_ALIGNMENT_CENTER))
	var preview := _make_preview(guy)
	preview.custom_minimum_size = Vector2(92.0, 92.0)
	ball_col.add_child(preview)
	ball_col.add_child(PaperKit.label("ID %02d" % int(guy.get("id", 0)), PaperKit.FONT_SMALL,
			Feel.COL_INK.lightened(0.3), HORIZONTAL_ALIGNMENT_CENTER))
	row.add_child(ball_col)

	var info := VBoxContainer.new()
	info.name = "CrewDetails"
	info.custom_minimum_size = Vector2(240.0, 0.0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 3)
	var name_label := PaperKit.label(String(guy.get("name", "NOBODY")), PaperKit.FONT_BODY,
			Feel.COL_INK)
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size.y = 40.0
	info.add_child(name_label)
	var crew_meta := PaperKit.label("LEVEL %d   ·   READY" %
			int(guy.get("level", 0)), PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.3))
	crew_meta.clip_text = true
	crew_meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(crew_meta)
	var trait_name := GuyTraits.label(String(guy.get("trait", "")))
	var effect := GuyTraits.describe(String(guy.get("trait", "")))
	var trait_line := trait_name.to_upper() if not trait_name.is_empty() else "NO TRAIT"
	var trait_label := PaperKit.label(trait_line, PaperKit.FONT_SMALL,
			Feel.COL_BRASS.darkened(0.1))
	trait_label.clip_text = true
	info.add_child(trait_label)
	card.tooltip_text = effect if not effect.is_empty() else "plain steel — no special effect"
	var status := PaperKit.label("AVAILABLE", PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.3))
	status.name = "SelectionStatus"
	status.clip_text = true
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(status)
	_crew_status_labels.append(status)
	row.add_child(info)

	var action := VBoxContainer.new()
	action.name = "SelectionAction"
	action.custom_minimum_size = Vector2(184.0, 0.0)
	action.size_flags_vertical = Control.SIZE_FILL
	action.mouse_filter = Control.MOUSE_FILTER_PASS
	action.alignment = BoxContainer.ALIGNMENT_BEGIN
	action.add_theme_constant_override("separation", 5)
	var badge := PanelContainer.new()
	badge.name = "ServeBadge"
	badge.custom_minimum_size = Vector2(84.0, 68.0)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _order_badge_box(false))
	var badge_label := PaperKit.label("—", PaperKit.FONT_TITLE, Feel.COL_INK.lightened(0.3),
			HORIZONTAL_ALIGNMENT_CENTER)
	badge_label.name = "OrderNumber"
	badge.add_child(badge_label)
	action.add_child(badge)
	_crew_order_badges.append(badge_label)
	_crew_order_badge_panels.append(badge)
	var choose := PaperKit.button("ADD", PaperKit.FONT_SMALL, Feel.COL_CLEAN)
	choose.name = "Choose"
	choose.custom_minimum_size = Vector2(184.0, Presentation.theme.touch_min)
	choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	choose.pressed.connect(_toggle_guy.bind(index))
	_crew_buttons.append(choose)
	action.add_child(choose)
	row.add_child(action)
	return card


func _crew_card_box(occupied: bool) -> StyleBoxFlat:
	var border := Feel.COL_CLEAN if occupied else Feel.COL_BRASS.darkened(0.28)
	return PaperKit.box(Feel.COL_NEWSPRINT.darkened(0.04), border, 4.0 if occupied else 2.0)


func _order_badge_box(occupied: bool) -> StyleBoxFlat:
	var fill := Feel.COL_CLEAN if occupied else Feel.COL_INK.lightened(0.08)
	var border := Feel.COL_INK if occupied else Feel.COL_BRASS.darkened(0.25)
	return PaperKit.box(fill, border, 3.0)


func _make_portrait(index: int, guy: Dictionary = {}) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.name = "Mugshot"
	var identity := int(guy.get("id", index + 1)) if not guy.is_empty() else index + 1
	var slot := posmod(identity - 1, 4) + 1
	portrait.texture = Presentation.art.resolve(StringName("mugshot.starter_%02d" %
			slot), null, false)
	portrait.set_meta("portrait_slot", slot)
	portrait.custom_minimum_size = Vector2(116.0, 146.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return portrait


## Specialists are not playable balls; they are the hands that keep the racket running.
## They get the same physical card language and Phase 1 mugshots until specialist-specific
## art arrives, while the crew selection above remains the only gameplay interaction.
func _build_specialists(body: VBoxContainer) -> void:
	if Game.stats == null:
		return
	var specialists := Game.stats.specialists()
	if specialists.is_empty():
		return
	body.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.4)))
	body.add_child(PaperKit.label("THE SPECIALISTS", PaperKit.FONT_BIG, Feel.COL_VIOLET))
	body.add_child(PaperKit.label("HIRED HANDS WORK IN THE BACKGROUND · CREW BONUS ACTIVE",
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.18)))
	var list := VBoxContainer.new()
	list.name = "SpecialistCards"
	list.add_theme_constant_override("separation", 8)
	body.add_child(list)
	for i in specialists.size():
		var specialist: Dictionary = specialists[i]
		list.add_child(_make_specialist_card(i, specialist))


func _make_specialist_card(index: int, specialist: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SpecialistCard_%02d" % (index + 1)
	card.custom_minimum_size = Vector2(0.0, 150.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta("specialist_id", String(specialist.get("id", "")))
	card.add_theme_stylebox_override("panel", PaperKit.box(
			Feel.COL_NEWSPRINT.darkened(0.04), Feel.COL_VIOLET.darkened(0.08), 2.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	var frame := PanelContainer.new()
	frame.name = "PortraitFrame"
	frame.custom_minimum_size = Vector2(96.0, 120.0)
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", PaperKit.box(
			Feel.COL_INK.lightened(0.03), Feel.COL_VIOLET.darkened(0.12), 2.0))
	var specialist_portrait := _make_portrait(_specialist_portrait_index(specialist, index))
	specialist_portrait.custom_minimum_size = Vector2(84.0, 108.0)
	frame.add_child(specialist_portrait)
	row.add_child(frame)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_constant_override("separation", 3)
	var name_label := PaperKit.label(String(specialist.get("name", "SPECIALIST")), PaperKit.FONT_BODY,
			Feel.COL_INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(name_label)
	var level := int(specialist.get("level", 0))
	var max_level := int(specialist.get("max_level", 0))
	info.add_child(PaperKit.label("SPECIALIST · LEVEL %d/%d" % [level, max_level],
			PaperKit.FONT_SMALL, Feel.COL_BRASS.darkened(0.12)))
	var instrument := String(specialist.get("instrument", ""))
	info.add_child(PaperKit.label("VOICE · %s   ·   ACTIVE EVERY NIGHT" %
			instrument.replace("_", " ").to_upper(), PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.3)))
	row.add_child(info)
	return card


func _specialist_portrait_index(specialist: Dictionary, fallback: int) -> int:
	var slug := String(specialist.get("id", ""))
	if slug.is_empty():
		return fallback
	var total := 0
	for i in slug.length():
		total += slug.unicode_at(i)
	return total


func _make_preview(guy: Dictionary) -> Control:
	var slot: Control = null
	if ball_preview_factory.is_valid():
		var made: Variant = ball_preview_factory.call(guy)
		if made is Control:
			slot = made as Control
	if slot == null:
		var preview := BallPreview.new()
		preview.set_guy(guy)
		slot = preview
		slot.custom_minimum_size = Vector2(78.0, 78.0)
	slot.set_meta("ball_guy", guy)
	ball_preview_requested.emit(guy)
	return slot


func _toggle_guy(index: int) -> void:
	if index < 0 or index >= available.size():
		return
	var guy: Dictionary = available[index]
	var id := int(guy.get("id", -1))
	for i in selected.size():
		if int(selected[i].get("id", -2)) == id:
			selected.remove_at(i)
			_refresh()
			return
	if selected.size() < MAX_GUYS:
		selected.append(guy)
	_refresh()


func _refresh() -> void:
	var want := mini(MAX_GUYS, available.size())
	if _selection_label != null:
		_selection_label.text = "SERVE ORDER   ·   %d OF %d SELECTED" % [selected.size(), want]
	for i in _serve_order_slots.size():
		var occupied := i < selected.size()
		_serve_order_slots[i].add_theme_stylebox_override("panel", _serve_slot_box(occupied))
		if occupied:
			var guy: Dictionary = selected[i]
			_serve_order_names[i].text = String(guy.get("name", "NOBODY"))
			_serve_order_states[i].text = "FIRST UP" if i == 0 else "NEXT UP"
			_serve_order_names[i].add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
			_serve_order_states[i].add_theme_color_override("font_color",
					Feel.COL_CLEAN.lightened(0.16))
		else:
			_serve_order_names[i].text = "OPEN"
			_serve_order_states[i].text = "PICK A GUY"
			_serve_order_names[i].add_theme_color_override("font_color", Feel.COL_NEWSPRINT.darkened(0.2))
			_serve_order_states[i].add_theme_color_override("font_color",
					Feel.COL_NEWSPRINT.darkened(0.35))
	for i in _crew_buttons.size():
		var guy: Dictionary = available[i]
		var order := _selected_order(guy)
		_crew_buttons[i].text = ("SERVE %d" % order) if order > 0 else "ADD"
		_crew_buttons[i].disabled = order == 0 and selected.size() >= MAX_GUYS
		if i < _crew_cards.size():
			_crew_cards[i].add_theme_stylebox_override("panel", _crew_card_box(order > 0))
		if i < _crew_order_badges.size():
			_crew_order_badges[i].text = str(order) if order > 0 else "—"
			_crew_order_badges[i].add_theme_color_override("font_color",
					Feel.COL_INK if order > 0 else Feel.COL_INK.lightened(0.3))
		if i < _crew_order_badge_panels.size():
			_crew_order_badge_panels[i].add_theme_stylebox_override("panel", _order_badge_box(order > 0))
		if i < _crew_status_labels.size():
			_crew_status_labels[i].text = ("SELECTED   ·   SERVE %d" % order) \
					if order > 0 else "AVAILABLE   ·   TAP TO ADD"
			_crew_status_labels[i].add_theme_color_override("font_color",
					Feel.COL_CLEAN.darkened(0.15) if order > 0 else Feel.COL_INK.lightened(0.3))
	if _start != null:
		_start.disabled = want <= 0 or selected.size() != want
		_start.text = "START NIGHT" if selected.size() == want else "SELECT %d GUYS" % want


func _selected_order(guy: Dictionary) -> int:
	var id := int(guy.get("id", -1))
	for i in selected.size():
		if int(selected[i].get("id", -2)) == id:
			return i + 1
	return 0


func _on_start() -> void:
	var want := mini(MAX_GUYS, available.size())
	if want <= 0 or selected.size() != want:
		return
	start_pressed.emit(selected.duplicate())


## Job checks are the source of truth for scope; the slip data itself remains untouched.
static func scope_for_job(job: Dictionary) -> String:
	return scope_for_check(String(job.get("check", "")))


static func scope_for_check(check: String) -> String:
	match check:
		"ball_survival":
			return "FIRST GUY"
		"switch_count_one_ball", "collect_all_one_ball":
			return "ONE GUY"
		"bumper_burst":
			return "ANY GUY"
		_:
			return "ALL NIGHT"
