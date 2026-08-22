extends Node2D
## FLOW acceptance runner (specs/m1-hook.md Lane 1 "Sims"). Boots the real game scene with
## a purchased-set fixture, plays scripted Nights with real physics, and asserts the session
## model: count summary math, Bench states, both Raid branches, bail, Jobs and the save
## round-trip. Prints PASS/FAIL per scenario and quits 0 only if every one passed.
##
## Everything is counted in physics ticks, never wall time, and the save file is redirected
## to `user://sim_night_save.json` so a sim run never touches a real career.

const MAIN_SCENE := preload("res://game/main.tscn")
const SIM_SAVE := "user://sim_night_save.json"
const SEED := 0x4B50494E

## Fixture: the R0 shopping list plus the laundromat, so laundering and idle both have
## something to do inside a sim Night.
const FIXTURE: PackedStringArray = [
	"muscle.real_plunger", "rackets.trash_2", "rackets.trash_3", "muscle.corner_boys",
	"muscle.chalk_lines", "rackets.numbers_game", "fronts.coin_op",
]

const DRAIN_POINT := Vector2(490.0, 1876.0)
const SAFE_POINT := Vector2(490.0, 760.0)
const KEEP_ALIVE_Y := 1400.0

## Headless physics runs at 1x wall clock, so every second of scripted play costs a second
## of CI. Nights are played on a budget and the Raid's 45 s is shortened to RAID_SECONDS —
## the branch logic is what is under test, not the length of the mode.
const NIGHT_BUDGET := 26.0
const RAID_SECONDS := 8.0

var main: Main = null
var table: Node2D = null
var stats: Stats = null

var _results: Array[Dictionary] = []
var _current: String = ""
var _fails: PackedStringArray = []
var _rng := RandomNumberGenerator.new()

var _earned: BigMoney = BigMoney.zero()
var _laundered: BigMoney = BigMoney.zero()
var _counts: Dictionary = {}
var _raid_results: Array[bool] = []
var _keep_alive: bool = false
var _flip_state: bool = false


func _ready() -> void:
	_rng.seed = SEED
	main = MAIN_SCENE.instantiate()
	main.auto_start = false
	main.show_hud = true
	add_child(main)
	table = main.table

	SaveGame.new(SIM_SAVE).erase()
	main.start_session(SIM_SAVE)
	Game.new_game(SEED)
	stats = Game.stats

	Events.dirty_earned.connect(func(a: BigMoney, _g: StringName) -> void:
		_earned = _earned.add(a))
	Events.laundered.connect(func(a: BigMoney) -> void: _laundered = _laundered.add(a))
	Events.night_started.connect(func(_n: int) -> void: _bump("night_started"))
	Events.night_ended.connect(func(_s: Dictionary) -> void: _bump("night_ended"))
	Events.guy_pinched.connect(func(_g: Dictionary) -> void: _bump("guy_pinched"))
	Events.raid_started.connect(func() -> void: _bump("raid_started"))
	Events.raid_ended.connect(func(survived: bool) -> void:
		_bump("raid_ended")
		_raid_results.append(survived))
	Events.job_completed.connect(func(_id: String, _r: int) -> void: _bump("job_completed"))
	Events.skill_shot.connect(func() -> void: _bump("skill_shot"))
	Events.rank_changed.connect(func(_r: int) -> void: _bump("rank_changed"))
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


func _bump(key: String) -> void:
	_counts[key] = int(_counts.get(key, 0)) + 1


func count_of(key: String) -> int:
	return int(_counts.get(key, 0))


func ball() -> Ball:
	return TableAPI.ball(table)


## Keep the current guy alive: a raid has to be survivable in a sim that cannot flip well.
func _physics_process(_delta: float) -> void:
	if not _keep_alive:
		return
	var b := ball()
	if b != null and b.global_position.y > KEEP_ALIVE_Y:
		b.place(SAFE_POINT)


# ---------------------------------------------------------------- driving

## Play the table: launch whatever is sitting in the lane and work the flippers, so the
## Night earns like a Night instead of like a dropped ball.
func _drive(tick: int) -> void:
	var plunger: Plunger = TableAPI.prop(table, "plunger") as Plunger
	if plunger != null and plunger.ball_ready():
		plunger.launch(_rng.randf_range(0.9, 1.0))
		return
	if tick % 40 != 0:
		return
	_flip_state = not _flip_state
	for key: String in ["flipper_left", "flipper_right"]:
		var f: Variant = TableAPI.prop(table, key)
		if f is Flipper:
			(f as Flipper).set_pressed(_flip_state)


func _release_flippers() -> void:
	for key: String in ["flipper_left", "flipper_right"]:
		var f: Variant = TableAPI.prop(table, key)
		if f is Flipper:
			(f as Flipper).set_pressed(false)


## Run the Night until it hands over to The Count (or `max_seconds` runs out).
func _play_until_count(max_seconds: float) -> int:
	var t := 0
	var limit := ticks(max_seconds)
	while Game.state == &"night" and t < limit:
		_drive(t)
		await step(1)
		t += 1
	_release_flippers()
	return t


## Force the current guy into holding right now.
func _force_drain() -> void:
	var b := ball()
	if b != null:
		b.place(DRAIN_POINT)
	await wait(0.2)


## Drain whatever is left of tonight's line-up so the Night reaches The Count on a budget.
func _finish_night_by_force() -> void:
	for i in range(NightController.GUYS_PER_NIGHT + 2):
		if Game.state != &"night":
			return
		await _force_drain()
		await wait(NightController.PINCH_BEAT + 0.4)


func _wait_for_state(want: StringName, max_seconds: float) -> bool:
	var limit := ticks(max_seconds)
	for i in range(limit):
		if Game.state == want:
			return true
		await step(1)
	return Game.state == want


func _buy_fixture(ids: PackedStringArray) -> void:
	for id in ids:
		Game.buy_upgrade(id, BigMoney.zero())


# ---------------------------------------------------------------- scenarios

func _run() -> void:
	print("== KINGPIN M1 flow sim ==")
	print("physics %d Hz | seed 0x%X | save %s" % [Engine.physics_ticks_per_second, SEED, SIM_SAVE])
	await step(4)

	await _s1_full_night()
	await _s2_raid_survived()
	await _s3_raid_lost()
	await _s4_bail_and_bench()
	await _s5_save_roundtrip()
	await _s6_offline_safe()

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


## 1 — a whole Night: three guys, real physics, and a Count that adds up.
func _s1_full_night() -> void:
	begin("full night: three guys, count summary math")
	_buy_fixture(FIXTURE)
	check(stats.hardware_unlocked(&"bumper_2"), "fixture did not unlock bumper_2")
	check(stats.flag(&"plunger_bands"), "fixture did not set the plunger_bands flag")
	check(stats.launder_rate() > 0.0, "fixture did not unlock the laundromat loop")

	_earned = BigMoney.zero()
	_laundered = BigMoney.zero()
	var respect_before := Game.respect
	Game.start_night()
	check(Game.state == &"night", "state is %s, expected night" % Game.state)
	check(count_of("night_started") == 1, "night_started fired %d times" % count_of("night_started"))
	check(main.night != null and main.night.running, "no NightController is running")
	var fielded := main.night.lineup.size()
	check(fielded == 3, "fielded %d guys, expected 3" % fielded)
	# At R0 only `send_a_message` clears the min_rank gate, so the board is one slip deep.
	check(Game.jobs.active.size() == 1,
			"rolled %d job slips at R0, expected 1 eligible" % Game.jobs.active.size())

	var played := await _play_until_count(NIGHT_BUDGET)
	await _finish_night_by_force()
	check(await _wait_for_state(&"count", 6.0), "night never reached The Count")

	var s := Game.last_night
	print("        played %.1fs | dirty %s | laundered %s | clean %s | respect +%d | jobs %d"
			% [float(played) / float(Engine.physics_ticks_per_second),
				_money(s, "dirty").text(), _money(s, "laundered").text(),
				_money(s, "clean").text(), int(s.get("respect", 0)), int(s.get("jobs_done", 0))])
	print("        headline: %s" % String(s.get("headline", "")))

	check(count_of("guy_pinched") == 3, "guy_pinched fired %d times" % count_of("guy_pinched"))
	check(int(s.get("guys_lost", 0)) == 3, "summary says %d guys lost" % int(s.get("guys_lost", 0)))
	check(_money(s, "dirty").equals_approx(_earned, 1e-6),
			"summary dirty %s != sum of dirty_earned %s" % [_money(s, "dirty").text(), _earned.text()])
	check(_money(s, "laundered").equals_approx(_laundered, 1e-6),
			"summary laundered %s != sum of laundered events %s"
			% [_money(s, "laundered").text(), _laundered.text()])
	check(_money(s, "clean").equals_approx(Game.wallet.clean, 1e-9), "summary clean != wallet clean")
	check(_money(s, "clean").equals_approx(_money(s, "laundered"), 1e-6),
			"clean %s should be exactly what was laundered %s"
			% [_money(s, "clean").text(), _money(s, "laundered").text()])
	var expect_dirty := _money(s, "dirty").sub_clamped(_money(s, "laundered"))
	check(Game.wallet.dirty.equals_approx(expect_dirty, 1e-6),
			"held dirty %s != earned - laundered %s" % [Game.wallet.dirty.text(), expect_dirty.text()])
	check(_money(s, "pocket").is_positive(), "pocket money did not auto-clean anything")
	check(int(s.get("respect", 0)) == Game.respect - respect_before,
			"summary respect %d != actual gain %d" % [int(s.get("respect", 0)), Game.respect - respect_before])
	check(not String(s.get("headline", "")).is_empty(), "no headline was printed")
	check(int(s.get("night", 0)) == 1, "summary night is %d" % int(s.get("night", 0)))

	var held := Game.bench.holding()
	check(held.size() == 3, "%d guys in holding, expected 3" % held.size())
	check(Game.bench.available().size() == Game.bench.guys.size() - 3,
			"available roster did not shrink by the three pinched guys")
	check(main.count != null and is_instance_valid(main.count), "The Count screen was not built")
	if main.count != null:
		main.count.skip()
		check(main.count.finished(), "The Count never finished its roll-up")
	finish()


## 2 — Heat 100 with the guy kept alive: Beat the Rap.
func _s2_raid_survived() -> void:
	begin("raid survived: +25 respect, clean payout, heat 30")
	check(is_equal_approx(RaidMode.DURATION, 45.0),
			"the shipped raid is %.0f s, the spec says 45" % RaidMode.DURATION)
	Game.start_night()
	main.night.raid_duration = RAID_SECONDS
	await wait(0.5)
	var plunger: Plunger = TableAPI.prop(table, "plunger") as Plunger
	if plunger != null:
		plunger.launch(1.0)
	await wait(0.5)
	_keep_alive = true

	var respect_before := Game.respect
	var clean_before := Game.wallet.clean
	var raids_before := count_of("raid_started")
	Game.heat.value = Rates.RAID_THRESHOLD
	await wait(0.2)
	check(count_of("raid_started") == raids_before + 1, "raid_started did not fire at heat 100")
	check(main.night.raid != null and main.night.raid.active, "no RaidMode is running")

	await wait(RAID_SECONDS + 1.0)
	_keep_alive = false
	check(_raid_results.size() > 0 and _raid_results[-1] == true, "the raid was not survived")
	check(is_equal_approx(Game.heat.value, Rates.RAID_SURVIVE_HEAT),
			"heat is %.1f after surviving, expected %.1f" % [Game.heat.value, Rates.RAID_SURVIVE_HEAT])
	check(Game.respect - respect_before >= Game.RESPECT_RAID_SURVIVED,
			"surviving paid %d respect, expected at least %d"
			% [Game.respect - respect_before, Game.RESPECT_RAID_SURVIVED])
	check(Game.wallet.clean.cmp(clean_before) > 0, "Beat the Rap paid no clean cash")
	print("        heat %.0f | respect +%d | clean %s -> %s"
			% [Game.heat.value, Game.respect - respect_before, clean_before.text(),
				Game.wallet.clean.text()])

	await _finish_night_by_force()
	check(await _wait_for_state(&"count", 6.0), "the Night after the raid never reached The Count")
	check(String(Game.last_night.get("raid", "")) == "survived",
			"summary raid is '%s'" % String(Game.last_night.get("raid", "")))
	check(_money(Game.last_night, "raid_payout").is_positive(), "summary has no raid payout")
	finish()


## 3 — Heat 100 and the guy drains: confiscation of DIRTY only, never clean.
func _s3_raid_lost() -> void:
	begin("raid lost: 30% of dirty confiscated, clean untouched, longer stretch")
	Game.start_night()
	main.night.raid_duration = RAID_SECONDS
	await wait(0.5)
	var plunger: Plunger = TableAPI.prop(table, "plunger") as Plunger
	if plunger != null:
		plunger.launch(1.0)
	await wait(0.6)

	var dirty_before := Game.wallet.dirty
	var clean_before := Game.wallet.clean
	var guy := main.night.current_guy()
	Game.heat.value = Rates.RAID_THRESHOLD
	await wait(0.2)
	check(main.night.raid != null and main.night.raid.active, "no RaidMode is running")
	await _force_drain()
	await wait(0.5)

	check(_raid_results.size() > 0 and _raid_results[-1] == false, "the raid was not lost")
	check(is_equal_approx(Game.heat.value, Rates.RAID_BUST_HEAT),
			"heat is %.1f after a bust, expected %.1f" % [Game.heat.value, Rates.RAID_BUST_HEAT])
	var want_dirty := dirty_before.mul(1.0 - Rates.RAID_CONFISCATE_FRACTION)
	check(Game.wallet.dirty.equals_approx(want_dirty, 1e-6),
			"dirty %s after confiscation, expected %s" % [Game.wallet.dirty.text(), want_dirty.text()])
	check(Game.wallet.clean.equals_approx(clean_before, 1e-9), "a busted raid touched clean cash")
	var pinched := Game.bench.find_by_id(int(guy["id"]))
	check(bool(pinched.get("from_raid", false)), "the guy did not get a raid stretch")
	check(int(pinched.get("sit_out", 0)) == Bench.SIT_OUT_NIGHTS_RAID,
			"raid stretch is %d nights" % int(pinched.get("sit_out", 0)))
	var normal := Rates.bail_cost(int(pinched["level"]), maxi(int(pinched["pinches"]) - 1, 0), false)
	check(Game.bench.bail_cost(pinched).equals_approx(normal.mul(Rates.BAIL_RAID_MULTIPLIER), 1e-9),
			"raid bail is not x%.0f" % Rates.BAIL_RAID_MULTIPLIER)
	print("        dirty %s -> %s | clean held at %s | stretch %d nights"
			% [dirty_before.text(), Game.wallet.dirty.text(), Game.wallet.clean.text(),
				int(pinched.get("sit_out", 0))])

	await _finish_night_by_force()
	check(await _wait_for_state(&"count", 6.0), "the raid Night never reached The Count")
	check(String(Game.last_night.get("raid", "")) == "lost", "summary raid is not 'lost'")
	finish()


## 4 — the Bench: bail costs dirty and puts a guy straight back on the roster; everyone
## else walks after sitting a Night out.
func _s4_bail_and_bench() -> void:
	begin("bench: bail springs a guy, the rest walk after a night")
	var held := Game.bench.holding()
	check(held.size() > 0, "nobody is in holding after three Nights")
	if held.is_empty():
		finish()
		return
	var guy := held[0]
	var cost := Game.bench.bail_cost(guy)
	Game.wallet.earn_dirty(cost.mul(2.0))
	var dirty_before := Game.wallet.dirty
	var ok := Game.bail_guy(guy)
	check(ok, "bail_guy refused a payable bail")
	check(String(guy["state"]) == Bench.STATE_FREE, "the bailed guy is still inside")
	check(Game.wallet.dirty.equals_approx(dirty_before.sub_clamped(cost), 1e-6),
			"bail did not cost exactly %s" % cost.text())

	for i in Bench.SIT_OUT_NIGHTS_RAID:
		Game.bench.night_tick(Game.stats.bench_slots())
	check(Game.bench.holding().is_empty(),
			"holding did not empty after sitting out the longest stretch")
	check(Game.bench.available().size() >= 1, "the bench cannot field anybody — hard lock")
	print("        bail %s | roster %d | available %d"
			% [cost.text(), Game.bench.guys.size(), Game.bench.available().size()])
	finish()


## 5 — the whole session dict survives a write/read cycle, and a shredded save falls back
## to its backup instead of to a new career.
func _s5_save_roundtrip() -> void:
	begin("save: round-trip equality and backup salvage")
	check(Game.save_now(), "save_now() failed: %s" % Game.save.last_error)
	var before := JSON.stringify(Game.to_dict())

	Game.wallet.earn_dirty(BigMoney.of(9.0, 9))
	Game.respect += 777
	Game.night_no += 5
	Game.owned["muscle.fresh_rubbers"] = 3
	Game.from_dict(Game.save.read())
	var after := JSON.stringify(Game.to_dict())
	check(before == after, "state did not round-trip through the save file")
	if before != after:
		print("        first difference at %s" % _first_diff(before, after))

	check(Game.save_now(), "second save_now() failed")
	var f := FileAccess.open(Game.save.path, FileAccess.WRITE)
	if f != null:
		f.store_string("{ this is not json")
		f.close()
	var salvaged := Game.save.read()
	check(not salvaged.is_empty(), "a shredded save did not fall back to a backup")
	check(not Game.save.salvaged_from.is_empty(), "salvage did not report which file it used")
	print("        payload %d bytes | salvaged from %s" % [before.length(), Game.save.salvaged_from])
	Game.from_dict(salvaged)
	check(Game.save_now(), "could not rewrite the save after a salvage")
	finish()


## 6 — the Safe: time away turns the idle rate into dirty cash, capped by safe_hours.
func _s6_offline_safe() -> void:
	begin("safe: offline accrual on boot, capped")
	var rate := Game.stats.idle_rate_total()
	check(rate.is_positive(), "the fixture has no idle rate to accrue")
	var away := 3600.0
	Game.last_seen = Time.get_unix_time_from_system() - away
	# Not save_now(): that stamps "last seen" as now, which is exactly what we are faking.
	check(Game.save.write(Game.to_dict()), "could not save before the offline test")

	Game.boot(SIM_SAVE)
	var want := Offline.accrue(rate, away, Rates.safe_cap(rate, Game.stats.safe_hours()))
	check(Game.safe_pending.equals_approx(want, 1e-6),
			"safe holds %s, expected %s" % [Game.safe_pending.text(), want.text()])
	var dirty_before := Game.wallet.dirty
	var got := Game.collect_safe()
	check(got.equals_approx(want, 1e-6), "collect paid %s, expected %s" % [got.text(), want.text()])
	check(Game.wallet.dirty.equals_approx(dirty_before.add(want), 1e-6),
			"the Safe did not land in the wallet")
	check(not Game.safe_pending.is_positive(), "the Safe still holds money after collecting")

	var huge := 100.0 * 3600.0
	Game.last_seen = Time.get_unix_time_from_system() - huge
	check(Game.save.write(Game.to_dict()), "could not save before the cap test")
	Game.boot(SIM_SAVE)
	var cap := Rates.safe_cap(rate, Game.stats.safe_hours())
	check(Game.safe_pending.equals_approx(cap, 1e-6),
			"100 hours away paid %s, expected the cap %s" % [Game.safe_pending.text(), cap.text()])
	print("        rate %s/s | 1h -> %s | capped at %s"
			% [rate.text(), want.text(), Game.safe_pending.text()])
	finish()


# ---------------------------------------------------------------- helpers

## Where two serialized states first disagree, with a little context each side.
static func _first_diff(a: String, b: String) -> String:
	var n := mini(a.length(), b.length())
	for i in range(n):
		if a[i] != b[i]:
			var from := maxi(i - 60, 0)
			return "char %d\n          saved:  ...%s\n          loaded: ...%s" \
					% [i, a.substr(from, 140), b.substr(from, 140)]
	return "length %d vs %d" % [a.length(), b.length()]


static func _money(d: Dictionary, key: String) -> BigMoney:
	var v: Variant = d.get(key, null)
	return v if v is BigMoney else BigMoney.zero()
