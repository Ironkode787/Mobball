extends RefCounted
## The Bench (game/flow/bench.gd): roster, pinches, bail, and the walk home.


func run(t: TestCtx) -> void:
	_roster(t)
	_pinch_and_bail(t)
	_night_tick(t)
	_never_hard_locks(t)
	_serialization(t)


func _roster(t: TestCtx) -> void:
	var b := Bench.new(1234)
	t.eq(b.guys.size(), Bench.START_SLOTS, "roster starts at four guys")
	t.eq(b.available().size(), Bench.START_SLOTS, "everyone starts free")
	for g in b.guys:
		t.ok(not String(g["name"]).is_empty(), "every guy has a name")
		t.eq(int(g["level"]), 0, "nobodies start at level 0")

	var same := Bench.new(1234)
	t.eq(String(same.guys[0]["name"]), String(b.guys[0]["name"]), "same seed, same crew")
	var other := Bench.new(999)
	var differs := false
	for i in b.guys.size():
		if String(other.guys[i]["name"]) != String(b.guys[i]["name"]):
			differs = true
	t.ok(differs, "a different seed hires different people")

	var ids := {}
	for g in b.guys:
		ids[int(g["id"])] = true
	t.eq(ids.size(), b.guys.size(), "guy ids are unique")


func _pinch_and_bail(t: TestCtx) -> void:
	var b := Bench.new(7)
	var guy := b.guys[0]
	t.ok(not b.bail_cost(guy).is_positive(), "a free guy costs nothing to bail")

	b.pinch(guy)
	t.eq(String(guy["state"]), Bench.STATE_HOLDING, "a pinched guy is in holding")
	t.eq(b.available().size(), Bench.START_SLOTS - 1, "he is off the roster")
	t.eq(b.holding().size(), 1, "and in the holding list")
	var first_cost := b.bail_cost(guy)
	t.ok(first_cost.equals_approx(Rates.bail_cost(0, 0, false)), "first bail is the base rate")

	var paid := b.bail(guy)
	t.ok(paid.equals_approx(first_cost), "bail() returns what was owed")
	t.eq(String(guy["state"]), Bench.STATE_FREE, "bail springs him immediately")
	t.ok(not b.bail(guy).is_positive(), "bailing a free guy is free and a no-op")

	b.pinch(guy)
	t.ok(b.bail_cost(guy).cmp(first_cost) > 0, "a rap sheet makes the next bail dearer")

	var raid_guy := b.guys[1]
	b.pinch(raid_guy, true)
	t.ok(bool(raid_guy["from_raid"]), "a raid pinch is flagged")
	t.eq(int(raid_guy["sit_out"]), Bench.SIT_OUT_NIGHTS_RAID, "raids hand out longer stretches")
	t.ok(b.bail_cost(raid_guy).equals_approx(Rates.bail_cost(0, 0, true)),
			"raid bail carries the x3")


func _night_tick(t: TestCtx) -> void:
	var b := Bench.new(11)
	var guy := b.guys[0]
	var raid_guy := b.guys[1]
	b.pinch(guy)
	b.pinch(raid_guy, true)

	b.night_tick()
	t.eq(String(guy["state"]), Bench.STATE_HOLDING, "a stretch outlasts the first Night")
	b.night_tick()
	t.eq(String(guy["state"]), Bench.STATE_FREE, "two Nights off and he walks")
	t.eq(String(raid_guy["state"]), Bench.STATE_HOLDING, "the raid stretch is longer")
	b.night_tick()
	t.eq(String(raid_guy["state"]), Bench.STATE_FREE, "and it ends after the third Night")
	t.ok(not bool(raid_guy["from_raid"]), "walking clears the raid flag")

	var survivor := b.guys[2]
	for i in Bench.NIGHTS_PER_LEVEL:
		b.survived_night(survivor)
	t.eq(int(survivor["level"]), 1, "guys level slowly by surviving Nights")


func _never_hard_locks(t: TestCtx) -> void:
	var b := Bench.new(3)
	for g in b.guys.duplicate():
		b.pinch(g)
	t.eq(b.available().size(), 0, "everyone is inside")
	b.night_tick()
	t.ok(b.available().size() >= 1, "the night_tick always leaves somebody to field")

	var wide := Bench.new(3)
	wide.night_tick(6)
	t.eq(wide.guys.size(), 6, "more Bench slots hire more nobodies")
	t.eq(wide.slots, 6, "and the roster remembers the new size")


func _serialization(t: TestCtx) -> void:
	var b := Bench.new(42)
	b.pinch(b.guys[0])
	b.survived_night(b.guys[1])
	b.hire()
	var dict := b.to_dict()
	var through_json: Variant = JSON.parse_string(JSON.stringify(dict))
	t.ok(through_json is Dictionary, "the roster survives JSON")

	var loaded := Bench.new(0)
	loaded.from_dict(through_json)
	t.eq(JSON.stringify(loaded.to_dict()), JSON.stringify(dict), "round-trip is exact")
	t.eq(loaded.guys.size(), b.guys.size(), "same crew size")
	t.eq(String(loaded.guys[0]["state"]), Bench.STATE_HOLDING, "holding survives the save")

	var junk := Bench.new(0)
	junk.from_dict({"guys": [{"name": "Half A Guy"}, "not a guy"]})
	t.eq(junk.guys.size(), 1, "corrupt entries are dropped, not crashed on")
	t.eq(String(junk.guys[0]["state"]), Bench.STATE_FREE, "a half-written guy is made whole")
