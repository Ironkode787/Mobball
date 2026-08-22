class_name Jobs
extends RefCounted
## "Tonight's Work" (docs/05 §1) — the ☆ Respect faucet. Slips are data
## (`game/content/jobs.json`); this class implements the `check` ids and tracks progress.
##
## Pure logic with an internal clock fed by `tick()`: no nodes, no signals from the tree,
## so the whole job system unit-tests and replays deterministically. The NightController
## is the only thing that talks to it, and it forwards table events verbatim.

## A slip just completed. The Night awards the Respect and emits Events.job_completed.
signal completed(job: Dictionary, respect: int)

const PATH := "res://game/content/jobs.json"

## Every slip in the data file, keyed by id.
var pool: Dictionary = {}
## Tonight's slips: [{"id": String, "done": bool, "state": Dictionary}, …]
var active: Array[Dictionary] = []
## Ids completed at least once, ever — they do not come back around.
var done_ids: Dictionary = {}

var _clock: float = 0.0
var _ball_index: int = -1


func _init() -> void:
	var raw := _read_json(PATH)
	for row: Variant in raw.get("jobs", []):
		if row is Dictionary and (row as Dictionary).has("id"):
			pool[String((row as Dictionary)["id"])] = row


func loaded() -> bool:
	return not pool.is_empty()


func job(id: String) -> Dictionary:
	return pool.get(id, {})


func active_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for a in active:
		var j: Dictionary = pool.get(String(a["id"]), {})
		if not j.is_empty():
			out.append(j)
	return out


func is_done(id: String) -> bool:
	return done_ids.has(id)


# --- night lifecycle ----------------------------------------------------------


## Pick tonight's slips: keep unfinished ones, drop the finished, fill up to `slots` from
## the eligible pool (rank + owned hardware) in seeded-random order.
func roll(rank: int, stats: Stats, slots: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var kept: Array[Dictionary] = []
	for a in active:
		if not bool(a["done"]) and not done_ids.has(String(a["id"])):
			kept.append(a)
	active = kept
	var want := maxi(slots, 0)
	while active.size() > want:
		active.pop_back()

	var candidates: PackedStringArray = []
	for id: String in pool:
		if done_ids.has(id) or _is_active(id):
			continue
		if eligible(pool[id], rank, stats):
			candidates.append(id)
	candidates.sort()
	while active.size() < want and candidates.size() > 0:
		var pick := 0
		if rng != null:
			pick = rng.randi() % candidates.size()
		var id := candidates[pick]
		candidates.remove_at(pick)
		active.append({"id": id, "done": false, "state": _fresh_state(pool[id])})
	return active_jobs()


static func eligible(j: Dictionary, rank: int, stats: Stats) -> bool:
	if int(j.get("min_rank", 0)) > rank:
		return false
	var hw := String(j.get("requires_hardware", ""))
	if hw.is_empty():
		return true
	if stats == null:
		return false
	return stats.hardware_unlocked(StringName(hw))


## Fresh Night: per-Night counters go back to zero, the slips stay.
func begin_night() -> void:
	_clock = 0.0
	_ball_index = -1
	for a in active:
		a["state"] = _fresh_state(pool.get(String(a["id"]), {}))


## A guy takes the table. `index` is his position in tonight's line-up (0 = first guy).
func begin_ball(index: int) -> void:
	_ball_index = index
	for a in active:
		var st: Dictionary = a["state"]
		st["ball_n"] = 0
		st["ball_seen"] = {}
		st["alive"] = 0.0


# --- table events -------------------------------------------------------------


func tick(delta: float, heat: float) -> void:
	if delta <= 0.0:
		return
	_clock += delta
	for a in active:
		if bool(a["done"]):
			continue
		var j: Dictionary = pool.get(String(a["id"]), {})
		var st: Dictionary = a["state"]
		var params: Dictionary = j.get("params", {})
		match String(j.get("check", "")):
			"earn_under_heat":
				if heat > float(params.get("heat_max", 100.0)):
					st["blown"] = true
			"ball_survival":
				if _ball_index == 0:
					st["alive"] = float(st.get("alive", 0.0)) + delta
					if float(st["alive"]) >= float(params.get("seconds", 180.0)):
						_finish(a)


func on_switch(id: StringName, group: StringName) -> void:
	for a in active:
		if bool(a["done"]):
			continue
		var j: Dictionary = pool.get(String(a["id"]), {})
		var st: Dictionary = a["state"]
		var params: Dictionary = j.get("params", {})
		var want := String(params.get("group", ""))
		match String(j.get("check", "")):
			"bumper_burst":
				if group != &"bumpers":
					continue
				var stamps: Array = st.get("stamps", [])
				stamps.append(_clock)
				var window := float(params.get("window", 5.0))
				while stamps.size() > 0 and _clock - float(stamps[0]) > window:
					stamps.pop_front()
				st["stamps"] = stamps
				if stamps.size() >= int(params.get("count", 6)):
					_finish(a)
			"switch_count_one_ball":
				if not _in_group(id, group, want):
					continue
				st["ball_n"] = int(st.get("ball_n", 0)) + 1
				if int(st["ball_n"]) >= int(params.get("count", 3)):
					_finish(a)
			"switch_cover":
				if String(group) != want:
					continue
				var seen: Dictionary = st.get("seen", {})
				seen[String(id)] = true
				st["seen"] = seen
				if seen.size() >= int(Switches.COVER_SIZE.get(StringName(want), 3)):
					_finish(a)
			"bank_completions":
				if not (Switches.is_bank_complete(id) and String(id).begins_with(want)):
					continue
				st["n"] = int(st.get("n", 0)) + 1
				if int(st["n"]) >= int(params.get("count", 2)):
					_finish(a)


func on_earn(amount: BigMoney, _group: StringName) -> void:
	if amount == null or not amount.is_positive():
		return
	for a in active:
		if bool(a["done"]):
			continue
		var j: Dictionary = pool.get(String(a["id"]), {})
		if String(j.get("check", "")) != "earn_under_heat":
			continue
		var st: Dictionary = a["state"]
		var total := BigMoney.from_dict(st.get("earned", {})).add(amount)
		st["earned"] = total.to_dict()
		var params: Dictionary = j.get("params", {})
		if not bool(st.get("blown", false)) and total.cmp(BigMoney.parse(String(params.get("amount", "0")))) >= 0:
			_finish(a)


func on_launder(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	for a in active:
		if bool(a["done"]):
			continue
		var j: Dictionary = pool.get(String(a["id"]), {})
		if String(j.get("check", "")) != "launder_total":
			continue
		var st: Dictionary = a["state"]
		var total := BigMoney.from_dict(st.get("washed", {})).add(amount)
		st["washed"] = total.to_dict()
		var params: Dictionary = j.get("params", {})
		if total.cmp(BigMoney.parse(String(params.get("amount", "0")))) >= 0:
			_finish(a)


func on_storefront(id: StringName) -> void:
	for a in active:
		if bool(a["done"]):
			continue
		var j: Dictionary = pool.get(String(a["id"]), {})
		if String(j.get("check", "")) != "collect_all_one_ball":
			continue
		var st: Dictionary = a["state"]
		var seen: Dictionary = st.get("ball_seen", {})
		seen[String(id)] = true
		st["ball_seen"] = seen
		var want := String((j.get("params", {}) as Dictionary).get("group", "storefronts"))
		if seen.size() >= int(Switches.COVER_SIZE.get(StringName(want), 3)):
			_finish(a)


func on_bribe(heat_at_bribe: float) -> void:
	for a in active:
		if bool(a["done"]):
			continue
		var j: Dictionary = pool.get(String(a["id"]), {})
		if String(j.get("check", "")) != "bribe_above_heat":
			continue
		var params: Dictionary = j.get("params", {})
		if heat_at_bribe >= float(params.get("heat_min", 70.0)):
			_finish(a)


# --- internals ----------------------------------------------------------------


func _finish(entry: Dictionary) -> void:
	if bool(entry["done"]):
		return
	entry["done"] = true
	var j: Dictionary = pool.get(String(entry["id"]), {})
	done_ids[String(entry["id"])] = true
	completed.emit(j, int(j.get("respect", 0)))


func _is_active(id: String) -> bool:
	for a in active:
		if String(a["id"]) == id:
			return true
	return false


## Jobs name their target either as a value group (`spinner`) or as a hardware id prefix
## (`wire_bank`); both spellings are in the shipped data, so both are honoured.
static func _in_group(id: StringName, group: StringName, want: String) -> bool:
	if want.is_empty():
		return false
	return String(group) == want or String(id).begins_with(want)


static func _fresh_state(_j: Dictionary) -> Dictionary:
	return {
		"stamps": [],
		"seen": {},
		"ball_seen": {},
		"n": 0,
		"ball_n": 0,
		"alive": 0.0,
		"blown": false,
		"earned": BigMoney.zero().to_dict(),
		"washed": BigMoney.zero().to_dict(),
	}


## Progress comes back from JSON with every number a float and no key order to speak of.
## Rebuilding it on top of a fresh state fixes both, so a save/load cycle is a true no-op.
static func _sanitize_state(raw: Dictionary) -> Dictionary:
	var s := _fresh_state({})
	var stamps: Array = []
	for v: Variant in raw.get("stamps", []):
		stamps.append(float(v))
	s["stamps"] = stamps
	for key: String in ["seen", "ball_seen"]:
		var d: Variant = raw.get(key, {})
		if d is Dictionary:
			var clean := {}
			for k: Variant in d as Dictionary:
				clean[String(k)] = true
			s[key] = clean
	s["n"] = int(raw.get("n", 0))
	s["ball_n"] = int(raw.get("ball_n", 0))
	s["alive"] = float(raw.get("alive", 0.0))
	s["blown"] = bool(raw.get("blown", false))
	for key2: String in ["earned", "washed"]:
		var m: Variant = raw.get(key2, {})
		s[key2] = BigMoney.from_dict(m if m is Dictionary else {}).to_dict()
	return s


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# --- serialization ------------------------------------------------------------


func to_dict() -> Dictionary:
	var list: Array = []
	for a in active:
		list.append({"id": String(a["id"]), "done": bool(a["done"]), "state": (a["state"] as Dictionary).duplicate(true)})
	var ids: Array = done_ids.keys()
	ids.sort()
	return {"active": list, "done": ids}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	active.clear()
	for raw: Variant in d.get("active", []):
		if not (raw is Dictionary):
			continue
		var r: Dictionary = raw
		var id := String(r.get("id", ""))
		if id.is_empty() or not pool.has(id):
			continue
		var st: Variant = r.get("state", {})
		active.append({
			"id": id,
			"done": bool(r.get("done", false)),
			"state": _sanitize_state(st as Dictionary) if st is Dictionary else _fresh_state(pool[id]),
		})
	done_ids.clear()
	for raw2: Variant in d.get("done", []):
		done_ids[String(raw2)] = true
