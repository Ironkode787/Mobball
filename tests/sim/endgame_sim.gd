extends Node2D
## FLOW acceptance runner for the ENDGAME (specs/m3-fall-rise.md FLOW-3).
##
## The club flow sim proved the M2 modes are wired to the real table and the real money path.
## This one does the same for everything M3 hangs off the Docks, the Penthouse and the dome:
## that a smuggling run arms on the yard's own signal and ships on the union of three stacks,
## that the Sit-Down really stops the meter, that a Penthouse chair stays claimed across
## Nights, that a heist's checklist advances on ordinary switch traffic and fails forward,
## that the City Hall Circuit lights EMPIRE, that a RICO Night pays or confiscates, and that
## Skip Town ends a career and starts a city.
##
## House rules as everywhere else: the real `main.tscn` with the real table under it, physics
## ticks rather than wall time, the save file redirected somewhere harmless, and a non-zero
## exit code on any failure. The table is driven through its OWN signals — the same surface
## `game/flow/night.gd` binds to — because what is under test is the flow lane's reaction,
## not the yard's geometry (that is tests/sim/docks_sim).

const MAIN_SCENE := preload("res://game/main.tscn")
const SIM_SAVE := "user://sim_endgame_save.json"
const SEED := 0x454E4447

## A Kingpin's table: the block, the Club, the Docks and the Penthouse.
const FIXTURE: PackedStringArray = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "rackets.numbers_game",
	"fronts.coin_op", "rackets.the_wire", "rackets.protection_laundromat",
	"rackets.protection_pizzeria", "rackets.protection_pawn", "rackets.getaway_loop",
	"rackets.club_license", "muscle.second_set", "rackets.docks_concession",
	"rackets.truck_route", "rackets.the_penthouse",
]

const DRAIN_POINT := Vector2(490.0, 1876.0)
const SAFE_POINT := Vector2(430.0, 760.0)
## Two minutes of federal raid is two minutes of CI; the branch logic is what is under test.
const RICO_SECONDS := 6.0

var main: Main = null
var table: Node2D = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _parked: Dictionary = {}
var _smuggling: Array[Dictionary] = []
var _heists: Array[Dictionary] = []
var _empire: Array[Dictionary] = []


func _ready() -> void:
	main = MAIN_SCENE.instantiate()
	main.auto_start = false
	main.show_hud = true
	add_child(main)
	table = main.table

	SaveGame.new(SIM_SAVE).erase()
	main.start_session(SIM_SAVE)
	Game.new_game(SEED)

	Game.smuggling_changed.connect(func(s: Dictionary) -> void: _smuggling.append(s))
	Game.heist_changed.connect(func(s: Dictionary) -> void: _heists.append(s))
	Game.empire_changed.connect(func(s: Dictionary) -> void: _empire.append(s))
	_run()


# ---------------------------------------------------------------- harness

func ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(Engine.physics_ticks_per_second))))


func step(count: int = 1) -> void:
	for i in range(count):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	await step(ticks(seconds))


func begin(scenario: String) -> void:
	_current = scenario
	_fails = PackedStringArray()


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if _fails.is_empty() else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


func park(ball: Ball, at: Vector2) -> void:
	if ball != null and is_instance_valid(ball):
		_parked[ball.get_instance_id()] = {"ball": ball, "at": at}


func unpark(ball: Ball) -> void:
	if ball != null:
		_parked.erase(ball.get_instance_id())


func _physics_process(_delta: float) -> void:
	for key: Variant in _parked.keys():
		var row: Dictionary = _parked[key]
		# Held as a Variant on purpose: a Night torn down under a parked ball frees it, and
		# assigning a freed instance to a typed local is an error rather than a null.
		var b: Variant = row["ball"]
		if not is_instance_valid(b):
			_parked.erase(key)
			continue
		(b as Ball).place(row["at"])


func money(v: Variant) -> BigMoney:
	return v if v is BigMoney else BigMoney.zero()


## Close the Night and land on The Count — the only state the war room and the train can be
## worked from, exactly as a player would reach them.
func end_the_night() -> void:
	if Game.state != &"night":
		return
	_parked.clear()
	if main.night != null and is_instance_valid(main.night) and main.night.running:
		main.night.stop()
	Game.end_night({})
	await step(2)


## Open one with the ball held somewhere harmless, so a scenario owns its own clock.
func open_night() -> void:
	Game.start_night()
	await wait(0.4)
	park(TableAPI.ball(table), SAFE_POINT)
	await wait(0.2)


func fresh_night() -> void:
	await end_the_night()
	await open_night()


## Every switch the flow lane sees comes through here, so a scenario can play a shot without
## owning a ball trajectory (tests/sim/docks_sim owns the geometry).
func hit(id: StringName, strength: float = 0.0) -> void:
	Events.switch_hit.emit(id, TableAPI.ball(table), strength)
	await step(1)


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M3 endgame flow sim ==")
	print("physics %d Hz | seed 0x%X | save %s"
			% [Engine.physics_ticks_per_second, SEED, SIM_SAVE])
	await step(4)

	for id in FIXTURE:
		Game.buy_upgrade(id, BigMoney.zero())
	Game.rank = 7
	await fresh_night()

	await _s1_smuggling_run()
	await _s2_sitdown_freezes_the_meter()
	await _s3_chairs_persist()
	await _s4_heist_checklist()
	await _s5_city_hall_circuit()
	await _s6_family_reunion()
	await _s7_rico_night()
	await _s8_skip_town()

	var failed := 0
	for r: Dictionary in _results:
		if not (r["fails"] as PackedStringArray).is_empty():
			failed += 1
	print("---")
	print("scenarios: %d  passed: %d  failed: %d"
			% [_results.size(), _results.size() - failed, failed])
	print("OK" if failed == 0 else "SIM FAILED")
	if main.night != null and is_instance_valid(main.night):
		main.night.stop()
	_parked.clear()
	main.queue_free()
	await step(2)
	get_tree().quit(0 if failed == 0 else 1)


## 1 — the shipment. The yard's own signals arm the run, three stacks ship it, and the cargo
## ramp doubles it. The window is real: a run that runs out ships nothing.
func _s1_smuggling_run() -> void:
	begin("docks: a run arms, three stacks ship, the truck doubles")
	Game.heat.reset()
	_smuggling.clear()
	var dirty_before := Game.wallet.dirty

	table.emit_signal(&"docks_entered")
	await step(2)
	check(Game.smuggling.active, "entering the yard did not arm a run")
	check(not _smuggling.is_empty(), "the mode said nothing to the HUD")

	table.emit_signal(&"container_stack_cleared", 0)
	table.emit_signal(&"container_stack_cleared", 0)
	await step(2)
	check(Game.smuggling.cleared_count() == 1, "the same stack twice counted twice")

	table.emit_signal(&"cargo_shipped", 900.0)
	await step(2)
	check(Game.smuggling.hot, "the hoist did not put the load on the truck")

	var heat_before := Game.heat.value
	table.emit_signal(&"container_stack_cleared", 1)
	table.emit_signal(&"container_stack_cleared", 2)
	await step(4)
	check(not Game.smuggling.active, "three stacks did not close the run")
	check(Game.smuggling.night_shipments == 1, "the shipment was not booked")
	var paid := Game.night_group_dirty(&"smuggling")
	check(paid.is_positive(), "the shipment paid nothing")
	check(Game.wallet.dirty.cmp(dirty_before) > 0, "and none of it reached the wallet")
	check(Game.heat.value >= heat_before + SmugglingRun.SHIPMENT_HEAT - 0.01,
			"a shipment is a loud act and this one was quiet")
	var hot_take := paid

	# The same run, cold, is worth half as much — and a lapsed window ships nothing at all.
	await wait(SmugglingRun.RETRIGGER_GAP + 0.2)
	table.emit_signal(&"docks_entered")
	await step(2)
	check(Game.smuggling.active, "the yard did not re-arm after the cooldown")
	var before_cold := Game.night_group_dirty(&"smuggling")
	table.emit_signal(&"containers_state", [0, 1, 2])
	await step(4)
	var cold_take := Game.night_group_dirty(&"smuggling").sub_clamped(before_cold)
	check(cold_take.is_positive(), "the state report did not ship the load")
	check(cold_take.cmp(hot_take) < 0, "a load that never saw the truck paid the same")

	await wait(SmugglingRun.RETRIGGER_GAP + 0.2)
	table.emit_signal(&"docks_entered")
	await step(2)
	var shipments := Game.smuggling.night_shipments
	Game.smuggling.tick(SmugglingRun.RUN_SECONDS)
	await step(2)
	check(not Game.smuggling.active, "the window did not close")
	check(Game.smuggling.night_shipments == shipments, "a lapsed run shipped anyway")
	print("        hot %s | cold %s | heat %.1f" % [hot_take.text(), cold_take.text(),
			Game.heat.value])
	finish()


## 2 — the Sit-Down. Sixty seconds where the meter does not move at all: not down, not up, and
## not later either — the earn window is never fed.
func _s2_sitdown_freezes_the_meter() -> void:
	begin("penthouse: the Sit-Down stops the meter dead")
	Game.heat.reset()
	Game.heat.value = 55.0
	var held := Game.heat.value

	table.emit_signal(&"sitdown_entered")
	await step(2)
	check(Game.sitdown.active, "the saucer did not open a negotiation")
	check(Game.heat_frozen(), "the meter is still running")

	Game.earn_switch(&"bumpers", BigMoney.of(5.0, 6))
	await wait(1.0)
	check(is_equal_approx(Game.heat.value, held), "the meter moved during a Sit-Down")
	check(is_zero_approx(Game.heat.pending_units()),
			"money made inside the minute is queued to warm the meter later")

	Game.sitdown.tick(SitDown.SECONDS)
	await step(2)
	check(not Game.sitdown.active, "the negotiation did not end")
	check(not Game.heat_frozen(), "and the freeze outlived it")
	Game.heat_add_flat(5.0)
	check(Game.heat.value > held, "the meter did not come back to life")
	print("        held %.1f -> %.1f" % [held, Game.heat.value])
	finish()


## 3 — the five chairs. A claimed chair is claimed for the career: it survives the Night, the
## save, and the reload. Five of them plus a sweep lights the campaign.
func _s3_chairs_persist() -> void:
	begin("penthouse: chairs are claimed for the career, not the Night")
	table.emit_signal(&"chair_taken", 0)
	table.emit_signal(&"chair_taken", 1)
	await step(2)
	check(Game.chairs.claimed_count() == 2, "two chairs did not stay taken")

	await fresh_night()
	check(Game.chairs.claimed_count() == 2, "a new Night gave the room back")
	check(Game.chairs.night_claimed == 0, "and tonight's tally is not clean")

	Game.save_now()
	var reload := Game.save.read()
	check(int((reload.get("chairs", {}) as Dictionary).get("claimed", []).size()) == 2,
			"the save did not carry the claimed chairs")

	for i in range(2, CommissionChairs.CHAIRS):
		table.emit_signal(&"chair_taken", i)
	await step(2)
	check(Game.chairs.all_claimed(), "five chairs did not seat the Commission")
	check(not Game.elections.unlocked, "the campaign opened without a sweep")
	table.emit_signal(&"chairs_completed")
	await step(2)
	check(Game.elections.unlocked, "the sweep did not light ELECTIONS")
	print("        chairs %d/%d | campaign %s" % [Game.chairs.claimed_count(),
			CommissionChairs.CHAIRS, "open" if Game.elections.unlocked else "shut"])
	finish()


## 4 — a heist runs on an ordinary Night, off ordinary switch traffic, and fails forward:
## a blown beat is a worse payday and only a drain ends the job.
func _s4_heist_checklist() -> void:
	begin("heists: the checklist advances on real switches and fails forward")
	Game.wallet.earn_dirty(BigMoney.of(1.0, 9))
	_heists.clear()
	await end_the_night()
	var planned := Game.plan_heist(Heists.PAYROLL, Heists.LOUD,
			{"name": "Sal", "trait": GuyTraits.FAST})
	check(not planned.is_empty(), "the war room refused the job")
	await open_night()

	var job := Game.heist
	check(job != null and job.active, "the Night did not open on the job")
	if job == null:
		finish()
		return
	check(Game.heists.casing_left(Heists.PAYROLL, Game.night_no) == Heists.CASING_NIGHTS,
			"running the job did not start the casing clock")

	var first: Dictionary = job.beats()[0]
	for i in int(first["count"]):
		await hit(&"bumper_1", 0.5)
	check(job.beat_index == 1, "three bumper hits did not close the first beat")
	check(not _heists.is_empty(), "the checklist said nothing to the HUD")

	# Blow the second beat on the clock: fail-forward, not failure.
	job.tick(job.window_for(1) + 0.1)
	await step(2)
	check(job.active, "a blown beat ended the job")
	check(job.blown == 1, "the blown beat was not counted")
	check(job.beat_index == 2, "the checklist did not move on")

	var clean_before := Game.wallet.clean
	var stars := Game.respect
	var last: Dictionary = job.beats()[2]
	for i in int(last["count"]):
		await hit(&"orbit_left", 0.5)
	check(not job.active, "the last beat did not finish the job")
	check(Game.heist == null, "the crew is still on the table")
	check(Game.wallet.clean.cmp(clean_before) > 0, "the take did not land in CLEAN")
	check(Game.respect > stars, "a cleared job paid no ☆")
	check(Game.heists.cleared == 1, "the book did not record it")
	check(int(Game.career.get("heists_cleared", 0)) == 1, "and it does not count toward Juice")
	check(not Game.heists.is_available(Heists.PAYROLL, Game.night_no),
			"the same truck is on the board again the same Night")
	print("        take %s | blown %d | casing %d nights"
			% [Game.wallet.clean.sub_clamped(clean_before).text(), job.blown,
				Game.heists.casing_left(Heists.PAYROLL, Game.night_no)])
	finish()


## 5 — the City Hall Circuit. Four legs, in order, on the table's own signals; the fourth
## lights EMPIRE and sixty seconds later it pays a clean dividend.
func _s5_city_hall_circuit() -> void:
	begin("empire: the circuit lights it and the dividend is clean")
	await fresh_night()
	_empire.clear()
	var quiet := Game.preview_switch(&"bumpers", BigMoney.from_float(100.0))

	table.emit_signal(&"orbit_completed")
	await step(2)
	check(Game.empire.leg == 1, "the orbit is not the first leg")
	table.emit_signal(&"staircase_climbed", 900.0)
	await step(2)
	check(Game.empire.leg == 2, "the staircase is not the second leg")
	table.emit_signal(&"penthouse_entered", 1000.0)
	await step(2)
	check(Game.empire.leg == 3, "the Penthouse gate is not the third leg")

	check(table.has_signal(&"dome_loop_completed"), "the table has no dome to close the lap")
	table.emit_signal(&"dome_loop_completed", 1400.0)
	await step(2)
	check(Game.empire.active, "the circuit did not light EMPIRE")

	var loud := Game.preview_switch(&"bumpers", BigMoney.from_float(100.0))
	check(loud.equals_approx(quiet.mul(EmpireMode.DIRTY_MULT), 1e-6),
			"EMPIRE is not paying ×10")
	var earned := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0))
	var clean_before := Game.wallet.clean
	# Run the mode's clock down to a frame's worth and let the NightController close it: what
	# is under test is that the Night pays the dividend, not that a float reaches zero.
	Game.empire.time_left = 0.02
	await wait(0.3)
	check(not Game.empire.active, "the sixty seconds did not run out")
	var dividend := Game.wallet.clean.sub_clamped(clean_before)
	check(dividend.is_positive(), "EMPIRE paid no dividend")
	check(dividend.equals_approx(earned.mul(EmpireMode.CLEAN_SHARE), 1e-6),
			"the dividend is not a clean share of what the minute made")
	check(Game.empire.lit_tonight, "the Reunion does not know EMPIRE was lit")
	print("        earned %s | dividend %s" % [earned.text(), dividend.text()])
	finish()


## 6 — the Family Reunion. At R7 with EMPIRE lit tonight, the back room sends everybody.
func _s6_family_reunion() -> void:
	begin("reunion: the back room puts the whole crew on the table")
	check(Game.reunion_ready(), "R7 with EMPIRE lit is not Reunion-ready")
	Game.meeting.lit = true
	var before := Balls.count()
	table.emit_signal(&"backroom_entered")
	await step(4)

	check(Game.meeting.active, "the back room did not start a Meeting")
	check(Game.meeting.is_reunion(), "a Reunion-ready Night started an ordinary Meeting")
	check(Game.meeting.size == FamilyMeeting.REUNION_GUYS,
			"the Reunion fielded %d guys" % Game.meeting.size)
	check(Balls.count() > before, "no extra balls reached the table")
	check(is_equal_approx(Game.meeting.dirty_multiplier(), float(Game.meeting.size)),
			"the Meeting's rules did not scale with the crew")

	var names := {}
	for g in Game.meeting.extra_guys:
		names[String(g.get("name", ""))] = true
	check(names.size() == Game.meeting.extra_guys.size(), "the crew are not all named guys")

	# Park them all so the Night does not end underneath the next scenario.
	for b in Balls.live():
		park(b, SAFE_POINT + Vector2(float(b.get_instance_id() % 5) * 40.0, 0.0))
	await step(2)
	print("        crew %d | balls %d | all dirty x%d" % [Game.meeting.size, Balls.count(),
			int(Game.meeting.dirty_multiplier())])
	finish()


## 7 — the RICO Night. The blue meter tops out, the next Night IS the raid, and it ends in
## the biggest payout in the game or in a doubled confiscation.
func _s7_rico_night() -> void:
	begin("rico: the federal raid replaces a Night and pays or takes")
	Game.federal.enable(true)
	Game.federal.value = FederalHeat.RICO_AT
	Game.federal.rico_pending = true
	Game.wallet.earn_dirty(BigMoney.of(4.0, 8))
	# The raid is built and begun inside `NightController.start()`, so the clock has to be
	# shortened before the Night opens at all.
	RicoRaid.duration_override = RICO_SECONDS
	await fresh_night()

	check(main.night != null and main.night.rico != null,
			"the Feds did not replace the Night")
	if main.night == null or main.night.rico == null:
		finish()
		return
	var raid := main.night.rico
	check(raid.active, "the raid is not running")
	check(raid.phase == 1, "the raid did not open on the street sweep")

	var dirty := Game.wallet.dirty
	var clean := Game.wallet.clean
	await wait(RICO_SECONDS * 0.5)
	check(main.night.rico == null or main.night.rico.phase >= 2,
			"the raid never reached the wiretap")

	await wait(RICO_SECONDS)
	RicoRaid.duration_override = 0.0
	check(Game.wallet.clean.cmp(clean) > 0, "surviving the RICO raid paid nothing")
	# The pile keeps earning through the raid, so the payout is measured against what was
	# held when it started: at least twice that, and far more than an ordinary Beat the Rap.
	var payout := Game.wallet.clean.sub_clamped(clean)
	check(payout.cmp(dirty.mul(Game.RICO_CLEAN_PAYOUT)) >= 0,
			"the payout is less than twice the dirty the raid opened on")
	check(payout.cmp(dirty.mul(Game.RAID_CLEAN_PAYOUT)) > 0,
			"the biggest payout in the game is smaller than an ordinary raid's")
	check(is_zero_approx(Game.federal.value), "the blue meter did not empty")
	check(not Game.rico_pending(), "the Feds are still at the door")
	check(AudioDirector.rico_step() == 0 if AudioDirector.has_method("rico_step") else true,
			"the wiretap left a bus muted")
	print("        payout %s | federal %.0f" % [Game.wallet.clean.sub_clamped(clean).text(),
			Game.federal.meter_value()])
	finish()


## 8 — the train. Skip Town ends a career and starts a city: the Juice is banked, one guy
## comes along, and everything else is gone.
func _s8_skip_town() -> void:
	begin("skip town: the career ends and a city begins")
	await end_the_night()
	Game.respect = 9_000
	Game._book_lifetime_clean(BigMoney.of(9.0, 11))
	check(Game.skip_town_available(), "R7 cannot leave town")
	var preview := Game.skip_town_preview()
	check(int(preview["juice"]) > 0, "the city is worth no Juice")

	var keep := Game.bench.available()[0]
	var kept_name := String(keep["name"])
	var nodes := Game.owned.size()
	var result := Game.skip_town(keep)

	check(int(result["juice"]) == int(preview["juice"]), "the train paid a different number")
	check(Game.owned.size() < nodes, "the table came with us")
	check(not Game.wallet.clean.is_positive(), "the clean cash came with us")
	check(Game.night_no == 0, "the new city did not start on Night one")
	check(String(Game.bench.guys[0]["name"]) == kept_name, "the one guy did not come along")
	check(is_zero_approx(Game.heat.value), "the trail is not cold")
	check(not Game.federal.rico_pending, "the Feds followed us to the new city")

	var book := Game.prestige()
	if book != null and book.has_method("juice"):
		check(int(book.get("juice")) >= int(result["juice"]),
				"the Book did not bank the Juice")
	check(Game.to_dict().has("prestige"), "the save does not carry the Black Book")
	print("        juice %d | city %d | kept %s" % [int(result["juice"]),
			int(result.get("next_city", 2)), kept_name])
	finish()
