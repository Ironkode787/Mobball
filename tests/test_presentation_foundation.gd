extends RefCounted


func run(t: TestCtx) -> void:
	_theme_and_city(t)
	_art_catalog(t)
	_phase_one_assets(t)
	_effect_bus(t)
	_budget(t)


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
