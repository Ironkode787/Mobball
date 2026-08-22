class_name GuyTraits
extends RefCounted
## Guy traits v1 (docs/01 §4 "balls are guys", specs/m2-empire.md FLOW-2). One trait per
## guy, small but felt. The vocabulary is data (`game/content/names.json` → `traits_m2`);
## what each id *does* is here, because every effect lands on the money path, the Heat meter
## or a drain — and all three of those belong to the flow lane.
##
## Static and pure: no nodes, no autoload lookups, so the Bench can hand a trait out inside
## a headless test and `Game.earn_switch` can fold one without going through the tree.
##
## Folds are multiplicative ACROSS the guys currently on the table: during a Family Meeting
## two Loud guys really are twice as loud. With the usual single ball it is one guy's number,
## which is the case that has to stay obvious.

const PATH := "res://game/content/names.json"
## Nobodies are nobodies. Traits start being handed out once the crew is worth naming, which
## is R2 (docs/02 §1) — before that a new hire is a warm body with a nickname.
const MIN_RANK := 2

const LOUD := "loud"
const CAREFUL := "careful"
const FAST := "fast"
const OLD_TIMER := "old_timer"
const SLIPPERY := "slippery"
const LUCKY := "lucky"
const HEAVY := "heavy"

## Multiplier on every dirty payout while the guy is on the table.
const DIRTY_MULT := {"loud": 1.10, "fast": 1.10}
## Scale on Heat GAINS while he is fielded (HeatMeter.gain_scale).
const HEAT_SCALE := {"loud": 1.10, "careful": 0.85}
## Respect from Jobs finished on his watch.
const JOB_RESPECT_MULT := {"old_timer": 1.25}
## docs/03 §3 briefcase odds. Mystery briefcases are not in this sub-wave; the number lives
## here so the Lucky guys already on the roster mean something the day the trench coat lands.
const BRIEFCASE_ODDS_ADD := {"lucky": 0.05}

## HEAVY is deferred: "+mass, smashes gates, slower" is ball physics, and `game/core/ball.gd`
## is frozen (a per-ball mass/velocity-cap hook is the ask — see the FLOW-2 report). It stays
## in the vocabulary so a save that carries it still loads and the Count still names it; it is
## simply never dealt out, because a trait that does nothing is worse than one fewer trait.
const DEFERRED: PackedStringArray = ["heavy"]

static var _rows: Array = []
static var _loaded: bool = false


# ================================================================== vocabulary =====


## Every trait in the data file, as `{id, name, desc}` rows.
static func rows() -> Array:
	_load()
	return _rows


## Ids that can actually be dealt out (everything except the deferred ones).
static func dealable() -> PackedStringArray:
	var out := PackedStringArray()
	for row: Variant in rows():
		var id := String((row as Dictionary).get("id", ""))
		if not id.is_empty() and not DEFERRED.has(id):
			out.append(id)
	return out


## Display name ("Old-Timer"), falling back to the raw id so an unknown trait still reads.
static func label(id: String) -> String:
	if id.is_empty():
		return ""
	for row: Variant in rows():
		if String((row as Dictionary).get("id", "")) == id:
			return String((row as Dictionary).get("name", id))
	return id.capitalize()


static func describe(id: String) -> String:
	for row: Variant in rows():
		if String((row as Dictionary).get("id", "")) == id:
			return String((row as Dictionary).get("desc", ""))
	return ""


## The trait a new hire gets. Empty below MIN_RANK, and never a deferred one.
static func pick(rng: RandomNumberGenerator, rank: int) -> String:
	if rank < MIN_RANK:
		return ""
	var pool := dealable()
	if pool.is_empty():
		return ""
	var i := 0
	if rng != null:
		i = rng.randi() % pool.size()
	return pool[i]


static func of(guy: Dictionary) -> String:
	if guy == null or guy.is_empty():
		return ""
	return String(guy.get("trait", ""))


# ===================================================================== effects =====


static func dirty_mult(guy: Dictionary) -> float:
	return float(DIRTY_MULT.get(of(guy), 1.0))


static func heat_scale(guy: Dictionary) -> float:
	return float(HEAT_SCALE.get(of(guy), 1.0))


static func job_respect_mult(guy: Dictionary) -> float:
	return float(JOB_RESPECT_MULT.get(of(guy), 1.0))


## Reserved for the Mystery Briefcase roll (docs/03 §3). No consumer in this wave.
static func briefcase_odds_add(guy: Dictionary) -> float:
	return float(BRIEFCASE_ODDS_ADD.get(of(guy), 0.0))


## "One free outlane escape per Night" — the NightController spends it before it reaches for
## a kickback or a ball-save charge.
static func can_outlane_save(guy: Dictionary) -> bool:
	return of(guy) == SLIPPERY


# ======================================================================= folds =====


static func dirty_mult_for(guys: Array) -> float:
	var m := 1.0
	for g: Variant in guys:
		if g is Dictionary:
			m *= dirty_mult(g as Dictionary)
	return m


static func heat_scale_for(guys: Array) -> float:
	var m := 1.0
	for g: Variant in guys:
		if g is Dictionary:
			m *= heat_scale(g as Dictionary)
	return m


static func job_respect_mult_for(guys: Array) -> float:
	var m := 1.0
	for g: Variant in guys:
		if g is Dictionary:
			m *= job_respect_mult(g as Dictionary)
	return m


## Stars a Job pays with these guys on the table. Never fewer than the slip promised.
static func job_respect(stars: int, guys: Array) -> int:
	return maxi(int(round(float(stars) * job_respect_mult_for(guys))), stars)


# =================================================================== internals =====


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_rows = []
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (parsed is Dictionary):
		return
	var raw: Variant = (parsed as Dictionary).get("traits_m2", [])
	if not (raw is Array):
		return
	for row: Variant in raw as Array:
		if row is Dictionary and not String((row as Dictionary).get("id", "")).is_empty():
			_rows.append(row)
