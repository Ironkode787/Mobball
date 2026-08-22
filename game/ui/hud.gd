class_name GameHUD
extends CanvasLayer
## The real HUD (specs/m1-hook.md Lane 1): dirty, clean, Heat with its band ticks, Respect,
## the Night number and the combo flash — plus who is on the table right now, because the
## balls are guys (docs/01 §4).
##
## Signal-driven: it never polls the model except for the plunger charge, which is a
## per-frame value by nature.

const STRIP_H := 168.0
const HEAT_W := 470.0
const HEAT_H := 26.0
const COMBO_FLASH := 1.1

var night_controller: NightController = null

var _dirty: Label = null
var _clean: Label = null
var _night: Label = null
var _respect: Label = null
var _guy: Label = null
var _combo: Label = null
var _heat: HeatBar = null
var _charge: ProgressBar = null
var _star: StarBadge = null
var _combo_left: float = 0.0


func _ready() -> void:
	layer = 10
	var strip := ColorRect.new()
	strip.name = "Strip"
	strip.color = Feel.COL_INK
	strip.set_anchors_preset(Control.PRESET_TOP_WIDE)
	strip.offset_bottom = STRIP_H
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)

	var rule := ColorRect.new()
	rule.color = Feel.COL_BRASS.darkened(0.35)
	rule.set_anchors_preset(Control.PRESET_TOP_WIDE)
	rule.offset_top = STRIP_H
	rule.offset_bottom = STRIP_H + 3.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	_dirty = _add_label(Vector2(26.0, 14.0), PaperKit.FONT_BIG, Feel.COL_DIRTY)
	_clean = _add_label(Vector2(26.0, 74.0), PaperKit.FONT_BIG, Feel.COL_CLEAN)
	_night = _add_label(Vector2(0.0, 14.0), PaperKit.FONT_SMALL, Feel.COL_NEWSPRINT,
			HORIZONTAL_ALIGNMENT_RIGHT)
	_respect = _add_label(Vector2(0.0, 60.0), PaperKit.FONT_BIG, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_RIGHT)
	_guy = _add_label(Vector2(26.0, 124.0), PaperKit.FONT_SMALL,
			Feel.COL_NEWSPRINT.darkened(0.25))

	_star = StarBadge.new()
	_star.position = Vector2(1080.0 - 250.0, 74.0)
	_star.size = Vector2(34.0, 34.0)
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_star)

	_heat = HeatBar.new()
	_heat.position = Vector2(540.0 - HEAT_W * 0.5, 128.0)
	_heat.size = Vector2(HEAT_W, HEAT_H)
	_heat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_heat)

	_combo = _add_label(Vector2(0.0, 210.0), PaperKit.FONT_HUGE, Feel.COL_BRASS,
			HORIZONTAL_ALIGNMENT_CENTER)
	_combo.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_combo.offset_top = 210.0
	_combo.offset_bottom = 320.0
	_combo.modulate.a = 0.0

	_charge = ProgressBar.new()
	_charge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_charge.offset_left = 620.0
	_charge.offset_right = -40.0
	_charge.offset_top = -46.0
	_charge.offset_bottom = -14.0
	_charge.max_value = 1.0
	_charge.step = 0.001
	_charge.show_percentage = false
	_charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_charge)

	Game.wallet.dirty_changed.connect(_on_dirty)
	Game.wallet.clean_changed.connect(_on_clean)
	Game.heat.heat_changed.connect(_on_heat)
	Events.combo_changed.connect(_on_combo)
	Events.respect_changed.connect(_on_respect)
	Events.rank_changed.connect(_on_rank)
	Events.night_started.connect(_on_night)
	Events.guy_pinched.connect(_on_guy_changed)
	Events.plunger_charge_changed.connect(_on_charge)
	refresh()


func _add_label(at: Vector2, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := PaperKit.label("", size, color, align)
	l.set_anchors_preset(Control.PRESET_TOP_WIDE)
	l.offset_left = at.x
	l.offset_right = -26.0
	l.offset_top = at.y
	l.offset_bottom = at.y + float(size) + 12.0
	add_child(l)
	return l


func refresh() -> void:
	_on_dirty(Game.wallet.dirty)
	_on_clean(Game.wallet.clean)
	_on_heat(Game.heat.value)
	_on_respect(Game.respect)
	_on_night(Game.night_no)
	_update_guy()


func _process(delta: float) -> void:
	if _combo_left > 0.0:
		_combo_left = maxf(_combo_left - delta, 0.0)
		_combo.modulate.a = clampf(_combo_left / COMBO_FLASH, 0.0, 1.0)
	_update_guy()


func _update_guy() -> void:
	if _guy == null:
		return
	var text := ""
	if night_controller != null and is_instance_valid(night_controller) and night_controller.running:
		var guy := night_controller.current_guy()
		if not guy.is_empty():
			text = "%s   ·   %d up next" % [String(guy["name"]), night_controller.guys_left()]
	if text != _guy.text:
		_guy.text = text


# --- model signals ------------------------------------------------------------


func _on_dirty(v: BigMoney) -> void:
	_dirty.text = "DIRTY  " + v.text()


func _on_clean(v: BigMoney) -> void:
	_clean.text = "CLEAN  " + v.text()


func _on_heat(v: float) -> void:
	if _heat != null:
		_heat.set_heat(v)


func _on_respect(total: int) -> void:
	var next := Game.respect_to_next_rank()
	if next > 0:
		_respect.text = "%d   (%d to %s)" % [total, next, Headlines.rank_title(Game.rank + 1)]
	else:
		_respect.text = str(total)


func _on_rank(_rank: int) -> void:
	_on_respect(Game.respect)
	_on_night(Game.night_no)


func _on_night(n: int) -> void:
	_night.text = "NIGHT %d   ·   %s" % [n, Game.rank_title()]


func _on_guy_changed(_guy: Dictionary) -> void:
	_update_guy()


func _on_combo(count: int) -> void:
	if count < 2:
		_combo_left = 0.0
		_combo.modulate.a = 0.0
		return
	_combo.text = "x%d  CLEAN WORK" % count
	_combo_left = COMBO_FLASH
	_combo.modulate.a = 1.0


func _on_charge(power: float) -> void:
	if _charge != null:
		_charge.value = power


## The Heat dial with its band edges marked, so "surf at 90" is a readable instruction
## rather than a number to memorise (docs/03 §4).
class HeatBar:
	extends Control

	var value: float = 0.0

	func set_heat(v: float) -> void:
		if is_equal_approx(v, value):
			return
		value = v
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Feel.COL_INK.lightened(0.12))
		var f := clampf(value / Rates.HEAT_MAX, 0.0, 1.0)
		var band := Rates.band_for(value)
		var col := Color("FF7A2E")
		if band >= 4:
			col = Feel.COL_DIRTY
		elif band == 0:
			col = Color("FF7A2E").darkened(0.35)
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * f, size.y)), col)
		for t: float in Rates.BAND_THRESHOLDS:
			var x := size.x * clampf(t / Rates.HEAT_MAX, 0.0, 1.0)
			draw_line(Vector2(x, 0.0), Vector2(x, size.y), Feel.COL_NEWSPRINT, 2.0)
		draw_rect(r, Feel.COL_BRASS.darkened(0.3), false, 2.0)


## The brass ☆ next to the Respect count — drawn, because the default font has no star.
class StarBadge:
	extends Control

	func _draw() -> void:
		PaperKit.draw_star(self, size * 0.5, size.x * 0.5, Feel.COL_BRASS)
