class_name TableJobs
extends RefCounted
## THE WIRE'S JOBS (docs/19 §4): Space Cadet's missions, played on the table.
##
##   * Roll Call deals three lines, one per payphone. Hit a payphone and its line rings: that Job
##     is SELECTED and its shots light.
##   * Shoot LUCKY'S to take it: the fuse lights, full. With no line rung, Lucky's gives you the
##     next open one (docs/20 §4): the payphones choose, they are not a gate.
##   * Make the lit shots before the fuse burns down (the NUMBERS spinner buys time). Done pays
##     dirty and ☆ and marks the line; a blown fuse puts the line back on the board.
##   * Finish all three lines in a Night and BIG SCORE lights at Lucky's: every shot on the board
##     lights for a jackpot, and when they are all in, Lucky's pays the vault.
##   * THE TAKE (×2 ×3 ×4 ×5 ×8) climbs one step per storefront cash-out and multiplies Job pay
##     and jackpots; it resets when a guy's ball is over.
##
## Pure logic on a fed clock and a seeded RNG, like every mode in this lane: the table reports
## shots, the NightController forwards them, `Game` owns the money.

signal changed()
signal job_selected(line: int)
signal job_started(line: int)
signal job_done(line: int, job: Dictionary)
signal job_blown(line: int, job: Dictionary)
signal big_score_ready()
signal big_score_started()
signal big_score_jackpot(shot: StringName)
signal big_score_vault()
signal big_score_ended()
signal take_changed(level: int)

enum LineState { OFFERED, SELECTED, RUNNING, DONE }

const PATH := "res://game/content/table_jobs.json"
const LINES := 3
const FUSE_SECONDS := 75.0
const FUSE_SPIN_SECONDS := 0.35
const FUSE_SPIN_MAX := 20.0
## Slow Burn (the Ledger): every Job's fuse, this much longer.
const SLOW_BURN_SCALE := 1.33
const TAKE_STEPS: PackedFloat32Array = [1.0, 2.0, 3.0, 4.0, 5.0, 8.0]
const VAULT_SHOT := &"luckys"
## Every shot a Job can ask for, and the Ledger hardware that has to stand for it to be askable.
const SHOT_HARDWARE := {
	&"alley": &"",
	&"dropoff": &"rollovers",
	&"wire": &"wire_bank",
	&"spinner": &"spinner_numbers",
	&"getaway": &"orbit_left",
	&"luckys": &"laundromat_loop",
	&"beat_cop": &"bribe_target",
	&"nonnas": &"storefront_pizzeria",
	&"fat_tonys": &"storefront_pawn",
	&"truck_route": &"orbit_right",
	&"staircase": &"staircase_ramp",
}
## The Big Score's jackpots: the major shots (the ones with arrows).
const JACKPOT_SHOTS: Array[StringName] = [&"getaway", &"wire", &"staircase", &"nonnas", &"alley",
		&"fat_tonys", &"beat_cop", &"truck_route"]

var catalogue: Array[Dictionary] = []
var lines: Array[Dictionary] = []          ## {job, state, left: {shot: n}}
var selected: int = -1
var running: int = -1
var fuse_left: float = 0.0
var fuse_total: float = FUSE_SECONDS
var done_tonight: int = 0
var big_score_lit: bool = false
var big_score_active: bool = false
var jackpots_left: Array[StringName] = []
var vault_lit: bool = false
var take_level: int = 0
var owned_shots: Array[StringName] = []
var fuse_scale: float = 1.0
## Career tallies (saved).
var jobs_done_total: int = 0
var big_scores_total: int = 0
## Tonight's, for The Count.
var night_jobs_done: int = 0
var night_jobs_blown: int = 0
var night_big_scores: int = 0
var night_jackpots: int = 0

var _spin_bought: float = 0.0
## The table reports the Lucky's visit that takes a Job as a shot as well; that one is the
## taking, not the first of the Job's shots.
var _taken_at_luckys: bool = false


func _init() -> void:
	var raw := _read_json(PATH)
	for row: Variant in raw.get("jobs", []):
		if row is Dictionary and (row as Dictionary).has("id") and (row as Dictionary).has("shots"):
			catalogue.append(row)


## The shots that exist on this table tonight, from the Ledger's hardware.
static func shots_owned(has_hardware: Callable) -> Array[StringName]:
	var out: Array[StringName] = []
	for shot: StringName in SHOT_HARDWARE:
		var hw: StringName = SHOT_HARDWARE[shot]
		if hw == &"" or bool(has_hardware.call(hw)):
			out.append(shot)
	return out


## The Wire is open for business once the payphones and Lucky's both stand.
static func open_for(shots: Array[StringName]) -> bool:
	return shots.has(&"wire") and shots.has(&"luckys")


static func eligible(job: Dictionary, rank: int, shots: Array[StringName]) -> bool:
	if int(job.get("min_rank", 0)) > rank:
		return false
	for shot: Variant in (job.get("shots", {}) as Dictionary):
		if not shots.has(StringName(shot)):
			return false
	return true


func begin_night(rank: int, shots: Array[StringName], rng: RandomNumberGenerator) -> void:
	owned_shots = shots.duplicate()
	lines.clear()
	selected = -1
	running = -1
	fuse_left = 0.0
	_taken_at_luckys = false
	done_tonight = 0
	big_score_lit = false
	big_score_active = false
	jackpots_left.clear()
	vault_lit = false
	take_level = 0
	night_jobs_done = 0
	night_jobs_blown = 0
	night_big_scores = 0
	night_jackpots = 0
	if not open_for(shots):
		changed.emit()
		return
	var pool: Array[Dictionary] = []
	for j in catalogue:
		if eligible(j, rank, shots):
			pool.append(j)
	# harder rows first in the file: deal from the whole pool, then order the lines by tier
	while lines.size() < LINES and not pool.is_empty():
		var pick := rng.randi_range(0, pool.size() - 1) if rng != null else 0
		lines.append({"job": pool[pick], "state": LineState.OFFERED, "left": {}})
		pool.remove_at(pick)
	changed.emit()


func live() -> bool:
	return not lines.is_empty()


## Every line of Tonight's Work is done: the payphones have nothing left to ring.
func all_done() -> bool:
	return live() and done_tonight >= lines.size()


func line_job(line: int) -> Dictionary:
	return lines[line]["job"] if line >= 0 and line < lines.size() else {}


func line_state(line: int) -> int:
	return int(lines[line]["state"]) if line >= 0 and line < lines.size() else -1


## A payphone rang: line `line` is the Job the player is picking up.
func select(line: int) -> bool:
	if running >= 0 or big_score_active or line < 0 or line >= lines.size():
		return false
	if int(lines[line]["state"]) == LineState.DONE:
		return false
	for i in range(lines.size()):
		if int(lines[i]["state"]) == LineState.SELECTED:
			lines[i]["state"] = LineState.OFFERED
	lines[line]["state"] = LineState.SELECTED
	selected = line
	job_selected.emit(line)
	changed.emit()
	return true


## The next line a hit on the Wire would ring (payphones cycle through the open lines).
func next_open_line(after: int) -> int:
	for k in range(1, lines.size() + 1):
		var i := (after + k) % lines.size()
		if int(lines[i]["state"]) != LineState.DONE:
			return i
	return -1


## A ball into Lucky's. Returns what it started: &"big_score", &"vault", &"job" or &"".
func on_lucky() -> StringName:
	if big_score_active and vault_lit:
		vault_lit = false
		big_score_vault.emit()
		_relight_jackpots()
		changed.emit()
		return &"vault"
	if big_score_lit and not big_score_active:
		_start_big_score()
		return &"big_score"
	if running < 0 and live():
		if selected < 0 or int(lines[selected]["state"]) != LineState.SELECTED:
			if not select(next_open_line(-1)):
				return &""
		_start_job(selected)
		return &"job"
	return &""


func _start_job(line: int) -> void:
	running = line
	var job: Dictionary = lines[line]["job"]
	fuse_total = float(job.get("fuse", FUSE_SECONDS)) * fuse_scale
	fuse_left = fuse_total
	_spin_bought = 0.0
	var left := {}
	for shot: Variant in (job.get("shots", {}) as Dictionary):
		left[StringName(shot)] = int(job["shots"][shot])
	lines[line]["left"] = left
	lines[line]["state"] = LineState.RUNNING
	_taken_at_luckys = true
	job_started.emit(line)
	changed.emit()


## A shot the table reports. True if it counted for a Job or a jackpot.
func on_shot(shot: StringName) -> bool:
	if _taken_at_luckys:
		_taken_at_luckys = false
		if shot == VAULT_SHOT:
			return false
	var counted := false
	if big_score_active and jackpots_left.has(shot):
		jackpots_left.erase(shot)
		night_jackpots += 1
		big_score_jackpot.emit(shot)
		if jackpots_left.is_empty():
			vault_lit = true
		counted = true
	if running >= 0:
		var left: Dictionary = lines[running]["left"]
		if int(left.get(shot, 0)) > 0:
			left[shot] = int(left[shot]) - 1
			counted = true
			var all_in := true
			for s: Variant in left:
				if int(left[s]) > 0:
					all_in = false
					break
			if all_in:
				_finish_job()
	if shot == &"spinner" and running >= 0 and _spin_bought < FUSE_SPIN_MAX:
		var buy := minf(minf(FUSE_SPIN_SECONDS, FUSE_SPIN_MAX - _spin_bought), fuse_total - fuse_left)
		if buy > 0.0:
			_spin_bought += buy
			fuse_left += buy
	if counted:
		changed.emit()
	return counted


func _finish_job() -> void:
	var line := running
	var job: Dictionary = lines[line]["job"]
	lines[line]["state"] = LineState.DONE
	running = -1
	selected = -1
	fuse_left = 0.0
	done_tonight += 1
	night_jobs_done += 1
	jobs_done_total += 1
	job_done.emit(line, job)
	if done_tonight >= lines.size() and not big_score_lit:
		big_score_lit = true
		big_score_ready.emit()


func _blow() -> void:
	var line := running
	var job: Dictionary = lines[line]["job"]
	lines[line]["state"] = LineState.OFFERED
	lines[line]["left"] = {}
	running = -1
	selected = -1
	fuse_left = 0.0
	night_jobs_blown += 1
	job_blown.emit(line, job)
	changed.emit()


func _start_big_score() -> void:
	big_score_active = true
	big_score_lit = false
	big_scores_total += 1
	night_big_scores += 1
	_relight_jackpots()
	big_score_started.emit()
	changed.emit()


func _relight_jackpots() -> void:
	jackpots_left.clear()
	for shot: StringName in JACKPOT_SHOTS:
		if owned_shots.has(shot):
			jackpots_left.append(shot)


## Back to one ball: the Big Score is over. Finishing it once re-deals nothing; the Night's
## lines stay done.
func end_big_score() -> void:
	if not big_score_active:
		return
	big_score_active = false
	jackpots_left.clear()
	vault_lit = false
	big_score_ended.emit()
	changed.emit()


func tick(delta: float) -> void:
	if running < 0 or delta <= 0.0:
		return
	fuse_left -= delta
	if fuse_left <= 0.0:
		_blow()


func fuse_fraction() -> float:
	return clampf(fuse_left / fuse_total, 0.0, 1.0) if running >= 0 and fuse_total > 0.0 else 0.0


# ------------------------------------------------------------------ the Take -----


func advance_take() -> void:
	if take_level >= TAKE_STEPS.size() - 1:
		return
	take_level += 1
	take_changed.emit(take_level)
	changed.emit()


func reset_take() -> void:
	if take_level == 0:
		return
	take_level = 0
	take_changed.emit(take_level)
	changed.emit()


func take_multiplier() -> float:
	return TAKE_STEPS[clampi(take_level, 0, TAKE_STEPS.size() - 1)]


# ------------------------------------------------------------------ the lamps -----


## What the arrows should say: shot -> [mode, colour-key]. Modes are InsertField.Mode values.
func arrow_states() -> Dictionary:
	var out := {}
	if big_score_active:
		for shot: StringName in jackpots_left:
			out[shot] = [2, &"jackpot"]
		if vault_lit:
			out[VAULT_SHOT] = [2, &"vault"]
		return out
	if big_score_lit:
		out[VAULT_SHOT] = [2, &"big_score"]
		return out
	if running >= 0:
		var left: Dictionary = lines[running]["left"]
		for shot: Variant in left:
			if int(left[shot]) > 0:
				out[StringName(shot)] = [2, &"job"]
		return out
	if selected >= 0:
		for shot: Variant in (lines[selected]["job"].get("shots", {}) as Dictionary):
			out[StringName(shot)] = [1, &"job"]
		out[VAULT_SHOT] = [2, &"accept"]
		return out
	if live() and not all_done():
		out[&"wire"] = [1, &"phone"]
	return out


## One HUD line for the Job on the board.
func headline() -> String:
	if big_score_active:
		if vault_lit:
			return "BIG SCORE: THE VAULT IS OPEN AT LUCKY'S"
		return "BIG SCORE: %d JACKPOTS LIT" % jackpots_left.size()
	if big_score_lit:
		return "BIG SCORE IS LIT: SHOOT LUCKY'S"
	if running >= 0:
		var job: Dictionary = lines[running]["job"]
		return "%s  %s  %ds" % [String(job.get("name", "JOB")).to_upper(), _left_text(lines[running]["left"]), int(ceil(fuse_left))]
	if selected >= 0:
		return "SHOOT LUCKY'S TO TAKE %s" % String(lines[selected]["job"].get("name", "JOB")).to_upper()
	if all_done():
		return "TONIGHT'S WORK IS DONE"
	if live():
		var next := next_open_line(-1)
		if next >= 0:
			return "SHOOT LUCKY'S FOR A JOB: %s" % String(lines[next]["job"].get("name", "JOB")).to_upper()
	return ""


## A shot as the player reads it on the playfield.
const SHOT_NAMES := {
	&"alley": "THE CANS", &"dropoff": "DROP-OFF LANES", &"wire": "PAYPHONES", &"spinner": "SPINNER",
	&"getaway": "GETAWAY", &"luckys": "LUCKY'S", &"beat_cop": "BEAT COP", &"nonnas": "NONNA'S",
	&"fat_tonys": "FAT TONY'S", &"truck_route": "TRUCK ROUTE", &"staircase": "STAIRCASE",
}


static func shot_name(shot: StringName) -> String:
	return String(SHOT_NAMES.get(shot, String(shot).replace("_", " ").to_upper()))


static func _left_text(left: Dictionary) -> String:
	var parts: PackedStringArray = []
	for shot: Variant in left:
		var n := int(left[shot])
		if n > 0:
			parts.append("%s ×%d" % [shot_name(StringName(shot)), n])
	return " · ".join(parts)


# ------------------------------------------------------------------ data -----


func night_summary() -> Dictionary:
	return {
		"done": night_jobs_done,
		"blown": night_jobs_blown,
		"lines": lines.size(),
		"big_scores": night_big_scores,
		"jackpots": night_jackpots,
	}


func to_dict() -> Dictionary:
	return {"jobs_done": jobs_done_total, "big_scores": big_scores_total}


func from_dict(d: Dictionary) -> void:
	if d == null:
		return
	jobs_done_total = int(d.get("jobs_done", 0))
	big_scores_total = int(d.get("big_scores", 0))


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
