class_name LedgerDocket
extends Control
## The docket: the paper sheet that slides up when you tap a card. Name, flavor, what it
## puts on the table, what it does to the numbers, what it costs — and the one button.
##
## It is a real node tree (labels wrap, the button is a button) sitting on a hand-painted
## paper background, because everything else on this screen is drawn and a default-theme
## panel would look like a different game.

signal buy_pressed(id: String)
signal dismissed

const HEIGHT := 660.0

var node_id: String = ""

var _title: Label = null
var _sub: Label = null
var _flavor: Label = null
var _table: Label = null
var _effects: VBoxContainer = null
var _cost: Label = null
var _buy: Button = null
var _shut: Button = null
var _slide: float = 0.0
var _tween: Tween = null
var _pad: MarginContainer = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	_build()
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)
	_set_slide(0.0)


func _build() -> void:
	_pad = MarginContainer.new()
	_pad.name = "SafeContent"
	_pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pad.add_child(col)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)
	_title = _label("", 40, LedgerStyle.INK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_shut = Button.new()
	_shut.text = "×"
	_shut.custom_minimum_size = Vector2(68.0, 68.0)
	_shut.add_theme_font_size_override("font_size", 40)
	LedgerStyle.style_button(_shut, Color(LedgerStyle.INK, 0.10), LedgerStyle.INK)
	_shut.pressed.connect(func() -> void: dismissed.emit())
	head.add_child(_shut)

	_sub = _label("", 20, LedgerStyle.INK_SOFT)
	col.add_child(_sub)

	_flavor = _label("", 23, Color(LedgerStyle.INK, 0.72))
	_flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_flavor)

	col.add_child(_rule())
	col.add_child(_label("ON THE TABLE", 17, LedgerStyle.BRASS.darkened(0.25)))
	_table = _label("", 22, LedgerStyle.INK)
	_table.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_table)

	col.add_child(_label("ON THE BOOKS", 17, LedgerStyle.BRASS.darkened(0.25)))
	_effects = VBoxContainer.new()
	_effects.add_theme_constant_override("separation", 4)
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_effects)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 24)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(foot)
	_cost = _label("", 38, LedgerStyle.CLEAN.darkened(0.25))
	_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	foot.add_child(_cost)
	_buy = Button.new()
	_buy.text = "BUY"
	_buy.custom_minimum_size = Vector2(320.0, 92.0)
	_buy.add_theme_font_size_override("font_size", 30)
	LedgerStyle.style_button(_buy, LedgerStyle.CLEAN.darkened(0.15), LedgerStyle.INK)
	_buy.pressed.connect(func() -> void: buy_pressed.emit(node_id))
	foot.add_child(_buy)


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_pad, Vector4(44.0, 34.0, 44.0, 34.0))


# --- content ------------------------------------------------------------------


func show_for(node_def: Dictionary, level: int, cost: BigMoney, block: int, reason: String) -> void:
	node_id = String(node_def["id"])
	var max_level := int(node_def["max_level"])
	_title.text = String(node_def["name"])
	var bits: PackedStringArray = [
		LedgerStyle.branch_title(String(node_def["branch"])),
		"TIER %d" % int(node_def["tier"]),
	]
	if max_level > 1:
		bits.append("LEVEL %d OF %d" % [level, max_level])
	elif level > 0:
		bits.append("OWNED")
	var specialist: Dictionary = node_def["specialist"]
	if not specialist.is_empty():
		bits.append("SPECIALIST · %s" % LedgerStyle.pretty(String(specialist["instrument"])).to_upper())
	_sub.text = "  ·  ".join(bits)
	_flavor.text = "“%s”" % String(node_def["flavor"])
	_table.text = String(node_def["table_change"])

	for child in _effects.get_children():
		_effects.remove_child(child)
		child.queue_free()
	var effects: Array = node_def["effects"]
	for effect: Variant in effects:
		_add_effect_lines(effect as Dictionary, level, max_level)

	if block == Upgrades.Block.MAXED:
		_cost.text = "MAXED"
		_cost.add_theme_color_override("font_color", LedgerStyle.INK_SOFT)
	else:
		_cost.text = cost.text()
		_cost.add_theme_color_override("font_color",
			LedgerStyle.CLEAN.darkened(0.25) if block == Upgrades.Block.NONE else LedgerStyle.DIRTY.darkened(0.1))

	_buy.disabled = block != Upgrades.Block.NONE
	_buy.text = "BUY" if block == Upgrades.Block.NONE else reason
	_buy.add_theme_font_size_override("font_size", 30 if block == Upgrades.Block.NONE else 22)
	open()


## One line for a one-off. For a repeatable you already own a level of, two: what the books
## say now, and what the next stamp turns it into — the whole question the escalating price
## is asking. An unowned or maxed node has no "next", so it keeps the single line.
func _add_effect_lines(effect: Dictionary, level: int, max_level: int) -> void:
	var levelled := bool(effect["per_level"]) and max_level > 1 and level >= 1
	if not levelled:
		_effects.add_child(_label("•  " + LedgerStyle.effect_line(effect), 22, LedgerStyle.INK))
		return
	_effects.add_child(_label("•  " + LedgerStyle.effect_line_at(effect, level), 22, LedgerStyle.INK))
	if level >= max_level:
		return
	var delta := LedgerStyle.effect_delta(effect, level)
	var next := LedgerStyle.effect_line_at(effect, level + 1)
	var line := "     next:  %s" % next
	if delta != "":
		line += "   (%s)" % delta
	_effects.add_child(_label(line, 19, LedgerStyle.BRASS.darkened(0.35)))


func open() -> void:
	visible = true
	_slide_to(1.0)


func dismiss() -> void:
	_slide_to(0.0)


func is_open() -> bool:
	return _slide > 0.5


# --- slide --------------------------------------------------------------------


func _slide_to(v: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if not is_inside_tree():
		_set_slide(v)
		return
	_tween = create_tween()
	_tween.tween_method(_set_slide, _slide, v, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_slide(v: float) -> void:
	_slide = v
	offset_bottom = HEIGHT * (1.0 - v)
	offset_top = offset_bottom - HEIGHT
	visible = v > 0.01


# --- paint --------------------------------------------------------------------


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(Rect2(Vector2(0.0, -10.0), Vector2(size.x, 10.0)), Color(0.0, 0.0, 0.0, 0.35))
	draw_rect(r, LedgerStyle.PAPER)
	draw_rect(Rect2(0.0, 0.0, size.x, 5.0), LedgerStyle.BRASS)
	# Faint ruled lines: it is a docket, it came out of a typewriter.
	var y := 120.0
	while y < size.y:
		draw_line(Vector2(30.0, y), Vector2(size.x - 30.0, y), Color(LedgerStyle.INK, 0.045), 1.0)
		y += 34.0


# --- helpers ------------------------------------------------------------------


func _label(text: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rule() -> Control:
	var c := ColorRect.new()
	c.color = Color(LedgerStyle.INK, 0.18)
	c.custom_minimum_size = Vector2(0.0, 2.0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
