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
	_test_blackbook_page(t)


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
