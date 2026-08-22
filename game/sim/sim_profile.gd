class_name SimProfile
extends RefCounted
## One skill profile for the balance autoplayer (docs/09-TECH.md §7: duffer / decent / shark).
##
## A profile is the ONLY place the sim guesses. Everything downstream of it — values,
## multipliers, heat, laundering, costs, ranks — is the shipped economy code. So the split is
## deliberate: `game/sim/profiles.json` holds "how a human plays", the rest of the sim holds
## "what the game does about it". When telemetry lands, these numbers get replaced and every
## conclusion in the tuning report can be re-derived.
##
## Pure RefCounted, no Node, no autoload: the whole autoplayer runs under the bare test runner.

const PATH := "res://game/sim/profiles.json"
const SCHEMA := 2
## Profile order used by `--profile all` and every report table.
const ORDER: PackedStringArray = ["duffer", "decent", "shark"]

static var _cache: Dictionary = {}

var id: String = ""
var label: String = ""
var note: String = ""

# --- play -------------------------------------------------------------------------
## Mean of the exponential ball-survival draw, in seconds of live ball.
var ball_seconds_mean: float = 45.0
## Added to every draw: nobody drains in zero seconds, the ball has to get down there.
var ball_seconds_min: float = 6.0
## Scoring switch closures per second of live ball (bumper taps, lane rolls, target hits).
var switches_per_sec: float = 2.0
## Chance this guy tilts the machine away rather than draining honestly.
var tilt_per_ball: float = 0.03
## Chance of taking the lit lane on the plunge, when `rollovers` is owned.
var skill_shot_p: float = 0.3
## 0..1 — chance an aimed shot picks a target that is actually worth something right now
## (an unmarked payphone, an armed or open storefront) instead of a dead one. This is the
## single biggest skill lever in the model, and the one docs/03 §9 "skilled vs unskilled"
## is really measuring.
var target_discipline: float = 0.6
## rad/s handed to the spinner blade per pass — mirrors `Spinner`'s
## `ball.speed() * SPEED_PER_PX` clamped to MAX_SPEED. A duffer dribbles through the lane.
var spinner_kick_speed: float = 60.0
## Share of shots spent putting the ball through Lucky's door instead of earning.
var wash_share: float = 0.2
## Chance the next switch is in the SAME value group as the last one — the ball rattling in
## the nest, chewing through one drop bank, trading sling to sling. This is what makes
## `Combo` a skill: a chain only extends on a DIFFERENT group, so a player who lets the ball
## bounce where it lands never chains, and one who moves it around does. Without it, drawing
## every shot independently invents combo chains nobody earned.
var cluster: float = 0.45
## Buy a bribe above this heat (0 = never bribes).
var bribe_at_heat: float = 0.0
## 0..1 — how far up the High Roller ladder this player holds the ball before letting it go
## (`Casino.CasinoRules.HIGH_ROLLER_MULT`). Greed is the whole skill of that saucer: every
## rung multiplies the NEXT casino payout and adds flat Heat, so `risk_appetite` is the one
## profile number that trades money against the meter directly.
var risk_appetite: float = 0.4

# --- M2: the Club (specs/m2-content.md §1/§4) ---------------------------------------
## Chance an attempt at the Staircase mouth actually has the pace to climb. The mouth is a
## SPEED gate, not a switch (game/table/segments/club_deck.gd) — a soft shot is simply not
## taken and the ball carries on up the corridor, so this is the single number that decides
## how often a player sees the deck at all.
var stair_take: float = 0.5
## Mean seconds a visit to the deck lasts before the ball comes back down the return lane.
## Scaled by whether the mini-bats are bought: without `club_flippers` the deck is one lap.
var deck_seconds_mean: float = 13.0
## Mean seconds two balls stay out together once a Family Meeting starts — the ×2 window.
var meeting_seconds_mean: float = 19.0
## Chance of winning a Commission fight, per fight id (`sammy`, `butcher`). Unknown ids fall
## back to `boss_win_default`; a fight lost costs the Night and is retried.
var boss_win: Dictionary = {}
var boss_win_default: float = 0.5

# --- session / day ----------------------------------------------------------------
var sessions_per_day: float = 3.0
var nights_per_session: int = 4
## Seconds spent in The Count + The Ledger between two Nights of one session.
var count_seconds: float = 45.0

# --- purchase policy --------------------------------------------------------------
## 0 = buy only what is buyable now; 1..2 = also price a locked node together with the
## parents that would unlock it (see SimPolicy).
var lookahead: int = 1
## How many Nights of clean income this player is willing to bank for a better node before
## settling for a cheaper one.
var save_up_nights: float = 2.0
## Refuse purchases whose projected clean-per-night gain per dollar is below this.
var min_gain_per_cost: float = 0.0

var affinity: Dictionary = {}

var errors: PackedStringArray = []


## Every profile in the data file, keyed by id, parsed once per process.
static func load_all(path: String = PATH) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var out: Dictionary = {}
	var raw := _read_json(path)
	var profiles: Variant = raw.get("profiles", null)
	if not (profiles is Dictionary):
		push_error("sim: %s has no `profiles` object" % path)
		_cache[path] = out
		return out
	if int(raw.get("schema", 0)) != SCHEMA:
		push_error("sim: %s schema %s, this loader speaks %d" % [path, raw.get("schema", 0), SCHEMA])
	for key: Variant in profiles as Dictionary:
		var p := SimProfile.new()
		p._ingest(String(key), (profiles as Dictionary)[key])
		out[p.id] = p
	_cache[path] = out
	return out


static func get_profile(id: String, path: String = PATH) -> SimProfile:
	return load_all(path).get(id, null)


## Ids in report order, then anything the data file added that ORDER does not know about.
static func ids(path: String = PATH) -> PackedStringArray:
	var all := load_all(path)
	var out: PackedStringArray = []
	for id in ORDER:
		if all.has(id):
			out.append(id)
	var extra: PackedStringArray = []
	for id: Variant in all:
		if not out.has(String(id)):
			extra.append(String(id))
	extra.sort()
	out.append_array(extra)
	return out


## Relative weight multiplier this player puts on a value group. Unknown groups pay 1.0 —
## new hardware shows up in the sim before its profile weights do.
func affinity_for(group: StringName) -> float:
	return float(affinity.get(String(group), 1.0))


## Chance this player beats `fight_id` on one attempt (specs/m3-fall-rise.md SIM-2 opening
## bids). A fight the profile has never heard of is a coin toss rather than a crash.
func boss_win_chance(fight_id: StringName) -> float:
	return float(boss_win.get(String(fight_id), boss_win_default))


## Average hours between two session opens over a whole day (the projection's estimate of
## how much the Safe collects per session). The actual schedule bunches sessions into a
## waking window and puts the long gap overnight — see SimCareer.
func session_gap_hours() -> float:
	return 24.0 / maxf(sessions_per_day, 0.25)


# --- internals --------------------------------------------------------------------


func _ingest(key: String, raw: Variant) -> void:
	id = key
	label = key.capitalize()
	if not (raw is Dictionary):
		errors.append("%s: profile is not an object" % key)
		return
	var d := raw as Dictionary
	label = String(d.get("label", label))
	note = String(d.get("note", ""))
	ball_seconds_mean = _num(d, "ball_seconds_mean", ball_seconds_mean, 1.0, 1800.0)
	ball_seconds_min = _num(d, "ball_seconds_min", ball_seconds_min, 0.0, 600.0)
	switches_per_sec = _num(d, "switches_per_sec", switches_per_sec, 0.01, 40.0)
	tilt_per_ball = _num(d, "tilt_per_ball", tilt_per_ball, 0.0, 1.0)
	skill_shot_p = _num(d, "skill_shot_p", skill_shot_p, 0.0, 1.0)
	target_discipline = _num(d, "target_discipline", target_discipline, 0.0, 1.0)
	spinner_kick_speed = _num(d, "spinner_kick_speed", spinner_kick_speed, 0.0, SimTable.SPIN_MAX_SPEED)
	wash_share = _num(d, "wash_share", wash_share, 0.0, 1.0)
	cluster = _num(d, "cluster", cluster, 0.0, 0.95)
	bribe_at_heat = _num(d, "bribe_at_heat", bribe_at_heat, 0.0, 200.0)
	risk_appetite = _num(d, "risk_appetite", risk_appetite, 0.0, 1.0)
	stair_take = _num(d, "stair_take", stair_take, 0.0, 1.0)
	deck_seconds_mean = _num(d, "deck_seconds_mean", deck_seconds_mean, 0.5, 600.0)
	meeting_seconds_mean = _num(d, "meeting_seconds_mean", meeting_seconds_mean, 0.5, 600.0)
	boss_win_default = _num(d, "boss_win_default", boss_win_default, 0.0, 1.0)
	boss_win = {}
	var wins: Variant = d.get("boss_win", {})
	if wins is Dictionary:
		for f: Variant in wins as Dictionary:
			boss_win[String(f)] = clampf(float((wins as Dictionary)[f]), 0.0, 1.0)
	sessions_per_day = _num(d, "sessions_per_day", sessions_per_day, 0.25, 24.0)
	nights_per_session = int(_num(d, "nights_per_session", float(nights_per_session), 1.0, 100.0))
	count_seconds = _num(d, "count_seconds", count_seconds, 0.0, 3600.0)
	lookahead = int(_num(d, "lookahead", float(lookahead), 0.0, 3.0))
	save_up_nights = _num(d, "save_up_nights", save_up_nights, 0.0, 100.0)
	min_gain_per_cost = _num(d, "min_gain_per_cost", min_gain_per_cost, 0.0, 1.0e9)
	var aff: Variant = d.get("affinity", {})
	affinity = {}
	if aff is Dictionary:
		for g: Variant in aff as Dictionary:
			affinity[String(g)] = maxf(float((aff as Dictionary)[g]), 0.0)


func _num(d: Dictionary, key: String, fallback: float, lo: float, hi: float) -> float:
	if not d.has(key):
		return fallback
	var v: Variant = d[key]
	if not (v is float or v is int) or not is_finite(float(v)):
		errors.append("%s.%s is not a number" % [id, key])
		return fallback
	return clampf(float(v), lo, hi)


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("sim: missing %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}
