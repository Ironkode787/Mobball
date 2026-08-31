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

## The old surface spent 194 logical px on an empty masthead. 164 keeps the title, wallet,
## page switch, and safe top inset while returning a meaningful slice of board to the phone.
const HEADER_H := 164.0
const FOOTER_H := 136.0
const DOCKET_RESERVATION_H := 660.0

## Which page the header is titling and the body is showing.
const PAGE_BOARD := &"board"
const PAGE_BOOK := &"blackbook"

## Mirrors `Commission.SPOIL_PREFIX`, kept as a literal so this screen does not compile
## against the flow lane's boss table (see `LedgerStyle.spoil_descriptor`, same reason).
const SPOIL_PREFIX := "spoil."
## Spoils the standalone render pretends to have taken, so the trophy shelf is in the shot.
## Live sessions read `Game.spoils()`; nothing else ever uses these.
const PREVIEW_SPOILS: PackedStringArray = ["spoil.sammys_spare", "spoil.cold_storage"]
const PORTRAIT_FACES := {
	"skids": 1, "nussbaum": 2, "big_sal": 3, "professor": 4,
	"rosa": 2, "cohen": 4, "manny": 1, "eddie": 3, "consigliere": 4, "bagman": 2,
}


## A shallow wood rail and brass tacks around the board. LedgerBoard owns the pan-able cork;
## this stays fixed to the cabinet so the map feels pinned into a physical evidence frame.
class LedgerMaterialFrame extends Control:
	var header_bottom := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_header_bottom(value: float) -> void:
		header_bottom = value
		queue_redraw()

	func _draw() -> void:
		if size.x < 2.0 or size.y <= header_bottom:
			return
		var rail := 18.0
		var body := Rect2(0.0, header_bottom, size.x, size.y - header_bottom)
		# These rails are intentionally narrow: the board remains the tactile hero, while the
		# fixed edge gives the moving sheet a cabinet to live in.
		draw_rect(Rect2(0.0, body.position.y, rail, body.size.y), LedgerStyle.CORK_LIGHT)
		draw_rect(Rect2(size.x - rail, body.position.y, rail, body.size.y), LedgerStyle.CORK_LIGHT)
		draw_rect(Rect2(0.0, body.position.y, size.x, 7.0), LedgerStyle.BRASS)
		draw_line(Vector2(rail, body.position.y + 12.0), Vector2(rail, size.y),
			Color(LedgerStyle.BRASS, 0.36), 2.0)
		draw_line(Vector2(size.x - rail, body.position.y + 12.0), Vector2(size.x - rail, size.y),
			Color(LedgerStyle.BRASS, 0.36), 2.0)
		for y in range(int(body.position.y + 66.0), int(size.y), 184):
			var left := Vector2(rail * 0.5, float(y))
			var right := Vector2(size.x - rail * 0.5, float(y))
			_draw_tack(left)
			_draw_tack(right)

	func _draw_tack(at: Vector2) -> void:
		draw_circle(at + Vector2(2.0, 3.0), 8.0, Color(0.0, 0.0, 0.0, 0.35))
		draw_circle(at, 6.0, LedgerStyle.BRASS.darkened(0.36))
		draw_circle(at + Vector2(-1.5, -1.5), 2.0, LedgerStyle.BRASS.lightened(0.38))


## The purchase beat is a local overlay on the card, so it follows the board's zoom and pan.
## It is cosmetic only; the economy has already committed by the time this is attached.
class LedgerPurchaseStamp extends Control:
	var progress := 0.0:
		set(value):
			progress = clampf(value, 0.0, 1.0)
			queue_redraw()

	var _font: Font = null

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		_font = Presentation.theme.font_for(&"annotation_bold")

	func set_progress(value: float) -> void:
		progress = value

	func _draw() -> void:
		if _font == null or progress <= 0.0:
			return
		var eased := 1.0 - pow(1.0 - progress, 3.0)
		var center := Vector2(size.x * 0.5, size.y * 0.5)
		var alpha := clampf(eased * 0.84, 0.0, 0.84)
		for i in 8:
			var angle := TAU * float(i) / 8.0
			var ray := center + Vector2(cos(angle), sin(angle)) * (24.0 + eased * 78.0)
			draw_line(center, ray, Color(LedgerStyle.BRASS, alpha * 0.46), 2.0)
		draw_set_transform(center, deg_to_rad(-10.0 + eased * 3.0), Vector2.ONE * eased)
		var rect := Rect2(-84.0, -25.0, 168.0, 50.0)
		draw_rect(Rect2(rect.position + Vector2(4.0, 5.0), rect.size), Color(0.0, 0.0, 0.0, alpha * 0.35))
		draw_rect(rect, Color(LedgerStyle.DIRTY, alpha), false, 3.0)
		var text := "PINNED"
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26).x
		draw_string(_font, Vector2(-w * 0.5, 9.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26,
			Color(LedgerStyle.DIRTY, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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
var _safe_margins := Vector4.ZERO
var _material_frame: LedgerMaterialFrame = null
var _profile := "standard"
## Standalone captures can lower this without touching the live Game wallet. Live sessions
## always read Game.wallet.clean, so the preview affordance cannot become a gameplay override.
var _preview_clean := BigMoney.parse("90K")


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
	_font = Presentation.theme.font_for(&"headline")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_apply_safe_area()
	Presentation.safe.margins_changed.connect(_on_safe_margins_changed)
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


func _on_safe_margins_changed(_margins: Vector4) -> void:
	_apply_safe_area()


func _apply_safe_area() -> void:
	if _board == null:
		return
	_safe_margins = Presentation.safe.margins()
	_profile = _current_profile()
	var header_bottom := HEADER_H + _safe_margins.y
	_board.offset_top = header_bottom
	_book_page.offset_top = header_bottom
	_book_page.set_safe_margins(_safe_margins)

	var close_right := -(_safe_margins.z + 24.0)
	_close_btn.offset_left = close_right - 168.0
	_close_btn.offset_right = close_right
	_close_btn.offset_top = _safe_margins.y + 18.0
	_close_btn.offset_bottom = _safe_margins.y + 114.0
	_book_btn.offset_right = _close_btn.offset_left - 16.0
	_book_btn.offset_left = _book_btn.offset_right - 228.0
	_book_btn.offset_top = _safe_margins.y + 18.0
	_book_btn.offset_bottom = _safe_margins.y + 114.0

	_zoom_btn.offset_left = _safe_margins.x + 36.0
	_zoom_btn.offset_right = _zoom_btn.offset_left + 206.0
	_zoom_btn.offset_bottom = -(_safe_margins.w + 32.0)
	_zoom_btn.offset_top = _zoom_btn.offset_bottom - 96.0
	_compass.offset_right = -(_safe_margins.z + 36.0)
	_compass.offset_left = _compass.offset_right - 300.0
	_compass.offset_bottom = -(_safe_margins.w + 32.0)
	_compass.offset_top = _compass.offset_bottom - 96.0
	if _material_frame != null:
		_material_frame.set_header_bottom(header_bottom)
	queue_redraw()


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


## Read-only geometry for the D4 subtitle/toast arbiter and capture tooling. All rectangles
## are in this Ledger's logical viewport coordinates, never in host physical pixels.
func geometry_contract() -> Dictionary:
	_profile = _current_profile()
	var logical := size
	var safe := Presentation.safe.content_rect().intersection(Rect2(Vector2.ZERO, logical))
	return {
		"schema": "kingpin.ledger.geometry.v1",
		"profile": _profile,
		"requested_physical_size": Vector2i(ProjectSettings.get_setting(
			"display/window/size/viewport_width", 1080), ProjectSettings.get_setting(
			"display/window/size/viewport_height", 1920)),
		"actual_physical_size": Vector2i(DisplayServer.window_get_size()),
		"logical_viewport": logical,
		"safe_content": safe,
		"page": String(_page),
		"reservations": content_reservations(),
	}


func _current_profile() -> String:
	var physical_width: int = DisplayServer.window_get_size().x
	var width: float = float(physical_width) if physical_width > 0 else size.x
	return "compact" if width < 820.0 else "standard"


func geometry_snapshot() -> Dictionary:
	return geometry_contract()


func content_reservations() -> Dictionary:
	var header := Rect2(0.0, 0.0, size.x, HEADER_H + _safe_margins.y)
	var board := Rect2(0.0, header.end.y, size.x, maxf(size.y - header.end.y - FOOTER_H, 0.0))
	var footer := Rect2(0.0, maxf(size.y - FOOTER_H - _safe_margins.w, board.position.y),
		size.x, FOOTER_H + _safe_margins.w)
	var docket := Rect2()
	if _docket != null and _docket.is_open():
		docket = Rect2(0.0, maxf(size.y - DOCKET_RESERVATION_H, 0.0), size.x,
		DOCKET_RESERVATION_H)
	var selected_rect := _board.card_rect_in_view(_selected) if _board != null else Rect2()
	if _board != null and selected_rect.size.x > 0.0 and selected_rect.size.y > 0.0:
		# Board coordinates begin below the fixed masthead. Publish the selected card in this
		# Ledger's space so D4 can subtract it without knowing the scene tree transform.
		selected_rect.position += _board.position
	return {
		"header": header,
		"board_viewport": board,
		"footer": footer,
		"footer_actions": {
			"next_buy": _compass.get_global_rect() if _compass != null and _compass.visible else Rect2(),
			"fit_focus": _zoom_btn.get_global_rect() if _zoom_btn != null and _zoom_btn.visible else Rect2(),
			"close": _close_btn.get_global_rect() if _close_btn != null else Rect2(),
		},
		"selected_card": selected_rect,
		"docket": docket,
		"subtitle_safe_region": Rect2(board.position + Vector2(32.0, 24.0),
			Vector2(maxf(board.size.x - 64.0, 0.0), maxf(board.size.y - 48.0, 0.0))),
		"subtitle_exclusion_rects": [header, footer, docket, selected_rect],
		"board": _board.geometry_contract() if _board != null else {},
	}


# --- construction -------------------------------------------------------------


func _build() -> void:
	_board = LedgerBoard.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.offset_top = HEADER_H
	_board.card_tapped.connect(_on_card_tapped)
	add_child(_board)
	_board.build(catalog, _trophies())
	_install_portrait_cards()

	_material_frame = LedgerMaterialFrame.new()
	_material_frame.name = "LedgerMaterialFrame"
	_material_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_material_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_material_frame.set_header_bottom(HEADER_H)
	add_child(_material_frame)

	_book_page = LedgerBlackBook.new()
	_book_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_book_page.offset_top = HEADER_H
	_book_page.visible = false
	_book_page.buy_pressed.connect(_on_perk_buy)
	add_child(_book_page)
	_book_page.build(book, prestige)

	_close_btn = _button("CLOSE", Vector2(168.0, 96.0), Color(LedgerStyle.NEWSPRINT, 0.12), LedgerStyle.NEWSPRINT)
	_close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.offset_left = -220.0
	_close_btn.offset_right = -30.0
	_close_btn.offset_top = 26.0
	_close_btn.offset_bottom = 122.0
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

	_book_btn = _button("BLACK BOOK", Vector2(228.0, 96.0), Color(LedgerStyle.NEWSPRINT, 0.12),
		LedgerStyle.NEWSPRINT)
	_book_btn.add_theme_font_size_override("font_size", 21)
	_book_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_book_btn.offset_left = -540.0
	_book_btn.offset_right = -240.0
	_book_btn.offset_top = 26.0
	_book_btn.offset_bottom = 122.0
	_book_btn.pressed.connect(_on_turn_page)
	add_child(_book_btn)

	_zoom_btn = _button("FIT / FOCUS", Vector2(206.0, 96.0), Color(LedgerStyle.INK, 0.78), LedgerStyle.NEWSPRINT)
	_zoom_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_zoom_btn.offset_left = 36.0
	_zoom_btn.offset_right = 242.0
	_zoom_btn.offset_top = -136.0
	_zoom_btn.offset_bottom = -40.0
	_zoom_btn.pressed.connect(_on_zoom)
	add_child(_zoom_btn)

	_compass = _button("NEXT BUY  ▸", Vector2(300.0, 96.0), Color(LedgerStyle.BRASS, 0.96), LedgerStyle.INK)
	_compass.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_compass.offset_left = -336.0
	_compass.offset_right = -36.0
	_compass.offset_top = -136.0
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


## Specialists use the same evidence-file portrait language as Roll Call. The four Phase 1
## faces are reused as a restrained archive treatment until a specialist-specific set exists;
## the id mapping is deterministic, so opening the Ledger never shuffles a face.
func _install_portrait_cards() -> void:
	if _board == null:
		return
	_install_portrait_cards_under(_board)


func _install_portrait_cards_under(node: Node) -> void:
	for child in node.get_children():
		if child is LedgerCard:
			_install_portrait_on_card(child as LedgerCard)
		else:
			_install_portrait_cards_under(child)


func _install_portrait_on_card(card: LedgerCard) -> void:
	if card == null or card.kind != LedgerCard.Kind.NODE:
		return
	var node_def := catalog.def(card.id)
	var specialist: Dictionary = node_def.get("specialist", {})
	if specialist.is_empty() or card.has_meta("portrait_face"):
		return
	var specialist_id := String(specialist.get("id", ""))
	var face := int(PORTRAIT_FACES.get(specialist_id, posmod(abs(card.id.hash()), 4) + 1))
	var portrait := TextureRect.new()
	portrait.name = "PortraitCard"
	portrait.texture = Presentation.art.resolve(StringName("mugshot.starter_%02d" % face), null, false)
	portrait.position = Vector2(card.size.x - 82.0, 48.0)
	portrait.custom_minimum_size = Vector2(58.0, 76.0)
	portrait.size = Vector2(58.0, 76.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.modulate = Color(1.0, 1.0, 1.0, 0.94)
	portrait.z_index = 2
	card.add_child(portrait)
	card.set_meta("portrait_face", face)


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
	var states := reveal.observe(owned)
	_board.refresh(states, owned, _rank(), _clean(), reveal.pending_ids())
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
	var cost := catalog.next_cost(id, owned)
	# The wash lesson: the reason line names the real problem when the player HAS the
	# money — just the wrong color of it.
	var dirty_covers := block == Upgrades.Block.MONEY \
			and Game.wallet.can_afford_dirty(cost)
	# The docket owns the lower safe area. Re-centre the selected card first so the
	# comparison sheet never rises over the thing the player just chose.
	_board.center_on(id, false)
	_docket.show_for(
		node_def, int(owned.get(id, 0)), cost, block,
		LedgerStyle.block_reason(block, node_def, catalog, owned, dirty_covers)
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
	_play_purchase(id)


func _play_purchase(id: String) -> void:
	if _reduced_motion():
		return
	var card := _find_card(id, _board)
	if card == null or not is_instance_valid(card):
		return
	var stamp := LedgerPurchaseStamp.new()
	stamp.name = "PurchaseStamp"
	stamp.position = Vector2(-32.0, -46.0)
	stamp.custom_minimum_size = Vector2(300.0, 250.0)
	stamp.size = Vector2(300.0, 250.0)
	card.add_child(stamp)
	var base_scale := card.scale
	var tween := create_tween()
	tween.tween_method(stamp.set_progress, 0.0, 1.0, 0.38) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(card, "scale", base_scale * 1.06, 0.10) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", base_scale, 0.20) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(stamp.queue_free)


func _find_card(id: String, node: Node) -> LedgerCard:
	if node == null:
		return null
	for child in node.get_children():
		if child is LedgerCard and (child as LedgerCard).id == id:
			return child as LedgerCard
		var nested := _find_card(id, child)
		if nested != null:
			return nested
	return null


func _reduced_motion() -> bool:
	return Presentation.fx != null and Presentation.fx.reduced_motion


# --- session accessors --------------------------------------------------------


func _rank() -> int:
	return 2 if _preview else Game.rank


func _clean() -> BigMoney:
	return _preview_clean if _preview else Game.wallet.clean


func _dirty() -> BigMoney:
	return BigMoney.parse("14K") if _preview else Game.wallet.dirty


func _is_standalone() -> bool:
	if get_tree().current_scene == self:
		return true
	return ReleaseChannel.allow_development_hooks() \
			and OS.get_environment("SHOT_SCENE").ends_with("ledger.tscn")


## A plausible mid-R2 career, so the preview shows owned, affordable, locked and face-down
## cards at once instead of a board of identical unaffordable rectangles.
func _seed_preview() -> void:
	_preview = true
	_preview_clean = BigMoney.parse("90K")
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
	if not ReleaseChannel.allow_development_hooks():
		return
	# SHOT_CATALOG renders a candidate content file instead of the shipped one — how a draft
	# of the T4-T5 tier or a new specialist gets looked at before it is committed.
	var alt := OS.get_environment("SHOT_CATALOG")
	if alt != "" and FileAccess.file_exists(alt):
		catalog = Upgrades.from_file(alt)
		reveal.catalog = catalog
		_board.build(catalog, _trophies())
		_install_portrait_cards()
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
	var top := _safe_margins.y
	var left := _safe_margins.x + 36.0
	var header_bottom := HEADER_H + top
	draw_rect(Rect2(0.0, 0.0, w, header_bottom), LedgerStyle.INK)
	draw_rect(Rect2(0.0, header_bottom - 3.0, w, 3.0), LedgerStyle.BRASS)
	if _page == PAGE_BOOK:
		_draw_book_header(w)
		return
	draw_string(_font, Vector2(left, top + 64.0), "THE LEDGER", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_type_px(42, &"title"), LedgerStyle.NEWSPRINT)
	draw_string(_font, Vector2(left + 2.0, top + 94.0), "CAREER PURCHASES", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, _type_px(17, &"metadata"), Color(LedgerStyle.BRASS, 0.72))

	var rank_text := "R%d" % _rank()
	var rank_px := _type_px(26, &"primary_value")
	var rw := _font.get_string_size(rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, rank_px).x
	draw_rect(Rect2(left, top + 108.0, rw + 26.0, 34.0), Color(LedgerStyle.BRASS, 0.9))
	draw_string(_font, Vector2(left + 13.0, top + 134.0), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_type_px(24, &"primary_value"), LedgerStyle.INK)

	# Wallets occupy the quiet strip under the title, never the right-side button zone.
	var wallet_x := left + rw + 46.0
	var clean_text := "CLEAN  " + _clean().text()
	var clean_px := _type_px(23, &"primary_value")
	draw_string(_font, Vector2(wallet_x, top + 132.0), clean_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, clean_px, LedgerStyle.CLEAN)
	var dirty_text := "DIRTY  " + _dirty().text()
	var dirty_px := _type_px(18, &"metadata")
	var dirty_x := wallet_x + maxf(188.0, _font.get_string_size(clean_text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, clean_px).x + 42.0)
	draw_string(_font, Vector2(dirty_x, top + 132.0), dirty_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, dirty_px, Color(LedgerStyle.DIRTY, 0.82))


## The Black Book's header. Same bar, different currency: Juice where clean cash goes, and
## the city count where the rank badge goes — this page belongs to the player, not the career.
func _draw_book_header(w: float) -> void:
	var top := _safe_margins.y
	var left := _safe_margins.x + 36.0
	draw_string(_font, Vector2(left, top + 64.0), "THE BLACK BOOK", HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_type_px(42, &"title"), LedgerStyle.NEWSPRINT)
	draw_string(_font, Vector2(left + 2.0, top + 94.0), "WITNESS RELOCATION FORM 12-B",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _type_px(17, &"metadata"), Color(LedgerStyle.BRASS, 0.7))

	var city_text := "CITY %d" % prestige.city_number()
	var city_px := _type_px(22, &"metadata")
	var cw := _font.get_string_size(city_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, city_px).x
	draw_rect(Rect2(left, top + 108.0, cw + 26.0, 34.0), Color(LedgerStyle.BRASS, 0.9))
	draw_string(_font, Vector2(left + 13.0, top + 134.0), city_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_type_px(21, &"metadata"), LedgerStyle.INK)

	var jx := left + cw + 58.0
	draw_string(_font, Vector2(jx, top + 132.0), "JUICE  %d" % prestige.juice,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _type_px(23, &"primary_value"), LedgerStyle.BRASS)
	var earned := "%d EARNED" % prestige.juice_earned
	draw_string(_font, Vector2(jx + 174.0, top + 132.0), earned, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_type_px(18, &"metadata"), Color(LedgerStyle.NEWSPRINT, 0.45))


func _button(text: String, min_size: Vector2, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", _type_px(26, &"button"))
	LedgerStyle.style_button(b, bg, fg)
	return b


func _type_px(base: int, role: StringName) -> int:
	if Presentation.theme == null:
		return base
	var authored := 34.0
	match role:
		&"title": authored = 44.0
		&"section": authored = 38.0
		&"primary_value": authored = 44.0
		&"caption": authored = 24.0
		&"metadata": authored = 22.0
		&"button": authored = 28.0
		&"micro": authored = 20.0
		_: authored = 34.0
	return maxi(1, roundi(float(base) * float(Presentation.theme.size_for(role)) / authored))
