extends RefCounted
## The guard rail for `game/content/blackbook.json`.
##
## Same job as tests/test_upgrades_data.gd, one shelf up: the Black Book is design-owned data
## tuned in data-only commits, so this file is what stands between a typo and a shipped build.
## It checks the shape of every perk, the whole docs/06 §3 table row by row (cost, ★ mark and
## rule text — the design document IS the specification here), that every perk moves a
## `Prestige` number, and the other half of the job: that the loader really rejects the
## mistakes it claims to reject.


## docs/06 §3, transcribed: id -> [cost, deferred (the ★ rows), max_level, note].
##
## The note is the design table's Notes column verbatim, minus markdown emphasis — JSON is
## data, not markup. A doc edit is meant to break this test; that is the whole point of it.
const DOCS_TABLE := {
	"blackbook.old_contacts": [1, false, 3,
		"start each city at +1 rank (max R3 start)"],
	"blackbook.kept_man": [1, false, 3,
		"one chosen specialist survives Skip Town (slot per level)"],
	"blackbook.traveling_light": [2, false, 1,
		"Pocket Money auto-clean scales with city #"],
	"blackbook.reputation_precedes_you": [2, false, 1,
		"first Commission boss of each city starts at phase 2"],
	"blackbook.the_stash": [3, false, 1,
		"begin each city with 5% of previous city's clean cash (dirty, ha)"],
	"blackbook.everybody_knows_somebody": [3, false, 1,
		"Bench starts with 2 leveled guys"],
	"blackbook.double_life": [5, true, 1,
		"previous city's idle income keeps flowing at 10% (stacking cities = the empire never really resets)"],
	"blackbook.the_big_sleep": [5, true, 3,
		"retire a maxed specialist forever → he becomes a patron-saint statue on all future tables: a small aura zone with his power at half strength, always on. The roster of saints grows across prestiges — your history literally watches over the table"],
	"blackbook.museum_of_crime": [8, true, 1,
		"unlocks the relic gallery: heist relics socket into set bonuses (3 Museum pieces = permanent +1 casino edge, etc.)"],
	"blackbook.fast_learner": [8, false, 1,
		"☆ requirements −20% in cities you've beaten before"],
	"blackbook.the_golden_era": [10, true, 1,
		"unlock the Golden Ball tier in every city at T5 instead of T7"],
	"blackbook.silent_empire": [15, true, 1,
		"offline Safe cap doubles AND fills with 10% clean directly"],
	"blackbook.the_sixth_family": [25, true, 1,
		"New Game++: all five cities' Commissions rolled into one repeatable gauntlet table (post-launch content hook)"],
}

## The order docs/06 §3 lists them in, which is cost order, which is the board's spine.
const DOCS_ORDER: PackedStringArray = [
	"blackbook.old_contacts", "blackbook.kept_man", "blackbook.traveling_light",
	"blackbook.reputation_precedes_you", "blackbook.the_stash",
	"blackbook.everybody_knows_somebody", "blackbook.double_life", "blackbook.the_big_sleep",
	"blackbook.museum_of_crime", "blackbook.fast_learner", "blackbook.the_golden_era",
	"blackbook.silent_empire", "blackbook.the_sixth_family",
]

## A live perk's flavor prints as ONE line on its card (game/ui/ledger/blackbook_board.gd),
## and a line that runs off the edge is worse than a shorter joke.
const FLAVOR_MAX := 46


func run(t: TestCtx) -> void:
	var book := BlackBook.from_file(BlackBook.DEFAULT_PATH)
	_test_loads_clean(t, book)
	if book.perks.is_empty():
		return
	_test_docs_table(t, book)
	_test_identity(t, book)
	_test_cost_ladders(t, book)
	_test_effects(t, book)
	_test_every_perk_earns_its_place(t, book)
	_test_deferred_discipline(t, book)
	_test_perk_english(t)
	_test_loader_rejects(t)


# --- the shipped file ---------------------------------------------------------


func _test_loads_clean(t: TestCtx, book: BlackBook) -> void:
	t.eq(book.errors.size(), 0, "blackbook.json loads clean: %s" % ", ".join(book.errors))
	t.eq(book.schema, BlackBook.SCHEMA_VERSION, "schema version")
	t.ok(book.is_valid(), "the Book reports itself valid")
	t.eq(book.perks.size(), DOCS_TABLE.size(), "every docs/06 §3 row shipped")


## The design table, row by row. Cost, ★ mark, ↻ levels and rule text all have to agree with
## docs/06 §3 — this is the one test that would catch a perk quietly getting cheaper.
func _test_docs_table(t: TestCtx, book: BlackBook) -> void:
	for id: String in DOCS_TABLE:
		var row: Array = DOCS_TABLE[id]
		var perk := book.def(id)
		t.ok(not perk.is_empty(), "docs/06 §3 perk `%s` is in the Book" % id)
		if perk.is_empty():
			continue
		t.eq(int(perk["cost"]), int(row[0]), "%s costs %d Juice" % [id, int(row[0])])
		t.eq(bool(perk["deferred"]), bool(row[1]),
			"%s is %s" % [id, "★ deferred" if bool(row[1]) else "live"])
		t.eq(int(perk["max_level"]), int(row[2]), "%s levels to %d" % [id, int(row[2])])
		t.eq(String(perk["note"]), String(row[3]), "%s carries its docs/06 rule verbatim" % id)

	t.eq(book.ids(), DOCS_ORDER, "the Book is in docs/06 §3 order, which is cost order")
	var last := 0
	for id in book.ids():
		var cost := int(book.def(id)["cost"])
		t.ok(cost >= last, "%s at %d Juice does not undercut the row above it" % [id, cost])
		last = cost


func _test_identity(t: TestCtx, book: BlackBook) -> void:
	var seen: Dictionary = {}
	for p in book.perks:
		var id := String(p["id"])
		t.ok(not seen.has(id), "id `%s` is unique" % id)
		seen[id] = true
		t.ok(id.begins_with(BlackBook.ID_PREFIX), "%s: id carries the blackbook prefix" % id)
		t.ok(id.split(".").size() == 2 and not id.ends_with("."), "%s: id is blackbook.slug" % id)
		for key in ["name", "flavor", "note"]:
			t.ok(not String(p[key]).strip_edges().is_empty(), "%s: has a %s" % [id, key])
		t.ok(String(p["note"]).length() > 8, "%s: the note says something" % id)
		if not bool(p["deferred"]):
			t.ok(String(p["flavor"]).length() <= FLAVOR_MAX,
				"%s: flavor fits one line on the card (%d/%d chars)"
					% [id, String(p["flavor"]).length(), FLAVOR_MAX])
		t.ok((p["requires"] as PackedStringArray).is_empty(),
			"%s: docs/06 §3 has no prerequisites — the Book is flat, gated only by Juice" % id)


func _test_cost_ladders(t: TestCtx, book: BlackBook) -> void:
	for p in book.perks:
		var id := String(p["id"])
		var base := int(p["cost"])
		var repeat: Variant = p["repeat"]
		t.eq(book.cost_at_level(id, 0), base, "%s: the first level costs the listed price" % id)
		if repeat == null:
			t.eq(book.cost_at_level(id, 4), base, "%s: a one-off never gets more expensive" % id)
			t.eq(book.total_cost(id), base, "%s: and its whole ladder is one price" % id)
			t.eq(book.is_repeatable(id), false, "%s: is a one-off" % id)
			continue
		var step := int((repeat as Dictionary)["step"])
		t.ok(book.is_repeatable(id), "%s: is a ↻ perk" % id)
		var sum := 0
		for level in book.max_level(id):
			t.eq(book.cost_at_level(id, level), base + step * level,
				"%s: level %d costs base + step × level" % [id, level + 1])
			sum += base + step * level
		t.eq(book.total_cost(id), sum, "%s: total_cost is the whole ladder" % id)
		# A ladder nobody could ever finish is a ladder with a broken step.
		t.ok(book.total_cost(id) <= BlackBook.MAX_COST,
			"%s: the whole ladder (%d) stays inside a reachable number of Juice"
				% [id, book.total_cost(id)])


func _test_effects(t: TestCtx, book: BlackBook) -> void:
	var kinds_used: Dictionary = {}
	for p in book.perks:
		var id := String(p["id"])
		var effects: Array = p["effects"]
		t.ok(not effects.is_empty(), "%s: has at least one effect" % id)
		for e: Variant in effects:
			var effect := e as Dictionary
			var kind: StringName = effect["kind"]
			kinds_used[kind] = true
			t.ok(BlackBook.PERK_SPECS.has(kind) or Upgrades.EFFECT_SPECS.has(kind),
				"%s: effect kind `%s` is in a vocabulary" % [id, kind])
			t.eq(String(effect["target"]), "", "%s: a perk effect takes no target" % id)
			if not BlackBook.PERK_SPECS.has(kind):
				continue
			var spec: Dictionary = BlackBook.PERK_SPECS[kind]
			if spec.has("value"):
				t.ok(float(effect["num"]) != 0.0, "%s: %s carries a non-zero value" % [id, kind])
				t.ok(float(effect["num"]) >= float(spec.get("min", -INF))
					and float(effect["num"]) <= float(spec.get("max", INF)),
					"%s: %s value %f is inside its band" % [id, kind, float(effect["num"])])
			else:
				t.near(float(effect["num"]), 0.0, 1e-9, "%s: %s is a flag, not a number" % [id, kind])
			if bool(effect["per_level"]):
				t.ok(p["repeat"] != null, "%s: per_level needs a repeat block" % id)
	# The Book is the only user of its vocabulary; a kind nobody uses is a kind nobody tested.
	t.ok(kinds_used.size() >= 12,
		"the shipped Book exercises the perk vocabulary (%d kinds)" % kinds_used.size())


## Every perk must move at least one number a lane can read — deferred ones included, because
## the day M4 turns them on is not the day to discover the effect was a no-op. The check runs
## against a copy of the shipped data with `deferred` cleared, since a deferred perk cannot be
## bought (and `Prestige.set_owned` refuses to own one).
func _test_every_perk_earns_its_place(t: TestCtx, book: BlackBook) -> void:
	var live := _shipped_all_live()
	t.eq(live.errors.size(), 0, "the all-live copy of the Book loads: %s" % ", ".join(live.errors))
	var base := _snapshot(_prestige(live, {}))
	for p in live.perks:
		var id := String(p["id"])
		var one := _snapshot(_prestige(live, {id: 1}))
		t.ok(one != base, "%s: owning it changes something" % id)
		if int(p["max_level"]) > 1:
			var maxed := _snapshot(_prestige(live, {id: int(p["max_level"])}))
			t.ok(maxed != one, "%s: levelling it past 1 changes something" % id)


func _test_deferred_discipline(t: TestCtx, book: BlackBook) -> void:
	var rich := _prestige(book, {})
	rich.award(BlackBook.MAX_COST * 2)
	var deferred_count := 0
	for p in book.perks:
		var id := String(p["id"])
		if not bool(p["deferred"]):
			t.eq(book.block_for(id, {}, 999), BlackBook.Block.NONE,
				"%s: a live perk is for sale to a full wallet" % id)
			continue
		deferred_count += 1
		t.eq(book.block_for(id, {}, 999), BlackBook.Block.DEFERRED,
			"%s: a ★ perk is never for sale, however much Juice is on the table" % id)
		t.eq(rich.buy(id), 0, "%s: buying it does nothing" % id)
	t.ok(deferred_count > 0 and deferred_count < book.perks.size(),
		"the Book ships both kinds: %d deferred of %d" % [deferred_count, book.perks.size()])
	t.eq(rich.owned().size(), 0, "and a wallet full of Juice bought none of them")


## Every kind in the vocabulary says something in English. A kind that falls through prints
## its own name, which is how a missing line shows up on a card.
func _test_perk_english(t: TestCtx) -> void:
	for kind: Variant in BlackBook.PERK_SPECS:
		var spec: Dictionary = BlackBook.PERK_SPECS[kind]
		var value := float(spec.get("min", 1.0))
		if spec.get("value", &"") == &"int":
			value = roundf(maxf(value, 1.0))
		elif spec.has("value"):
			value = maxf(value, 0.05)
		var effect := {
			"kind": StringName(String(kind)), "target": StringName(""),
			"num": value, "money": BigMoney.zero(), "per_level": false, "perk_kind": true,
		}
		var line := LedgerStyle.perk_line(effect)
		t.ok(not line.is_empty() and line != String(kind),
			"perk kind `%s` has an English line (got `%s`)" % [kind, line])

	# The two shapes the Black Book page prints on its own.
	t.eq(LedgerStyle.juice(1), "1 JUICE", "Juice is a count, never a money string")
	t.eq(LedgerStyle.juice(25), "25 JUICE", "…at any size")

	var book := BlackBook.shared()
	var poor := Prestige.new(book)
	poor.award(1)
	t.eq(LedgerStyle.perk_block_reason(BlackBook.Block.DEFERRED, book,
		"blackbook.museum_of_crime", poor), "NOT IN THIS LIFE. YET.", "a ★ perk says so")
	t.eq(LedgerStyle.perk_block_reason(BlackBook.Block.JUICE, book,
		"blackbook.the_stash", poor), "NEEDS 2 MORE JUICE", "a short wallet says how short")
	t.eq(LedgerStyle.perk_block_reason(BlackBook.Block.MAXED, book,
		"blackbook.the_stash", poor), "IN THE BOOK", "an owned perk says so")


# --- the loader ---------------------------------------------------------------


func _test_loader_rejects(t: TestCtx) -> void:
	var good := _load([_valid_perk()])
	t.eq(good.errors.size(), 0, "the reference perk is accepted: %s" % ", ".join(good.errors))
	t.eq(good.perks.size(), 1, "the reference perk loads")

	_rejects(t, "an unknown key (a typo in a hand-edited file)", {"defered": true})
	_rejects(t, "a missing name", {}, ["name"])
	_rejects(t, "a missing note", {}, ["note"])
	_rejects(t, "a missing flavor", {}, ["flavor"])
	_rejects(t, "an empty note", {"note": "   "})
	_rejects(t, "an id outside the blackbook namespace", {"id": "rackets.example"})
	_rejects(t, "an id with no slug", {"id": "blackbook."})
	_rejects(t, "an id slug that is not lower_snake_case", {"id": "blackbook.Old Contacts"})
	_rejects(t, "a cost written as a money string", {"cost": "3"})
	_rejects(t, "a fractional cost (Juice is countable)", {"cost": 2.5})
	_rejects(t, "a free perk", {"cost": 0})
	_rejects(t, "a negative cost", {"cost": -3})
	_rejects(t, "a cost past the ceiling", {"cost": BlackBook.MAX_COST + 1})
	_rejects(t, "a deferred flag that is not a bool", {"deferred": "yes"})
	_rejects(t, "a repeat that cannot repeat", {"repeat": {"max": 1, "step": 1}})
	_rejects(t, "a repeat with a free second level", {"repeat": {"max": 3, "step": 0}})
	_rejects(t, "a repeat with a fractional step", {"repeat": {"max": 3, "step": 1.5}})
	_rejects(t, "a repeat with an unknown key", {"repeat": {"max": 3, "step": 1, "growth": 1.15}})
	_rejects(t, "a repeat missing its step", {"repeat": {"max": 3}})
	_rejects(t, "a repeatable with no per_level effect", {
		"repeat": {"max": 3, "step": 1},
		"effects": [{"kind": "museum"}],
	})
	_rejects(t, "per_level on a one-off", {
		"effects": [{"kind": "start_rank", "value": 1, "per_level": true}],
	})
	_rejects(t, "no effects at all", {"effects": []})
	_rejects(t, "an unknown effect kind", {"effects": [{"kind": "free_money", "value": 1}]})
	_rejects(t, "an effect with an unknown key", {
		"effects": [{"kind": "museum", "chance": 0.5}],
	})
	_rejects(t, "a target on a perk effect", {
		"effects": [{"kind": "start_rank", "value": 1, "target": "all"}],
	})
	_rejects(t, "a value on a flag perk", {"effects": [{"kind": "museum", "value": 1}]})
	_rejects(t, "a flag perk asked for a value it does not take", {
		"effects": [{"kind": "gauntlet", "value": 2}],
	})
	_rejects(t, "a perk effect with no value at all", {"effects": [{"kind": "start_rank"}]})
	_rejects(t, "a value written as a string", {"effects": [{"kind": "start_rank", "value": "1"}]})
	_rejects(t, "requires that is not an array", {"requires": "blackbook.other"})
	_rejects(t, "a perk that requires itself", {"requires": ["blackbook.example"]})
	_rejects(t, "a requires entry that is not an id", {"requires": [7]})
	_rejects(t, "a parent that does not exist", {"requires": ["blackbook.nowhere"]})

	# The bands ARE the design: each perk kind's value is the only thing standing between
	# "+1 rank" and "start every city at R7".
	_rejects_effect(t, "a start_rank past the docs/06 max R3 start", {"kind": "start_rank", "value": 4})
	_rejects_effect(t, "a start_rank of zero", {"kind": "start_rank", "value": 0})
	_rejects_effect(t, "a fractional start_rank", {"kind": "start_rank", "value": 1.5})
	_rejects_effect(t, "a fourth kept man", {"kind": "kept_specialist", "value": 4})
	_rejects_effect(t, "a boss opening at phase 1 (that is just a fight)",
		{"kind": "boss_start_phase", "value": 1})
	_rejects_effect(t, "a boss opening past its last phase", {"kind": "boss_start_phase", "value": 4})
	# 0.5 instead of 0.05 is THE typo this band exists to catch.
	_rejects_effect(t, "a stash of half the last city", {"kind": "stash_fraction", "value": 0.5})
	_rejects_effect(t, "a stash of nothing", {"kind": "stash_fraction", "value": 0.0})
	_rejects_effect(t, "a Bench that starts fuller than it is", {"kind": "bench_starters", "value": 5})
	_rejects_effect(t, "a ☆ discount past half", {"kind": "star_requirement_mult", "value": 0.4})
	_rejects_effect(t, "a ☆ multiplier that makes the ladder LONGER",
		{"kind": "star_requirement_mult", "value": 1.2})
	_rejects_effect(t, "an idle carryover of half the last city",
		{"kind": "idle_carryover", "value": 0.5})
	_rejects_effect(t, "a fourth saint", {"kind": "saint_statue", "value": 4})
	_rejects_effect(t, "a Golden Ball before T4", {"kind": "golden_ball_tier", "value": 3})
	_rejects_effect(t, "a Safe multiplied by five", {"kind": "safe_cap_mult", "value": 5.0})
	_rejects_effect(t, "a Safe multiplier that shrinks it", {"kind": "safe_cap_mult", "value": 0.5})
	_rejects_effect(t, "a Safe that fills half-clean", {"kind": "safe_clean_share", "value": 0.5})

	# …and the design numbers themselves must load.
	var every := _valid_perk()
	every["repeat"] = {"max": 3, "step": 2}
	every["effects"] = [
		{"kind": "start_rank", "value": 1, "per_level": true},
		{"kind": "kept_specialist", "value": 1, "per_level": true},
		{"kind": "pocket_city_scale"},
		{"kind": "boss_start_phase", "value": 2},
		{"kind": "stash_fraction", "value": 0.05},
		{"kind": "bench_starters", "value": 2},
		{"kind": "star_requirement_mult", "value": 0.8},
		{"kind": "idle_carryover", "value": 0.10},
		{"kind": "saint_statue", "value": 1, "per_level": true},
		{"kind": "museum"},
		{"kind": "golden_ball_tier", "value": 5},
		{"kind": "safe_cap_mult", "value": 2.0},
		{"kind": "safe_clean_share", "value": 0.10},
		{"kind": "gauntlet"},
	]
	var loaded := _load([every])
	t.eq(loaded.errors.size(), 0, "the docs/06 §3 numbers all load: %s" % ", ".join(loaded.errors))
	t.eq(loaded.perks.size(), 1, "a perk carrying every promise loads")

	# A perk may borrow the LEDGER's vocabulary, and it is measured against the Ledger's bands.
	var borrowed := _valid_perk()
	borrowed["effects"] = [{"kind": "idle_rate_add", "target": "union", "value": "2K"}]
	t.eq(_load([borrowed]).errors.size(), 0, "a perk may promise a Ledger effect")
	borrowed["effects"] = [{"kind": "value_mult", "target": "pinballs", "value": 1.2}]
	t.ok(_load([borrowed]).errors.size() > 0, "…and the Ledger's target vocabulary still applies")
	borrowed["effects"] = [{"kind": "clean_share", "value": 0.9}]
	t.ok(_load([borrowed]).errors.size() > 0, "…and so do the Ledger's bands")
	borrowed["effects"] = [{"kind": "idle_rate_add", "target": "union", "value": 2000}]
	t.ok(_load([borrowed]).errors.size() > 0, "…and money is still a string, not a number")

	# Cross-perk rules need more than one perk.
	var dupes := _load([_valid_perk(), _valid_perk()])
	t.ok(dupes.errors.size() > 0, "loader reports a duplicate id")
	t.eq(dupes.perks.size(), 1, "the duplicate is dropped, the first survives")

	var a := _valid_perk()
	var b := _valid_perk()
	a["id"] = "blackbook.a"
	a["requires"] = ["blackbook.b"]
	b["id"] = "blackbook.b"
	b["requires"] = ["blackbook.a"]
	t.ok(_load([a, b]).errors.size() > 0, "loader reports a requires cycle")

	# A live perk behind a ★ perk is a live perk nobody could ever reach.
	var star := _valid_perk()
	star["id"] = "blackbook.star"
	star["deferred"] = true
	var behind := _valid_perk()
	behind["id"] = "blackbook.behind"
	behind["requires"] = ["blackbook.star"]
	var stuck := _load([star, behind])
	t.ok(stuck.errors.size() > 0, "loader reports a live perk gated behind a deferred one")
	t.eq(stuck.perks.size(), 1, "…and drops the unreachable one")

	t.ok(BlackBook.from_json("{ not json", "broken", true).errors.size() > 0,
		"loader survives broken JSON")
	t.ok(BlackBook.from_variant([], "array", true).errors.size() > 0,
		"loader survives a non-object root")
	t.ok(BlackBook.from_variant({"schema": 1}, "empty", true).errors.size() > 0,
		"loader survives a missing perks array")
	t.ok(BlackBook.from_variant({"schema": 1, "perks": [], "notes": "hi"}, "extra", true)
		.errors.size() > 0, "loader refuses a stray root key")
	t.ok(BlackBook.from_variant({"schema": 99, "perks": []}, "future", true).errors.size() > 0,
		"loader refuses a schema it does not speak")
	t.ok(BlackBook.from_file("res://game/content/no_such_book.json", true).errors.size() > 0,
		"loader survives a missing file")


# --- helpers ------------------------------------------------------------------


func _valid_perk() -> Dictionary:
	return {
		"id": "blackbook.example", "name": "Example", "flavor": "A flavor.",
		"note": "does something permanent", "cost": 3, "repeat": null, "requires": [],
		"deferred": false, "effects": [{"kind": "museum"}],
	}


func _load(perks: Array) -> BlackBook:
	return BlackBook.from_variant({"schema": 1, "perks": perks}, "test fixture", true)


func _rejects(t: TestCtx, why: String, patch: Dictionary, drop: PackedStringArray = []) -> void:
	var perk := _valid_perk()
	perk.merge(patch, true)
	for key in drop:
		perk.erase(key)
	var b := _load([perk])
	t.ok(b.errors.size() > 0, "loader reports: %s" % why)
	t.eq(b.perks.size(), 0, "loader skips the perk: %s" % why)


func _rejects_effect(t: TestCtx, why: String, effect: Dictionary) -> void:
	_rejects(t, why, {"repeat": null, "effects": [effect]})


func _prestige(book: BlackBook, owned: Dictionary) -> Prestige:
	var p := Prestige.new(book)
	p.set_owned(owned)
	return p


## The shipped Book with every ★ cleared, so the deferred half can be exercised at all.
func _shipped_all_live() -> BlackBook:
	var text := FileAccess.get_file_as_string(BlackBook.DEFAULT_PATH)
	var json := JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return BlackBook.from_variant({}, "all-live copy", true)
	var root: Dictionary = (json.data as Dictionary).duplicate(true)
	for entry: Variant in root.get("perks", []):
		if entry is Dictionary:
			(entry as Dictionary)["deferred"] = false
	return BlackBook.from_variant(root, "all-live copy", true)


## Every number a Prestige exposes, in one comparable value.
func _snapshot(p: Prestige) -> Array:
	return [
		p.start_rank(), p.kept_specialists(), p.pocket_scales_with_city(), p.stash_fraction(),
		p.bench_starters(), p.boss_start_phase(), p.star_requirement_mult(),
		p.idle_carryover(), p.saint_statues(), p.museum_unlocked(), p.golden_ball_tier(),
		p.safe_cap_mult(), p.safe_clean_share(), p.gauntlet_unlocked(), p.stats_effects().size(),
	]
