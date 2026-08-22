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

## Seconds each line takes to roll up, and the gap between the bill-counter ticks.
const LINE_TIME := 0.55
const TICK_INTERVAL := 0.07
const LINE_GAP := 0.12

var summary: Dictionary = {}

var _rows: Array[Dictionary] = []
var _row_index: int = -1
var _row_time: float = 0.0
var _tick_time: float = 0.0
var _headline: Label = null
var _headline_shown: bool = false
var _buttons: HBoxContainer = null
var _roster: VBoxContainer = null
var _safe: PanelContainer = null
var _body: VBoxContainer = null
var _counter: AudioStreamPlayer = null


func _ready() -> void:
	layer = 20
	summary = Game.last_night.duplicate() if not Game.last_night.is_empty() else {}
	_build()
	_row_index = 0
	_row_time = 0.0
	# The counter runs under the tally and stops when the last line lands (audio-wave2 §1).
	_counter = AudioDirector.play(&"bill_counter", {"loop": true})


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Feel.COL_NEWSPRINT
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	margin.add_child(_body)

	_body.add_child(PaperKit.label("THE COUNT", PaperKit.FONT_TITLE, Feel.COL_INK))
	_body.add_child(PaperKit.label(
			"NIGHT %d   ·   %s" % [int(summary.get("night", Game.night_no)), Game.rank_title()],
			PaperKit.FONT_SMALL, Feel.COL_INK.lightened(0.35)))
	_body.add_child(PaperKit.rule(Feel.COL_INK, 4.0))

	_build_safe_banner()
	_build_lines()

	_body.add_child(PaperKit.rule(Feel.COL_INK, 4.0))
	_headline = PaperKit.label("", PaperKit.FONT_BIG, Feel.COL_INK)
	_headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_headline.custom_minimum_size = Vector2(0.0, 190.0)
	_headline.modulate.a = 0.0
	_body.add_child(_headline)

	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 8)
	_body.add_child(_roster)
	_build_roster()

	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(grow)

	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 24)
	_body.add_child(_buttons)

	var ledger := PaperKit.button("THE LEDGER")
	ledger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ledger.pressed.connect(func() -> void: ledger_pressed.emit())
	_buttons.add_child(ledger)

	var next := PaperKit.button("NEXT NIGHT", PaperKit.FONT_BIG, Feel.COL_CLEAN)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.pressed.connect(func() -> void: next_night_pressed.emit())
	_buttons.add_child(next)


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
	if _money(summary.get("raid_payout", null)).is_positive():
		_add_money_row("BEAT THE RAP", summary.get("raid_payout", BigMoney.zero()), Feel.COL_CLEAN)
	if _money(summary.get("confiscated", null)).is_positive():
		_add_money_row("CONFISCATED", summary.get("confiscated", BigMoney.zero()), Feel.COL_DIRTY)
	_add_money_row("CLEAN BALANCE", summary.get("clean", Game.wallet.clean), Feel.COL_CLEAN)
	_add_int_row("RESPECT GAINED", int(summary.get("respect", 0)), Feel.COL_BRASS.darkened(0.25))
	_add_int_row("JOBS DONE", int(summary.get("jobs_done", 0)), Feel.COL_INK)
	for name: Variant in summary.get("jobs", []):
		_body.add_child(PaperKit.label("   " + String(name), PaperKit.FONT_SMALL,
				Feel.COL_INK.lightened(0.35)))


func _add_money_row(text: String, value: Variant, color: Color, size: int = PaperKit.FONT_BODY) -> void:
	_rows.append(_row(text, color, size, _money(value), 0))


func _add_int_row(text: String, value: int, color: Color, size: int = PaperKit.FONT_BODY) -> void:
	_rows.append(_row(text, color, size, null, value))


static func _money(v: Variant) -> BigMoney:
	return v if v is BigMoney else BigMoney.zero()


func _row(text: String, color: Color, size: int, money: BigMoney, count: int) -> Dictionary:
	var line := HBoxContainer.new()
	var left := PaperKit.label(text, size, Feel.COL_INK)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := PaperKit.label("", size, color, HORIZONTAL_ALIGNMENT_RIGHT)
	right.custom_minimum_size = Vector2(300.0, 0.0)
	line.add_child(left)
	line.add_child(right)
	_body.add_child(line)
	return {"label": right, "money": money, "count": count}


func _build_roster() -> void:
	for c in _roster.get_children():
		c.queue_free()
	var held: Array[Dictionary] = []
	if Game.bench != null:
		held = Game.bench.holding()
	if held.is_empty():
		return
	_roster.add_child(PaperKit.label("IN HOLDING", PaperKit.FONT_SMALL,
			Feel.COL_INK.lightened(0.35)))
	for guy: Dictionary in held:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var name_label := PaperKit.label(String(guy["name"]), PaperKit.FONT_SMALL, Feel.COL_INK)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var cost := Game.bench.bail_cost(guy)
		var b := PaperKit.button("BAIL " + cost.text(), PaperKit.FONT_SMALL, Feel.COL_DIRTY)
		b.disabled = not Game.wallet.can_afford_dirty(cost)
		b.pressed.connect(_on_bail.bind(guy))
		row.add_child(b)
		_roster.add_child(row)


func _on_bail(guy: Dictionary) -> void:
	if Game.bail_guy(guy):
		_build_roster()


# --- the roll-up --------------------------------------------------------------


func _process(delta: float) -> void:
	if _row_index < 0 or _row_index >= _rows.size():
		if not _headline_shown:
			_show_headline()
		return
	_row_time += delta
	_tick_time += delta
	var t := clampf(_row_time / LINE_TIME, 0.0, 1.0)
	_paint_row(_rows[_row_index], t)
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


## True once every line has rolled up and the paper has printed.
func finished() -> bool:
	return _headline_shown


## Tap anywhere to stop the theatre and see the numbers — the ritual is a gift, not a toll.
func _input(event: InputEvent) -> void:
	var tapped := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not tapped:
		return
	if _row_index >= 0 and _row_index < _rows.size():
		skip()


## Finish every roll-up now.
func skip() -> void:
	for row in _rows:
		_paint_row(row, 1.0)
	_row_index = _rows.size()
	_show_headline()


func _show_headline() -> void:
	if _headline_shown:
		return
	_headline_shown = true
	_stop_counter()
	for row in _rows:
		_paint_row(row, 1.0)
	_headline.text = String(summary.get("headline", ""))
	_headline.modulate.a = 1.0
	AudioDirector.play(&"headline_sting")


func _stop_counter() -> void:
	if _counter != null and is_instance_valid(_counter):
		_counter.stop()
	_counter = null


## The screen can be torn down mid-tally (NEXT NIGHT on the first frame).
func _exit_tree() -> void:
	_stop_counter()
