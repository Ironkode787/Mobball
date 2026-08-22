class_name TableScore
extends RefCounted
## The table's end of the single money path (specs/m1-hook.md): every switch worth money
## calls in here, and this calls `Game.earn_switch` — nothing on the table ever touches the
## wallet, the heat meter or a multiplier itself.
##
## The per-switch numbers live here rather than in the hardware scripts so the whole payout
## table can be read in one screen (specs/m1-hook.md Lane 3 economics).

const BUMPER := 10.0
const SLING := 5.0
const SPINNER_SEGMENT := 25.0
const ROLLOVER := 25.0
const WIRE_TARGET := 150.0
const BANK_COMPLETE := 1000.0
const ORBIT := 500.0
## M2 — the Club (specs/m2-empire.md TABLE-2). The casino pieces pay a courtesy switch only:
## the real money on this deck is the bet, and the flow lane owns bets.
const RAMP_CLIMB := 750.0
const CASINO_POCKET := 100.0
const CASINO_REEL := 100.0
## M3 — the Docks and the Penthouse (specs/m3-fall-rise.md TABLE-3). A crate is a mid-table
## switch worth roughly a wire target's bank; a Commission chair is the biggest single switch
## on the machine, because there are only five of them and the room costs a rank to reach.
const SMUGGLING_CONTAINER := 400.0
const PENTHOUSE_CHAIR := 2000.0

const GROUP_BUMPERS := &"bumpers"
const GROUP_SLINGS := &"slings"
const GROUP_SPINNER := &"spinner"
const GROUP_ROLLOVERS := &"rollovers"
const GROUP_WIRE := &"wire"
const GROUP_STOREFRONTS := &"storefronts"
const GROUP_ORBIT := &"orbit"
const GROUP_RAMPS := &"ramps"
const GROUP_CASINO := &"casino"
const GROUP_SMUGGLING := &"smuggling"
const GROUP_PENTHOUSE := &"penthouse"

const UPGRADES_PATH := "res://game/content/upgrades.json"

## Dirty per second each protection racket idles at. Read from the `idle_rate_add` effect on
## the storefront nodes in game/content/upgrades.json so design can tune it as data; these
## are the shipped values, kept as the fallback if the content file ever moves.
const STOREFRONT_IDLE_FALLBACK := {
	&"storefront_laundromat": 60.0,
	&"storefront_pizzeria": 90.0,
	&"storefront_pawn": 120.0,
}

static var _idle_rates: Dictionary = {}


## A switch that reports but does not pay (kickback, bribe, gate switches).
static func hit(id: StringName, ball: Node2D, strength: float = 0.0) -> void:
	Events.switch_hit.emit(id, ball, strength)


static func earn(group: StringName, base: float, id: StringName, ball: Node2D,
		strength: float = 0.0) -> BigMoney:
	return earn_big(group, BigMoney.from_float(base), id, ball, strength)


static func earn_big(group: StringName, base: BigMoney, id: StringName, ball: Node2D,
		strength: float = 0.0) -> BigMoney:
	Events.switch_hit.emit(id, ball, strength)
	Events.scored.emit(id, int(round(base.approx_float())))
	return Game.earn_switch(group, base)


## Pay for a switch that has already reported itself. A DropTarget announces its own closure
## from `drop()`, so a bank that pays per target (the Club's slot reels) must not report it a
## second time — Jobs count switch ids, and one hit is one hit.
static func earn_quiet(group: StringName, base: float, id: StringName) -> BigMoney:
	Events.scored.emit(id, int(round(base)))
	return Game.earn_switch(group, BigMoney.from_float(base))


## A collection cashes out `Stats.collect_minutes()` minutes of that racket's idle rate
## (docs/02 §2 R3: "instantly cash out minutes of that racket's idle income").
static func storefront_collect_value(id: StringName) -> BigMoney:
	var minutes := 5.0
	if Game != null and Game.stats != null:
		minutes = Game.stats.collect_minutes()
	return BigMoney.from_float(storefront_idle_per_sec(id) * minutes * 60.0)


static func storefront_idle_per_sec(id: StringName) -> float:
	if _idle_rates.is_empty():
		_load_idle_rates()
	return float(_idle_rates.get(id, 0.0))


static func _load_idle_rates() -> void:
	_idle_rates = STOREFRONT_IDLE_FALLBACK.duplicate()
	if not FileAccess.file_exists(UPGRADES_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(UPGRADES_PATH))
	if not (parsed is Dictionary):
		return
	var nodes: Variant = (parsed as Dictionary).get("nodes", [])
	if not (nodes is Array):
		return
	for entry: Variant in nodes as Array:
		if not (entry is Dictionary):
			continue
		var hardware := &""
		var rate := -1.0
		for effect: Variant in (entry as Dictionary).get("effects", []):
			if not (effect is Dictionary):
				continue
			var e := effect as Dictionary
			match String(e.get("kind", "")):
				"unlock_hardware":
					var target := String(e.get("target", ""))
					if target.begins_with("storefront_"):
						hardware = StringName(target)
				"idle_rate_add":
					rate = BigMoney.parse(str(e.get("value", "0"))).approx_float()
		if hardware != &"" and rate >= 0.0:
			_idle_rates[hardware] = rate
