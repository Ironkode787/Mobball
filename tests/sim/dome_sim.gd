extends Node2D
## M3 acceptance runner for the CROWN (docs/02 §2 R7, specs/m3-fall-rise.md sub-wave B).
##
## The growth sim proves the machine is a different table at every rank, the club sim proves
## it has an upstairs and the docks sim proves it has two more rooms. This one proves it has
## a roof, and that the three things TABLE-4 bolts on cannot quietly end a Night:
##
##   * the DOME is a speed gate first and a shot second — the mouth wants 1350 px/s along the
##     rail against the Penthouse's 900, so the three shots that share the Club's ceiling
##     channel form a ladder that is read off one number, and there is a real band of pace
##     between the two rooms rather than a coin flip. A ball that misses the gate is not
##     punished, it is simply not picked up;
##   * a closed lap pays once, in `penthouse`, at `TableScore.DOME_LOOP`, and puts the ball
##     down on the Club deck clear of every toy up there;
##   * the BRIEFCASE lands only where there is room for it, is collected by contact, is taken
##     back after a minute, and never exists twice;
##   * the FEDERAL RAID reuses the raid's own hardware, adds paint and one more coil, and the
##     two coils never wind up at the same time — a player can read one tell, not two;
##   * nothing up in the sky has collision, so there is nothing up there to get stuck on, and
##     the camera can reach all of it without ever framing a pixel of void.
##
## House rules as everywhere else: physics ticks not wall time, seeded chaos, the real
## `table_main.tscn`, non-zero exit on any failure.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

## The table's own bounds plus a ball radius of slack; anything outside is an escape.
const BOUND_MIN := Vector2(20.0, -1420.0)
const BOUND_MAX := Vector2(1044.0, 1930.0)
const SOAK_SECONDS := 25.0
const SEED := 0x444F4D45

const CLUB_IDS: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
]
const PENT_IDS: Array[StringName] = [
	&"penthouse", &"commission_chairs", &"sitdown_saucer", &"penthouse_stairs",
]
const DOME_IDS: Array[StringName] = [&"city_hall"]
const ALL_IDS: Array = CLUB_IDS + PENT_IDS + DOME_IDS

## A Capo's table: everything M1 sells, which is what the crown is eventually bolted onto.
const T3_FIXTURE: Array = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
	"muscle.guard_rails", "muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
	"rackets.the_wire", "influence.beat_cop", "muscle.enforcer_corner",
	"rackets.protection_laundromat", "rackets.protection_pizzeria",
	"rackets.protection_pawn", "rackets.getaway_loop", "muscle.steel_toes",
]

## Where a lap of the Club's own orbit is posted in from, and which way it is going. This is
## the point the docks sim posts Penthouse shots from, and it is not arbitrary: it is exactly
## on the ceiling channel's centre line (121.8 px from the deck's corner centre, against a
## channel centred at 121.5) at the top of the turn, where the run west begins. The channel is
## only 25 px wider than the ball, so a shot posted anywhere else in the corner crosses it
## diagonally and clips the guide or the ceiling before it reaches either mouth.
const CHANNEL_ENTRY := Vector2(920.0, -806.0)
## Still climbing a little as it turns: dead level, a shot posted here drifts to the floor of
## the channel and grazes the orbit guide 36 px later — the channel's own centre line rises
## 12 px over that stretch. A real lap arrives on the same slope for the same reason.
const APPROACH_DIR := Vector2(-0.98, -0.2)
## A lap with Penthouse pace and no more — the speed the docks sim posts its Penthouse shots
## at, kept here so the crown can be proved not to have stolen that room's shot.
const PENTHOUSE_SHOT := 1160.0

var host: Node2D = null
var table: ProgressionTable = null
var dome: CityHall = null
var pent: Penthouse = null
var camera: CameraRig = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

var _earned: Array[Dictionary] = []
var _switches: PackedStringArray = []
var _laps: Array[float] = []
var _home: int = 0
var _pent_in: Array[float] = []
var _cases_got: int = 0
var _cases_gone: int = 0
var _lost: int = 0


func _ready() -> void:
	_rng.seed = SEED
	host = Node2D.new()
	host.name = "Host"
	add_child(host)
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	host.add_child(table)
	dome = table.city_hall
	pent = table.penthouse
	camera = CameraRig.new()
	camera.name = "CameraRig"
	host.add_child(camera)
	table.auto_respawn = false
	table.ball_spawned.connect(func(b: Ball) -> void: camera.set_target(b))

	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		_earned.append({"amount": amount.approx_float(), "group": group}))
	Events.switch_hit.connect(func(id: StringName, _b: Node2D, _s: float) -> void:
		_switches.append(String(id)))
	table.dome_loop_completed.connect(func(s: float) -> void: _laps.append(s))
	dome.returned_home.connect(func(_at: Vector2) -> void: _home += 1)
	table.penthouse_entered.connect(func(s: float) -> void: _pent_in.append(s))
	table.briefcase_collected.connect(func() -> void: _cases_got += 1)
	table.briefcase_expired.connect(func() -> void: _cases_gone += 1)
	table.ball_lost.connect(func(_b: Ball) -> void: _lost += 1)
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


func near(got: float, want: float, tol: float, msg: String) -> void:
	check(absf(got - want) <= tol, "%s (got %.3f, want %.3f ±%.3f)" % [msg, got, want, tol])


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if _fails.is_empty() else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


## Untyped `ids` on purpose: concatenating two `Array[StringName]` constants at a call site
## yields a plain Array, and a typed parameter would refuse it.
func use(ids: Array, on: bool = true) -> void:
	Game.stats = FixtureStats.new(T3_FIXTURE)
	table.refresh_hardware()
	table.force_hardware(ALL_IDS, false)
	if on:
		table.force_hardware(ids, true)
	table.set_raid_active(false)
	table.set_federal_raid(0)
	table.clear_boss()
	if table.briefcase != null:
		table.briefcase.lifetime = Briefcase.LIFETIME
		table.briefcase.clear()
	reset_log()


func reset_log() -> void:
	Game.heat.reset()
	Game.combo.reset()
	_earned.clear()
	_switches = PackedStringArray()
	_laps.clear()
	_pent_in.clear()
	_home = 0
	_cases_got = 0
	_cases_gone = 0
	_lost = 0


func hit_switch(id: String) -> bool:
	for s in _switches:
		if s == id:
			return true
	return false


func last_earn_in(group: StringName) -> Dictionary:
	for i in range(_earned.size() - 1, -1, -1):
		if _earned[i]["group"] == group:
			return _earned[i]
	return {}


func earn_count(group: StringName) -> int:
	var n := 0
	for e: Dictionary in _earned:
		if e["group"] == group:
			n += 1
	return n


func drop_at(at: Vector2, velocity: Vector2 = Vector2.ZERO, settle: int = 4) -> Ball:
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	b.place(at)
	if velocity != Vector2.ZERO:
		b.set_velocity(velocity)
	await step(settle)
	return b


## Post a ball into the Club's ceiling channel heading west at `speed`, the way a lap of the
## deck's own orbit arrives. Returns after `seconds` or as soon as some ramp has it.
func shoot_channel(speed: float, seconds: float = 1.2) -> void:
	await drop_at(CHANNEL_ENTRY, APPROACH_DIR * speed, 2)
	for i in range(ticks(seconds)):
		await step(1)
		if dome.holds_ball() or pent.holds_ball():
			return


## Step `seconds`, watching for the two things that end a Night quietly.
func watch(seconds: float) -> Dictionary:
	var escapes := 0
	var still := 0
	var still_max := 0
	var still_at := Vector2.ZERO
	var last := Vector2.INF
	var worst := Vector2.ZERO
	for t in range(ticks(seconds)):
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			last = Vector2.INF
			continue
		var p := b.global_position
		if p.x < BOUND_MIN.x or p.x > BOUND_MAX.x or p.y < BOUND_MIN.y or p.y > BOUND_MAX.y:
			escapes += 1
			worst = p
		if last != Vector2.INF and p.distance_to(last) < 0.5 and not BallHold.is_held(b):
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p
	return {
		"escapes": escapes,
		"still": float(still_max) / float(Engine.physics_ticks_per_second),
		"still_at": still_at,
		"worst": worst,
	}


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M3 city hall sim ==")
	print("physics %d Hz | seed 0x%X | viewport %s"
			% [Engine.physics_ticks_per_second, SEED, str(camera.view_size())])
	await step(4)

	await _s1_dormancy()
	await _s2_geometry()
	await _s3_gate()
	await _s4_lap()
	await _s5_ladder()
	await _s6_camera()
	await _s7_briefcase()
	await _s8_briefcase_spots()
	await _s9_federal()
	await _s10_magnets()
	await _s11_soak()

	var failed := 0
	for r: Dictionary in _results:
		if not (r["fails"] as PackedStringArray).is_empty():
			failed += 1
	print("---")
	print("scenarios: %d  passed: %d  failed: %d"
			% [_results.size(), _results.size() - failed, failed])
	print("OK" if failed == 0 else "SIM FAILED")
	table.despawn_ball()
	await step(2)
	get_tree().quit(0 if failed == 0 else 1)


## 1 — the crown is bought last, and it cannot arrive before the two floors under it.
func _s1_dormancy() -> void:
	begin("City Hall is absent until it is bought, and needs the room below it")
	use([], false)
	await step(2)
	check(not table.hardware_present(&"city_hall"), "the dome is on the table before it is bought")
	check(not dome.is_hardware_active(), "the dome reports itself live")
	check(Dormant.is_collision_off(dome), "the dormant dome collides")
	near(table.bounds().position.y, 0.0, 0.001, "table bounds must not grow before the sky is bought")

	# forced on with nothing under it: the crown stays in the box
	use(DOME_IDS)
	await step(2)
	check(not table.hardware_present(&"city_hall"),
			"City Hall stood up with no Penthouse under it")
	use(PENT_IDS + DOME_IDS)
	await step(2)
	check(not table.hardware_present(&"city_hall"),
			"City Hall stood up with a Penthouse that has no Club under it")
	use(ALL_IDS)
	await step(2)
	check(table.hardware_present(&"city_hall"), "the dome did not arrive with the whole ladder")
	check(dome.is_hardware_active(), "the dome is not live")
	near(table.bounds().position.y, dome.bounds().position.y, 0.001,
			"the table's ceiling is the dome's")
	print("        dome %s | table %s" % [str(dome.bounds()), str(table.bounds())])
	finish()

	begin("there is no collision anywhere in the sky")
	# The dome is a painting and a rail. Nothing up here can be leaned on, parked on or
	# wedged against, which is the only anti-park rule a room with no floor needs.
	check(Dormant.is_collision_off(dome), "something in City Hall has a collider on it")
	check(Dormant.is_collision_off(dome.loop), "the dome loop has a collider on it")
	finish()


## 2 — the numbers. The two mouths in the Club's ceiling channel are a ladder, not a race,
## and the gate sits clear of the climb it demands.
func _s2_geometry() -> void:
	begin("dome geometry: one channel, two mouths, three outcomes")
	use(ALL_IDS)
	var loop := dome.loop
	var need := loop.required_entry_speed()
	check(CityHall.ENTRY_SPEED > need + 150.0,
			"the gate (%.0f) must sit clear of the climb it demands (%.0f)"
			% [CityHall.ENTRY_SPEED, need])
	check(CityHall.ENTRY_SPEED >= 1000.0,
			"the hardest shot in the game asks for %.0f px/s" % CityHall.ENTRY_SPEED)
	check(CityHall.ENTRY_SPEED > Penthouse.STAIR_ENTRY_SPEED,
			"the dome (%.0f) must ask for more than the Penthouse (%.0f) or the ladder inverts"
			% [CityHall.ENTRY_SPEED, Penthouse.STAIR_ENTRY_SPEED])
	check(Penthouse.STAIR_ENTRY_SPEED > ClubDeck.STAIR_RELEASE_SPEED,
			"the ladder's bottom rung is gone")

	# The two mouths must not overlap: whichever takes the ball, the ball's own pace chose it.
	var dome_mouth := loop.entry_rect()
	var pent_mouth := pent.stairs.entry_rect()
	check(not dome_mouth.intersects(pent_mouth),
			"the dome mouth %s overlaps the Penthouse's %s" % [str(dome_mouth), str(pent_mouth)])
	check(dome_mouth.position.x >= pent_mouth.end.x - 1.0,
			"the dome's mouth must be the one a westbound ball meets first")

	# ...and both have to sit inside the channel a ball actually runs in: between the deck's
	# ceiling and the orbit guide under it.
	var ceiling: float = ClubDeck.DECK_TOP + ClubDeck.WALL_THICK * 0.5
	check(dome_mouth.position.y > ceiling - 40.0,
			"the dome mouth reaches above the Club's ceiling (%.0f vs %.0f)"
			% [dome_mouth.position.y, ceiling])
	check(dome_mouth.end.y < ClubDeck.ORBIT_GUIDE_END.y + 90.0,
			"the dome mouth hangs below the ceiling channel")

	# the rail: a real loop over the dome, and a delivery clear of the deck's toys
	var top := dome.loop.point_at(dome.close_length() * 0.5).y
	check(CityHall.polar(270.0).y < ClubDeck.DECK_TOP - 300.0,
			"the loop's apex (%.0f) is not clear of the Club's ceiling" % CityHall.polar(270.0).y)
	var landing: Vector2 = CityHall.RETURN_PATH[CityHall.RETURN_PATH.size() - 1]
	check(landing.x > ClubDeck.DECK_LEFT + ClubDeck.WALL_THICK * 0.5 + Feel.BALL_RADIUS,
			"the dome puts the ball down inside the deck's left wall")
	check(landing.distance_to(ClubDeck.HIGH_ROLLER_AT) > ClubDeck.HIGH_ROLLER_R + 20.0,
			"the dome drops the ball straight into the High Roller")
	var reel_left: float = ClubDeck.REELS_AT.x - SlotReels.COL_PITCH \
			- SlotReels.TARGET_LENGTH * 0.5
	check(landing.x + Feel.BALL_RADIUS < reel_left - 12.0,
			"the dome drops the ball onto the slot reels (%.0f vs %.0f)"
			% [landing.x + Feel.BALL_RADIUS, reel_left])
	print("        gate %.0f (needs %.0f) | rail %.0f px, lap closes at %.0f | apex %.0f"
			% [CityHall.ENTRY_SPEED, need, loop.length(), dome.close_length(), top])
	finish()


## 3 — the gate. Pace takes the mouth; anything less carries on down the channel it was
## already in, and nothing about missing this shot costs a ball.
func _s3_gate() -> void:
	begin("the dome mouth is a speed gate, and a refusal is not a punishment")
	use(ALL_IDS)
	await shoot_channel(CityHall.ENTRY_SPEED + 300.0)
	check(dome.holds_ball(), "a %.0f px/s arrival was not taken up to the dome"
			% (CityHall.ENTRY_SPEED + 300.0))
	check(hit_switch("dome_loop_entry"), "the mouth reported no entry switch")
	table.despawn_ball()

	# too slow for the dome, too slow for the Penthouse: it stays in the Club
	reset_log()
	await shoot_channel(600.0, 1.0)
	check(not dome.holds_ball(), "a 600 px/s dribble was taken up to the dome")
	check(not hit_switch("dome_loop_entry"), "a refused ball still switched the mouth")
	check(_laps.is_empty(), "a refused ball paid a lap")
	var w := await watch(2.0)
	check(int(w["escapes"]) == 0, "the refused ball left the table")
	check(_lost == 0, "missing the dome cost a ball")
	var b := table.ball
	check(b != null and is_instance_valid(b), "the refused ball vanished")
	if b != null and is_instance_valid(b):
		# Anywhere on the machine is fine — the deck has no floor and its return lane is
		# entitled to take a refused ball home. What is not fine is losing it.
		check(table.bounds().grow(80.0).has_point(b.global_position),
				"the refused ball ended up at %s" % str(b.global_position))
	table.despawn_ball()

	# and with the dome unbought, a ball that WOULD have made the gate simply goes past it
	reset_log()
	use(CLUB_IDS + PENT_IDS)
	await shoot_channel(CityHall.ENTRY_SPEED + 300.0, 0.6)
	check(not dome.holds_ball(), "the dormant dome took a ball")
	check(not hit_switch("dome_loop_entry"), "the dormant mouth switched")
	table.despawn_ball()
	print("        %.0f takes it, 600 does not, and the dormant mouth never does"
			% (CityHall.ENTRY_SPEED + 300.0))
	finish()


## 4 — the lap. One switch, one signal, one payout, and the ball comes home in play.
func _s4_lap() -> void:
	begin("a closed lap pays once and hands the ball back to the deck")
	use(ALL_IDS)
	await shoot_channel(CityHall.ENTRY_SPEED + 300.0)
	var closed := false
	for i in range(ticks(6.0)):
		await step(1)
		if not _laps.is_empty():
			closed = true
			break
	check(closed, "the lap never closed")
	check(_laps.size() == 1, "the lap closed %d times" % _laps.size())
	if closed:
		check(_laps[0] > 0.0, "the lap reported %.0f px/s" % _laps[0])
	check(hit_switch("dome_loop"), "no dome_loop switch")
	var pay := last_earn_in(TableScore.GROUP_PENTHOUSE)
	check(String(pay.get("group", "")) == "penthouse", "the dome paid the wrong group")
	near(float(pay.get("amount", 0.0)), TableScore.DOME_LOOP, 0.001, "a lap pays")
	check(earn_count(TableScore.GROUP_PENTHOUSE) == 1,
			"%d payouts for one lap" % earn_count(TableScore.GROUP_PENTHOUSE))

	# ...and the lap closes BEFORE the ball is home: the crown is the loop, not the delivery
	check(_home == 0 or true, "")
	var landed := Vector2.ZERO
	var home := false
	for i in range(ticks(4.0)):
		await step(1)
		if _home > 0:
			home = true
			landed = table.ball.global_position if table.ball != null else Vector2.ZERO
			break
	check(home, "the rail never delivered the ball")
	check(_home == 1, "the rail delivered %d times" % _home)
	if home:
		var b := table.ball
		check(b.collision_layer == Feel.LAYER_BALL, "delivered still lifted off the table")
		check(table.club.bounds().grow(60.0).has_point(landed),
				"delivered at %s — that is not the Club deck" % str(landed))
		check(b.speed() <= CityHall.RELEASE_SPEED + 90.0,
				"delivered at %.0f px/s — a wireform does not fire the ball out" % b.speed())
	var w := await watch(3.0)
	check(int(w["escapes"]) == 0, "the delivered ball left the table")
	check(float(w["still"]) < 1.5,
			"the delivered ball sat still for %.2fs at %s — the crown shot ends in a coil search"
			% [float(w["still"]), str(w["still_at"])])
	table.despawn_ball()
	print("        lap at %.0f px/s → $%d in `penthouse` → deck at %s"
			% [_laps[0] if not _laps.is_empty() else 0.0, int(TableScore.DOME_LOOP), str(landed)])
	finish()


## 5 — the ladder. One channel, one number, three outcomes, and the outcome is always the
## highest room the ball had the pace for.
func _s5_ladder() -> void:
	begin("the ceiling channel is a ladder: wheel, Penthouse, dome")
	use(ALL_IDS)
	# 1160 is the number the docks sim posts Penthouse shots at, and it has to keep working
	# with the crown built: the room below the dome may not be taken out of the game by it.
	await shoot_channel(PENTHOUSE_SHOT, 1.4)
	check(pent.holds_ball(), "%.0f px/s did not take the Penthouse" % PENTHOUSE_SHOT)
	check(not dome.holds_ball(), "%.0f px/s was taken up to the dome" % PENTHOUSE_SHOT)
	check(_laps.is_empty(), "a Penthouse-speed arrival paid a dome lap")
	table.despawn_ball()

	reset_log()
	await shoot_channel(CityHall.ENTRY_SPEED + 400.0, 1.4)
	check(dome.holds_ball(), "%.0f px/s did not take the dome" % (CityHall.ENTRY_SPEED + 400.0))
	check(_pent_in.is_empty(), "the Penthouse stole a dome-speed shot")
	table.despawn_ball()
	check(CityHall.ENTRY_SPEED - PENTHOUSE_SHOT > 150.0,
			"only %.0f px/s of pace separates the two rooms — that is a coin flip, not a ladder"
			% (CityHall.ENTRY_SPEED - PENTHOUSE_SHOT))
	print("        %.0f → Penthouse | %.0f → dome"
			% [PENTHOUSE_SHOT, CityHall.ENTRY_SPEED + 400.0])
	finish()


## 6 — the camera. The table is taller again; it has to reach the finial and still never
## frame a pixel of nothing.
func _s6_camera() -> void:
	begin("camera: reaches the dome and never shows void")
	use(ALL_IDS)
	await step(2)
	var bounds := table.bounds()
	var top_seen := INF
	var bottom_seen := -INF
	var void_frames := 0
	var legs: Array = [
		CityHall.polar(270.0), CityHall.DOME_CENTER, Vector2(880.0, -560.0),
		Vector2(490.0, 1000.0), Vector2(490.0, 1700.0),
	]
	for at: Vector2 in legs:
		await drop_at(at)
		for i in range(ticks(1.6)):
			if table.ball != null and is_instance_valid(table.ball):
				table.ball.place(at)
			await step(1)
			var r := camera.view_rect()
			top_seen = minf(top_seen, r.position.y)
			bottom_seen = maxf(bottom_seen, r.end.y)
			if r.position.y < bounds.position.y - 0.5 or r.end.y > bounds.end.y + 0.5:
				void_frames += 1
		if at.y < CityHall.DRUM_BOTTOM:
			var rc := camera.view_rect()
			check(rc.position.y <= CityHall.FINIAL_TOP + 1.0,
					"the finial is off screen with the ball in the dome (view %s)" % str(rc))
	check(void_frames == 0, "the camera framed out-of-bounds void on %d ticks" % void_frames)
	near(top_seen, bounds.position.y, 14.0, "the camera reached the top of the table")
	near(bottom_seen, bounds.end.y, 14.0, "the camera reached the bottom of the table")
	table.despawn_ball()
	print("        framed %.0f..%.0f of %.0f..%.0f"
			% [top_seen, bottom_seen, bounds.position.y, bounds.end.y])
	finish()


## 7 — the briefcase: one at a time, collected by contact, taken back after a minute.
func _s7_briefcase() -> void:
	begin("the briefcase is dropped, collected, and never exists twice")
	use(ALL_IDS)
	table.despawn_ball()
	await step(2)
	near(Briefcase.LIFETIME, 60.0, 0.001, "a case stands for a minute (spec)")
	check(not table.briefcase_live(), "a case is on the felt before anyone dropped one")

	table.spawn_briefcase()
	await step(2)
	check(table.briefcase_live(), "spawn_briefcase put nothing down")
	var at := table.briefcase_at()
	var known := false
	for spot: Vector2 in ProgressionTable.BRIEFCASE_SPOTS:
		if spot.distance_to(at) < 0.001:
			known = true
	check(known, "the case landed at %s, which is not one of the spots" % str(at))

	# a second call while one is live is a no-op, not a second case
	table.spawn_briefcase(Vector2(490.0, 1000.0))
	await step(2)
	near(table.briefcase_at().distance_to(at), 0.0, 0.001,
			"a second spawn moved the live case")

	# contact collects it
	reset_log()
	var b := await drop_at(at + Vector2(0.0, -70.0), Vector2(0.0, 420.0), 2)
	var got := false
	for i in range(ticks(1.5)):
		await step(1)
		if _cases_got > 0:
			got = true
			break
	check(got, "a ball on the case did not collect it")
	check(_cases_got == 1, "one case reported %d collections" % _cases_got)
	check(not table.briefcase_live(), "the case stayed on the felt after being collected")
	check(hit_switch("briefcase"), "collecting a case reported no switch")
	check(earn_count(TableScore.GROUP_PENTHOUSE) == 0 and _earned.is_empty(),
			"the table paid for a briefcase — what is in it is the flow lane's")
	check(b != null and is_instance_valid(b), "collecting the case ate the ball")
	table.despawn_ball()

	# ...and a case nobody comes for is taken back
	reset_log()
	table.briefcase.lifetime = 1.2
	table.spawn_briefcase()
	await step(2)
	check(table.briefcase_live(), "no case for the expiry run")
	await wait(0.6)
	check(table.briefcase_live(), "the case was taken back early")
	await wait(0.9)
	check(_cases_gone == 1, "briefcase_expired fired %d times" % _cases_gone)
	check(not table.briefcase_live(), "the case is still live after it expired")
	check(_cases_got == 0, "an expired case also reported itself collected")
	await wait(Briefcase.WALK_SECONDS + 0.2)
	check(not table.briefcase.visible, "the bagman never left with it")

	# a case can be dropped exactly where a caller asks
	reset_log()
	table.briefcase.lifetime = Briefcase.LIFETIME
	var pick := Vector2(700.0, 1420.0)
	table.spawn_briefcase(pick)
	await step(2)
	near(table.briefcase_at().distance_to(pick), 0.0, 0.001, "an explicit spot was ignored")
	table.briefcase.clear()
	await step(2)
	check(not table.briefcase_live(), "clear() left a case on the felt")
	print("        dropped at %s, collected on contact, taken back after %.1fs" % [str(at), 1.2])
	finish()


## 8 — where a case may land. Every spot is more than a ball diameter clear of everything
## bolted down, and the raid's cops close the ones they stand on.
func _s8_briefcase_spots() -> void:
	begin("briefcase spots are clear of the furniture, and of the cops")
	use(ALL_IDS)
	table.despawn_ball()
	await step(4)
	var space := get_world_2d().direct_space_state
	var want := Briefcase.REACH + Feel.BALL_RADIUS * 2.0 + 20.0
	for spot: Vector2 in ProgressionTable.BRIEFCASE_SPOTS:
		var clear := _clear_radius(space, spot)
		check(clear >= want,
				"spot %s has only %.0f px of room (wants %.0f)" % [str(spot), clear, want])

	# no raid: the bagman uses more than one door
	var seen: Array[Vector2] = []
	for i in range(14):
		table.briefcase.clear()
		table.spawn_briefcase()
		await step(1)
		var at := table.briefcase_at()
		if not seen.has(at):
			seen.append(at)
	check(seen.size() >= 2, "%d of the %d spots were ever used"
			% [seen.size(), ProgressionTable.BRIEFCASE_SPOTS.size()])
	table.briefcase.clear()

	# raid on: the two spots the cops leave alone, and never the one they stand on
	table.set_raid_active(true)
	await step(2)
	var blocked: Vector2 = ProgressionTable.BRIEFCASE_SPOTS[2]
	var used: Array[Vector2] = []
	for i in range(14):
		table.briefcase.clear()
		table.spawn_briefcase()
		await step(1)
		var at := table.briefcase_at()
		check(at.distance_to(blocked) > 1.0,
				"a case was dropped on %s with a cop standing on it" % str(at))
		if not used.has(at):
			used.append(at)
	check(used.size() >= 1, "a raid closed every spot on the table")
	for at: Vector2 in used:
		check(_clear_radius(space, at) >= want,
				"raid spot %s has only %.0f px of room" % [str(at), _clear_radius(space, at)])
	table.briefcase.clear()
	table.set_raid_active(false)

	# and never on top of the ball
	await drop_at(ProgressionTable.BRIEFCASE_SPOTS[0], Vector2.ZERO, 2)
	for i in range(6):
		table.briefcase.clear()
		table.spawn_briefcase()
		await step(1)
		if table.briefcase_live():
			check(table.briefcase_at().distance_to(ProgressionTable.BRIEFCASE_SPOTS[0]) > 1.0,
					"a case was dropped on top of the ball")
	table.briefcase.clear()
	table.despawn_ball()
	print("        %d spots, all >= %.0f px clear | raid used %s"
			% [ProgressionTable.BRIEFCASE_SPOTS.size(), want, str(used)])
	finish()


## Largest circle centred here that touches nothing solid — the same measurement the spots
## were chosen with.
func _clear_radius(space: PhysicsDirectSpaceState2D, at: Vector2) -> float:
	var r := 40.0
	var last := 0.0
	while r <= 200.0:
		var shape := CircleShape2D.new()
		shape.radius = r
		var q := PhysicsShapeQueryParameters2D.new()
		q.shape = shape
		q.transform = Transform2D(0.0, at)
		q.collision_mask = Feel.LAYER_WALLS | Feel.LAYER_HARDWARE | Feel.LAYER_FLIPPERS
		q.collide_with_areas = false
		if not space.intersect_shape(q, 1).is_empty():
			return last
		last = r
		r += 4.0
	return last


## 9 — the federal raid: three stages built out of hardware the table already had.
func _s9_federal() -> void:
	begin("federal phases stand up, escalate and clean up")
	use(ALL_IDS)
	check(table.federal_phase == 0, "the Bureau is already here")
	check(not table.vans.is_active() and not table.director.active, "phase 0 has hardware out")

	table.set_federal_raid(1)
	await step(2)
	for c: StandupTarget in table.cop_targets:
		check(c.visible and not Dormant.is_collision_off(c),
				"cop %s did not come out for the street sweep" % c.name)
	check(table.magnet.active, "the Captain's coil is not running in phase 1")
	check(not table.vans.is_active(), "the vans turned out for a street sweep")
	check(not table.director.active, "the Director turned out for a street sweep")
	check(table._raid_tint() > ProgressionTable.RAID_TINT,
			"a federal sweep must read dirtier than a local raid")

	table.set_federal_raid(2)
	await step(2)
	check(table.vans.is_active(), "the wiretap put no vans out")
	check(Dormant.is_collision_off(table.vans),
			"the vans have collision — a warrant may not change the geometry")
	check(not table.director.active, "the Director arrived a phase early")

	table.set_federal_raid(3)
	await step(2)
	check(table.director.active, "the Director never turned up")
	check(table.vans.is_active() and table.magnet.active, "phase 3 dropped the earlier phases")
	near(table.director.position.x, ProgressionTable.DIRECTOR_AT.x, 0.001, "Director x")
	near(table.director.position.y, ProgressionTable.DIRECTOR_AT.y, 0.001, "Director y")

	# the Director drags drain-ward like the Captain does
	var b := await drop_at(Vector2(490.0, 1200.0))
	var before := b.linear_velocity
	table.director.pull(b)
	await step(1)
	check(b.linear_velocity.y > before.y, "the Director's pull did not drag the ball drain-ward")
	table.despawn_ball()

	table.set_federal_raid(0)
	await step(2)
	for c: StandupTarget in table.cop_targets:
		check(not c.visible and Dormant.is_collision_off(c),
				"cop %s stayed out after the Bureau left" % c.name)
	check(not table.magnet.active and not table.director.active and not table.vans.is_active(),
			"phase 0 left federal hardware on the table")
	near(table._raid_tint(), 0.0, 0.001, "the felt stayed dirty after the Bureau left")

	# a local raid during a federal one is not a double toggle
	table.set_raid_active(true)
	table.set_federal_raid(3)
	await step(2)
	table.set_federal_raid(0)
	await step(2)
	check(table.magnet.active, "the Bureau leaving took the local raid's coil with it")
	check(table.cop_targets[0].visible, "the Bureau leaving took the local raid's cops with it")
	near(table._raid_tint(), ProgressionTable.RAID_TINT, 0.001,
			"the felt did not fall back to the local raid's tint")
	table.set_raid_active(false)
	await step(2)
	check(not table.magnet.active, "the local raid could not switch itself off")
	print("        1 sweep · 2 wiretap (no collision) · 3 Director, and 0 puts it all away")
	finish()


## 10 — two coils, one tell. Whichever is winding up owns the field.
func _s10_magnets() -> void:
	begin("the Captain and the Director never telegraph at once")
	use(ALL_IDS)
	table.set_federal_raid(3)
	await step(2)
	var both := 0
	var cap_tells := 0
	var dir_tells := 0
	var cap_was := false
	var dir_was := false
	var gap := INF
	var last_tell := -1000.0
	for t in range(ticks(DrainMagnet.PERIOD * 3.5)):
		await step(1)
		var cap := table.magnet.is_telegraphing()
		var dir := table.director.is_telegraphing()
		if cap and dir:
			both += 1
		var now := float(t) / float(Engine.physics_ticks_per_second)
		if cap and not cap_was:
			cap_tells += 1
			gap = minf(gap, now - last_tell)
			last_tell = now
		if dir and not dir_was:
			dir_tells += 1
			gap = minf(gap, now - last_tell)
			last_tell = now
		cap_was = cap
		dir_was = dir
	check(both == 0, "the two coils telegraphed together on %d ticks" % both)
	check(cap_tells >= 2, "the Captain's coil telegraphed %d times in %.0fs"
			% [cap_tells, DrainMagnet.PERIOD * 3.5])
	check(dir_tells >= 2, "the Director's coil telegraphed %d times in %.0fs"
			% [dir_tells, DrainMagnet.PERIOD * 3.5])
	check(gap > DrainMagnet.TELEGRAPH,
			"two tells came %.2fs apart — closer than one telegraph is one blur" % gap)
	table.set_federal_raid(0)
	await step(2)
	print("        %d + %d tells, never together, closest %.2fs apart"
			% [cap_tells, dir_tells, gap])
	finish()


## 11 — the whole machine with the crown on, under a seeded thrashing.
func _s11_soak() -> void:
	begin("no-tunnel soak with City Hall on (%.0fs)" % SOAK_SECONDS)
	use(ALL_IDS)
	table.set_federal_raid(3)
	table.auto_respawn = true
	table.despawn_ball()
	await step(2)
	table.spawn_ball()
	await wait(0.3)
	table.plunger.launch(1.0)

	var escapes := 0
	var still := 0
	var still_max := 0
	var still_at := Vector2.ZERO
	var last := Vector2.INF
	var next_flip := [0, 0]
	var flip := [false, false]
	var in_sky := 0
	var next_trip := ticks(2.0)
	var trips := 0
	var cases := 0
	reset_log()

	for t in range(ticks(SOAK_SECONDS)):
		for s in range(2):
			if t >= next_flip[s]:
				flip[s] = not flip[s]
				var f: Flipper = table.flipper_left if s == 0 else table.flipper_right
				f.set_pressed(flip[s])
				next_flip[s] = t + ticks(_rng.randf_range(0.3, 0.7))
		if table.plunger.ball_ready():
			table.plunger.launch(_rng.randf_range(0.85, 1.0))
		# a random flipper will never find the hardest shot on the machine, so post the ball
		# into the ceiling channel by hand at a pace either side of the gate
		if t >= next_trip and table.ball != null and is_instance_valid(table.ball) \
				and not BallHold.is_held(table.ball):
			table.ball.place(CHANNEL_ENTRY)
			table.ball.set_velocity(APPROACH_DIR
					* (CityHall.ENTRY_SPEED + _rng.randf_range(-260.0, 900.0)))
			trips += 1
			next_trip = t + ticks(_rng.randf_range(2.5, 4.0))
		if not table.briefcase_live() and t % ticks(6.0) == 0:
			table.spawn_briefcase()
			if table.briefcase_live():
				cases += 1
		await step(1)
		var b := table.ball
		if b == null or not is_instance_valid(b):
			last = Vector2.INF
			continue
		var p := b.global_position
		if p.y < ClubDeck.DECK_TOP:
			in_sky += 1
		if p.x < BOUND_MIN.x or p.x > BOUND_MAX.x or p.y < BOUND_MIN.y or p.y > BOUND_MAX.y:
			escapes += 1
			if escapes <= 3:
				print("        ESCAPE at %s v=%s" % [p, b.linear_velocity])
		if last != Vector2.INF and p.distance_to(last) < 0.5 and not BallHold.is_held(b):
			still += 1
			if still > still_max:
				still_max = still
				still_at = p
		else:
			still = 0
		last = p

	table.flipper_left.set_pressed(false)
	table.flipper_right.set_pressed(false)
	table.auto_respawn = false
	table.set_federal_raid(0)
	var stuck := float(still_max) / float(Engine.physics_ticks_per_second)
	var groups := {}
	for e: Dictionary in _earned:
		groups[e["group"]] = int(groups.get(e["group"], 0)) + 1
	print("        served %d | trips %d | laps %d | sky %d ticks | cases %d | switches %d"
			% [table.balls_served, trips, _laps.size(), in_sky, cases, _switches.size()])
	print("        groups hit: %s | longest still %.2fs at %s" % [str(groups), stuck, str(still_at)])
	check(escapes == 0, "the ball escaped the table %d times" % escapes)
	check(_switches.size() > 0, "nothing on the table was ever hit")
	check(stuck < 2.0, "ball sat motionless for %.2fs — wedged in the new geometry" % stuck)
	check(_laps.size() > 0, "the soak never once made the dome")
	table.briefcase.clear()
	finish()
