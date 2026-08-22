extends RefCounted
## The morning paper (game/flow/headlines.gd) and the rank ladder it names.


func run(t: TestCtx) -> void:
	_data(t)
	_conditions(t)
	_placeholders(t)
	_ranks(t)


func _data(t: TestCtx) -> void:
	var h := Headlines.new()
	t.ok(h.loaded(), "headlines.json loaded")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var line := h.pick({}, rng)
	t.ok(not line.is_empty(), "an empty Night still gets a front page")

	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	t.eq(h.pick({}, a), h.pick({}, b), "the same seed prints the same paper")


func _conditions(t: TestCtx) -> void:
	var h := Headlines.new()
	t.eq(h.condition_for({"rank_up": true, "raid": "lost", "tilts": 2}), "rank_up",
			"a promotion is the lead story, whatever else happened")
	t.eq(h.condition_for({"raid": "survived"}), "raid_survived", "beating the rap makes the paper")
	t.eq(h.condition_for({"raid": "lost"}), "raid_lost", "so does losing it")
	t.eq(h.condition_for({"tilts": 1}), "tilted", "the inspector files his report")
	t.eq(h.condition_for({"bench_free": 0}), "all_guys_lost", "an empty Bench is news")
	t.eq(h.condition_for({
		"bench_free": 2,
		"dirty": BigMoney.parse("1K"),
		"laundered": BigMoney.parse("800"),
	}), "laundered_big", "a big wash is a laundering story")
	t.eq(h.condition_for({
		"bench_free": 2,
		"dirty": BigMoney.parse("10K"),
		"best_night": BigMoney.parse("1K"),
	}), "big_night", "a record take is a big night")
	t.eq(h.condition_for({
		"bench_free": 2,
		"dirty": BigMoney.parse("50"),
		"best_night": BigMoney.parse("10K"),
		"quiet_floor": BigMoney.parse("200"),
	}), "quiet_night", "under the pocket-money floor is a quiet night")
	t.eq(h.condition_for({
		"bench_free": 2,
		"dirty": BigMoney.parse("5K"),
		"best_night": BigMoney.parse("10K"),
		"quiet_floor": BigMoney.parse("200"),
	}), "default", "an ordinary Night gets the ordinary headline")


func _placeholders(t: TestCtx) -> void:
	var s := {
		"dirty": BigMoney.parse("12.5K"),
		"clean": BigMoney.parse("2K"),
		"laundered": BigMoney.parse("1K"),
		"guys_lost": 3,
		"night": 7,
		"rank": 2,
	}
	var line := Headlines.substitute(
			"{night}: {dirty} in, {laundered} washed, {clean} clean, {guys_lost} lost, {rank_title}", s)
	t.eq(line, "7: $12.5K in, $1.00K washed, $2.00K clean, 3 lost, NUMBERS RUNNER",
			"every placeholder is filled")
	t.eq(Headlines.substitute("{dirty}", {}), "$0", "a missing amount reads as zero")


func _ranks(t: TestCtx) -> void:
	t.eq(Headlines.rank_title(0), "LOOKOUT", "R0")
	t.eq(Headlines.rank_title(3), "SOLDIER", "R3 is the M1 ceiling")
	t.eq(Headlines.rank_title(7), "KINGPIN", "R7")
	t.eq(Headlines.rank_title(99), "KINGPIN", "out of range clamps")
	t.eq(Headlines.RANK_TITLES.size(), Game.RANK_RESPECT.size(),
			"one title per rank threshold")
