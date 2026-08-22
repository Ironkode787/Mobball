class_name SimTable
extends RefCounted
## The playfield as a weighted shot menu: which switches exist right now, how often a ball
## finds each one, and what each one is worth before the economy touches it.
##
## The values are `TableScore`'s, mirrored (a RefCounted sim must not preload the table
## scene). The *weights* are the model: they say "a loose ball spends its time in the bumper
## nest, and only an aimed shot goes up the numbers lane", scaled by the profile's affinity.
## Nothing here decides money — it decides which `Game.earn_switch` call happens next.
##
## Switch ids match `game/table/segments/progression_table.gd` exactly (`bumper_1`, `sling_l`,
## `rollover_2`, `wire_3`, `wire_bank_complete`, `storefront_pawn_collect`, `orbit_left`,
## `laundromat_loop`) because the real `Jobs` checks parse them.

enum Kind {
	BUMPER, SLING, ROLLOVER, SPINNER, WIRE, STOREFRONT, ORBIT, WASH,
	# M2, the Club (specs/m2-content.md §1): the Staircase downstairs, and the deck's own
	# menu upstairs. A deck row is only ever picked from `SimTable.deck`.
	RAMP, ROULETTE, REEL, HIGH_ROLLER, BACKROOM,
}

# --- mirrors of Spinner (game/table/hardware/spinner.gd) --------------------------
## Mirrored rather than referenced: `Spinner` is a Node2D in the table lane's tree and
## reaching for it drags the whole hardware stack (and `AudioDirector`) into a RefCounted
## sim. tests/test_sim_smoke.gd asserts these three against the real class.
const SPIN_FRICTION := 25.0
const SPIN_MAX_SPEED := 78.0
const SPIN_MIN_KICK := 6.0

# --- mirrors of TableScore (specs/m1-hook.md Lane 3 economics) ---------------------
const BUMPER := 10.0
const SLING := 5.0
const SPINNER_SEGMENT := 25.0
const ROLLOVER := 25.0
const WIRE_TARGET := 150.0
const BANK_COMPLETE := 1000.0
const ORBIT := 500.0
## M2 courtesy switches (specs/m2-empire.md TABLE-2): the real money on the deck is the bet,
## so the wheel and the reels pay a token and the flow lane settles the rest.
const RAMP_CLIMB := 750.0
const CASINO_POCKET := 100.0
const CASINO_REEL := 100.0
## Mirrors `Storefront.open_seconds` / `rearm_seconds` and `TargetBank.reset_seconds`.
const STOREFRONT_OPEN_SEC := 6.0
const STOREFRONT_REARM_SEC := 20.0
const STOREFRONT_TARGETS := 3
const WIRE_TARGETS := 3
const WIRE_RESET_SEC := 2.0
## Mirrors `NightController.WASH_COOLDOWN` (flow) against `Storefront.WASH_COOLDOWN` (table):
## the slower of the two is what a player actually gets.
const WASH_COOLDOWN := 1.6

# --- mirrors of the Club deck (game/table/segments/club_deck.gd, slot_reels.gd) -----
## The slots: a 3×3 grid of drop targets, one column per reel, each column three shots deep
## and re-arming on its own timer. Clearing all three columns inside ONE deck visit is the
## Jackpot (`Casino.CasinoRules.JACKPOT_COLUMNS`).
const SLOT_COLUMNS := 3
const SLOT_ROWS := 3
const SLOT_RESET_SEC := 2.0
## The wheel as built: eight pockets, three of them the house's, given back in this order as
## Loaded Dice buys them (`RouletteWheel.HOUSE_POCKETS` / `HOUSE_GIVE_ORDER`).
const ROULETTE_POCKETS := 8
const HOUSE_POCKETS: PackedInt32Array = [0, 3, 6]
const HOUSE_GIVE_ORDER: PackedInt32Array = [6, 3, 0]
## Seconds per rung of the High Roller ladder (`HoldSaucer.step_seconds` as the deck sets it).
## Greed costs deck time as well as Heat, which is what makes the ladder a decision.
const HIGH_ROLLER_STEP_SEC := 0.9

# --- shot weights (the model's assumptions) ---------------------------------------
## Per live trash can. The nest is where an unaimed ball lives, which is exactly why the
## first upgrades are cans: they raise the floor of bad play.
const W_BUMPER := 3.0
## Per slingshot. They fire on nearly every return pass; nobody aims at them.
const W_SLING := 2.5
## Per top lane. Rolled on feeds and on anything that comes back over the arch.
const W_ROLLOVER := 0.8
## The numbers lane: one aimed shot up the left channel.
const W_SPINNER := 1.0
## Per payphone. Three standups in a cluster on the right — a spray hits something.
const W_WIRE := 1.2
## Per storefront bank. Wide targets across the waist, hard to miss and easy to waste.
const W_STOREFRONT := 1.4
## The getaway loop: a full-speed aimed orbit.
const W_ORBIT := 0.9
## The Staircase mouth, downstairs: one aimed shot up the right-hand corridor. Whether it
## CLIMBS is a separate speed gate (`SimProfile.stair_take`) — this is only how often a ball
## is pointed at it.
const W_RAMP := 0.4

# --- the deck's own menu (upstairs) ------------------------------------------------
## The wheel is the deck's sink: the ceiling channel runs out of guide above it, so every lap
## of the deck's little orbit ends in the bowl. Nothing else up there gets that much traffic.
const W_ROULETTE := 3.0
## Per reel column (three targets deep).
const W_REEL := 1.6
const W_HIGH_ROLLER := 0.8
const W_BACKROOM := 0.7
## Switch closures per second of DECK time. Pinned to a cadence rather than run through
## `shot_rate` because the deck is not a nest: the loop up there is wheel → eject → ceiling
## channel → wheel, a ~3 s lap with a 1.2 s pocket hold in it, and a bumper-nest shot rate
## would invent five times the spins the geometry can deliver. The constant folds travel and
## hold together; `club_flippers` is what turns one lap into a rally.
const DECK_SHOTS_PER_SEC := 0.45
const DECK_FLIPPER_RATE := 1.6
## A deck with no mini-bats is a one-way trip: in, round the loop, out the return lane.
const DECK_NO_FLIPPERS := 0.35

## How busy a table has to be before a ball is closing switches at the profile's quoted
## rate. A ball finds switches at a rate set by how much steel is in its way: the bare alley
## (one trash can, raw weight 3) is a quiet roll to the drain, a built-out T3 table (raw
## weight ~26) rattles. `shot_rate` runs the raw weight through a saturating curve pinned so
## that raw weight WEIGHT_HALF pays exactly `profile.switches_per_sec`, and an infinitely
## busy table pays twice that. This is what makes "Second Trash Can" worth $80.
const WEIGHT_HALF := 12.0
## Flipper power buys reach: harder flips put more shots on target. Half the multiplier goes
## to the shot rate, all of it to the spinner kick.
const FLIPPER_POWER_TO_RATE := 0.5

const STOREFRONT_HARDWARE: Array[StringName] = [
	&"storefront_laundromat", &"storefront_pizzeria", &"storefront_pawn",
]
## Fallback rates if a content edit drops the `idle_rate_add` (mirrors TableScore's).
const STOREFRONT_IDLE_FALLBACK := {
	&"storefront_laundromat": 60.0,
	&"storefront_pizzeria": 90.0,
	&"storefront_pawn": 120.0,
}

## Menu rows: { kind, id, group, base, weight, index }.
var shots: Array[Dictionary] = []
var total_weight: float = 0.0
## Sum of the weights BEFORE the profile's affinity — how much live hardware is out there,
## which is a property of the table, not of the player. Drives `shot_rate()`.
var raw_weight: float = 0.0
var storefronts: Array[StringName] = []
## The Club's upper deck as its own menu, or null when the licence has not been bought. It is
## a whole second table: the ball only reaches it up the Staircase, and while it is up there
## the downstairs menu does not exist (see SimClub).
var deck: SimTable = null
## Mini-bats on the deck (`club_flippers`) — the difference between one lap and a rally.
var deck_flippers: bool = false
var wash_live: bool = false
## True once a storefront bank stands in front of Lucky's door: the wash stops being a
## free-standing doorway and starts riding the bank/door/re-arm cycle (see SimNight).
var wash_gated_by_bank: bool = false

var _cum: PackedFloat32Array = []
var _rows_by_group: Dictionary = {}

## Racket rates keyed by catalog+hardware: the projection asks for these thousands of times
## per simulated day and the answer only changes when the content file does.
static var _idle_cache: Dictionary = {}


## Build the menu for the hardware this Stats has unlocked.
static func build(stats: Stats, profile: SimProfile, catalog: Upgrades = null) -> SimTable:
	var t := SimTable.new()
	t._build(stats, profile, catalog if catalog != null else Upgrades.shared())
	return t


## Weighted pick. Returns an empty Dictionary only if the table has no live switches at all,
## which cannot happen — the bare alley always has its one trash can.
func pick(rng: RandomNumberGenerator) -> Dictionary:
	if shots.is_empty() or total_weight <= 0.0:
		return {}
	var r := rng.randf() * total_weight
	for i in _cum.size():
		if r <= _cum[i]:
			return shots[i]
	return shots[shots.size() - 1]


## A shot into a group the ball is already working — the nest it is rattling in, the bank it
## is chewing through. Returns {} if that group has no switches.
func pick_in_group(group: StringName, rng: RandomNumberGenerator) -> Dictionary:
	var rows: PackedInt32Array = _rows_by_group.get(group, PackedInt32Array())
	if rows.is_empty():
		return {}
	return shots[rows[rng.randi() % rows.size()]]


## Dirty per second of one protection racket, read from the catalog exactly like
## `TableScore.storefront_idle_per_sec` reads it from the content file.
static func storefront_idle_per_sec(hardware: StringName, catalog: Upgrades) -> float:
	var key := "%d/%s" % [catalog.get_instance_id(), hardware]
	if _idle_cache.has(key):
		return float(_idle_cache[key])
	var rate := _scan_idle(hardware, catalog)
	_idle_cache[key] = rate
	return rate


static func _scan_idle(hardware: StringName, catalog: Upgrades) -> float:
	for n in catalog.nodes:
		var effects: Array = n["effects"]
		var unlocks := false
		var rate := -1.0
		for effect: Variant in effects:
			var e: Dictionary = effect
			if StringName(e["kind"]) == &"unlock_hardware" and StringName(e["target"]) == hardware:
				unlocks = true
			elif StringName(e["kind"]) == &"idle_rate_add":
				rate = (e["money"] as BigMoney).approx_float()
		if unlocks and rate >= 0.0:
			return rate
	return float(STOREFRONT_IDLE_FALLBACK.get(hardware, 0.0))


## What one collection pays before the economy touches it: `collect_minutes` of that
## racket's idle rate (docs/02 §2 R3, mirrored from `TableScore.storefront_collect_value`).
static func collect_value(hardware: StringName, stats: Stats, catalog: Upgrades) -> BigMoney:
	return BigMoney.from_float(storefront_idle_per_sec(hardware, catalog) * stats.collect_minutes() * 60.0)


## Segments a spinner pass pays out from a blade speed, straight off `Spinner`'s physics:
## the blade sheds FRICTION rad/s², one switch per half turn, so a kick at v rad/s travels
## v²/(2·FRICTION) radians and closes v²/(2·FRICTION·π) switches before it stops.
static func spin_segments(speed: float) -> int:
	var v := clampf(absf(speed), 0.0, SPIN_MAX_SPEED)
	return int(floor(v * v / (2.0 * SPIN_FRICTION * PI)))


## Switch closures per second of live ball on this table, for this player.
func shot_rate(profile: SimProfile, stats: Stats) -> float:
	var w := maxf(raw_weight, 0.0001)
	var busy := 2.0 * w / (w + WEIGHT_HALF)
	var power := 1.0 + (stats.flipper_power() - 1.0) * FLIPPER_POWER_TO_RATE
	return profile.switches_per_sec * busy * power


# --- internals --------------------------------------------------------------------


func _build(stats: Stats, profile: SimProfile, catalog: Upgrades) -> void:
	var bumpers := profile.affinity_for(&"bumpers")
	# The bare alley: one dented can, and nothing else worth money (docs/02 §2 R0).
	_add(Kind.BUMPER, &"bumper_1", &"bumpers", BUMPER, W_BUMPER, bumpers)
	for i in [2, 3]:
		if stats.hardware_unlocked(StringName("bumper_%d" % i)):
			_add(Kind.BUMPER, StringName("bumper_%d" % i), &"bumpers", BUMPER, W_BUMPER, bumpers)
	if stats.hardware_unlocked(&"slingshots"):
		for id in [&"sling_l", &"sling_r"]:
			_add(Kind.SLING, id, &"slings", SLING, W_SLING, profile.affinity_for(&"slings"))
	if stats.hardware_unlocked(&"rollovers"):
		for i in range(3):
			_add(Kind.ROLLOVER, StringName("rollover_%d" % (i + 1)), &"rollovers", ROLLOVER,
					W_ROLLOVER, profile.affinity_for(&"rollovers"))
	if stats.hardware_unlocked(&"spinner_numbers"):
		_add(Kind.SPINNER, &"spinner_numbers", &"spinner", SPINNER_SEGMENT, W_SPINNER,
				profile.affinity_for(&"spinner"))
	if stats.hardware_unlocked(&"wire_bank"):
		for i in range(WIRE_TARGETS):
			_add(Kind.WIRE, StringName("wire_%d" % (i + 1)), &"wire", WIRE_TARGET, W_WIRE,
					profile.affinity_for(&"wire"))
	for hw in STOREFRONT_HARDWARE:
		if stats.hardware_unlocked(hw):
			storefronts.append(hw)
			_add(Kind.STOREFRONT, hw, &"storefronts", 0.0, W_STOREFRONT,
					profile.affinity_for(&"storefronts"))
	if stats.hardware_unlocked(&"orbit_left"):
		_add(Kind.ORBIT, &"orbit_left", &"orbit", ORBIT, W_ORBIT, profile.affinity_for(&"orbit"))
	if stats.hardware_unlocked(&"staircase_ramp"):
		_add(Kind.RAMP, &"staircase_ramp", &"ramps", RAMP_CLIMB, W_RAMP,
				profile.affinity_for(&"ramps"))
	if stats.hardware_unlocked(&"club_deck"):
		deck = SimTable.new()
		deck._build_deck(stats, profile)

	wash_live = stats.hardware_unlocked(&"laundromat_loop")
	wash_gated_by_bank = wash_live and stats.hardware_unlocked(&"storefront_laundromat")
	if wash_live and profile.wash_share > 0.0 and stats.launder_rate() > 0.0:
		# `wash_share` is a share of ALL shots, so its weight is solved for rather than set:
		# w / (W + w) = share. The door is a hole in the wall, not extra hardware, so it
		# adds no raw weight — putting the ball through it costs a shot instead of earning.
		var share := clampf(profile.wash_share * profile.affinity_for(&"wash"), 0.0, 0.9)
		shots.append({
			"kind": Kind.WASH, "id": &"laundromat_loop", "group": &"laundry", "base": 0.0,
			"base_big": BigMoney.zero(),
			"weight": total_weight * share / maxf(1.0 - share, 0.05), "index": shots.size(),
		})

	_index()


## Freeze the menu: the cumulative weights the picker binary-walks and the per-group index
## the cluster draw reads. Called once a menu is finished, downstairs or up.
func _index() -> void:
	_cum = PackedFloat32Array()
	_cum.resize(shots.size())
	_rows_by_group.clear()
	var acc := 0.0
	for i in shots.size():
		acc += float(shots[i]["weight"])
		_cum[i] = acc
		var group: StringName = shots[i]["group"]
		var rows: PackedInt32Array = _rows_by_group.get(group, PackedInt32Array())
		rows.append(i)
		_rows_by_group[group] = rows
	total_weight = acc


## The upper deck's menu. Built as its own SimTable because that is what it is: while the
## ball is upstairs the downstairs rows are not reachable at all, and the deck has its own
## traffic pattern (everything ends in the wheel).
func _build_deck(stats: Stats, profile: SimProfile) -> void:
	deck_flippers = stats.hardware_unlocked(&"club_flippers")
	if stats.hardware_unlocked(&"roulette_wheel"):
		_add(Kind.ROULETTE, &"roulette_wheel", &"casino", CASINO_POCKET, W_ROULETTE,
				profile.affinity_for(&"casino"))
	if stats.hardware_unlocked(&"slot_reels"):
		for c in SLOT_COLUMNS:
			_add(Kind.REEL, StringName("slot_reels_%d" % (c + 1)), &"casino", CASINO_REEL,
					W_REEL, profile.affinity_for(&"reels"))
	if stats.hardware_unlocked(&"high_roller_saucer"):
		_add(Kind.HIGH_ROLLER, &"high_roller_saucer", &"casino", 0.0, W_HIGH_ROLLER,
				profile.affinity_for(&"saucers"))
	if stats.hardware_unlocked(&"backroom_saucer"):
		_add(Kind.BACKROOM, &"backroom_saucer", &"casino", 0.0, W_BACKROOM,
				profile.affinity_for(&"saucers"))
	_index()


## Switch closures per second while the ball is on the deck. Not `shot_rate`: see
## DECK_SHOTS_PER_SEC for why the deck is a cadence and not a nest.
func deck_rate(profile: SimProfile) -> float:
	var aim := 0.7 + 0.3 * clampf(profile.target_discipline, 0.0, 1.0)
	return DECK_SHOTS_PER_SEC * aim * (DECK_FLIPPER_RATE if deck_flippers else 1.0)


## Mean seconds one visit upstairs lasts. Falling off the deck costs the trip, never the ball
## (the return lane catches everything), so this bounds the money, not the survival.
func deck_visit_seconds(profile: SimProfile) -> float:
	return profile.deck_seconds_mean * (1.0 if deck_flippers else DECK_NO_FLIPPERS)


## Is pocket `i` one the house still owns? The wheel keeps its own three and hands back the
## far side first (`RouletteWheel.HOUSE_GIVE_ORDER`), so the pockets a player has learned to
## aim at never move under him.
static func pocket_is_house(pocket: int, player_pockets: int) -> bool:
	var given := clampi(player_pockets - (ROULETTE_POCKETS - HOUSE_POCKETS.size()), 0,
			HOUSE_GIVE_ORDER.size())
	for i in HOUSE_POCKETS.size():
		if HOUSE_POCKETS[i] != pocket:
			continue
		for g in given:
			if HOUSE_GIVE_ORDER[g] == pocket:
				return false
		return true
	return false


func _add(kind: Kind, id: StringName, group: StringName, base: float, weight: float,
		affinity: float) -> void:
	raw_weight += weight
	var w := weight * affinity
	if w <= 0.0:
		return
	shots.append({
		"kind": kind, "id": id, "group": group, "base": base,
		# Prebuilt because the sim pays this exact amount thousands of times per Night and
		# BigMoney values are immutable by convention.
		"base_big": BigMoney.from_float(base),
		"weight": w, "index": shots.size(),
	})
	total_weight += w
