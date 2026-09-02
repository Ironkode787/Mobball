extends Node2D
## FLOW acceptance runner for the CLUB (specs/m2-content.md §1/§4, docs/05 §3–4).
##
## The M1 night sim proves the session is a game. This one proves the modes that hang off it
## are wired to the real table and the real money path: that a casino win lands in the pile
## the Ledger says it should, that a Jackpot has to be finished inside one deck visit, that a
## Family Meeting puts a SECOND NAMED GUY on the table and pinches the right one when he
## drains, that the tote board draws against the spinner's count, that a perfect Collection
## Round pays double, and that the Cooler keeps its promise.
##
## House rules as everywhere else here: the real `main.tscn` with the real table under it,
## physics ticks rather than wall time, the save file redirected somewhere harmless, and a
## non-zero exit code on any failure.
##
## Where the sim drives the table it does so through the table's own signals — the same
## surface `game/flow/night.gd` binds to — rather than by aiming balls, because what is under
## test is the flow lane's reaction, not the deck's geometry (that is tests/sim/club_sim).

const MAIN_SCENE := preload("res://game/main.tscn")
const SIM_SAVE := "user://sim_club_flow_save.json"
const SEED := 0x434C5542

## A Boss's table: the M1 block plus the Club, without the Casino Wash — scenario 1 buys it.
const FIXTURE: PackedStringArray = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "rackets.numbers_game",
	"fronts.coin_op", "rackets.the_wire", "rackets.protection_laundromat",
	"rackets.protection_pizzeria", "rackets.protection_pawn", "rackets.club_license",
	"fronts.high_roller", "muscle.second_set",
]

## One of the wheel's five player pockets, and one of the house's three.
const PLAYER_POCKET := 1
const HOUSE_POCKET := 0

const DRAIN_POINT := Vector2(490.0, 1876.0)
const SAFE_POINT := Vector2(440.0, 1280.0)
const SAFE_POINT_B := Vector2(560.0, 1280.0)
## On the Club deck: anything above y=0 counts as upstairs, which is what keeps a deck visit
## open (game/flow/night.gd DECK_LINE).
const UPSTAIRS_POINT := Vector2(700.0, -320.0)
## Down the left outlane rather than between the bats — the Slippery escape is an outlane
## trait, and flow reads that off the table's own bounds.
const OUTLANE_POINT := Vector2(150.0, 1876.0)

var main: Main = null
var table: Node2D = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
## instance id -> {"ball": Ball, "at": Vector2}: balls held in place so a scenario can take
## as long as it needs without the Night ending underneath it.
var _parked: Dictionary = {}
var _pinched: Array[Dictionary] = []
var _casino_events: Array[Dictionary] = []
var _wire_events: Array[Dictionary] = []


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
	Game.casino_resolved.connect(func(r: Dictionary) -> void: _casino_events.append(r))
	Game.wire_drawn.connect(func(r: Dictionary) -> void: _wire_events.append(r))
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


## Hold a ball at a point every physics tick. A scenario that wants a drain unparks first.
func park(ball: Ball, at: Vector2) -> void:
	if ball == null or not is_instance_valid(ball):
		return
	_parked[ball.get_instance_id()] = {"ball": ball, "at": at}


func unpark(ball: Ball) -> void:
	if ball != null:
		_parked.erase(ball.get_instance_id())


func _physics_process(_delta: float) -> void:
	for key: Variant in _parked.keys():
		var row: Dictionary = _parked[key]
		var b: Ball = row["ball"]
		if b == null or not is_instance_valid(b):
			_parked.erase(key)
			continue
		b.place(row["at"])


func extra_ball() -> Ball:
	var primary := TableAPI.ball(table)
	for b in Balls.live():
		if b != primary:
			return b
	return null


## Drain one ball and let the Night react to it.
func drain(ball: Ball) -> void:
	await drain_at(ball, DRAIN_POINT)


func drain_at(ball: Ball, at: Vector2) -> void:
	unpark(ball)
	if ball != null and is_instance_valid(ball):
		ball.place(at)
	await wait(0.25)


func spinner() -> Object:
	var s: Variant = TableAPI.prop(table, "spinner", null)
	return s as Object


## Put spins on the numbers lane the way tests/sim/table_growth_sim does: the blade has a
## `kick()` for exactly this, so the ticket and the spinner's earnings are both real.
func spin_the_lane(times: int) -> void:
	var s := spinner()
	if s == null or not s.has_method("kick"):
		return
	for i in range(times):
		s.call("kick", Spinner.MAX_SPEED)
		await wait(3.4)


func money(v: Variant) -> BigMoney:
	return v if v is BigMoney else BigMoney.zero()


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M2 club flow sim ==")
	print("physics %d Hz | seed 0x%X | save %s"
			% [Engine.physics_ticks_per_second, SEED, SIM_SAVE])
	await step(4)

	for id in FIXTURE:
		Game.buy_upgrade(id, BigMoney.zero())
	Game.start_night()
	await wait(0.4)
	var served := TableAPI.ball(table)
	park(served, SAFE_POINT)
	await wait(0.2)

	await _s1_casino_wash_gating()
	await _s2_jackpot_per_visit()
	await _s3_family_meeting()
	await _s4_wire_draws()
	await _s5_collection_round()
	await _s6_cooler_pity()
	await _s7_slippery_outlane()
	await _s8_influence_nodes()

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


## 1 — the Casino Wash is a purchase. Until it is bought the house pays you in the same
## dirty money you handed it; after it, the same win arrives clean.
func _s1_casino_wash_gating() -> void:
	begin("casino: dirty wins before the Wash, clean after")
	Game.heat.reset()
	Game.wallet.earn_dirty(BigMoney.from_float(200_000.0))
	check(not Game.stats.flag(&"casino_wash"), "the fixture must not include the Wash")

	var dirty_before := Game.wallet.dirty
	var clean_before := Game.wallet.clean
	var want_stake := Casino.stake_for(dirty_before, Game.rank)
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", PLAYER_POCKET, false)
	await step(2)

	check(_casino_events.size() == 1, "the wheel reported %d bets" % _casino_events.size())
	if _casino_events.is_empty():
		finish()
		return
	var r: Dictionary = _casino_events[0]
	check(bool(r["bet"]), "the landing did not place a bet")
	check(money(r["staked"]).equals_approx(want_stake, 1e-6),
			"staked %s, expected 5%% of held dirty (%s)"
			% [money(r["staked"]).text(), want_stake.text()])
	check(not bool(r["clean"]), "an unwashed casino paid clean")
	check(Game.wallet.clean.equals_approx(clean_before, 1e-9),
			"clean moved without the Wash: %s -> %s" % [clean_before.text(), Game.wallet.clean.text()])
	check(Game.wallet.dirty.cmp(dirty_before.sub_clamped(want_stake)) > 0,
			"the dirty win never landed")
	check(not Game.casino.night_washed.is_positive(), "an unwashed win was booked as washed")
	# Balance-sim ruling: a pre-Wash win is dirty cash in a pocket, so it IS hot money — and it
	# is paid at face value, never back through the multipliers that priced the shots.
	check(Game.heat.pending_units() > 0.0,
			"a dirty casino win did not feed the Heat window (%.4f units)"
			% Game.heat.pending_units())
	check(money(r["paid"]).equals_approx(money(r["won"]), 1e-6),
			"the wheel promised %s and the wallet took %s — a payout was multiplied twice"
			% [money(r["won"]).text(), money(r["paid"]).text()])

	Game.buy_upgrade("fronts.casino_wash", BigMoney.zero())
	check(Game.stats.flag(&"casino_wash"), "buying the Wash did not set the flag")
	clean_before = Game.wallet.clean
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", PLAYER_POCKET, false)
	await step(2)
	var w: Dictionary = _casino_events[0] if not _casino_events.is_empty() else {}
	check(bool(w.get("clean", false)), "the washed casino still paid dirty")
	check(Game.wallet.clean.cmp(clean_before) > 0, "the washed win never reached clean")
	check(Game.casino.night_washed.is_positive(), "the Count's washed line is empty")
	print("        stake %s | dirty win %s | clean win %s | EV %.3f"
			% [want_stake.text(), money(r["won"]).text(), money(w.get("won", null)).text(),
				Casino.expected_value(Game.stats)])

	# A house pocket takes the stake and nothing comes back.
	var before_loss := Game.wallet.dirty
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", HOUSE_POCKET, true)
	await step(2)
	var lost: Dictionary = _casino_events[0]
	check(not money(lost["won"]).is_positive(), "a house pocket paid out")
	check(Game.wallet.dirty.equals_approx(before_loss.sub_clamped(money(lost["staked"])), 1e-6),
			"a losing spin cost something other than the stake")
	finish()


## 2 — the Jackpot is a deck-visit shot: all three reels between the top of the Staircase and
## coming back downstairs. Cleared reels outside a visit are worth nothing extra.
func _s2_jackpot_per_visit() -> void:
	begin("slots: three columns inside ONE deck visit is the Jackpot")
	Game.heat.reset()
	var ball := TableAPI.ball(table)
	park(ball, SAFE_POINT)
	await step(2)

	var clean_before := Game.wallet.clean
	table.emit_signal(&"reels_state", [0, 1, 2])
	await step(2)
	check(Game.wallet.clean.equals_approx(clean_before, 1e-9),
			"reels cleared with nobody upstairs paid a Jackpot")
	check(Game.casino.night_jackpots == 0, "and booked one")

	# Up the stairs: the visit opens and stays open while a ball is on the deck.
	park(ball, UPSTAIRS_POINT)
	await step(2)
	table.emit_signal(&"staircase_climbed", ClubDeck.STAIR_ENTRY_SPEED)
	await step(2)
	check(Game.casino.visit_open(), "a completed climb did not open a deck visit")

	table.emit_signal(&"reels_state", [0])
	await step(2)
	table.emit_signal(&"reels_state", [1])
	await step(2)
	check(Game.casino.night_jackpots == 0, "two columns paid a Jackpot")
	check(Game.casino.visit_columns() == 2, "the visit forgot a column between reel resets")

	clean_before = Game.wallet.clean
	var heat_before := Game.heat.value
	var rate := Game.stats.idle_rate_total()
	table.emit_signal(&"reels_state", [2])
	await step(2)
	var paid := Game.wallet.clean.sub_clamped(clean_before)
	var want := Casino.jackpot_value(rate)
	check(Game.casino.night_jackpots == 1, "the third column did not pay a Jackpot")
	check(paid.equals_approx(want, 1e-4),
			"the Jackpot paid %s, expected 8 minutes of idle (%s)" % [paid.text(), want.text()])
	check(Game.heat.value - heat_before >= Casino.CasinoRules.JACKPOT_HEAT - 0.1,
			"the Jackpot did not put the deck on the map (+%.1f heat)"
			% (Game.heat.value - heat_before))
	check(Game.meeting.jackpots_tonight == 1, "the back room did not count the Jackpot")
	check(not Game.meeting.lit, "one Jackpot lit the Family Meeting on its own")

	table.emit_signal(&"reels_state", [0, 1, 2])
	await step(2)
	check(Game.casino.night_jackpots == 1, "the same visit paid a second Jackpot")

	# Back downstairs: the visit closes by itself, and the next climb re-arms it.
	park(ball, SAFE_POINT)
	await wait(0.1)
	check(not Game.casino.visit_open(), "the visit stayed open with the ball downstairs")
	park(ball, UPSTAIRS_POINT)
	await step(2)
	table.emit_signal(&"staircase_climbed", ClubDeck.STAIR_ENTRY_SPEED)
	await step(2)
	table.emit_signal(&"reels_state", [0, 1, 2])
	await step(2)
	check(Game.casino.night_jackpots == 2, "a second visit could not earn a second Jackpot")
	check(Game.meeting.lit, "two Jackpots in a Night did not light the back room")
	park(ball, SAFE_POINT)
	await wait(0.1)
	print("        jackpot %s clean | idle rate %s/s | back room lit after %d"
			% [paid.text(), rate.text(), Game.meeting.jackpots_tonight])
	finish()


## 3 — FAMILY MEETING: a second NAMED guy joins, all dirty doubles, the back room pays a
## growing jackpot, and when one of them drains it is HIS guy who goes inside.
func _s3_family_meeting() -> void:
	begin("family meeting: two guys, x2 dirty, growing back room, right man pinched")
	Game.heat.reset()
	var primary := TableAPI.ball(table)
	park(primary, SAFE_POINT)
	await step(2)
	check(Game.meeting.lit, "the back room should still be lit from the Jackpots")

	var lineup_before := main.night.lineup.size()
	var on_deck := main.night.current_guy()
	var baseline := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})

	_pinched.clear()
	table.emit_signal(&"backroom_entered")
	await step(2)

	check(Game.meeting.active, "the back room did not start the Meeting")
	check(not Game.meeting.lit, "starting the Meeting did not spend the light")
	check(Balls.count() == 2, "%d balls live, expected 2" % Balls.count())
	var second := extra_ball()
	check(second != null, "no second ball was served")
	if second == null or not Game.meeting.active:
		finish()
		return
	park(second, SAFE_POINT_B)
	await step(2)

	var second_guy := Balls.guy_for(second)
	check(not second_guy.is_empty(), "the second ball is not carrying a guy")
	check(int(second_guy.get("id", -1)) != int(on_deck.get("id", -2)),
			"the second ball is the same man as the first")
	check(String(second_guy.get("name", "")) != "", "the second guy has no name")
	check(main.night.extras.size() == 1, "the Night did not record the extra man")
	check(main.night.lineup.size() == lineup_before, "the Meeting ate a line-up slot")
	check(int(Balls.guy_for(primary).get("id", -1)) == int(on_deck.get("id", -2)),
			"the first ball lost its guy when the second arrived")

	var doubled := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	check(doubled.equals_approx(baseline.mul(FamilyMeeting.DIRTY_MULT), 1e-6),
			"dirty paid %s during the Meeting, expected %s (x%d)"
			% [doubled.text(), baseline.mul(FamilyMeeting.DIRTY_MULT).text(),
				int(FamilyMeeting.DIRTY_MULT)])

	# Back-room re-entry pays clean, and grows.
	var rate := Game.stats.idle_rate_total()
	var clean_before := Game.wallet.clean
	table.emit_signal(&"backroom_entered")
	await step(2)
	var first_pay := Game.wallet.clean.sub_clamped(clean_before)
	var want_first := rate.mul(FamilyMeeting.JACKPOT_MINUTES * 60.0)
	check(first_pay.equals_approx(want_first, 1e-4),
			"the first back-room jackpot paid %s, expected %s"
			% [first_pay.text(), want_first.text()])
	clean_before = Game.wallet.clean
	table.emit_signal(&"backroom_entered")
	await step(2)
	var second_pay := Game.wallet.clean.sub_clamped(clean_before)
	check(second_pay.equals_approx(first_pay.mul(FamilyMeeting.JACKPOT_GROWTH), 1e-4),
			"the back room paid %s then %s — it is supposed to grow by half each time"
			% [first_pay.text(), second_pay.text()])
	check(Balls.count() == 2, "a back-room jackpot restarted the Meeting")

	# The 8 s grace first: a second guy who arrives mid-shot is not thrown straight away.
	_pinched.clear()
	await drain(second)
	check(_pinched.is_empty(), "the Meeting's grace did not cover the second ball")
	check(Balls.count() == 2, "the saved ball was not put back (%d live)" % Balls.count())
	check(Game.meeting.active, "a grace save ended the Meeting")
	var saved := extra_ball()
	check(saved != null and saved != second, "the save did not serve a fresh ball")
	if saved != null:
		check(int(Balls.guy_for(saved).get("id", -1)) == int(second_guy.get("id", -2)),
				"the saved ball came back carrying somebody else")
		park(saved, SAFE_POINT_B)
	await wait(NightController.RESERVE_SAVE_SECONDS + 0.3)

	# Now for real: HE goes inside, the Meeting ends, the Night carries on.
	_pinched.clear()
	await drain(saved)
	check(_pinched.size() == 1, "%d guys were pinched by one drain" % _pinched.size())
	if not _pinched.is_empty():
		check(int(_pinched[0].get("id", -1)) == int(second_guy.get("id", -2)),
				"the drain pinched %s, but %s was the man on that ball"
				% [String(_pinched[0].get("name", "?")), String(second_guy.get("name", "?"))])
		check(String(_pinched[0]["state"]) == Bench.STATE_HOLDING, "the pinched guy is not inside")
	check(not Game.meeting.active, "one ball left did not end the Meeting")
	check(Balls.count() == 1, "%d balls after the drain" % Balls.count())
	check(Game.state == &"night", "the Night ended when the extra ball drained")
	check(int(main.night.current_guy().get("id", -1)) == int(on_deck.get("id", -2)),
			"the line-up moved on when it was not the line-up's man who drained")
	var plain := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	check(plain.equals_approx(baseline, 1e-6),
			"dirty is still doubled after the Meeting (%s vs %s)" % [plain.text(), baseline.text()])
	check(Game.bench.find_by_id(int(second_guy["id"]))["state"] == Bench.STATE_HOLDING,
			"the second guy is not on the Bench's holding list")

	# ...and the survivor is still the man the HUD names.
	check(main.night.guys_lost == 1, "guys_lost is %d after one drain" % main.night.guys_lost)
	print("        second guy %s (%s) | back room %s -> %s | line-up intact"
			% [String(second_guy.get("name", "?")),
				GuyTraits.label(String(second_guy.get("trait", ""))),
				first_pay.text(), second_pay.text()])
	park(TableAPI.ball(table), SAFE_POINT)
	finish()


## 4 — the tote board. The ticket is the spinner's count, the last digit pays x6 FLAT dirty
## off the spinner's BASE line and the exact number pays x80 clean (balance-sim ruling: the
## take is already post-multiplier, so pricing off it put the Heat band on the same money
## twice, and paying it back through the money path did it a third time).
func _s4_wire_draws() -> void:
	begin("the wire: 90s draws, spinner ticket, x6 flat off the BASE line and x80 clean")
	Game.heat.reset()
	check(Game.stats.hardware_unlocked(&"wire_bank"), "the fixture has no tote board")
	await spin_the_lane(2)
	var spins := int(TableAPI.call_if(table, "spinner_spins", [], 0))
	check(spins > 0, "the numbers lane never turned")
	var spinner_base := Game.night_group_base_dirty(&"spinner")
	check(spinner_base.is_positive(), "the spinner earned nothing to price a ticket off")

	# The Night's own clock draws it: nudge the timer rather than waiting 90 seconds.
	_wire_events.clear()
	Game.wire.time_left = 0.01
	await wait(0.15)
	check(_wire_events.size() == 1, "the 90 s clock drew %d times" % _wire_events.size())
	if _wire_events.is_empty():
		finish()
		return
	var drawn: Dictionary = _wire_events[0]
	check(int(drawn["ticket"]) == spins % WireDraws.NUMBERS,
			"ticket %d, but the spinner has turned %d times" % [int(drawn["ticket"]), spins])
	check(int(drawn["number"]) >= 0 and int(drawn["number"]) < WireDraws.NUMBERS,
			"the board drew %d" % int(drawn["number"]))
	check(Game.wire.draws == 1, "the Night's book says %d draws" % Game.wire.draws)

	# Both winning branches, priced against the same base.
	var base := WireDraws.base_for(Game.night_group_base_dirty(&"spinner"))
	var last_digit_ticket := (Game.wire.peek() + 10) % WireDraws.NUMBERS
	var dirty_before := Game.wallet.dirty
	var clean_before := Game.wallet.clean
	_wire_events.clear()
	Game.wire_draw(last_digit_ticket)
	await step(1)
	var hit: Dictionary = _wire_events[0]
	check(StringName(hit["hit"]) == WireDraws.HIT_LAST,
			"ticket %d against %d was not a last-digit hit"
			% [last_digit_ticket, int(hit["number"])])
	check(not bool(hit["clean"]), "a last-digit hit paid clean")
	check(Game.wallet.clean.equals_approx(clean_before, 1e-9), "and it moved clean cash")
	check(Game.wallet.dirty.cmp(dirty_before) > 0, "the x6 never landed")
	check(money(hit["won"]).equals_approx(base.mul(WireDraws.LAST_DIGIT_MULT), 1e-4),
			"the x6 was priced off %s, expected the spinner's BASE line %s"
			% [money(hit["won"]).div(WireDraws.LAST_DIGIT_MULT).text(), base.text()])
	check(money(hit["paid"]).equals_approx(money(hit["won"]), 1e-6),
			"a dirty hit paid %s against a ticket worth %s — it went back through the money path"
			% [money(hit["paid"]).text(), money(hit["won"]).text()])

	var exact_ticket := Game.wire.peek()
	base = WireDraws.base_for(Game.night_group_base_dirty(&"spinner"))
	clean_before = Game.wallet.clean
	_wire_events.clear()
	Game.wire_draw(exact_ticket)
	await step(1)
	var exact: Dictionary = _wire_events[0]
	check(StringName(exact["hit"]) == WireDraws.HIT_EXACT, "the exact number was not an exact hit")
	check(bool(exact["clean"]), "an exact number paid dirty")
	check(Game.wallet.clean.cmp(clean_before) > 0, "the x80 never reached clean")
	check(money(exact["paid"]).equals_approx(base.mul(WireDraws.EXACT_MULT), 1e-4),
			"the exact number paid %s, expected x80 of %s"
			% [money(exact["paid"]).text(), base.text()])
	check(Game.wire.exacts == 1, "the book did not record the exact")
	print("        %d spins -> ticket %02d | base line %s | x6 %s flat dirty | x80 %s clean"
			% [spins, spins % WireDraws.NUMBERS, spinner_base.text(),
				money(hit["won"]).text(), money(exact["paid"]).text()])
	finish()


## 5 — a Collection Round: three armed banks start a 25 s clock, the third collect pays its
## value again, ☆10 lands, and the back room lights up.
func _s5_collection_round() -> void:
	begin("collection round: all three, last pays double, +10 respect, lights the meeting")
	Game.heat.reset()
	Game.meeting.lit = false
	# Re-arm the round rather than wait out the 25 s clock the Night has already been running.
	Game.collection.begin_night()
	await wait(NightController.STOREFRONT_POLL + 0.15)
	check(Game.collection.active, "three armed storefronts did not start a round")
	if not Game.collection.active:
		finish()
		return
	check(Game.collection.time_left > CollectionRound.SECONDS - 1.0,
			"the round started with %.1fs on the clock" % Game.collection.time_left)

	var value := BigMoney.from_float(10_000.0)
	var respect_before := Game.respect
	table.emit_signal(&"storefront_collected", &"storefront_laundromat", value)
	await step(1)
	check(Game.collection.active, "one shop ended the round")
	check(Game.collection.collected_count() == 1, "the round is not counting shops")
	table.emit_signal(&"storefront_collected", &"storefront_pizzeria", value)
	await step(1)
	check(Game.collection.active, "two shops ended the round")

	var dirty_before := Game.wallet.dirty
	table.emit_signal(&"storefront_collected", &"storefront_pawn", value)
	await step(1)
	var bonus := Game.wallet.dirty.sub_clamped(dirty_before)
	check(not Game.collection.active, "the third shop did not finish the round")
	check(Game.collection.night_won == 1, "the round was not booked as perfect")
	check(bonus.is_positive(), "the last shop did not pay double")
	check(bonus.cmp(value) >= 0,
			"the double collection paid %s against a %s shop" % [bonus.text(), value.text()])
	check(Game.respect - respect_before == CollectionRound.RESPECT,
			"a perfect round paid %d respect, expected %d"
			% [Game.respect - respect_before, CollectionRound.RESPECT])
	check(Game.meeting.lit, "a perfect round did not light the Family Meeting")

	# Balance-sim ruling: the ☆ are once a NIGHT. A second perfect round still pays its double
	# and still lights the room; it just does not rank you up again.
	Game.collection.tick(CollectionRound.RETRIGGER_GAP + 0.1)
	check(Game.collection.on_all_armed(), "the block did not start a second round")
	respect_before = Game.respect
	dirty_before = Game.wallet.dirty
	for shop in [&"storefront_laundromat", &"storefront_pizzeria", &"storefront_pawn"]:
		table.emit_signal(&"storefront_collected", shop, value)
		await step(1)
	check(Game.collection.night_won == 2, "the second round was not booked as perfect")
	check(Game.wallet.dirty.cmp(dirty_before) > 0, "the second round paid no double")
	check(Game.respect == respect_before,
			"the second perfect round of the Night paid %d more ☆ — they are once a Night"
			% (Game.respect - respect_before))

	# The lapse branch: the clock runs out and it simply costs nothing.
	var won_before := Game.collection.total_won
	Game.collection.begin_night()
	await wait(NightController.STOREFRONT_POLL + 0.15)
	check(Game.collection.active, "the block did not re-arm")
	Game.collection.tick(CollectionRound.SECONDS + 0.1)
	await step(2)
	check(not Game.collection.active, "the round never lapsed")
	check(Game.collection.total_won == won_before, "a lapsed round was booked as a win")
	check(Game.collection.collected_count() == 0, "the lapsed round kept its shops")
	print("        double collection %s | +%d respect | meeting lit: %s"
			% [bonus.text(), CollectionRound.RESPECT, str(Game.meeting.lit)])
	finish()


## 6 — the Cooler. Five straight losing spins and the house apologises on the next win.
func _s6_cooler_pity() -> void:
	begin("the cooler: five losses, then the next win pays +50%")
	Game.heat.reset()
	Game.wallet.earn_dirty(BigMoney.from_float(500_000.0))
	Game.casino.loss_streak = 0
	Game.casino.armed = 1.0

	_casino_events.clear()
	for i in range(Casino.CasinoRules.COOLER_STREAK):
		table.emit_signal(&"roulette_landed", HOUSE_POCKET, true)
		await step(2)
	check(_casino_events.size() == Casino.CasinoRules.COOLER_STREAK,
			"%d of five losing spins were resolved" % _casino_events.size())
	check(Game.casino.loss_streak == Casino.CasinoRules.COOLER_STREAK,
			"the streak reads %d after five losses" % Game.casino.loss_streak)

	_casino_events.clear()
	table.emit_signal(&"roulette_landed", PLAYER_POCKET, false)
	await step(2)
	var win: Dictionary = _casino_events[0]
	check(bool(win["cooler"]), "the sixth spin did not fire the Cooler")
	var want := Casino.payout_rate(Game.stats) * (1.0 + Casino.cooler_bonus(Game.stats))
	check(absf(float(win["multiplier"]) - want) < 1e-6,
			"the apology paid x%.3f, expected x%.3f" % [float(win["multiplier"]), want])
	check(Game.casino.loss_streak == 0, "a win did not clear the streak")

	# The High Roller ladder rides the very next BET and is spent on it (balance-sim ruling:
	# ×5 on a payout is an EV multiplier the wheel's odds were never told about; ×5 on the bet
	# is the variance a High Roller is actually buying).
	var ev_before := Casino.expected_value(Game.stats)
	var table_stake := Casino.stake_for(Game.wallet.dirty, Game.rank)
	table.emit_signal(&"high_roller_held", 3)
	await step(2)
	check(is_equal_approx(Game.casino.armed_multiplier(), 5.0),
			"a full hold armed x%.1f" % Game.casino.armed_multiplier())
	check(is_equal_approx(Casino.expected_value(Game.stats), ev_before),
			"an armed ladder moved the wheel's EV from %.4f to %.4f"
			% [ev_before, Casino.expected_value(Game.stats)])
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", PLAYER_POCKET, false)
	await step(2)
	var armed: Dictionary = _casino_events[0]
	check(money(armed["staked"]).equals_approx(table_stake.mul(5.0), 1e-4),
			"the armed bet staked %s against a table stake of %s"
			% [money(armed["staked"]).text(), table_stake.text()])
	check(absf(float(armed["multiplier"]) - Casino.payout_rate(Game.stats)) < 1e-6,
			"the armed win paid x%.3f — the ladder must not touch the payout"
			% float(armed["multiplier"]))
	check(is_equal_approx(Game.casino.armed_multiplier(), 1.0), "the ladder was not spent")
	print("        cooler x%.2f | high roller staked %s (x5 of %s) | casino book: staked %s won %s"
			% [float(win["multiplier"]), money(armed["staked"]).text(), table_stake.text(),
				Game.casino.night_staked.text(), Game.casino.night_won.text()])
	finish()


## 7 — a trait where it actually bites: Slippery buys one outlane escape a Night, spent
## before any ball-save charge, and only once (docs/01 §4).
func _s7_slippery_outlane() -> void:
	begin("traits: Slippery slips the outlane once, then he is just a guy")
	Game.heat.reset()
	check(main.night.saves_left == 0,
			"the fixture carries %d ball-save charges — this scenario needs none"
			% main.night.saves_left)
	var guy := main.night.current_guy()
	check(not guy.is_empty(), "nobody is on the table")
	if guy.is_empty():
		finish()
		return
	# The guy dict is the Bench's own, so this is the same as having hired him Slippery.
	guy["trait"] = GuyTraits.SLIPPERY
	Game.set_fielded([guy])
	check(GuyTraits.dirty_mult_for(Game.fielded) == 1.0, "Slippery is not a money trait")

	var lost_before := main.night.guys_lost
	_pinched.clear()
	await drain_at(TableAPI.ball(table), OUTLANE_POINT)
	await wait(0.9)
	check(_pinched.is_empty(), "the Slippery guy did not slip the outlane")
	check(main.night.guys_lost == lost_before, "he was pinched anyway")
	check(Game.state == &"night", "the Night ended on a saved outlane drain")
	var back := TableAPI.ball(table)
	check(back != null, "the escape did not put a ball back")
	if back == null:
		finish()
		return
	check(int(main.night.current_guy().get("id", -1)) == int(guy.get("id", -2)),
			"the escape handed the ball to somebody else")

	# The same drain a second time: the escape is spent, and he goes inside.
	await wait(NightController.RESERVE_SAVE_SECONDS + 0.3)
	_pinched.clear()
	await drain_at(TableAPI.ball(table), OUTLANE_POINT)
	await wait(0.3)
	check(_pinched.size() == 1, "%d guys pinched on the second outlane drain" % _pinched.size())
	if not _pinched.is_empty():
		check(int(_pinched[0].get("id", -1)) == int(guy.get("id", -2)),
				"the wrong man went inside")
	check(main.night.guys_lost == lost_before + 1, "the Night did not count the pinch")
	print("        %s (%s) slipped once, then went inside" % [String(guy.get("name", "?")),
			GuyTraits.label(GuyTraits.SLIPPERY)])
	finish()


## 8 — the Influence nodes bite. Loaded Dice and Eddie Odds buy edge points, `coolers_fired`
## doubles the apology, and `fronts.comps` puts the first stake of the Night on the house
## (specs/m2-content.md §1/§3). Influence buys the odds, never the outcome (P2).
func _s8_influence_nodes() -> void:
	begin("influence: edge points, a doubled Cooler and a comped stake")
	Game.heat.reset()
	var base_payout := Casino.payout_rate(Game.stats)
	var base_ev := Casino.expected_value(Game.stats)
	check(is_equal_approx(base_payout, Casino.CasinoRules.PAYOUT),
			"the wheel should still be at its base 1.48x, reads %.3f" % base_payout)

	for i in range(12):
		Game.buy_upgrade("influence.loaded_dice", BigMoney.zero())
	var bought_payout := Casino.payout_rate(Game.stats)
	var bought_ev := Casino.expected_value(Game.stats)
	check(bought_payout > base_payout,
			"Loaded Dice bought no payout at all (%.3f)" % bought_payout)
	check(bought_payout <= Casino.CasinoRules.PAYOUT_MAX + 1e-9,
			"the payout ran past the design ceiling to %.3f" % bought_payout)
	check(bought_ev > base_ev, "the edge did not move the EV")
	check(Game.stats.casino_edge_add() > 0.0, "Stats reports no edge for an owned node")
	# Balance-sim ruling: the edge is bought in PAYOUT only. A pocket is worth +18.5% EV in one
	# purchase against a payout point's +0.625%, so no shipped node moves the wheel itself.
	check(Game.stats.casino_player_pockets() == Stats.CASINO_POCKETS_BASE,
			"a maxed Loaded Dice repainted the wheel to %d of 8"
			% Game.stats.casino_player_pockets())
	check(is_equal_approx(bought_ev - base_ev,
			float(Casino.CasinoRules.PLAYER_POCKETS) / float(Casino.CasinoRules.POCKETS)
			* Game.stats.casino_edge_add()),
			"%d edge points moved the EV by %.4f, not by 5/8 of themselves"
			% [int(round(Game.stats.casino_edge_add() * 100.0)), bought_ev - base_ev])

	# The odds are what moved, not the wheel: a house pocket still takes the stake.
	Game.wallet.earn_dirty(BigMoney.from_float(200_000.0))
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", HOUSE_POCKET, true)
	await step(2)
	check(not money(_casino_events[0]["won"]).is_positive(),
			"buying edge started paying out house pockets")

	Game.buy_upgrade("influence.coolers_fired", BigMoney.zero())
	check(is_equal_approx(Casino.cooler_bonus(Game.stats), Casino.CasinoRules.COOLER_BONUS_FIRED),
			"coolers_fired did not double the apology")

	# Comps: the first stake of a Night is the house's money.
	Game.buy_upgrade("fronts.comps", BigMoney.zero())
	Game.casino.begin_night(Casino.comps_for(Game.stats))
	check(Game.casino.comps_left == Casino.CasinoRules.COMPS_PER_NIGHT,
			"a comped career opened the Night with %d free stakes" % Game.casino.comps_left)
	var dirty_before := Game.wallet.dirty
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", PLAYER_POCKET, false)
	await step(2)
	var comped: Dictionary = _casino_events[0]
	check(bool(comped["comped"]), "the first stake of the Night was not comped")
	check(not money(comped["staked"]).is_positive(), "a comped stake was booked against the player")
	check(money(comped["won"]).is_positive(), "a comped bet did not pay")
	check(Game.wallet.dirty.cmp(dirty_before) >= 0,
			"the comped stake came out of the wallet anyway")

	dirty_before = Game.wallet.dirty
	_casino_events.clear()
	table.emit_signal(&"roulette_landed", HOUSE_POCKET, true)
	await step(2)
	check(not bool(_casino_events[0]["comped"]), "the house comped a second stake")
	check(Game.wallet.dirty.cmp(dirty_before) < 0, "the second stake was free too")
	print("        payout %.3f -> %.3f | EV %.4f -> %.4f | pockets %d/%d | comps %d"
			% [base_payout, bought_payout, base_ev, bought_ev,
				Casino.player_pockets(Game.stats), Casino.CasinoRules.POCKETS,
				Casino.CasinoRules.COMPS_PER_NIGHT])
	finish()
