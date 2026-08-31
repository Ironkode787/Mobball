extends RefCounted


func run(t: TestCtx) -> void:
	_state_vocabulary(t)
	_modifier_vocabulary(t)
	_lamp_contract(t)
	_feedback_contract(t)
	_feedback_pool_metadata(t)
	_reduced_modes(t)


func _state_vocabulary(t: TestCtx) -> void:
	var expected: Array[StringName] = [
		&"idle", &"armed", &"active", &"completed", &"disabled", &"danger",
	]
	t.eq(TableVisualState.STATE_NAMES, expected, "C2 exposes exactly six canonical states")
	var marks: Array[StringName] = []
	var patterns: Array[StringName] = []
	for state in expected.size():
		var token := TableVisualState.state_token(state)
		t.eq(token["state"], expected[state], "state token keeps its canonical name")
		t.ok(not String(token["mark"]).is_empty(), "state has a non-color mark")
		t.ok(not String(token["pattern"]).is_empty(), "state has a non-color pattern")
		t.ok(PresentationTheme.MATERIAL_ROLES.has(token["material"]),
			"state selects a canonical material role")
		t.eq(token["grayscale_cue"], token["pattern"], "grayscale cue is explicit")
		marks.append(token["mark"])
		patterns.append(token["pattern"])
	t.eq(marks.size(), marks.duplicate().size(), "each state has a deterministic mark")
	t.eq(patterns.size(), patterns.duplicate().size(), "each state has a deterministic pattern")
	t.eq(TableVisualState.state_from("ACTIVE"), TableVisualState.VisualState.ACTIVE,
		"state lookup is case-insensitive")
	t.eq(TableVisualState.state_from(&"not-a-state"), TableVisualState.VisualState.IDLE,
		"unknown state fails closed to idle")


func _modifier_vocabulary(t: TestCtx) -> void:
	var expected: Array[StringName] = [
		&"pulse", &"flash", &"cooldown", &"telegraph", &"held", &"marked", &"down",
		&"dead", &"jam", &"moving", &"parked", &"raid_phase", &"boss_phase",
	]
	t.eq(TableVisualState.LOCAL_MODIFIERS, expected, "local modifiers are canonical")
	var mods := TableVisualState.modifiers([&"held", &"boss_phase", &"unknown"])
	t.ok(bool(mods[&"held"]) and bool(mods[&"boss_phase"]),
		"known local modifiers survive normalization")
	t.ok(not mods.has(&"unknown"), "unknown local modifiers are ignored")
	t.eq(TableVisualState.state_mark(TableVisualState.VisualState.DISABLED, {&"cooldown": true}),
		&"cooldown_clock", "cooldown has a distinct mark from dormant disabled")
	t.eq(TableVisualState.state_pattern(TableVisualState.VisualState.ACTIVE, {&"held": true}),
		&"held_ring", "held is a local active pattern")
	t.eq(TableVisualState.state_mark(TableVisualState.VisualState.DANGER, {&"jam": true}),
		&"jam_alert", "jam is a local danger mark")


func _lamp_contract(t: TestCtx) -> void:
	t.eq(TableVisualState.LAMP_CHANNEL_NAMES, [
		&"ambient_attract", &"current_objective", &"recent_hit", &"mode_start", &"jackpot",
		&"cooldown",
	], "lamp channels are canonical")
	t.ok(TableVisualState.lamp_priority(&"jackpot") > TableVisualState.lamp_priority(&"danger"),
		"ceremony outranks danger")
	t.ok(TableVisualState.lamp_priority(&"danger") > TableVisualState.lamp_priority(&"recent_hit"),
		"danger outranks recent hit")
	t.ok(TableVisualState.lamp_priority(&"recent_hit") >
			TableVisualState.lamp_priority(&"current_objective"), "recent hit outranks objective")
	t.ok(TableVisualState.lamp_priority(&"current_objective") >
			TableVisualState.lamp_priority(&"ambient_attract"), "objective outranks ambient")
	t.ok(TableVisualState.lamp_is_invitation(&"current_objective",
			TableVisualState.VisualState.ARMED), "armed objective is an invitation")
	t.ok(not TableVisualState.lamp_is_invitation(&"current_objective",
			TableVisualState.VisualState.DISABLED, {&"cooldown": true}),
			"disabled cooldown suppresses invitation")
	t.eq(TableVisualState.lamp_priority(&"current_objective",
			TableVisualState.VisualState.DISABLED), 0, "disabled suppresses objective lamp")


func _feedback_contract(t: TestCtx) -> void:
	var expected := {
		&"impact": &"micro_hit", &"currency": &"reward", &"combo": &"reward",
		&"launder": &"reward", &"drain": &"consequence", &"pinch": &"consequence",
		&"bail": &"consequence", &"warning": &"consequence", &"mode": &"ceremony",
		&"jackpot": &"ceremony", &"rank": &"ceremony", &"boss": &"ceremony",
	}
	for kind: StringName in expected:
		t.eq(TableVisualState.feedback_level_name(TableVisualState.feedback_level(kind)),
			expected[kind], "%s has its canonical feedback level" % kind)
	var source := Vector2(400.0, 300.0)
	var viewport := Vector2(486.0, 864.0)
	var margins := Vector4(56.0, 112.0, 72.0, 80.0)
	var micro := TableVisualState.feedback_destination(TableVisualState.FeedbackLevel.MICRO_HIT,
			source, viewport, margins)
	var consequence := TableVisualState.feedback_destination(
			TableVisualState.FeedbackLevel.CONSEQUENCE, source, viewport, margins)
	var ceremony := TableVisualState.feedback_destination(TableVisualState.FeedbackLevel.CEREMONY,
			source, viewport, margins)
	t.ok(micro.x >= margins.x and micro.x <= viewport.x - margins.z and micro.y >= margins.y
			and micro.y <= viewport.y - margins.w, "micro hit is safe-clamped")
	t.ok(consequence.x >= margins.x and consequence.x <= viewport.x - margins.z
			and consequence.y >= margins.y and consequence.y <= viewport.y - margins.w,
			"consequence destination is safe-clamped")
	t.eq(ceremony, Vector2((margins.x + viewport.x - margins.z) * 0.5,
			(margins.y + viewport.y - margins.w) * 0.5), "ceremony owns safe center")


func _reduced_modes(t: TestCtx) -> void:
	var normal := TableVisualState.reduced_effects(false, false)
	t.eq(normal["motion_scale"], 1.0, "normal motion scale")
	t.eq(normal["flash_scale"], 1.0, "normal flash scale")
	t.ok(bool(normal["travel"]) and bool(normal["rays"]) and bool(normal["chase"]),
		"normal effects retain causal motion")
	var reduced := TableVisualState.reduced_effects(true, true)
	t.eq(reduced["motion_scale"], 0.0, "reduced motion removes travel")
	t.eq(reduced["flash_scale"], 0.25, "reduced flash caps opacity")
	t.ok(not bool(reduced["travel"]) and not bool(reduced["scale"]) and not bool(reduced["rays"]),
		"reduced motion removes motion-only decoration")
	t.ok(not bool(reduced["chase"]) and not bool(reduced["telegraph"]),
		"reduced flash freezes fast chase and telegraph")


func _feedback_pool_metadata(t: TestCtx) -> void:
	var bus := EffectBus.new()
	var budget := PresentationBudget.new()
	var feedback := GameplayFeedback.new()
	feedback.configure(bus, budget, Presentation.safe)
	var source := Vector2(100.0, 120.0)
	bus.request(&"drain", {"screen_position": source})
	var active: Dictionary = feedback.snapshot()["active"][0]
	t.eq(active["level"], &"consequence", "pooled slot exposes its feedback level")
	t.eq(active["state"], &"danger", "pooled slot exposes its visual state")
	t.eq(active["pattern"], &"telegraph_hatch", "pooled consequence keeps a non-color cue")
	t.eq(active["source"], source, "pooled slot keeps the immutable source position")
	feedback.clear()
	t.eq(budget.count(&"emitters"), 0, "metadata fixture releases its budget token")
	feedback.free()
