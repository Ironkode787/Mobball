extends Node2D
## THE ACCEPTANCE PATH (specs/m1-hook.md §Acceptance): the first ten minutes, scripted.
##
##   boot fresh → attract → Night 1 → earn → The Count shows pocket-money clean →
##   buy `muscle.real_plunger` + `rackets.trash_2` in the Ledger → Night 2 has bumper 2 live
##   and a chargeable plunger → save → reload → state intact.
##
## Named `night_sim_first10` so it sits in the flow lane's `tests/sim/night_sim*` slot. Runs
## against the real Stats, the real Upgrades catalog and the real progression table: this is
## the sim that fails when the three M1 lanes disagree.

const MAIN_SCENE := preload("res://game/main.tscn")
const SIM_SAVE := "user://sim_first10_save.json"
const SEED := 0x310A
const FIRST_BUYS: PackedStringArray = ["muscle.real_plunger", "rackets.trash_2"]

const DRAIN_POINT := Vector2(490.0, 1876.0)
## Where the coach puts the ball back (see `_coach`): the mouth of the middle top lane,
## above the one trash can the bare alley owns.
const COACH_POINT := Vector2(490.0, 480.0)
const COACH_BELOW_Y := 1250.0
## Seconds of coached play per Night — enough for the alley to bank a Night's takings.
const COACH_SECONDS := 8.0
## A launch has this long to put the ball on the playfield before the sim calls the feed
## broken (see PLAYABLE_STARTER_BAND).
const FEED_SECONDS := 2.5
const LANE_X := 900.0
## The R0 rubber band must still *deliver*. The three starter bands are 0.90/0.95/1.00;
## use the top band as a coaching fallback if a table fixture cannot feed at the default.
const PLAYABLE_STARTER_BAND := 2

var main: Main = null
var table: Node2D = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _coaching: bool = false
var _feed_warned: bool = false


func _ready() -> void:
	main = MAIN_SCENE.instantiate()
	main.auto_start = false
	add_child(main)
	table = main.table
	SaveGame.new(SIM_SAVE).erase()
	_run()


# ---------------------------------------------------------------- harness

func ticks(seconds: float) -> int:
	return maxi(1, int(round(seconds * float(Engine.physics_ticks_per_second))))


func step(count: int = 1) -> void:
	for i in range(count):
		await get_tree().physics_frame


func wait(seconds: float) -> void:
	await step(ticks(seconds))


func begin(name: String) -> void:
	_current = name
	_fails = PackedStringArray()


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails.append(msg)


func finish() -> void:
	_results.append({"name": _current, "fails": _fails.duplicate()})
	print("  [%s] %s" % ["PASS" if _fails.is_empty() else "FAIL", _current])
	for f in _fails:
		print("        - %s" % f)


func plunger() -> Plunger:
	return TableAPI.prop(table, "plunger") as Plunger


## The coach: a stand-in for skilled play. It keeps the guy off the drain and feeds him back
## over the trash can, so the alley banks a Night's takings through the real money path
## (switch → TableScore → Game.earn_switch → wallet) in seconds rather than minutes. It
## replaces the *player*, never the economy: every dollar here is a real bumper hit.
func _physics_process(_delta: float) -> void:
	if not _coaching:
		return
	var b := TableAPI.ball(table)
	if b != null and b.global_position.y > COACH_BELOW_Y:
		b.place(COACH_POINT)


## Launch, then check the ball actually made it onto the playfield.
func _serve_and_launch() -> bool:
	var p := plunger()
	if p == null:
		return false
	for i in range(ticks(4.0)):
		if p.ball_ready():
			break
		await step(1)
	p.launch(1.0)
	var reached := false
	for i in range(ticks(FEED_SECONDS)):
		await step(1)
		var b := TableAPI.ball(table)
		if b != null and b.global_position.x < LANE_X:
			reached = true
			break
	if not reached and not _feed_warned:
		_feed_warned = true
		print("        TABLE LANE: the R0 plunger cannot feed the playfield —")
		if p is BandedPlunger:
			var starter := p as BandedPlunger
			print("        BandedPlunger starter band %d (%.2f) left the ball in the shooter lane;"
					% [starter.starter_band, starter.starter_power()])
		print("        this geometry needs a safe starter feed. Coaching the ball on to finish the run.")
	if not reached:
		if p is BandedPlunger:
			(p as BandedPlunger).set_starter_band(PLAYABLE_STARTER_BAND)
	return reached


func _coach_night(seconds: float) -> void:
	_coaching = true
	await wait(seconds)
	_coaching = false


func _drain_out() -> void:
	for i in range(NightController.GUYS_PER_NIGHT + 2):
		if Game.state != &"night":
			break
		var b := TableAPI.ball(table)
		if b != null:
			b.place(DRAIN_POINT)
		await wait(NightController.PINCH_BEAT + 0.6)


# ---------------------------------------------------------------- the path

func _run() -> void:
	print("== KINGPIN first-ten-minutes sim ==")
	print("physics %d Hz | save %s" % [Engine.physics_ticks_per_second, SIM_SAVE])
	await step(4)

	await _boot_fresh()
	await _night_one()
	await _the_ledger()
	await _night_two()
	await _save_and_reload()

	var failed := 0
	for r: Dictionary in _results:
		if not (r["fails"] as PackedStringArray).is_empty():
			failed += 1
	print("---")
	print("scenarios: %d  passed: %d  failed: %d" % [_results.size(), _results.size() - failed, failed])
	print("OK" if failed == 0 else "SIM FAILED")
	if main.night != null and is_instance_valid(main.night):
		main.night.stop()
	main.queue_free()
	await step(2)
	get_tree().quit(0 if failed == 0 else 1)


## Boot with no save at all: a bare table, an attract screen, nothing owned.
func _boot_fresh() -> void:
	begin("boot fresh: attract screen over a bare alley")
	main.start_session(SIM_SAVE)
	Game.new_game(SEED)
	await step(2)
	check(Game.state == &"attract", "state is %s, expected attract" % Game.state)
	check(main.attract != null and is_instance_valid(main.attract), "no attract screen")
	check(Game.night_no == 0, "a fresh career has played %d nights" % Game.night_no)
	check(Game.owned.is_empty(), "a fresh career owns %d upgrades" % Game.owned.size())
	check(Game.bench != null and Game.bench.guys.size() == Bench.START_SLOTS,
			"the Bench did not start with four guys")
	check(not Game.stats.flag(&"plunger_bands"), "the rubber band is already a real plunger")
	check(not Game.stats.hardware_unlocked(&"bumper_2"), "the second can is already out")
	check(not _hardware_present(&"bumper_2"), "an unbought can is standing on the playfield")
	check(not _hardware_present(&"slingshots"),
			"Corner Boys are not powered on the bare table")
	var starter_sling := TableAPI.call_if(table, "hardware_node", [&"slingshots"], null) as Slingshot
	check(starter_sling != null and starter_sling.visible,
			"the bare table is missing its passive sling triangle")
	check(starter_sling != null and starter_sling.is_present()
			and not starter_sling.is_powered(),
			"the bare sling is not solid dead rubber")
	var face := starter_sling.get_node_or_null("Face") as Area2D if starter_sling != null else null
	check(face != null and face.collision_layer == 0 and face.collision_mask == 0,
			"the bare sling face sensor is still powered")
	finish()


## Night 1 on the bare table, and a Count that hands back pocket money as clean cash.
func _night_one() -> void:
	begin("night 1: play the alley, The Count pays pocket money")
	Game.start_night()
	check(Game.state == &"night", "ROLL CALL did not start the Night")
	check(main.night != null and main.night.running, "no NightController")
	check(main.hud != null and main.hud.visible, "the HUD is not up during the Night")
	var lineup := main.night.lineup.size()
	check(lineup >= 1 and lineup <= NightController.GUYS_PER_NIGHT,
			"fielded %d guys" % lineup)

	# The starter rubber band: the desktop/script path uses its middle coarse band.
	var p := plunger()
	await wait(0.6)
	if p != null:
		p.launch(1.0)
		await step(2)
		var b := TableAPI.ball(table)
		var speed := b.speed() if b != null else 0.0
		check(speed > 0.0, "the ball never left the lane")
		check(speed < Feel.PLUNGER_MAX_IMPULSE * 0.95,
				"a full-power plunge got out of a starter band (%.0f px/s)" % speed)
		await wait(FEED_SECONDS)

	await _serve_and_launch()
	await _coach_night(COACH_SECONDS)
	await _drain_out()
	check(Game.state == &"count", "the Night did not reach The Count (state %s)" % Game.state)
	check(main.count != null and is_instance_valid(main.count), "no Count screen")

	var s := Game.last_night
	var dirty: BigMoney = s.get("dirty", BigMoney.zero())
	var pocket: BigMoney = s.get("pocket", BigMoney.zero())
	print("        night 1: dirty %s | pocket %s | clean %s | respect %d | %s"
			% [dirty.text(), pocket.text(), Game.wallet.clean.text(), Game.respect,
				String(s.get("headline", ""))])
	check(dirty.is_positive(), "the alley paid nothing at all")
	check(pocket.is_positive(), "pocket money did not auto-clean the first of the Night")
	check(Game.wallet.clean.equals_approx(pocket, 1e-9),
			"clean is %s but pocket money was %s" % [Game.wallet.clean.text(), pocket.text()])
	if main.count != null:
		main.count.skip()
		check(main.count.finished(), "The Count never printed its headline")
	finish()


## The Ledger: two real purchases with the Night's clean cash.
func _the_ledger() -> void:
	begin("the ledger: buy the plunger and the second trash can")
	Game.open_ledger()
	await step(2)
	var opened := Game.state == &"ledger"
	check(opened or Game.state == &"count",
			"opening the Ledger left the session in %s" % Game.state)
	if opened:
		check(main.ledger != null and is_instance_valid(main.ledger), "no Ledger overlay")

	var catalog := Upgrades.shared()
	var spent := BigMoney.zero()
	for id in FIRST_BUYS:
		var cost := catalog.next_cost(id, Game.owned)
		check(Game.wallet.can_afford_clean(cost),
				"cannot afford %s (%s) with %s clean" % [id, cost.text(), Game.wallet.clean.text()])
		var clean_before := Game.wallet.clean
		check(Game.buy_upgrade(id, cost), "the purchase of %s was refused" % id)
		spent = spent.add(cost)
		check(Game.wallet.clean.equals_approx(clean_before.sub_clamped(cost), 1e-9),
				"%s did not cost exactly %s" % [id, cost.text()])
		check(int(Game.owned.get(id, 0)) == 1, "%s is not owned at level 1" % id)
	print("        bought %s for %s" % [", ".join(FIRST_BUYS), spent.text()])

	check(Game.stats.flag(&"plunger_bands"), "the real plunger did not set plunger_bands")
	check(Game.stats.hardware_unlocked(&"bumper_2"), "trash_2 did not unlock the second can")
	check(_meta_owned().has(FIRST_BUYS[0]),
			"the meta lane's owned map did not hear about the purchase")

	Game.close_ledger()
	await step(2)
	check(Game.state == &"count", "closing the Ledger did not return to The Count")
	finish()


## Night 2: the money became furniture.
func _night_two() -> void:
	begin("night 2: the second can is live and the plunger charges")
	Game.start_night()
	await wait(0.8)
	check(Game.night_no == 2, "this is night %d" % Game.night_no)
	check(_hardware_present(&"bumper_2"), "the bought can is not on the playfield")

	var p := plunger()
	check(p != null, "the table has no plunger")
	if p != null:
		p.set_pressed(true)
		await wait(0.35)
		var charged := p.power
		p.set_pressed(false)
		check(charged > 0.05 and charged < 0.95,
				"the plunger did not charge partway (power %.2f)" % charged)
		await step(2)
		check(not p.charging, "the plunger is still winding after release")
	print("        night 2: bumper_2 present, plunger charges")

	var dirty_before := Game.night_dirty
	await _serve_and_launch()
	await _coach_night(COACH_SECONDS * 0.5)
	check(Game.night_dirty.cmp(dirty_before) > 0, "night 2 earned nothing")
	await _drain_out()
	check(Game.state == &"count", "night 2 did not reach The Count")
	finish()


## Everything above has to survive the app dying.
func _save_and_reload() -> void:
	begin("save and reload: the career comes back whole")
	check(Game.save_now(), "save failed: %s" % Game.save.last_error)
	var before := _stable_state()
	var night_no := Game.night_no
	var respect := Game.respect
	var clean := Game.wallet.clean
	var owned := Game.owned.duplicate()
	var crew: PackedStringArray = []
	for g in Game.bench.guys:
		crew.append(String(g["name"]))

	# The app is gone: a brand new career object, then boot off the file on disk.
	Game.new_game(0)
	check(Game.night_no == 0, "the wipe did not take")
	Game.boot(SIM_SAVE)
	# Snapshot before yielding: Heat decays in Game._process, so a single frame between the
	# reload and the comparison would legitimately move the meter.
	var after := _stable_state()
	await step(2)

	check(after == before, "the reloaded career is not the saved one")
	if after != before:
		print("        saved:  %s" % before)
		print("        loaded: %s" % after)
	check(Game.night_no == night_no, "night %d came back as %d" % [night_no, Game.night_no])
	check(Game.respect == respect, "respect came back wrong")
	check(Game.wallet.clean.equals_approx(clean, 1e-9), "clean cash came back wrong")
	check(Game.owned == owned, "the owned upgrades came back wrong")
	check(Game.stats.flag(&"plunger_bands"), "Stats did not recompute from the loaded save")
	check(_meta_owned().size() == owned.size(), "the Ledger board did not get the loaded levels")
	var names: PackedStringArray = []
	for g in Game.bench.guys:
		names.append(String(g["name"]))
	check(names == crew, "the crew came back as different people")
	check(Game.state == &"attract", "a reload should land on the attract screen")
	print("        reloaded night %d, %s clean, %d upgrades, crew %s"
			% [Game.night_no, Game.wallet.clean.text(), Game.owned.size(), ", ".join(names)])
	finish()


# ---------------------------------------------------------------- helpers

## The whole session as text, minus the one field that is *meant* to move: booting stamps
## "last seen" as now once the Safe has been accounted for.
func _stable_state() -> String:
	var d := Game.to_dict()
	(d["safe"] as Dictionary).erase("last_seen")
	return JSON.stringify(d)


func _hardware_present(id: StringName) -> bool:
	return bool(TableAPI.call_if(table, "hardware_present", [id], true))


func _meta_owned() -> Dictionary:
	if not ResourceLoader.exists(Game.LEDGER_STATE_PATH):
		return Game.owned
	var store: GDScript = load(Game.LEDGER_STATE_PATH)
	if store == null or not store.has_method("get_owned"):
		return Game.owned
	var owned: Variant = store.call("get_owned")
	return owned if owned is Dictionary else {}
