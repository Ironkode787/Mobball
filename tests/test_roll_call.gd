extends RefCounted
## Roll Call state and ordered lineup contract. UI rendering is intentionally left to the
## scene host; these checks exercise the model boundary the screen calls.


func run(t: TestCtx) -> void:
	Game.new_game(20260823)
	Game.open_roll_call()
	t.eq(Game.state, &"roll_call", "attract opens the pre-Night Roll Call state")
	t.eq(Game.night_no, 1, "Roll Call prepares exactly one Night")
	t.ok(not Game.jobs.active_jobs().is_empty(), "Tonight's Work is rolled before the screen")

	var free := Game.bench.available()
	var chosen: Array[Dictionary] = []
	chosen.append(free[2])
	chosen.append(free[0])
	chosen.append(free[1])
	Game.start_prepared_night(chosen)
	t.eq(Game.state, &"night", "Start advances Roll Call into the Night")
	t.eq(int(Game.prepared_lineup[0]["id"]), int(free[2]["id"]), "first selection is first serve")
	t.eq(int(Game.prepared_lineup[1]["id"]), int(free[0]["id"]), "second selection is second serve")
	t.eq(int(Game.prepared_lineup[2]["id"]), int(free[1]["id"]), "third selection is third serve")
	Game.end_night({})
	t.eq(Game.prepared_lineup.size(), 0, "ending a Night clears the hand-off lineup")

	Game.new_game(20260824)
	Game.start_night()
	t.eq(Game.state, &"night", "direct callers still start immediately")
	var defaults := Game.bench.available()
	for i in 3:
		t.eq(int(Game.prepared_lineup[i]["id"]), int(defaults[i]["id"]),
				"direct Night start defaults to the first three")
	Game.end_night({})

	Game.new_game(20260825)
	Game.open_roll_call()
	var held := Game.bench.available()[3]
	Game.bench.pinch(held)
	var malformed: Array[Dictionary] = [Game.bench.available()[0], Game.bench.available()[0], held]
	Game.start_prepared_night(malformed)
	t.eq(Game.prepared_lineup.size(), 3, "invalid selection is filled to the available crew")
	t.eq(int(Game.prepared_lineup[0]["id"]), int(malformed[0]["id"]),
			"the first valid selection remains first")
	t.ok(Game.prepared_lineup[1]["id"] != malformed[0]["id"], "duplicate selection is removed")
	t.ok(Game.prepared_lineup[2]["id"] != held["id"], "held selection is removed")
	Game.end_night({})

	t.eq(RollCallScreen.scope_for_check("bumper_burst"), "ANY GUY", "any-guy job scope")
	t.eq(RollCallScreen.scope_for_check("switch_count_one_ball"), "ONE GUY", "one-guy job scope")
	t.eq(RollCallScreen.scope_for_check("ball_survival"), "FIRST GUY", "first-guy job scope")
	t.eq(RollCallScreen.scope_for_check("earn_under_heat"), "ALL NIGHT", "all-night job scope")
