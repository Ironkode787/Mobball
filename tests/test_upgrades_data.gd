extends RefCounted
## The guard rail for `game/content/upgrades.json`.
##
## Upgrade numbers are meant to be tuned in data-only commits, which means nothing but this
## file stands between a typo and a shipped build. So it checks the *shape* of every node
## (schema, vocabulary, graph, cost bands from docs/03 §7), that every node actually moves
## a Stats number, that the whole tree is reachable across a career, and — the other half of
## the job — that the loader really rejects the mistakes it claims to reject.


func run(t: TestCtx) -> void:
	var catalog := Upgrades.from_file(Upgrades.DEFAULT_PATH)
	_test_loads_clean(t, catalog)
	if catalog.nodes.is_empty():
		return
	_test_identity(t, catalog)
	_test_costs(t, catalog)
	_test_repeat_blocks(t, catalog)
	_test_requires_graph(t, catalog)
	_test_reveal_blocks(t, catalog)
	_test_effects(t, catalog)
	_test_every_node_earns_its_place(t, catalog)
	_test_hardware_coverage(t, catalog)
	_test_entry_points(t, catalog)
	_test_career_reachability(t, catalog)
	_test_reveal_engine(t, catalog)
	_test_purchase_rules(t, catalog)
	_test_ledger_state(t)
	_test_loader_rejects(t)


# --- the shipped file ---------------------------------------------------------


func _test_loads_clean(t: TestCtx, catalog: Upgrades) -> void:
	t.eq(catalog.errors.size(), 0, "upgrades.json loads clean: %s" % ", ".join(catalog.errors))
	t.eq(catalog.schema, Upgrades.SCHEMA_VERSION, "schema version")
	t.ok(catalog.nodes.size() >= 24, "the M1 set is ~30 nodes, got %d" % catalog.nodes.size())
	t.ok(catalog.is_valid(), "catalog reports itself valid")


func _test_identity(t: TestCtx, catalog: Upgrades) -> void:
	var seen: Dictionary = {}
	for n in catalog.nodes:
		var id := String(n["id"])
		var branch := String(n["branch"])
		t.ok(not seen.has(id), "id `%s` is unique" % id)
		seen[id] = true
		t.ok(Upgrades.BRANCHES.has(branch), "%s: branch `%s` is one of the six" % [id, branch])
		t.ok(id.begins_with(branch + "."), "%s: id carries its branch prefix" % id)
		t.ok(id.split(".").size() == 2 and not id.ends_with("."), "%s: id is branch.slug" % id)
		var tier := int(n["tier"])
		t.ok(tier >= 0 and tier <= Upgrades.MAX_TIER, "%s: tier %d in 0..7" % [id, tier])
		for key in ["name", "flavor", "table_change"]:
			t.ok(not String(n[key]).strip_edges().is_empty(), "%s: has a %s" % [id, key])
		# docs/04: every node names a visible table change — pillar P1 is not optional.
		t.ok(String(n["table_change"]).length() > 8, "%s: table_change says something" % id)


## docs/03 §7 pins a cost band per tier. A tuning commit may move a number inside its band
## freely; leaving the band is the thing this catches.
func _test_costs(t: TestCtx, catalog: Upgrades) -> void:
	for n in catalog.nodes:
		var id := String(n["id"])
		var tier := int(n["tier"])
		var cost: BigMoney = n["base_cost"]
		t.ok(cost.is_positive(), "%s: cost parses to a positive amount" % id)
		t.ok(cost.equals_approx(BigMoney.parse(String(n["cost"]))), "%s: parsed cost matches the string" % id)
		var lo := Rates.tier_cost_low(tier)
		var hi := Rates.tier_cost_high(tier)
		t.ok(cost.cmp(lo) >= 0 and cost.cmp(hi) <= 0,
			"%s: %s sits inside the T%d band %s–%s" % [id, cost.text(), tier, lo.text(), hi.text()])

	# The cost curve is base x growth^level, and for the canonical 1.15 it has to agree
	# with Rates.repeatable_cost to the last cent.
	for n in catalog.nodes:
		var id := String(n["id"])
		var repeat: Variant = n["repeat"]
		if repeat == null:
			t.ok(catalog.cost_at_level(id, 5).equals_approx(n["base_cost"]),
				"%s: a one-off never gets more expensive" % id)
			continue
		var growth := float((repeat as Dictionary)["growth"])
		for level in [0, 1, 3, int((repeat as Dictionary)["max"])]:
			var got := catalog.cost_at_level(id, level)
			var want: BigMoney = (n["base_cost"] as BigMoney).mul(pow(growth, float(level)))
			t.ok(got.equals_approx(want, 1e-6),
				"%s: level %d costs %s, want %s" % [id, level, got.text(), want.text()])
		if is_equal_approx(growth, Rates.REPEATABLE_GROWTH):
			for level in [1, 7, 20]:
				t.ok(catalog.cost_at_level(id, level).equals_approx(
					Rates.repeatable_cost(n["base_cost"], level), 1e-6),
					"%s: the 1.15 curve matches Rates.repeatable_cost at level %d" % [id, level])


func _test_repeat_blocks(t: TestCtx, catalog: Upgrades) -> void:
	for n in catalog.nodes:
		var id := String(n["id"])
		var repeat: Variant = n["repeat"]
		var effects: Array = n["effects"]
		var per_level := false
		for e: Variant in effects:
			per_level = per_level or bool((e as Dictionary)["per_level"])
		if repeat == null:
			t.eq(int(n["max_level"]), 1, "%s: a one-off maxes at level 1" % id)
			t.ok(not per_level, "%s: per_level needs a repeat block" % id)
			continue
		var d := repeat as Dictionary
		t.ok(int(d["max"]) >= 2, "%s: repeat.max %d is worth repeating" % [id, int(d["max"])])
		t.ok(float(d["growth"]) > 1.0, "%s: repeat.growth rises" % id)
		t.ok(float(d["growth"]) <= 3.0, "%s: repeat.growth %f is a price, not a wall" % [id, float(d["growth"])])
		t.eq(int(n["max_level"]), int(d["max"]), "%s: max_level mirrors repeat.max" % id)
		t.ok(per_level, "%s: a repeatable must have a per_level effect" % id)


func _test_requires_graph(t: TestCtx, catalog: Upgrades) -> void:
	for n in catalog.nodes:
		var id := String(n["id"])
		var parents: PackedStringArray = n["requires"]
		var seen: Dictionary = {}
		for parent in parents:
			t.ok(catalog.has_id(parent), "%s: requires `%s`, which exists" % [id, parent])
			t.ok(parent != id, "%s: does not require itself" % id)
			t.ok(not seen.has(parent), "%s: lists `%s` once" % [id, parent])
			seen[parent] = true
			if catalog.has_id(parent):
				t.ok(int(catalog.def(parent)["tier"]) <= int(n["tier"]),
					"%s (T%d): parent `%s` is not from a later tier" % [id, int(n["tier"]), parent])
		for child in catalog.children_of(id):
			t.ok(catalog.parents_of(child).has(id), "%s: child index agrees with `%s`" % [id, child])

	# Acyclic: settle every node whose parents are already settled; anything left is a loop.
	var pending: Dictionary = {}
	for n in catalog.nodes:
		pending[String(n["id"])] = true
	var progress := true
	while progress:
		progress = false
		for id: String in pending.keys():
			var ready := true
			for parent in catalog.parents_of(id):
				if pending.has(parent):
					ready = false
					break
			if ready:
				pending.erase(id)
				progress = true
	t.eq(pending.size(), 0, "the requires graph is acyclic (stuck: %s)" % ", ".join(PackedStringArray(pending.keys())))


func _test_reveal_blocks(t: TestCtx, catalog: Upgrades) -> void:
	var with_reveal := 0
	for n in catalog.nodes:
		var id := String(n["id"])
		var reveal: Dictionary = n["reveal"]
		if reveal.is_empty():
			continue
		with_reveal += 1
		t.eq(reveal.size(), 1, "%s: exactly one reveal condition" % id)
		var key := String((reveal.keys() as Array)[0])
		t.ok(Upgrades.REVEAL_KEYS.has(key), "%s: reveal condition `%s` is known" % [id, key])
		match key:
			"rank":
				t.ok(int(reveal[key]) <= int(n["tier"]),
					"%s: reveal.rank %d does not trail its own tier" % [id, int(reveal[key])])
			"event":
				t.ok(Upgrades.REVEAL_EVENTS.has(String(reveal[key])),
					"%s: milestone `%s` is one the reveal engine fires" % [id, reveal[key]])
			"purchased":
				t.ok(catalog.has_id(String(reveal[key])),
					"%s: reveal.purchased points at a real node" % id)
			"dirty_held":
				t.ok(BigMoney.parse(String(reveal[key])).is_positive(),
					"%s: reveal.dirty_held parses" % id)
	# docs/04's design rule: the tree is a suspense engine, so something has to be hidden.
	t.ok(with_reveal >= 3, "the content actually uses reveal gates (%d nodes)" % with_reveal)


func _test_effects(t: TestCtx, catalog: Upgrades) -> void:
	var kinds_used: Dictionary = {}
	for n in catalog.nodes:
		var id := String(n["id"])
		var effects: Array = n["effects"]
		t.ok(not effects.is_empty(), "%s: has at least one effect" % id)
		for e: Variant in effects:
			var effect := e as Dictionary
			var kind: StringName = effect["kind"]
			kinds_used[kind] = true
			t.ok(Upgrades.EFFECT_SPECS.has(kind), "%s: effect kind `%s` is in the vocabulary" % [id, kind])
			if not Upgrades.EFFECT_SPECS.has(kind):
				continue
			var spec: Dictionary = Upgrades.EFFECT_SPECS[kind]
			var target := String(effect["target"])
			match kind:
				&"unlock_hardware":
					t.ok(Upgrades.HARDWARE_IDS.has(target), "%s: hardware `%s` is registered" % [id, target])
				&"feature_flag":
					t.ok(Upgrades.FEATURE_FLAGS.has(target), "%s: flag `%s` has code behind it" % [id, target])
				&"value_mult", &"value_add":
					t.ok(Upgrades.VALUE_GROUPS.has(target), "%s: switch group `%s` is known" % [id, target])
				&"kickback_unlock":
					t.ok(Upgrades.KICKBACK_SIDES.has(target), "%s: kickback side `%s`" % [id, target])
			if String(spec.get("value", "")) == "money":
				t.ok((effect["money"] as BigMoney).is_positive(), "%s: %s carries a positive amount" % [id, kind])
			elif spec.has("value"):
				t.ok(float(effect["num"]) != 0.0, "%s: %s carries a non-zero value" % [id, kind])
			if kind == &"value_mult" or kind == &"flipper_power_mult" or kind == &"collect_minutes_mult":
				t.ok(float(effect["num"]) > 1.0, "%s: %s is an upgrade, not a nerf" % [id, kind])
	t.ok(kinds_used.size() >= 12, "the M1 set exercises the effects vocabulary (%d kinds)" % kinds_used.size())


## Every node must move at least one number. A node whose effects all no-op is money the
## player spends on nothing, and it is exactly the kind of thing a rename breaks silently.
func _test_every_node_earns_its_place(t: TestCtx, catalog: Upgrades) -> void:
	var base := _snapshot(_stats(catalog, {}))
	for n in catalog.nodes:
		var id := String(n["id"])
		var one := _snapshot(_stats(catalog, {id: 1}))
		t.ok(one != base, "%s: buying it changes something" % id)
		if int(n["max_level"]) > 1:
			var maxed := _snapshot(_stats(catalog, {id: int(n["max_level"])}))
			t.ok(maxed != one, "%s: levelling it past 1 changes something" % id)


func _test_hardware_coverage(t: TestCtx, catalog: Upgrades) -> void:
	var unlockers: Dictionary = {}
	for n in catalog.nodes:
		var effects: Array = n["effects"]
		for e: Variant in effects:
			var effect := e as Dictionary
			if effect["kind"] != &"unlock_hardware":
				continue
			var target := String(effect["target"])
			t.ok(not unlockers.has(target),
				"hardware `%s` has one owner (%s and %s both claim it)" % [target, unlockers.get(target, ""), n["id"]])
			unlockers[target] = String(n["id"])
	# The M1 table lane needs these live by R3; the content has to actually sell them.
	for required in ["bumper_2", "slingshots", "rollovers", "spinner_numbers", "laundromat_loop",
			"storefront_laundromat", "storefront_pizzeria", "storefront_pawn", "orbit_left"]:
		t.ok(unlockers.has(required), "some node unlocks `%s`" % required)
	# Side-vocabulary unlocks bridge into hardware ids inside Stats, not the content file.
	var s := Stats.new()
	s.catalog = catalog
	s.recompute({"muscle.enforcer_corner": 1, "influence.beat_cop": 1})
	t.eq(s.hardware_unlocked(&"kickback_left"), true, "The Enforcer's Corner lights kickback_left")
	t.eq(s.hardware_unlocked(&"bribe_target"), true, "Beat Cop lights bribe_target")


## A fresh career must have something to buy on Night 1 with no rank, no parents and no
## milestone: tier 0, no requires, no reveal gate.
func _test_entry_points(t: TestCtx, catalog: Upgrades) -> void:
	var openers: PackedStringArray = []
	for n in catalog.nodes:
		var requires: PackedStringArray = n["requires"]
		var reveal: Dictionary = n["reveal"]
		if int(n["tier"]) == 0 and requires.is_empty() and reveal.is_empty():
			openers.append(String(n["id"]))
	t.ok(openers.size() >= 2, "R0 opens with something to buy: %s" % ", ".join(openers))
	var cheapest: BigMoney = null
	for id in openers:
		var c := catalog.cost_at_level(id, 0)
		cheapest = c if cheapest == null else BigMoney.min_of(cheapest, c)
	t.ok(cheapest != null and cheapest.cmp(BigMoney.parse("500")) <= 0,
		"the first purchase is inside one Night's earnings (%s)" % cheapest.text())


## Walk a whole career: every rank, every milestone fired, infinite money. Nothing in the
## file may be unreachable — an orphan node is content nobody will ever see.
func _test_career_reachability(t: TestCtx, catalog: Upgrades) -> void:
	var reveal := Reveal.new(catalog)
	for milestone in Upgrades.REVEAL_EVENTS:
		reveal.mark_event(StringName(milestone))
	reveal.note_dirty_held(BigMoney.parse("1e15"))
	var owned: Dictionary = {}
	for rank in range(0, Upgrades.MAX_TIER + 1):
		reveal.rank = rank
		var progress := true
		while progress:
			progress = false
			var states := reveal.states(owned)
			for n in catalog.nodes:
				var id := String(n["id"])
				if owned.has(id):
					continue
				if int(states.get(id, Reveal.State.HIDDEN)) != Reveal.State.REVEALED:
					continue
				if catalog.block_for(id, owned, rank, null) != Upgrades.Block.NONE:
					continue
				owned[id] = 1
				progress = true
	var missed: PackedStringArray = []
	for n in catalog.nodes:
		if not owned.has(String(n["id"])):
			missed.append(String(n["id"]))
	t.eq(missed.size(), 0, "every node is reachable in a full career (orphans: %s)" % ", ".join(missed))


func _test_reveal_engine(t: TestCtx, catalog: Upgrades) -> void:
	var reveal := Reveal.new(catalog)
	reveal.rank = 0
	var fresh := reveal.states({})
	var revealed := 0
	var facedown := 0
	var hidden := 0
	for id: Variant in fresh:
		match int(fresh[id]):
			Reveal.State.REVEALED:
				revealed += 1
			Reveal.State.FACEDOWN:
				facedown += 1
			_:
				hidden += 1
	t.ok(revealed >= 2, "a fresh R0 board shows something (%d cards)" % revealed)
	t.ok(facedown >= 1, "a fresh R0 board always has string running to a face-down card")
	t.ok(hidden >= 1, "docs/04: the player never sees the whole tree")

	# A face-down card must have a revealed parent; a hidden one must not.
	for n in catalog.nodes:
		var id := String(n["id"])
		var parents: PackedStringArray = n["requires"]
		if int(fresh[id]) != Reveal.State.FACEDOWN:
			continue
		var anchored := false
		for parent in parents:
			anchored = anchored or int(fresh[parent]) == Reveal.State.REVEALED
		t.ok(anchored, "%s is face-down because something visible points at it" % id)

	# Sticky conditions: a dirty_held threshold survives spending the money again.
	var gate := ""
	var gate_amount := ""
	for n in catalog.nodes:
		var rv: Dictionary = n["reveal"]
		if rv.has("dirty_held"):
			gate = String(n["id"])
			gate_amount = String(rv["dirty_held"])
			break
	if gate != "":
		t.eq(int(reveal.states({})[gate]), Reveal.State.HIDDEN, "%s starts hidden" % gate)
		t.eq(reveal.note_dirty_held(BigMoney.parse(gate_amount).mul(0.5)), 0, "half the threshold is not the threshold")
		t.ok(reveal.note_dirty_held(BigMoney.parse(gate_amount)) >= 1, "crossing the threshold fires once")
		t.eq(reveal.note_dirty_held(BigMoney.parse(gate_amount)), 0, "and only once")
		t.eq(int(reveal.states({})[gate]), Reveal.State.REVEALED, "%s stays revealed after the money is gone" % gate)

	# Milestone marks: first_tilt is one-shot and serializes.
	var tilt_gate := ""
	for n in catalog.nodes:
		var rv: Dictionary = n["reveal"]
		if rv.has("event") and String(rv["event"]) == "first_tilt":
			tilt_gate = String(n["id"])
			break
	if tilt_gate != "":
		t.eq(int(reveal.states({})[tilt_gate]), Reveal.State.HIDDEN, "%s waits for the first tilt" % tilt_gate)
		t.eq(reveal.mark_event(&"first_tilt"), true, "the first tilt is news")
		t.eq(reveal.mark_event(&"first_tilt"), false, "the second tilt is not")
		t.eq(int(reveal.states({})[tilt_gate]), Reveal.State.REVEALED, "%s flips up" % tilt_gate)

	var restored := Reveal.new(catalog)
	restored.from_dict(reveal.to_dict())
	restored.rank = reveal.rank
	t.eq(restored.states({}), reveal.states({}), "reveal state survives a save/load round trip")

	# Owning a node reveals it whatever its gate says (a save from a future content build).
	var late := Reveal.new(catalog)
	late.rank = 0
	var deep := String(catalog.nodes[catalog.nodes.size() - 1]["id"])
	t.eq(int(late.states({deep: 1})[deep]), Reveal.State.REVEALED, "an owned node is never hidden")


func _test_purchase_rules(t: TestCtx, catalog: Upgrades) -> void:
	var repeatable := ""
	var gated := ""
	for n in catalog.nodes:
		if repeatable == "" and int(n["max_level"]) > 1:
			repeatable = String(n["id"])
		var requires: PackedStringArray = n["requires"]
		if gated == "" and not requires.is_empty():
			gated = String(n["id"])
	t.ok(repeatable != "" and gated != "", "the content has a repeatable and a gated node to test with")
	if repeatable == "" or gated == "":
		return

	var rich := BigMoney.parse("1e12")
	var rep_def := catalog.def(repeatable)
	var rep_tier := int(rep_def["tier"])
	var rep_parents := {}
	for parent in catalog.parents_of(repeatable):
		rep_parents[parent] = 1

	t.eq(catalog.block_for(repeatable, rep_parents, rep_tier, rich), Upgrades.Block.NONE, "rank + parents + money = buy")
	t.eq(catalog.block_for(repeatable, rep_parents, rep_tier, BigMoney.zero()), Upgrades.Block.MONEY, "broke is MONEY")
	if rep_tier > 0:
		t.eq(catalog.block_for(repeatable, rep_parents, rep_tier - 1, rich), Upgrades.Block.RANK, "under rank is RANK")
	var maxed := rep_parents.duplicate()
	maxed[repeatable] = int(rep_def["max_level"])
	t.eq(catalog.block_for(repeatable, maxed, rep_tier, rich), Upgrades.Block.MAXED, "at max level is MAXED")
	t.eq(catalog.block_for("nope.not_a_node", {}, 7, rich), Upgrades.Block.UNKNOWN, "an unknown id is UNKNOWN")

	var gated_def := catalog.def(gated)
	t.eq(catalog.block_for(gated, {}, int(gated_def["tier"]), rich), Upgrades.Block.REQUIRES, "missing parents is REQUIRES")
	t.eq(catalog.requires_met(gated, {}), false, "requires_met sees the gap")
	var parents_owned: Dictionary = {}
	for parent in catalog.parents_of(gated):
		parents_owned[parent] = 1
	t.eq(catalog.requires_met(gated, parents_owned), true, "requires_met is satisfied by level 1 parents")

	# next_cost walks the ladder the docket shows.
	var ladder := rep_parents.duplicate()
	var first := catalog.next_cost(repeatable, ladder)
	ladder[repeatable] = 1
	var second := catalog.next_cost(repeatable, ladder)
	t.ok(second.cmp(first) > 0, "%s: the second one costs more than the first" % repeatable)

	# MAXED outranks MONEY: a maxed node is never advertised as "save up for this".
	t.eq(catalog.block_for(repeatable, maxed, rep_tier, BigMoney.zero()), Upgrades.Block.MAXED,
		"a maxed node reads MAXED even when broke")


func _test_ledger_state(t: TestCtx) -> void:
	var before := LedgerState.get_owned()
	LedgerState.clear()
	t.eq(LedgerState.get_owned(), {}, "cleared")
	LedgerState.set_owned({"rackets.trash_2": 2, "bad": 0, "worse": -4, 7: 3})
	t.eq(LedgerState.get_owned(), {"rackets.trash_2": 2}, "set_owned drops junk levels and non-string ids")
	t.eq(LedgerState.level_of("rackets.trash_2"), 2, "level_of")
	t.eq(LedgerState.add_level("rackets.trash_2"), 3, "add_level returns the new level")
	t.eq(LedgerState.add_level("muscle.real_plunger"), 1, "add_level starts a new node at 1")
	var copy := LedgerState.get_owned()
	copy["rackets.trash_2"] = 99
	t.eq(LedgerState.level_of("rackets.trash_2"), 3, "get_owned hands out a copy, not the store")
	LedgerState.set_level("rackets.trash_2", 0)
	t.eq(LedgerState.level_of("rackets.trash_2"), 0, "set_level 0 removes the node")
	LedgerState.set_owned(before)


# --- the loader's own promises ------------------------------------------------


func _valid_node() -> Dictionary:
	return {
		"id": "rackets.example", "branch": "rackets", "tier": 1,
		"name": "Example", "flavor": "A flavor.", "cost": "5K",
		"repeat": null, "requires": [], "reveal": {"rank": 1},
		"effects": [{"kind": "unlock_hardware", "target": "bumper_2"}],
		"table_change": "something visibly appears",
	}


func _load_nodes(nodes: Array) -> Upgrades:
	return Upgrades.from_variant({"schema": 1, "nodes": nodes}, "test fixture", true)


## `patch` is merged over a known-good node; `drop` removes keys. Both must be rejected
## loudly and the node must not survive into the catalog.
func _rejects(t: TestCtx, why: String, patch: Dictionary, drop: PackedStringArray = []) -> void:
	var node := _valid_node()
	node.merge(patch, true)
	for key in drop:
		node.erase(key)
	var u := _load_nodes([node])
	t.ok(u.errors.size() > 0, "loader reports: %s" % why)
	t.eq(u.nodes.size(), 0, "loader skips the node: %s" % why)


func _test_loader_rejects(t: TestCtx) -> void:
	var good := _load_nodes([_valid_node()])
	t.eq(good.errors.size(), 0, "the reference node is accepted: %s" % ", ".join(good.errors))
	t.eq(good.nodes.size(), 1, "the reference node loads")

	_rejects(t, "an unknown key (a typo in a hand-edited file)", {"requries": []})
	_rejects(t, "a missing name", {}, ["name"])
	_rejects(t, "a missing table_change", {}, ["table_change"])
	_rejects(t, "an empty flavor", {"flavor": "   "})
	_rejects(t, "an unknown branch", {"id": "syndicate.example", "branch": "syndicate"})
	_rejects(t, "an id that does not match its branch", {"id": "muscle.example"})
	_rejects(t, "a tier past R7", {"tier": 9})
	_rejects(t, "a non-numeric tier", {"tier": "one"})
	_rejects(t, "a cost that is a bare number", {"cost": 5000})
	_rejects(t, "a cost that does not parse", {"cost": "five thousand"})
	_rejects(t, "a zero cost", {"cost": "0"})
	_rejects(t, "a repeat that cannot repeat", {"repeat": {"max": 1, "growth": 1.15}})
	_rejects(t, "a repeat that never gets dearer", {"repeat": {"max": 5, "growth": 1.0}})
	_rejects(t, "a repeat with an unknown key", {"repeat": {"max": 5, "growth": 1.15, "cap": 2}})
	_rejects(t, "a repeatable with no per_level effect", {"repeat": {"max": 5, "growth": 1.15}})
	_rejects(t, "per_level on a one-off", {
		"effects": [{"kind": "value_mult", "target": "bumpers", "value": 1.2, "per_level": true}],
	})
	_rejects(t, "no effects at all", {"effects": []})
	_rejects(t, "an unknown effect kind", {"effects": [{"kind": "print_money", "value": 1}]})
	_rejects(t, "an unknown hardware id", {"effects": [{"kind": "unlock_hardware", "target": "bumper_9"}]})
	_rejects(t, "an unknown feature flag", {"effects": [{"kind": "feature_flag", "target": "wings"}]})
	_rejects(t, "an unknown switch group", {
		"effects": [{"kind": "value_mult", "target": "pinballs", "value": 1.2}],
	})
	_rejects(t, "a money value written as a number", {
		"effects": [{"kind": "value_add", "target": "bumpers", "value": 10}],
	})
	_rejects(t, "a money value that does not parse", {
		"effects": [{"kind": "launder_cap_add", "value": "a lot"}],
	})
	_rejects(t, "a launder rate above 100%", {"effects": [{"kind": "launder_rate_add", "value": 1.4}]})
	_rejects(t, "a fractional bench slot", {"effects": [{"kind": "bench_slot_add", "value": 1.5}]})
	_rejects(t, "an effect with an unknown key", {
		"effects": [{"kind": "bribe_unlock", "chance": 0.5}],
	})
	_rejects(t, "a target on an effect that takes none", {
		"effects": [{"kind": "bribe_unlock", "target": "left"}],
	})
	_rejects(t, "a value on an effect that takes none", {
		"effects": [{"kind": "unlock_hardware", "target": "bumper_2", "value": 3}],
	})
	_rejects(t, "an unknown kickback side", {"effects": [{"kind": "kickback_unlock", "target": "middle"}]})
	_rejects(t, "two reveal conditions at once", {"reveal": {"rank": 1, "event": "first_tilt"}})
	_rejects(t, "an unknown reveal condition", {"reveal": {"vibes": 3}})
	_rejects(t, "an unknown milestone", {"reveal": {"event": "first_pizza"}})
	_rejects(t, "a reveal that trails its own tier", {"tier": 1, "reveal": {"rank": 2}})
	_rejects(t, "a dirty_held gate that does not parse", {"reveal": {"dirty_held": "lots"}})
	_rejects(t, "a node that requires itself", {"requires": ["rackets.example"]})
	_rejects(t, "a requires entry that is not an id", {"requires": [7]})
	_rejects(t, "a requires list with a duplicate", {"requires": ["rackets.trash_2", "rackets.trash_2"]})
	_rejects(t, "a parent that does not exist", {"requires": ["rackets.nowhere"]})

	# Cross-node rules need more than one node.
	var dupes := _load_nodes([_valid_node(), _valid_node()])
	t.ok(dupes.errors.size() > 0, "loader reports a duplicate id")
	t.eq(dupes.nodes.size(), 1, "the duplicate is dropped, the first survives")

	var a := _valid_node()
	var b := _valid_node()
	a["id"] = "rackets.a"
	a["requires"] = ["rackets.b"]
	b["id"] = "rackets.b"
	b["requires"] = ["rackets.a"]
	var cycle := _load_nodes([a, b])
	t.ok(cycle.errors.size() > 0, "loader reports a requires cycle")

	var child := _valid_node()
	child["id"] = "rackets.child"
	child["tier"] = 0
	child["reveal"] = null
	child["requires"] = ["rackets.example"]
	var inverted := _load_nodes([_valid_node(), child])
	t.ok(inverted.errors.size() > 0, "loader reports a parent from a later tier")

	var ghost := _valid_node()
	ghost["id"] = "rackets.ghost"
	ghost["reveal"] = {"purchased": "rackets.nobody"}
	var ghosted := _load_nodes([ghost])
	t.ok(ghosted.errors.size() > 0, "loader reports reveal.purchased pointing nowhere")

	t.ok(Upgrades.from_json("{ not json", "broken", true).errors.size() > 0, "loader survives broken JSON")
	t.ok(Upgrades.from_variant([], "array", true).errors.size() > 0, "loader survives a non-object root")
	t.ok(Upgrades.from_variant({"schema": 1}, "empty", true).errors.size() > 0, "loader survives a missing nodes array")
	t.ok(Upgrades.from_variant({"schema": 99, "nodes": []}, "future", true).errors.size() > 0,
		"loader refuses a schema it does not speak")
	t.ok(Upgrades.from_file("res://game/content/no_such_file.json", true).errors.size() > 0,
		"loader survives a missing file")


# --- helpers ------------------------------------------------------------------


func _stats(catalog: Upgrades, owned: Dictionary) -> Stats:
	var s := Stats.new()
	s.catalog = catalog
	s.recompute(owned)
	return s


## Every number Stats exposes, in one comparable value.
func _snapshot(s: Stats) -> Array:
	var out: Array = []
	for group in Upgrades.VALUE_GROUPS:
		out.append(s.value_mult(StringName(group)))
		out.append(s.value_add(StringName(group)).to_dict())
	for hardware in Upgrades.HARDWARE_IDS:
		out.append(s.hardware_unlocked(StringName(hardware)))
	for flag in Upgrades.FEATURE_FLAGS:
		out.append(s.flag(StringName(flag)))
	out.append(s.idle_rate_total().to_dict())
	out.append(s.launder_cap().to_dict())
	out.append(s.pocket_money().to_dict())
	out.append(s.launder_rate())
	out.append(s.passive_wash_per_sec())
	out.append(s.safe_hours())
	out.append(s.flipper_power())
	out.append(s.collect_minutes())
	out.append(s.bench_slots())
	out.append(s.ball_saves())
	out.append(s.tilt_leans())
	out.append(s.job_slots())
	out.append(s.kickbacks())
	out.append(s.bribe_unlocked())
	return out
