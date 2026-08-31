class_name RollCallScreen
extends CanvasLayer
## PRE-NIGHT ROLL CALL — choose tonight's job and the order in which the available balls
## serve. This is a screen, not a pause menu: Start tears it down through the normal flow.

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
var _holding: VBoxContainer = null
var _specialists: VBoxContainer = null
var _specialists_list: VBoxContainer = null
var _specialists_toggle: Button = null
var _specialists_expanded := false
var _start: Button = null
var _start_requirement: Label = null
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
	bg.name = "RollCallBackdrop"
	bg.color = Feel.COL_INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_content_margin = MarginContainer.new()
	_content_margin.name = "SafeContent"
	_content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_margin)
	_apply_safe_area()
	if not Presentation.safe.margins_changed.is_connected(_on_safe_margins_changed):
		Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var outer := VBoxContainer.new()
	outer.name = "RollCallLayout"
	outer.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	_content_margin.add_child(outer)

	var heading := PaperKit.section_header("ROLL CALL", "PRE-NIGHT DOSSIER")
	heading.name = "RollCallHeader"
	outer.add_child(heading)
	var explain := PaperKit.type_label(
		"Each guy is one ball. Choose who serves first, second, and third tonight.",
		&"body", Feel.COL_NEWSPRINT)
	explain.name = "RollCallInstructions"
	explain.custom_minimum_size.y = 56.0
	outer.add_child(explain)

	var scroll := ScrollContainer.new()
	scroll.name = "RollCallScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.clip_contents = true
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "RollCallBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	scroll.add_child(body)

	body.add_child(_job_docket(Game.jobs.active_jobs() if Game.jobs != null else []))
	body.add_child(PaperKit.section_header("TONIGHT'S CREW", "FIELD ORDER"))
	_build_serve_order(body)
	_crew = VBoxContainer.new()
	_crew.name = "AvailableCrew"
	_crew.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	body.add_child(_crew)
	_build_crew()

	_holding = VBoxContainer.new()
	_holding.name = "HoldingCrew"
	_holding.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	body.add_child(_holding)
	_build_holding()

	_specialists = VBoxContainer.new()
	_specialists.name = "HiredHands"
	_specialists.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	body.add_child(_specialists)
	_build_specialists()

	var footer := VBoxContainer.new()
	footer.name = "RollCallFooter"
	footer.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	footer.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.25), 3.0))
	_start_requirement = PaperKit.type_label("", &"caption", Feel.COL_NEWSPRINT.darkened(0.1),
		HORIZONTAL_ALIGNMENT_CENTER)
	_start_requirement.name = "StartRequirement"
	_start_requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_requirement.visible = false
	footer.add_child(_start_requirement)
	var bar := PaperKit.bottom_action_bar("START NIGHT")
	bar.name = "StartNightFooter"
	bar.set_meta("roll_call_footer", true)
	_start = bar.get_node_or_null("Actions/Primary") as Button
	if _start != null:
		_start.name = "StartNight"
		_start.pressed.connect(_on_start)
	footer.add_child(bar)
	outer.add_child(footer)
	_refresh()


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content_margin,
			Vector4(42.0, 42.0, 42.0, 36.0))


func _job_docket(jobs: Array[Dictionary]) -> PanelContainer:
	var docket := PaperKit.paper_card("TONIGHT'S WORK", "")
	docket.name = "JobDocket"
	docket.set_meta("roll_call_docket", true)
	var content := docket.get_node_or_null("Content") as VBoxContainer
	if content == null:
		content = VBoxContainer.new()
		content.name = "Content"
		docket.add_child(content)
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	if jobs.is_empty():
		var none := PaperKit.type_label("No work has been posted for this Night.", &"body", Feel.COL_INK)
		none.name = "NoJob"
		content.add_child(none)
		return docket

	var hero := HBoxContainer.new()
	hero.name = "HeroJob"
	hero.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_16")))
	content.add_child(hero)
	var details := VBoxContainer.new()
	details.name = "HeroDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	hero.add_child(details)
	var first: Dictionary = jobs[0]
	var first_name := PaperKit.type_label(String(first.get("name", "Tonight's job")), &"title", Feel.COL_INK)
	first_name.name = "JobName"
	details.add_child(first_name)
	var objective := PaperKit.type_label(String(first.get("desc", "Keep the machine moving.")), &"body", Feel.COL_INK.lightened(0.06))
	objective.name = "JobObjective"
	details.add_child(objective)
	var reward := PaperKit.type_label("REWARD  +%d RESPECT" % int(first.get("respect", 0)), &"metadata", Feel.COL_BRASS.darkened(0.22))
	reward.name = "JobReward"
	details.add_child(reward)
	var scope := PaperKit.type_label("SCOPE  %s" % scope_for_job(first), &"metadata", Feel.COL_INK.lightened(0.2))
	scope.name = "JobScope"
	details.add_child(scope)

	var prop := TextureRect.new()
	prop.name = "JobProp"
	prop.texture = Presentation.art.resolve(&"ui.job_board", null, false)
	prop.custom_minimum_size = Vector2(144.0, 128.0)
	prop.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	prop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero.add_child(prop)

	if jobs.size() > 1:
		content.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.45), 2.0))
		var other_label := PaperKit.type_label("OTHER WORK", &"metadata", Feel.COL_BRASS.darkened(0.15))
		content.add_child(other_label)
		for i in range(1, jobs.size()):
			content.add_child(_compact_job_row(jobs[i]))
	return docket


func _compact_job_row(job: Dictionary) -> PanelContainer:
	var row := PaperKit.receipt_row(String(job.get("name", "Unlisted work")),
			"+%d" % int(job.get("respect", 0)), scope_for_job(job))
	row.name = "JobRow_%s" % String(job.get("id", "job"))
	row.set_meta("job_id", String(job.get("id", "")))
	return row


## Three fixed slots make the append-only selection rule legible before a player ever touches
## a crew card. Their fixed count is a model contract, not a responsive card grid.
func _build_serve_order(body: VBoxContainer) -> void:
	var panel := PaperKit.glass_panel("SERVE ORDER", "Selections serve in this order. Remove a pin to change the line.")
	panel.name = "ServeOrder"
	var content := panel.get_node_or_null("Content") as VBoxContainer
	if content == null:
		return
	_selection_label = content.get_node_or_null("Title") as Label
	if _selection_label == null:
		_selection_label = PaperKit.type_label("SERVE ORDER", &"section", Feel.COL_BRASS)
		content.add_child(_selection_label)
	_selection_label.name = "SelectionCount"
	var rail := HBoxContainer.new()
	rail.name = "ServeOrderRail"
	rail.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	content.add_child(rail)
	_serve_order_slots.clear()
	_serve_order_names.clear()
	_serve_order_states.clear()
	for i in MAX_GUYS:
		var slot := PanelContainer.new()
		slot.name = "ServeSlot%d" % (i + 1)
		slot.custom_minimum_size = Vector2(0.0, 112.0)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.add_theme_stylebox_override("panel", _serve_slot_box(false))
		var slot_col := VBoxContainer.new()
		slot_col.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_col.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
		slot.add_child(slot_col)
		var number := PaperKit.type_label(str(i + 1), &"title", Feel.COL_BRASS,
				HORIZONTAL_ALIGNMENT_CENTER)
		number.name = "OrderNumber"
		number.custom_minimum_size.y = 52.0
		slot_col.add_child(number)
		var name_label := PaperKit.type_label("OPEN", &"caption", Feel.COL_NEWSPRINT,
				HORIZONTAL_ALIGNMENT_CENTER)
		name_label.name = "Name"
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.y = 34.0
		slot_col.add_child(name_label)
		var state_label := PaperKit.type_label("Pick a guy", &"micro",
				Feel.COL_NEWSPRINT.darkened(0.25), HORIZONTAL_ALIGNMENT_CENTER)
		state_label.name = "State"
		state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		slot_col.add_child(state_label)
		rail.add_child(slot)
		_serve_order_slots.append(slot)
		_serve_order_names.append(name_label)
		_serve_order_states.append(state_label)
	body.add_child(panel)


func _serve_slot_box(occupied: bool) -> StyleBoxFlat:
	var fill := Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.26) if occupied \
			else Feel.COL_INK.lightened(0.12)
	var border := Feel.COL_BRASS if occupied else Feel.COL_BRASS.darkened(0.35)
	return PaperKit.box(fill, border, 3.0 if occupied else 2.0)


func _build_crew() -> void:
	if _crew == null:
		return
	for child in _crew.get_children():
		child.free()
	_crew_buttons.clear()
	_crew_cards.clear()
	_crew_status_labels.clear()
	_crew_order_badges.clear()
	_crew_order_badge_panels.clear()
	if available.is_empty():
		var empty := PaperKit.paper_card("NO OPEN CREW", "No free guys can serve this Night. Bail or wait for the holding roster to return.")
		empty.name = "EmptyCrew"
		_crew.add_child(empty)
	else:
		for i in available.size():
			var guy: Dictionary = available[i]
			var card := _make_crew_card(i, guy)
			_crew_cards.append(card)
			_crew.add_child(card)
	_refresh()


func _make_crew_card(index: int, guy: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "CrewCard_%02d" % (index + 1)
	card.custom_minimum_size = Vector2(0.0, 242.0)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.set_meta("guy_id", int(guy.get("id", -1)))
	card.set_meta("roll_call_card", true)
	card.add_theme_stylebox_override("panel", _crew_card_box(false))
	var column := VBoxContainer.new()
	column.name = "CardContent"
	column.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	card.add_child(column)

	var identity := HBoxContainer.new()
	identity.name = "Identity"
	identity.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	column.add_child(identity)
	var portrait_frame := PanelContainer.new()
	portrait_frame.name = "PortraitFrame"
	portrait_frame.custom_minimum_size = Vector2(96.0, 112.0)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_frame.add_theme_stylebox_override("panel", PaperKit.box(
			Feel.COL_INK.lightened(0.03), Feel.COL_BRASS.darkened(0.3), 2.0))
	portrait_frame.add_child(_make_portrait(index, guy))
	identity.add_child(portrait_frame)

	var details := VBoxContainer.new()
	details.name = "CrewDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	identity.add_child(details)
	var name_label := PaperKit.type_label(String(guy.get("name", "Nobody")), &"section", Feel.COL_INK)
	name_label.name = "Name"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = false
	details.add_child(name_label)
	var crew_meta := PaperKit.type_label("Level %d  |  Free to serve" % int(guy.get("level", 0)),
			&"metadata", Feel.COL_INK.lightened(0.3))
	crew_meta.name = "Availability"
	crew_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(crew_meta)
	var trait_name := GuyTraits.label(String(guy.get("trait", "")))
	var effect := GuyTraits.describe(String(guy.get("trait", "")))
	var trait_line := trait_name if not trait_name.is_empty() else "No special trait"
	var trait_label := PaperKit.type_label(trait_line, &"caption", Feel.COL_BRASS.darkened(0.1))
	trait_label.name = "Trait"
	trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(trait_label)
	card.tooltip_text = effect if not effect.is_empty() else "Plain steel - no special effect."
	var status := PaperKit.type_label("READY", &"metadata", Feel.COL_INK.lightened(0.25))
	status.name = "SelectionStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(status)
	_crew_status_labels.append(status)

	var lower := HBoxContainer.new()
	lower.name = "BallAndOrder"
	lower.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	column.add_child(lower)
	var preview := _make_preview(guy)
	preview.name = "BallPreview"
	preview.custom_minimum_size = Vector2(70.0, 70.0)
	preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lower.add_child(preview)
	var ball_note := PaperKit.type_label("Ball %02d\nOrder is pinned below." % int(guy.get("id", 0)),
			&"metadata", Feel.COL_INK.lightened(0.18))
	ball_note.name = "BallIdentity"
	ball_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ball_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ball_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lower.add_child(ball_note)
	var badge := PanelContainer.new()
	badge.name = "ServeBadge"
	badge.custom_minimum_size = Vector2(74.0, 66.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", _order_badge_box(false))
	var badge_label := PaperKit.type_label("-", &"primary_value", Feel.COL_INK.lightened(0.3),
			HORIZONTAL_ALIGNMENT_CENTER)
	badge_label.name = "OrderNumber"
	badge.add_child(badge_label)
	lower.add_child(badge)
	_crew_order_badges.append(badge_label)
	_crew_order_badge_panels.append(badge)

	var choose := PaperKit.action_button("ADD TO LINE", &"secondary")
	choose.name = "Choose"
	choose.custom_minimum_size = Vector2(0.0, Presentation.theme.touch_min)
	choose.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choose.pressed.connect(_toggle_guy.bind(index))
	_crew_buttons.append(choose)
	column.add_child(choose)
	return card


func _crew_card_box(occupied: bool) -> StyleBoxFlat:
	var border := Feel.COL_BRASS if occupied else Feel.COL_BRASS.darkened(0.28)
	var fill := Feel.COL_NEWSPRINT.darkened(0.02) if occupied else Feel.COL_NEWSPRINT.darkened(0.08)
	return PaperKit.box(fill, border, 4.0 if occupied else 2.0)


func _order_badge_box(occupied: bool) -> StyleBoxFlat:
	var fill := Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.86) if occupied \
			else Feel.COL_INK.lightened(0.08)
	var border := Feel.COL_INK if occupied else Feel.COL_BRASS.darkened(0.25)
	return PaperKit.box(fill, border, 3.0)


func _make_portrait(index: int, guy: Dictionary = {}) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.name = "Mugshot"
	var identity := int(guy.get("id", index + 1)) if not guy.is_empty() else index + 1
	var slot := posmod(identity - 1, 4) + 1
	portrait.texture = Presentation.art.resolve(StringName("mugshot.starter_%02d" % slot), null, false)
	portrait.set_meta("portrait_slot", slot)
	portrait.custom_minimum_size = Vector2(84.0, 100.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return portrait


func _build_holding() -> void:
	if _holding == null:
		return
	for child in _holding.get_children():
		child.free()
	var held: Array[Dictionary] = Game.bench.holding() if Game.bench != null else []
	if held.is_empty():
		return
	_holding.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.45), 2.0))
	_holding.add_child(PaperKit.section_header("IN HOLDING", "OFF THE TABLE"))
	var note := PaperKit.type_label("A held guy cannot be selected. Bail now or wait out the sit-out.",
			&"caption", Feel.COL_NEWSPRINT.darkened(0.12))
	note.name = "HoldingNote"
	_holding.add_child(note)
	for i in held.size():
		_holding.add_child(_make_holding_card(i, held[i]))


func _make_holding_card(index: int, guy: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "HoldingCard_%02d" % (index + 1)
	card.custom_minimum_size = Vector2(0.0, 176.0)
	card.set_meta("guy_id", int(guy.get("id", -1)))
	card.set_meta("roll_call_state", Bench.STATE_HOLDING)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", PaperKit.box(
			Feel.COL_INK.lightened(0.07), Feel.COL_BRASS.darkened(0.42), 2.0))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	card.add_child(content)
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_12")))
	content.add_child(identity)
	var name_label := PaperKit.type_label(String(guy.get("name", "Nobody")), &"section", Feel.COL_NEWSPRINT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(name_label)
	var state := PaperKit.type_label("HOLDING", &"metadata", Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_RIGHT)
	state.name = "HoldingStatus"
	# Keep the semantic holding token readable beside long names at phone widths.  A fixed
	# metadata-sized column prevents the HBox from collapsing the label into one character per
	# line while leaving the name column free to wrap naturally.
	state.autowrap_mode = TextServer.AUTOWRAP_OFF
	state.custom_minimum_size.x = 128.0
	identity.add_child(state)
	var nights := maxi(int(guy.get("sit_out", 1)), 1)
	var walk_text := "Walks next Night" if nights <= 1 else "Walks in %d Nights" % nights
	var context := PaperKit.type_label("%s  |  Non-selectable" % walk_text, &"caption",
			Feel.COL_NEWSPRINT.darkened(0.06))
	context.name = "WalkContext"
	context.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(context)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	content.add_child(action_row)
	var cost := Game.bail_cost(guy) if Game.has_method("bail_cost") else BigMoney.zero()
	var affordable := Game.wallet.can_afford_dirty(cost) if Game.wallet != null else false
	var bail := PaperKit.action_button("BAIL  %s" % cost.text(), &"destructive")
	bail.name = "Bail"
	bail.disabled = not affordable
	if not affordable:
		bail.tooltip_text = "Dirty cash only - you are short."
	bail.pressed.connect(_on_bail.bind(guy))
	action_row.add_child(bail)
	var hint := PaperKit.type_label("Dirty cash only", &"metadata", Feel.COL_NEWSPRINT.darkened(0.18))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	action_row.add_child(hint)
	return card


## Specialists are not playable balls; they are the hands that keep the racket running. They
## stay below the core selection and are collapsed until the player asks for the dossier.
func _build_specialists() -> void:
	if _specialists == null or Game.stats == null:
		return
	var list_data := Game.stats.specialists()
	if list_data.is_empty():
		return
	_specialists.add_child(PaperKit.rule(Feel.COL_VIOLET.darkened(0.25), 2.0))
	var header := HBoxContainer.new()
	header.name = "HiredHandsHeader"
	header.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	_specialists.add_child(header)
	var title := PaperKit.section_header("HIRED HANDS", "SPECIALISTS")
	title.name = "HiredHandsTitle"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_specialists_toggle = PaperKit.action_button("SHOW %d" % list_data.size(), &"quiet")
	_specialists_toggle.name = "HiredHandsToggle"
	_specialists_toggle.custom_minimum_size = Vector2(148.0, Presentation.theme.touch_min)
	_specialists_toggle.pressed.connect(_toggle_specialists)
	header.add_child(_specialists_toggle)
	var note := PaperKit.type_label("Specialists work in the background. They do not take a serve slot.",
			&"caption", Feel.COL_NEWSPRINT.darkened(0.16))
	note.name = "HiredHandsNote"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_specialists.add_child(note)
	_specialists_list = VBoxContainer.new()
	_specialists_list.name = "SpecialistCards"
	_specialists_list.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_8")))
	_specialists_list.visible = _specialists_expanded
	_specialists.add_child(_specialists_list)
	for i in list_data.size():
		_specialists_list.add_child(_make_specialist_card(i, list_data[i]))


func _toggle_specialists() -> void:
	_specialists_expanded = not _specialists_expanded
	if _specialists_list != null:
		_specialists_list.visible = _specialists_expanded
	if _specialists_toggle != null:
		_specialists_toggle.text = "HIDE" if _specialists_expanded else "SHOW %d" % _specialist_count()


func _specialist_count() -> int:
	return Game.stats.specialists().size() if Game.stats != null else 0


func _make_specialist_card(index: int, specialist: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SpecialistCard_%02d" % (index + 1)
	card.custom_minimum_size = Vector2(0.0, 148.0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta("specialist_id", String(specialist.get("id", "")))
	card.set_meta("roll_call_state", "specialist")
	card.add_theme_stylebox_override("panel", PaperKit.box(
			Feel.COL_NEWSPRINT.darkened(0.04), Feel.COL_VIOLET.darkened(0.08), 2.0))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(Presentation.theme.spacing_for(&"space_4")))
	card.add_child(column)
	var name_label := PaperKit.type_label(String(specialist.get("name", "Specialist")), &"section", Feel.COL_INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(name_label)
	var level := int(specialist.get("level", 0))
	var max_level := int(specialist.get("max_level", 0))
	column.add_child(PaperKit.type_label("Level %d/%d  |  Hired hand" % [level, max_level],
			&"metadata", Feel.COL_BRASS.darkened(0.12)))
	var instrument := String(specialist.get("instrument", ""))
	column.add_child(PaperKit.type_label("Works every Night: %s" % instrument.replace("_", " "),
			&"caption", Feel.COL_INK.lightened(0.3)))
	return card


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


func _on_bail(guy: Dictionary) -> void:
	if not Game.bail_guy(guy):
		return
	available = Game.bench.available() if Game.bench != null else []
	_build_crew()
	_build_holding()
	_refresh()


func _refresh() -> void:
	var want := mini(MAX_GUYS, available.size())
	if _selection_label != null:
		_selection_label.text = "%d OF %d PINNED" % [selected.size(), want]
	for i in _serve_order_slots.size():
		var occupied := i < selected.size()
		_serve_order_slots[i].add_theme_stylebox_override("panel", _serve_slot_box(occupied))
		if occupied:
			var guy: Dictionary = selected[i]
			_serve_order_names[i].text = String(guy.get("name", "Nobody"))
			_serve_order_states[i].text = "FIRST UP" if i == 0 else "NEXT UP"
			_serve_order_names[i].add_theme_color_override("font_color", Feel.COL_NEWSPRINT)
			_serve_order_states[i].add_theme_color_override("font_color", Feel.COL_BRASS.lightened(0.16))
		else:
			_serve_order_names[i].text = "OPEN"
			_serve_order_states[i].text = "Pick a guy"
			_serve_order_names[i].add_theme_color_override("font_color", Feel.COL_NEWSPRINT.darkened(0.2))
			_serve_order_states[i].add_theme_color_override("font_color", Feel.COL_NEWSPRINT.darkened(0.35))
	for i in _crew_buttons.size():
		var guy: Dictionary = available[i]
		var order := _selected_order(guy)
		_crew_buttons[i].text = ("REMOVE PIN %d" % order) if order > 0 else "ADD TO LINE"
		_crew_buttons[i].disabled = order == 0 and selected.size() >= MAX_GUYS
		if i < _crew_cards.size():
			_crew_cards[i].add_theme_stylebox_override("panel", _crew_card_box(order > 0))
		if i < _crew_order_badges.size():
			_crew_order_badges[i].text = str(order) if order > 0 else "-"
			_crew_order_badges[i].add_theme_color_override("font_color",
					Feel.COL_INK if order > 0 else Feel.COL_INK.lightened(0.3))
		if i < _crew_order_badge_panels.size():
			_crew_order_badge_panels[i].add_theme_stylebox_override("panel", _order_badge_box(order > 0))
		if i < _crew_status_labels.size():
			_crew_status_labels[i].text = ("PINNED  |  SERVE %d" % order) if order > 0 else "READY"
			_crew_status_labels[i].add_theme_color_override("font_color",
					Feel.COL_BRASS.darkened(0.12) if order > 0 else Feel.COL_INK.lightened(0.3))
	if _start != null:
		_start.disabled = want <= 0 or selected.size() != want
		_start.text = "START NIGHT"
		_start.tooltip_text = "Select all open crew before starting." if _start.disabled else "Begin tonight's run."
	if _start_requirement != null:
		_start_requirement.visible = _start != null and _start.disabled
		if want <= 0:
			_start_requirement.text = "No free crew can start this Night."
		else:
			_start_requirement.text = "Pin all %d open crew to start this Night." % want


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
