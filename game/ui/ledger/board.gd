class_name LedgerBoard
extends Control
## The corkboard: a pannable sheet of cards joined by red string.
##
## This node is the *window* — it clips, it owns the drag/zoom input, and it never moves.
## Inside it are two painted layers: a fixed cork ground (so a zoomed-out board never shows
## a hole) and the sheet, which carries the map lines, the branch headers, the string edges
## and every card, and is what actually pans.
##
## Layout is deterministic: branch = column band, tier = row, ties broken by file order.
## Nothing reflows when a card is revealed, so the board a player learns stays learned.
##
## One band is not a branch: TROPHIES, at the far right, holds the boss spoils a career took
## (`spoil.*`). They are not catalog nodes, they have no strings and no price, and the only
## thing that changes them is beating somebody new.

signal card_tapped(id: String)

const MARGIN := Vector2(42.0, 86.0)
const PITCH_X := LedgerCard.W + 30.0
const PITCH_Y := LedgerCard.H + 38.0
const BRANCH_GAP := 70.0
const TIER_GAP := 58.0
const MAX_COLUMNS_PER_TIER := 2
## Movement (in screen px) past which a press is a pan, not a tap.
const TAP_SLOP := 14.0
## Cards this far outside the window still draw, so the purchase-stamp scale and the pin's
## shadow never pop at the edge.
const CULL_MARGIN := 24.0
## Zoom rungs: readable, mid, and "show me the whole conspiracy" (computed to fit the
## board's width, so it stays honest as content grows).
const ZOOM_STEPS: PackedFloat64Array = [1.0, 0.62, 0.0]
## The band spoils hang in. Not a branch: `LedgerStyle.branch_title` prints it and
## `branch_color` falls through to brass, which is exactly the colour a trophy wants.
const TROPHY_BAND := "trophies"

var catalog: Upgrades = null

var _sheet: Control = null
var _ground: Control = null
var _font: Font = null

var _cards: Dictionary = {}
var _drawable: Dictionary = {}
var _trophies: Array[Dictionary] = []
var _slots: Dictionary = {}
var _bands: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _edges: Array[Dictionary] = []
var _content := Vector2.ZERO
var _profile := "standard"

var _pan := Vector2.ZERO
var _zoom := ZOOM_STEPS[0]
var _dragging := false
var _drag_travel := 0.0
# Maps-style zoom (device request): raw touches tracked for the pinch; wheel/buttons set a
# TARGET the view glides toward, anchored at a focal screen point so the spot under the
# cursor/pinch stays put. Fingers get direct control (no lag); everything else eases.
var _touches: Dictionary = {}
var _pinching := false
var _pinch_start_dist := 0.0
var _pinch_start_zoom := 1.0
var _pinch_mid := Vector2.ZERO
var _zoom_target := ZOOM_STEPS[0]
var _zoom_focus := Vector2.ZERO
const ZOOM_MIN := 0.2
const ZOOM_MAX := 2.0
const ZOOM_GLIDE := 12.0
var _selected := ""
## Centre request that arrived before the board had a size — re-applied on first layout.
var _pending_center := ""


class Painter:
	extends Control
	var paint: Callable

	func _draw() -> void:
		if paint.is_valid():
			paint.call(self)


func _ready() -> void:
	_ensure_layers()
	if not resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	set_process(true)


## The glide half of maps-zoom: ease toward the target around the stored focal point.
## Fingers (the pinch) bypass this entirely — they ARE the zoom while they are down.
func _process(delta: float) -> void:
	if _pinching or absf(_zoom_target - _zoom) < 0.0005:
		return
	var z := lerpf(_zoom, _zoom_target, 1.0 - exp(-ZOOM_GLIDE * delta))
	_zoom_at(_zoom_focus, z)


## The cork and the sheet, built on demand rather than only in `_ready` — the headless test
## runner never reaches a frame, so a board it builds has to raise its own layers first.
func _ensure_layers() -> void:
	if _sheet != null:
		return
	_font = Presentation.theme.font_for(&"headline")
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ground = Painter.new()
	(_ground as Painter).paint = _paint_ground
	_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ground)
	_sheet = Painter.new()
	(_sheet as Painter).paint = _paint_sheet
	_sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sheet)


# --- construction -------------------------------------------------------------


## Builds one card per catalog node (plus one per trophy) and freezes their positions.
func build(from_catalog: Upgrades, trophies: Array[Dictionary] = []) -> void:
	_ensure_layers()
	catalog = from_catalog
	_trophies = trophies.duplicate()
	for child in _sheet.get_children():
		_sheet.remove_child(child)
		child.queue_free()
	_cards.clear()
	_drawable.clear()
	_layout()
	for n in catalog.nodes:
		var card := LedgerCard.new()
		_sheet.add_child(card)
		card.setup(n)
		card.position = _slots.get(String(n["id"]), Vector2.ZERO)
		card.visible = false
		_cards[String(n["id"])] = card
		_drawable[String(n["id"])] = false
	for trophy in _trophies:
		var t := LedgerCard.new()
		_sheet.add_child(t)
		t.setup_trophy(trophy)
		t.position = _slots.get(String(trophy.get("id", "")), Vector2.ZERO)
		_cards[String(trophy.get("id", ""))] = t
		_drawable[String(trophy.get("id", ""))] = true
	_sheet.size = _content
	_apply_view()


## The spoils this board is showing. Rebuilding only when the set actually changed keeps the
## pan, the zoom and every card's pin angle exactly where the player left them. Returns true
## when the board was rebuilt (every card is a fresh node then).
func set_trophies(trophies: Array[Dictionary]) -> bool:
	if catalog == null or _trophy_ids(trophies) == _trophy_ids(_trophies):
		return false
	build(catalog, trophies)
	return true


static func _trophy_ids(list: Array[Dictionary]) -> PackedStringArray:
	var out: PackedStringArray = []
	for d in list:
		out.append(String(d.get("id", "")))
	return out


func _layout() -> void:
	_slots.clear()
	_bands.clear()
	_rows.clear()
	if catalog == null or catalog.nodes.is_empty():
		_content = size
		return

	var min_tier := 99
	var max_tier := 0
	var counts: Dictionary = {}
	var widest: Dictionary = {}
	for n in catalog.nodes:
		var branch := String(n["branch"])
		var tier := int(n["tier"])
		min_tier = mini(min_tier, tier)
		max_tier = maxi(max_tier, tier)
		var key := "%s:%d" % [branch, tier]
		var c := int(counts.get(key, 0)) + 1
		counts[key] = c
		widest[branch] = maxi(int(widest.get(branch, 0)), c)

	var tier_rows: Dictionary = {}
	for tier in range(min_tier, max_tier + 1):
		var rows := 1
		for branch in widest:
			rows = maxi(rows, int(ceil(float(counts.get("%s:%d" % [branch, tier], 0)) \
				/ float(MAX_COLUMNS_PER_TIER))))
		tier_rows[tier] = rows

	var tier_y: Dictionary = {}
	var y_cursor := MARGIN.y
	for tier in range(min_tier, max_tier + 1):
		tier_y[tier] = y_cursor
		y_cursor += float(tier_rows[tier]) * PITCH_Y + TIER_GAP

	var x := MARGIN.x
	var starts: Dictionary = {}
	for branch in Upgrades.BRANCHES:
		if not widest.has(branch):
			continue
		var slots := mini(int(widest[branch]), MAX_COLUMNS_PER_TIER)
		var band_w := float(slots) * PITCH_X - (PITCH_X - LedgerCard.W)
		starts[branch] = x
		_bands.append({
			"branch": branch,
			"x": x - 30.0,
			"w": band_w + 60.0,
		})
		x += band_w + BRANCH_GAP

	var used: Dictionary = {}
	for n in catalog.nodes:
		var branch := String(n["branch"])
		var tier := int(n["tier"])
		var key := "%s:%d" % [branch, tier]
		var idx := int(used.get(key, 0))
		used[key] = idx + 1
		# Two-up packing keeps a root decision cluster complete on a phone. The branch still
		# owns its column and tier, while a four-card opening cluster becomes a quiet 2x2.
		var branch_columns := mini(int(widest[branch]), MAX_COLUMNS_PER_TIER)
		var columns := mini(int(counts[key]), MAX_COLUMNS_PER_TIER)
		var slack := float(branch_columns - columns) * PITCH_X * 0.5
		var row := idx / MAX_COLUMNS_PER_TIER
		var column := idx % MAX_COLUMNS_PER_TIER
		_slots[String(n["id"])] = Vector2(
			float(starts[branch]) + slack + float(column) * PITCH_X,
			float(tier_y[tier]) + float(row) * PITCH_Y
		)

	for tier in range(min_tier, max_tier + 1):
		_rows.append({"tier": tier, "y": float(tier_y[tier]),
			"h": float(tier_rows[tier]) * PITCH_Y + TIER_GAP})

	# The trophy shelf: one column at the far right, one card a row from the top, because a
	# spoil belongs to no tier — you did not reach it, you took it.
	if not _trophies.is_empty():
		_bands.append({
			"branch": TROPHY_BAND,
			"x": x - 30.0,
			"w": PITCH_X - (PITCH_X - LedgerCard.W) + 60.0,
		})
		for i in _trophies.size():
			_slots[String(_trophies[i].get("id", ""))] = Vector2(
				x, MARGIN.y + float(i) * PITCH_Y
			)
		x += PITCH_X + BRANCH_GAP

	_content = Vector2(
		x - BRANCH_GAP + MARGIN.x,
		maxf(y_cursor - TIER_GAP, MARGIN.y + float(maxi(_trophies.size() - 1, 0)) * PITCH_Y
			+ LedgerCard.H) + MARGIN.y
	)
	_profile = _current_profile()


# --- refresh ------------------------------------------------------------------


## Re-reads the whole board from the meta layer. Cheap enough to call on every change:
## 31 cards, no allocation beyond the edge list.
func refresh(states: Dictionary, owned: Dictionary, rank: int, clean: BigMoney,
		new_ids: PackedStringArray = PackedStringArray()) -> void:
	if catalog == null:
		return
	for n in catalog.nodes:
		var id := String(n["id"])
		var card: LedgerCard = _cards.get(id, null)
		if card == null:
			continue
		var state := int(states.get(id, Reveal.State.HIDDEN))
		var face := LedgerCard.Face.HIDDEN
		if state == Reveal.State.REVEALED:
			face = LedgerCard.Face.REVEALED
		elif state == Reveal.State.FACEDOWN:
			face = LedgerCard.Face.FACEDOWN
		card.set_state(
			face, int(owned.get(id, 0)), catalog.next_cost(id, owned),
			catalog.block_for(id, owned, rank, clean), new_ids.has(id)
		)
		_drawable[id] = card.visible
		card.set_selected(id == _selected)
	_build_edges(states)
	_sheet.queue_redraw()
	_sync_card_visibility()


func set_selected(id: String) -> void:
	if _selected == id:
		return
	var prev: LedgerCard = _cards.get(_selected, null)
	if prev != null:
		prev.set_selected(false)
	_selected = id
	var next: LedgerCard = _cards.get(id, null)
	if next != null:
		next.set_selected(true)


## A string is drawn only when both ends are on the board — the whole point of a face-down
## card is that you can see the string arriving at it.
func _build_edges(states: Dictionary) -> void:
	_edges.clear()
	for n in catalog.nodes:
		var id := String(n["id"])
		var child_state := int(states.get(id, Reveal.State.HIDDEN))
		if child_state == Reveal.State.HIDDEN:
			continue
		var parents: PackedStringArray = n["requires"]
		for parent in parents:
			if int(states.get(parent, Reveal.State.HIDDEN)) == Reveal.State.HIDDEN:
				continue
			var a: Vector2 = _slots.get(parent, Vector2.ZERO)
			var b: Vector2 = _slots.get(id, Vector2.ZERO)
			var from := a + Vector2(LedgerCard.W * 0.5, LedgerCard.H)
			var to := b + Vector2(LedgerCard.W * 0.5, 0.0)
			if absf(a.y - b.y) < 4.0:
				# Same tier: run the string around the sides instead of through the cards.
				var left_first := a.x <= b.x
				from = a + Vector2(LedgerCard.W if left_first else 0.0, LedgerCard.H * 0.5)
				to = b + Vector2(0.0 if left_first else LedgerCard.W, LedgerCard.H * 0.5)
			_edges.append({
				"from": from,
				"to": to,
				"faded": child_state == Reveal.State.FACEDOWN,
			})


# --- view ---------------------------------------------------------------------


func content_size() -> Vector2:
	return _content


## Where a card sits on the sheet, or `Vector2.ZERO` for a card this board does not carry.
## Positions are frozen at build time (see `_layout`), so this is also the answer to "did the
## board actually nail this one up".
func slot_of(id: String) -> Vector2:
	return _slots.get(id, Vector2.ZERO)


## Read-only layout handoff for D4 and capture tooling. Coordinates are in this board's
## logical parent space; card_rects stay in sheet space so a consumer can apply `pan` and
## `zoom` without guessing at the host window scale.
func geometry_contract() -> Dictionary:
	_profile = _current_profile()
	var logical := size
	var safe := Presentation.safe.content_rect().intersection(Rect2(Vector2.ZERO, logical))
	return {
		"schema": "kingpin.ledger.board.geometry.v1",
		"profile": _profile,
		"requested_physical_size": Vector2i(ProjectSettings.get_setting(
			"display/window/size/viewport_width", 1080), ProjectSettings.get_setting(
			"display/window/size/viewport_height", 1920)),
		"actual_physical_size": Vector2i(DisplayServer.window_get_size()),
		"logical_viewport": logical,
		"safe_content": safe,
		"viewport": Rect2(Vector2.ZERO, logical),
		"content_size": _content,
		"zoom": _zoom,
		"pan": _pan,
		"selected": _selected,
		"reservations": content_reservations(),
	}


func geometry_snapshot() -> Dictionary:
	return geometry_contract()


func content_reservations() -> Dictionary:
	var cards: Dictionary = {}
	for id: Variant in _slots:
		cards[String(id)] = Rect2(Vector2(_slots[id]), Vector2(LedgerCard.W, LedgerCard.H))
	return {
		"viewport": Rect2(Vector2.ZERO, size),
		"card_rects": cards,
		"selected_card": cards.get(_selected, Rect2()),
		"content": Rect2(Vector2.ZERO, _content),
		"fit_target": _zoom_step(2),
	}


func zoom() -> float:
	return _zoom


func cycle_zoom() -> void:
	var i := 0
	for s in ZOOM_STEPS.size():
		if is_equal_approx(_zoom_target, _zoom_step(s)):
			i = s
			break
	# The button GLIDES to the next rung (maps feel), anchored at the view centre.
	_zoom_focus = size * 0.5
	_zoom_target = clampf(_zoom_step((i + 1) % ZOOM_STEPS.size()), ZOOM_MIN, ZOOM_MAX)


func fit_board() -> void:
	var focus := size * 0.5
	_zoom_focus = focus
	_zoom_target = _zoom_step(2)
	if not is_inside_tree() or (Presentation.fx != null and Presentation.fx.reduced_motion):
		_zoom = _zoom_target
		_apply_view()


func focus_card(id: String, animate: bool = true) -> void:
	center_on(id, animate)


func card_rect_in_view(id: String) -> Rect2:
	if not _slots.has(id):
		return Rect2()
	var p := Vector2(_slots[id]) * _zoom + _pan
	return Rect2(p, Vector2(LedgerCard.W, LedgerCard.H) * _zoom)


func _current_profile() -> String:
	var physical_width: int = DisplayServer.window_get_size().x
	var width: float = float(physical_width) if physical_width > 0 else size.x
	return "compact" if width < 820.0 else "standard"


## A zero rung means "fit the whole width", which only the live board size knows.
func _zoom_step(i: int) -> float:
	var z := ZOOM_STEPS[i]
	if z > 0.0:
		return z
	if _content.x <= 0.0 or size.x <= 0.0:
		return 0.38
	return clampf(size.x / _content.x, 0.18, 1.0)


## Instant (shot rigs and tests need determinism); interactive paths glide via _zoom_target.
func set_zoom(z: float) -> void:
	var focus := (size * 0.5 - _pan) / maxf(_zoom, 0.0001)
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_zoom_target = _zoom
	_pan = size * 0.5 - focus * _zoom
	_apply_view()


## Puts a card in the middle of the window (the compass, and every docket selection).
func center_on(id: String, animate: bool = true) -> void:
	if not _slots.has(id):
		return
	if size.x < 2.0 or size.y < 2.0:
		# open() can land before the first layout pass; finish the job in _on_resized.
		_pending_center = id
		return
	var target := size * 0.5 - (Vector2(_slots[id]) + Vector2(LedgerCard.W, LedgerCard.H) * 0.5) * _zoom
	target = _clamp_pan(target)
	if not animate or not is_inside_tree() \
			or (Presentation.fx != null and Presentation.fx.reduced_motion):
		_pan = target
		_apply_view()
		return
	var tw := create_tween()
	tw.tween_method(_set_pan, _pan, target, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_pan(v: Vector2) -> void:
	_pan = v
	_apply_view()


func _clamp_pan(p: Vector2) -> Vector2:
	var visual := _content * _zoom
	var out := p
	out.x = (size.x - visual.x) * 0.5 if visual.x <= size.x else clampf(p.x, size.x - visual.x, 0.0)
	# Vertically the board hangs from the top rather than floating in the middle: tier 0 is
	# the top row, and zooming out should not drop the whole ladder into the centre of a wall.
	out.y = 0.0 if visual.y <= size.y else clampf(p.y, size.y - visual.y, 0.0)
	return out


func _apply_view() -> void:
	if _sheet == null:
		return
	_pan = _clamp_pan(_pan)
	_sheet.scale = Vector2(_zoom, _zoom)
	_sheet.position = _pan
	_sync_card_visibility()


## Cards outside the tactile window are switched off so a 60-card sheet costs what the
## screen shows. A card that straddles the edge stays on and is clipped by the board — hiding
## it whole made cards wink out under the finger on every pan and pinch. Face/state truth
## remains in `_drawable`, so a hidden model card is never made visible here.
func _sync_card_visibility() -> void:
	if _cards.is_empty() or size.x < 2.0 or size.y < 2.0:
		return
	var viewport := Rect2(Vector2.ZERO, size).grow(CULL_MARGIN)
	for id: Variant in _cards:
		var card: LedgerCard = _cards[id]
		var wanted := bool(_drawable.get(String(id), false))
		if not wanted:
			card.visible = false
			continue
		var rect := card_rect_in_view(String(id))
		card.visible = viewport.intersects(rect)


func _on_resized() -> void:
	_apply_view()
	if _ground != null:
		_ground.queue_redraw()
	if _pending_center != "":
		var id := _pending_center
		_pending_center = ""
		center_on(id, false)


# --- input --------------------------------------------------------------------


func _gui_input(event: InputEvent) -> void:
	# RAW touches drive the pinch. Single-finger pan/tap stays on the emulated-mouse path
	# below (Android turns finger 0 into mouse events), so the two never double-handle:
	# while two fingers are down, `_pinching` gates the mouse path off.
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() >= 2:
				_begin_pinch()             # a third finger re-baselines rather than skewing
		else:
			_touches.erase(st.index)
			if _pinching and _touches.size() >= 2:
				_begin_pinch()             # the two that remain become the pinch
			elif _pinching:
				_pinching = false
				_dragging = false          # the survivor re-anchors on its next press
		return
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touches.has(sd.index):
			_touches[sd.index] = sd.position
		if _pinching and _touches.size() >= 2:
			_update_pinch()
			accept_event()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_focus = mb.position
			_zoom_target = clampf(_zoom_target * 1.18, ZOOM_MIN, ZOOM_MAX)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_focus = mb.position
			_zoom_target = clampf(_zoom_target / 1.18, ZOOM_MIN, ZOOM_MAX)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if _pinching:
				accept_event()
				return
			if mb.pressed:
				_dragging = true
				_drag_travel = 0.0
				_pending_center = ""
			else:
				_dragging = false
				if _drag_travel < TAP_SLOP:
					_tap_at(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging and not _pinching:
		var mm := event as InputEventMouseMotion
		_drag_travel += mm.relative.length()
		_pan += mm.relative
		_apply_view()
		accept_event()


## Fingers the board never saw lifted (a release over the header, the app backgrounded
## mid-pinch) would turn the next single tap into a one-finger pinch that flings the sheet.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_OUT \
			or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_touches.clear()
		_pinching = false
		_dragging = false


func _begin_pinch() -> void:
	_pinching = true
	_dragging = false
	_drag_travel = TAP_SLOP * 2.0          # a pinch is never a tap
	var pts := _touches.values().slice(-2)
	_pinch_start_dist = maxf((pts[0] as Vector2).distance_to(pts[1] as Vector2), 1.0)
	_pinch_start_zoom = _zoom
	_pinch_mid = ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


## Two fingers = absolute control, exactly like a map: the world point under the pinch
## midpoint stays under it (zoom anchor), and moving both fingers together pans.
func _update_pinch() -> void:
	var pts := _touches.values().slice(-2)
	var a := pts[0] as Vector2
	var b := pts[1] as Vector2
	var mid := (a + b) * 0.5
	_pan += mid - _pinch_mid
	_pinch_mid = mid
	var dist := maxf(a.distance_to(b), 1.0)
	var z := clampf(_pinch_start_zoom * dist / _pinch_start_dist, ZOOM_MIN, ZOOM_MAX)
	_zoom_at(mid, z)
	_zoom_target = _zoom                   # release leaves the view where the fingers put it


## Zoom keeping the world point under `focus` (screen px) exactly under it.
func _zoom_at(focus: Vector2, z: float) -> void:
	var world := (focus - _pan) / maxf(_zoom, 0.0001)
	_zoom = clampf(z, ZOOM_MIN, ZOOM_MAX)
	_pan = focus - world * _zoom
	_apply_view()


func _tap_at(where: Vector2) -> void:
	var local := (where - _pan) / _zoom
	for i in range(_sheet.get_child_count() - 1, -1, -1):
		var card: LedgerCard = _sheet.get_child(i)
		if not card.visible:
			continue
		if Rect2(card.position, card.size).has_point(local):
			card_tapped.emit(card.id)
			return


# --- painting -----------------------------------------------------------------


## Cork stays put behind everything: it is the wall, not the board.
func _paint_ground(c: Control) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, LedgerStyle.CORK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4477
	for i in 140:
		var p := Vector2(rng.randf() * c.size.x, rng.randf() * c.size.y)
		c.draw_circle(p, rng.randf_range(24.0, 90.0), Color(LedgerStyle.CORK_LIGHT, 0.16))
	for i in 1800:
		var p := Vector2(rng.randf() * c.size.x, rng.randf() * c.size.y)
		var col := LedgerStyle.CORK_SPECK if rng.randf() < 0.55 else LedgerStyle.INK
		c.draw_circle(p, rng.randf_range(1.4, 4.2), Color(col, rng.randf_range(0.20, 0.65)))
	# Vignette: four inset bars is cheaper than a gradient and reads the same at this size.
	for i in 6:
		var t := float(i) / 6.0
		var inset := t * 46.0
		c.draw_rect(Rect2(inset, inset, c.size.x - inset * 2.0, c.size.y - inset * 2.0),
			Color(0.0, 0.0, 0.0, 0.05 * (1.0 - t)), false, 46.0 - inset)


func _paint_sheet(c: Control) -> void:
	_paint_map(c)
	_paint_bands(c)
	_paint_strings(c)


## The 1970s transit map under the glass (docs/07 §4) — suggested, not drawn: a few long
## faint runs and district blocks so the cork is not a void behind the cards.
func _paint_map(c: Control) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 9:
		var y := rng.randf() * _content.y
		var col := LedgerStyle.NEON_TEAL if i % 3 == 0 else LedgerStyle.BRASS
		var pts := PackedVector2Array()
		var x := 0.0
		while x < _content.x:
			pts.append(Vector2(x, y + sin(x * 0.0016 + float(i)) * 90.0))
			x += 160.0
		c.draw_polyline(pts, Color(col, 0.05), 6.0)
	for i in 14:
		var p := Vector2(rng.randf() * _content.x, rng.randf() * _content.y)
		var s := Vector2(rng.randf_range(180.0, 520.0), rng.randf_range(120.0, 300.0))
		c.draw_rect(Rect2(p, s), Color(LedgerStyle.NEWSPRINT, 0.022))


func _paint_bands(c: Control) -> void:
	for row: Dictionary in _rows:
		var y := float(row["y"]) - 30.0
		c.draw_rect(Rect2(0.0, y, _content.x, float(row.get("h", PITCH_Y))),
			Color(LedgerStyle.NEWSPRINT, 0.018))
		var label := "TIER %d  ·  RANK R%d" % [int(row["tier"]), int(row["tier"])]
		var lx := 24.0
		while lx < _content.x:
			c.draw_string(_font, Vector2(lx, y + 22.0), label, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, _type_px(17, &"metadata"), Color(LedgerStyle.BRASS, 0.28))
			lx += 1180.0
	for band: Dictionary in _bands:
		var branch := String(band["branch"])
		var col := LedgerStyle.branch_color(branch)
		var x := float(band["x"])
		var w := float(band["w"])
		c.draw_rect(Rect2(x, 22.0, w, _content.y - 44.0), Color(col, 0.022))
		c.draw_rect(Rect2(x, 22.0, w, _content.y - 44.0), Color(col, 0.10), false, 2.0)
		c.draw_string(_font, Vector2(x + 18.0, 54.0), LedgerStyle.branch_title(branch),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _type_px(34, &"section"), Color(col, 0.42))


## Red string with a midpoint sag — a quadratic bezier, sampled, with a dark twin under it
## so it reads as thread rather than a vector line.
func _paint_strings(c: Control) -> void:
	for edge: Dictionary in _edges:
		var a: Vector2 = edge["from"]
		var b: Vector2 = edge["to"]
		var sag := 26.0 + a.distance_to(b) * 0.16
		var ctrl := (a + b) * 0.5 + Vector2(0.0, sag)
		var pts := PackedVector2Array()
		for i in 19:
			var t := float(i) / 18.0
			pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
		var shadow := PackedVector2Array()
		for p in pts:
			shadow.append(p + Vector2(3.0, 5.0))
		var alpha := 0.45 if bool(edge["faded"]) else 0.92
		c.draw_polyline(shadow, Color(0.0, 0.0, 0.0, 0.30 * alpha), 4.0)
		c.draw_polyline(pts, Color(LedgerStyle.DIRTY, alpha), 3.0)
		c.draw_circle(a, 4.5, Color(LedgerStyle.DIRTY.darkened(0.3), alpha))
		c.draw_circle(b, 4.5, Color(LedgerStyle.DIRTY.darkened(0.3), alpha))


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
