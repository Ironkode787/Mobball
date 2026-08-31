extends RefCounted


func run(t: TestCtx) -> void:
	_theme_and_city(t)
	_art_catalog(t)
	_phase_one_assets(t)
	_effect_bus(t)
	_presentation_settings(t)
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
	_semantic_tokens(theme, t)
	var city := CitySkin.eastport()
	t.eq(city.id, &"eastport", "default city skin")
	t.eq(city.felt, Feel.COL_FELT, "city skin begins without a visual jump")
	_city_tokens(city, t)


func _semantic_tokens(theme: PresentationTheme, t: TestCtx) -> void:
	var expected_type_roles: Array[StringName] = [
		&"hero", &"title", &"section", &"primary_value", &"body", &"caption", &"metadata",
		&"button", &"micro",
	]
	t.eq(PresentationTheme.TYPE_ROLES, expected_type_roles, "semantic type role set is complete")
	for role: StringName in expected_type_roles:
		var token := theme.typography_for(role)
		t.eq(token.get("role", &""), role, "%s reports its canonical role" % role)
		t.ok(token.get("font", null) != null, "%s has a font token" % role)
		t.ok(int(token.get("size", 0)) > 0, "%s has a positive size" % role)
		t.ok(float(token.get("line_height", 0.0)) > 0.0, "%s has line-height metadata" % role)
		t.ok(float(token.get("tracking", -1.0)) >= 0.0, "%s has tracking metadata" % role)
		t.ok(float(token.get("max_width", 0.0)) >= float(token.get("size", 0)),
				"%s has a usable max line width" % role)
		t.ok(token.has("tabular_numbers"), "%s has tabular-number metadata" % role)
		t.eq(token.keys().size(), 7, "%s exposes one canonical metadata key per value" % role)
	t.eq(theme.size_for(&"display"), 78, "legacy display size remains stable")
	t.eq(theme.size_for(&"headline"), 56, "legacy headline size remains stable")
	t.eq(theme.size_for(&"title"), 44, "legacy title size remains stable")
	t.eq(theme.size_for(&"annotation"), 28, "legacy annotation size remains stable")
	t.eq(theme.font_for(&"title"), theme.body_font, "legacy title font fallback remains stable")
	t.eq(theme.typography_for(&"title").get("font"), theme.headline_font,
			"semantic title resolves its canonical display font")
	t.eq(theme.font_for(&"annotation_bold"), PresentationTheme.FONT_COURIER_BOLD,
			"legacy bold annotation font remains stable")
	t.eq(theme.space_xs, 8.0, "legacy extra-small spacing remains stable")
	t.eq(theme.space_sm, 14.0, "legacy small spacing remains stable")
	t.eq(theme.space_md, 28.0, "legacy medium spacing remains stable")
	t.eq(theme.space_lg, 48.0, "legacy large spacing remains stable")
	t.eq(theme.touch_min, 96.0, "legacy touch minimum remains stable")
	var spacing := theme.spacing_tokens()
	var expected_spacing_roles: Array[StringName] = [
		&"space_4", &"space_8", &"space_12", &"space_16", &"space_24", &"space_32",
		&"space_40", &"space_48", &"space_64",
	]
	t.eq(PresentationTheme.SPACING_ROLES, expected_spacing_roles,
			"semantic spacing role set is complete")
	for role: StringName in expected_spacing_roles:
		var value := float(spacing.get(role, -1.0))
		t.ok(value > 0.0 and int(value) % 4 == 0, "%s follows the 4/8 spacing rhythm" % role)
		t.eq(value, theme.spacing_for(role), "%s collection uses the canonical lookup" % role)
	t.eq(theme.spacing_for(&"space_4"), 4.0, "4-point spacing token")
	t.eq(theme.spacing_for(&"space_8"), 8.0, "8-point spacing token")
	var legacy_xs := theme.space_xs
	theme.space_xs = 14.0
	t.eq(theme.spacing_for(&"space_8"), 8.0, "canonical 8-point spacing ignores legacy customization")
	theme.space_xs = legacy_xs
	var compact := theme.layout_profile(&"compact")
	var standard := theme.layout_profile(&"standard")
	t.eq(PresentationTheme.LAYOUT_PROFILES, [&"compact", &"standard"],
			"layout profile set is complete")
	t.eq(compact.get("id"), &"compact", "compact layout profile is canonical")
	t.eq(standard.get("id"), &"standard", "standard layout profile is canonical")
	t.ok(float(compact.get("content_width", 0.0)) > 0.0,
			"compact profile has a bounded content width")
	t.ok(float(standard.get("content_width", 0.0)) > float(compact.get("content_width", 0.0)),
			"standard profile has the wider content width")
	var compact_gutter: Vector4 = compact.get("safe_gutter", Vector4.ZERO)
	var standard_gutter: Vector4 = standard.get("safe_gutter", Vector4.ZERO)
	t.eq(theme.layout_profile(&"compact").get("safe_gutter"), compact_gutter,
			"compact profile exposes its canonical safe gutter")
	t.eq(theme.layout_profile(&"standard").get("content_width"),
			float(standard.get("content_width", 0.0)),
			"standard profile exposes its canonical content width")
	t.ok(compact_gutter.x > 0.0 and compact_gutter.y > 0.0 and compact_gutter.z > 0.0
			and compact_gutter.w > 0.0, "compact profile protects all safe edges")
	t.ok(standard_gutter.x > 0.0 and standard_gutter.y > 0.0 and standard_gutter.z > 0.0
			and standard_gutter.w > 0.0, "standard profile protects all safe edges")
	var expected_material_roles: Array[StringName] = [
		&"ink_glass", &"newsprint", &"aged_paper", &"cork", &"wood", &"brass", &"felt",
	]
	t.eq(PresentationTheme.MATERIAL_ROLES, expected_material_roles,
			"material role set is complete")
	for role: StringName in expected_material_roles:
		var material := theme.material_for(role)
		t.eq(material.keys().size(), 4, "%s material has one complete contract" % role)
		for key in [&"fill", &"border", &"shadow", &"opacity"]:
			t.ok(material.has(key), "%s material exposes %s" % [role, key])
	var expected_control_roles: Array[StringName] = [
		&"button", &"compact_button", &"toggle", &"slider", &"touch_target",
	]
	t.eq(PresentationTheme.CONTROL_ROLES, expected_control_roles,
			"control role set is complete")
	for role: StringName in expected_control_roles:
		var control := theme.control_for(role)
		t.ok(float(control.get("min_height", 0.0)) >= theme.touch_min,
				"%s control preserves the touch minimum" % role)
		t.eq(control.keys().size(), 6, "%s control has one height contract" % role)
		t.ok(control.get("padding", null) is Vector4, "%s control has typed padding" % role)
	var expected_surface_roles: Array[StringName] = [
		&"screen", &"panel", &"card", &"receipt", &"overlay", &"control",
	]
	t.eq(PresentationTheme.SURFACE_ROLES, expected_surface_roles,
			"surface role set is complete")
	for role: StringName in expected_surface_roles:
		var surface := theme.surface_for(role)
		var material_role: StringName = surface.get("material", &"")
		t.ok(PresentationTheme.MATERIAL_ROLES.has(material_role),
				"%s surface selects a known material" % role)
		t.eq(surface.keys().size(), 5, "%s surface has one complete contract" % role)
	var neutral_fill = theme.material_for(&"ink_glass").get("fill", Color.TRANSPARENT)
	t.ok(neutral_fill != theme.dirty and neutral_fill != theme.clean and neutral_fill != theme.heat
			and neutral_fill != theme.police, "neutral materials do not repurpose state colors")
	for alias in [&"type_for", &"type_token", &"space_for", &"spacing_token", &"layout_for",
			&"layout_profile_for", &"profile_for", &"safe_gutter_for", &"content_width_for",
			&"line_height_for", &"tracking_for", &"max_width_for", &"tabular_numbers_for",
			&"material_token", &"control_token", &"surface_token"]:
		t.ok(not theme.has_method(alias), "%s is not a parallel token lookup" % alias)


func _city_tokens(city: CitySkin, t: TestCtx) -> void:
	var expected_roles: Array[StringName] = [
		&"felt", &"wood", &"wood_dark", &"wood_edge", &"brass", &"paper",
		&"aged_paper", &"cork", &"ink_glass", &"earned_neon",
	]
	t.eq(CitySkin.AMBIENT_MATERIAL_ROLES, expected_roles, "city ambient role set is complete")
	var ambient := city.ambient_materials()
	t.eq(ambient.keys().size(), expected_roles.size(), "city ambient map has no omitted roles")
	for role: StringName in expected_roles:
		t.eq(ambient.get(role), city.material_for(role), "%s city lookup is canonical" % role)
		t.ok(ambient.get(role, Color.TRANSPARENT) != Color.TRANSPARENT,
				"%s city material is non-empty" % role)
	for reserved in [&"dirty", &"clean", &"heat", &"police"]:
		t.eq(city.material_for(reserved), Color.TRANSPARENT,
				"city skin cannot redefine reserved %s" % reserved)


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
	t.near(bus.motion_scale(), 0.0, 0.001, "reduced motion exposes one shared policy scale")
	t.near(bus.flash_scale(), 0.25, 0.001, "reduced flash exposes one shared policy scale")


func _presentation_settings(t: TestCtx) -> void:
	var path := "user://phase4_presentation_test.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var bus := EffectBus.new()
	var settings := PresentationSettings.new(path)
	t.ok(settings.set_toggle(&"reduced_motion", true, bus),
			"accessibility toggle persists through ConfigFile")
	t.ok(settings.set_toggle(&"reduced_flash", true, bus), "reduced flash persists")
	t.ok(settings.set_toggle(&"haptics_enabled", false, bus), "haptic choice persists")
	t.ok(settings.set_toggle(&"subtitles_enabled", false, bus), "subtitle choice persists")
	t.ok(bus.reduced_motion and bus.reduced_flash, "saved sensory choices apply immediately")
	t.ok(not bus.haptics_enabled and not bus.subtitles_enabled,
			"saved channel choices apply immediately")
	var loaded := PresentationSettings.new(path)
	var loaded_bus := EffectBus.new()
	loaded.load_into(loaded_bus)
	t.eq(loaded.snapshot()["reduced_motion"], true, "reduced motion survives process restart")
	t.eq(loaded.snapshot()["subtitles_enabled"], false, "subtitles survive process restart")
	t.ok(not loaded.set_toggle(&"unknown", true, loaded_bus), "unknown settings fail closed")
	DirAccess.remove_absolute(path)


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
