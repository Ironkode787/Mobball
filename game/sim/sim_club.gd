class_name SimClub
extends RefCounted
## THE CLUB, headless (specs/m2-content.md §1/§4): the deck visit, the wheel, the reels, the
## High Roller ladder, the back room and the Family Meeting.
##
## The division of labour is the flow lane's, kept deliberately: `Casino`, `FamilyMeeting` and
## `CollectionRound` are the REAL objects and they own every rule and every number. This file
## is the NightController's half — it decides when a ball is upstairs, which piece of deck
## hardware the next switch closes on, how long a hold lasts and when a Meeting ends — and
## `SimState` is `Game`'s half, which pays what those objects decide.
##
## ## What is modelled and what is assumed
##
## Assumed (and therefore living in `profiles.json`): `stair_take` — whether a shot at the
## Staircase mouth has the pace to climb, because the mouth is a speed gate and the sim has no
## speeds; `deck_seconds_mean` — how long a visit lasts; `meeting_seconds_mean` — how long two
## balls stay out together; `risk_appetite` — how far up the High Roller ladder greed goes.
##
## Modelled off the shipped geometry: the deck's traffic pattern (everything ends in the
## wheel, `SimTable.W_ROULETTE`), the reels as three independent three-deep columns on their
## own reset timers, the Jackpot as the union of columns cleared inside one visit, and the
## rule that falling off the deck costs the trip and never the ball — the return lane catches
## everything below the mini-bats (`ClubDeck.RETURN_PATH`), which is why deck seconds are
## added to a ball's life rather than drawn against its drain clock.
##
## ## The two-ball simplification, stated plainly
##
## A Family Meeting is modelled as ONE live ball paying double, for a window drawn off the
## profile, rather than as two independently-drained balls. When the window closes (or the
## live ball drains while it is open) exactly one guy goes inside and play continues with the
## other — which is what `NightController._lose_guy` + `_promote_survivor` do, and it keeps
## the Bench cost of a Meeting honest without a second ball loop. What it cannot show is the
## variance of losing BOTH balls inside a second; that is a feel question, not an economy one.

## Rungs of the High Roller ladder a `risk_appetite` of 1.0 climbs before letting go. The
## ladder is 1×/2×/3×/5× and every rung is flat Heat, so this is greed measured in rungs.
const LADDER_TOP := 3
## Flipper power is worth more at the Staircase mouth than anywhere else on the table: the
## gate wants pace, and pace is what the bats buy.
const STAIR_POWER_EXP := 1.5

var state: SimState
var profile: SimProfile
var table: SimTable

## True while the ball is on the deck; the downstairs menu does not exist while it is.
var upstairs: bool = false
var visit_left: float = 0.0
## Seconds of deck time this Night — the ball is alive for every one of them.
var deck_seconds: float = 0.0
var visits: int = 0
var climbs_tried: int = 0
var spins: int = 0
var jackpots: int = 0
var holds: int = 0

## Family Meeting: seconds left in the two-ball window and the second guy who is out for it.
var meeting_left: float = 0.0
var meeting_guy: Dictionary = {}
var meetings: int = 0
var meeting_seconds: float = 0.0
## Set when a Meeting ended on the PRIMARY guy's drain: the survivor takes over his slot in
## the line-up, exactly as `NightController._promote_survivor` does. Read and cleared by
## SimNight.
var promote_to: Dictionary = {}

var _rng: RandomNumberGenerator
## Targets down in each reel column, and each column's own re-arm timer.
var _col_down: PackedInt32Array = PackedInt32Array()
var _col_reset: PackedFloat32Array = PackedFloat32Array()
## Columns already cleared inside THIS visit — the Jackpot wants three different ones.
var _col_clear: Dictionary = {}


func _init(p_state: SimState, p_profile: SimProfile, p_table: SimTable,
		rng: RandomNumberGenerator) -> void:
	state = p_state
	profile = p_profile
	table = p_table
	_rng = rng
	_col_down.resize(SimTable.SLOT_COLUMNS)
	_col_reset.resize(SimTable.SLOT_COLUMNS)
	for c in SimTable.SLOT_COLUMNS:
		_col_down[c] = 0
		_col_reset[c] = -1.0


## Is there a deck to visit at all?
func live() -> bool:
	return table.deck != null and not table.deck.shots.is_empty()


# ================================================================== the stairs =====


## A shot at the Staircase mouth. True if it climbed — the mouth is a speed gate, so a soft
## shot is simply not taken and the ball carries on up the corridor and comes back down.
## Flipper power is the difference between "aimed at it" and "had the pace for it", which is
## why `muscle.steel_toes` shows up in the Club's numbers and not just in the bumpers'.
func try_climb() -> bool:
	climbs_tried += 1
	state.stair_attempts += 1
	var power := pow(maxf(state.stats.flipper_power(), 0.1), STAIR_POWER_EXP)
	return _rng.randf() < clampf(profile.stair_take * power, 0.01, 0.95)


## `NightController._on_staircase_climbed`: a completed climb opens the deck visit — the
## window the slots Jackpot has to be finished inside.
func enter_deck() -> void:
	upstairs = true
	visits += 1
	state.deck_visits += 1
	state.casino.open_visit()
	_col_clear.clear()
	visit_left = maxf(_expo(table.deck.deck_visit_seconds(profile)), 1.0)


## `NightController._tick_deck`: the visit closes as soon as nothing is upstairs any more.
func leave_deck() -> void:
	if not upstairs:
		return
	upstairs = false
	visit_left = 0.0
	_col_clear.clear()
	state.casino.close_visit()


## How fast switches close while upstairs.
func rate() -> float:
	return table.deck.deck_rate(profile)


# ================================================================ the hardware =====


## The wheel took the ball: one auto-bet, resolved by the real `Casino` against the real
## pockets. `Stats.casino_player_pockets()` says how many of the eight pay, and Loaded Dice
## buys them off the house in the wheel's own give-order.
func roulette() -> Dictionary:
	spins += 1
	var pockets := Casino.player_pockets(state.stats)
	var pocket := _rng.randi() % SimTable.ROULETTE_POCKETS
	return state.casino_roulette(pocket, SimTable.pocket_is_house(pocket, pockets))


## One drop target off a reel column. A disciplined player finishes the column he started; a
## duffer sprays across the grid. Clearing the third DIFFERENT column of a visit is the
## Jackpot — the columns re-arm independently, so the union across the visit is what counts.
func reel(column: int) -> bool:
	var c := _pick_column(column)
	if c < 0:
		return false
	_col_down[c] = _col_down[c] + 1
	if _col_down[c] < SimTable.SLOT_ROWS:
		return true
	_col_down[c] = 0
	_col_reset[c] = SimTable.SLOT_RESET_SEC
	_col_clear[c] = true
	if state.casino_reels([c]).is_positive():
		jackpots += 1
	return true


## The High Roller saucer: hold for `risk_appetite`'s worth of rungs, arm the next STAKE and
## take the flat Heat. Returns the deck seconds the greed cost — the ladder runs on its own
## cadence while the visit clock is running out, so holding is paid for twice.
func high_roller() -> float:
	var steps := clampi(int(round(profile.risk_appetite * float(LADDER_TOP))), 0, LADDER_TOP)
	if steps <= 0:
		return 0.0
	holds += 1
	state.casino_high_roller(steps)
	return float(steps) * SimTable.HIGH_ROLLER_STEP_SEC


## The back room: it pays the growing Meeting jackpot during a Meeting, and starts one when
## the room is lit and the Club is owned (`FamilyMeeting.can_start`).
func backroom() -> void:
	if meeting_left > 0.0:
		state.meeting_jackpot()
		return
	if not state.meeting.can_start(state.stats.hardware_unlocked(&"club_deck")):
		return
	_start_meeting()


# =============================================================== the meeting =====


func meeting_active() -> bool:
	return meeting_left > 0.0


## A second named guy joins the table, both balls get a grace, ALL dirty doubles and the back
## room starts paying (specs/m2-content.md §4). The window is a draw, not a rule: how long two
## balls stay out together is a property of the player, not of the machine.
func _start_meeting() -> void:
	var spare := _spare_guy()
	if spare.is_empty():
		return
	state.meeting.start(spare)
	meeting_guy = spare
	meeting_left = maxf(_expo(profile.meeting_seconds_mean), 2.0)
	meetings += 1
	state.meetings += 1
	var out: Array[Dictionary] = state.fielded.duplicate()
	out.append(spare)
	state.set_fielded(out)


## One ball is down. Whoever was riding it goes inside like anyone (docs/01 §4 — the crew out
## together); the other man carries on, and if it was the line-up's own guy who drained, the
## survivor takes over his slot. `primary_drained` is forced when the caller already knows
## which ball it was (the live ball's own survival span running out).
func end_meeting(primary_drained: bool) -> void:
	if meeting_left <= 0.0 and meeting_guy.is_empty():
		return
	var primary: Dictionary = state.fielded[0] if not state.fielded.is_empty() else {}
	var lost := primary if primary_drained else meeting_guy
	promote_to = meeting_guy if primary_drained else {}
	state.meeting.end()
	meeting_left = 0.0
	meeting_guy = {}
	if not lost.is_empty():
		state.bench.pinch(lost, false)
		state.guys_pinched += 1
	state.combo.reset()


## Who else is free tonight. Nobody? Hire one — the Bench never hard-locks (docs/01 §8).
func _spare_guy() -> Dictionary:
	var taken: Dictionary = {}
	for g in state.fielded:
		taken[int(g.get("id", -1))] = true
	for g in state.bench.available():
		if not taken.has(int(g["id"])):
			return g
	return state.bench.hire()


# ==================================================================== the clock =====


## Deck-visit countdown, reel re-arms and the Meeting window. `dt` is live-ball time.
func tick(dt: float) -> void:
	for c in SimTable.SLOT_COLUMNS:
		if _col_reset[c] <= 0.0:
			continue
		_col_reset[c] = _col_reset[c] - dt
		if _col_reset[c] <= 0.0:
			_col_reset[c] = -1.0
			_col_down[c] = 0
	if meeting_left > 0.0:
		meeting_left -= dt
		meeting_seconds += dt
		state.meeting_seconds += dt
		if meeting_left <= 0.0:
			end_meeting(_rng.randf() < 0.5)
	if not upstairs:
		return
	deck_seconds += dt
	visit_left -= dt
	if visit_left <= 0.0:
		leave_deck()


## Between guys and at the end of the Night: nothing is upstairs any more, and nobody is out.
func on_night_end() -> void:
	leave_deck()
	state.meeting.end()
	meeting_left = 0.0
	meeting_guy = {}
	promote_to = {}


# ==================================================================== internals =====


## Which column this shot actually lands on, or -1 for a shot into a column that is still
## re-arming (the targets are simply not there yet). Discipline routes it at the column
## closest to clearing that the visit has not already banked.
func _pick_column(preferred: int) -> int:
	if _rng.randf() < profile.target_discipline:
		var best := -1
		var best_down := -1
		for c in SimTable.SLOT_COLUMNS:
			if _col_reset[c] > 0.0 or _col_clear.has(c):
				continue
			if _col_down[c] > best_down:
				best_down = _col_down[c]
				best = c
		if best >= 0:
			return best
	var col := clampi(preferred, 0, SimTable.SLOT_COLUMNS - 1)
	return -1 if _col_reset[col] > 0.0 else col


func _expo(mean: float) -> float:
	return -log(maxf(1.0 - _rng.randf(), 1.0e-12)) * mean
