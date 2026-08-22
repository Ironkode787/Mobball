extends RefCounted
## Guy traits v1 (game/flow/traits.gd + the Bench that deals them out). One trait per guy,
## dealt from R2, folded into the money path and the Heat meter for as long as he is out
## there (docs/01 §4).

const SAVE_PATH := "user://test_flow_traits.json"


func run(t: TestCtx) -> void:
	_vocabulary(t)
	_dealing(t)
	_folds(t)
	_bench(t)

	var real_save := Game.save
	Game.save = SaveGame.new(SAVE_PATH)
	Game.save.erase()
	_money_path(t)
	Game.save.erase()
	Game.save = real_save
	Game.new_game(0)


func _vocabulary(t: TestCtx) -> void:
	t.eq(GuyTraits.rows().size(), 7, "all seven traits from names.json are known")
	t.eq(GuyTraits.label(GuyTraits.OLD_TIMER), "Old-Timer", "traits read as the data names them")
	t.eq(GuyTraits.label(""), "", "a traitless guy has no line")
	t.ok(not GuyTraits.describe(GuyTraits.SLIPPERY).is_empty(), "and each one says what it does")

	var dealable := GuyTraits.dealable()
	t.eq(dealable.size(), 6, "six of them can actually be dealt")
	t.ok(not dealable.has(GuyTraits.HEAVY),
			"Heavy is deferred (ball physics, core is frozen) so it is never handed out")
	t.ok(GuyTraits.rows().size() > dealable.size(), "but it stays in the vocabulary")


func _dealing(t: TestCtx) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	t.eq(GuyTraits.pick(rng, 0), "", "nobodies get no trait")
	t.eq(GuyTraits.pick(rng, GuyTraits.MIN_RANK - 1), "", "and neither does the rank below")

	var seen := {}
	for i in 200:
		seen[GuyTraits.pick(rng, GuyTraits.MIN_RANK)] = true
	t.ok(not seen.has(""), "from R2 every hire gets one")
	t.ok(not seen.has(GuyTraits.HEAVY), "and it is never the deferred one")
	t.eq(seen.size(), GuyTraits.dealable().size(), "the whole dealable pool comes up")


func _folds(t: TestCtx) -> void:
	var loud := {"id": 1, "trait": GuyTraits.LOUD}
	var careful := {"id": 2, "trait": GuyTraits.CAREFUL}
	var fast := {"id": 3, "trait": GuyTraits.FAST}
	var old_timer := {"id": 4, "trait": GuyTraits.OLD_TIMER}
	var slippery := {"id": 5, "trait": GuyTraits.SLIPPERY}
	var lucky := {"id": 6, "trait": GuyTraits.LUCKY}
	var nobody := {"id": 7, "trait": ""}

	t.near(GuyTraits.dirty_mult(loud), 1.10, 1e-9, "Loud is +10% dirty")
	t.near(GuyTraits.dirty_mult(fast), 1.10, 1e-9, "Fast is +10% dirty")
	t.near(GuyTraits.dirty_mult(nobody), 1.0, 1e-9, "a nobody moves nothing")
	t.near(GuyTraits.heat_scale(loud), 1.10, 1e-9, "Loud runs hot")
	t.near(GuyTraits.heat_scale(careful), 0.85, 1e-9, "Careful runs cool")
	t.near(GuyTraits.heat_scale(fast), 1.0, 1e-9, "Fast is loud in money only")
	t.near(GuyTraits.briefcase_odds_add(lucky), 0.05, 1e-9, "Lucky is stored for the briefcases")
	t.ok(GuyTraits.can_outlane_save(slippery), "Slippery has an escape")
	t.ok(not GuyTraits.can_outlane_save(loud), "nobody else does")

	t.near(GuyTraits.dirty_mult_for([loud, fast]), 1.21, 1e-9,
			"two guys on the table stack: the crew works together")
	t.near(GuyTraits.heat_scale_for([loud, careful]), 1.10 * 0.85, 1e-9, "so do their meters")
	t.near(GuyTraits.dirty_mult_for([]), 1.0, 1e-9, "an empty table multiplies nothing")
	t.near(GuyTraits.heat_scale_for([nobody]), 1.0, 1e-9, "and neither does a nobody")

	t.eq(GuyTraits.job_respect(4, [old_timer]), 5, "an Old-Timer talks a 4-star job up to 5")
	t.eq(GuyTraits.job_respect(4, [nobody]), 4, "anyone else gets what the slip says")
	t.eq(GuyTraits.job_respect(1, [old_timer]), 1,
			"and rounding never pays a guy LESS than the slip promised")


func _bench(t: TestCtx) -> void:
	var early := Bench.new(4242, 4)
	var traited := 0
	for g in early.guys:
		if not String(g["trait"]).is_empty():
			traited += 1
	t.eq(traited, 0, "the four guys a career opens with are traitless nobodies")

	var made := Bench.new(4242, 4)
	made.night_tick(5, GuyTraits.MIN_RANK)
	t.eq(made.trait_rank, GuyTraits.MIN_RANK, "the Bench is told what rank it is hiring at")
	var fresh := made.guys[made.guys.size() - 1]
	t.ok(not String(fresh["trait"]).is_empty(), "and the fifth man comes with a trait")

	var loaded := Bench.new(0)
	loaded.from_dict(JSON.parse_string(JSON.stringify(made.to_dict())))
	t.eq(JSON.stringify(loaded.to_dict()), JSON.stringify(made.to_dict()),
			"traits survive the save file")
	var half := Bench.new(0)
	half.from_dict({"guys": [{"name": "Half A Guy"}]})
	t.eq(String(half.guys[0]["trait"]), "", "a guy written before traits existed loads traitless")


## The folds where they actually land: every dirty payout, and the Heat meter's gain scale.
func _money_path(t: TestCtx) -> void:
	Game.new_game(7)
	Game.heat.reset()
	Game.combo.reset()
	var base := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	t.ok(base.equals_approx(BigMoney.from_float(100.0), 1e-9), "a bare table pays face value")

	Game.set_fielded([{"id": 1, "trait": GuyTraits.LOUD}])
	t.near(Game.mode_multiplier(), 1.10, 1e-9, "a Loud guy on the table is +10% on everything")
	var loud := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	t.ok(loud.equals_approx(BigMoney.from_float(110.0), 1e-9), "and the money path folds it in")
	t.near(Game.heat.gain_scale, 1.10, 1e-9, "he runs the meter hot while he is out there")

	Game.set_fielded([{"id": 2, "trait": GuyTraits.CAREFUL}])
	t.near(Game.heat.gain_scale, 0.85, 1e-9, "a Careful guy cools it")
	var careful := Game.earn_switch(&"bumpers", BigMoney.from_float(100.0), {"no_combo": true})
	t.ok(careful.equals_approx(BigMoney.from_float(100.0), 1e-9), "without paying any less")

	Game.set_fielded([])
	t.near(Game.heat.gain_scale, 1.0, 1e-9, "an empty table is a normal meter")
	t.near(Game.mode_multiplier(), 1.0, 1e-9, "and a normal money path")
