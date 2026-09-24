extends RefCounted
## HOW IT WORKS only explains what the board has. A card for a mechanic that is not built yet
## (a Collection with one shop, Jobs without Lucky's, can levels without the Drop-Off lanes)
## sends a new player looking for something that is not there.


func run(t: TestCtx) -> void:
	_fresh_board(t)
	_every_piece_is_needed(t)
	_mechanics_needing_two_pieces(t)
	_every_need_is_buildable(t)


static func _built(ids: Array) -> Callable:
	return func(id: StringName) -> bool: return ids.has(id)


static func _shown(has: Callable) -> Array:
	var out: Array = []
	for rule: Dictionary in RulesSheet.sort_rules(has)["shown"]:
		out.append(rule["id"])
	return out


func _fresh_board(t: TestCtx) -> void:
	var shown := _shown(_built([]))
	t.eq(shown, [&"basics", &"controls", &"combos", &"alley", &"heat", &"briefcases"],
			"a fresh career is told only about what is on its board")
	var later: PackedStringArray = RulesSheet.sort_rules(_built([]))["later"]
	t.eq(later.size() + shown.size(), RulesSheet.RULES.size(),
			"every card not shown yet is named as still to come")


func _every_piece_is_needed(t: TestCtx) -> void:
	t.ok(not _shown(_built([])).has(&"dropoff"),
			"the can levels wait for the Drop-Off lanes")
	t.ok(_shown(_built([&"rollovers"])).has(&"dropoff"), "the Drop-Off lanes bring their card")


func _mechanics_needing_two_pieces(t: TestCtx) -> void:
	var one_shop := _shown(_built([&"storefront_pizzeria"]))
	t.ok(one_shop.has(&"shops"), "one shop explains its drops")
	t.ok(not one_shop.has(&"collection"), "a Collection needs both shops before it is explained")
	t.ok(_shown(_built([&"storefront_pizzeria", &"storefront_pawn"])).has(&"collection"),
			"both shops explain the Collection")
	var wire_only := _shown(_built([&"wire_bank"]))
	t.ok(wire_only.has(&"phone"), "the payphones explain the phone")
	t.ok(not wire_only.has(&"jobs") and not wire_only.has(&"big_score"),
			"Jobs wait for Lucky's to hand them out")
	t.ok(_shown(_built([&"wire_bank", &"laundromat_loop"])).has(&"jobs"),
			"the Wire and Lucky's together explain Jobs")
	t.ok(not _shown(_built([&"sewer"])).has(&"sewer"), "the Sewer waits for the Getaway that opens it")


## A mistyped id would hide its card for good: every one must be something the Ledger builds.
func _every_need_is_buildable(t: TestCtx) -> void:
	var catalog := Upgrades.from_file(Upgrades.DEFAULT_PATH)
	var owned := {}
	for id: String in catalog.ids():
		owned[id] = 1
	var everything := Stats.new()
	everything.recompute(owned)
	for rule: Dictionary in RulesSheet.RULES:
		var ids: Array = []
		ids.append_array(rule.get("needs", []))
		ids.append_array(rule.get("needs_all", []))
		for id: Variant in ids:
			t.ok(everything.hardware_unlocked(StringName(id)),
					"%s needs %s, which the Ledger can build" % [rule["id"], id])
	t.eq(_shown(func(id: StringName) -> bool: return everything.hardware_unlocked(id)).size(),
			RulesSheet.RULES.size(), "a finished board explains every card")
