extends RefCounted


func run(t: TestCtx) -> void:
	_theme_and_city(t)
	_art_catalog(t)
	_phase_one_assets(t)
	_effect_bus(t)
	_budget(t)
	_gameplay_feedback(t)
	_screen_transitions(t)


func _theme_and_city(t: TestCtx) -> void:
	var theme := PresentationTheme.defaults()
	t.eq(theme.color(&"dirty"), Feel.COL_DIRTY, "dirty stays reserved")
	t.eq(theme.color(&"clean"), Feel.COL_CLEAN, "clean stays reserved")
	t.eq(theme.color(&"felt"), Feel.COL_FELT, "default felt matches the live table")
	t.eq(theme.reserved_colors().size(), 4, "four state colors are reserved")
	t.eq(theme.color(&"not_a_role"), Color.TRANSPARENT, "unknown role is explicit")
	for role: StringName in [&"display", &"headline", &"ui", &"body", &"annotation"]:
		t.ok(theme.font_for(role) != null, "%s production font is loaded" % role)
	t.eq(theme.size_for(&"body"), 34, "body type token")
	var city := CitySkin.eastport()
	t.eq(city.id, &"eastport", "default city skin")
	t.eq(city.felt, Feel.COL_FELT, "city skin begins without a visual jump")


func _art_catalog(t: TestCtx) -> void:
	var catalog := ArtCatalog.new()
	var fallback := GradientTexture1D.new()
	var texture := GradientTexture1D.new()
	catalog.fallback = fallback
	var missing: Array[StringName] = []
	catalog.missing_requested.connect(func(id: StringName) -> void: missing.append(id))
	t.eq(catalog.resolve(&"missing"), fallback, "missing art keeps the fallback")
	t.eq(catalog.resolve(&"missing"), fallback, "missing lookup is stable")
	t.eq(missing.size(), 1, "missing art reports once")
	catalog.register(&"prop.trash_can", texture)
	t.ok(catalog.has(&"prop.trash_can"), "registered texture is present")
	t.eq(catalog.resolve(&"prop.trash_can"), texture, "semantic lookup resolves")
	catalog.unregister(&"prop.trash_can")
	t.ok(not catalog.has(&"prop.trash_can"), "unregister restores procedural fallback")


func _phase_one_assets(t: TestCtx) -> void:
	var ids: Array[StringName] = [
		&"table.backglass.eastport", &"ui.count_room_plate", &"prop.trash_can",
		&"prop.bicycle_spinner", &"prop.payphone_bank", &"ui.job_board",
		&"front.laundromat", &"front.pizzeria", &"front.pawn",
		&"mugshot.starter_01", &"mugshot.starter_02", &"mugshot.starter_03",
		&"mugshot.starter_04",
	]
	for id in ids:
		t.ok(Presentation.art.has(id), "%s is registered" % id)
	var touch := PaperKit.button("TEST")
	t.ok(touch.custom_minimum_size.y >= Presentation.theme.touch_min,
			"production buttons meet the touch target")
	touch.free()


func _effect_bus(t: TestCtx) -> void:
	var bus := EffectBus.new()
	var effects: Array[Dictionary] = []
	bus.effect_requested.connect(func(kind: StringName, payload: Dictionary) -> void:
		effects.append({"kind": kind, "payload": payload}))
	bus.reduced_motion = true
	bus.reduced_flash = true
	t.ok(bus.request(&"impact", {"flash_scale": 1.0}), "effect request accepted")
	t.eq(effects.size(), 1, "effect routed once")
	t.eq(effects[0]["kind"], &"impact", "semantic kind preserved")
	t.near(float(effects[0]["payload"]["motion_scale"]), 0.0, 0.001,
			"reduced motion degrades animation")
	t.near(float(effects[0]["payload"]["flash_scale"]), 0.25, 0.001,
			"reduced flash caps intensity")
	bus.haptics_enabled = false
	t.ok(not bus.haptic(&"flip"), "disabled haptics suppress requests")
	bus.subtitles_enabled = false
	t.ok(not bus.subtitle("A line", &"manny"), "disabled subtitles suppress requests")


func _budget(t: TestCtx) -> void:
	var budget := PresentationBudget.new()
	t.ok(budget.register(&"lights", 8), "budget accepts the limit")
	t.ok(not budget.register(&"lights"), "budget rejects an overage")
	t.eq(budget.count(&"lights"), 9, "audit records the real overage")
	t.ok(not budget.within(&"lights"), "overage is visible")
	t.eq(int(budget.violations()[&"lights"]["limit"]), 8, "violation reports limit")
	budget.release(&"lights", 100)
	t.eq(budget.count(&"lights"), 0, "release clamps at zero")
	t.ok(budget.register(&"custom", 500), "unknown counters are observable but unbounded")
	budget.reset()
	t.eq(budget.count(&"custom"), 0, "reset clears accounting")


func _gameplay_feedback(t: TestCtx) -> void:
	var bus := EffectBus.new()
	var budget := PresentationBudget.new()
	var feedback := GameplayFeedback.new()
	feedback.configure(bus, budget, Presentation.safe)
	bus.reduced_motion = true
	bus.reduced_flash = true
	var body := Node2D.new()
	body.position = Vector2(31.0, 47.0)
	bus.request(&"impact", {"screen_position": body.position, "strength": 1200.0})
	var snap := feedback.snapshot()
	t.eq(int(snap["active_count"]), 1, "feedback renderer leases one pooled slot")
	var first: Dictionary = snap["active"][0]
	t.near(float(first["motion_scale"]), 0.0, 0.001,
			"pooled renderer honors reduced motion")
	t.near(float(first["flash_scale"]), 0.25, 0.001,
			"pooled renderer honors reduced flash")
	t.eq(body.position, Vector2(31.0, 47.0), "screen-space feedback does not mutate a source node")
	feedback.clear()
	t.eq(budget.count(&"emitters"), 0, "clearing feedback returns its whole emitter budget")

	bus.reduced_motion = false
	bus.reduced_flash = false
	for i in GameplayFeedback.MAX_EFFECTS:
		bus.request(&"mode", {"id": StringName("mode_%d" % i), "title": "MODE %d" % i})
	t.eq(feedback.active_count(), GameplayFeedback.MAX_EFFECTS,
			"feedback pool reaches its fixed capacity")
	t.eq(budget.count(&"emitters"), GameplayFeedback.MAX_EFFECTS,
			"every live slot owns exactly one budget token")
	bus.request(&"rank", {"rank": 3, "title": "CAPO"})
	t.eq(feedback.active_count(), GameplayFeedback.MAX_EFFECTS,
			"ceremony overflow cannot grow the pool")
	t.eq(int(feedback.snapshot()["dropped"]), 1, "ceremony overflow is observable")
	t.eq(budget.count(&"emitters"), GameplayFeedback.MAX_EFFECTS,
			"rejected allocation does not leak an over-limit count")
	feedback.clear()
	t.eq(budget.count(&"emitters"), 0, "pool teardown is idempotent")
	feedback.clear()
	t.eq(budget.count(&"emitters"), 0, "second teardown stays at zero")

	bus.haptic(&"jackpot", 2.0)
	var haptic: Dictionary = feedback.snapshot()["last_haptic"]
	t.eq(haptic.get("pattern", &""), &"jackpot", "semantic haptic reaches the actuator")
	t.near(float(haptic.get("strength", 0.0)), 1.0, 0.001, "haptic strength is clamped")
	var margins := Vector4(56.0, 112.0, 72.0, 80.0)
	var target := GameplayFeedback.destination_for(&"clean", Vector2(486.0, 864.0), margins)
	t.ok(target.x >= margins.x and target.x <= 486.0 - margins.z,
			"clean flight lands inside asymmetric horizontal safe bounds")
	t.ok(target.y >= margins.y and target.y <= 864.0 - margins.w,
			"clean flight lands inside asymmetric vertical safe bounds")
	body.free()
	feedback.free()


func _screen_transitions(t: TestCtx) -> void:
	t.eq(ScreenTransition.ritual_for(&"attract", &"roll_call"), &"shutter",
			"front door closes through the cabinet shutter")
	t.eq(ScreenTransition.ritual_for(&"night", &"count"), &"receipt",
			"night hands off through the Count receipt")
	t.eq(ScreenTransition.ritual_for(&"count", &"ledger"), &"dossier",
			"Ledger opens as a dossier")
	t.eq(ScreenTransition.caption_for(&"ledger"), "THE LEDGER",
			"transition captions use authored screen names")
	var was_reduced := Presentation.fx.reduced_motion
	Presentation.fx.reduced_motion = true
	var transition := ScreenTransition.new()
	transition.play_reveal(&"count", &"ledger")
	t.ok(transition.visible and transition.amount == 1.0,
			"reduced-motion handoff still installs an opaque input cover")
	t.eq(transition.mouse_filter, Control.MOUSE_FILTER_STOP,
			"transition cover blocks accidental taps")
	transition._finish_reveal()
	t.ok(not transition.visible and transition.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"transition reveal releases input")
	transition.free()
	Presentation.fx.reduced_motion = was_reduced

	var book_page := LedgerBlackBook.new()
	book_page.build(BlackBook.shared(), Prestige.shared())
	book_page.set_safe_margins(Vector4(56.0, 112.0, 72.0, 80.0))
	var buy: Button = null
	for child in book_page.get_children():
		if child is Button:
			buy = child as Button
			break
	t.ok(buy != null, "Black Book builds its purchase control")
	if buy != null:
		t.near(buy.offset_right, -108.0, 0.001,
				"Black Book BUY clears the rounded right edge")
		t.near(buy.offset_bottom, -102.0, 0.001,
				"Black Book BUY clears the rounded bottom edge")
	book_page.free()
