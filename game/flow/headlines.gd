class_name Headlines
extends RefCounted
## The morning paper (docs/03 §7, game/content/headlines.json). The Count's payoff line:
## first matching condition top-to-bottom, then a random variant, then placeholders.
##
## Pure and seeded — the same Night summary with the same RNG always prints the same
## front page, which is what makes the sims able to assert on it.

const PATH := "res://game/content/headlines.json"

## docs/02 §1 rank ladder — used by the {rank_title} placeholder.
const RANK_TITLES: PackedStringArray = [
	"LOOKOUT", "ERRAND BOY", "NUMBERS RUNNER", "SOLDIER",
	"CAPO", "UNDERBOSS", "BOSS", "KINGPIN",
]

## A Night that washed at least this fraction of its take is a laundering story.
const LAUNDERED_BIG_FRACTION := 0.5
## A record take has to beat the standing one by this much to be news.
const BIG_NIGHT_OVER_BEST := 1.25

var _rows: Array[Dictionary] = []


func _init() -> void:
	var raw := _read_json(PATH)
	for row: Variant in raw.get("headlines", []):
		if row is Dictionary:
			_rows.append(row as Dictionary)


func loaded() -> bool:
	return not _rows.is_empty()


## `summary` is the Night summary dict built by the flow lane (see NightController).
func pick(summary: Dictionary, rng: RandomNumberGenerator = null) -> String:
	var when := condition_for(summary)
	var text := _variant(when, rng)
	if text.is_empty() and when != "default":
		text = _variant("default", rng)
	return substitute(text, summary)


## Which headline condition this Night satisfies, top-to-bottom (file order is design order).
func condition_for(summary: Dictionary) -> String:
	for row in _rows:
		var when := String(row.get("when", ""))
		if when == "default" or matches(when, summary):
			return when
	return "default"


static func matches(when: String, s: Dictionary) -> bool:
	match when:
		"boss_beaten":
			# A Commission fight is the biggest front page there is, so it sits above
			# `rank_up` in file order — a win is always a rank-up as well.
			var boss: Variant = s.get("boss", {})
			return boss is Dictionary and bool((boss as Dictionary).get("won", false))
		"boss_lost":
			var lost: Variant = s.get("boss", {})
			return lost is Dictionary and not (lost as Dictionary).get("id", "").is_empty() \
					and not bool((lost as Dictionary).get("won", false))
		"rank_up":
			return bool(s.get("rank_up", false))
		"raid_survived":
			return String(s.get("raid", "")) == "survived"
		"raid_lost":
			return String(s.get("raid", "")) == "lost"
		"tilted":
			return int(s.get("tilts", 0)) > 0
		"all_guys_lost":
			# Not "the Night ended" (it always does) — nobody is left on the Bench.
			return int(s.get("bench_free", 1)) <= 0
		"laundered_big":
			var laundered: BigMoney = s.get("laundered", BigMoney.zero())
			var dirty: BigMoney = s.get("dirty", BigMoney.zero())
			if laundered == null or not laundered.is_positive():
				return false
			if dirty == null or not dirty.is_positive():
				return true
			return laundered.ratio_to(dirty) >= LAUNDERED_BIG_FRACTION
		"big_night":
			var dirty2: BigMoney = s.get("dirty", BigMoney.zero())
			var best: BigMoney = s.get("best_night", BigMoney.zero())
			if dirty2 == null or not dirty2.is_positive():
				return false
			if best == null or not best.is_positive():
				return false
			return dirty2.cmp(best.mul(BIG_NIGHT_OVER_BEST)) >= 0
		"quiet_night":
			var dirty3: BigMoney = s.get("dirty", BigMoney.zero())
			var floor_amount: BigMoney = s.get("quiet_floor", Rates.pocket_money_per_night())
			if dirty3 == null:
				return true
			return dirty3.cmp(floor_amount) <= 0
		"default":
			return true
	return false


static func substitute(text: String, s: Dictionary) -> String:
	var out := text
	out = out.replace("{dirty}", _money(s.get("dirty", null)))
	out = out.replace("{clean}", _money(s.get("clean", null)))
	out = out.replace("{laundered}", _money(s.get("laundered", null)))
	out = out.replace("{guys_lost}", str(int(s.get("guys_lost", 0))))
	out = out.replace("{night}", str(int(s.get("night", 0))))
	out = out.replace("{rank_title}", rank_title(int(s.get("rank", 0))))
	var boss: Variant = s.get("boss", {})
	if boss is Dictionary:
		out = out.replace("{boss}", String((boss as Dictionary).get("name", "")))
		out = out.replace("{spoil}", String((boss as Dictionary).get("spoil_name", "")))
	return out


static func rank_title(rank: int) -> String:
	return RANK_TITLES[clampi(rank, 0, RANK_TITLES.size() - 1)]


func _variant(when: String, rng: RandomNumberGenerator) -> String:
	for row in _rows:
		if String(row.get("when", "")) != when:
			continue
		var variants: Array = row.get("variants", [])
		if variants.is_empty():
			return ""
		var idx := 0
		if rng != null:
			idx = rng.randi() % variants.size()
		return String(variants[idx])
	return ""


static func _money(v: Variant) -> String:
	if v is BigMoney:
		return (v as BigMoney).text()
	return "$0"


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}
