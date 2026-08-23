extends RefCounted
## THE PENTHOUSE AND CITY HALL (docs/02 §2 R6, docs/05 §8): the five chairs claimed across
## Nights, the campaign they unlock, Election Night, and the term in office.

const SAVE_PATH := "user://test_flow_elections.json"


func run(t: TestCtx) -> void:
	_chairs(t)
	_campaign(t)
	_election_night(t)
	_recount(t)
	_administration(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_chairs_are_a_career(t)
	_frenzy_pays(t)
	_save_round_trip(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


# --- the chairs ---------------------------------------------------------------


func _chairs(t: TestCtx) -> void:
	var room := CommissionChairs.new()
	room.begin_night()
	t.ok(room.on_chair_taken(0), "a seat nobody had is claimed")
	t.ok(not room.on_chair_taken(0), "and knocking it down again claims nothing")
	t.eq(room.night_taken, 2, "though both hits are on tonight's tally")
	t.eq(room.claimed_count(), 1, "one seat")
	t.ok(not room.on_chair_taken(-1) and not room.on_chair_taken(CommissionChairs.CHAIRS),
			"a chair that is not at the table is not a chair")

	# The claim is the career's, so a new Night does not give the room back.
	room.begin_night()
	t.eq(room.claimed_count(), 1, "the seat is still yours a Night later")
	t.eq(room.night_claimed, 0, "with tonight's tally clean")
	t.ok(not room.all_claimed(), "four to go")
	t.eq(room.open_seats().size(), 4, "and the room says which")

	for i in range(1, CommissionChairs.CHAIRS):
		room.on_chair_taken(i)
	t.ok(room.all_claimed(), "five chairs is the whole Commission")
	t.eq(room.open_seats().size(), 0, "nobody left standing")


func _campaign(t: TestCtx) -> void:
	var room := CommissionChairs.new()
	var city := Elections.new()
	# A sweep with seats still open is a good pass and nothing more.
	room.on_chair_taken(0)
	t.ok(not room.on_chairs_completed(), "the room is not yours until every seat is claimed")
	t.eq(room.sweeps, 1, "but the sweep is on the rap sheet")

	t.ok(not city.note(&"alley", 999), "and the campaign is shut until it is")
	t.eq(city.lit_count(), 0, "nothing canvassed")

	for i in CommissionChairs.CHAIRS:
		room.on_chair_taken(i)
	t.ok(room.on_chairs_completed(), "all five claimed and swept lights ELECTIONS")
	t.ok(city.unlock(), "which opens the campaign")
	t.ok(not city.unlock(), "once")

	# Canvassing is per-Night work; the light it earns is not.
	var alley := Elections.district(&"alley")
	t.ok(not city.note(&"alley", int(alley["need"]) - 1), "most of a district is not a district")
	t.ok(city.note(&"alley", 1), "finishing the job canvasses it")
	t.ok(city.is_lit(&"alley"), "and the light stays on")
	t.ok(not city.note(&"alley", 999), "a district already lit takes no more work")

	city.begin_night()
	t.ok(city.is_lit(&"alley"), "across Nights")
	t.eq(city.progress_in(&"corner"), 0, "while tonight's progress starts at nothing")
	t.ok(not city.note(&"the_moon"), "a district that does not exist cannot be canvassed")

	for d in Elections.DISTRICTS:
		city.note(StringName(d["id"]), int(d["need"]))
	t.ok(city.all_lit(), "five districts is a ballot")


func _election_night(t: TestCtx) -> void:
	var city := _lit_city()
	t.ok(city.call_election(), "the city votes")
	t.ok(not city.call_election(), "and only once at a time")
	t.near(city.time_left, Elections.ELECTION_SECONDS, 1e-9, "ninety seconds of it")
	t.near(city.dirty_multiplier(), Elections.FRENZY_MULT, 1e-9, "everything pays more")

	city.on_vote(Elections.VOTES_TO_WIN)
	t.ok(not city.tick(Elections.ELECTION_SECONDS - 1.0), "the polls are open to the buzzer")
	t.ok(city.tick(1.0), "then they close")
	t.ok(not city.active, "the frenzy is over")
	t.near(city.dirty_multiplier(), 1.0, 1e-9, "and the table pays its ordinary rate")
	t.ok(city.won(), "the votes were there")

	var result := city.settle()
	t.ok(bool(result["won"]), "so the city is bought")
	t.eq(int(result["term"]), Elections.TERM_NIGHTS, "for five Nights")
	t.eq(city.term_left, Elections.TERM_NIGHTS + 1,
			"and the Night it was won on is not one of them")
	t.ok(city.in_office(), "you are the administration")
	t.eq(city.lit_count(), 0, "and the board is clear for the next campaign")


func _recount(t: TestCtx) -> void:
	var city := _lit_city()
	city.call_election()
	city.on_vote(Elections.VOTES_TO_WIN - 1)
	city.tick(Elections.ELECTION_SECONDS)
	t.ok(not city.won(), "one vote short")
	var result := city.settle()
	t.ok(not bool(result["won"]), "is a recount")
	t.ok(not city.in_office(), "nobody takes office")
	t.eq(city.lit_count(), Elections.RECOUNT_KEEPS,
			"and a lost election keeps one district's light (P5: setbacks sting, never erase)")
	t.ok(city.is_lit(StringName(result["kept"])), "the one the result names")
	t.eq(city.terms_lost, 1, "the loss is on the record")


func _administration(t: TestCtx) -> void:
	var city := Elections.new()
	t.near(city.raid_threshold(), Rates.RAID_THRESHOLD, 1e-9,
			"out of office the Inspector's bar is the meter's own")
	city.term_left = 2
	t.ok(city.in_office(), "in office")
	t.near(city.raid_threshold(), Elections.ADMIN_RAID_THRESHOLD, 1e-9,
			"he needs a much better reason")
	t.ok(not city.night_tick(), "a Night in office spends a Night of the term")
	t.eq(city.term_left, 1, "four to go becomes three")
	t.ok(city.night_tick(), "and the last one reports the term running out")
	t.ok(not city.in_office(), "then City Hall is somebody else's")
	t.ok(not city.night_tick(), "and the term does not go negative")
	t.near(city.raid_threshold(), Rates.RAID_THRESHOLD, 1e-9, "the bar drops back")


# --- against the real session -------------------------------------------------


func _chairs_are_a_career(t: TestCtx) -> void:
	Game.new_game(11)
	Game.start_night()
	var stars := Game.respect
	t.ok(Game.chair_taken(0), "the first seat is claimed")
	t.eq(Game.respect, stars + CommissionChairs.RESPECT_PER_CHAIR, "and it is worth ☆")
	t.ok(not Game.chair_taken(0), "the same seat pays once")
	t.eq(Game.respect, stars + CommissionChairs.RESPECT_PER_CHAIR, "ever")

	t.ok(not Game.chairs_completed(), "a sweep with seats open lights nothing")
	t.ok(not Game.elections.unlocked, "the campaign is still shut")

	for i in range(1, CommissionChairs.CHAIRS):
		Game.chair_taken(i)
	t.eq(Game.respect, stars + CommissionChairs.RESPECT_PER_CHAIR * CommissionChairs.CHAIRS
			+ CommissionChairs.RESPECT_ALL_CHAIRS, "the fifth chair pays the room as well")
	t.ok(Game.chairs_completed(), "and now a sweep lights ELECTIONS")
	t.ok(Game.elections.unlocked, "the campaign is open")
	t.ok(not Game.chairs_completed(), "which only happens the once")


func _frenzy_pays(t: TestCtx) -> void:
	Game.new_game(12)
	Game.start_night()
	var quiet := Game.preview_switch(&"bumpers", BigMoney.from_float(100.0))

	Game.elections.unlocked = true
	for d in Elections.DISTRICTS:
		Game.elections.lit[String(d["id"])] = true
	t.ok(Game.elections.call_election(), "the ballot opens")
	var loud := Game.preview_switch(&"bumpers", BigMoney.from_float(100.0))
	t.ok(loud.equals_approx(quiet.mul(Elections.FRENZY_MULT), 1e-9),
			"and every switch is worth three times as much while the city votes")

	# The campaign is gated on the Penthouse, not on the Ledger: a locked city counts nothing.
	Game.new_game(13)
	Game.start_night()
	t.ok(not Game.election_note(&"alley", 999), "no Penthouse, no campaign")


func _save_round_trip(t: TestCtx) -> void:
	Game.new_game(14)
	Game.start_night()
	Game.chair_taken(1)
	Game.chair_taken(3)
	Game.elections.unlocked = true
	Game.election_note(&"block")
	Game.elections.term_left = 3
	t.ok(Game.save_now(), "the career writes")

	Game.new_game(0)
	Game.from_dict(Game.save.read())
	t.eq(Game.chairs.claimed_count(), 2, "the claimed seats come back")
	t.ok(Game.chairs.claimed.has(1) and Game.chairs.claimed.has(3), "the same two")
	t.ok(Game.elections.unlocked, "the campaign is still open")
	t.ok(Game.elections.is_lit(&"block"), "with the block still canvassed")
	t.eq(Game.elections.term_left, 3, "and the term still running")
	t.ok(Game.administration_active(), "so City Hall is still ours on load")

	# A Night in office costs a Night, and it is spent at The Count; tonight's canvassing
	# starts clean at roll call.
	Game.start_night()
	t.eq(Game.elections.term_left, 3, "roll call does not spend the term")
	t.eq(Game.elections.progress_in(&"alley"), 0, "but the campaign's clock is per Night")
	Game.end_night({})
	t.eq(Game.elections.term_left, 2, "The Count does")


func _lit_city() -> Elections:
	var city := Elections.new()
	city.unlock()
	for d in Elections.DISTRICTS:
		city.note(StringName(d["id"]), int(d["need"]))
	return city
