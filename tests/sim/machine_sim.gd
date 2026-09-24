extends SimBase
## The v4 machine, proven headless (docs/19 §3): the Drop-Off ladder, the Alley nest and its
## development, Lucky's Tower, the Staircase and the Club, both orbits, the Sewer, Pier 9, the
## Penthouse roof, City Hall's dome, the doorway banks, the kickback, the aim of both bats, and
## the career's dormancy contract.

const BLOCK_SET: Array = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers", &"spinner_numbers",
	&"orbit_left", &"orbit_right", &"wire_bank", &"laundromat_loop", &"sewer",
	&"storefront_pizzeria", &"storefront_pawn", &"bribe_target", &"kickback_left",
]

var _lanes: Array[int] = []
var _orbits: int = 0
var _trucks: int = 0
var _climbed: int = 0
var _home: int = 0
var _pops: int = 0
var _completed: int = 0
var _lucky: int = 0
var _washed: int = 0
var _warps: int = 0
var _loads: int = 0
var _roof: int = 0
var _dome: int = 0
var _collected: int = 0
var _kicks: int = 0
var _shots: Array[StringName] = []


func _ready() -> void:
	make_table(true)
	table.rollover_rolled.connect(func(i: int, _lit: bool) -> void: _lanes.append(i))
	table.orbit_completed.connect(func() -> void: _orbits += 1)
	table.truck_route_completed.connect(func() -> void: _trucks += 1)
	table.staircase_climbed.connect(func(_s: float) -> void: _climbed += 1)
	table.deck_returned.connect(func() -> void: _home += 1)
	table.lanes_completed.connect(func() -> void: _completed += 1)
	table.lucky_entered.connect(func(_b: Ball) -> void: _lucky += 1)
	table.laundromat_pass.connect(func() -> void: _washed += 1)
	table.sewer_warped.connect(func(_f: int, _t: int) -> void: _warps += 1)
	table.container_stack_cleared.connect(func(_s: int) -> void: _loads += 1)
	table.penthouse_entered.connect(func(_s: float) -> void: _roof += 1)
	table.dome_loop_completed.connect(func(_s: float) -> void: _dome += 1)
	table.storefront_collected.connect(func(_id: StringName, _a: BigMoney) -> void: _collected += 1)
	table.shot_made.connect(func(s: StringName, _b: Ball) -> void: _shots.append(s))
	for can in table.alley.cans:
		can.popped.connect(func(_c: Bumper, _b: Ball) -> void: _pops += 1)
	if table.kickback != null:
		table.kickback.fired.connect(func() -> void: _kicks += 1)
	_run()


func _reset() -> void:
	_lanes.clear()
	_orbits = 0
	_trucks = 0
	_climbed = 0
	_home = 0
	_pops = 0
	_completed = 0
	_lucky = 0
	_washed = 0
	_warps = 0
	_loads = 0
	_roof = 0
	_dome = 0
	_collected = 0
	_kicks = 0
	_shots.clear()


func _run() -> void:
	print("== KINGPIN machine sim (v4) ==")
	# SIM_ONLY=aim,dome runs just those scenarios while iterating on one piece
	var only := OS.get_environment("SIM_ONLY").split(",", false)
	for s: Callable in [_s_ladder, _s_nest, _s_lanes_build_the_cans, _s_lucky, _s_staircase,
			_s_orbits, _s_sewer, _s_pier, _s_roof, _s_dome, _s_doorway, _s_kickback, _s_aim,
			_s_no_pockets, _s_dormancy]:
		if only.is_empty() or only.has(s.get_method().trim_prefix("_s_")):
			await s.call()
	report("machine")


func _plunge(power: float) -> Ball:
	_reset()
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	await wait(0.3)
	_switches.clear()
	table.plunger.launch(power)
	return b


## 1 — the Drop-Off: the plunge rides the Truck Route's rail; the three starter bands finish in
## different places (back down the right lane, into a Drop-Off lane, or round to the Getaway lane).
func _s_ladder() -> void:
	begin("the Drop-Off ladder: the three starter bands finish in different places")
	var outcomes: PackedStringArray = []
	for power: float in ProgressionTable.PLUNGER_STARTER_POWERS:
		var b := await _plunge(power)
		await watch(4.5, b)
		var out := "none"
		for id: String in _switches:
			if id.begins_with("rollover_"):
				out = "lane" + id.substr(9)
				break
			if id == "orbit_left_entry":
				out = "left lane"
				break
			if id == "orbit_right_entry":
				out = "right lane"
				break
		outcomes.append(out)
		print("        band %.2f -> %s" % [power, out])
		table.despawn_ball()
	var distinct := {}
	for o in outcomes:
		distinct[o] = true
	check(distinct.size() >= 2, "every band ends up in the same place (%s)" % ", ".join(outcomes))
	check(not outcomes.has("none"), "a starter band reached no lane (%s)" % ", ".join(outcomes))
	finish()


## 2 — the Alley: a ball dropped into the nest rattles among the cans.
func _s_nest() -> void:
	begin("the Alley nest: a ball in the nest rattles off the cans")
	_reset()
	var b := await drop_at(Vector2(Layout.MIRROR_X + 0.05, -3.70), Vector3(0.6, 0.0, 0.0))
	await watch(3.0, b)
	print("        %d pops in 3 s" % _pops)
	check(_pops >= 4, "only %d pops in 3 s: the nest does not chatter" % _pops)
	finish()


## 3 — Space Cadet's rule: all three lanes lit raises every can a level, and the value doubles.
func _s_lanes_build_the_cans() -> void:
	begin("rolling all three Drop-Off lanes raises the cans a level")
	_reset()
	table.alley.reset_night()
	for x: float in Layout.DROPOFF_X:
		var b := await drop_at(Vector2(x, Layout.DROPOFF_ROLLOVER_Z - 0.22), Vector3(0.0, 0.0, 2.0))
		await wait(0.5)
	check(_completed == 1, "three lanes did not complete the set (%d)" % _completed)
	check(table.can_level() == 1, "the cans did not go up a level (level %d)" % table.can_level())
	check(table.alley.cans[0].scaled_value() == table.alley.cans[0].value * 2, "a Dumpster does not pay double")
	# the next Night starts from the Trash Can, however well tonight went
	table.light_penthouse()
	table.reset_board()
	check(table.can_level() == 0, "a new Night kept yesterday's can level (level %d)" % table.can_level())
	check(not table.penthouse_lit(), "a new Night kept yesterday's lit roof")
	# lane change: the flipper buttons rotate the lit lanes
	table.alley.reset_night()
	table.alley.lane_lit[0] = true
	Events.flipper_fired.emit(&"right")
	check(table.alley.lane_lit[1] and not table.alley.lane_lit[0], "the right button did not move the lit lane right")
	table.alley.reset_night()
	table.despawn_ball()
	finish()


## 4 — Lucky's Tower: the scoop takes the ball, the drum washes it, the lift lets it out into
## the Alley.
func _s_lucky() -> void:
	begin("Lucky's Tower: scoop, wash, lift, and out of the side door into the Alley")
	_reset()
	var b := await drop_at(Layout.SCOOP_AT + Vector2(-0.02, 0.35), Vector3(0.0, 0.0, -6.0))
	var gone_up := false
	for i in range(ticks(6.0)):
		await step(1)
		if not is_instance_valid(b):
			break
		if table.tower.is_busy():
			gone_up = true
		if gone_up and not table.tower.is_busy():
			break
	check(_lucky == 1, "the scoop did not take the ball")
	check(_washed == 1, "the drum did not wash")
	if is_instance_valid(b):
		await wait(0.4)
		var p := b.table_position()
		check(p.z < Layout.NEST_BOTTOM + 0.2 and absf(p.x - Layout.MIRROR_X) < Layout.NEST_HALF,
				"the side door did not let the ball into the Alley (%s)" % str(p))
	finish()


## 5 — the Staircase: pace makes the deck, a soft shot rolls back; the cashier brings it home.
func _s_staircase() -> void:
	begin("the Staircase climbs to the Club and the cashier lane brings the ball home")
	var dir := Layout.STAIR_PATH[1] - Layout.STAIR_PATH[0]
	dir.y = 0.0
	dir = dir.normalized()
	_reset()
	var b := await drop_at(Layout.STAIR_MOUTH - Vector2(dir.x, dir.z) * 0.5, dir * 20.0)
	var came_home := false
	for i in range(ticks(9.0)):
		await step(1)
		if not is_instance_valid(b):
			break
		if _home > 0 and b.table_position().z > 2.0:
			came_home = true
			break
	check(_climbed == 1, "a 20 u/s shot did not crest the Staircase")
	check(_home == 1, "the ball never came down the cashier lane")
	check(came_home, "the cashier lane did not deliver the ball to the left inlane")
	_reset()
	b = await drop_at(Layout.STAIR_MOUTH - Vector2(dir.x, dir.z) * 0.5, dir * 7.0)
	await watch(3.0, b)
	check(_climbed == 0, "a 7 u/s shot should roll back, not crest")
	finish()


## 6 — both orbits: a ball up either lane at pace goes round and comes down the other.
func _s_orbits() -> void:
	begin("the Getaway and the Truck Route go round the ring road")
	table.docks.set_lit(false)
	_reset()
	var b := await drop_at(Vector2(Layout.LANE_L_X, 0.3), Vector3(0.0, 0.0, -21.0))
	await watch(2.5, b)
	check(_orbits == 1 and _trucks == 0, "a 21 u/s ball up the left lane did not make the Getaway (orbits %d, trucks %d)" % [_orbits, _trucks])
	_reset()
	b = await drop_at(Vector2(Layout.LANE_R_X, 0.3), Vector3(0.0, 0.0, -21.0))
	await watch(2.5, b)
	check(_trucks == 1, "a 21 u/s ball up the right lane did not make the Truck Route (orbits %d, trucks %d)" % [_orbits, _trucks])
	table.docks.set_lit(true)
	finish()


## 7 — the Sewer: a lit Street manhole swallows the ball and it comes up in the Alley.
func _s_sewer() -> void:
	begin("the Sewer: a lit manhole takes the ball and it comes up in the Alley")
	_reset()
	table.open_sewer()
	var start: Vector2 = Layout.MANHOLE_AT[0]
	var b := await drop_at(start + Vector2(0.0, -0.4), Vector3(0.0, 0.0, 2.0))
	await wait(2.0)
	check(_warps == 1, "the manhole did not swallow the ball")
	check(not table.sewer_is_open(), "the sewer stayed open after one trip")
	if is_instance_valid(b):
		var p := b.table_position()
		check(p.z < Layout.NEST_BOTTOM + 0.3, "the ball did not come up in the Alley (%s)" % str(p))
	finish()


## 8 — Pier 9: the crane takes a Truck Route ball, loads a container and drops it back.
func _s_pier() -> void:
	begin("Pier 9: the crane loads a Truck Route ball and drops it back on the ring road")
	_reset()
	table.reset_pier()
	var b := await drop_at(Vector2(Layout.LANE_R_X, 0.3), Vector3(0.0, 0.0, -24.0))
	for i in range(ticks(6.0)):
		await step(1)
		if _loads > 0 and not table.docks.holds_ball():
			break
	check(_loads == 1, "the crane did not load a container")
	check(table.docks.loaded_count() == 1, "the yard does not show the load")
	if is_instance_valid(b):
		check(not BallHold.is_held(b), "the crane kept the ball")
	table.reset_pier()
	# the pier is bought before the Truck Route: its crane must take loads without that orbit
	_reset()
	var pier_set := [Docks.ID_DOCKS, Docks.ID_CONTAINERS, Docks.ID_CRANE]
	table.debug_all_hardware = false
	table.force_hardware(pier_set, true)
	table.docks.set_lit(true)
	check(not table.hardware_present(&"orbit_right"), "the Truck Route stood up with the pier")
	await wait(Docks.COOLDOWN + 0.2)
	var early := await drop_at(Vector2(Layout.LANE_R_X, 0.3), Vector3(0.0, 0.0, -24.0))
	for i in range(ticks(6.0)):
		await step(1)
		if _loads > 0 and not table.docks.holds_ball():
			break
	check(_loads == 1, "the crane took nothing before the Truck Route was bought")
	table.force_hardware(pier_set, false)
	table.debug_all_hardware = true
	table.refresh_hardware()
	table.reset_pier()
	if is_instance_valid(early):
		table.despawn_ball()
	finish()


## 9 — the roof: with the Penthouse lit, Lucky's lift seats the ball at the Commission table.
func _s_roof() -> void:
	begin("the Penthouse: a lit roof takes the lift to the Sit-Down and back down")
	_reset()
	table.light_penthouse()
	var b := await drop_at(Layout.SCOOP_AT + Vector2(-0.02, 0.35), Vector3(0.0, 0.0, -6.0))
	for i in range(ticks(9.0)):
		await step(1)
		if _roof > 0 and not table.tower.is_busy():
			break
	check(_roof == 1, "the lift did not reach the roof")
	check(table.penthouse.session_active(), "the Commission is not in session after the Sit-Down")
	check(is_instance_valid(b) and not BallHold.is_held(b), "the ball did not come back down")
	finish()


## 10 — City Hall: a full-speed orbit takes the dome loop; a slow one passes under the gate.
func _s_dome() -> void:
	begin("City Hall: a full-speed Getaway takes the dome, a slow one does not")
	_reset()
	var b := await drop_at(Vector2(Layout.LANE_L_X, 0.3), Vector3(0.0, 0.0, -30.0))
	await watch(4.0, b)
	check(_dome == 1, "a 30 u/s Getaway did not loop the dome")
	_reset()
	b = await drop_at(Vector2(Layout.LANE_L_X, 0.3), Vector3(0.0, 0.0, -21.0))
	await watch(3.0, b)
	check(_dome == 0, "an ordinary 21 u/s Getaway should not make the dome")
	finish()


## 11 — the doorway banks: all three drops down opens the shop, rolling through collects.
func _s_doorway() -> void:
	begin("Nonna's: three drops open the doorway and a ball through it collects")
	_reset()
	var s: Storefront = table.storefronts[0]
	for t in s.targets():
		t.drop()
	await step(2)
	check(s.is_open(), "the doorway did not open with the bank down")
	var face := s.facing()
	var mid := (s.front_from() + s.front_to()) * 0.5 + face * 0.35
	var b := await drop_at(mid, Vector3(-face.x, 0.0, -face.y) * 7.0)
	await wait(1.5)
	check(_collected == 1, "rolling through the open doorway did not collect")
	if is_instance_valid(b):
		check(b.table_position().z < s.centre().y, "the ball did not come out of the back door (%s)" % str(b.table_position()))
	finish()


## 12 — the Enforcer: an outlane ball is kicked back into play.
func _s_kickback() -> void:
	begin("the Enforcer kicks an outlane ball back up the left side")
	_reset()
	table.kickback.recharge()
	var b := await drop_at(Layout.KICKBACK_AT + Vector2(0.0, -0.8), Vector3(0.0, 0.0, 4.0))
	var w := await watch(2.0, b)
	check(_kicks == 1, "the kickback did not fire")
	check(bool(w["alive"]) and float(w["min_z"]) < 1.5, "the kicked ball did not go back up the table")
	finish()


## 13 — the aim: from a trap, each bat reaches its whole fan of shots somewhere in the release
## window (docs/19 §3.1).
func _s_aim() -> void:
	begin("aim: each bat makes its fan of shots from a trap")
	table.docks.set_lit(false)
	var want := {
		&"left": [&"truck_route", &"luckys", &"alley"],
		&"right": [&"getaway", &"staircase", &"alley"],
	}
	for side: StringName in [&"left", &"right"]:
		var f: Flipper = table.flipper_left if side == &"left" else table.flipper_right
		var seen := {}
		var d := 0.50
		while d <= 0.80:
			_reset()
			table.despawn_ball()
			f.release()
			await step(24)
			f.press()
			await step(24)
			var b := table.spawn_ball()
			b.place(f.cradle_point(0.45) + Vector3(0.0, 0.03, 0.0))
			await wait(0.6)
			f.release()
			await wait(d)
			f.press()
			var first := &""
			for i in range(ticks(3.0)):
				await step(1)
				first = _first_major_shot()
				if first != &"" or not is_instance_valid(b):
					break
			f.release()
			if first != &"":
				seen[first] = true
			d += 0.02
		print("        %s bat reaches: %s" % [side, ", ".join(PackedStringArray(seen.keys()))])
		for shot: StringName in want[side]:
			check(seen.has(shot), "the %s bat never made %s" % [side, shot])
	table.docks.set_lit(true)
	finish()


## The spinner and the Drop-Off lanes are on the way to other shots; they are not what a
## flip was aimed at.
func _first_major_shot() -> StringName:
	for s in _shots:
		if s != &"spinner" and s != &"dropoff":
			return s
	return &""


## 14 — no pockets: a ball dropped anywhere on the open board never sits still.
func _s_no_pockets() -> void:
	begin("no pockets: a ball dropped anywhere on the board keeps moving or is taken")
	var worst := 0
	var at_worst := Vector3.ZERO
	var z := -4.2
	while z <= 3.2:
		var x := -2.3
		while x <= 1.9:
			var p := Vector2(x, z)
			x += 0.55
			if _inside_solid(p):
				continue
			var b := await drop_at(p, Vector3.ZERO, 2)
			var w := await watch(3.0, b)
			if int(w["still_max"]) > worst:
				worst = int(w["still_max"])
				at_worst = w["still_at"]
		z += 0.55
	print("        longest still spell %.2f s at %s" % [float(worst) / 240.0, str(at_worst)])
	check(float(worst) / 240.0 < 2.5, "a ball sat still %.1f s at %s" % [float(worst) / 240.0, str(at_worst)])
	finish()


func _inside_solid(p: Vector2) -> bool:
	for poly: PackedVector2Array in [Layout.ISLAND_WIRE, Layout.ISLAND_COP, Layout.ISLAND_NONNA, Layout.ISLAND_TONY]:
		if Geometry2D.is_point_in_polygon(p, poly):
			return true
	if Geometry2D.is_point_in_polygon(p, ClubDeck.outline()):
		return true
	var r := Layout.TOWER_RECT
	if r.grow(0.15).has_point(p):
		return true
	for c: Vector2 in Layout.BUMPER_AT:
		if c.distance_to(p) < Layout.CAN_RADIUS + Feel.BALL_RADIUS:
			return true
	return false


## 15 — dormancy: the bare table has none of the bought hardware standing, invisible AND
## collision-free; buying it back stands it up.
func _s_dormancy() -> void:
	begin("dormancy: an unbought piece is invisible and collision-free")
	table.debug_all_hardware = false
	table.refresh_hardware()
	for id: StringName in [&"bumper_2", &"spinner_numbers", ClubDeck.ID_DECK, Docks.ID_DOCKS,
			Penthouse.ID_PENTHOUSE, CityHall.ID_CITY_HALL, &"sewer", &"orbit_right"]:
		var node := table.hardware_node(id)
		check(node != null, "%s is not registered" % id)
		if node != null:
			check(not table.hardware_present(id), "%s stands on a bare table" % id)
			check(Dormant.is_collision_off(node), "%s is hidden but still collides" % id)
	check(not table.storefronts[0].bank_enabled, "Nonna's bank is live without the racket")
	table.force_hardware(BLOCK_SET, true)
	check(table.hardware_present(&"bumper_2") and table.hardware_present(&"sewer"), "the Block did not stand up")
	check(not table.hardware_present(ClubDeck.ID_DECK), "the Club stood up without being bought")
	var club_set := [ClubDeck.ID_DECK, ClubDeck.ID_STAIRCASE, ClubDeck.ID_ROULETTE, ClubDeck.ID_REELS, ClubDeck.ID_BACKROOM]
	table.force_hardware(club_set, true)
	check(table.hardware_present(ClubDeck.ID_DECK) and table.hardware_present(ClubDeck.ID_STAIRCASE), "the Club did not stand up")
	table.force_hardware(BLOCK_SET + club_set, false)
	table.debug_all_hardware = true
	table.refresh_hardware()
	finish()
