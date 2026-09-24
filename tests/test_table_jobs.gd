extends RefCounted
## THE WIRE'S JOBS (docs/19 §4): three lines a Night, picked up at a payphone, taken at
## Lucky's, made against the fuse; three done light the Big Score. The rules are pure logic
## on a fed clock, so they are walked shot by shot here, and then the money half runs against
## the real `Game`.

const SAVE_PATH := "user://test_table_jobs.json"
const ALL_SHOTS: Array[StringName] = [&"alley", &"dropoff", &"wire", &"spinner", &"getaway",
		&"luckys", &"beat_cop", &"nonnas", &"fat_tonys", &"truck_route", &"staircase"]


func run(t: TestCtx) -> void:
	_deal(t)
	_a_job(t)
	_lucky_takes_the_next_job(t)
	_taking_is_not_a_shot(t)
	_the_fuse(t)
	_big_score(t)
	_the_take(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_money(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


## Three small Jobs on a known board, so the rules can be walked shot by shot.
func _board(jobs: TableJobs, shots: Array[StringName] = ALL_SHOTS) -> TableJobs:
	jobs.catalogue.clear()
	jobs.catalogue.append({"id": "cans", "name": "Cans", "shots": {"alley": 2}, "fuse": 30})
	jobs.catalogue.append({"id": "call", "name": "Call", "shots": {"wire": 1}, "fuse": 30})
	jobs.catalogue.append({"id": "lap", "name": "Lap", "shots": {"getaway": 1}, "fuse": 30})
	jobs.begin_night(0, shots, _rng(1))
	return jobs


func _line_of(jobs: TableJobs, id: String) -> int:
	for i in range(jobs.lines.size()):
		if String(jobs.line_job(i).get("id", "")) == id:
			return i
	return -1


func _make(jobs: TableJobs, id: String, shot: StringName, times: int) -> void:
	jobs.select(_line_of(jobs, id))
	jobs.on_lucky()
	for i in range(times):
		jobs.on_shot(shot)


# --- the deal -----------------------------------------------------------------


func _deal(t: TestCtx) -> void:
	var jobs := TableJobs.new()
	t.ok(jobs.catalogue.size() >= TableJobs.LINES, "the catalogue holds a Night's worth of Jobs")
	var no_wire: Array[StringName] = [&"alley", &"luckys", &"dropoff"]
	jobs.begin_night(0, no_wire, _rng(3))
	t.ok(not jobs.live(), "no payphones on the table, no Jobs")

	# an early table: every Job dealt must be makeable on it, and none above the rank
	var early: Array[StringName] = [&"alley", &"dropoff", &"wire", &"luckys"]
	var full_deals := true
	var makeable := true
	for seed_value in range(24):
		jobs.begin_night(0, early, _rng(seed_value))
		full_deals = full_deals and jobs.lines.size() == TableJobs.LINES
		for i in range(jobs.lines.size()):
			makeable = makeable and TableJobs.eligible(jobs.line_job(i), 0, early)
	t.ok(full_deals, "an early table still deals three lines")
	t.ok(makeable, "every dealt Job asks only for shots the table has, at the player's rank")

	var gated := false
	for seed_value in range(40):
		jobs.begin_night(0, ALL_SHOTS, _rng(seed_value))
		for i in range(jobs.lines.size()):
			gated = gated or int(jobs.line_job(i).get("min_rank", 0)) > 0
	t.ok(not gated, "the rank-gated Jobs stay off a rookie's board")


# --- one Job ------------------------------------------------------------------


## The visit to Lucky's that takes a Job is the taking; it is not also the Job's first wash.
func _taking_is_not_a_shot(t: TestCtx) -> void:
	var jobs := TableJobs.new()
	jobs.catalogue.clear()
	jobs.catalogue.append({"id": "wash", "name": "Wash", "shots": {"luckys": 2}, "fuse": 30})
	var shots: Array[StringName] = [&"wire", &"luckys"]
	jobs.begin_night(0, shots, _rng(2))
	var done: Array = []
	jobs.job_done.connect(func(_line: int, job: Dictionary) -> void: done.append(job["id"]))
	jobs.select(0)
	jobs.on_lucky()
	t.ok(not jobs.on_shot(&"luckys"), "the ball that took the Job does not count toward it")
	jobs.on_shot(&"luckys")
	t.eq(done.size(), 0, "one wash of two is not done")
	jobs.on_shot(&"luckys")
	t.eq(done, ["wash"], "two real washes are")


func _a_job(t: TestCtx) -> void:
	var jobs := _board(TableJobs.new())
	var cans := _line_of(jobs, "cans")
	t.ok(jobs.select(cans), "a payphone picks the line up")
	t.ok(not jobs.on_shot(&"alley"), "a picked-up Job does not count until it is taken")
	t.eq(jobs.on_lucky(), &"job", "Lucky's takes it")
	t.eq(jobs.running, cans, "the one the payphone rang")
	t.near(jobs.fuse_left, 30.0, 1e-9, "and the fuse lights full")
	t.ok(not jobs.select(_line_of(jobs, "call")), "one Job at a time")
	t.ok(not jobs.on_shot(&"wire"), "a shot the Job did not ask for does not count")

	var done: Array = []
	jobs.job_done.connect(func(_line: int, job: Dictionary) -> void: done.append(job["id"]))
	t.ok(jobs.on_shot(&"alley"), "the first can counts")
	t.eq(done.size(), 0, "one of two is not done")
	jobs.on_shot(&"alley")
	jobs.on_shot(&"alley")
	t.eq(done, ["cans"], "two of two is, and the Job pays once")
	t.eq(jobs.line_state(cans), TableJobs.LineState.DONE, "its line is marked")
	t.ok(not jobs.select(cans), "a done line cannot be picked up again")


## The payphones choose; they are not a gate (docs/20 §4). With no line rung, Lucky's gives
## the next open one, never a done one, and nothing once the board is cleared.
func _lucky_takes_the_next_job(t: TestCtx) -> void:
	var jobs := _board(TableJobs.new())
	t.ok(jobs.headline().begins_with("SHOOT LUCKY'S FOR A JOB"), "the HUD says where a Job comes from")
	var expected := jobs.next_open_line(-1)
	t.eq(jobs.on_lucky(), &"job", "Lucky's gives a Job without a payphone")
	var first := jobs.running
	t.eq(first, expected, "the next open line")
	for shot: Variant in (jobs.line_job(first)["shots"] as Dictionary).keys():
		for i in range(int(jobs.line_job(first)["shots"][shot]) + 1):
			jobs.on_shot(StringName(shot))
	t.eq(jobs.line_state(first), TableJobs.LineState.DONE, "that Job is made")
	t.eq(jobs.on_lucky(), &"job", "Lucky's gives the next one")
	t.ok(jobs.running != first, "…which is not the done one")
	jobs.running = -1
	for i in range(jobs.lines.size()):
		jobs.lines[i]["state"] = TableJobs.LineState.DONE
	jobs.selected = -1
	t.eq(jobs.on_lucky(), &"", "a cleared board has nothing left to give")


func _the_fuse(t: TestCtx) -> void:
	var jobs := _board(TableJobs.new())
	var lap := _line_of(jobs, "lap")
	jobs.select(lap)
	jobs.on_lucky()
	var blown: Array = []
	jobs.job_blown.connect(func(line: int, _job: Dictionary) -> void: blown.append(line))

	jobs.tick(25.0)
	jobs.on_shot(&"spinner")
	t.near(jobs.fuse_left, 5.0 + TableJobs.FUSE_SPIN_SECONDS, 1e-6, "a spinner tick buys fuse")
	for i in range(400):
		jobs.on_shot(&"spinner")
	t.near(jobs.fuse_left, 5.0 + TableJobs.FUSE_SPIN_MAX, 1e-6, "but only so much of it")
	t.ok(blown.is_empty(), "a Job is live while its fuse burns")

	jobs.tick(jobs.fuse_left + 0.01)
	t.eq(blown, [lap], "a burnt-out fuse blows the Job")
	t.eq(jobs.running, -1, "nothing is running after it")
	t.eq(jobs.line_state(lap), TableJobs.LineState.OFFERED, "the line goes back on the board")
	t.ok(jobs.select(lap), "so it can be picked up again")
	t.eq(jobs.on_lucky(), &"job", "and retaken")
	t.ok(jobs.on_shot(&"getaway"), "and made")
	t.eq(jobs.line_state(lap), TableJobs.LineState.DONE, "on the second try")

	var slow := _board(TableJobs.new())
	slow.fuse_scale = TableJobs.SLOW_BURN_SCALE
	slow.select(_line_of(slow, "lap"))
	slow.on_lucky()
	t.ok(slow.fuse_left > 30.0, "Slow Burn lights a longer fuse")

	# the spinner can only buy back burnt fuse: spun at a full fuse it saves its budget
	var full := _board(TableJobs.new())
	full.select(_line_of(full, "lap"))
	full.on_lucky()
	for i in range(100):
		full.on_shot(&"spinner")
	full.tick(25.0)
	for i in range(400):
		full.on_shot(&"spinner")
	t.near(full.fuse_left, 5.0 + TableJobs.FUSE_SPIN_MAX, 1e-6, "spinning at a full fuse wastes none of it")


# --- the Big Score --------------------------------------------------------------


func _big_score(t: TestCtx) -> void:
	# a table without the Club or the Docks: the Big Score may only light what stands
	var shots: Array[StringName] = [&"alley", &"wire", &"luckys", &"getaway", &"spinner"]
	var jobs := _board(TableJobs.new(), shots)
	var ready := [0]
	jobs.big_score_ready.connect(func() -> void: ready[0] += 1)
	_make(jobs, "cans", &"alley", 2)
	_make(jobs, "call", &"wire", 1)
	t.ok(not jobs.big_score_lit, "two lines of three do not light it")
	_make(jobs, "lap", &"getaway", 1)
	t.eq(ready[0], 1, "the third line lights the Big Score, once")

	t.eq(jobs.on_lucky(), &"big_score", "Lucky's starts it")
	var on_table := not jobs.jackpots_left.is_empty()
	for shot in jobs.jackpots_left:
		on_table = on_table and shots.has(shot)
	t.ok(on_table, "every lit jackpot is a shot this table has")
	t.eq(jobs.on_lucky(), &"", "the vault stays shut until the jackpots are in")

	var lit := jobs.jackpots_left.duplicate()
	for shot in lit:
		jobs.on_shot(shot)
	t.ok(jobs.vault_lit, "all of them in opens the vault")
	t.ok(not jobs.on_shot(lit[0]), "a collected jackpot does not pay twice")
	t.eq(jobs.on_lucky(), &"vault", "Lucky's pays the vault")
	t.eq(jobs.jackpots_left.size(), lit.size(), "and the jackpots relight for another round")

	jobs.end_big_score()
	t.ok(not jobs.big_score_active and jobs.jackpots_left.is_empty(), "back to one ball, it ends")
	t.eq(jobs.on_lucky(), &"", "and does not relight: the Night's lines stay done")
	t.ok(not jobs.arrow_states().has(&"wire"), "and the Wire stops asking for a payphone")


func _the_take(t: TestCtx) -> void:
	var jobs := _board(TableJobs.new())
	t.near(jobs.take_multiplier(), 1.0, 1e-9, "the Take starts at ×1")
	jobs.advance_take()
	var one_step := jobs.take_multiplier()
	t.ok(one_step > 1.0, "a cash-out raises it")
	for i in range(TableJobs.TAKE_STEPS.size() * 2):
		jobs.advance_take()
	var top := jobs.take_multiplier()
	jobs.advance_take()
	t.near(jobs.take_multiplier(), top, 1e-9, "it tops out")
	jobs.reset_take()
	t.near(jobs.take_multiplier(), 1.0, 1e-9, "and a lost ball puts it back to ×1")


# --- the money ----------------------------------------------------------------


func _money(t: TestCtx) -> void:
	Game.new_game(11)
	Game.start_night()
	var job := {"id": "test_job", "name": "Test Job", "minutes": 3.0, "respect": 4}
	var quote := Game.table_job_value(job)
	t.ok(quote.is_positive(), "a Job is worth something even on a fresh career")

	var dirty_before := Game.wallet.dirty
	var respect_before := Game.respect
	var paid := Game.table_job_done(job)
	t.ok(paid.equals_approx(quote, 1e-9), "a Job pays what it was quoted")
	t.ok(Game.wallet.dirty.equals_approx(dirty_before.add(paid), 1e-9), "in dirty cash")
	t.ok(Game.respect > respect_before, "and it earns respect")

	Game.table_jobs.advance_take()
	var taken := Game.table_job_value(job)
	t.ok(taken.equals_approx(quote.mul(Game.table_jobs.take_multiplier()), 1e-9),
			"the Take multiplies the pay")
	Game.table_jobs.reset_take()

	var jackpot := Game.big_score_jackpot(false)
	var vault := Game.big_score_jackpot(true)
	t.ok(jackpot.is_positive(), "a Big Score jackpot pays")
	t.ok(vault.cmp(jackpot) > 0, "and the vault pays more than one jackpot")

	var rookie := Game.table_job_value(job)
	Game.rank = 5
	t.ok(Game.table_job_value(job).cmp(rookie) > 0, "the same Job pays more further up the ladder")
	Game.rank = 0


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(12)
	var jobs := _board(Game.table_jobs)
	_make(jobs, "cans", &"alley", 2)
	_make(jobs, "call", &"wire", 1)
	_make(jobs, "lap", &"getaway", 1)
	jobs.on_lucky()
	t.eq(jobs.jobs_done_total, 3, "three Jobs on the career's book")
	t.ok(Game.save_now(), "the career writes")

	Game.new_game(0)
	t.eq(Game.table_jobs.jobs_done_total, 0, "a new career starts with a clean book")
	Game.from_dict(Game.save.read())
	t.eq(Game.table_jobs.jobs_done_total, 3, "Jobs done survive the save")
	t.eq(Game.table_jobs.big_scores_total, 1, "and so does the Big Score")
