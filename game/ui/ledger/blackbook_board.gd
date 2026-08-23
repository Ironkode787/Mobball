class_name LedgerBlackBook
extends Control
## THE BLACK BOOK — the prestige tree as the other page of the Ledger (docs/06 §3).
##
## Same corkboard, different currency. The Ledger's board is a conspiracy map of things you
## are going to buy with clean cash inside one career; this is the little book that survives
## the train, so it is laid out as a book: pages in cost order, a red string running down the
## spine, and the ★ pages you have not earned pinned face-down with their price on the back.
##
## It draws itself rather than hosting `LedgerCard`s: a perk card carries its own rule text
## (a Ledger node keeps that in the docket), so the card is twice the size and there is no
## docket at all — the footer bar is the whole transaction.
##
## Reads `Prestige` for the wallet and the owned map, `BlackBook` for the catalog. It never
## writes either: `buy_pressed` goes up to the Ledger, which owns the purchase.

signal perk_tapped(id: String)
signal buy_pressed(id: String)

const MARGIN := Vector2(44.0, 40.0)
const CARD_H := 214.0
const GAP := Vector2(28.0, 26.0)
const FOOTER_H := 132.0
## Movement (in screen px) past which a press is a scroll, not a tap.
const TAP_SLOP := 14.0
## Two columns while the page is wide enough for them to stay readable, one when it is not.
const MIN_COLUMN_W := 380.0

var book: BlackBook = null
var prestige: Prestige = null

var _font: Font = null
var _rects: Dictionary = {}
var _order: PackedStringArray = []
var _selected: String = ""
var _scroll: float = 0.0
var _content_h: float = 0.0
var _dragging: bool = false
var _drag_travel: float = 0.0
var _buy: Button = null


func _ready() -> void:
	_ensure_button()
	if not resized.is_connected(_relayout):
		resized.connect(_relayout)
	_relayout()


## Built on demand, not only in `_ready`: the headless runner never reaches a frame, and a
## page it builds still has to lay its cards out. Same reason as `LedgerBoard._ensure_layers`.
func _ensure_button() -> void:
	if _buy != null:
		return
	_font = get_theme_default_font()
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_buy = Button.new()
	_buy.custom_minimum_size = Vector2(340.0, 88.0)
	_buy.add_theme_font_size_override("font_size", 28)
	_buy.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_buy.offset_left = -376.0
	_buy.offset_right = -36.0
	_buy.offset_top = -110.0
	_buy.offset_bottom = -22.0
	_buy.pressed.connect(func() -> void: buy_pressed.emit(_selected))
	LedgerStyle.style_button(_buy, LedgerStyle.BRASS.darkened(0.1), LedgerStyle.INK)
	add_child(_buy)


# --- construction -------------------------------------------------------------


func build(from_book: BlackBook, from_prestige: Prestige) -> void:
	_ensure_button()
	book = from_book
	prestige = from_prestige
	_order = PackedStringArray()
	if book != null:
		_order = book.ids()
	_selected = ""
	_scroll = 0.0
	_relayout()


## Re-reads the wallet and the owned map. Cheap: thirteen painted cards and one button.
func refresh() -> void:
	_sync_button()
	queue_redraw()


func selected() -> String:
	return _selected


## Where a perk's card sits on the page, in page coordinates before the scroll offset.
## An empty Rect2 means the page is not carrying that perk.
func rect_of(id: String) -> Rect2:
	return _rects.get(id, Rect2())


## How tall the whole Book is, footer included — what the scroll clamps against.
func content_height() -> float:
	return _content_h


func select(id: String) -> void:
	_selected = id if book != null and book.has_id(id) else ""
	_sync_button()
	queue_redraw()


# --- layout -------------------------------------------------------------------


func _relayout() -> void:
	_rects.clear()
	if _order.is_empty() or size.x < 2.0:
		_content_h = 0.0
		_sync_button()
		return
	var columns := 2 if (size.x - MARGIN.x * 2.0 - GAP.x) * 0.5 >= MIN_COLUMN_W else 1
	var card_w := (size.x - MARGIN.x * 2.0 - GAP.x * float(columns - 1)) / float(columns)
	for i in _order.size():
		var col := i % columns
		var row := i / columns
		_rects[_order[i]] = Rect2(
			MARGIN.x + float(col) * (card_w + GAP.x),
			MARGIN.y + float(row) * (CARD_H + GAP.y),
			card_w, CARD_H
		)
	var rows := int(ceil(float(_order.size()) / float(columns)))
	_content_h = MARGIN.y * 2.0 + float(rows) * CARD_H + float(maxi(rows - 1, 0)) * GAP.y + FOOTER_H
	_clamp_scroll()
	_sync_button()
	queue_redraw()


func _clamp_scroll() -> void:
	var over := _content_h - size.y
	_scroll = clampf(_scroll, minf(-over, 0.0), 0.0)


# --- input --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll += 80.0
			_clamp_scroll()
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll -= 80.0
			_clamp_scroll()
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_travel = 0.0
			else:
				_dragging = false
				if _drag_travel < TAP_SLOP:
					_tap_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_drag_travel += mm.relative.length()
		_scroll += mm.relative.y
		_clamp_scroll()
		queue_redraw()
		accept_event()


func _tap_at(where: Vector2) -> void:
	var local := where - Vector2(0.0, _scroll)
	for id: Variant in _rects:
		if (_rects[id] as Rect2).has_point(local):
			select(String(id))
			perk_tapped.emit(String(id))
			return
	select("")


# --- the BUY button -----------------------------------------------------------


func _sync_button() -> void:
	if _buy == null:
		return
	if book == null or prestige == null or _selected == "":
		_buy.visible = false
		return
	_buy.visible = true
	var block := prestige.block_for(_selected)
	_buy.disabled = block != BlackBook.Block.NONE
	if block == BlackBook.Block.NONE:
		_buy.text = "BUY  ·  %s" % LedgerStyle.juice(book.next_cost(_selected, prestige.owned()))
		_buy.add_theme_font_size_override("font_size", 28)
	else:
		_buy.text = LedgerStyle.perk_block_reason(block, book, _selected, prestige)
		_buy.add_theme_font_size_override("font_size", 21)


# --- painting -----------------------------------------------------------------


func _draw() -> void:
	_paint_ground()
	if book == null or _order.is_empty():
		draw_string(_font, Vector2(MARGIN.x, MARGIN.y + 60.0), "THE BOOK IS EMPTY",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, Color(LedgerStyle.NEWSPRINT, 0.5))
		return
	var owned := prestige.owned() if prestige != null else {}
	var juice := prestige.juice if prestige != null else 0
	_paint_spine()
	for i in _order.size():
		var id := _order[i]
		_paint_card(id, owned, juice)
	_paint_footer(owned)


func _paint_ground() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, LedgerStyle.CORK.darkened(0.15))
	var rng := RandomNumberGenerator.new()
	rng.seed = 8813
	for i in 900:
		var p := Vector2(rng.randf() * size.x, rng.randf() * size.y)
		var col := LedgerStyle.CORK_SPECK if rng.randf() < 0.5 else LedgerStyle.INK
		draw_circle(p, rng.randf_range(1.2, 3.6), Color(col, rng.randf_range(0.18, 0.55)))
	# The ledger-paper rule lines of a little book, faint under the cards.
	var y := 60.0
	while y < size.y:
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(LedgerStyle.NEWSPRINT, 0.02), 1.0)
		y += 46.0


## The spine: one red string running page to page down the cost ladder, so the Book reads as
## an order — cheap promises first, the ones that change a run last.
func _paint_spine() -> void:
	for i in range(1, _order.size()):
		var a: Rect2 = _rects.get(_order[i - 1], Rect2())
		var b: Rect2 = _rects.get(_order[i], Rect2())
		if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
			continue
		var from := a.position + Vector2(a.size.x * 0.5, a.size.y) + Vector2(0.0, _scroll)
		var to := b.position + Vector2(b.size.x * 0.5, 0.0) + Vector2(0.0, _scroll)
		var sag := 18.0 + from.distance_to(to) * 0.10
		var ctrl := (from + to) * 0.5 + Vector2(0.0, sag)
		var pts := PackedVector2Array()
		for s in 15:
			var tt := float(s) / 14.0
			pts.append(from.lerp(ctrl, tt).lerp(ctrl.lerp(to, tt), tt))
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(2.0, 4.0))
		draw_polyline(shadow, Color(0.0, 0.0, 0.0, 0.28), 4.0)
		draw_polyline(pts, Color(LedgerStyle.DIRTY, 0.75), 3.0)


func _paint_card(id: String, owned: Dictionary, juice: int) -> void:
	var perk := book.def(id)
	if perk.is_empty():
		return
	var rect: Rect2 = _rects.get(id, Rect2())
	if rect.size == Vector2.ZERO:
		return
	rect.position.y += _scroll
	if rect.position.y > size.y or rect.end.y < 0.0:
		return
	var level := int(owned.get(id, 0))
	var deferred := bool(perk["deferred"])
	draw_rect(Rect2(rect.position + Vector2(5.0, 7.0), rect.size), LedgerStyle.SHADOW)
	if deferred:
		_paint_deferred(rect, perk)
	else:
		_paint_page(rect, perk, level, juice)
	if id == _selected:
		draw_rect(Rect2(rect.position - Vector2(5.0, 5.0), rect.size + Vector2(10.0, 10.0)),
			LedgerStyle.BRASS, false, 3.0)
	_paint_pin(rect.position + Vector2(rect.size.x * 0.5, 14.0),
		LedgerStyle.BRASS if not deferred else LedgerStyle.CARD_BACK_INK)


func _paint_page(rect: Rect2, perk: Dictionary, level: int, juice: int) -> void:
	var id := String(perk["id"])
	var max_level := int(perk["max_level"])
	var maxed := level >= max_level
	var accent := LedgerStyle.branch_color("blackbook")
	draw_rect(rect, LedgerStyle.PAPER_OWNED if level > 0 else LedgerStyle.PAPER)
	draw_rect(rect, LedgerStyle.PAPER_EDGE, false, 2.0)
	draw_rect(Rect2(rect.position, Vector2(7.0, rect.size.y)), accent)

	var pad := rect.position + Vector2(22.0, 0.0)
	draw_string(_font, pad + Vector2(0.0, 32.0), "BLACK BOOK", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 15, accent.darkened(0.15))
	if max_level > 1:
		var badge := "%d / %d" % [level, max_level]
		var bw := _font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
		draw_string(_font, rect.position + Vector2(rect.size.x - bw - 22.0, 32.0), badge,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, LedgerStyle.INK_SOFT)

	# Title, voice, rule, price — a page of a book, read top to bottom.
	draw_multiline_string(_font, pad + Vector2(0.0, 70.0), String(perk["name"]),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 28, 1, LedgerStyle.INK)
	draw_multiline_string(_font, pad + Vector2(0.0, 100.0), "“%s”" % String(perk["flavor"]),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 17, 1, Color(LedgerStyle.INK, 0.45))
	draw_multiline_string(_font, pad + Vector2(0.0, 136.0), String(perk["note"]),
		HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 44.0, 17, 2, Color(LedgerStyle.INK, 0.7))

	if maxed:
		_paint_stamp(rect, "IN THE BOOK")
	else:
		var cost := book.cost_at_level(id, level)
		var col := LedgerStyle.CLEAN.darkened(0.15) if juice >= cost else LedgerStyle.DIRTY
		var text := LedgerStyle.juice(cost)
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x
		draw_string(_font, rect.position + Vector2(rect.size.x - tw - 22.0, rect.size.y - 24.0),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, col)


## A ★ page: face-down, because the system behind it does not exist yet — but the price is
## written on the back, which is the honest way to sell a promise you cannot keep this build.
func _paint_deferred(rect: Rect2, perk: Dictionary) -> void:
	draw_rect(rect, LedgerStyle.CARD_BACK)
	var step := 22.0
	var x := -rect.size.y
	while x < rect.size.x:
		var x0 := maxf(x, 0.0)
		var x1 := minf(x + rect.size.y, rect.size.x)
		if x1 > x0:
			draw_line(rect.position + Vector2(x0, x0 - x), rect.position + Vector2(x1, x1 - x),
				LedgerStyle.CARD_BACK_LINE, 1.5)
		x += step
	draw_rect(Rect2(rect.position + Vector2(9.0, 9.0), rect.size - Vector2(18.0, 18.0)),
		LedgerStyle.CARD_BACK_LINE, false, 2.0)
	var c := rect.position + rect.size * 0.5
	var star := "★"
	var sw := _font.get_string_size(star, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 54).x
	draw_string(_font, c + Vector2(-sw * 0.5, -6.0), star, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 54,
		Color(LedgerStyle.BRASS, 0.65))
	var price := LedgerStyle.juice(int(perk["cost"]))
	var pw := _font.get_string_size(price, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24).x
	draw_string(_font, c + Vector2(-pw * 0.5, 44.0), price, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24,
		Color(LedgerStyle.BRASS, 0.8))
	var wait := "NOT IN THIS LIFE. YET."
	var ww := _font.get_string_size(wait, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	draw_string(_font, c + Vector2(-ww * 0.5, 76.0), wait, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16,
		LedgerStyle.CARD_BACK_INK)
	draw_rect(rect, LedgerStyle.INK * Color(1, 1, 1, 0.5), false, 2.0)


func _paint_stamp(rect: Rect2, text: String) -> void:
	var c := rect.position + Vector2(rect.size.x * 0.68, rect.size.y * 0.72)
	draw_set_transform(c, deg_to_rad(-11.0), Vector2.ONE)
	var ink := Color(LedgerStyle.BRASS.darkened(0.2), 0.85)
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24).x
	draw_rect(Rect2(-w * 0.5 - 16.0, -22.0, w + 32.0, 44.0), ink, false, 3.0)
	draw_string(_font, Vector2(-w * 0.5, 9.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 24, ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _paint_pin(at: Vector2, head: Color) -> void:
	if at.y < -20.0 or at.y > size.y + 20.0:
		return
	draw_circle(at, 9.0, head.darkened(0.45))
	draw_circle(at, 7.0, head)
	draw_circle(at + Vector2(-2.0, -2.0), 2.2, head.lightened(0.55))


## The transaction bar: what is selected, and what it costs. The BUY button is a real button
## sitting on top of this, so the bar only ever has to say who it is talking about.
func _paint_footer(owned: Dictionary) -> void:
	var top := size.y - FOOTER_H
	draw_rect(Rect2(0.0, top, size.x, FOOTER_H), Color(LedgerStyle.INK, 0.93))
	draw_rect(Rect2(0.0, top, size.x, 3.0), LedgerStyle.BRASS)
	if _selected == "" or book == null:
		draw_string(_font, Vector2(36.0, top + 74.0), "TAP A PAGE", HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, 26, Color(LedgerStyle.NEWSPRINT, 0.45))
		return
	var perk := book.def(_selected)
	if perk.is_empty():
		return
	var deferred := bool(perk["deferred"])
	var name_text := "★ NOT WRITTEN YET" if deferred else String(perk["name"]).to_upper()
	draw_string(_font, Vector2(36.0, top + 52.0), name_text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 30, LedgerStyle.NEWSPRINT)
	var level := int(owned.get(_selected, 0))
	var line := "%s  ·  %s" % [
		LedgerStyle.juice(book.cost_at_level(_selected, level)),
		"LEVEL %d OF %d" % [level, int(perk["max_level"])] if int(perk["max_level"]) > 1
			else ("OWNED" if level > 0 else "UNOWNED"),
	]
	draw_string(_font, Vector2(36.0, top + 88.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20,
		Color(LedgerStyle.BRASS, 0.85))
