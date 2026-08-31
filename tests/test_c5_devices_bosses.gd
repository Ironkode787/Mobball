extends RefCounted
## C5 presentation contract tests. These exercise draw-edge state reads without starting a
## physics scene, so the assertions cannot accidentally bless a gameplay mutation.


func run(t: TestCtx) -> void:
	_storefront(t)
	_roulette(t)
	_reels(t)
	_saucer(t)
	_kickback(t)
	_magnet(t)
	_boss(t)
	_preservation_surface(t)


func _storefront(t: TestCtx) -> void:
	var shop := Storefront.new()
	t.eq(shop.visual_state(), TableVisualState.VisualState.ARMED,
			"storefront begins as an armed invitation")
	t.eq(shop.state_name(), &"armed", "storefront keeps its native state name")
	t.ok(bool(shop.visual_token()["invitation"]), "armed storefront exposes an invitation cue")
	shop._state = Storefront.State.OPEN
	t.eq(shop.visual_state(), TableVisualState.VisualState.ACTIVE,
			"open storefront maps to active")
	shop._state = Storefront.State.COOLDOWN
	t.eq(shop.visual_state(), TableVisualState.VisualState.DISABLED,
			"cooldown storefront maps to disabled")
	t.eq(shop.visual_token()["mark"], &"cooldown_clock",
			"storefront cooldown has a non-colour clock mark")
	shop._present = false
	t.eq(shop.visual_state(), TableVisualState.VisualState.DISABLED,
			"absent storefront maps to disabled")
	shop.free()


func _roulette(t: TestCtx) -> void:
	var wheel := RouletteWheel.new()
	t.eq(wheel.pocket_count(), RouletteWheel.POCKETS, "roulette pocket count stays authored")
	t.eq(wheel.visual_state(), TableVisualState.VisualState.ARMED,
			"loose roulette wheel is available")
	wheel._inside_t = 0.1
	t.eq(wheel.visual_state(), TableVisualState.VisualState.ACTIVE,
			"roulette landing read maps to active")
	wheel._inside_t = 0.0
	wheel._cool = 0.4
	t.eq(wheel.visual_state(), TableVisualState.VisualState.DISABLED,
			"roulette cooldown maps to disabled")
	t.eq(wheel.visual_token()["mark"], &"cooldown_clock",
			"roulette cooldown has a clock mark")
	wheel.free()


func _reels(t: TestCtx) -> void:
	var reels := SlotReels.new()
	t.eq(reels.visual_state(), TableVisualState.VisualState.ARMED,
			"fresh reels are an armed three-column invitation")
	for i in range(SlotReels.COLS * SlotReels.ROWS):
		var target := DropTarget.new()
		target.down = i == 0
		reels._targets.append(target)
	# The fixture has one target down in the first column; the read still reports partial progress.
	t.eq(reels.visual_state(), TableVisualState.VisualState.ACTIVE,
			"partial reels map to active")
	t.ok(bool(reels.visual_modifiers()[&"down"]), "partial reels expose a down modifier")
	reels._present = false
	t.eq(reels.visual_state(), TableVisualState.VisualState.DISABLED,
			"absent reels map to disabled")
	reels.free()


func _saucer(t: TestCtx) -> void:
	var saucer := HoldSaucer.new()
	t.eq(saucer.visual_state(), TableVisualState.VisualState.ARMED,
			"empty saucer is an armed invitation")
	saucer._held = true
	t.eq(saucer.visual_state(), TableVisualState.VisualState.ACTIVE,
			"captured saucer maps to active")
	t.ok(bool(saucer.visual_modifiers()[&"held"]), "captured saucer exposes held modifier")
	saucer._held = false
	saucer._glow = 1.0
	t.eq(saucer.visual_state(), TableVisualState.VisualState.COMPLETED,
			"ejected saucer pulse maps to completed")
	saucer._cool = 0.5
	t.eq(saucer.visual_state(), TableVisualState.VisualState.DISABLED,
			"saucer cooldown maps to disabled")
	saucer.free()


func _kickback(t: TestCtx) -> void:
	var kicker := Kickback.new()
	t.ok(kicker.ready_to_fire(), "kickback starts charged")
	t.eq(kicker.visual_state(), TableVisualState.VisualState.ARMED,
			"charged kickback maps to armed")
	kicker._cool = 4.0
	t.eq(kicker.visual_state(), TableVisualState.VisualState.DISABLED,
			"kickback cooldown maps to disabled")
	t.eq(kicker.visual_token()["mark"], &"cooldown_clock",
			"kickback cooldown has a clock mark")
	kicker.free()


func _magnet(t: TestCtx) -> void:
	var magnet := DrainMagnet.new()
	t.eq(magnet.visual_state(), TableVisualState.VisualState.DISABLED,
			"inactive drain magnet maps to disabled")
	magnet.active = true
	t.eq(magnet.visual_state(), TableVisualState.VisualState.IDLE,
			"active idle magnet maps to idle")
	magnet._telegraphing = true
	t.eq(magnet.visual_state(), TableVisualState.VisualState.DANGER,
			"magnet telegraph maps to danger")
	t.ok(bool(magnet.visual_modifiers()[&"telegraph"]),
			"magnet telegraph remains an explicit modifier")
	magnet.free()


func _boss(t: TestCtx) -> void:
	var boss := BossTarget.new()
	t.eq(boss.visual_state(), TableVisualState.VisualState.DISABLED,
			"dormant boss maps to disabled")
	boss._present = true
	boss.hits_left = 3
	var before_moving := boss._moving
	var before_hits := boss.hits_left
	t.eq(boss.visual_state(), TableVisualState.VisualState.ARMED,
			"parked boss maps to armed")
	t.eq(boss._moving, before_moving, "boss visual read does not change movement")
	t.eq(boss.hits_left, before_hits, "boss visual read does not change hit count")
	boss._moving = true
	t.eq(boss.visual_state(), TableVisualState.VisualState.ACTIVE,
			"moving boss maps to active")
	boss._moving = false
	boss.hits_left = 0
	t.eq(boss.visual_state(), TableVisualState.VisualState.COMPLETED,
			"broken boss maps to completed")
	boss.free()


func _preservation_surface(t: TestCtx) -> void:
	t.eq(RouletteWheel.HOLD, 1.2, "roulette hold duration remains 1.2 seconds")
	t.eq(RouletteWheel.FORCE_AFTER, 3.0, "roulette anti-park force timing remains 3 seconds")
	t.eq(Storefront.TARGET_PITCH, 52.0, "storefront target pitch remains authored")
	t.eq(SlotReels.COL_PITCH, 130.0, "reel column pitch remains authored")
	t.eq(SlotReels.ROW_PITCH, 50.0, "reel row pitch remains authored")
	t.eq(HoldSaucer.STEP_SOUNDS.size(), 3, "saucer step sound ladder remains intact")
	t.eq(DrainMagnet.TELEGRAPH, 1.2, "magnet warning remains 1.2 seconds")
	t.eq(BossTarget.COOLDOWN, 0.30, "boss contact cooldown remains authored")
