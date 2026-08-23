extends RefCounted
## HEISTS (docs/05 §5): the board and the casing clock, the approach, the inside man, and the
## fail-forward checklist. The run is pure logic on a fed clock, so the whole sequence can be
## walked here with no table under it.

const SAVE_PATH := "user://test_flow_heists.json"


func run(t: TestCtx) -> void:
	_board(t)
	_casing(t)
	_checklist(t)
	_fail_forward(t)
	_approach_and_inside_man(t)
	_gentleness(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_planning(t)
	_the_take(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the board ----------------------------------------------------------------


func _board(t: TestCtx) -> void:
	var shipped := 0
	for row in Heists.TARGETS:
		if bool(row.get("shipped", false)):
			shipped += 1
			t.ok(not (row["beats"] as Array).is_empty(),
					"%s ships with a sequence" % row["id"])
			for b: Variant in row["beats"]:
				var beat: Dictionary = b
				t.ok(int(beat.get("count", 0)) > 0 and float(beat.get("seconds", 0.0)) > 0.0,
						"%s: every beat is a real ask on a real clock" % row["id"])
	t.eq(shipped, 3, "three of the five targets ship in M3")

	var book := Heists.new()
	var board := book.board(1)
	t.eq(board.size(), Heists.TARGETS.size(), "the board shows all five jobs")
	for row in board:
		if not bool(row["shipped"]):
			t.ok(not bool(row["available"]), "%s cannot be run yet" % row["name"])

	t.ok(HeistRun.make(Heists.TRAIN, Heists.QUIET, {}) == null,
			"a target with no sequence makes no run")
	t.ok(HeistRun.make(&"the_moon", Heists.QUIET, {}) == null,
			"and neither does one that does not exist")


func _casing(t: TestCtx) -> void:
	var book := Heists.new()
	t.ok(book.is_available(Heists.PAYROLL, 1), "a fresh board is open")
	book.begin(Heists.PAYROLL, 4)
	t.ok(not book.is_available(Heists.PAYROLL, 4), "you cannot hit the same truck twice")
	t.eq(book.casing_left(Heists.PAYROLL, 4), Heists.CASING_NIGHTS, "five Nights of casing")
	t.ok(book.is_available(Heists.MUSEUM, 4), "the other jobs are unaffected")
	t.ok(not book.is_available(Heists.PAYROLL, 4 + Heists.CASING_NIGHTS - 1),
			"four Nights is not five")
	t.ok(book.is_available(Heists.PAYROLL, 4 + Heists.CASING_NIGHTS),
			"and then it is back on the board")
	t.eq(book.attempted, 1, "the attempt is on the book")


# --- the sequence -------------------------------------------------------------


func _checklist(t: TestCtx) -> void:
	var run := HeistRun.make(Heists.PAYROLL, Heists.LOUD, {})
	t.ok(run != null, "the truck is a job")
	run.begin()
	t.ok(run.active, "and the crew is out")
	t.eq(run.beat_index, 0, "on the first beat")

	var first: Dictionary = run.beats()[0]
	t.eq(run.on_switch(&"spinner"), HeistRun.HIT_NONE, "the wrong shot is not the beat")
	t.eq(run.beat_hits, 0, "and does not count")
	for i in int(first["count"]) - 1:
		t.eq(run.on_switch(StringName(first["group"])), HeistRun.HIT_OK, "the right shot counts")
		t.eq(run.beat_index, 0, "the beat is not done yet")
	t.eq(run.on_switch(StringName(first["group"])), HeistRun.HIT_OK, "the last hit")
	t.eq(run.beat_index, 1, "moves the checklist on")
	t.eq(run.beat_hits, 0, "with a fresh count")
	t.eq(run.blown, 0, "and nothing blown")

	# Walk the rest of it clean.
	while run.active:
		var b := run.beat()
		run.on_switch(StringName(b["group"]))
	t.ok(run.cleared, "a clean sequence is a cleared job")
	t.near(run.take_share(), 1.0, 1e-9, "and pays the whole take")
	t.eq(run.on_switch(&"bumpers"), HeistRun.HIT_NONE, "a finished job takes no more shots")


func _fail_forward(t: TestCtx) -> void:
	# "missing a beat degrades the take, only a drain ends it" (docs/05 §5).
	var run := HeistRun.make(Heists.PAYROLL, Heists.LOUD, {})
	run.begin()
	t.ok(run.tick(run.window_for(0) + 0.01), "the first beat's window runs out")
	t.ok(run.active, "and the job goes on anyway")
	t.eq(run.beat_index, 1, "onto the next beat")
	t.eq(run.blown, 1, "one blown")
	t.near(run.take_share(), 1.0 - Heists.DEGRADE_PER_MISS, 1e-9, "for a worse payday")

	while run.active:
		run.tick(run.window_for(run.beat_index) + 0.01)
	t.ok(run.cleared, "a job where everything was blown still comes home")
	t.ok(run.take_share() >= Heists.MIN_SHARE - 1e-9,
			"with a floor under it — a setback stings, it does not erase (P5)")

	# A drain is the end of it, and it pays pro-rata on the beats that were closed.
	var drained := HeistRun.make(Heists.PAYROLL, Heists.LOUD, {})
	drained.begin()
	var b: Dictionary = drained.beats()[0]
	for i in int(b["count"]):
		drained.on_switch(StringName(b["group"]))
	t.eq(drained.beat_index, 1, "one beat done")
	t.ok(drained.on_ball_lost(), "the ball goes down and the job is over")
	t.ok(not drained.active and not drained.cleared, "not cleared")
	t.ok(drained.take_share() > 0.0, "but the crew still got out with something")
	t.ok(drained.take_share() < 1.0, "for less than the whole take")


func _approach_and_inside_man(t: TestCtx) -> void:
	var quiet := HeistRun.make(Heists.MUSEUM, Heists.QUIET, {})
	var loud := HeistRun.make(Heists.MUSEUM, Heists.LOUD, {})
	t.ok(quiet.window_for(0) < loud.window_for(0), "quiet means tighter windows")
	t.near(quiet.heat_cost(), 0.0, 1e-9, "and nobody hears a thing")
	t.near(loud.heat_cost(), float(Heists.APPROACHES[Heists.LOUD]["heat"]), 1e-9,
			"loud costs a flat +25 on the meter")

	var fast := HeistRun.make(Heists.MUSEUM, Heists.QUIET, {"trait": GuyTraits.FAST})
	t.ok(fast.window_for(0) > quiet.window_for(0), "the wheelman knows the timings")

	# Careful covers the first mistake; the take is what shows it.
	var careful := HeistRun.make(Heists.MUSEUM, Heists.QUIET, {"trait": GuyTraits.CAREFUL})
	careful.begin()
	careful.tick(careful.window_for(0) + 0.01)
	t.eq(careful.blown, 1, "a beat was still blown")
	t.near(careful.take_share(), 1.0, 1e-9, "but it did not cost anything")

	# Slippery gets out either way: one drain does not end the job.
	var slippery := HeistRun.make(Heists.MUSEUM, Heists.QUIET, {"trait": GuyTraits.SLIPPERY})
	slippery.begin()
	t.ok(not slippery.on_ball_lost(), "the first drain is survived")
	t.ok(slippery.active, "the job goes on")
	t.ok(slippery.on_ball_lost(), "the second is not")
	t.ok(not slippery.active, "and that is the job")

	# Loud on the crew takes more and makes noise.
	var shouty := HeistRun.make(Heists.MUSEUM, Heists.QUIET, {"trait": GuyTraits.LOUD})
	shouty.begin()
	t.ok(shouty.take_share() > 1.0, "he takes more")
	t.ok(shouty.heat_cost() > 0.0, "and a quiet job stops being quiet")


func _gentleness(t: TestCtx) -> void:
	# The Vault's walk-out is the one beat in the game that wants a SOFT hit.
	var run := HeistRun.make(Heists.VAULT, Heists.LOUD, {})
	run.begin()
	while run.beat_index < 2 and run.active:
		var b := run.beat()
		for i in int(b["count"]):
			run.on_switch(StringName(b["group"]))
	t.eq(run.beat_index, 2, "at the front door")
	var walk := run.beat()
	t.ok(walk.has("max_strength"), "which is a gentleness check")
	t.eq(run.on_switch(StringName(walk["group"]), 1.0), HeistRun.HIT_GENTLE,
			"slamming it is the right shot played wrong")
	t.ok(run.active, "and it does not end the job")
	t.eq(run.beat_index, 2, "the beat stands")
	t.eq(run.on_switch(StringName(walk["group"]), 0.0), HeistRun.HIT_OK, "walk out slow")
	t.ok(run.cleared, "and you are gone")


# --- against the real session -------------------------------------------------


func _planning(t: TestCtx) -> void:
	Game.new_game(21)
	t.ok(not Game.heists_unlocked(), "no docks, no war room")
	t.ok(Game.plan_heist(Heists.PAYROLL, Heists.QUIET).is_empty(), "and nothing to plan")

	Game.owned["rackets.docks_concession"] = 1
	Game._recompute_stats()
	t.ok(Game.heists_unlocked(), "the Docks are the war room (docs/02 §2 R5)")

	# A job wants a stake up front, and an empty pocket cannot put one up.
	t.ok(Game.plan_heist(Heists.PAYROLL, Heists.QUIET).is_empty(), "no stake, no job")
	Game.wallet.earn_dirty(BigMoney.of(9.0, 9))

	var plan := Game.plan_heist(Heists.PAYROLL, Heists.LOUD, {"name": "Sal", "trait": "fast"})
	t.ok(not plan.is_empty(), "the job goes on the books")
	t.eq(String(plan["target"]), String(Heists.PAYROLL), "for the truck")
	t.ok(not Game.heists.pending.is_empty(), "and the next Night runs it")

	Game.start_night()
	# The plan is consumed by the Night that runs it (NightController._start_heist), not by
	# roll call — the same rule `Commission.pending` follows, so a Night that never opened
	# still owes you the job.
	t.ok(not Game.heists.pending.is_empty(), "the job is still owed at roll call")
	Game.heists.begin(Heists.PAYROLL, Game.night_no)
	t.ok(Game.heists.pending.is_empty(), "and the Night that opens on it takes it")

	# The Count cannot book a job in the middle of a Night.
	t.ok(Game.plan_heist(Heists.MUSEUM, Heists.QUIET).is_empty(),
			"the war room is shut while the table is live")


func _the_take(t: TestCtx) -> void:
	Game.new_game(22)
	Game.owned["rackets.docks_concession"] = 1
	Game._recompute_stats()
	Game.start_night()

	var run := HeistRun.make(Heists.VAULT, Heists.QUIET, {})
	run.begin()
	Game.heist = run
	while run.active:
		var b := run.beat()
		for i in int(b["count"]):
			run.on_switch(StringName(b["group"]), 0.0)

	var clean_before := Game.wallet.clean
	var stars := Game.respect
	var result := Game.heist_finished(run)
	t.ok(bool(result["cleared"]), "the vault is cleared")
	t.ok((result["paid"] as BigMoney).is_positive(), "and it pays")
	t.ok(Game.wallet.clean.equals_approx(clean_before.add(result["paid"]), 1e-9),
			"in CLEAN — a heist is the one racket whose money never has to be washed")
	t.ok(not (result["paid"] as BigMoney).equals(Game.night_laundered),
			"and it is not laundering: nothing moved out of the dirty pile")
	t.eq(Game.respect, stars + Heists.RESPECT_CLEARED, "a cleared job is worth ☆")
	t.eq(int(Game.career.get("heists_cleared", 0)), 1, "and it counts toward the Juice")
	t.eq(Game.heists.cleared, 1, "the book agrees")
	t.ok(Game.heist == null, "the crew has gone home")

	# The Museum is the one that comes back with something for the gallery.
	var museum := HeistRun.make(Heists.MUSEUM, Heists.QUIET, {})
	museum.begin()
	while museum.active:
		var b := museum.beat()
		for i in int(b["count"]):
			museum.on_switch(StringName(b["group"]), 0.0)
	var relic := Game.heist_finished(museum)
	t.ok(not String(relic["relic"]).is_empty(), "a relic comes off the wall")
	t.ok(Game.heists.relics.has(String(relic["relic"])), "and into the collection")


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(23)
	Game.owned["rackets.docks_concession"] = 1
	Game._recompute_stats()
	Game.night_no = 6
	Game.heists.begin(Heists.MUSEUM, 6)
	Game.heists.book({"cleared": true, "blown": 2, "paid": BigMoney.of(3.0, 7),
			"relic": "relic.museum"})
	Game.career["raids_survived"] = 3
	t.ok(Game.save_now(), "the career writes")

	Game.new_game(0)
	Game.from_dict(Game.save.read())
	t.eq(Game.heists.cleared, 1, "cleared jobs survive the save")
	t.eq(Game.heists.blown_beats, 2, "so do the beats that got away")
	t.eq(Game.heists.casing_left(Heists.MUSEUM, 6), Heists.CASING_NIGHTS,
			"and the casing clock is still running")
	t.ok(Game.heists.relics.has("relic.museum"), "the relic is still on the shelf")
	t.eq(int(Game.career.get("raids_survived", 0)), 3, "and the rap sheet is intact")
	t.ok(Game.heists.pending.is_empty(), "a plan does not survive a reload")
