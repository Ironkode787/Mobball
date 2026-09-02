extends RefCounted
## The two things the Ledger draws that are not upgrade cards: TROPHIES (boss spoils, which
## were never for sale) and the BLACK BOOK page (perks, which are bought with Juice).
##
## A headless render probe, not a screenshot: it builds the real nodes, in the real tree, and
## asks them what state they are in and where they put things. What it cannot check is what
## the paint looks like — that is what `tools/shot.sh` renders are for. What it CAN check is
## everything a refactor breaks silently: a trophy that turns purchasable, a card that lands
## on top of another one, a page that stops finding its perks.


func run(t: TestCtx) -> void:
	_test_spoil_descriptors(t)
	_test_trophy_card(t)
	_test_trophy_shelf(t)
	_test_edge_cards_stay_visible(t)
	_test_pinch_bookkeeping(t)
	_test_blackbook_page(t)


# --- the tactile window -------------------------------------------------------


func _revealed_board(t: TestCtx) -> LedgerBoard:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.fail("no SceneTree to build a board in")
		return null
	var board := LedgerBoard.new()
	board.size = Vector2(1080.0, 1600.0)
	tree.root.add_child(board)
	var catalog := Upgrades.shared()
	board.build(catalog, [])
	var states: Dictionary = {}
	for id in catalog.ids():
		states[id] = Reveal.State.REVEALED
	board.refresh(states, {}, 7, BigMoney.parse("1M"))
	return board


func _visible_ids(board: LedgerBoard) -> PackedStringArray:
	var out := PackedStringArray()
	for id: Variant in board._cards:
		if (board._cards[id] as LedgerCard).visible:
			out.append(String(id))
	return out


## A card that straddles the window's edge is clipped, never switched off: hiding it whole
## made cards wink out under the finger on every pan and pinch ("cards disappear randomly").
func _test_edge_cards_stay_visible(t: TestCtx) -> void:
	var board := _revealed_board(t)
	if board == null:
		return
	var window := Rect2(Vector2.ZERO, board.size)
	for zoom in [1.0, 0.62, LedgerBoard.ZOOM_MAX]:
		board.set_zoom(zoom)
		var straddling := 0
		var hidden_inside := 0
		for id: Variant in board._cards:
			var rect := board.card_rect_in_view(String(id))
			var card: LedgerCard = board._cards[id]
			if window.intersects(rect) and not window.encloses(rect):
				straddling += 1
				if not card.visible:
					hidden_inside += 1
			elif not window.intersects(rect.grow(LedgerBoard.CULL_MARGIN)):
				t.ok(not card.visible, "%s is off the window at zoom %.2f and stays switched off" % [id, zoom])
		t.ok(straddling > 0, "at zoom %.2f some cards straddle the window edge" % zoom)
		t.eq(hidden_inside, 0, "at zoom %.2f no straddling card is hidden" % zoom)
		t.ok(_visible_ids(board).size() > 0, "at zoom %.2f the window is not empty" % zoom)
	# a pan by a few pixels must never change what is drawable, only what is on screen
	board.set_zoom(1.0)
	var before := _visible_ids(board).size()
	board._pan += Vector2(-7.0, -5.0)
	board._apply_view()
	t.ok(absi(_visible_ids(board).size() - before) <= 2, "a small pan does not empty a row of cards")
	(Engine.get_main_loop() as SceneTree).root.remove_child(board)
	board.free()


func _touch(board: LedgerBoard, index: int, at: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = at
	ev.pressed = pressed
	board._gui_input(ev)


func _drag(board: LedgerBoard, index: int, at: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = at
	board._gui_input(ev)


## Three fingers, a lost release, a finger lifted mid-pinch: the view must stay bounded and the
## board must forget fingers it will never see lifted.
func _test_pinch_bookkeeping(t: TestCtx) -> void:
	var board := _revealed_board(t)
	if board == null:
		return
	board.set_zoom(1.0)
	var zoom0 := board.zoom()
	_touch(board, 0, Vector2(300.0, 800.0), true)
	_touch(board, 1, Vector2(700.0, 800.0), true)
	t.ok(board._pinching, "two fingers pinch")
	_touch(board, 2, Vector2(500.0, 300.0), true)
	_drag(board, 2, Vector2(500.0, 320.0))
	t.ok(is_finite(board.zoom()) and board.zoom() >= LedgerBoard.ZOOM_MIN and board.zoom() <= LedgerBoard.ZOOM_MAX,
			"a third finger keeps the zoom bounded")
	_touch(board, 0, Vector2(300.0, 800.0), false)
	t.ok(board._pinching, "lifting one of three keeps pinching with the other two")
	var pan_before: Vector2 = board._pan
	_drag(board, 1, Vector2(702.0, 801.0))
	t.ok(pan_before.distance_to(board._pan) < 40.0, "the surviving pair does not fling the sheet")
	_touch(board, 1, Vector2(702.0, 801.0), false)
	_touch(board, 2, Vector2(500.0, 320.0), false)
	t.ok(not board._pinching and board._touches.is_empty(), "all fingers up ends the pinch")
	# a finger the board never sees lifted must not turn the next tap into a pinch
	var settled := board.zoom()
	_touch(board, 0, Vector2(400.0, 900.0), true)
	board._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	t.ok(board._touches.is_empty(), "losing focus forgets the fingers")
	_touch(board, 1, Vector2(500.0, 900.0), true)
	t.ok(not board._pinching, "one real finger after a lost release is not a pinch")
	_touch(board, 1, Vector2(500.0, 900.0), false)
	t.near(board.zoom(), settled, 1e-6, "the tap left the zoom alone")
	t.ok(zoom0 > 0.0, "the board started at a real zoom")
	(Engine.get_main_loop() as SceneTree).root.remove_child(board)
	board.free()


# --- trophies -----------------------------------------------------------------


## The names come from the flow lane's own fight table, read by path so this screen never
## compiles against it. If that ever silently breaks, a trophy shows a prettified slug — so
## the test asks for the real name.
func _test_spoil_descriptors(t: TestCtx) -> void:
	var sammy := LedgerStyle.spoil_descriptor("spoil.sammys_spare")
	t.eq(String(sammy["id"]), "spoil.sammys_spare", "the descriptor keeps its id")
	t.eq(String(sammy["name"]), "SAMMY'S SPARE", "the spoil's name comes off Commission.FIGHTS")
	t.eq(String(sammy["from"]), "SAMMY TWO-FLIPPERS", "…and so does whose it was")
	var butcher := LedgerStyle.spoil_descriptor("spoil.cold_storage")
	t.eq(String(butcher["name"]), "COLD STORAGE", "the Butcher's spoil, likewise")

	# A spoil the flow lane has not written yet still gets a card, with a legible name.
	var unknown := LedgerStyle.spoil_descriptor("spoil.the_wrench")
	t.eq(String(unknown["name"]), "THE WRENCH", "an unknown spoil falls back to its slug")
	t.eq(String(unknown["from"]), "", "…and admits it does not know whose it was")


func _test_trophy_card(t: TestCtx) -> void:
	var card := LedgerCard.new()
	card.setup_trophy({"id": "spoil.sammys_spare", "name": "SAMMY'S SPARE", "from": "SAMMY"})
	t.eq(card.kind, LedgerCard.Kind.TROPHY, "a trophy knows what it is")
	t.eq(card.face, LedgerCard.Face.REVEALED, "a trophy is face-up the moment it exists")
	t.eq(card.visible, true, "…and visible without waiting for a board refresh")
	t.eq(card.is_owned(), true, "you have it")
	t.eq(card.is_glinting(), false, "…so the pushpin never glints: there is nothing to buy")
	t.eq(card.block, Upgrades.Block.MAXED, "and the board reads it as unpurchasable")
	t.eq(card.cost.is_zero(), true, "a spoil has no price")
	t.eq(card.rotation, 0.0, "it is pinned flat, like everything already done")
	t.eq(card.max_level, 1, "and there is exactly one of it")
	card.free()

	# An ordinary node card must be unaffected by all of the above.
	var node := LedgerCard.new()
	node.setup(Upgrades.shared().def(Upgrades.shared().ids()[0]))
	t.eq(node.kind, LedgerCard.Kind.NODE, "a catalog card is still a catalog card")
	t.eq(node.face, LedgerCard.Face.HIDDEN, "…and starts hidden until the board says otherwise")
	node.free()


## The shelf: a board built with trophies puts them in their own band, off the tier grid and
## clear of every other card.
func _test_trophy_shelf(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.fail("no SceneTree to build a board in")
		return
	var board := LedgerBoard.new()
	board.size = Vector2(1080.0, 1600.0)
	tree.root.add_child(board)
	var catalog := Upgrades.shared()
	var trophies: Array[Dictionary] = [
		LedgerStyle.spoil_descriptor("spoil.sammys_spare"),
		LedgerStyle.spoil_descriptor("spoil.cold_storage"),
	]
	board.build(catalog, trophies)

	var slots: Dictionary = {}
	for id in catalog.ids():
		slots[id] = board.slot_of(id)
	var first := board.slot_of("spoil.sammys_spare")
	var second := board.slot_of("spoil.cold_storage")
	t.ok(first != Vector2.ZERO, "the first trophy got a slot")
	t.ok(second.y > first.y, "the second hangs under it")
	t.ok(is_equal_approx(first.x, second.x), "…in the same column")
	var rightmost := 0.0
	for id: Variant in slots:
		rightmost = maxf(rightmost, float((slots[id] as Vector2).x))
	t.ok(first.x > rightmost, "the shelf is right of every branch column")
	t.ok(board.content_size().x > rightmost + LedgerCard.W,
		"and the board grew to hold it")
	# Nothing may share a slot: a trophy landing on a node is the bug this catches.
	var seen: Dictionary = {}
	for id: Variant in slots:
		var key := str(slots[id])
		t.ok(not seen.has(key), "%s does not sit on top of %s" % [id, seen.get(key, "")])
		seen[key] = String(id)

	# Rebuilding with the same spoils must not churn the board; a new one must land.
	var before := board.content_size()
	board.set_trophies(trophies)
	t.ok(board.content_size() == before, "the same trophies do not rebuild the board")
	trophies.append(LedgerStyle.spoil_descriptor("spoil.the_wrench"))
	board.set_trophies(trophies)
	t.ok(board.slot_of("spoil.the_wrench") != Vector2.ZERO, "a new spoil gets nailed up")

	tree.root.remove_child(board)
	board.free()


# --- the Black Book page ------------------------------------------------------


func _test_blackbook_page(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		t.fail("no SceneTree to build a page in")
		return
	var book := BlackBook.shared()
	var prestige := Prestige.new(book)
	prestige.award(4)
	var page := LedgerBlackBook.new()
	page.size = Vector2(1080.0, 1400.0)
	tree.root.add_child(page)
	page.build(book, prestige)

	# Every perk in the Book gets a rectangle, and no two overlap.
	var rects: Array[Rect2] = []
	for id in book.ids():
		var r := page.rect_of(id)
		t.ok(r.size.x > 0.0 and r.size.y > 0.0, "%s: has a card on the page" % id)
		t.ok(r.position.x >= 0.0 and r.end.x <= page.size.x,
			"%s: the card stays on the page" % id)
		for other in rects:
			t.ok(not r.intersects(other), "%s: does not overlap another perk" % id)
		rects.append(r)
	t.eq(rects.size(), book.perks.size(), "one card per perk, no more")
	t.ok(page.content_height() > page.size.y * 0.5,
		"the page is long enough to be worth scrolling (%.0f)" % page.content_height())

	# Selection is what the footer and the BUY button read.
	t.eq(page.selected(), "", "nothing is selected on a fresh page")
	page.select("blackbook.kept_man")
	t.eq(page.selected(), "blackbook.kept_man", "selecting a perk sticks")
	page.select("blackbook.not_a_perk")
	t.eq(page.selected(), "", "selecting something that is not in the Book selects nothing")

	# The purchase path the page offers has to agree with the Book's own verdict.
	page.select("blackbook.the_sixth_family")
	t.eq(prestige.block_for("blackbook.the_sixth_family"), BlackBook.Block.DEFERRED,
		"a ★ perk is not for sale on the page either")
	page.select("blackbook.old_contacts")
	t.eq(prestige.block_for("blackbook.old_contacts"), BlackBook.Block.NONE,
		"and a live one is, with 4 Juice in hand")

	tree.root.remove_child(page)
	page.free()
