class_name SimPolicy
extends RefCounted
## What the bot buys, and the projection it argues from.
##
## Policy: greedy with lookahead. Every revealed, rank-legal, un-maxed node is priced as
## "clean cash per Night this would add, per dollar it costs"; the best one wins. Nodes
## blocked only by `requires` are priced as a BUNDLE with the parents that would unlock them
## (depth = `profile.lookahead`), which is what stops the bot from being blind to a cheap
## gate in front of a big node. If the best option is out of reach but within
## `save_up_nights` of income, the bot banks instead of buying something worse — the same
## thing a player does when the Ledger shows a card they want.
##
## The projection below is a MODEL, not the sim: it estimates a Night analytically so the
## policy can price ~40 candidates per Count without playing 40 Nights. The sim is the
## authority on what actually happens; the projection only has to RANK options correctly.
## Where the two would disagree the sim wins, and the report quotes the sim.

## Nodes considered per Count before the loop gives up (a guard, never reached in practice).
const MAX_BUYS_PER_COUNT := 24
## Storefront collect cadence: three bank targets, the door, the 20 s re-arm. Used to cap
## the projection's collect income at something the hardware can physically deliver.
const COLLECT_CYCLE_SEC := SimTable.STOREFRONT_OPEN_SEC * 0.5 + SimTable.STOREFRONT_REARM_SEC
## Shots a payphone bank takes per completion when every hit lands somewhere useful.
const WIRE_USEFUL_SHOTS := 3.0
## Shots a storefront takes per collection: three targets down, then the door.
const STOREFRONT_USEFUL_SHOTS := 4.0
## Nothing further away than this many Nights of clean income is worth pricing — a player
## does not plan around a card they cannot reach this year, and pricing them all is what
## makes the policy the slow half of the sim. The horizon widens on its own as income grows,
## so the next tier swims into view exactly when it becomes a real choice.
const REACH_NIGHTS := 60.0
## Cards priced per trip to the board. Pricing a card means projecting a whole Night with it
## owned, so the count is the sim's main cost; a player weighing the dozen cheapest face-up
## cards against the one they are saving for is also the honest model of the decision.
const MAX_PRICED := 12
## When a player gives up waiting and buys something cheap instead, they still keep most of
## the pile: an impatience purchase may not cost more than this share of clean on hand.
## Without a cap the bot dribbles every dollar into $120 trash cans and can never reach the
## $4K laundromat at all — which is a trap of the model, not of the game.
const IMPATIENCE_SHARE := 0.25
## Hardware ids that change the shot menu, in signature order (see `_table_for`).
const MENU_HARDWARE: Array[StringName] = [
	&"bumper_2", &"bumper_3", &"slingshots", &"rollovers", &"spinner_numbers", &"wire_bank",
	&"storefront_laundromat", &"storefront_pizzeria", &"storefront_pawn", &"orbit_left",
	&"laundromat_loop",
]

var catalog: Upgrades
var profile: SimProfile
var reveal: Reveal

var _scratch := Stats.new()
var _seen_ids: Dictionary = {}
var _menu_cache: Dictionary = {}


func _init(p_catalog: Upgrades, p_profile: SimProfile, p_reveal: Reveal) -> void:
	catalog = p_catalog
	profile = p_profile
	reveal = p_reveal
	_scratch.catalog = p_catalog


# --- buying -------------------------------------------------------------------------


## One trip through the Ledger between two Nights. Returns the ids bought, in order.
func buy_pass(state: SimState) -> PackedStringArray:
	var bought: PackedStringArray = []
	var states: Dictionary = reveal.states(state.owned)
	for _i in MAX_BUYS_PER_COUNT:
		var pick := _best(state, states)
		if pick.is_empty():
			break
		var chain: PackedStringArray = pick["chain"]
		var cost: BigMoney = pick["cost"]
		if state.wallet.clean.cmp(cost) < 0:
			break
		var ok := true
		var new_card := false
		for id in chain:
			var node_cost := catalog.next_cost(id, state.owned)
			new_card = new_card or int(state.owned.get(id, 0)) == 0
			if not state.buy_upgrade(id, node_cost):
				ok = false
				break
			bought.append(id)
		if not ok:
			break
		# Levels 2+ of a repeatable cannot turn a card over — every reveal condition reads
		# rank, a milestone, held dirty, or whether a node is owned AT ALL.
		if new_card:
			states = reveal.states(state.owned)
	return bought


## The best thing to do with money right now, or {} for "bank it / nothing left".
##
## Options are ranked on clean-per-Night gained per dollar, because clean is what the Ledger
## eats. Early on that number is ZERO for everything — the only clean faucet at R0 is pocket
## money and it is already saturated — so the tie-break is dirty-per-Night per dollar, which
## is what a player is actually looking at when they buy a second trash can. If nothing at
## all is priceable (feature flags, job slips, bench depth) and clean is piling up, the bot
## buys the cheapest revealed card anyway: that is what people do with a full wallet and a
## board full of face-up cards, and it is the only way those nodes ever get exercised.
func _best(state: SimState, states: Dictionary) -> Dictionary:
	var base := project(state.stats, state.rank, state.heat.multiplier())
	var base_clean: BigMoney = base["clean_per_night"]
	var base_dirty: BigMoney = base["dirty_per_night"]
	var horizon := state.wallet.clean.add(base_clean.mul(REACH_NIGHTS))
	var best: Dictionary = {}
	var best_affordable: Dictionary = {}
	var cheapest: Dictionary = {}
	var candidates: Array[Dictionary] = []
	for node in catalog.nodes:
		var id := String(node["id"])
		if int(states.get(id, Reveal.State.HIDDEN)) != Reveal.State.REVEALED:
			continue
		var chain := _chain_for(id, state, profile.lookahead)
		if chain.is_empty():
			continue
		var cost := _chain_cost(chain, state.owned)
		if not cost.is_positive() or cost.cmp(horizon) > 0:
			continue
		candidates.append({"id": id, "chain": chain, "cost": cost})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["cost"] as BigMoney).cmp(b["cost"] as BigMoney) < 0)
	if candidates.size() > MAX_PRICED:
		candidates.resize(MAX_PRICED)

	for candidate in candidates:
		var id: String = candidate["id"]
		var chain: PackedStringArray = candidate["chain"]
		var cost: BigMoney = candidate["cost"]
		var gain := _gain_of(chain, state, base_clean, base_dirty)
		var clean_gain: BigMoney = gain["clean"]
		var option := {
			"chain": chain, "cost": cost, "id": id, "clean_gain": clean_gain,
			"clean": clean_gain.ratio_to(cost),
			"dirty": (gain["dirty"] as BigMoney).ratio_to(cost),
		}
		var affordable := state.wallet.clean.cmp(cost) >= 0
		if affordable and (cheapest.is_empty() or cost.cmp(cheapest["cost"]) < 0):
			cheapest = option
		if float(option["clean"]) <= profile.min_gain_per_cost and float(option["dirty"]) <= 0.0:
			continue
		if _better(option, best):
			best = option
		if affordable and _better(option, best_affordable):
			best_affordable = option
	if best.is_empty():
		return _explore(state, cheapest, base_clean)
	if state.wallet.clean.cmp(best["cost"]) >= 0:
		return best
	if best_affordable.is_empty():
		return _explore(state, cheapest, base_clean)

	# The best card is out of reach. Three ways that can end:
	#   1. an affordable card pays for itself before the good one would have arrived → take it;
	#   2. the good one is inside this player's patience → bank;
	#   3. it is further off than they are willing to wait → buy the best affordable card,
	#      which is what people actually do with a board full of face-up cards.
	# Patience is the profile's `save_up_nights`, and it is a real strategy difference: a
	# shark banks a month of income for the laundromat, a duffer buys another trash can.
	var wait := (best["cost"] as BigMoney).sub_clamped(state.wallet.clean).ratio_to(base_clean)
	if (best_affordable["clean_gain"] as BigMoney).is_positive():
		var payback := (best_affordable["cost"] as BigMoney).ratio_to(best_affordable["clean_gain"])
		if payback < wait:
			return best_affordable
	if wait <= profile.save_up_nights:
		return {}
	if (best_affordable["cost"] as BigMoney).cmp(state.wallet.clean.mul(IMPATIENCE_SHARE)) <= 0:
		return best_affordable
	return {}


## Lexicographic: clean first, dirty only when neither option moves clean at all.
static func _better(option: Dictionary, incumbent: Dictionary) -> bool:
	if incumbent.is_empty():
		return true
	var a_clean := float(option["clean"])
	var b_clean := float(incumbent["clean"])
	if a_clean > 0.0 or b_clean > 0.0:
		return a_clean > b_clean
	return float(option["dirty"]) > float(incumbent["dirty"])


## Nothing on the board is priceable. Buy the cheapest revealed card once the wallet is
## comfortably past its price — modelling the player who clears the cheap cards rather than
## sitting on clean cash forever. Without this, every respect-only node (job slips, bench
## depth) would read as dead purely because the projection cannot see respect.
func _explore(state: SimState, cheapest: Dictionary, clean_per_night: BigMoney) -> Dictionary:
	if cheapest.is_empty():
		return {}
	var slack := (cheapest["cost"] as BigMoney).add(clean_per_night.mul(profile.save_up_nights))
	if state.wallet.clean.cmp(slack) < 0:
		return {}
	return cheapest


## `id` plus the cheapest set of unbought parents that would make it legal, or [] if it is
## unreachable inside `depth` purchases (rank gates are never bought past).
func _chain_for(id: String, state: SimState, depth: int) -> PackedStringArray:
	_seen_ids.clear()
	var out: PackedStringArray = []
	if not _walk(id, state, depth, out):
		return PackedStringArray()
	return out


func _walk(id: String, state: SimState, depth: int, out: PackedStringArray) -> bool:
	if _seen_ids.has(id):
		return true
	var node := catalog.def(id)
	if node.is_empty():
		return false
	if state.rank < int(node["tier"]):
		return false
	if int(state.owned.get(id, 0)) >= int(node["max_level"]):
		return false
	_seen_ids[id] = true
	for parent in catalog.parents_of(id):
		if int(state.owned.get(parent, 0)) >= 1:
			continue
		if depth <= 0:
			return false
		if not _walk(parent, state, depth - 1, out):
			return false
	out.append(id)
	return true


func _chain_cost(chain: PackedStringArray, owned: Dictionary) -> BigMoney:
	var total := BigMoney.zero()
	for id in chain:
		total = total.add(catalog.next_cost(id, owned))
	return total


## Clean- and dirty-per-Night this chain would add, per the projection.
func _gain_of(chain: PackedStringArray, state: SimState, base_clean: BigMoney,
		base_dirty: BigMoney) -> Dictionary:
	var owned := state.owned.duplicate()
	for id in chain:
		owned[id] = int(owned.get(id, 0)) + 1
	_scratch.recompute(owned)
	var after := project(_scratch, state.rank, state.heat.multiplier())
	return {
		"clean": (after["clean_per_night"] as BigMoney).sub_clamped(base_clean),
		"dirty": (after["dirty_per_night"] as BigMoney).sub_clamped(base_dirty),
	}


# --- the projection -------------------------------------------------------------------


## An analytic Night: how long it runs, what it earns dirty, and how much of that turns
## clean. Used by the policy to rank purchases and by the report to quote a rate.
func project(stats: Stats, rank: int, heat_mult: float = 1.0) -> Dictionary:
	var ball := expected_ball_seconds(stats)
	var saves := float(stats.ball_saves()) * _save_use_chance() * ball
	var play := float(SimNight.GUYS_PER_NIGHT) * ball + saves
	var night_seconds := play + float(SimNight.GUYS_PER_NIGHT) * SimNight.PINCH_BEAT

	var table := _table_for(stats)
	var rate := table.shot_rate(profile, stats)
	var shots := rate * play
	var per_group: Dictionary = {}
	for row in table.shots:
		var group: StringName = row["group"]
		per_group[group] = float(per_group.get(group, 0.0)) + float(row["weight"])
	var combo := combo_factor(per_group, rate, profile.cluster)

	var dirty := BigMoney.zero()
	for row in table.shots:
		var share := float(row["weight"]) / maxf(table.total_weight, 0.0001)
		var n := shots * share
		var value := _value_per_shot(row, stats, night_seconds, n)
		if value.is_positive():
			dirty = dirty.add(value.mul(n * heat_mult * combo))
	var idle := stats.idle_rate_total().mul(night_seconds)
	dirty = dirty.add(idle)
	var safe := _safe_per_night(stats)
	dirty = dirty.add(safe)

	# Skill shots ride the same money path, once per served ball.
	if stats.hardware_unlocked(&"rollovers"):
		var skill := BigMoney.of(SimState.SKILL_SHOT_MANTISSA, SimState.SKILL_SHOT_EXP)
		if SimState.skill_shot_scales_with_rank:
			skill = skill.mul_big(Rates.rank_scale(rank).div_big(Rates.rank_scale(0)))
		skill = skill.add(stats.value_add(&"skill_shot")).mul(stats.value_mult(&"skill_shot"))
		var p := profile.skill_shot_p
		if stats.flag(&"plunger_bands"):
			p = minf(p * SimNight.PLUNGER_SKILL_BONUS, 1.0)
		dirty = dirty.add(skill.mul(float(SimNight.GUYS_PER_NIGHT) * p * heat_mult))

	var clean := _clean_from(dirty, stats, table, shots, night_seconds)
	return {
		"night_seconds": night_seconds,
		"ball_seconds": ball,
		"shots": shots,
		"rate": rate,
		"combo": combo,
		"dirty_per_night": dirty,
		"clean_per_night": clean,
		"idle_per_night": idle.add(safe),
	}


## The shot menu for a Stats, cached: the projection prices ~30 candidates per Count and
## almost none of them change the hardware, so rebuilding the menu each time is pure waste.
func _table_for(stats: Stats) -> SimTable:
	var id := 0
	for i in MENU_HARDWARE.size():
		if stats.hardware_unlocked(MENU_HARDWARE[i]):
			id |= 1 << i
	if stats.launder_rate() > 0.0:
		id |= 1 << MENU_HARDWARE.size()
	var cached: SimTable = _menu_cache.get(id, null)
	if cached != null:
		return cached
	var built := SimTable.build(stats, profile, catalog)
	_menu_cache[id] = built
	return built


## The Safe's share of one Night: a session collects `min(gap, safe_hours)` of idle income
## and then splits it across the Nights of that session (docs/03 §6 — this is what a Bigger
## Safe is actually worth, and it is invisible if you only look at the table).
func _safe_per_night(stats: Stats) -> BigMoney:
	var rate := stats.idle_rate_total()
	if not rate.is_positive():
		return BigMoney.zero()
	var gap := profile.session_gap_hours() * 3600.0
	var got := Offline.accrue(rate, gap, Rates.safe_cap(rate, stats.safe_hours()))
	return got.div(maxf(float(profile.nights_per_session), 1.0))


## Dirty a single shot at this row is worth, before heat and combo.
func _value_per_shot(row: Dictionary, stats: Stats, night_seconds: float, shots_here: float) -> BigMoney:
	var group: StringName = row["group"]
	var add := stats.value_add(group)
	var mult := stats.value_mult(group)
	var base := BigMoney.from_float(float(row["base"]))
	match int(row["kind"]):
		SimTable.Kind.SPINNER:
			var kick := minf(profile.spinner_kick_speed * stats.flipper_power(), SimTable.SPIN_MAX_SPEED)
			var segs := float(SimTable.spin_segments(kick))
			return base.add(add).mul(mult * segs)
		SimTable.Kind.WIRE:
			# Three phones pay 150 once each, the bank pays 1000, and a hit on a phone that
			# is already down pays nothing at all — which is what discipline is worth here.
			var q := _useful_share()
			var per_cycle := base.add(add).mul(3.0).add(
					BigMoney.from_float(SimTable.BANK_COMPLETE).add(add))
			return per_cycle.mul(mult * q / WIRE_USEFUL_SHOTS)
		SimTable.Kind.STOREFRONT:
			var value := SimTable.collect_value(row["id"], stats, catalog).add(add).mul(mult)
			var per_shot := value.mul(_useful_share() / STOREFRONT_USEFUL_SHOTS)
			# …but the block can only be shaken so often: the bank re-arms for 20 s.
			var cadence := night_seconds / COLLECT_CYCLE_SEC
			if shots_here > 0.0 and shots_here * _useful_share() / STOREFRONT_USEFUL_SHOTS > cadence:
				per_shot = value.mul(cadence / maxf(shots_here, 0.0001))
			return per_shot
		SimTable.Kind.WASH:
			return BigMoney.zero()
	return base.add(add).mul(mult)


## How much of a Night's dirty comes out clean: the loop against tonight's cap, the passive
## wash, then pocket money on whatever is left.
func _clean_from(dirty: BigMoney, stats: Stats, table: SimTable, shots: float,
		night_seconds: float) -> BigMoney:
	var cap := stats.launder_cap()
	var washed := BigMoney.zero()
	if cap.is_positive():
		var f := stats.launder_rate()
		if table.wash_live and f > 0.0:
			var passes := shots * _wash_share(table)
			if table.wash_gated_by_bank:
				passes = minf(passes, night_seconds / COLLECT_CYCLE_SEC)
			passes = minf(passes, night_seconds / SimTable.WASH_COOLDOWN)
			var moved := 1.0 - pow(1.0 - f, maxf(passes, 0.0))
			washed = BigMoney.min_of(dirty.mul(moved), cap)
		var passive := stats.passive_wash_per_sec()
		if passive > 0.0:
			var by_passive := dirty.mul(clampf(passive * night_seconds, 0.0, 1.0))
			washed = BigMoney.min_of(washed.add(by_passive), cap)
	var left := dirty.sub_clamped(washed)
	var pocket := BigMoney.min_of(stats.pocket_money(), left)
	return washed.add(pocket)


## Share of shots that go at the wash door rather than at money.
func _wash_share(table: SimTable) -> float:
	if not table.wash_live:
		return 0.0
	for row in table.shots:
		if int(row["kind"]) == SimTable.Kind.WASH:
			return float(row["weight"]) / maxf(table.total_weight, 0.0001)
	return 0.0


## Share of aimed shots that land on something still worth hitting. Averaged over a bank's
## cycle: the useful fraction of a 3-target set walks 3/3, 2/3, 1/3 as it goes down.
func _useful_share() -> float:
	return profile.target_discipline + (1.0 - profile.target_discipline) * (2.0 / 3.0)


## Chance a ball drains inside the 8 s save window (so a charge gets spent).
func _save_use_chance() -> float:
	var tail := maxf(profile.ball_seconds_mean - profile.ball_seconds_min, 1.0)
	var window := SimNight.BALL_SAVE_SECONDS - profile.ball_seconds_min
	if window <= 0.0:
		return 0.0
	return 1.0 - exp(-window / tail)


func expected_ball_seconds(stats: Stats) -> float:
	var scale := 1.0
	if stats.hardware_unlocked(&"inlane_guides"):
		scale *= SimNight.GUIDES_BALL_TIME
	if stats.hardware_unlocked(&"kickback_left"):
		scale *= SimNight.KICKBACK_BALL_TIME
	var tilt := profile.tilt_per_ball * float(Stats.BASE_TILT_LEANS) / float(maxi(stats.tilt_leans(), 1))
	# A tilt cuts the ball off at a uniform point, so it costs half a ball on average.
	return profile.ball_seconds_mean * scale * (1.0 - tilt * 0.5)


## Expected combo multiplier per scoring hit, from the group mix and the shot rate.
##
## `Combo` extends a chain only when the next hit is a DIFFERENT group inside 4 s, so with
## weights wᵢ the chance a hit repeats a group already in an n-long chain is about n·Σpᵢ²
## (exact for a uniform mix, where it reads n/G), and a `cluster` share of hits stay in the
## last group by construction. Walking the chain length as a Markov chain and reading off its
## stationary distribution gives E[min(1.5ⁿ⁻¹, 8)] without simulating a single ball.
static func combo_factor(group_weights: Dictionary, rate: float, cluster: float = 0.0) -> float:
	var total := 0.0
	for g: Variant in group_weights:
		if String(g) != "laundry":
			total += float(group_weights[g])
	if total <= 0.0:
		return 1.0
	var repeat := 0.0
	for g: Variant in group_weights:
		if String(g) == "laundry":
			continue
		var p := float(group_weights[g]) / total
		repeat += p * p
	var gap := 1.0 - exp(-maxf(rate, 0.0) * Combo.WINDOW)
	var move := 1.0 - clampf(cluster, 0.0, 1.0)
	var pi: PackedFloat64Array = [1.0]
	var acc := 1.0
	for n in range(1, 12):
		var advance := gap * move * maxf(1.0 - float(n) * repeat, 0.0)
		acc *= advance
		if acc <= 1.0e-9:
			break
		pi.append(acc)
	var sum := 0.0
	var weighted := 0.0
	for i in pi.size():
		var n := i + 1
		sum += pi[i]
		weighted += pi[i] * minf(pow(Combo.STEP, float(n - 1)), Combo.CAP)
	return weighted / maxf(sum, 1.0e-9)
