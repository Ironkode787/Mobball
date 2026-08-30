class_name AttractScreen
extends CanvasLayer
## The session's front door. Lives beside The Count because they are the same object in
## two moods: the shell you see when no guy is on the table.
##
## Boot ritual (docs/03 §6): if the Safe filled up while you were away, it is the first
## thing on screen — bag-drop sound, count, collect.

signal start_pressed

var _safe_panel: PanelContainer = null
var _safe_label: Label = null
var _content_margin: MarginContainer = null


func _ready() -> void:
	layer = 20
	var bg := ColorRect.new()
	bg.color = Feel.COL_INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The table's illuminated backglass is the title screen now. A lighter smoked-glass wash
	# keeps it visible instead of printing a second KINGPIN logo over the first one.
	bg.color.a = 0.62
	add_child(bg)

	_content_margin = MarginContainer.new()
	_content_margin.name = "SafeContent"
	_content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content_margin)
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	_content_margin.add_child(col)

	col.add_child(PaperKit.label("THE HOUSE IS OPEN", PaperKit.FONT_TITLE, Feel.COL_BRASS,
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
	start.custom_minimum_size.y = Presentation.theme.touch_min
	start.pressed.connect(func() -> void: start_pressed.emit())
	col.add_child(start)

	Game.safe_changed.connect(_on_safe_changed)


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	Presentation.safe.apply_to_margin_container(_content_margin,
			Vector4(60.0, 1030.0, 60.0, 120.0))


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
