extends RefCounted
## C3 presentation adapters: native hardware states remain truthful and non-color cues are
## available without changing physics owners. Geometry and timing remain covered by the
## established flipper/table/plunger suites.


func run(t: TestCtx) -> void:
	_bumper_states(t)
	_slingshot_states(t)
	_flipper_states(t)
	_plunger_metadata(t)
	_ball_hold_metadata(t)
	_wall_piece_states(t)


func _bumper_states(t: TestCtx) -> void:
	var bumper := Bumper.new()
	var idle := bumper.visual_state()
	t.eq(idle["state"], &"idle", "present bumper is idle")
	t.eq(idle["mark"], &"outline", "idle bumper has an outline mark")
	bumper.set_hardware_active(false)
	var disabled := bumper.visual_state()
	t.eq(disabled["state"], &"disabled", "absent bumper is disabled")
	t.eq(disabled["mark"], &"lock_offline", "absent bumper has an offline mark")
	bumper.free()


func _slingshot_states(t: TestCtx) -> void:
	var sling := Slingshot.new()
	sling.passive_when_inactive = true
	sling.set_hardware_active(false)
	var passive := sling.visual_state()
	t.eq(passive["state"], &"idle", "passive sling remains idle, not an invitation")
	sling.set_hardware_active(true)
	var armed := sling.visual_state()
	t.eq(armed["state"], &"armed", "powered sling exposes an armed cue")
	sling.set_hardware_active(false)
	sling.passive_when_inactive = false
	sling.set_hardware_active(false)
	t.eq(sling.visual_state()["state"], &"disabled", "non-passive sling is absent when disabled")
	sling.free()


func _flipper_states(t: TestCtx) -> void:
	var flipper := Flipper.new()
	t.eq(flipper.visual_state()["state"], &"idle", "resting flipper is idle")
	flipper.state = Flipper.State.RISING
	t.eq(flipper.visual_state()["state"], &"active", "rising flipper is active")
	flipper.state = Flipper.State.HELD
	var held := flipper.visual_state()
	t.eq(held["state"], &"active", "held flipper remains an active native state")
	t.eq(held["mark"], &"held_ring", "held flipper has a ring mark")
	flipper.state = Flipper.State.REST
	flipper.telegraph(1.0)
	t.eq(flipper.visual_state()["state"], &"danger", "telegraph is danger")
	flipper.unjam()
	flipper.jam(1.0)
	t.eq(flipper.visual_state()["mark"], &"jam_alert", "jam has a dedicated danger mark")
	flipper.unjam()
	flipper.dead = true
	t.eq(flipper.visual_state()["state"], &"disabled", "dead flipper is disabled")
	flipper.free()


func _plunger_metadata(t: TestCtx) -> void:
	var plunger := BandedPlunger.new()
	var idle := plunger.visual_state()
	t.eq(idle["state"], &"idle", "plunger starts idle")
	t.eq(idle["draw_owner"], &"hud.plunger_lane", "plunger names the HUD draw owner")
	t.eq(int(idle["starter_band"]), BandedPlunger.DEFAULT_STARTER_BAND,
		"starter band metadata uses the authored default")
	plunger.set_starter_pull(BandedPlunger.STARTER_BAND_DISTANCE_PX * 2.0)
	t.eq(int(plunger.visual_state()["starter_band"]), 2, "pull metadata tracks the selected band")
	plunger.charging = true
	t.eq(plunger.visual_state()["state"], &"active", "charging plunger is active")
	plunger.enabled = false
	t.eq(plunger.visual_state()["state"], &"disabled", "disabled plunger is unavailable")
	plunger.free()


func _ball_hold_metadata(t: TestCtx) -> void:
	var ball := Ball.new()
	var idle := BallHold.visual_state(ball)
	t.eq(idle["state"], &"idle", "free ball has an idle holder state")
	t.eq(idle["draw_owner"], &"caller", "holder leaves visuals to its caller")
	BallHold.take(ball)
	var held := BallHold.visual_state(ball)
	t.eq(held["state"], &"active", "held ball is active")
	t.eq(held["mark"], &"held_ring", "held ball has a non-color ring mark")
	BallHold.give_back(ball)
	t.eq(BallHold.visual_state(ball)["state"], &"idle", "released ball returns to idle metadata")
	ball.free()


func _wall_piece_states(t: TestCtx) -> void:
	var wall := WallPiece.new()
	t.eq(wall.visual_state()["state"], &"idle", "active wall is idle")
	wall.set_hardware_active(false)
	t.eq(wall.visual_state()["state"], &"disabled", "hidden wall is disabled")
	wall.free()
