extends Node2D
## BOSS acceptance runner — the Commission (specs/m2-content.md §5, docs/05 §6).
##
## What is under test is a *ceremony with a fight in it*: that respect alone cannot promote you
## past R3 or R4, that the fight replaces a Night with the economy switched off, that Sammy's
## wrench really eats a button press for a second and a half and really gives it back, that the
## Butcher's truck only answers to orbit pace and his freezer pays out exactly what the cans
## were denied, that losing costs nothing but the Night, and that winning pays the purse, hands
## over a spoil that was never for sale, and lets the promotion land.
##
## It also runs the FLOW-2 specialist consumers that landed with this lane (Cohen's decay and
## bail, Nussbaum's wash, Manny's collect, the Consigliere's rerolls, the rain policy) and the
## Loaded Dice pocket count, because those are the same lane's one-liners and a one-liner with
## no test is a rumour.
##
## House rules as everywhere else here: the real `main.tscn` with the real table under it,
## physics ticks rather than wall time, the save file redirected somewhere harmless, and a
## non-zero exit code on any failure.

const MAIN_SCENE := preload("res://game/main.tscn")
const SIM_SAVE := "user://sim_boss_save.json"
const SEED := 0x424F5353

## A Capo's table: enough hardware for a fight to be a fight.
const FIXTURE: PackedStringArray = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "rackets.numbers_game",
	"fronts.coin_op", "rackets.the_wire", "rackets.protection_laundromat",
	"rackets.protection_pizzeria", "rackets.protection_pawn", "rackets.getaway_loop",
]

const DRAIN_POINT := Vector2(490.0, 1876.0)
## Clear felt above the bumper nest and clear of the left channel guide.
const SAFE_POINT := Vector2(250.0, 660.0)
## Where the sim parks the Butcher's truck to shoot at it. The orbit channel is deliberately
## narrower than a ball plus a truck, so a ball cannot be staged beside it up there; phase 1
## is about the speed RULE, and parking it on open felt tests exactly that rule.
const OPEN_FIELD := Vector2(490.0, 1180.0)

var main: Main = null
var table: Node2D = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _parked: Dictionary = {}
var _pinched: Array[Dictionary] = []
var _boss_events: Array[Dictionary] = []
var _collects: Array[Dictionary] = []


func _ready() -> void:
	main = MAIN_SCENE.instantiate()
	main.auto_start = false
	main.show_hud = true
	add_child(main)
	table = main.table

	SaveGame.new(SIM_SAVE).erase()
	main.start_session(SIM_SAVE)
	Game.new_game(SEED)

	Events.guy_pinched.connect(func(g: Dictionary) -> void: _pinched.append(g))
	Game.boss_changed.connect(func(s: Dictionary) -> void: _boss_events.append(s))
	Game.auto_collected.connect(func(id: StringName, amount: BigMoney) -> void:
		_collects.append({"id": id, "amount": amount}))
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


## Balls are parked by instance id, not by reference: a Night that ends frees every ball on
## the table, and a freed reference cannot even be tested with `is` without erroring.
func park(b: Ball, at: Vector2) -> void:
	if b != null and is_instance_valid(b):
		_parked[b.get_instance_id()] = at


func unpark(b: Ball) -> void:
	if b != null:
		_parked.erase(b.get_instance_id())


func _physics_process(_delta: float) -> void:
	for key: Variant in _parked.keys():
		var id := int(key)
		var held := instance_from_id(id) if is_instance_id_valid(id) else null
		var b := held as Ball
		if b == null or not is_instance_valid(b):
			_parked.erase(key)
			continue
		b.place(_parked[key])


func money(v: Variant) -> BigMoney:
	return v if v is BigMoney else BigMoney.zero()


func fight() -> BossFight:
	return main.night.boss if main.night != null and is_instance_valid(main.night) else null


func ball() -> Ball:
	return TableAPI.ball(table)


func park_safe() -> void:
	park(ball(), SAFE_POINT)


## The first shop with its shutters up — the only kind that can be knocked down and worked.
func _armed_shop(shops: Array) -> Storefront:
	for s: Variant in shops:
		var shop := s as Storefront
		if shop != null and shop.visible and shop.state_name() == &"armed":
			return shop
	return null


## Fire the ball at a boss vehicle from off its nose, at a chosen speed. Short approach on
## purpose: at 3800 px/s² of table rake a long run adds hundreds of px/s of fall to the
## contact speed, and phase 1 of the Butcher is a speed rule.
##
## Always from the right-hand end: the left of both marks is the numbers-lane guide and
## Lucky's bank, and a staging point inside either of those is a shot at a wall.
func strike_vehicle(t: BossTarget, speed: float) -> void:
	var b := ball()
	if b == null or t == null:
		return
	unpark(b)
	var d := t.body_length * 0.5 + t.body_thick * 0.5 + Feel.BALL_RADIUS * 2.0 + 12.0
	var from := t.to_global(Vector2(d, 0.0))
	var other := t.to_global(Vector2(-d, 0.0))
	if other.x > from.x:
		from = other
	var dir := (t.global_position - from).normalized()
	b.place(from)
	b.set_velocity(dir * speed)
	await wait(0.16)
	park_safe()
	# One contact is one hit: a panel ignores everything for `COOLDOWN` after being touched,
	# and that includes a shrugged slow hit. Wait it out or the next shot never happens.
	await wait(BossTarget.COOLDOWN + 0.05)


## Knock a standup (a goon, a door panel) off its face side. Placed onto the face rather than
## fired at it from across the table: a standup has no speed rule, and every approach lane on
## this playfield has something else standing in it.
func strike_standup(t: StandupTarget, speed: float = 900.0) -> void:
	var b := ball()
	if b == null or t == null or not t.visible:
		return
	unpark(b)
	var from := t.to_global(Vector2(0.0, 45.0))
	var dir := (t.global_position - from).normalized()
	b.place(from)
	b.set_velocity(dir * speed)
	await wait(0.1)
	park_safe()
	await step(2)


## Drain until The Count. A boss Night is a Night: three guys, then the tally.
func drain_out(limit: int = 14) -> void:
	for i in range(limit):
		if Game.state != &"night":
			return
		var b := ball()
		unpark(b)
		if b != null and is_instance_valid(b):
			b.place(DRAIN_POINT)
		await wait(1.6)
	await step(2)


func run_boss_night(want: StringName) -> bool:
	var started := Game.start_boss_night()
	await wait(0.5)
	park_safe()
	await step(2)
	return started and fight() != null and fight().id == want


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M2 boss sim ==")
	print("physics %d Hz | seed 0x%X | save %s"
			% [Engine.physics_ticks_per_second, SEED, SIM_SAVE])
	await step(4)

	for id in FIXTURE:
		Game.buy_upgrade(id, BigMoney.zero())

	await _s1_the_gate()
	await _s2_sammy_round_one()
	await _s3_sammy_the_ceremony()
	await _s4_the_butcher()
	await _s5_cold_storage_spoil()
	await _s6_specialists()
	await _s6b_sammys_spare()
	await _s7_loaded_dice_pockets()

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


## 1 — the ladder stops at the Commission. Stars buy the meeting, not the chair.
func _s1_the_gate() -> void:
	begin("the gate: respect alone stops at R3, and Sammy is the door")
	check(Game.rank == 0, "a fresh career opens at R0")
	Game.add_respect(Game.RANK_RESPECT[3] - 1, &"sim")
	check(Game.rank == 2, "R2 at %d stars" % Game.respect)
	check(Game.boss_waiting().is_empty(), "the Commission asked before the stars were in")

	Game.add_respect(Game.RANK_RESPECT[4] - Game.respect, &"sim")
	check(Game.rank_for_respect(Game.respect) == 4,
			"%d stars is worth R4 on the ladder" % Game.respect)
	check(Game.rank == 3, "but the Commission holds the career at R3 (reads %d)" % Game.rank)
	var f := Game.boss_waiting()
	check(not f.is_empty(), "nobody is waiting with the R4 stars banked")
	check(StringName(f.get("id", "")) == Commission.SAMMY, "the wrong family answered")
	check(String(f.get("call", "")) == "SAMMY'S WAITING", "the button does not say his line")
	check(Game.commission.attempts_at(Commission.SAMMY) == 0, "the book already counted a Night")

	# Every ungated step still promotes on the stars alone — the gate is two rungs, not a wall.
	check(Game.commission.rank_cap(0, 3) == 3, "the Commission blocked a rank below R3")
	check(Game.commission.rank_cap(3, 5) == 3, "R3 leaked past Sammy")
	check(Game.commission.rank_cap(4, 6) == 4, "R4 leaked past the Butcher")
	print("        %d stars | rank %d | waiting: %s"
			% [Game.respect, Game.rank, String(f.get("name", "-"))])
	finish()


## 2 — the fight replaces a Night: no earning, no raid, a wrench on a schedule — and losing
## costs nothing but the Night, with the rematch on the button.
func _s2_sammy_round_one() -> void:
	begin("sammy round one: economy off, the wrench bites, a loss is only a Night")
	var started := await run_boss_night(Commission.SAMMY)
	check(started, "the Count's button did not start the fight")
	if not started:
		finish()
		return
	var boss := fight()
	check(Game.state == &"night", "a fight is a Night, not a state of its own")
	check(Game.commission.attempts_at(Commission.SAMMY) == 1, "the attempt was not booked")
	check(boss.phase == 1, "the fight opened on phase %d" % boss.phase)
	check(Game.economy_paused(), "the economy kept running through a Commission fight")

	# THE ECONOMY IS OFF. Every switch on the table is worth exactly nothing.
	var dirty_before := Game.wallet.dirty
	var paid := Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	check(not paid.is_positive(), "a switch paid %s during a boss fight" % paid.text())
	check(Game.wallet.dirty.equals_approx(dirty_before, 1e-9), "and it reached the wallet")
	check(not Game.night_dirty.is_positive(), "the Night's book counted paused money")

	# THE WRENCH. Two seconds of gag, then the bat eats the button for a second and a half.
	var left := TableAPI.prop(table, "flipper_left") as Flipper
	check(left != null, "the table has no left bat to jam")
	if left == null:
		finish()
		return
	main.night.telegraph_flipper(&"left", SammyFight.TELEGRAPH)
	check(left.is_telegraphed(), "the wrench gag never showed")
	var jammed := main.night.jam_flipper(&"left", SammyFight.JAM_SECONDS)
	check(jammed, "the jam did not land")
	check(left.is_jammed(), "the bat is not jammed")
	left.press()
	await step(3)
	check(left.state == Flipper.State.REST and is_zero_approx(left.progress),
			"a jammed bat answered the button (state %d)" % int(left.state))
	left.release()
	await wait(SammyFight.JAM_SECONDS + 0.2)
	check(not left.is_jammed(), "the wrench never came out (%.2fs left)" % left.jam_left())
	left.press()
	await step(3)
	check(left.state != Flipper.State.REST, "the bat did not come back after the jam")
	left.release()
	await wait(0.3)

	# It is HIS Night: the Inspector does not get a look in.
	Game.heat.value = 100.0
	await wait(0.2)
	check(main.night.raid == null, "a raid started inside a boss fight")
	Game.heat.reset()

	# Two panels off the sedan, and then the Night runs out on him.
	var sedan: BossTarget = TableAPI.prop(table, "boss_sedan", null)
	check(sedan != null and sedan.is_hardware_active(), "the sedan is not on the table")
	check(sedan.hits_left == SammyFight.P1_PANELS,
			"the sedan opened with %d panels" % sedan.hits_left)
	await strike_vehicle(sedan, 900.0)
	check(sedan.hits_left == SammyFight.P1_PANELS - 1,
			"a clean hit left %d panels" % sedan.hits_left)
	check(boss.panels_left == sedan.hits_left, "the fight and the car disagree on panels")

	_pinched.clear()
	await drain_out()
	check(Game.state == &"count", "the Night never ended (state %s)" % String(Game.state))
	check(Game.rank == 3, "a lost fight promoted the career to R%d" % Game.rank)
	check(not Game.commission.is_beaten(Commission.SAMMY), "a lost fight was booked as a win")
	check(not Game.has_spoil(Commission.SPOIL_SAMMY), "a lost fight handed over the spoil")
	check(Game.boss == null, "the fight is still hanging off the session")
	var summary: Dictionary = Game.last_night
	var result: Dictionary = summary.get("boss", {})
	check(not result.is_empty() and not bool(result.get("won", true)),
			"The Count does not know the fight was lost")
	check(not money(summary.get("boss_paid", null)).is_positive(), "a lost fight paid a purse")
	check(not Game.boss_waiting().is_empty(), "the rematch is not on the Count's button")
	check(Game.commission.attempts_at(Commission.SAMMY) == 1,
			"attempts read %d" % Game.commission.attempts_at(Commission.SAMMY))
	print("        economy paused | jam %.1fs | wrench every %ds | lost, rematch offered"
			% [SammyFight.JAM_SECONDS, int(SammyFight.JAM_PERIOD)])
	finish()


## 3 — the whole fight, and the ceremony at the end of it.
func _s3_sammy_the_ceremony() -> void:
	begin("sammy round two: three phases, the purse, the spoil and the promotion")
	var started := await run_boss_night(Commission.SAMMY)
	check(started, "the rematch did not start")
	if not started:
		finish()
		return
	var boss := fight()
	var sedan: BossTarget = TableAPI.prop(table, "boss_sedan", null)
	check(sedan.hits_left == SammyFight.P1_PANELS, "the rematch remembered last Night's damage")

	for attempt in range(12):
		if sedan.hits_left <= 0:
			break
		await strike_vehicle(sedan, 900.0)
	check(sedan.hits_left == 0, "%d panels still on the sedan after twelve shots" % sedan.hits_left)
	await wait(BossFight.PHASE_BEAT + 0.3)
	check(boss.phase == 2, "four panels did not open phase 2 (phase %d)" % boss.phase)

	# PHASE 2: his crew holds the cans shut. Armored is a real state on the money path.
	check(Game.is_group_armored(&"bumpers"), "the cans are not armored in phase 2")
	var goons: Array = TableAPI.prop(table, "boss_goons", []) as Array
	check(goons.size() == 3, "%d goons showed up" % goons.size())
	check(int(TableAPI.call_if(table, "boss_goons_standing", [], 0)) == 3,
			"the goons are not standing")
	for g: Variant in goons:
		await strike_standup(g as StandupTarget)
	await wait(BossFight.PHASE_BEAT + 0.3)
	check(boss.phase == 3, "three goons down did not open phase 3 (phase %d)" % boss.phase)
	check(not Game.is_group_armored(&"bumpers"), "the cans stayed armored after the goons")

	# PHASE 3: he parks, three panels, and the wrench comes twice as often.
	check(sedan.is_hardware_active(), "the sedan did not come back for phase 3")
	check(sedan.hits_left == SammyFight.P3_PANELS,
			"the parked sedan has %d panels" % sedan.hits_left)
	check(sedan.global_position.distance_to(ProgressionTable.SEDAN_PARK) < 1.0,
			"the sedan parked at %s" % str(sedan.global_position))

	var clean_before := Game.wallet.clean
	var respect_before := Game.respect
	_boss_events.clear()
	for attempt in range(12):
		if sedan.hits_left <= 0:
			break
		await strike_vehicle(sedan, 900.0)
	check(sedan.hits_left == 0, "the parked sedan kept %d panels" % sedan.hits_left)
	# The win lands one phase beat after the last panel — the hardware comes down first.
	await wait(BossFight.PHASE_BEAT + 0.6)

	var purse := Commission.purse_for(Commission.fight(Commission.SAMMY))
	check(Game.commission.is_beaten(Commission.SAMMY), "Sammy is still standing")
	check(Game.wallet.clean.sub_clamped(clean_before).cmp(purse) >= 0,
			"the purse did not arrive (%s, expected %s)"
			% [Game.wallet.clean.sub_clamped(clean_before).text(), purse.text()])
	check(Game.has_spoil(Commission.SPOIL_SAMMY), "the Spare was not taken off him")
	check(Game.rank == 4, "the ceremony did not promote the career (rank %d)" % Game.rank)
	check(Game.respect > respect_before, "beating a boss paid no stars")
	check(not Upgrades.shared().has_id(Commission.SPOIL_SAMMY),
			"the spoil is in the Ledger catalog — a signature spoil is not for sale")
	check(Game.spoils().has(Commission.SPOIL_SAMMY), "the spoil is not in the career's list")

	await wait(NightController.BOSS_CEREMONY + 0.6)
	check(Game.state == &"count", "the ceremony did not end the Night")
	var summary: Dictionary = Game.last_night
	var result: Dictionary = summary.get("boss", {})
	check(bool(result.get("won", false)), "The Count does not know he went down")
	check(bool(summary.get("rank_up", false)), "the summary is not a rank-up Night")
	check(String(summary.get("headline", "")) != "", "a boss Night printed no front page")
	check(Game.boss_waiting().is_empty(), "Sammy is waiting again after losing")

	# The save carries it: a beaten boss stays beaten, and so does his spoil.
	Game.save_now()
	var reloaded := Commission.new()
	reloaded.from_dict(Game.to_dict().get("commission", {}))
	check(reloaded.is_beaten(Commission.SAMMY), "the save forgot the fight")
	check(int(Game.to_dict().get("owned", {}).get(Commission.SPOIL_SAMMY, 0)) > 0,
			"the save forgot the spoil")
	print("        purse %s | spoil %s | rank %d | headline: %s"
			% [purse.text(), Commission.SPOIL_SAMMY, Game.rank,
				String(summary.get("headline", ""))])
	finish()


## 4 — the Butcher: orbit pace or nothing, a freezer that fills while you are not paid, and a
## 25-second frenzy that hands it back double if you lit the lanes on the way.
func _s4_the_butcher() -> void:
	begin("the butcher: orbit-speed only, the freezer fills, the frenzy pays it out x2")
	Game.add_respect(Game.RANK_RESPECT[5] - Game.respect, &"sim")
	check(Game.rank == 4, "the ladder did not stop at R4 (rank %d)" % Game.rank)
	var waiting := Game.boss_waiting()
	check(StringName(waiting.get("id", "")) == Commission.BUTCHER, "the Butcher is not waiting")

	var started := await run_boss_night(Commission.BUTCHER)
	check(started, "the Butcher's Night did not start")
	if not started:
		finish()
		return
	var boss: ButcherFight = fight() as ButcherFight
	var truck: BossTarget = TableAPI.prop(table, "boss_truck", null)
	check(truck != null and truck.is_hardware_active(), "the truck is not on the table")
	check(truck.min_speed >= ButcherFight.ORBIT_SPEED - 0.001,
			"the truck takes hits at %.0f px/s" % truck.min_speed)

	# The truck really does ride the channel before the sim parks it to shoot at it.
	var was := truck.global_position
	await wait(0.5)
	check(truck.global_position.distance_to(was) > 20.0, "the truck is not circling anything")
	truck.set_moving(false)
	truck.park_at(OPEN_FIELD)
	await step(2)

	# ORBIT PACE OR NOTHING.
	var panels := truck.hits_left
	await strike_vehicle(truck, 220.0)
	check(truck.hits_left == panels, "a crawling ball dented the truck")
	await strike_vehicle(truck, 1600.0)
	check(truck.hits_left == panels - 1, "a loop-speed hit did not count")

	# THE FREEZER. The cans are armored, and what they refuse is banked to the penny.
	check(Game.is_group_armored(&"bumpers"), "the cans are not in cold storage")
	var want := Game.preview_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	var frozen_before := boss.frozen
	Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	check(boss.frozen.sub_clamped(frozen_before).equals_approx(want, 1e-6),
			"the freezer banked %s, the can was worth %s"
			% [boss.frozen.sub_clamped(frozen_before).text(), want.text()])
	for i in range(9):
		Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	check(boss.frozen.equals_approx(want.mul(10.0), 1e-6),
			"ten denied cans banked %s" % boss.frozen.text())

	# The lanes: hidden depth, counted through phases 1 and 2 only.
	for i in range(3):
		table.emit_signal(&"rollover_rolled", i, false)
	await step(2)
	check(boss.lanes_all_lit(), "three lanes did not light the doubler")

	# Finish the truck: two more panels at pace.
	for attempt in range(10):
		if truck.hits_left <= 0:
			break
		await strike_vehicle(truck, 1600.0)
	check(truck.hits_left == 0, "%d panels left in the truck" % truck.hits_left)
	await wait(BossFight.PHASE_BEAT + 0.3)
	check(boss.phase == 2, "the broken truck did not open phase 2 (phase %d)" % boss.phase)
	check(Game.is_group_armored(&"bumpers"), "the cans thawed in phase 2")

	# PHASE 2: the back door, six panels, twice.
	var door: TargetBank = TableAPI.prop(table, "boss_door", null)
	check(door != null and door.targets().size() == 6, "the door is not a 2x3 bank")
	for round_no in range(ButcherFight.DOOR_BREAKS):
		for t: StandupTarget in door.targets():
			await strike_standup(t)
		if round_no == 0:
			check(boss.doors_broken == 1, "the first break was not counted")
			await wait(door.reset_seconds + 0.4)
	await wait(BossFight.PHASE_BEAT + 0.4)
	check(boss.phase == 3, "two breaks did not open the frenzy (phase %d)" % boss.phase)
	check(boss.secured, "the fight is not decided once the door is down twice")
	check(not Game.is_group_armored(&"bumpers"), "the frenzy started with the cans armored")

	# PHASE 3: the freezer comes back out through the cans, doubled.
	var frozen := boss.frozen
	var slice := frozen.mul(ButcherFight.ALL_LANES_MULT / float(ButcherFight.FRENZY_HITS))
	var clean_before := Game.wallet.clean
	Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	var got := Game.wallet.clean.sub_clamped(clean_before)
	check(got.equals_approx(slice, 1e-6),
			"a frenzy pop paid %s, expected the freezer's twelfth doubled (%s)"
			% [got.text(), slice.text()])
	check(boss.frozen_paid.equals_approx(slice, 1e-6), "the freezer's book disagrees")
	for i in range(ButcherFight.FRENZY_HITS):
		Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	check(boss.frozen_left().ratio_to(frozen) < 1e-6,
			"the freezer still holds %s of %s after the whole bank"
			% [boss.frozen_left().text(), frozen.text()])
	var paid_total := Game.wallet.clean.sub_clamped(clean_before)
	check(paid_total.equals_approx(frozen, 1e-4),
			"the frenzy paid %s of a %s freezer" % [paid_total.text(), frozen.text()])

	# The single branch, priced the same way with the lanes dark.
	var plain := ButcherFight.new()
	plain.frozen = BigMoney.from_float(1200.0)
	check(plain._slice_value().equals_approx(
			BigMoney.from_float(1200.0 / float(ButcherFight.FRENZY_HITS)), 1e-9),
			"with dark lanes a pop is not a plain twelfth")
	plain.free()

	# And the clock ends it: the fight is won, the rank lands, the spoil is taken. The frenzy
	# clock is wound forward rather than waited out — 25 s of real physics proves nothing the
	# payout above has not already proved.
	var clean_at_win := Game.wallet.clean
	check(boss.frenzy_left > 0.0, "the frenzy clock had already run out")
	boss.frenzy_left = 0.05
	await wait(BossFight.PHASE_BEAT + 0.6)
	var purse := Commission.purse_for(Commission.fight(Commission.BUTCHER))
	check(Game.commission.is_beaten(Commission.BUTCHER), "the Butcher is still standing")
	check(Game.wallet.clean.sub_clamped(clean_at_win).cmp(purse) >= 0,
			"the Butcher's purse did not arrive")
	check(Game.has_spoil(Commission.SPOIL_BUTCHER), "Cold Storage was not taken")
	check(Game.rank == 5, "the ceremony did not promote to R5 (rank %d)" % Game.rank)
	await wait(NightController.BOSS_CEREMONY + 0.8)
	check(Game.state == &"count", "the Butcher's Night did not end")
	print("        freezer %s | slice %s (x%d) | purse %s | rank %d"
			% [frozen.text(), slice.text(), int(ButcherFight.ALL_LANES_MULT), purse.text(),
				Game.rank])
	finish()


## 5 — the spoil itself, away from the man it came from: armored hardware banks half of what
## it denies and hands it over when the armor comes off (spec §5).
func _s5_cold_storage_spoil() -> void:
	begin("cold storage: armored cans bank half, paid on re-enable")
	check(Game.has_spoil(Commission.SPOIL_BUTCHER), "the scenario needs the spoil")
	check(not Game.economy_paused(), "no fight should be running here")
	Game.heat.reset()
	var want := Game.preview_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	Game.set_group_armored(&"bumpers", true)
	var dirty_before := Game.wallet.dirty
	var paid := Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	check(not paid.is_positive(), "an armored can paid %s" % paid.text())
	check(Game.wallet.dirty.equals_approx(dirty_before, 1e-9), "and it reached the wallet")
	check(Game.armored_bank(&"bumpers").equals_approx(
			want.mul(Game.COLD_STORAGE_FRACTION), 1e-6),
			"cold storage banked %s of a %s can" % [Game.armored_bank(&"bumpers").text(),
				want.text()])
	for i in range(5):
		Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	var owed := Game.armored_bank(&"bumpers")
	var clean_before := Game.wallet.clean
	Game.set_group_armored(&"bumpers", false)
	check(Game.wallet.clean.sub_clamped(clean_before).equals_approx(owed, 1e-6),
			"re-enabling paid %s of %s owed"
			% [Game.wallet.clean.sub_clamped(clean_before).text(), owed.text()])
	check(not Game.armored_bank(&"bumpers").is_positive(), "the bank was not emptied")
	var live := Game.earn_switch(&"bumpers", BigMoney.from_float(TableScore.BUMPER))
	check(live.is_positive(), "the cans did not come back on")
	print("        banked %s over six denied cans, paid on re-enable" % owed.text())
	finish()


## 6 — the FLOW-2 specialist consumers. One line each, and each one visible.
func _s6_specialists() -> void:
	begin("specialists: decay, bail, the wash, Manny, rerolls and the rain policy")

	# COHEN — heat decay and the bondsman.
	var decay_before := Game.heat.decay_scale
	Game.buy_upgrade("crew.cohen", BigMoney.zero())
	Game.buy_upgrade("crew.cohen", BigMoney.zero())
	check(Game.stats.heat_decay_mult() > 1.0, "Cohen bought no decay")
	check(is_equal_approx(Game.heat.decay_scale, Game.stats.heat_decay_mult()),
			"the meter is cooling at %.3f, Stats says %.3f"
			% [Game.heat.decay_scale, Game.stats.heat_decay_mult()])
	check(Game.heat.decay_scale > decay_before, "the meter did not get the memo")
	# Somebody has to be inside for a bail to have a price. The Nights before this one have
	# long since let their guys out, so this scenario puts one back.
	if Game.bench.holding().is_empty():
		var free_guys := Game.bench.available()
		if not free_guys.is_empty():
			Game.bench.pinch(free_guys[0], false)
	var held := Game.bench.holding()
	check(not held.is_empty(), "nobody is in holding to bail")
	if not held.is_empty():
		var guy: Dictionary = held[0]
		# Bail rides rank_scale now (device ruling): the undiscounted reference must be
		# priced at the SAME rank Game prices at, or Cohen looks like a markup.
		var full := Game.bench.bail_cost(guy, Game.rank)
		var ours := Game.bail_cost(guy)
		check(ours.cmp(full) < 0, "bail is still %s with Cohen hired" % ours.text())
		check(ours.equals_approx(full.mul(1.0 - Game.stats.bail_discount()), 1e-6),
				"the discount is not the one Stats reports")

	# NUSSBAUM — the wash that needs no loop pass, and the same per-Night cap as everything.
	Game.buy_upgrade("fronts.industrial_washers", BigMoney.zero())
	Game.buy_upgrade("crew.nussbaum", BigMoney.zero())
	check(Game.stats.auto_launder_per_sec() > 0.0, "Nussbaum washes nothing")
	Game.start_night()
	await wait(0.4)
	park_safe()
	await step(2)
	Game.wallet.earn_dirty(BigMoney.from_float(400_000.0))
	var washed_before := Game.night_laundered
	await wait(1.0)
	check(Game.night_laundered.cmp(washed_before) > 0, "the accountant washed nothing in a second")

	# MANNY — a lit award collects itself, and it is visible when it does.
	Game.buy_upgrade("crew.manny", BigMoney.zero())
	check(Game.stats.auto_collect_interval() > 0.0, "Manny has no clock")
	# Hired mid-Night his clock is already at zero, so he would take the first bank that opens
	# before the scenario had finished setting it up. Wind him forward first.
	main.night._collect_in = 30.0
	var shops: Variant = TableAPI.prop(table, "storefronts", null)
	check(shops is Array and not (shops as Array).is_empty(), "no storefronts to work")
	var shop: Storefront = _armed_shop(shops as Array)
	check(shop != null, "no storefront was armed to work")
	if shop == null:
		finish()
		return
	for t: DropTarget in shop.targets():
		t.drop()
	await step(6)
	check(shop.is_open(), "the bank did not open (%s, %d/%d down)"
			% [String(shop.state_name()), shop.down_count(), shop.targets().size()])
	_collects.clear()
	var dirty_before := Game.wallet.dirty
	main.night._collect_in = 0.05
	await wait(0.6)
	check(_collects.size() == 1, "Manny collected %d tills" % _collects.size())
	check(Game.wallet.dirty.cmp(dirty_before) > 0, "and none of it reached the wallet")
	check(shop.state_name() == &"cooldown", "the shop is still open after a collect")
	if not _collects.is_empty():
		check(StringName(_collects[0]["id"]) == shop.id, "he worked somebody else's till")

	# THE CONSIGLIERE — a reroll on the board.
	Game.buy_upgrade("crew.consigliere", BigMoney.zero())
	check(Game.stats.job_rerolls() > 0, "the Consigliere brought no rerolls")
	Game.night_rerolls = Game.stats.job_rerolls()
	var before_ids := PackedStringArray()
	for j: Dictionary in Game.jobs.active_jobs():
		before_ids.append(String(j.get("id", "")))
	var rerolls_before := Game.night_rerolls
	var swapped := Game.reroll_job(0)
	if before_ids.size() > 0:
		check(not swapped.is_empty(), "the reroll swapped nothing")
		check(Game.night_rerolls == rerolls_before - 1,
				"the reroll was free (%d left)" % Game.night_rerolls)
		var after := Game.jobs.active_jobs()
		check(after.size() == before_ids.size(), "the board changed size")
		if not after.is_empty():
			check(String(after[0].get("id", "")) != before_ids[0],
					"the same slip came back")

	# ★ RAIN INSURANCE — one confiscation a Night, and only one.
	Game.buy_upgrade("influence.rain_insurance", BigMoney.zero())
	check(Game.stats.flag(&"rain_insurance"), "the policy was not signed")
	Game.wallet.earn_dirty(BigMoney.from_float(1_000_000.0))
	var held_dirty := Game.wallet.dirty
	main.night._on_raid_finished(false)
	await step(2)
	# Nussbaum is washing dirty into clean the whole time, so the test is the SHAPE of the
	# change: a covered raid leaves the pile alone, an uncovered one takes a quarter of it.
	check(Game.wallet.dirty.ratio_to(held_dirty) > 0.98,
			"the policy did not cover the raid (%s -> %s)"
			% [held_dirty.text(), Game.wallet.dirty.text()])
	check(Game.night_insured, "the policy was not marked as spent")
	held_dirty = Game.wallet.dirty
	main.night._on_raid_finished(false)
	await step(2)
	check(Game.wallet.dirty.ratio_to(held_dirty) < 1.0 - Rates.RAID_CONFISCATE_FRACTION * 0.5,
			"the policy covered a second raid the same Night (%s -> %s)"
			% [held_dirty.text(), Game.wallet.dirty.text()])

	print("        decay x%.2f | bail -%d%% | wash %.3f/s | manny every %ds | rerolls %d"
			% [Game.heat.decay_scale, int(round(Game.stats.bail_discount() * 100.0)),
				Game.stats.auto_launder_per_sec(), int(Game.stats.auto_collect_interval()),
				Game.stats.job_rerolls()])
	finish()


## 6b — the Spare, the other spoil: once a Night the wrench falls out by itself and hands back
## a Lean, and every wrench after it lasts a third as long (spec §5). Runs on the Night scenario
## 6 started, because a Lean belongs to a Night's tilt meter.
func _s6b_sammys_spare() -> void:
	begin("sammy's spare: the first wrench falls out free, the rest are short")
	check(Game.has_spoil(Commission.SPOIL_SAMMY), "the scenario needs the Spare")
	check(Game.state == &"night", "the Spare needs a Night to be spent in")
	var left := TableAPI.prop(table, "flipper_left") as Flipper
	check(left != null, "no bat to jam")
	if left == null or Game.state != &"night":
		finish()
		return
	check(main.night._spare_ready, "the Spare was already spent this Night")
	var leans_before := main.nudge.meter.max_warnings
	var warnings_before := main.nudge.meter.warnings

	var landed := main.night.jam_flipper(&"left", SammyFight.JAM_SECONDS)
	check(not landed, "the Spare did not eat the first wrench")
	check(not left.is_jammed(), "the bat stayed jammed through the Spare")
	check(main.nudge.meter.max_warnings + warnings_before
			> leans_before + main.nudge.meter.warnings, "no free Lean came back")
	check(not main.night._spare_ready, "the Spare is once a Night, not once a wrench")
	left.press()
	await step(3)
	check(left.state != Flipper.State.REST, "the bat did not answer after the Spare cleared it")
	left.release()
	await wait(0.3)

	var second := main.night.jam_flipper(&"left", SammyFight.JAM_SECONDS)
	check(second, "the second wrench did not land")
	check(left.is_jammed(), "the second wrench did not stick")
	check(left.jam_left() <= SammyFight.JAM_SECONDS * NightController.SPARE_JAM_SCALE + 0.05,
			"a wrench after the Spare still lasts %.2fs" % left.jam_left())
	left.unjam()
	print("        first wrench free (+1 lean) | later wrenches %.2fs instead of %.2fs"
			% [SammyFight.JAM_SECONDS * NightController.SPARE_JAM_SCALE, SammyFight.JAM_SECONDS])
	finish()


## 7 — Loaded Dice, after the balance ruling. The pocket half of the node is GONE from the
## content: `casino_pocket_add` and `Stats.casino_player_pockets()` stay in the vocabulary for
## the day design wants a pocket to be buyable, but the ceiling equals the base, so nothing
## shipped can repaint the wheel. The whole edge is bought in payout, at +0.625% EV a point.
func _s7_loaded_dice_pockets() -> void:
	begin("loaded dice: the wheel stays 5/8 and the edge is bought in payout")
	var wheel: RouletteWheel = null
	var club: Variant = TableAPI.prop(table, "club", null)
	if club is ClubDeck:
		wheel = (club as ClubDeck).roulette
	check(wheel != null, "the deck has no wheel")

	# The vocabulary survives the ruling: the kind, the fold and the getter are all still here.
	check(Stats.fold_of(&"casino_pocket_add") == Stats.Fold.SUM, "the new kind does not sum")
	check(Upgrades.EFFECT_SPECS.has(&"casino_pocket_add"), "the loader does not know the kind")
	check(Game.stats.has_method("casino_player_pockets"), "the pocket getter is gone")
	check(Game.stats.casino_player_pockets() == Stats.CASINO_POCKETS_BASE,
			"a career with no Influence has %d pockets" % Game.stats.casino_player_pockets())
	check(Casino.player_pockets(Game.stats) == Casino.CasinoRules.PLAYER_POCKETS,
			"the rulebook and the getter disagree on the base wheel")
	check(Stats.CASINO_POCKETS_MAX == Stats.CASINO_POCKETS_BASE
			and Casino.CasinoRules.PLAYER_POCKETS_MAX == Casino.CasinoRules.PLAYER_POCKETS,
			"the pocket ceiling (%d) is not the base (%d) — a node could buy the wheel"
			% [Stats.CASINO_POCKETS_MAX, Stats.CASINO_POCKETS_BASE])

	# The shipped node: no pocket effect on it any more, and every level is a payout point.
	var shipped := Upgrades.shared().def("influence.loaded_dice")
	check(not shipped.is_empty(), "the catalog lost influence.loaded_dice entirely")
	var kinds := PackedStringArray()
	for e: Variant in shipped.get("effects", []):
		kinds.append(String((e as Dictionary)["kind"]))
	check(not kinds.has("casino_pocket_add"),
			"Loaded Dice still buys a pocket: %s" % ", ".join(kinds))
	check(kinds.has("casino_edge_add"), "Loaded Dice stopped buying edge: %s" % ", ".join(kinds))

	# Even a greedy fixture that DOES author pockets cannot get past the ceiling, so the day
	# somebody writes that content the wheel is still the wheel until this constant moves.
	var fixture := Upgrades.from_json(_POCKET_CONTENT, "boss_sim_pockets", true)
	check(fixture.is_valid(), "the pocket fixture did not load: %s" % str(fixture.errors))
	var greedy := Stats.new()
	greedy.catalog = fixture
	greedy.recompute({"influence.marked_deck": 5})
	check(greedy.casino_player_pockets() == Stats.CASINO_POCKETS_MAX,
			"ten pockets of Influence gave the player %d of 8"
			% greedy.casino_player_pockets())
	check(Casino.player_pockets(greedy) == Casino.CasinoRules.PLAYER_POCKETS_MAX,
			"the rulebook clamps the ceiling somewhere else than Stats does")

	# The edge, on the other hand, is a straight line the player can read: +0.625% a point,
	# from the honest -7.5% house edge to exactly +5.0% at full investment.
	var bare := Casino.expected_value(Game.stats)
	check(absf(bare + 0.075) < 1e-9, "a bare wheel is %.4f, not -0.075" % bare)
	var invested := Stats.new()
	invested.recompute({"crew.eddie": 12, "influence.loaded_dice": 8})
	check(absf(Casino.expected_value(invested) - 0.05) < 1e-9,
			"full investment runs at %.4f, not +0.05" % Casino.expected_value(invested))
	check(absf(Casino.payout_rate(invested) - Casino.CasinoRules.PAYOUT_MAX) < 1e-9,
			"full investment pays x%.4f, not the ceiling x%.4f"
			% [Casino.payout_rate(invested), Casino.CasinoRules.PAYOUT_MAX])

	# The wheel's paint follows the getter, and with the ceiling at the base it never moves.
	if wheel != null:
		var real := Game.stats
		Game.stats = invested
		wheel.refresh_pockets()
		check(wheel.player_pockets() == Stats.CASINO_POCKETS_BASE,
				"a fully-invested Club repainted the wheel to %d pockets"
				% wheel.player_pockets())
		check(wheel.house_pocket_count() == RouletteWheel.HOUSE_POCKETS.size(),
				"the house kept %d of its three pockets" % wheel.house_pocket_count())
		for p: int in RouletteWheel.HOUSE_POCKETS:
			check(wheel.is_house_now(p), "pocket %d stopped being the house's" % p)
		Game.stats = real
		wheel.refresh_pockets()
		check(wheel.house_pocket_count() == RouletteWheel.HOUSE_POCKETS.size(),
				"the wheel did not come back to the bare table")
	print("        wheel %d/8 fixed | edge %.0f points -> payout x%.2f | EV %.4f -> %.4f"
			% [Stats.CASINO_POCKETS_BASE, invested.casino_edge_add() * 100.0,
				Casino.payout_rate(invested), bare, Casino.expected_value(invested)])
	finish()


## A greedy fixture, kept so the CEILING is proven against content that actually tries to buy
## pockets. Nothing shipped authors `casino_pocket_add` any more (the balance ruling took it
## off Loaded Dice); this is what the day it comes back has to survive.
const _POCKET_CONTENT := """{
  "schema": 1,
  "nodes": [
	{
	  "id": "influence.loaded_dice", "branch": "influence", "tier": 4,
	  "name": "Loaded Dice", "flavor": "The wheel remembers who owns the room.",
	  "cost": "2M", "repeat": {"max": 8, "growth": 1.4},
	  "table_change": "One of the house's pockets is repainted as yours.",
	  "effects": [
		{"kind": "casino_edge_add", "value": 0.01, "per_level": true},
		{"kind": "casino_pocket_add", "value": 1}
	  ]
	},
	{
	  "id": "influence.marked_deck", "branch": "influence", "tier": 5,
	  "name": "Marked Deck", "flavor": "A greedy stack, here to prove the ceiling holds.",
	  "cost": "20M", "repeat": {"max": 5, "growth": 1.5},
	  "table_change": "Nothing — this node exists only in the sim's fixture.",
	  "effects": [
		{"kind": "casino_pocket_add", "value": 2, "per_level": true}
	  ]
	}
  ]
}"""
