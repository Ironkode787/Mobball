class_name Ledger
extends Control
## THE LEDGER — the upgrade tree as a corkboard conspiracy map (docs/04, docs/07 §4).
##
## Contract (specs/m1-hook.md): `res://game/ui/ledger/ledger.tscn`, root exposes `open()`,
## `close()` and the `closed` signal; the flow lane instantiates it lazily by path. The
## owned-levels map is NOT stored here — it lives in LedgerState so it outlives this node —
## but `get_owned()` / `set_owned()` are proxied here for the save system.
##
## Everything on screen is built in code (CLAUDE.md: keep .tscn minimal) and drawn from the
## palette. No textures ship with this screen.
##
## The screen has TWO pages behind one header: the corkboard (this career, bought with clean
## cash) and THE BLACK BOOK (every career, bought with Juice — docs/06 §3). The button in the
## header turns the page; nothing else about the Ledger changes, because it is one screen in
## the fiction: the stuff on the wall, and the little book in the coat.

signal closed

const HEADER_H := 168.0

## Which page the header is titling and the body is showing.
const PAGE_BOARD := &"board"
const PAGE_BOOK := &"blackbook"

## Mirrors `Commission.SPOIL_PREFIX`, kept as a literal so this screen does not compile
## against the flow lane's boss table (see `LedgerStyle.spoil_descriptor`, same reason).
const SPOIL_PREFIX := "spoil."
## Spoils the standalone render pretends to have taken, so the trophy shelf is in the shot.
## Live sessions read `Game.spoils()`; nothing else ever uses these.
const PREVIEW_SPOILS: PackedStringArray = ["spoil.sammys_spare", "spoil.cold_storage"]

var catalog: Upgrades = null
var reveal: Reveal = null
## The prestige half. `Prestige` is process-wide and outlives this node (and the career), the
## same way `LedgerState` does — the flow lane saves and restores it, this screen spends it.
var book: BlackBook = null
var prestige: Prestige = null

var _board: LedgerBoard = null
var _book_page: LedgerBlackBook = null
var _docket: LedgerDocket = null
var _compass: Button = null
var _zoom_btn: Button = null
var _close_btn: Button = null
var _book_btn: Button = null
var _font: Font = null
var _selected: String = ""
var _page: StringName = PAGE_BOARD
## Standalone render (tools/shot.sh) has no session behind it; the board then reads a fixed
## demo career instead of an empty one, so the screenshot shows real card states.
var _preview: bool = false
## The board and docket only exist after _ready; the meta layer exists from instantiation.
var _built: bool = false
var _open_wanted: bool = false


## Catalog and reveal are wired at instantiation, not at _ready, so `get_owned()` and
## `next_target()` answer correctly even if the flow lane asks before adding us to a tree.
func _init() -> void:
	catalog = Upgrades.shared()
	reveal = Reveal.shared()
	reveal.catalog = catalog
	book = BlackBook.shared()
	prestige = Prestige.shared()
	if prestige.catalog == null:
		prestige.catalog = book


func _ready() -> void:
	_font = get_theme_default_font()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_connect_events()
	_built = true
	if _is_standalone():
		_seed_preview()
		open()
		_apply_shot_framing()
	elif _open_wanted:
		open()
	else:
		visible = false


# --- public surface -----------------------------------------------------------


func open() -> void:
	_open_wanted = true
	if not _built:
		return
	visible = true
	_selected = ""
	_docket.dismiss()
	# A visit always starts on the corkboard: the Black Book is where you go, not where you are.
	_page = PAGE_BOARD
	_board.visible = true
	_book_page.visible = false
	_refresh()
	var target := next_target()
	if target != "":
		_board.center_on(target, false)
	_set_board_controls(true)


func close() -> void:
	_open_wanted = false
	visible = false
	closed.emit()


## Owned upgrade levels for the save system: node id (String) -> level (int).
func get_owned() -> Dictionary:
	return LedgerState.get_owned()


func set_owned(owned: Dictionary) -> void:
	LedgerState.set_owned(owned)
	if not _preview:
		Game.stats.recompute(LedgerState.get_owned())
	if _built and visible:
		_refresh()


## Cheapest node the player could buy right now; falls back to the cheapest one that is
## only waiting on money. Empty when the board has nothing left to sell.
func next_target() -> String:
	var owned := LedgerState.get_owned()
	var states := reveal.states(owned)
	var best := ""
	var best_cost: BigMoney = null
	var best_affordable := false
	for n in catalog.nodes:
		var id := String(n["id"])
		if int(states.get(id, Reveal.State.HIDDEN)) != Reveal.State.REVEALED:
			continue
		var block := catalog.block_for(id, owned, _rank(), _clean())
		if block != Upgrades.Block.NONE and block != Upgrades.Block.MONEY:
			continue
		var cost := catalog.next_cost(id, owned)
		var affordable := block == Upgrades.Block.NONE
		var better := best == ""
		if not better and affordable != best_affordable:
			better = affordable
		elif not better:
			better = cost.cmp(best_cost) < 0
		if better:
			best = id
			best_cost = cost
			best_affordable = affordable
	return best


# --- construction -------------------------------------------------------------


func _build() -> void:
	_board = LedgerBoard.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.offset_top = HEADER_H
	_board.card_tapped.connect(_on_card_tapped)
	add_child(_board)
	_board.build(catalog, _trophies())

	_book_page = LedgerBlackBook.new()
	_book_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_book_page.offset_top = HEADER_H
	_book_page.visible = false
	_book_page.buy_pressed.connect(_on_perk_buy)
	add_child(_book_page)
	_book_page.build(book, prestige)

	_close_btn = _button("CLOSE", Vector2(190.0, 74.0), Color(LedgerStyle.DIRTY, 0.85), LedgerStyle.NEWSPRINT)
	_close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.offset_left = -220.0
	_close_btn.offset_right = -30.0
	_close_btn.offset_top = 26.0
	_close_btn.offset_bottom = 96.0
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	_book_btn = _button("BLACK BOOK", Vector2(300.0, 74.0),
		Color(LedgerStyle.branch_color("blackbook"), 0.85), LedgerStyle.NEWSPRINT)
	_book_btn.add_theme_font_size_override("font_size", 22)
	_book_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_book_btn.offset_left = -540.0
	_book_btn.offset_right = -240.0
	_book_btn.offset_top = 26.0
	_book_btn.offset_bottom = 96.0
	_book_btn.pressed.connect(_on_turn_page)
	add_child(_book_btn)

	_zoom_btn = _button("ZOOM", Vector2(150.0, 84.0), Color(LedgerStyle.INK, 0.72), LedgerStyle.BRASS)
	_zoom_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_zoom_btn.offset_left = 36.0
	_zoom_btn.offset_right = 186.0
	_zoom_btn.offset_top = -124.0
	_zoom_btn.offset_bottom = -40.0
	_zoom_btn.pressed.connect(_on_zoom)
	add_child(_zoom_btn)

	_compass = _button("NEXT BUY  ▸", Vector2(330.0, 84.0), Color(LedgerStyle.BRASS, 0.92), LedgerStyle.INK)
	_compass.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_compass.offset_left = -366.0
	_compass.offset_right = -36.0
	_compass.offset_top = -124.0
	_compass.offset_bottom = -40.0
	_compass.pressed.connect(_on_compass)
	add_child(_compass)

	# Added last: the docket slides over the board controls, never under them.
	_docket = LedgerDocket.new()
	_docket.buy_pressed.connect(_on_buy)
	_docket.dismissed.connect(_on_docket_dismissed)
	add_child(_docket)


func _connect_events() -> void:
	# Reveal marks are sticky and the Ledger is instantiated lazily, so these only catch
	# what happens while the board is alive; `_refresh` re-syncs rank and held dirty on
	# every open. See the report: the flow lane owns the durable hook.
	if not Events.tilted.is_connected(_on_tilted):
		Events.tilted.connect(_on_tilted)
	if not Events.rank_changed.is_connected(_on_rank_changed):
		Events.rank_changed.connect(_on_rank_changed)
	if not Events.dirty_earned.is_connected(_on_dirty_earned):
		Events.dirty_earned.connect(_on_dirty_earned)


# --- state --------------------------------------------------------------------


func _refresh() -> void:
	if not _built:
		return
	if _page == PAGE_BOOK:
		_book_page.refresh()
		queue_redraw()
		return
	var owned := LedgerState.get_owned()
	reveal.rank = _rank()
	reveal.note_dirty_held(_dirty())
	_board.set_trophies(_trophies())
	# `observe`, not `states`: the board banks what flipped, it never drains the queue. Seeing
	# a card here does not spend the Count's stinger (docs/04 — the flip is a scripted beat).
	_board.refresh(reveal.observe(owned), owned, _rank(), _clean())
	if _selected != "":
		_show_docket(_selected)
	queue_redraw()


# --- the Black Book page ------------------------------------------------------


## Turns the page. The corkboard keeps its pan, its zoom and its selection while it is away.
func _on_turn_page() -> void:
	_page = PAGE_BOARD if _page == PAGE_BOOK else PAGE_BOOK
	var on_book := _page == PAGE_BOOK
	_book_btn.text = "THE LEDGER" if on_book else "BLACK BOOK"
	_book_page.visible = on_book
	_board.visible = not on_book
	if on_book:
		_docket.dismiss()
		_set_board_controls(false)
	else:
		_set_board_controls(_selected == "")
	_refresh()


## A Juice purchase. Same shape as `_on_buy` one page over: the Book decides whether it is
## allowed, the wallet moves, and the save follows immediately — Juice is too expensive to
## lose to a kill -9.
func _on_perk_buy(id: String) -> void:
	if id.is_empty() or prestige.buy(id) <= 0:
		return
	AudioDirector.play(&"stamp_thunk")
	if not _preview:
		Game.save_now()
	_refresh()


## The trophy shelf, as descriptors for the board (`spoil.*`, docs/05 §6). Names come from the
## flow lane's own fight table via `LedgerStyle.spoil_descriptor`.
##
## Anything the CURRENT career has taken is nailed to the prestige shelf on the way past,
## because docs/06 §1 keeps spoils across Skip Town while the career's owned map does not
## survive it. The wall is the one place a player's whole history is visible at once.
func _trophies() -> Array[Dictionary]:
	for id in _spoil_ids():
		prestige.remember_spoil(id)
	var out: Array[Dictionary] = []
	for id in prestige.trophies():
		out.append(LedgerStyle.spoil_descriptor(id))
	return out


func _spoil_ids() -> PackedStringArray:
	if _preview:
		return PREVIEW_SPOILS
	# `spoils()` is the flow lane's, and the flow lane is allowed to move: a Ledger with no
	# trophy shelf is a smaller loss than a Ledger that will not open.
	if not Game.has_method("spoils"):
		return PackedStringArray()
	return Game.spoils()


func _show_docket(id: String) -> void:
	var node_def := catalog.def(id)
	if node_def.is_empty() or not _built:
		return
	var owned := LedgerState.get_owned()
	var block := catalog.block_for(id, owned, _rank(), _clean())
	_docket.show_for(
		node_def, int(owned.get(id, 0)), catalog.next_cost(id, owned), block,
		LedgerStyle.block_reason(block, node_def, catalog, owned)
	)
	_set_board_controls(false)


func _on_card_tapped(id: String) -> void:
	if not _built:
		return
	if id.begins_with(SPOIL_PREFIX):
		# A trophy has no docket and no price. It is a photograph of a night that already
		# happened, and tapping a photograph does nothing.
		return
	var state := reveal.state_of(id, LedgerState.get_owned())
	if state != Reveal.State.REVEALED:
		# A face-down card has nothing to say yet. That is the point of it.
		return
	_selected = id
	_board.set_selected(id)
	_show_docket(id)


func _set_board_controls(v: bool) -> void:
	# The compass and the zoom rungs belong to the corkboard; the Black Book page has neither.
	var on_board := v and _page == PAGE_BOARD
	_compass.visible = on_board
	_zoom_btn.visible = on_board


func _on_docket_dismissed() -> void:
	_selected = ""
	_board.set_selected("")
	_docket.dismiss()
	_set_board_controls(true)


func _on_compass() -> void:
	var target := next_target()
	if target == "":
		return
	_board.center_on(target)
	_on_card_tapped(target)


func _on_zoom() -> void:
	_board.cycle_zoom()


func _on_tilted() -> void:
	if reveal.mark_event(&"first_tilt") and visible:
		_refresh()


func _on_rank_changed(_rank_value: int) -> void:
	if visible:
		_refresh()


func _on_dirty_earned(_amount: BigMoney, _group: StringName) -> void:
	# Held dirty is a reveal condition (docs/04: "first $10k held"), so it is watched even
	# though the Ledger only ever spends clean.
	if reveal.note_dirty_held(_dirty()) > 0 and visible:
		_refresh()


## The purchase: rank, requires and clean cash all have to agree, then the money moves,
## the level goes up, Stats rebuilds from the new owned map and the table hears about it.
func _on_buy(id: String) -> void:
	var owned := LedgerState.get_owned()
	var node_def := catalog.def(id)
	if node_def.is_empty():
		return
	if _rank() < int(node_def["tier"]) or not catalog.requires_met(id, owned):
		return
	if int(owned.get(id, 0)) >= int(node_def["max_level"]):
		return
	var cost := catalog.next_cost(id, owned)
	if not Game.wallet.can_afford_clean(cost):
		return
	if not Game.wallet.spend_clean(cost):
		return
	var level := LedgerState.add_level(id)
	Game.stats.recompute(LedgerState.get_owned())
	Events.upgrade_purchased.emit(id, level)
	AudioDirector.play(&"stamp_thunk")
	_refresh()


# --- session accessors --------------------------------------------------------


func _rank() -> int:
	return 2 if _preview else Game.rank


func _clean() -> BigMoney:
	return BigMoney.parse("90K") if _preview else Game.wallet.clean


func _dirty() -> BigMoney:
	return BigMoney.parse("14K") if _preview else Game.wallet.dirty


func _is_standalone() -> bool:
	if get_tree().current_scene == self:
		return true
	return OS.get_environment("SHOT_SCENE").ends_with("ledger.tscn")


## A plausible mid-R2 career, so the preview shows owned, affordable, locked and face-down
## cards at once instead of a board of identical unaffordable rectangles.
func _seed_preview() -> void:
	_preview = true
	LedgerState.set_owned({
		"muscle.real_plunger": 1, "rackets.trash_2": 1, "rackets.trash_3": 1,
		"rackets.can_deposits": 4, "muscle.corner_boys": 1, "muscle.fresh_rubbers": 2,
		"rackets.numbers_game": 1, "fronts.coin_op": 1, "muscle.second_wind": 1,
	})
	reveal.mark_event(&"first_tilt")
	reveal.note_dirty_held(_dirty())
	# …and one Skip Town behind it, so the Black Book page shows every state it has: bought,
	# affordable, too dear, and face-down.
	prestige.from_dict({
		"juice": 6, "earned": 14, "cities": 1,
		"owned": {"blackbook.old_contacts": 2, "blackbook.traveling_light": 1},
	})


## Framing hooks for tools/shot.sh, so evidence renders need no code edits. Preview only.
func _apply_shot_framing() -> void:
	# SHOT_CATALOG renders a candidate content file instead of the shipped one — how a draft
	# of the T4-T5 tier or a new specialist gets looked at before it is committed.
	var alt := OS.get_environment("SHOT_CATALOG")
	if alt != "" and FileAccess.file_exists(alt):
		catalog = Upgrades.from_file(alt)
		reveal.catalog = catalog
		_board.build(catalog, _trophies())
		_refresh()
	# SHOT_PAGE=blackbook renders the prestige page instead of the corkboard; SHOT_PERK picks
	# the page it opens with selected, which is how a new perk gets looked at before it lands.
	if OS.get_environment("SHOT_PAGE") == String(PAGE_BOOK):
		_on_turn_page()
		var perk := OS.get_environment("SHOT_PERK")
		if perk != "" and book.has_id(perk):
			_book_page.select(perk)
		return
	var z := OS.get_environment("SHOT_ZOOM")
	if z.is_valid_float():
		_board.set_zoom(z.to_float())
	# SHOT_CENTER frames any card without opening its docket — the only way to photograph a
	# card that HAS no docket, which is exactly what a trophy is.
	var center := OS.get_environment("SHOT_CENTER")
	if center != "":
		_board.center_on(center, false)
		return
	var docket_id := OS.get_environment("SHOT_DOCKET")
	if docket_id == "":
		return
	var id := docket_id if catalog.has_id(docket_id) else next_target()
	_board.center_on(id, false)
	_on_card_tapped(id)


# --- header -------------------------------------------------------------------


func _draw() -> void:
	var w := size.x
	draw_rect(Rect2(0.0, 0.0, w, HEADER_H), LedgerStyle.INK)
	draw_rect(Rect2(0.0, HEADER_H - 3.0, w, 3.0), LedgerStyle.BRASS)
	if _page == PAGE_BOOK:
		_draw_book_header(w)
		return
	draw_string(_font, Vector2(36.0, 74.0), "THE LEDGER", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 48, LedgerStyle.NEWSPRINT)
	draw_string(_font, Vector2(38.0, 106.0), "EVIDENCE PHOTO 44-C", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color(LedgerStyle.BRASS, 0.7))

	var rank_text := "R%d" % _rank()
	var rw := _font.get_string_size(rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x
	draw_rect(Rect2(36.0, 122.0, rw + 26.0, 34.0), Color(LedgerStyle.BRASS, 0.9))
	draw_string(_font, Vector2(49.0, 148.0), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26, LedgerStyle.INK)

	# The Ledger only takes clean, so clean is the headline and dirty is the reminder.
	var clean_text := _clean().text()
	var cw := _font.get_string_size(clean_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42).x
	var cx := w - 250.0 - cw
	draw_string(_font, Vector2(cx, 148.0), clean_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42, LedgerStyle.CLEAN)
	draw_string(_font, Vector2(cx, 112.0), "CLEAN", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(LedgerStyle.CLEAN, 0.6))
	var dirty_text := _dirty().text()
	var dw := _font.get_string_size(dirty_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x
	draw_string(_font, Vector2(cx - dw - 34.0, 148.0), dirty_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(LedgerStyle.DIRTY, 0.85))


## The Black Book's header. Same bar, different currency: Juice where clean cash goes, and
## the city count where the rank badge goes — this page belongs to the player, not the career.
func _draw_book_header(w: float) -> void:
	draw_string(_font, Vector2(36.0, 74.0), "THE BLACK BOOK", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 48,
		LedgerStyle.NEWSPRINT)
	draw_string(_font, Vector2(38.0, 106.0), "WITNESS RELOCATION FORM 12-B",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 19, Color(LedgerStyle.BRASS, 0.7))

	var city_text := "CITY %d" % prestige.city_number()
	var cw := _font.get_string_size(city_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22).x
	draw_rect(Rect2(36.0, 122.0, cw + 26.0, 34.0), Color(LedgerStyle.BRASS, 0.9))
	draw_string(_font, Vector2(49.0, 148.0), city_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22,
		LedgerStyle.INK)

	var juice_text := str(prestige.juice)
	var jw := _font.get_string_size(juice_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42).x
	var jx := w - 250.0 - jw
	draw_string(_font, Vector2(jx, 148.0), juice_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 42,
		LedgerStyle.BRASS)
	draw_string(_font, Vector2(jx, 112.0), "JUICE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18,
		Color(LedgerStyle.BRASS, 0.6))
	var earned := "%d EARNED" % prestige.juice_earned
	var ew := _font.get_string_size(earned, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
	draw_string(_font, Vector2(jx - ew - 34.0, 148.0), earned, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20,
		Color(LedgerStyle.NEWSPRINT, 0.45))


func _button(text: String, min_size: Vector2, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 26)
	LedgerStyle.style_button(b, bg, fg)
	return b
