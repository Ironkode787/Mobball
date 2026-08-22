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

signal closed

const HEADER_H := 168.0

var catalog: Upgrades = null
var reveal: Reveal = null

var _board: LedgerBoard = null
var _docket: LedgerDocket = null
var _compass: Button = null
var _zoom_btn: Button = null
var _close_btn: Button = null
var _font: Font = null
var _selected: String = ""
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
	_board.build(catalog)

	_close_btn = _button("CLOSE", Vector2(190.0, 74.0), Color(LedgerStyle.DIRTY, 0.85), LedgerStyle.NEWSPRINT)
	_close_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_close_btn.offset_left = -220.0
	_close_btn.offset_right = -30.0
	_close_btn.offset_top = 52.0
	_close_btn.offset_bottom = 126.0
	_close_btn.pressed.connect(close)
	add_child(_close_btn)

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
	var owned := LedgerState.get_owned()
	reveal.rank = _rank()
	reveal.note_dirty_held(_dirty())
	_board.refresh(reveal.states(owned), owned, _rank(), _clean())
	if _selected != "":
		_show_docket(_selected)
	queue_redraw()


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
	var state := reveal.state_of(id, LedgerState.get_owned())
	if state != Reveal.State.REVEALED:
		# A face-down card has nothing to say yet. That is the point of it.
		return
	_selected = id
	_board.set_selected(id)
	_show_docket(id)


func _set_board_controls(v: bool) -> void:
	_compass.visible = v
	_zoom_btn.visible = v


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


## Framing hooks for tools/shot.sh, so evidence renders need no code edits. Preview only.
func _apply_shot_framing() -> void:
	var z := OS.get_environment("SHOT_ZOOM")
	if z.is_valid_float():
		_board.set_zoom(z.to_float())
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


func _button(text: String, min_size: Vector2, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 26)
	LedgerStyle.style_button(b, bg, fg)
	return b
