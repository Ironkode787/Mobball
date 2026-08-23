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
var _selection_label: Label = null
var _start: Button = null


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

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	margin.add_child(outer)
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
	for job: Dictionary in Game.jobs.active_jobs():
		body.add_child(_job_slip(job))
	body.add_child(PaperKit.rule(Feel.COL_BRASS.darkened(0.4)))
	body.add_child(PaperKit.label("TONIGHT'S CREW", PaperKit.FONT_BIG, Feel.COL_BRASS))
	_selection_label = PaperKit.label("", PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.12))
	body.add_child(_selection_label)
	_crew = VBoxContainer.new()
	_crew.add_theme_constant_override("separation", 10)
	body.add_child(_crew)
	_build_crew()

	_start = PaperKit.button("START NIGHT", PaperKit.FONT_BIG, Feel.COL_CLEAN)
	_start.pressed.connect(_on_start)
	outer.add_child(_start)
	_refresh()


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


func _build_crew() -> void:
	if _crew == null:
		return
	for child in _crew.get_children():
		child.queue_free()
	_crew_buttons.clear()
	for i in available.size():
		var guy: Dictionary = available[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var preview := _make_preview(guy)
		row.add_child(preview)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(PaperKit.label(String(guy.get("name", "NOBODY")), PaperKit.FONT_BODY,
			Feel.COL_NEWSPRINT))
		info.add_child(PaperKit.label("LEVEL %d   ·   READY" % int(guy.get("level", 0)),
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.18)))
		var trait_name := GuyTraits.label(String(guy.get("trait", "")))
		var effect := GuyTraits.describe(String(guy.get("trait", "")))
		var trait_line := trait_name.to_upper() if not trait_name.is_empty() else "NO TRAIT"
		info.add_child(PaperKit.label(trait_line, PaperKit.FONT_SMALL, Feel.COL_BRASS))
		var effect_label := PaperKit.label(effect if not effect.is_empty() else "plain steel — no special effect",
			PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT.darkened(0.28))
		effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(effect_label)
		row.add_child(info)
		var choose := PaperKit.button("", PaperKit.FONT_SMALL, Feel.COL_CLEAN)
		choose.custom_minimum_size = Vector2(180.0, 112.0)
		choose.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		choose.pressed.connect(_toggle_guy.bind(i))
		_crew_buttons.append(choose)
		row.add_child(choose)
		_crew.add_child(row)
	_refresh()


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
		_selection_label.text = "%d OF %d SELECTED — ORDER IS SERVE ORDER" % [selected.size(), want]
	for i in _crew_buttons.size():
		var guy: Dictionary = available[i]
		var order := _selected_order(guy)
		_crew_buttons[i].text = ("SERVE %d" % order) if order > 0 else "ADD"
		_crew_buttons[i].disabled = order == 0 and selected.size() >= MAX_GUYS
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
