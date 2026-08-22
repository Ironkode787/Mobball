extends RefCounted
## Tonight's Work (game/flow/jobs.gd): the data loads, the slips are eligible, and every
## `check` id in game/content/jobs.json actually completes.


func run(t: TestCtx) -> void:
	_pool(t)
	_eligibility(t)
	_rolling(t)
	_bumper_burst(t)
	_earn_under_heat(t)
	_launder_total(t)
	_switch_cover(t)
	_one_ball_checks(t)
	_bank_and_bribe(t)
	_serialization(t)


func _stats(owned: Dictionary) -> Stats:
	var s := Stats.new()
	s.recompute(owned)
	return s


## Force one slip onto the board, whatever the data pool says.
func _only(id: String) -> Jobs:
	var j := Jobs.new()
	j.active = [{"id": id, "done": false, "state": Jobs._fresh_state(j.job(id))}]
	j.begin_night()
	j.begin_ball(0)
	return j


func _completions(j: Jobs) -> Array[String]:
	var out: Array[String] = []
	j.completed.connect(func(job: Dictionary, _r: int) -> void: out.append(String(job["id"])))
	return out


func _pool(t: TestCtx) -> void:
	var j := Jobs.new()
	t.ok(j.loaded(), "jobs.json loaded")
	t.eq(j.pool.size(), 10, "the M1 pool is ten slips")
	for id: Variant in j.pool:
		var job: Dictionary = j.pool[id]
		t.ok(int(job.get("respect", 0)) > 0, "%s pays Respect" % id)
		t.ok(not String(job.get("check", "")).is_empty(), "%s names a check" % id)


func _eligibility(t: TestCtx) -> void:
	var j := Jobs.new()
	var bare := _stats({})
	var eligible := 0
	for id: Variant in j.pool:
		if Jobs.eligible(j.pool[id], 0, bare):
			eligible += 1
	t.eq(eligible, 1, "at R0 with nothing bought, exactly one slip is playable")
	t.ok(Jobs.eligible(j.job("send_a_message"), 0, bare), "and it is Send a Message")
	t.ok(not Jobs.eligible(j.job("milk_run"), 1, bare), "hardware gates hold at the right rank")
	t.ok(Jobs.eligible(j.job("milk_run"), 1, _stats({"rackets.numbers_game": 1})),
			"buying the spinner opens the Milk Run")
	t.ok(not Jobs.eligible(j.job("milk_run"), 0, _stats({"rackets.numbers_game": 1})),
			"rank still gates it")


func _rolling(t: TestCtx) -> void:
	var owned := {"rackets.numbers_game": 1, "fronts.coin_op": 1, "muscle.chalk_lines": 1}
	var stats := _stats(owned)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var j := Jobs.new()
	var rolled := j.roll(1, stats, 2, rng)
	t.eq(rolled.size(), 2, "two slots, two slips")

	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 5
	var j2 := Jobs.new()
	var rolled2 := j2.roll(1, stats, 2, rng2)
	t.eq(String(rolled2[0]["id"]), String(rolled[0]["id"]), "the draw is seeded")

	# A finished slip is replaced next Night; an unfinished one stays on the board.
	var keep := String(j.active[0]["id"])
	j._finish(j.active[1])
	j.roll(1, stats, 2, rng)
	t.eq(String(j.active[0]["id"]), keep, "the unfinished slip stays pinned")
	t.ok(not j.active[1]["done"], "the finished one was replaced")
	t.ok(j.is_done(String(rolled[1]["id"])), "and it never comes back around")


func _bumper_burst(t: TestCtx) -> void:
	var j := _only("send_a_message")
	var done := _completions(j)
	for i in 5:
		j.on_switch(&"bumper_1", &"bumpers")
	t.eq(done.size(), 0, "five cans is not six")
	j.on_switch(&"bumper_2", &"bumpers")
	t.eq(done, ["send_a_message"], "six inside the window sends the message")

	var slow := _only("send_a_message")
	var slow_done := _completions(slow)
	for i in 10:
		slow.on_switch(&"bumper_1", &"bumpers")
		slow.tick(1.5, 0.0)
	t.eq(slow_done.size(), 0, "six cans spread past the window is not a burst")


func _earn_under_heat(t: TestCtx) -> void:
	var j := _only("keep_it_quiet")
	var done := _completions(j)
	j.on_earn(BigMoney.parse("1.5K"), &"bumpers")
	t.eq(done.size(), 0, "not banked yet")
	j.on_earn(BigMoney.parse("600"), &"bumpers")
	t.eq(done, ["keep_it_quiet"], "quiet money pays out")

	var loud := _only("keep_it_quiet")
	var loud_done := _completions(loud)
	loud.tick(0.1, 55.0)
	loud.on_earn(BigMoney.parse("5K"), &"bumpers")
	t.eq(loud_done.size(), 0, "passing Heat 40 blows the job for the Night")


func _launder_total(t: TestCtx) -> void:
	var j := _only("clean_hands")
	var done := _completions(j)
	j.on_launder(BigMoney.parse("400"))
	j.on_launder(BigMoney.parse("400"))
	t.eq(done.size(), 0, "$800 washed is not $1K")
	j.on_launder(BigMoney.parse("250"))
	t.eq(done, ["clean_hands"], "$1.05K washed clears it")


func _switch_cover(t: TestCtx) -> void:
	var j := _only("no_loose_ends")
	var done := _completions(j)
	j.on_switch(&"rollover_1", &"rollovers")
	j.on_switch(&"rollover_1", &"rollovers")
	j.on_switch(&"rollover_2", &"rollovers")
	t.eq(done.size(), 0, "the same lane twice is one lane")
	j.on_switch(&"rollover_3", &"rollovers")
	t.eq(done, ["no_loose_ends"], "all three lanes rung")


func _one_ball_checks(t: TestCtx) -> void:
	var spins := _only("milk_run")
	var spins_done := _completions(spins)
	spins.on_switch(&"spinner_numbers", &"spinner")
	spins.on_switch(&"spinner_numbers", &"spinner")
	spins.begin_ball(1)
	spins.on_switch(&"spinner_numbers", &"spinner")
	t.eq(spins_done.size(), 0, "a new guy starts the count again")
	spins.on_switch(&"spinner_numbers", &"spinner")
	spins.on_switch(&"spinner_numbers", &"spinner")
	t.eq(spins_done, ["milk_run"], "three passes with one guy")

	var alive := _only("old_debts")
	var alive_done := _completions(alive)
	alive.tick(179.0, 0.0)
	t.eq(alive_done.size(), 0, "179 seconds is not three minutes")
	alive.tick(1.5, 0.0)
	t.eq(alive_done, ["old_debts"], "the first guy went the distance")

	var not_first := _only("old_debts")
	var not_first_done := _completions(not_first)
	not_first.begin_ball(1)
	not_first.tick(400.0, 0.0)
	t.eq(not_first_done.size(), 0, "Old Debts is about the FIRST guy")

	var shops := _only("shake_the_block")
	var shops_done := _completions(shops)
	shops.on_storefront(&"storefront_laundromat")
	shops.on_storefront(&"storefront_pizzeria")
	shops.begin_ball(1)
	shops.on_storefront(&"storefront_pawn")
	t.eq(shops_done.size(), 0, "the collections have to be one guy's work")
	shops.on_storefront(&"storefront_laundromat")
	shops.on_storefront(&"storefront_pizzeria")
	t.eq(shops_done, ["shake_the_block"], "all three shops in one run")


func _bank_and_bribe(t: TestCtx) -> void:
	var bank := _only("place_your_bets")
	var bank_done := _completions(bank)
	bank.on_switch(&"wire_bank_1", &"wire")
	bank.on_switch(&"wire_bank_complete", &"wire")
	t.eq(bank_done.size(), 0, "one bank down is not two")
	bank.on_switch(&"wire_bank_complete", &"wire")
	t.eq(bank_done, ["place_your_bets"], "both payphone banks")

	var cool := _only("cool_head")
	var cool_done := _completions(cool)
	cool.on_bribe(40.0)
	t.eq(cool_done.size(), 0, "a bribe at Heat 40 is not a cool head")
	cool.on_bribe(85.0)
	t.eq(cool_done, ["cool_head"], "bribing while hot is")


func _serialization(t: TestCtx) -> void:
	var j := _only("send_a_message")
	j.on_switch(&"bumper_1", &"bumpers")
	j.on_earn(BigMoney.parse("500"), &"bumpers")
	var dict := j.to_dict()
	var through: Variant = JSON.parse_string(JSON.stringify(dict))
	var loaded := Jobs.new()
	loaded.from_dict(through)
	t.eq(JSON.stringify(loaded.to_dict()), JSON.stringify(dict), "job progress round-trips")
	loaded.from_dict({"active": [{"id": "no_such_job"}], "done": ["gone"]})
	t.eq(loaded.active.size(), 0, "a slip that is no longer in the data file is dropped")
	t.ok(loaded.is_done("gone"), "the completed list still loads")
