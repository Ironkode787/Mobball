class_name GameHUD
extends CanvasLayer
## The real HUD (specs/m1-hook.md Lane 1): dirty, clean, Heat with its band ticks, Respect,
## the Night number and the combo flash — plus who is on the table right now, because the
## balls are guys (docs/01 §4).
##
## M2 hangs the modes under the strip: the Wire's tote board, the Collection Round's clock,
## whether the back room is lit and whether the Family Meeting is running. Each line only
## exists while it has something to say — a mode line that is always there is furniture.
##
## Signal-driven for state, per-frame for clocks (a countdown is a per-frame value by nature,
## as is the plunger charge).

const STRIP_H := 168.0
const HEAT_W := 470.0
const HEAT_H := 26.0
const COMBO_FLASH := 1.1
## How long Manny's collect stays on the mode strip.
const AUTO_COLLECT_FLASH := 2.5
## Where the mode lines hang, and how tall each one is.
const MODES_TOP := STRIP_H + 16.0
const MODE_H := 34.0

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
var _modes: VBoxContainer = null
var _wire: Label = null
var _collect: Label = null
var _meeting: Label = null
var _casino: Label = null
var _boss: Label = null
## Manny's collect, flashed for a beat so an off-screen earner is still visible.
var _flash: String = ""
var _flash_left: float = 0.0


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

	_build_modes()

	Game.wallet.dirty_changed.connect(_on_dirty)
	Game.wallet.clean_changed.connect(_on_clean)
	Game.heat.heat_changed.connect(_on_heat)
	Events.combo_changed.connect(_on_combo)
	Events.respect_changed.connect(_on_respect)
	Events.rank_changed.connect(_on_rank)
	Events.night_started.connect(_on_night)
	Events.guy_pinched.connect(_on_guy_changed)
	Events.plunger_charge_changed.connect(_on_charge)
	Game.auto_collected.connect(_on_auto_collected)
	refresh()


## The mode lines. Nothing is laid out per-mode: they stack, and a line with no text takes
## no room, so the block grows and shrinks with what is actually happening.
func _build_modes() -> void:
	_modes = VBoxContainer.new()
	_modes.name = "Modes"
	_modes.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_modes.offset_left = 26.0
	_modes.offset_right = -26.0
	_modes.offset_top = MODES_TOP
	_modes.offset_bottom = MODES_TOP + MODE_H * 5.0
	_modes.add_theme_constant_override("separation", 2)
	_modes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_modes)

	# The Commission goes first: while a fight is on, it is the only thing on the table.
	_boss = _add_mode(Feel.COL_DIRTY)
	_meeting = _add_mode(Feel.COL_BRASS)
	_collect = _add_mode(Feel.COL_CLEAN)
	_wire = _add_mode(Feel.COL_NEWSPRINT.darkened(0.2))
	_casino = _add_mode(Color("FF2E63"))


func _add_mode(color: Color) -> Label:
	var l := PaperKit.label("", PaperKit.FONT_SMALL, color)
	l.visible = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modes.add_child(l)
	return l


static func _set_mode(l: Label, text: String) -> void:
	if l == null:
		return
	if l.text != text:
		l.text = text
	l.visible = not text.is_empty()


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
	_update_modes()


func _process(delta: float) -> void:
	if _combo_left > 0.0:
		_combo_left = maxf(_combo_left - delta, 0.0)
		_combo.modulate.a = clampf(_combo_left / COMBO_FLASH, 0.0, 1.0)
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
		if _flash_left <= 0.0:
			_flash = ""
	_update_guy()
	_update_modes()


# --- the modes ----------------------------------------------------------------


## Four clocks and lights, drawn from the model every frame because three of them are
## counting down. Anything with nothing to say renders as an empty line and disappears.
func _update_modes() -> void:
	if _modes == null:
		return
	_set_mode(_boss, _boss_text())
	_set_mode(_meeting, _meeting_text())
	_set_mode(_collect, _collection_text())
	_set_mode(_wire, _wire_text())
	_set_mode(_casino, _casino_text())


## The fight, when there is one: who, which phase, and what he is doing to you right now.
## Manny's collect rides the same line when nothing is fighting, because both are "something
## happened that you did not do with the flippers".
func _boss_text() -> String:
	var fight := Game.boss
	if fight != null and is_instance_valid(fight) and bool(fight.get("active")):
		var line := String(fight.call("phase_line")) if fight.has_method("phase_line") else ""
		return "%s   ·   PHASE %d/%d%s" % [String(fight.get("boss_name")),
				mini(int(fight.get("phase")), int(fight.get("phases"))),
				int(fight.get("phases")), "" if line.is_empty() else "   ·   " + line]
	return _flash


func _meeting_text() -> String:
	if Game.meeting.active:
		return "FAMILY MEETING   ·   ALL DIRTY x%d   ·   BACK ROOM %s" \
				% [int(FamilyMeeting.DIRTY_MULT),
					Game.meeting.jackpot_value(Game.stats.idle_rate_total()).text()]
	if Game.meeting.lit:
		return "BACK ROOM LIT   ·   FAMILY MEETING READY"
	var need := FamilyMeeting.JACKPOTS_TO_LIGHT - Game.meeting.jackpots_tonight
	if Game.casino.night_jackpots > 0 and need > 0:
		return "BACK ROOM   ·   %d MORE JACKPOT%s" % [need, "" if need == 1 else "S"]
	return ""


func _collection_text() -> String:
	if not Game.collection.active:
		return ""
	return "COLLECTION ROUND   ·   %d/3   ·   %0.1fs" \
			% [Game.collection.collected_count(), maxf(Game.collection.time_left, 0.0)]


func _wire_text() -> String:
	if Game.wire.draws <= 0 and Game.wire.time_left >= WireDraws.PERIOD - 0.05:
		return ""
	var ticket := 0
	var live := Game.night as NightController
	if live != null and is_instance_valid(live):
		ticket = posmod(int(TableAPI.call_if(live.table, "spinner_spins", [], 0)),
				WireDraws.NUMBERS)
	var drawn := "--" if Game.wire.last_number < 0 else "%02d" % Game.wire.last_number
	var line := "THE WIRE   ·   DREW %s   ·   YOUR TICKET %02d   ·   NEXT %ds" \
			% [drawn, ticket, int(ceilf(maxf(Game.wire.time_left, 0.0)))]
	# The Wiretap: the number arrives before the draw does, and the spinner is the bet slip.
	var early := Game.wire.early_number(Game.stats.flag(&"wiretap_wire"))
	if early >= 0:
		line += "   ·   WIRETAP SAYS %02d" % early
	return line


func _casino_text() -> String:
	var armed := Game.casino.armed_multiplier()
	if armed > 1.0:
		# The ladder rides the BET, not the payout (balance-sim ruling), and the HUD has to say
		# so — a player who reads "next payout" is being sold an edge he did not buy.
		return "HIGH ROLLER   ·   NEXT BET x%d" % int(armed)
	if Game.casino.loss_streak >= Casino.CasinoRules.COOLER_STREAK:
		return "THE COOLER GOT FIRED   ·   NEXT WIN PAYS MORE"
	return ""


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


## Manny walked a till while you were busy (`auto_collect_interval`).
func _on_auto_collected(id: StringName, amount: BigMoney) -> void:
	var shop := String(id).replace("storefront_", "").to_upper()
	_flash = "MANNY COLLECTED %s   ·   %s" % [shop, amount.text()]
	_flash_left = AUTO_COLLECT_FLASH


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
