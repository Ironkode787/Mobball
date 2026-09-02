extends SimBase
## The machine's shot map, proven headless (specs/table-3d-flow.md): the Drop-Off ladder,
## the Staircase, both orbits, the docks scoop, the Penthouse stairs and the dome, the
## kickback and the outlanes, and the career's dormancy contract.

const CLUB_SET: Array = [
	ClubDeck.ID_DECK, ClubDeck.ID_STAIRCASE, ClubDeck.ID_ROULETTE, ClubDeck.ID_REELS,
	ClubDeck.ID_HIGH_ROLLER, ClubDeck.ID_BACKROOM, ClubDeck.ID_FLIPPERS,
]
const DOCKS_SET: Array = [Docks.ID_DOCKS, Docks.ID_CONTAINERS, Docks.ID_CRANE, Docks.ID_CARGO_RAMP]
const PENT_SET: Array = [Penthouse.ID_PENTHOUSE, Penthouse.ID_CHAIRS, Penthouse.ID_SITDOWN, Penthouse.ID_STAIRS]
const DOME_SET: Array = [CityHall.ID_CITY_HALL, CityHall.ID_LOOP]
const BLOCK_SET: Array = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers", &"spinner_numbers",
	&"orbit_left", &"orbit_right", &"wire_bank", &"laundromat_loop", &"storefront_laundromat",
	&"storefront_pizzeria", &"storefront_pawn", &"bribe_target", &"kickback_left",
]

var _rollover: int = -1
var _orbits: int = 0
var _trucks: int = 0
var _climbed: int = 0
var _shipped: int = 0
var _penthouse: int = 0
var _returned: int = 0
var _dome: int = 0
var _kicks: int = 0
var _lost: int = 0
var _docks_in: int = 0


func _ready() -> void:
	make_table(true)
	table.rollover_rolled.connect(func(i: int, _lit: bool) -> void:
		if _rollover < 0:
			_rollover = i)
	table.orbit_completed.connect(func() -> void: _orbits += 1)
	table.truck_route_completed.connect(func() -> void: _trucks += 1)
	table.staircase_climbed.connect(func(_s: float) -> void: _climbed += 1)
	table.cargo_shipped.connect(func(_s: float) -> void: _shipped += 1)
	table.penthouse_entered.connect(func(_s: float) -> void: _penthouse += 1)
	table.penthouse_returned.connect(func() -> void: _returned += 1)
	table.dome_loop_completed.connect(func(_s: float) -> void: _dome += 1)
	table.docks_entered.connect(func() -> void: _docks_in += 1)
	table.ball_lost.connect(func(_b: Ball) -> void: _lost += 1)
	if table.kickback != null:
		table.kickback.fired.connect(func() -> void: _kicks += 1)
	_run()


func _reset() -> void:
	_rollover = -1
	_orbits = 0
	_trucks = 0
	_climbed = 0
	_shipped = 0
	_penthouse = 0
	_returned = 0
	_dome = 0
	_kicks = 0
	_lost = 0
	_docks_in = 0


func _run() -> void:
	print("== KINGPIN machine sim (3D) ==")
	await _s_ladder()
	await _s_staircase()
	await _s_orbits()
	await _s_kickback_and_outlanes()
	await _s_docks()
	await _s_penthouse_and_dome()
	await _s_dormancy()
	report("machine")


func _plunge(power: float) -> Ball:
	_reset()
	table.despawn_ball()
	await step(2)
	var b := table.spawn_ball()
	await wait(0.3)
	table.plunger.launch(power)
	return b


## 1 — the Drop-Off: the three starter bands land in three different places.
func _s_ladder() -> void:
	begin("the Drop-Off ladder: soft, medium and hard plunges differ")
	var outcomes: Array[String] = []
	for power: float in ProgressionTable.PLUNGER_STARTER_POWERS:
		var b := await _plunge(power)
		await watch(4.5, b)
		var lane := _rollover
		var out := ("lane%d" % (lane + 1)) if lane >= 0 else "none"
		outcomes.append(out)
		print("        band %.2f -> %s (orbits %d)" % [power, out, _orbits])
		table.despawn_ball()
	check(outcomes[0] == "lane3", "the soft band should die into lane 3 (got %s)" % outcomes[0])
	check(outcomes[1] == "lane2", "the middle band should carry to lane 2 (got %s)" % outcomes[1])
	check(outcomes[2] == "lane1", "the hard band should lap the arch into lane 1 (got %s)" % outcomes[2])
	finish()


## 2 — the Staircase: a real ramp. Pace makes the deck; a soft shot rolls back out.
func _s_staircase() -> void:
	begin("the Staircase climbs to the Club at pace and refuses a soft shot")
	var dir := Layout.STAIR_PATH[1] - Layout.STAIR_PATH[0]
	dir.y = 0.0
	dir = dir.normalized()
	_reset()
	var b := await drop_at(Layout.STAIR_MOUTH + Vector2(0.0, 0.5), dir * 32.0)
	var w := await watch(3.0, b)
	check(_climbed == 1, "a 32 u/s shot did not crest the Staircase")
	check(hit_switch("staircase_ramp_entry"), "no staircase_ramp_entry switch")
	if w["alive"]:
		check(b.table_position().y > ClubDeck.DECK_H - 0.05, "the ball is not on the deck after cresting (%s)" % str(b.table_position()))
	_reset()
	b = await drop_at(Layout.STAIR_MOUTH + Vector2(0.0, 0.5), dir * 12.0)
	await watch(3.0, b)
	check(_climbed == 0, "a 12 u/s shot should not make the Club")
	check(hit_switch("staircase_ramp_entry"), "the soft shot never even entered the mouth")
	check(_lost >= 1 or (is_instance_valid(b) and b.table_position().y < 0.3), "the refused ball did not come back down")
	table.despawn_ball()
	finish()


## 3 — both orbits: up the left lane over the spinner and rollover 1; up the right lane
## for the Truck Route.
func _s_orbits() -> void:
	begin("the Getaway Loop and the Truck Route both complete")
	_reset()
	var b := await drop_at(Layout.ORBIT_L_ENTRY + Vector2(0.0, 0.6), Vector3(0.0, 0.0, -22.0))
	await watch(3.0, b)
	check(_orbits >= 1, "the left orbit did not complete")
	check(hit_switch("spinner_numbers"), "the spinner did not spin")
	check(_rollover == 0, "the orbit ball did not roll over lane 1 (got %d)" % _rollover)
	table.despawn_ball()
	_reset()
	b = await drop_at(Layout.ORBIT_R_ENTRY + Vector2(0.0, 0.8), Vector3(0.0, 0.0, -22.0))
	await watch(3.0, b)
	check(_trucks >= 1, "the right orbit (Truck Route) did not complete")
	table.despawn_ball()
	finish()


## 4 — the outlanes drain, the kickback throws a left-outlane ball back.
func _s_kickback_and_outlanes() -> void:
	begin("outlanes drain and the kickback saves the left one")
	_reset()
	table.kickback.recharge()
	var b := await drop_at(Vector2(Layout.KICKBACK_AT.x, 2.6))
	var w := await watch(3.0, b)
	check(_kicks == 1, "the kickback did not fire")
	check(w["min_z"] < 2.0, "the kickback did not throw the ball up the field (min z %.2f)" % w["min_z"])
	table.despawn_ball()
	_reset()
	b = await drop_at(Vector2(Layout.KICKBACK_AT.x, 2.6))
	await watch(3.0, b)
	check(_kicks == 0 and _lost == 1, "the spent kickback should let the ball drain")
	_reset()
	var right_outlane := Vector2((Layout.inlane_guide_x(1.0) + Layout.DIVIDER_X) * 0.5, 2.6)
	b = await drop_at(right_outlane)
	await watch(3.0, b)
	check(_lost == 1, "the right outlane did not drain")
	finish()


## 5 — the docks: a ball down the left lane enters the yard; the scoop ships it back out
## into the left lane over the roof.
func _s_docks() -> void:
	begin("the docks take a lane ball and the cargo scoop ships it out")
	_reset()
	var b := await drop_at(Vector2(Layout.ORBIT_L_ENTRY.x, -1.6), Vector3(0.0, 0.0, 6.0))
	var w := await watch(6.0, b)
	check(_docks_in >= 1, "the ball never entered the yard")
	check(_shipped >= 1 or _lost >= 1, "the ball is still in the yard after 6 s (%s)" % str(w["still_at"]))
	if _shipped >= 1:
		check(hit_switch("cargo_scoop"), "shipped without the scoop switch")
	print("        entered %d, shipped %d, lost %d" % [_docks_in, _shipped, _lost])
	table.despawn_ball()
	finish()


## 6 — upstairs: a ball on the deck shot into the stairs mouth climbs to the Penthouse; with
## more pace it continues into the dome loop.
func _s_penthouse_and_dome() -> void:
	begin("the Penthouse stairs and the City Hall loop")
	_reset()
	var dir := Penthouse.STAIR_PATH[1] - Penthouse.STAIR_PATH[0]
	dir.y = 0.0
	dir = dir.normalized()
	var b := await drop_at(ClubDeck.PENTHOUSE_MOUTH + Vector2(0.30, 0.30), dir * 21.0)
	var w := await watch(4.0, b)
	print("        soft shot: %s" % str(w))
	check(_penthouse >= 1, "a 21 u/s deck shot did not reach the Penthouse")
	if w["alive"]:
		check(b.table_position().y > Penthouse.ROOM_H - 0.05 or _returned >= 1,
				"the ball neither stayed in the Penthouse nor took the chute out (%s)" % str(b.table_position()))
	table.despawn_ball()
	_reset()
	b = await drop_at(ClubDeck.PENTHOUSE_MOUTH + Vector2(0.30, 0.30), dir * 32.0)
	await watch(5.0, b)
	check(_penthouse >= 1, "the fast deck shot did not reach the Penthouse")
	check(_dome >= 1, "the fast deck shot did not carry into the dome loop")
	print("        penthouse %d, dome %d" % [_penthouse, _dome])
	table.despawn_ball()
	finish()


## 7 — dormancy: what is not bought is not there — invisible AND collision-free.
func _s_dormancy() -> void:
	begin("dormant hardware is invisible and collision-free; bought hardware stands")
	table.debug_all_hardware = false
	table.force_hardware(BLOCK_SET + CLUB_SET + DOCKS_SET + PENT_SET + DOME_SET, false)
	for piece: Dictionary in table.hardware_pieces():
		var node: Node = piece["node"]
		var ids: Array = piece["ids"]
		if table.hardware_piece_active(piece):
			continue
		check(not (node as Node3D).visible or String(ids[0]) == "slingshots",
				"dormant %s is visible" % str(ids))
		check(Dormant.is_collision_off(node) or String(ids[0]) == "slingshots" or node is Storefront,
				"dormant %s still has collision" % str(ids))
	check(not table.hardware_present(&"orbit_left"), "orbit_left present on a bare table")
	check(table.bounds().size.y > 1.0, "bounds lost the upper storey")
	table.force_hardware(BLOCK_SET, true)
	check(table.hardware_present(&"orbit_left") and table.hardware_present(&"wire_bank"), "the Block did not stand up")
	check(not table.hardware_present(ClubDeck.ID_DECK), "the Club stood up without being bought")
	table.force_hardware(CLUB_SET, true)
	check(table.hardware_present(ClubDeck.ID_DECK) and table.hardware_present(ClubDeck.ID_STAIRCASE), "the Club did not stand up")
	check(not table.hardware_present(Penthouse.ID_PENTHOUSE), "the Penthouse needs the Club and more")
	table.force_hardware(PENT_SET, true)
	check(table.hardware_present(Penthouse.ID_PENTHOUSE), "the Penthouse did not stand up")
	table.debug_all_hardware = true
	table.refresh_hardware()
	finish()
