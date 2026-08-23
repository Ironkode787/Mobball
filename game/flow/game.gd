extends Node
## The Game autoload — owns the session (specs/m1-hook.md). The public surface below is
## contract-locked: `wallet` `heat` `stats` `respect` `rank` `night_no` `bench` `state`
## `state_changed` `earn_switch`. Everything else is the flow lane's internals.
##
## This is the model half of the session. It owns money, career and the state machine but
## never touches the scene tree: `game/main.gd` hosts the table and the screens and reacts
## to `state_changed`, and `game/flow/night.gd` drives the live Night.
##
##     attract ──start_night──▶ night ──end_night──▶ count ⇄ ledger
##                                ▲                    │
##                                └──── start_night ───┘

signal state_changed(state: StringName)
## Offline earnings waiting in the Safe (docs/03 §6). Zero once collected.
signal safe_changed(amount: BigMoney)
## M2 mode traffic for the HUD and The Count. `Events` is core and frozen, so the modes the
## flow lane owns announce themselves here rather than on the global bus.
signal casino_resolved(result: Dictionary)
signal wire_drawn(result: Dictionary)
signal meeting_changed(active: bool, lit: bool)
signal collection_changed(active: bool, collected: int)
## M3 mode traffic, same rule: the flow lane's own modes announce themselves here.
## A smuggling run armed, advanced, shipped or lapsed (docs/02 §2 R5).
signal smuggling_changed(state: Dictionary)
## A Sit-Down opened or ran out — the sixty seconds the Heat meter does not move.
signal sitdown_changed(active: bool, time_left: float)
## A Penthouse chair was claimed for the career, or the whole room went down in one pass.
signal chairs_changed(state: Dictionary)
## The campaign moved: a district canvassed, the ballot opened, the city counted (docs/05 §8).
signal election_changed(state: Dictionary)
## A heist's checklist moved, or the crew came out (docs/05 §5).
signal heist_changed(state: Dictionary)
## The blue meter moved, or the Feds are at the door (docs/05 §9).
signal federal_changed(state: Dictionary)
## The City Hall Circuit moved a leg, or EMPIRE lit / ran out (docs/02 §2 R7).
signal empire_changed(state: Dictionary)
## A briefcase was opened, or the bagman left with it (docs/05 §10).
signal briefcase_opened(result: Dictionary)
## The backbox phone rang, was answered, or rang out (docs/05 §10).
signal phone_changed(state: Dictionary)
## The Rat arc moved: a clue Night opened, a clue landed, a name was called (docs/05 §7).
signal rat_changed(state: Dictionary)
## A Commission fight's shape changed (phase, panels, the Butcher's freezer) — HUD fodder.
signal boss_changed(state: Dictionary)
## Manny worked a till without a ball (`auto_collect_interval`). The HUD flashes it, because
## a specialist earning money off-screen has to be visible or it is not a hire, it is a tax.
signal auto_collected(id: StringName, amount: BigMoney)

## ☆ thresholds per rank, docs/02 §1. R1=10 R2=50 R3=150 are M1's ladder; the rest are
## here so the ladder is data rather than a special case when M2 lands.
const RANK_RESPECT: PackedInt32Array = [0, 10, 50, 150, 400, 1000, 2500, 6000]
const RESPECT_SKILL_SHOT := 1
const RESPECT_RAID_SURVIVED := 25
## "Exhibit A returned": surviving a raid pays a quarter of the held dirty, in CLEAN.
const RAID_CLEAN_PAYOUT := 0.25
## Skill shot cash at R0; scales with rank_scale like every other payout (docs/03 §7).
const SKILL_SHOT_MANTISSA := 2.0
const SKILL_SHOT_EXP := 2
## Cold Storage (Commission spoil, specs/m2-content.md §5): armored hardware banks this much
## of what it refuses to pay, and hands it over when the armor comes off.
const COLD_STORAGE_FRACTION := 0.5
## Music stems audible per rank (docs/08 §1) — rank 0 already has a band, R7 has all eight.
const MUSIC_LEVEL_OFFSET := 1
## THE RICO RAID (docs/05 §9): surviving it pays twice the held dirty, in clean — the single
## largest payout in the game, which is what a two-minute federal raid is supposed to be
## worth. Losing it is the ordinary confiscation, doubled.
const RICO_CLEAN_PAYOUT := 2.0
const RICO_CONFISCATE_MULT := 2.0
const RESPECT_RICO_SURVIVED := 100

var wallet := Wallet.new()
var heat := HeatMeter.new()
var stats := Stats.new()
var respect: int = 0
var rank: int = 0
var night_no: int = 0
var bench: Bench = null
var state: StringName = &"attract":
	set(v):
		if state == v:
			return
		state = v
		state_changed.emit(v)

# --- flow-lane additions ------------------------------------------------------

var save := SaveGame.new()
var jobs := Jobs.new()
var combo := Combo.new()
## M2 modes (specs/m2-content.md). All four are pure logic on a fed clock; the
## NightController feeds them table events and this file pays what they decide.
var casino := Casino.new()
var meeting := FamilyMeeting.new()
var wire := WireDraws.new()
var collection := CollectionRound.new()
## M3 modes (specs/m3-fall-rise.md FLOW-3), same discipline: pure logic on a fed clock.
var smuggling := SmugglingRun.new()
var sitdown := SitDown.new()
## THE PENTHOUSE (docs/02 §2 R6): the five chairs, claimed across Nights, and the campaign
## they unlock.
var chairs := CommissionChairs.new()
var elections := Elections.new()
## THE WAR ROOM (docs/05 §5): the board, the casing clock and what the jobs have paid.
var heists := Heists.new()
## The heist on the table right now, or null (typed loosely — see `boss`).
var heist: HeistRun = null
## FEDERAL HEAT (docs/05 §9): the blue stage and the raid waiting at the top of it.
var federal := FederalHeat.new()
## EMPIRE MODE (docs/02 §2 R7): the City Hall Circuit and the sixty seconds it lights.
var empire := EmpireMode.new()
## The small rituals (docs/05 §10): the man in the trench coat, and the phone.
var briefcases := Briefcases.new()
var phone := ThePhone.new()
## THE RAT (docs/05 §7): who is talking, what it is costing, and the three names.
var rat := TheRat.new()
## THE COMMISSION (specs/m2-content.md §5): who is waiting, who has been put away, and which
## rank the ladder is not allowed past yet.
var commission := Commission.new()
## The live fight while one is running (typed loosely, same reason as `night`).
var boss: Node = null
## The guys physically on the table right now — one normally, two during a Family Meeting.
## Their traits fold into every dirty payout and into the Heat meter's gain scale.
var fielded: Array[Dictionary] = []
## Ledger node id -> owned level, and the half of it flow is responsible for: the save file.
## The meta lane keeps the same map in `LedgerState` for its board; the two are kept in step
## by `_push_owned_to_meta()` / `_pull_owned_from_meta()` on every purchase and every load.
var owned: Dictionary = {}
## The live NightController while `state == &"night"` (typed loosely to keep game.gd and
## night.gd out of a class-reference cycle).
var night: Node = null
## Untaken offline earnings; the attract screen and The Count offer them.
var safe_pending: BigMoney = BigMoney.zero()
## Wall-clock stamp the Safe accrues from.
var last_seen: float = 0.0
## Summary of the Night The Count is showing.
var last_night: Dictionary = {}
## Biggest Night so far — the headline generator's "record take" test.
var best_night: BigMoney = BigMoney.zero()
var session_seed: int = 0

# Per-Night tallies, reset by start_night() and read by the summary.
var night_dirty: BigMoney = BigMoney.zero()
var night_idle: BigMoney = BigMoney.zero()
var night_laundered: BigMoney = BigMoney.zero()
## Clean paid straight out (casino wins under the Wash, Jackpots, exact Wire numbers) —
## money that was never dirty, as opposed to `night_laundered`, which was.
var night_clean: BigMoney = BigMoney.zero()
## Dirty booked per value group tonight, at what actually landed in the wallet.
var night_group: Dictionary = {}
## The same groups at their BASE — the Ledger's own value for the shot, before tonight's
## volatile multipliers (Heat band, mode, combo). The Wire prices its ticket off this line:
## pricing off the post-multiplier take let the Heat band and a Family Meeting multiply the
## same Night twice (balance-sim ruling — a draw was paying 165% of the whole spinner line).
var night_group_base: Dictionary = {}
var night_respect: int = 0
var night_jobs: Array[String] = []
var night_skill_shots: int = 0
var night_best_combo: int = 0
var night_bribes: int = 0
## What the Commission paid tonight — the purse and the Butcher's freezer.
var night_boss: BigMoney = BigMoney.zero()
## Job rerolls left on the board (the Consigliere, `job_reroll_add`). Refilled every Night.
var night_rerolls: int = 0
## The rain-insurance policy is one confiscation a Night, and it is spent here.
var night_insured: bool = false
## The heist this Night ran, as The Count wants to read it. Empty on an ordinary Night.
var night_heist: Dictionary = {}

## THE RAP SHEET. Counters no other system owns and every one of them is a term in the Juice
## formula (docs/06 §2) — so a career that is about to Skip Town can be scored without asking
## six subsystems to remember what they did five cities ago.
var career: Dictionary = {}

## The meta lane's stores: the authoritative owned-upgrades map and the reveal history.
## Both are loaded by path rather than referenced as classes so the flow lane keeps booting
## if the meta lane moves them — the cost of one going missing is the Ledger board losing
## its state, not the game failing to start.
const LEDGER_STATE_PATH := "res://game/meta/ledger_state.gd"
const REVEAL_PATH := "res://game/meta/reveal.gd"

var _booted: bool = false
## Value groups whose hardware is armored right now: they pay nothing, and Cold Storage banks
## half of what they refuse until the armor comes off.
var _armored: Dictionary = {}
var _armored_bank: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _headlines := Headlines.new()
var _ledger_state: GDScript = null
var _reveal_script: GDScript = null


## Wired at construction, not in `_ready()`: the headless test runner is a bare SceneTree
## that never reaches a frame, so `_ready()` would land after the tests had already used
## the singleton. Every connect below is guarded, so both paths are safe.
func _init() -> void:
	career = _blank_career()
	_wire(combo.changed, _on_combo_changed)
	_wire(combo.respect_earned, _on_combo_respect)
	_wire(jobs.completed, _on_job_completed)
	_wire(heat.raid_triggered, _on_raid_triggered)


func _ready() -> void:
	_wire(Events.upgrade_purchased, _on_upgrade_purchased)
	_wire(Events.tilted, _on_tilted)
	_wire(combo.changed, _on_combo_changed)
	_wire(combo.respect_earned, _on_combo_respect)
	_wire(jobs.completed, _on_job_completed)
	_wire(heat.raid_triggered, _on_raid_triggered)


## The Inspector's first report turns a face-down card over (docs/04 influence branch).
func _on_tilted() -> void:
	mark_reveal_event(&"first_tilt")


## THE ONE listener on `HeatMeter.raid_triggered`, owned here for the life of the process.
##
## The meter LATCHES at 100 and `_process` above ticks it in every state — so when only the
## NightController listened, a crossing at The Count (the earn window a hot Night left behind,
## still crediting) latched with nobody home and killed the Raid for the rest of the career.
## The balance sim measured that on 89 of 120 shark Nights. Game holds the connection instead
## and defers to whatever Night is live; a crossing with no Night running is simply left
## pending, and `NightController.start()` opens the next one with the door coming in.
func _on_raid_triggered() -> void:
	if night != null and is_instance_valid(night) and night.has_method("on_raid_called"):
		night.call("on_raid_called")


static func _wire(sig: Signal, to: Callable) -> void:
	if not sig.is_connected(to):
		sig.connect(to)


func _process(delta: float) -> void:
	if not heat_frozen():
		heat.tick(delta)


## Is the meter stopped dead right now? The Sit-Down (docs/02 §2 R6) is a real freeze: no
## decay, no gain, and no earn window filling up to land on you afterwards. Everything that
## can move the meter asks here first, so there is one answer to "is Heat live".
func heat_frozen() -> bool:
	return sitdown.active


## Every loud act's flat Heat goes through here rather than at `heat.add_flat` directly, so
## the freeze covers the smuggling shipment and the High Roller's greed as well as the tick.
func heat_add_flat(amount: float) -> void:
	if not heat_frozen():
		heat.add_flat(amount)


## The same guard the other way: a frozen meter does not fall either.
func heat_reduce(amount: float) -> void:
	if not heat_frozen():
		heat.reduce(amount)


# =============================================================== money path =====


## THE single money path: every dirty payout on the table flows through here.
## base_value × stats add/mult × heat multiplier × mode/trait multiplier × combo → wallet;
## unless `no_heat` says otherwise the same post-multiplier amount feeds the heat window
## (hot money is what raises heat, docs/03 §4), and it always feeds the Jobs.
##
## `Stats` already folds the &"all" group into every `value_add`/`value_mult` it returns, so
## there is exactly one lookup here — folding it in again would square the Brass Balls line.
##
## `meta` options:
##   `no_combo` — idle/mode payouts that must not extend a chain.
##   `no_heat`  — dirty that lands in the wallet without warming the meter. Nothing on the
##                shipped table asks for this any more (casino winnings, which used to, are
##                paid by `earn_flat_dirty` and ARE hot money); it stays because "this payout
##                is not hot" is a real thing a future racket may need to say.
##   `switch`   — the hardware id, for Jobs that count specific switches.
##
## Two things can refuse a payout before it is made, and both hand the money somewhere rather
## than dropping it: **armored** hardware (the Butcher's cold storage) banks its share, and a
## live **Commission fight** pauses the economy outright — a boss is pure skill (docs/05 §6),
## so the table earns nothing at all and the fight is told what it refused.
func earn_switch(group: StringName, base_value: BigMoney, meta: Dictionary = {}) -> BigMoney:
	var base := ledger_value(group, base_value)
	var v := base.mul(heat.multiplier()).mul(mode_multiplier())
	var armored := is_group_armored(group)
	if armored:
		_bank_armored(group, v)
	if economy_paused():
		_boss_denied(group, v)
		return BigMoney.zero()
	if armored:
		return BigMoney.zero()
	if not bool(meta.get("no_combo", false)):
		v = v.mul(combo.on_hit(group))
	wallet.earn_dirty(v)
	if not bool(meta.get("no_heat", false)) and not heat_frozen():
		heat.on_dirty_earned(v, Rates.rank_scale(rank))
	Events.dirty_earned.emit(v, group)
	night_dirty = night_dirty.add(v)
	_book_group(group, v, base)
	jobs.on_earn(v, group)
	_take_clean_share(v)
	return v


## ★ the Black Book's clean share (`Stats.clean_share`, cap 0.25). A slice of every switch is
## already clean by the time it reaches the pocket — but it is drawn AGAINST tonight's wash
## cap, the switch was hot money for the whole of its value, and it books as LAUNDERED rather
## than as clean income, because dirty really did become clean. All three properties are what
## keep it a convenience instead of a second, unpriced faucet: see the docstring on
## `Stats.clean_share()`.
func _take_clean_share(v: BigMoney) -> void:
	var share := stats.clean_share()
	if share <= 0.0 or v == null or not v.is_positive():
		return
	launder(1.0, BigMoney.min_of(v.mul(share), launder_cap_left()))


## Money that arrives already priced — a bet's winnings, a Wire ticket. It lands in the wallet
## at FACE VALUE: the switch multipliers priced the shots that funded it, and pricing the
## payout again multiplies the same Night twice (balance-sim ruling — the casino was paying
## 2.9× the stake at Heat band 2 on a wheel whose whole edge is ±7.5%). It is still dirty cash
## in a pocket, so it is hot money like any other dirty and the Jobs still count it; it is
## never a shot, so it can neither open nor extend a chain.
func earn_flat_dirty(amount: BigMoney, group: StringName) -> BigMoney:
	if amount == null or not amount.is_positive():
		return BigMoney.zero()
	var armored := is_group_armored(group)
	if armored:
		_bank_armored(group, amount)
	if economy_paused():
		_boss_denied(group, amount)
		return BigMoney.zero()
	if armored:
		return BigMoney.zero()
	wallet.earn_dirty(amount)
	if not heat_frozen():
		heat.on_dirty_earned(amount, Rates.rank_scale(rank))
	Events.dirty_earned.emit(amount, group)
	night_dirty = night_dirty.add(amount)
	# Flat money is its own base: nothing multiplied it, so both lines move together.
	_book_group(group, amount, amount)
	jobs.on_earn(amount, group)
	return amount


func _book_group(group: StringName, value: BigMoney, base: BigMoney) -> void:
	# Empire Mode's dividend is a share of what the sixty seconds actually made, so it is
	# measured here — where every dirty payout, switch or flat, is already passing.
	empire.book_earned(value)
	var total: Variant = night_group.get(group, null)
	night_group[group] = value if not (total is BigMoney) else (total as BigMoney).add(value)
	var raw: Variant = night_group_base.get(group, null)
	night_group_base[group] = base if not (raw is BigMoney) else (raw as BigMoney).add(base)


## What a switch is worth before tonight's volatile multipliers: the base plus everything the
## Ledger has bought for that group. This is the line the Wire prices off, so a bought empire
## still grows the numbers draw while a hot Night does not double it.
func ledger_value(group: StringName, base_value: BigMoney) -> BigMoney:
	return base_value.add(stats.value_add(group)).mul(stats.value_mult(group))


## What a switch WOULD pay right now, without paying it or touching anything. Everything the
## money path does before the combo — the combo is a chain of shots that landed, so a denied
## hit must not be able to extend or price one.
func preview_switch(group: StringName, base_value: BigMoney) -> BigMoney:
	return ledger_value(group, base_value).mul(heat.multiplier()).mul(mode_multiplier())


## Everything that multiplies dirty because of who is on the table and what mode is running:
## the Family Meeting's ×2 while two guys are working, and the fielded guys' own traits
## (Loud, Fast). Multiplicative across guys — during a Meeting both men's traits are live,
## which is the point of taking the crew out together.
func mode_multiplier() -> float:
	return meeting.dirty_multiplier() * elections.dirty_multiplier() \
			* empire.dirty_multiplier() * briefcases.dirty_multiplier() \
			* GuyTraits.dirty_mult_for(fielded)


## Dirty booked in one value group tonight, as it landed in the wallet.
func night_group_dirty(group: StringName) -> BigMoney:
	var v: Variant = night_group.get(group, null)
	return (v as BigMoney).copy() if v is BigMoney else BigMoney.zero()


## The same group at its base, before Heat, mode and combo (the Wire prices off `&"spinner"`).
func night_group_base_dirty(group: StringName) -> BigMoney:
	var v: Variant = night_group_base.get(group, null)
	return (v as BigMoney).copy() if v is BigMoney else BigMoney.zero()


## Clean paid directly, never having been dirty: casino wins under the Wash, the slots
## Jackpot, the Meeting jackpot, an exact Wire number. It is not laundering — nothing moved
## out of the dirty pile — so it books its own line rather than eating the wash cap, and it
## does NOT emit `Events.laundered`, whose contract is "this much dirty became clean"
## (`night_dirty − night_laundered == held dirty` is a load-bearing invariant in the sims).
## The Jobs board still counts it, because in the fiction the casino is a laundry (docs/03 §2).
##
## `_source` labels the call site for readers; it is not published. `Events` is core and
## frozen, and each M2 mode announces itself on its own signal above with its whole result.
func earn_clean(amount: BigMoney, _source: StringName = &"") -> BigMoney:
	if amount == null or not amount.is_positive():
		return BigMoney.zero()
	wallet.earn_clean(amount)
	night_clean = night_clean.add(amount)
	_book_lifetime_clean(amount)
	jobs.on_launder(amount)
	return amount


# ================================================================= the rap sheet =====
##
## Career counters. Every one of them is a term in the Juice formula (docs/06 §2), and none
## of them belongs to any other system: the wallet holds what you HAVE, not what you have
## ever had, and a heist book that resets with the city cannot score the city it lost.


static func _blank_career() -> Dictionary:
	return {
		"lifetime_clean": BigMoney.zero(),
		"raids_survived": 0,
		"heists_cleared": 0,
		"cities": 0,
	}


## Every dollar that has ever turned clean, however it got there — paid clean, washed, or
## handed back as exhibit A.
func _book_lifetime_clean(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	var held: Variant = career.get("lifetime_clean", null)
	career["lifetime_clean"] = amount if not (held is BigMoney) \
			else (held as BigMoney).add(amount)


func lifetime_clean() -> BigMoney:
	var v: Variant = career.get("lifetime_clean", null)
	return (v as BigMoney).copy() if v is BigMoney else BigMoney.zero()


## A raid ridden out. Called by the NightController, because the raid's outcome is the
## Night's to decide and the rap sheet is this file's to keep.
func career_raid_survived() -> void:
	career["raids_survived"] = int(career.get("raids_survived", 0)) + 1


## The career as the Juice formula wants to read it (docs/06 §2). Handed to the meta lane's
## `Prestige` verbatim — which is why the keys are its vocabulary, not this file's, and why
## `lifetime_clean` is money EARNED rather than money held.
func career_totals() -> Dictionary:
	return {
		"lifetime_clean": lifetime_clean(),
		"bosses_beaten": commission.beaten.size(),
		"heists_cleared": int(career.get("heists_cleared", 0)),
		"raids_survived": int(career.get("raids_survived", 0)),
		"excess_respect": maxi(respect - rank_threshold(rank), 0),
	}


func _career_to_dict() -> Dictionary:
	return {
		"lifetime_clean": lifetime_clean().to_dict(),
		"raids_survived": int(career.get("raids_survived", 0)),
		"heists_cleared": int(career.get("heists_cleared", 0)),
		"cities": int(career.get("cities", 0)),
	}


func _career_from_dict(d: Variant) -> void:
	career = _blank_career()
	if not (d is Dictionary) or (d as Dictionary).is_empty():
		return
	var raw: Dictionary = d
	career["lifetime_clean"] = BigMoney.from_dict(raw.get("lifetime_clean", {}))
	career["raids_survived"] = maxi(int(raw.get("raids_survived", 0)), 0)
	career["heists_cleared"] = maxi(int(raw.get("heists_cleared", 0)), 0)
	career["cities"] = maxi(int(raw.get("cities", 0)), 0)


## Who is on the table. Their traits fold into the money path and into the Heat meter's gain
## scale (Loud +10%, Careful −15%) for exactly as long as they are out there.
func set_fielded(guys: Array) -> void:
	fielded = []
	for g: Variant in guys:
		if g is Dictionary and not (g as Dictionary).is_empty():
			fielded.append(g as Dictionary)
	heat.gain_scale = GuyTraits.heat_scale_for(fielded)


## The idle layer's trickle (docs/03 §6): real dirty cash, but it is not "hot money" —
## it neither feeds Heat nor extends a combo.
func earn_idle(amount: BigMoney) -> void:
	if amount == null or not amount.is_positive():
		return
	wallet.earn_dirty(amount)
	night_dirty = night_dirty.add(amount)
	night_idle = night_idle.add(amount)
	Events.dirty_earned.emit(amount, &"idle")


## Wash dirty → clean and book it for The Count. Returns what actually moved.
func launder(fraction: float, cap: BigMoney = null) -> BigMoney:
	var moved := wallet.launder_fraction(fraction, cap)
	if moved.is_positive():
		# THE RAT's cut (docs/05 §7). The dirty side of the move is untouched — the money
		# really did leave the pile — so `night_dirty − night_laundered == held dirty` still
		# holds; what is short is what reaches the pocket, which is the clue.
		var cut := rat.skim_fraction()
		if cut > 0.0:
			var taken := moved.mul(cut)
			if wallet.spend_clean(taken):
				rat.book_skim(taken)
		night_laundered = night_laundered.add(moved)
		_book_lifetime_clean(moved)
		jobs.on_launder(moved)
		Events.laundered.emit(moved)
	return moved


## Remaining wash allowance for tonight (docs/03 §2 — the loop is capped per Night).
func launder_cap_left() -> BigMoney:
	var cap := stats.launder_cap()
	if cap == null or not cap.is_positive():
		return BigMoney.zero()
	return cap.sub_clamped(night_laundered)


# ================================================================ the club =====
##
## The deck reports outcomes and this file pays them (specs/m2-empire.md casino API). Every
## casino payout is routed by ONE rule: clean if `casino_wash` is owned, otherwise FLAT dirty.
## Until the Wash is bought the house pays you in the same dirty money you handed it — which
## is exactly the reason to buy it (specs/m2-content.md §3: "REQUIRED for clean payouts").
## Neither branch goes back through the switch multipliers: a bet's winnings are already
## priced by the wheel, and the shot that fed the wallet was priced when it was taken.


## One `roulette_landed`. Stakes 5% of held dirty (capped by rank), resolves it, pays it.
## A comped stake (`fronts.comps`) is the house's money: the bet is placed and paid exactly
## as usual, the wallet is simply never asked.
func casino_roulette(pocket: int, house: bool) -> Dictionary:
	# The High Roller's rungs ride the BET (balance-sim ruling): greed buys variance, and the
	# wheel's own odds decide what it was worth.
	var stake := casino.stake_with_ladder(Casino.stake_for(wallet.dirty, rank), wallet.dirty)
	var comped := casino.take_comp(stake)
	if stake.is_positive() and not comped and not wallet.spend_dirty(stake):
		stake = BigMoney.zero()
	var result := casino.resolve(pocket, house, stake, Casino.payout_rate(stats),
			Casino.wash_active(stats), Casino.cooler_bonus(stats), comped)
	var won: BigMoney = result["won"]
	var paid := _pay_casino(won, bool(result["clean"]), &"roulette_wheel")
	result["paid"] = paid
	casino_resolved.emit(result)
	return result


## A High Roller hold ended: arm the next stake, take the Heat the greed cost.
func casino_high_roller(steps: int) -> float:
	var added := casino.arm(steps)
	if added > 0.0:
		heat_add_flat(added)
	return added


## A `reels_state` report. Pays the JACKPOT when it completes all three columns inside one
## deck visit: eight minutes of the whole empire's idle rate, clean, plus flat Heat.
func casino_reels(cleared_columns: Array) -> BigMoney:
	if not casino.on_reels(cleared_columns):
		return BigMoney.zero()
	var paid := _pay_casino(Casino.jackpot_value(stats.idle_rate_total()), true, &"slot_reels")
	heat_add_flat(Casino.CasinoRules.JACKPOT_HEAT)
	if meeting.note_casino_jackpot():
		meeting_changed.emit(meeting.active, meeting.lit)
	casino_resolved.emit({"jackpot": true, "paid": paid, "clean": true,
			"jackpots": casino.night_jackpots})
	return paid


## The one place a casino payout can enter the wallet. The wheel already priced this money —
## it is `stake × payout`, and the stake came out of a wallet the table's multipliers filled —
## so the dirty branch pays FACE VALUE (balance-sim ruling) and only the Wash changes the pile
## it lands in.
func _pay_casino(won: BigMoney, clean: bool, switch: StringName) -> BigMoney:
	if won == null or not won.is_positive():
		return BigMoney.zero()
	var paid := earn_clean(won, switch) if clean else earn_flat_dirty(won, &"casino")
	casino.book_payout(paid, clean)
	return paid


## One Wire draw (docs/05 §4). The ticket is the spinner's count; the base is what the spinner
## has earned tonight AT ITS BASE — floored at $500, and deliberately not the post-multiplier
## take, which the Heat band and a Meeting had already multiplied once (balance-sim ruling).
## A last-digit hit pays ×6 of that line FLAT dirty; the exact number pays ×80 clean.
func wire_draw(ticket: int) -> Dictionary:
	var result := wire.draw(ticket, night_group_base_dirty(&"spinner"))
	var won: BigMoney = result["won"]
	var paid := BigMoney.zero()
	if won.is_positive():
		paid = earn_clean(won, &"wire") if bool(result["clean"]) \
				else earn_flat_dirty(won, &"wire")
		wire.book_payout(paid)
	result["paid"] = paid
	wire_drawn.emit(result)
	return result


## The third storefront of a Collection Round: the last one pays its value again, the back
## room lights up, and the FIRST perfect round of the Night is worth ☆10 (docs/05 §3).
## Balance-sim ruling: the ☆ are once a Night, like the combo's — a repeatable ☆10 made the
## block 87% of a career's Respect, and the Respect ladder belongs to Jobs. Later rounds still
## pay the double and still light the Meeting; they just do not rank you up.
func collection_completed(id: StringName, base_value: BigMoney) -> BigMoney:
	var bonus := BigMoney.zero()
	if base_value != null and base_value.is_positive():
		bonus = earn_switch(&"storefronts", base_value.mul(CollectionRound.LAST_PAYS_EXTRA),
				{"no_combo": true, "switch": id})
	add_respect(collection.take_respect(), &"collection")
	if meeting.note_collection_round():
		meeting_changed.emit(meeting.active, meeting.lit)
	return bonus


# ============================================================== the Docks =====


## THE SHIPMENT (docs/02 §2 R5). Three stacks inside the window: the load goes out, and it is
## paid FLAT — the crates that funded it were already priced when they were broken, exactly
## as the casino's winnings and the Wire's ticket are. What it IS worth is minutes of the
## whole empire's idle rate through the Ledger's smuggling line, so a shipment grows with the
## docks instead of needing a new number at every rank; the truck run doubles it.
##
## It is a loud act, so it costs flat Heat on top of the hot money — unless a Sit-Down is
## running, which is the one thing on this table that makes a shipment quiet.
func smuggling_shipment(hot: bool) -> BigMoney:
	var value := ledger_value(&"smuggling", SmugglingRun.base_value(stats.idle_rate_total()))
	if hot:
		value = value.mul(SmugglingRun.TRUCK_MULT)
	var paid := earn_flat_dirty(value, &"smuggling")
	smuggling.book_payout(paid)
	heat_add_flat(SmugglingRun.SHIPMENT_HEAT)
	smuggling_changed.emit({
		"shipped": true,
		"hot": hot,
		"paid": paid,
		"active": smuggling.active,
		"cleared": smuggling.cleared_count(),
		"time_left": smuggling.time_left,
	})
	return paid


## THE SIT-DOWN (docs/02 §2 R6). The room stops the meter for a minute; the NightController
## re-arms the block and feeds the clock.
func sitdown_begin() -> bool:
	var seconds := SitDown.SECONDS_QUIET_WORD if has_spoil(SitDown.SPOIL_QUIET_WORD) \
			else SitDown.SECONDS
	var opened := sitdown.begin(seconds)
	sitdown_changed.emit(sitdown.active, sitdown.time_left)
	return opened


# =================================================== the chairs & the campaign =====


## A Penthouse chair went down. The table already paid the switch; this is the career half —
## a seat nobody had taken before is claimed for good, and it is worth ☆.
func chair_taken(index: int) -> bool:
	var claimed := chairs.on_chair_taken(index)
	if claimed:
		add_respect(CommissionChairs.RESPECT_PER_CHAIR, &"chairs")
		if chairs.all_claimed():
			add_respect(CommissionChairs.RESPECT_ALL_CHAIRS, &"chairs")
			AudioDirector.play(&"rankup_fanfare")
		save_now()
	chairs_changed.emit(chairs.night_summary())
	return claimed


## The whole room went down in one pass. With every seat already claimed, that is the moment
## the city becomes buyable: ELECTIONS light (docs/05 §8).
func chairs_completed() -> bool:
	if not chairs.on_chairs_completed():
		chairs_changed.emit(chairs.night_summary())
		return false
	var first := elections.unlock()
	chairs_changed.emit(chairs.night_summary())
	if first:
		AudioDirector.play(&"headline_sting")
		election_changed.emit(_election_state(&"unlocked"))
		save_now()
	return first


## Work done in one of the five districts (docs/05 §8). Returns true on the report that
## canvasses it; the fifth light calls the election on the spot.
func election_note(district: StringName, amount: int = 1) -> bool:
	if not elections.note(district, amount):
		return false
	AudioDirector.play(&"paper_slip")
	election_changed.emit(_election_state(&"canvassed", district))
	if elections.all_lit() and elections.call_election():
		AudioDirector.play(&"election_open")
		AudioDirector.play(&"knocker")
		election_changed.emit(_election_state(&"open"))
	save_now()
	return true


## The polls closed. Winning is a term at City Hall; losing is a recount that keeps one light.
func election_settle() -> Dictionary:
	var result := elections.settle()
	AudioDirector.play(&"election_win" if bool(result["won"]) else &"election_lost")
	var state := _election_state(&"settled")
	state["result"] = result
	election_changed.emit(state)
	save_now()
	return result


## Is City Hall ours right now? Read by the raid, the cops and the block.
func administration_active() -> bool:
	return elections.in_office()


# ================================================================== the heists =====
##
## A heist is planned at The Count and runs from the first serve of the next Night (docs/05
## §5). Unlike a Commission fight the economy stays ON — the table earns while the crew works,
## which is exactly the tension the fail-forward checklist is built on.


## Can the war room take an order at all? The Docks are the war room (docs/02 §2 R5).
func heists_unlocked() -> bool:
	return stats.hardware_unlocked(&"docks")


## Put a job on the books for the next Night. Returns the plan, or an empty dict if the
## target is not on the board, the stake is not in the pocket, or a Night is already running.
func plan_heist(target: StringName, approach: StringName, guy: Dictionary = {}) -> Dictionary:
	if state == &"night" or not heists_unlocked():
		return {}
	if not heists.is_available(target, night_no):
		return {}
	var stake := Heists.stake_for(target, stats.idle_rate_total())
	if stake.is_positive() and not wallet.spend_dirty(stake):
		return {}
	var plan := heists.plan(target, approach, guy)
	plan["stake"] = stake
	save_now()
	return plan


## The Count's "THE CREW IS READY" button: plan it and open the Night it runs on.
func start_heist_night(target: StringName, approach: StringName, guy: Dictionary = {}) -> bool:
	if plan_heist(target, approach, guy).is_empty():
		return false
	start_night()
	return true


## The crew came out (or did not). Pays the take CLEAN — a heist is the one racket whose
## money never has to be washed — degraded by whatever was blown along the way.
func heist_finished(run: HeistRun) -> Dictionary:
	var result := {
		"target": String(run.target) if run != null else "",
		"name": run.target_name if run != null else "",
		"approach": String(run.approach) if run != null else "",
		"cleared": run != null and run.cleared,
		"blown": run.blown if run != null else 0,
		"beats": run.beats().size() if run != null else 0,
		"guy": String(run.guy.get("name", "")) if run != null else "",
		"take": BigMoney.zero(),
		"paid": BigMoney.zero(),
		"relic": "",
	}
	if run != null:
		var take := Heists.take_for(run.target, stats.idle_rate_total()).mul(run.take_share())
		result["take"] = take
		result["paid"] = earn_clean(take, &"heist")
		if run.cleared:
			var row := Heists.target(run.target)
			result["relic"] = String(row.get("relic", ""))
			add_respect(Heists.RESPECT_CLEARED, &"heist")
			career["heists_cleared"] = int(career.get("heists_cleared", 0)) + 1
	heists.book(result)
	night_heist = result.duplicate()
	heist = null
	heist_changed.emit({"active": false, "result": result})
	save_now()
	return result


# ============================================================== federal heat =====
##
## docs/03 §4 and docs/05 §9. The second stage of the meter and the raid at the top of it.
## The red meter under it is the economy core's and is not touched here: `HeatMeter` latches
## its own raid at 100, and `heat.federal_enabled` only raises that meter's ceiling. What
## accrues from empire size is `federal.value`, drawn as 100 + itself.


## Ledger nodes this career owns. Spoils and relics ride in the same map as pseudo-ids
## (`spoil.`, `relic.`) and are not empire — the Feds count what you BOUGHT.
func owned_node_count() -> int:
	var n := 0
	for id: Variant in owned:
		var key := String(id)
		if key.begins_with(Commission.SPOIL_PREFIX) or key.begins_with("relic."):
			continue
		if int(owned[id]) > 0:
			n += 1
	return n


## Roll call: open the stage at R7 and let the file get thicker.
func _tick_federal() -> void:
	federal.enable(rank >= FederalHeat.RANK)
	heat.federal_enabled = federal.enabled
	var gained := federal.night_tick(owned_node_count())
	if gained > 0.0 or federal.rico_pending:
		federal_changed.emit(federal.night_summary())


## Is the next Night the RICO raid? The Count says so, and the NightController builds it.
func rico_pending() -> bool:
	return federal.rico_pending


## THE VERDICT (docs/05 §9). Survive and it is the single largest payout in the game — twice
## the held dirty, paid CLEAN, and the whole blue stage comes off. Lose and the confiscation
## is the ordinary raid's, doubled, and The Count starts suggesting the train.
func rico_finished(survived: bool, insured: bool = false) -> Dictionary:
	var result := {
		"survived": survived,
		"payout": BigMoney.zero(),
		"confiscated": BigMoney.zero(),
		"insured": false,
		"federal_before": federal.value,
	}
	if survived:
		var payout := wallet.dirty.mul(RICO_CLEAN_PAYOUT)
		wallet.earn_clean(payout)
		_book_lifetime_clean(payout)
		career_raid_survived()
		result["payout"] = payout
		add_respect(RESPECT_RICO_SURVIVED, &"rico")
		mark_reveal_event(&"first_raid_survived")
	elif insured:
		# A policy does not cover a federal case; it covers half of one (docs/04 T5).
		result["insured"] = true
		result["confiscated"] = wallet.confiscate_dirty(Rates.RAID_CONFISCATE_FRACTION)
	else:
		result["confiscated"] = wallet.confiscate_dirty(
				Rates.RAID_CONFISCATE_FRACTION * RICO_CONFISCATE_MULT)
	federal.resolve_rico(survived)
	result["federal"] = federal.value
	federal_changed.emit(federal.night_summary())
	save_now()
	return result


# ================================================================ empire mode =====
##
## docs/02 §2 R7. The City Hall Circuit lights it; sixty seconds of ×10 and a clean dividend
## at the end. Re-lightable, because the shot that opens it is the hardest one on the machine
## and a player who can fly it twice has earned it twice.


## Is the crown even reachable? The dome is a purchase (`influence.city_hall`), not a rank —
## the circuit's last leg is a shot at hardware that has to be standing there.
func empire_unlocked() -> bool:
	return stats.hardware_unlocked(&"city_hall")


## One leg of the circuit. Returns true if that closed it and lit the mode.
func empire_leg(id: StringName) -> bool:
	if not empire.on_leg(id):
		empire_changed.emit(empire.state())
		return false
	empire.begin()
	add_respect(EmpireMode.RESPECT_CIRCUIT, &"empire")
	AudioDirector.play(&"empire_start")
	AudioDirector.play(&"knocker")
	AudioDirector.music_set_level(8)
	empire_changed.emit(empire.state())
	return true


## The sixty seconds are up: the empire pays its dividend, in clean.
func empire_finished() -> BigMoney:
	var paid := earn_clean(empire.dividend(), &"empire")
	empire.book_payout(paid)
	AudioDirector.play(&"empire_end")
	AudioDirector.music_set_level(clampi(rank + MUSIC_LEVEL_OFFSET, 0, 8))
	var state := empire.state()
	state["paid"] = paid
	empire_changed.emit(state)
	return paid


## THE FAMILY REUNION (docs/02 §2 R7): at R7, once Empire has been lit tonight, the back room
## does not send one spare man — it sends everybody.
func reunion_ready() -> bool:
	return rank >= FederalHeat.RANK and empire.lit_tonight


# ================================================================== SKIP TOWN =====
##
## docs/06 §1. The one act in this game that throws a career away on purpose, so it is the
## one act that has to be exactly what it says: everything below is either kept or lost, and
## there is no third list.


## Offered from R7, and offered early after a RICO raid that did not go your way — never
## forced (docs/06 §1: "prestige is always the player's choice").
func skip_town_available() -> bool:
	return rank >= SkipTown.RANK or federal.raids_lost > 0


## What the train is worth and what gets on it, without getting on it. The Count shows this
## and the player agonizes over the last line, which is the point (docs/06 §1).
func skip_town_preview() -> Dictionary:
	var record := career_totals()
	return {
		"available": skip_town_available(),
		"juice": SkipTown.juice_for(record),
		"breakdown": SkipTown.breakdown(record),
		"city": SkipTown.city_number(),
		"next_city": SkipTown.city_number() + 1,
		"keep_candidates": bench.available() if bench != null else [],
		"start_rank": SkipTown.start_rank(),
		"stash": wallet.clean.mul(SkipTown.stash_fraction()),
		"spoils": spoils(),
		"relics": Array(heists.relics),
	}


## The Black Book perks that are GRANTED rather than read, applied at the one moment they
## mean anything: a city beginning. Everything here is idempotent per city because it happens
## exactly once — `new_game()` is the only door into a city, Skip Town included.
func _apply_city_start() -> void:
	var start := clampi(SkipTown.start_rank(), 0, RANK_RESPECT.size() - 1)
	if start > 0:
		rank = start
		respect = rank_threshold(start)
		Events.rank_changed.emit(rank)
		Events.respect_changed.emit(respect)
	if bench == null:
		return
	bench.trait_rank = rank
	for i in SkipTown.bench_starters():
		var starter := bench.hire()
		starter["level"] = maxi(int(starter.get("level", 0)), 1)


## ★ Kept Man: the specialists who come with you, most valuable first. The Book says how many
## may be named; until a picker exists the crew picks itself by seniority, which is at least
## the choice a player would make (TODO(UI): let them name them at The Count).
func kept_specialist_ids(limit: int = -1) -> PackedStringArray:
	var slots := SkipTown.kept_specialists() if limit < 0 else limit
	var out: PackedStringArray = []
	if slots <= 0:
		return out
	var rows: Array = []
	for id: Variant in owned:
		var key := String(id)
		if key.begins_with("crew.") and int(owned[id]) > 0:
			rows.append({"id": key, "level": int(owned[id])})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["level"]) != int(b["level"]):
			return int(a["level"]) > int(b["level"])
		return String(a["id"]) < String(b["id"]))
	for row: Variant in rows:
		if out.size() >= slots:
			break
		out.append(String((row as Dictionary)["id"]))
	return out


## THE ACT. `keep` is the one guy who comes with you; an empty dict means you left alone.
##
## Order matters here. The career is SCORED first (the Juice is what the city was worth), the
## stash is measured off the clean pile before it is burned, and only then is everything torn
## down — so nothing that pays out is reading a wallet that has already been emptied.
func skip_town(keep: Dictionary = {}) -> Dictionary:
	var record := career_totals()
	var result := {
		"juice": SkipTown.award(record),
		"breakdown": SkipTown.breakdown(record),
		"kept": keep.duplicate() if keep != null and not keep.is_empty() else {},
		"city": SkipTown.city_number(),
		"farewell": SkipTown.play_farewell(),
		"stash": wallet.clean.mul(SkipTown.stash_fraction()),
		"relics": Array(heists.relics),
	}

	var cities := int(career.get("cities", 0)) + 1
	var seed_value := session_seed + cities
	var kept_relics := heists.relics
	# ★ Kept Man: the specialists named to come along, and the levels they arrive at.
	var kept_nodes := {}
	for id in kept_specialist_ids():
		kept_nodes[id] = int(owned.get(id, 0))
	result["kept_specialists"] = kept_nodes.keys()

	# `new_game` IS the door into a city: it clears the career and applies the Black Book's
	# city-start perks (★ Old Contacts, ★ Everybody Knows Somebody) on the way through.
	new_game(seed_value)
	career["cities"] = cities

	# ★ The Stash: a slice of the city you left, as dirty, because of course it is.
	if (result["stash"] as BigMoney).is_positive():
		wallet.earn_dirty(result["stash"])
	# The Museum is a shelf, not a racket: relics survive the city that took them.
	heists.relics = kept_relics
	for id: Variant in kept_nodes:
		owned[String(id)] = int(kept_nodes[id])
	if not kept_nodes.is_empty():
		_push_owned_to_meta()
		_recompute_stats()
	if not (result["kept"] as Dictionary).is_empty():
		result["kept"] = _keep_one_guy(result["kept"])

	result["rank"] = rank
	result["next_city"] = SkipTown.city_number()
	AudioDirector.music_set_state(&"calm")
	save_now()
	return result


## He comes with you: same name, same rap sheet, same trait, standing at the front of a bench
## full of strangers in a city he has never seen. He is dealt a NEW id — the old city's
## numbering went with the old city, and two guys sharing an id is a bail bug waiting for a
## Family Meeting.
func _keep_one_guy(keep: Dictionary) -> Dictionary:
	var him := bench.hire()
	for key: String in ["name", "level", "pinches", "nights", "trait"]:
		if keep.has(key):
			him[key] = keep[key]
	him["state"] = Bench.STATE_FREE
	him["sit_out"] = 0
	him["from_raid"] = false
	var roster: Array[Dictionary] = [him]
	for g in bench.guys:
		if int(g.get("id", -1)) != int(him.get("id", -2)):
			roster.append(g)
	bench.guys = roster
	return him


# ======================================================= briefcases & the phone =====


## A case was hit. Rolls what was in it and pays it (docs/05 §10, odds docs/03 §3). Returns
## the result so the Night can make the right noise.
func open_briefcase() -> Dictionary:
	var result := briefcases.open(stats.hardware_unlocked(Briefcases.FENCE_FLAG))
	result["paid"] = BigMoney.zero()
	match StringName(result["kind"]):
		Briefcases.WAD:
			var wad := earn_flat_dirty(Briefcases.wad_value(stats.idle_rate_total()),
					&"briefcase")
			briefcases.book_payout(wad)
			result["paid"] = wad
		Briefcases.SETUP:
			# Stung. Heat and a face at the door — the cop is the table's to stand up.
			heat_add_flat(Briefcases.SETUP_HEAT)
		Briefcases.BOON:
			match StringName(result["boon"]):
				Briefcases.BOON_COOL:
					heat_reduce(Briefcases.BOON_COOL_HEAT)
				Briefcases.BOON_SAVE:
					pass    # the Night hands out the charge; it owns the ball saves
	briefcase_opened.emit(result)
	return result


## The phone was picked up. Every caller is worth something (docs/05 §10).
func answer_phone() -> Dictionary:
	var who := phone.answer()
	var result := {"caller": String(who), "answered": who != &""}
	match who:
		ThePhone.TIP:
			heat_reduce(ThePhone.TIP_HEAT)
		ThePhone.BET:
			# A free stake on the next landing: the house is buying, exactly as a comp does.
			casino.comps_left += 1
		ThePhone.JOB:
			add_respect(ThePhone.JOB_RESPECT, &"phone")
		ThePhone.NONNA:
			add_respect(ThePhone.NONNA_RESPECT, &"phone")
	if who != &"":
		phone_changed.emit(result)
	return result


## It rang out. If that was your grandmother, it costs you exactly one ☆ and you have earned
## every bit of it (docs/05 §10).
func phone_rang_out() -> void:
	if phone.missed_nonna():
		respect = maxi(respect - ThePhone.NONNA_MISS_RESPECT, 0)
		Events.respect_changed.emit(respect)
	phone_changed.emit({"caller": "", "answered": false, "missed": true})


# ==================================================================== THE RAT =====
##
## docs/05 §7. Roll call decides whether tonight is a clue Night; play surfaces the clues; the
## top lanes are the three names. `Game` owns the ☆, the flip and the skim.


## Roll call. True if tonight is flagged "Something's Off".
func rat_night() -> bool:
	var roster: Array = bench.available() if bench != null else []
	var opened := rat.begin_night(night_no, rank, roster, session_seed)
	if opened:
		AudioDirector.play(&"headline_sting")
		rat_changed.emit(rat.state())
	return opened


## A clue surfaced. True the first time this one lands tonight.
func rat_clue(id: StringName) -> bool:
	if not rat.note_clue(id):
		return false
	AudioDirector.play(&"radio_squelch")
	var state := rat.state()
	state["clue"] = String(id)
	state["line"] = TheRat.clue_line(id)
	rat_changed.emit(state)
	return true


## Name him (docs/05 §7). Right and he is flipped — the skim stops and it is worth ☆50. Wrong
## and the real rat makes one phone call; the caller runs the raid, and the backglass is dark
## for three Nights.
func rat_accuse(index: int) -> Dictionary:
	var result := rat.accuse(index)
	if not bool(result["made"]):
		return result
	if bool(result["right"]):
		add_respect(TheRat.RESPECT_CAUGHT, &"rat")
		AudioDirector.play(&"rankup_fanfare")
		AudioDirector.play(&"knocker")
	else:
		rat.stand_down(night_no)
		AudioDirector.play(&"drop_clack")
	var state := rat.state()
	state["result"] = result
	rat_changed.emit(state)
	save_now()
	return result


func _election_state(what: StringName, district: StringName = &"") -> Dictionary:
	return {
		"what": String(what),
		"district": String(district),
		"lit": elections.lit_count(),
		"districts": Elections.DISTRICTS.size(),
		"active": elections.active,
		"votes": elections.votes,
		"needed": Elections.VOTES_TO_WIN,
		"time_left": elections.time_left,
		"term_left": elections.term_left,
	}


# ============================================================ the Commission =====
##
## A boss fight replaces a Night (state stays `&"night"`, the NightController builds a
## `BossFight` instead of an ordinary rules set). While one is live the economy is off: the
## table earns nothing, the fight pays a fixed clean purse if it is won, and nothing else
## moves. See specs/m2-content.md §5 and game/flow/bosses/.


## Is a Commission fight suppressing the economy right now?
func economy_paused() -> bool:
	return boss != null and is_instance_valid(boss) and bool(boss.get("economy_paused"))


## Who is waiting for this career at The Count, or an empty dict. Respect for the next rank
## has to be in the bank first — the ☆ get you the meeting, the fight gets you the chair.
func boss_waiting() -> Dictionary:
	return commission.waiting(rank, respect, rank_ladder())


## The Count's "SAMMY'S WAITING" button. The next Night IS the fight.
func start_boss_night() -> bool:
	var f := boss_waiting()
	if f.is_empty() or state == &"night":
		return false
	commission.pending = StringName(f["id"])
	start_night()
	return true


## The fight is over. Victory is the rank-up ceremony: the purse, the spoil, the ☆ and the
## promotion the respect had already earned but the Commission was holding back.
func boss_finished(fight_id: StringName, victory: bool) -> Dictionary:
	var f := Commission.fight(fight_id)
	var result := {
		"id": String(fight_id),
		"name": String(f.get("name", "")),
		"won": victory,
		"purse": BigMoney.zero(),
		"spoil": "",
		"spoil_name": "",
		"attempts": commission.attempts_at(fight_id),
	}
	if victory and not f.is_empty():
		commission.mark_beaten(fight_id)
		var purse := Commission.purse_for(f)
		result["purse"] = earn_clean(purse, &"commission")
		night_boss = night_boss.add(result["purse"])
		result["spoil"] = String(f.get("spoil", ""))
		result["spoil_name"] = String(f.get("spoil_name", ""))
		grant_spoil(String(f.get("spoil", "")))
		# The trophy shelf is the Black Book's and it updates at the moment of victory, not at
		# the next Skip Town — a spoil is a thing you did, and prestige only carries it.
		var book := prestige()
		if book != null and book.has_method("remember_spoil"):
			book.call("remember_spoil", String(f.get("spoil", "")))
		add_respect(int(f.get("respect", 0)), &"boss")
		# The respect gate was already met; the fight was the only thing in the way.
		_check_rank()
	commission.last_result = result
	boss_changed.emit({"id": String(fight_id), "active": false, "won": victory})
	return result


## A fight's own payout (the Butcher's freezer). Clean, and booked on its own line so The
## Count never files boss money as a Night's takings.
func boss_payout(amount: BigMoney, _fight_id: StringName = &"") -> BigMoney:
	var paid := earn_clean(amount, &"boss")
	night_boss = night_boss.add(paid)
	return paid


func _boss_denied(group: StringName, value: BigMoney) -> void:
	if boss != null and is_instance_valid(boss) and boss.has_method("on_denied"):
		boss.call("on_denied", group, value)


# --- armored hardware / the Cold Storage spoil --------------------------------


## Armor a whole value group: its hardware still bangs and flashes, it just pays nothing.
## Turning the armor OFF hands over whatever Cold Storage banked while it was on.
func set_group_armored(group: StringName, on: bool) -> void:
	if on:
		_armored[group] = true
		return
	if not _armored.has(group):
		return
	_armored.erase(group)
	var owed: Variant = _armored_bank.get(group, null)
	_armored_bank.erase(group)
	if owed is BigMoney and (owed as BigMoney).is_positive():
		earn_clean(owed as BigMoney, &"cold_storage")
		AudioDirector.play(&"safe_open")


func is_group_armored(group: StringName) -> bool:
	return _armored.has(group)


## What Cold Storage is holding for a group right now.
func armored_bank(group: StringName) -> BigMoney:
	var v: Variant = _armored_bank.get(group, null)
	return (v as BigMoney).copy() if v is BigMoney else BigMoney.zero()


func _bank_armored(group: StringName, value: BigMoney) -> void:
	if not has_spoil(Commission.SPOIL_BUTCHER) or value == null or not value.is_positive():
		return
	var share := value.mul(COLD_STORAGE_FRACTION)
	var held: Variant = _armored_bank.get(group, null)
	_armored_bank[group] = share if not (held is BigMoney) else (held as BigMoney).add(share)


# --- spoils -------------------------------------------------------------------
##
## Signature upgrades cannot be bought (docs/05 §6), so they are not Ledger nodes — they ride
## in the same owned map as pseudo-ids (`spoil.sammys_spare`). `Stats.recompute` skips ids the
## catalog does not know, which is exactly the behaviour a taken-not-bought upgrade needs.


func has_spoil(id: String) -> bool:
	return int(owned.get(id, 0)) > 0


func grant_spoil(id: String) -> void:
	if id.is_empty() or has_spoil(id):
		return
	owned[id] = 1
	_push_owned_to_meta()
	_recompute_stats()
	save_now()


func spoils() -> PackedStringArray:
	var out: PackedStringArray = []
	for id: Variant in owned:
		if String(id).begins_with(Commission.SPOIL_PREFIX):
			out.append(String(id))
	out.sort()
	return out


# ============================================================ career ladder =====


## Every ☆ in the game arrives here (docs/03 §5 — never purchasable, never idle).
func add_respect(stars: int, _source: StringName = &"") -> void:
	if stars <= 0:
		return
	respect += stars
	night_respect += stars
	Events.respect_changed.emit(respect)
	_check_rank()


func rank_for_respect(total: int) -> int:
	var r := 0
	for i in RANK_RESPECT.size():
		if total >= rank_threshold(i):
			r = i
	return r


func respect_to_next_rank() -> int:
	var next := rank + 1
	if next >= RANK_RESPECT.size():
		return 0
	return maxi(rank_threshold(next) - respect, 0)


## The ☆ say what rank you have earned; the Commission says what rank you are allowed to
## take. Every step below R3 promotes the moment the stars land, exactly as it did in M1 —
## R3→R4 and R4→R5 wait for a fight (specs/m2-content.md §5, docs/05 §6).
func _check_rank() -> void:
	var want := commission.rank_cap(rank, rank_for_respect(respect))
	if want <= rank:
		return
	rank = want
	Events.rank_changed.emit(rank)
	AudioDirector.play(&"knocker")
	AudioDirector.play(&"rankup_fanfare")
	AudioDirector.music_set_level(clampi(rank + MUSIC_LEVEL_OFFSET, 0, 8))
	save_now()


func rank_title() -> String:
	return Headlines.rank_title(rank)


# ========================================================== state machine ======


## Boot the session: load the save, accrue the Safe, land on the attract screen.
func boot(save_path: String = SaveGame.DEFAULT_PATH) -> void:
	save = SaveGame.new(save_path)
	var data := save.read()
	if data.is_empty():
		new_game(int(Time.get_unix_time_from_system()))
	else:
		from_dict(data)
		if not save.salvaged_from.is_empty():
			print("[save] salvaged from ", save.salvaged_from)
	_accrue_safe()
	_booted = true
	state = &"attract"
	AudioDirector.music_set_level(clampi(rank + MUSIC_LEVEL_OFFSET, 0, 8))
	AudioDirector.music_set_state(&"calm")
	# The table (and anything else mirroring Stats into the world) re-reads on this —
	# its _ready ran before this load, so without it a restored career boots bare.
	Events.session_booted.emit()


func is_booted() -> bool:
	return _booted


## A career from nothing. `seed` drives the Bench names and the Job draw.
func new_game(seed_value: int = 0) -> void:
	session_seed = seed_value
	_rng.seed = seed_value
	wallet.reset()
	heat.reset()
	respect = 0
	rank = 0
	night_no = 0
	owned = {}
	_push_owned_to_meta()
	_recompute_stats()
	bench = Bench.new(seed_value, stats.bench_slots())
	jobs = Jobs.new()
	_wire(jobs.completed, _on_job_completed)
	_reveal_from_dict({})
	combo.reset()
	casino = Casino.new()
	meeting = FamilyMeeting.new()
	wire = WireDraws.new()
	collection = CollectionRound.new()
	smuggling = SmugglingRun.new()
	sitdown = SitDown.new()
	chairs = CommissionChairs.new()
	elections = Elections.new()
	heists = Heists.new()
	heist = null
	federal = FederalHeat.new()
	empire = EmpireMode.new()
	briefcases = Briefcases.new()
	phone = ThePhone.new()
	rat = TheRat.new()
	career = _blank_career()
	commission = Commission.new()
	boss = null
	_armored.clear()
	_armored_bank.clear()
	set_fielded([])
	safe_pending = BigMoney.zero()
	last_seen = Time.get_unix_time_from_system()
	best_night = BigMoney.zero()
	last_night = {}
	_reset_night_tallies()
	_apply_city_start()
	_booted = true
	state = &"attract"


## attract/count → night. The host scene builds the NightController when it sees the state.
func start_night() -> void:
	if state == &"night":
		return
	if bench == null:
		bench = Bench.new(session_seed, stats.bench_slots())
	night_no += 1
	bench.night_tick(stats.bench_slots(), rank)
	jobs.roll(rank, stats, stats.job_slots(), _rng)
	jobs.begin_night()
	night_rerolls = maxi(stats.job_rerolls(), 0)
	combo.reset_night()
	casino.begin_night(Casino.comps_for(stats))
	meeting.begin_night()
	collection.begin_night()
	smuggling.begin_night()
	sitdown.begin_night()
	chairs.begin_night()
	elections.begin_night()
	heist = null
	empire.begin_night()
	briefcases.begin_night(session_seed, night_no)
	phone.begin_night(session_seed, night_no)
	_tick_federal()
	wire.begin_night(session_seed, night_no)
	set_fielded([])
	_reset_night_tallies()
	_armored.clear()
	_armored_bank.clear()
	state = &"night"
	Events.night_started.emit(night_no)
	AudioDirector.music_set_state(&"calm")


## night → count. `summary` comes from the NightController; the pocket-money wash, the
## headline and the record book are applied here so the Count screen only has to render.
func end_night(summary: Dictionary) -> Dictionary:
	var pocket := launder(1.0, BigMoney.min_of(pocket_money(), night_dirty))
	var s := summary.duplicate()
	s["night"] = night_no
	s["rank"] = rank
	s["rank_title"] = rank_title()
	s["dirty"] = night_dirty
	s["idle"] = night_idle
	s["pocket"] = pocket
	s["laundered"] = night_laundered
	s["clean"] = wallet.clean
	s["dirty_held"] = wallet.dirty
	s["respect"] = night_respect
	s["respect_total"] = respect
	s["jobs"] = night_jobs.duplicate()
	s["jobs_done"] = night_jobs.size()
	s["skill_shots"] = night_skill_shots
	s["best_combo"] = night_best_combo
	s["heat"] = heat.value
	s["bench_free"] = bench.available().size() if bench != null else 0
	s["best_night"] = best_night
	s["quiet_floor"] = pocket_money()
	s["clean_earned"] = night_clean
	s["casino"] = casino.night_summary()
	s["wire"] = wire.night_summary()
	s["meeting"] = meeting.night_summary()
	s["collection"] = collection.night_summary()
	s["smuggling"] = smuggling.night_summary()
	s["sitdown"] = sitdown.night_summary()
	s["chairs"] = chairs.night_summary()
	# A Night in office is spent here rather than at roll call, so the Night the ballot was
	# won still counts as one of yours (docs/05 §8).
	elections.night_tick()
	s["election"] = elections.night_summary()
	s["federal"] = federal.night_summary()
	s["empire"] = empire.night_summary()
	s["briefcases"] = briefcases.night_summary()
	s["phone"] = phone.night_summary()
	s["rat"] = rat.night_summary()
	s["heist"] = night_heist.duplicate()
	# `boss` comes from the NightController — `commission.last_result` is the CAREER's last
	# fight and would print a week-old front page on an ordinary Night.
	s["boss_paid"] = night_boss
	s["insured"] = night_insured
	s["rank_up"] = bool(s.get("rank_up", int(s.get("rank_before", rank)) < rank))
	# The board is worked at The Count, so the Consigliere's rerolls are refilled for it here
	# as well as at roll call — they are per Night, and this is where a Night is read.
	night_rerolls = maxi(stats.job_rerolls(), 0)
	s["rerolls"] = night_rerolls
	s["headline"] = _headlines.pick(s, _rng)
	if night_dirty.cmp(best_night) > 0:
		best_night = night_dirty
	last_night = s
	state = &"count"
	Events.night_ended.emit(s)
	AudioDirector.music_set_state(&"count")
	save_now()
	return s


func open_ledger() -> void:
	if state == &"count":
		state = &"ledger"


func close_ledger() -> void:
	if state == &"ledger":
		state = &"count"


# ================================================================= actions =====


## Ledger purchase. Spends clean, levels the node, recomputes Stats, tells the world.
## Ledger purchase from outside the Ledger board (the flow sims, and any one-tap buy that
## lands later). The level is minted by the meta lane's `LedgerState` so the owned map has
## exactly one canonical home; `owned` is this file's mirror of it, for the save.
func buy_upgrade(id: String, cost: BigMoney) -> bool:
	if not wallet.spend_clean(cost):
		return false
	var level := _mint_level(id)
	_recompute_stats()
	AudioDirector.play(&"stamp_thunk")
	Events.upgrade_purchased.emit(id, level)
	return true


func _mint_level(id: String) -> int:
	_pull_owned_from_meta()
	var store := _meta_owned_store()
	var level := int(owned.get(id, 0)) + 1
	if store != null and store.has_method("add_level"):
		level = int(store.call("add_level", id))
	owned[id] = level
	_push_owned_to_meta()
	return level


## Every recompute of the fold goes through here, so the handful of Stats numbers that other
## systems have to be TOLD about (rather than asking every frame) are pushed in one place.
## Right now that is Whispers Cohen's `heat_decay_mult` on the meter's calm decay.
func _recompute_stats() -> void:
	stats.recompute(owned)
	heat.decay_scale = maxf(stats.heat_decay_mult(), 0.0)


## What a guy's bail actually costs after Cohen has talked to the bondsman
## (`bail_discount`, specs/m2-content.md §2). Capped by `Stats.BAIL_DISCOUNT_MAX`.
func bail_cost(guy: Dictionary) -> BigMoney:
	if bench == null or guy.is_empty():
		return BigMoney.zero()
	var cost := bench.bail_cost(guy, rank)
	var off := clampf(stats.bail_discount(), 0.0, Stats.BAIL_DISCOUNT_MAX)
	return cost if off <= 0.0 else cost.mul(1.0 - off)


## Post bail (docs/03 §8) — dirty cash, escalating with his rap sheet.
func bail_guy(guy: Dictionary) -> bool:
	if bench == null or guy.is_empty():
		return false
	var cost := bail_cost(guy)
	if not wallet.can_afford_dirty(cost):
		return false
	if not wallet.spend_dirty(cost):
		return false
	bench.bail(guy)
	AudioDirector.play(&"bail_paid")
	Events.guy_bailed.emit(guy)
	save_now()
	return true


## Throw one of tonight's slips back (the Consigliere, `job_reroll_add`). Costs a reroll and
## returns the slip that replaced it; an empty dict means nothing changed and nothing was
## spent — a board with no other eligible work is not a board you can shuffle.
func reroll_job(index: int) -> Dictionary:
	if night_rerolls <= 0:
		return {}
	var swapped := jobs.reroll(index, rank, stats, _rng)
	if swapped.is_empty():
		return {}
	night_rerolls -= 1
	AudioDirector.play(&"paper_slip")
	Events.job_assigned.emit(String(swapped.get("id", "")))
	save_now()
	return swapped


## The Beat Cop bribe shot: −20 heat for an escalating dirty cost (docs/03 §4).
func bribe() -> bool:
	var cost := heat.bribe_cost(night_bribes)
	if not wallet.can_afford_dirty(cost) or not wallet.spend_dirty(cost):
		return false
	var heat_before := heat.value
	night_bribes += 1
	heat.bribe()
	jobs.on_bribe(heat_before)
	AudioDirector.play(&"bribe_paid")
	return true


## Take the Safe (docs/03 §6). The session-open ritual.
func collect_safe() -> BigMoney:
	var got := safe_pending
	if got == null or not got.is_positive():
		return BigMoney.zero()
	wallet.earn_dirty(got)
	safe_pending = BigMoney.zero()
	last_seen = Time.get_unix_time_from_system()
	AudioDirector.play(&"safe_open")
	safe_changed.emit(safe_pending)
	save_now()
	return got


## Respect + cash for a clean Drop-Off (docs/01 §6). The cash rides the normal money path
## (so it is hot money like any other shot) but must not open a combo — the chain starts
## with the player's first real decision, not with the launch.
func award_skill_shot() -> BigMoney:
	night_skill_shots += 1
	# Balance-sim ruling: a flat base through the same multipliers as every other switch.
	# The old ×rank_scale factor made this one shot 99-100% of all career income. Career
	# growth comes from the Ledger, never from rank automatically; rank_scale stays a
	# heat/bail normalizer only.
	var payout := earn_switch(&"skill_shot", BigMoney.of(SKILL_SHOT_MANTISSA, SKILL_SHOT_EXP),
			{"no_combo": true})
	add_respect(RESPECT_SKILL_SHOT, &"skill_shot")
	AudioDirector.play(&"skill_shot_ding")
	Events.skill_shot.emit()
	return payout


# =========================================================== offline / save =====


func _accrue_safe() -> void:
	var rate := stats.idle_rate_total()
	var now := Time.get_unix_time_from_system()
	var elapsed := Offline.elapsed_clamped(now, last_seen)
	safe_pending = Offline.accrue(rate, elapsed, Rates.safe_cap(rate, stats.safe_hours()))
	last_seen = now
	safe_changed.emit(safe_pending)


func save_now() -> bool:
	last_seen = Time.get_unix_time_from_system()
	return save.write(to_dict())


func to_dict() -> Dictionary:
	return {
		"wallet": wallet.to_dict(),
		"heat": heat.to_dict(),
		"respect": respect,
		"rank": rank,
		"night_no": night_no,
		"owned": owned.duplicate(),
		"bench": bench.to_dict() if bench != null else {},
		"jobs": jobs.to_dict(),
		"reveal": _reveal_to_dict(),
		"casino": casino.to_dict(),
		"meeting": meeting.to_dict(),
		"wire": wire.to_dict(),
		"collection": collection.to_dict(),
		"smuggling": smuggling.to_dict(),
		"sitdown": sitdown.to_dict(),
		"chairs": chairs.to_dict(),
		"elections": elections.to_dict(),
		"heists": heists.to_dict(),
		"federal": federal.to_dict(),
		# The Black Book is the meta lane's object and the only one that outlives a career —
		# it rides in the same file because there is one save and it holds everything a player
		# owns, bought, taken or carried between cities.
		"prestige": _prestige_to_dict(),
		"empire": empire.to_dict(),
		"briefcases": briefcases.to_dict(),
		"phone": phone.to_dict(),
		"rat": rat.to_dict(),
		"career": _career_to_dict(),
		"commission": commission.to_dict(),
		"safe": {
			"last_seen": last_seen,
			"pending": safe_pending.to_dict(),
		},
		"records": {
			"best_night": best_night.to_dict(),
		},
		"rng": {
			"seed": str(session_seed),
			"state": str(_rng.state),
		},
	}


func from_dict(d: Dictionary) -> void:
	if d == null or d.is_empty():
		return
	wallet.from_dict(d.get("wallet", {}))
	heat.from_dict(d.get("heat", {}))
	respect = int(d.get("respect", 0))
	rank = int(d.get("rank", 0))
	night_no = int(d.get("night_no", 0))
	# The Book is restored BEFORE anything reads a perk: `start_rank`, the ladder's prices and
	# Pocket Money are all questions this file asks the moment a career comes back.
	_prestige_from_dict(d.get("prestige", {}))
	var raw_owned: Variant = d.get("owned", {})
	owned = {}
	if raw_owned is Dictionary:
		for k: Variant in raw_owned:
			owned[String(k)] = int((raw_owned as Dictionary)[k])
	_push_owned_to_meta()
	_recompute_stats()

	var rng_d: Dictionary = d.get("rng", {})
	session_seed = SaveGame.to_i64(rng_d.get("seed", 0), 0)
	_rng.seed = session_seed
	_rng.state = SaveGame.to_i64(rng_d.get("state", null), int(_rng.state))

	bench = Bench.new(session_seed, stats.bench_slots())
	bench.from_dict(d.get("bench", {}))
	jobs = Jobs.new()
	_wire(jobs.completed, _on_job_completed)
	jobs.from_dict(d.get("jobs", {}))
	_reveal_from_dict(d.get("reveal", {}))
	casino = Casino.new()
	casino.from_dict(d.get("casino", {}))
	meeting = FamilyMeeting.new()
	meeting.from_dict(d.get("meeting", {}))
	wire = WireDraws.new()
	wire.from_dict(d.get("wire", {}))
	collection = CollectionRound.new()
	collection.from_dict(d.get("collection", {}))
	smuggling = SmugglingRun.new()
	smuggling.from_dict(d.get("smuggling", {}))
	sitdown = SitDown.new()
	sitdown.from_dict(d.get("sitdown", {}))
	chairs = CommissionChairs.new()
	chairs.from_dict(d.get("chairs", {}))
	elections = Elections.new()
	elections.from_dict(d.get("elections", {}))
	heists = Heists.new()
	heists.from_dict(d.get("heists", {}))
	heist = null
	federal = FederalHeat.new()
	federal.from_dict(d.get("federal", {}))
	heat.federal_enabled = federal.enabled
	empire = EmpireMode.new()
	empire.from_dict(d.get("empire", {}))
	briefcases = Briefcases.new()
	briefcases.from_dict(d.get("briefcases", {}))
	phone = ThePhone.new()
	phone.from_dict(d.get("phone", {}))
	rat = TheRat.new()
	rat.from_dict(d.get("rat", {}))
	_career_from_dict(d.get("career", {}))
	commission = Commission.new()
	commission.from_dict(d.get("commission", {}))
	boss = null
	_armored.clear()
	_armored_bank.clear()
	set_fielded([])

	var safe_d: Dictionary = d.get("safe", {})
	last_seen = float(safe_d.get("last_seen", Time.get_unix_time_from_system()))
	safe_pending = BigMoney.from_dict(safe_d.get("pending", {}))
	var records: Dictionary = d.get("records", {})
	best_night = BigMoney.from_dict(records.get("best_night", {}))
	combo.reset()
	_reset_night_tallies()


# ================================================================ internals =====


func _reset_night_tallies() -> void:
	night_dirty = BigMoney.zero()
	night_idle = BigMoney.zero()
	night_laundered = BigMoney.zero()
	night_clean = BigMoney.zero()
	night_group = {}
	night_group_base = {}
	night_respect = 0
	night_jobs = []
	night_skill_shots = 0
	night_best_combo = 0
	night_bribes = 0
	night_boss = BigMoney.zero()
	night_insured = false
	night_heist = {}


## Fires for our own purchases and for anything the meta lane buys directly — the level
## is absolute, so recording it twice is harmless.
func _on_upgrade_purchased(id: String, level: int) -> void:
	_pull_owned_from_meta()
	owned[id] = maxi(level, int(owned.get(id, 0)))
	_recompute_stats()
	_push_owned_to_meta()
	if bench != null:
		bench.slots = maxi(bench.slots, stats.bench_slots())
	save_now()


## The meta lane's `Prestige` — Juice, the Black Book and what its perks promise. Reached
## through `SkipTown`, which loads it by path for the same reason `LedgerState` is loaded by
## path: a missing meta lane costs the Book, never the boot.
func prestige() -> Object:
	return SkipTown.prestige()


## Black Book perks that are READ rather than granted: they are facts about the city you are
## in, so they are folded where they are used instead of being applied once.


## ★ Traveling Light: Pocket Money scales with the city number.
func pocket_money() -> BigMoney:
	return stats.pocket_money().mul(maxf(float(SkipTown.perk("pocket_money_mult", 1.0)), 0.0))


## ★ Fast Learner: the ladder is cheaper in a city you have beaten before. The ranks are the
## same ranks; the ☆ they cost are not.
func rank_threshold(r: int) -> int:
	var i := clampi(r, 0, RANK_RESPECT.size() - 1)
	var mult := maxf(float(SkipTown.perk("star_requirement_mult", 1.0)), 0.01)
	return int(round(float(RANK_RESPECT[i]) * mult))


## The whole ladder at this city's prices — what `Commission.waiting` and the rank check read.
func rank_ladder() -> PackedInt32Array:
	var out: PackedInt32Array = []
	for i in RANK_RESPECT.size():
		out.append(rank_threshold(i))
	return out


func _meta_owned_store() -> GDScript:
	if _ledger_state == null and ResourceLoader.exists(LEDGER_STATE_PATH):
		_ledger_state = load(LEDGER_STATE_PATH)
	return _ledger_state


## The meta lane's `Reveal` singleton — which face-down Ledger cards have been turned over.
## The events that flip them happen here (a TILT, a survived raid), and the save file is
## flow's, so flow marks them and flow persists them.
func _reveal() -> Object:
	if _reveal_script == null and ResourceLoader.exists(REVEAL_PATH):
		_reveal_script = load(REVEAL_PATH)
	if _reveal_script == null or not _reveal_script.has_method("shared"):
		return null
	return _reveal_script.call("shared")


## Record a milestone the Ledger reveals cards on (`first_tilt`, `first_raid_survived`,
## `first_double_pinch` — see Upgrades.REVEAL_EVENTS).
func mark_reveal_event(id: StringName) -> void:
	var r := _reveal()
	if r != null and r.has_method("mark_event"):
		r.call("mark_event", id)


func _prestige_to_dict() -> Dictionary:
	var p := prestige()
	if p == null or not p.has_method("to_dict"):
		return {}
	var d: Variant = p.call("to_dict")
	return d if d is Dictionary else {}


func _prestige_from_dict(d: Variant) -> void:
	var p := prestige()
	if p != null and p.has_method("from_dict"):
		p.call("from_dict", d if d is Dictionary else {})


func _reveal_to_dict() -> Dictionary:
	var r := _reveal()
	if r == null or not r.has_method("to_dict"):
		return {}
	var d: Variant = r.call("to_dict")
	return d if d is Dictionary else {}


func _reveal_from_dict(d: Variant) -> void:
	var r := _reveal()
	if r == null or not r.has_method("from_dict"):
		return
	r.call("from_dict", d if d is Dictionary else {})


func _push_owned_to_meta() -> void:
	var store := _meta_owned_store()
	if store != null and store.has_method("set_owned"):
		store.call("set_owned", owned)


func _pull_owned_from_meta() -> void:
	var store := _meta_owned_store()
	if store == null or not store.has_method("get_owned"):
		return
	var theirs: Variant = store.call("get_owned")
	if not (theirs is Dictionary):
		return
	for id: Variant in theirs as Dictionary:
		var key := String(id)
		owned[key] = maxi(int((theirs as Dictionary)[id]), int(owned.get(key, 0)))


## An Old-Timer on the table talks the Commission up: +25% ☆ on anything he was out for.
## The Consigliere does the same from a desk (`job_respect_mult`, specs/m2-content.md §2);
## that getter is read through `has_method` because the meta lane is still growing `Stats`.
func _on_job_completed(j: Dictionary, stars: int) -> void:
	night_jobs.append(String(j.get("name", j.get("id", "job"))))
	var paid := GuyTraits.job_respect(stars, fielded)
	if stats.has_method("job_respect_mult"):
		paid = maxi(int(round(float(paid) * float(stats.call("job_respect_mult")))), paid)
	add_respect(paid, &"job")
	AudioDirector.play(&"job_done")
	Events.job_completed.emit(String(j.get("id", "")), stars)


func _on_combo_changed(count: int) -> void:
	night_best_combo = maxi(night_best_combo, count)
	Events.combo_changed.emit(count)
	if count == 2:
		AudioDirector.play(&"combo_2")
	elif count == 3:
		AudioDirector.play(&"combo_3")
	elif count >= 4:
		AudioDirector.play(&"combo_4")


func _on_combo_respect(stars: int) -> void:
	add_respect(stars, &"combo")
