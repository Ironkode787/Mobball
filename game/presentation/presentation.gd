extends Node
## Process-wide presentation services. No physics or economy code depends on this node.

const GAMEPLAY_FEEDBACK := preload("res://game/presentation/gameplay_feedback.gd")
const SUBTITLE_LAYER := preload("res://game/presentation/subtitle_layer.gd")

const PHASE_ONE_ART := {
	&"table.backglass.eastport": preload("res://assets/art/eastport/backglass.png"),
	&"ui.count_room_plate": preload("res://assets/art/eastport/count_room.png"),
	&"prop.trash_can": preload("res://assets/art/eastport/trash_can_bumper.png"),
	&"prop.bicycle_spinner": preload("res://assets/art/eastport/bicycle_spinner.png"),
	&"prop.payphone_bank": preload("res://assets/art/eastport/payphone.png"),
	&"ui.job_board": preload("res://assets/art/eastport/job_board.png"),
	&"front.laundromat": preload("res://assets/art/eastport/laundromat.png"),
	&"front.pizzeria": preload("res://assets/art/eastport/pizzeria.png"),
	&"front.pawn": preload("res://assets/art/eastport/pawn_shop.png"),
	&"mugshot.starter_01": preload("res://assets/art/portraits/starter_01.png"),
	&"mugshot.starter_02": preload("res://assets/art/portraits/starter_02.png"),
	&"mugshot.starter_03": preload("res://assets/art/portraits/starter_03.png"),
	&"mugshot.starter_04": preload("res://assets/art/portraits/starter_04.png"),
}

var theme := PresentationTheme.defaults()
var city := CitySkin.eastport()
var art := ArtCatalog.new()
var safe := PresentationSafeArea.new()
var fx := EffectBus.new()
var budget := PresentationBudget.new()
var settings := PresentationSettings.new()
var feedback_layer: CanvasLayer = null
var feedback: Control = null
var subtitle_layer: CanvasLayer = null
var subtitles: Control = null

var _last_impact_position := Vector2(-1.0, -1.0)
var _mode_active: Dictionary = {}
var _last_boss_key := ""


func _init() -> void:
	_register_phase_one_art()


func _ready() -> void:
	safe.name = "SafeArea"
	fx.name = "EffectBus"
	budget.name = "Budget"
	add_child(safe)
	add_child(fx)
	add_child(budget)
	settings.load_into(fx)
	feedback_layer = CanvasLayer.new()
	feedback_layer.name = "GameplayFeedbackLayer"
	feedback_layer.layer = 50
	add_child(feedback_layer)
	feedback = GAMEPLAY_FEEDBACK.new()
	feedback.name = "GameplayFeedback"
	feedback.configure(fx, budget, safe)
	feedback_layer.add_child(feedback)
	subtitle_layer = CanvasLayer.new()
	subtitle_layer.name = "SubtitleLayer"
	subtitle_layer.layer = 70
	add_child(subtitle_layer)
	subtitles = SUBTITLE_LAYER.new()
	subtitles.name = "Subtitles"
	subtitles.configure(fx, safe)
	subtitle_layer.add_child(subtitles)
	_connect_gameplay_events()


func _register_phase_one_art() -> void:
	for id: StringName in PHASE_ONE_ART:
		art.register(id, PHASE_ONE_ART[id] as Texture2D)


func set_city(next: CitySkin) -> void:
	if next != null:
		city = next


func _connect_gameplay_events() -> void:
	Events.switch_hit.connect(func(id: StringName, ball: Node2D, strength: float) -> void:
		_last_impact_position = _screen_position(ball)
		fx.request(&"impact", {"id": id, "strength": strength,
				"screen_position": _last_impact_position})
		fx.haptic(&"impact", clampf(strength / 1800.0, 0.24, 0.72)))
	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		if group != &"idle":
			fx.request(&"currency", {"currency": &"dirty", "amount": amount, "group": group,
					"screen_position": _effect_source()}))
	Events.laundered.connect(func(amount: BigMoney) -> void:
		fx.request(&"currency", {"currency": &"clean", "amount": amount,
				"screen_position": _effect_source()})
		fx.request(&"launder", {"amount": amount})
		fx.haptic(&"launder", 0.46))
	Events.clean_earned.connect(func(amount: BigMoney, source: StringName) -> void:
		fx.request(&"currency", {"currency": &"clean", "amount": amount, "source": source,
				"screen_position": _effect_source()}))
	Events.combo_changed.connect(func(count: int) -> void:
		fx.request(&"combo", {"count": count})
		if count >= 2:
			fx.haptic(&"combo", clampf(0.35 + float(count) * 0.11, 0.0, 0.88)))
	Events.rank_changed.connect(func(rank: int) -> void:
		if Game.state == &"night":
			fx.request(&"rank", {"rank": rank, "title": Headlines.rank_title(rank)})
			fx.haptic(&"rank", 0.88))
	Events.upgrade_purchased.connect(func(id: String, level: int) -> void:
		if level != 1:
			return
		var definition := Upgrades.shared().def(id)
		var specialist: Dictionary = definition.get("specialist", {})
		var speaker := StringName(String(specialist.get("id", "")))
		if not speaker.is_empty() and AudioDirector.SPECIALISTS.has(String(speaker)):
			AudioDirector.say(speaker, &"greeting"))
	Events.ball_drained.connect(func(ball: Node2D) -> void:
		var at := _screen_position(ball)
		fx.request(&"drain", {"screen_position": at})
		fx.haptic(&"drain", 0.78))
	Events.guy_pinched.connect(func(guy: Dictionary) -> void:
		fx.request(&"pinch", {"name": _guy_name(guy)})
		fx.haptic(&"pinch", 0.82))
	Events.guy_bailed.connect(func(guy: Dictionary) -> void:
		fx.request(&"bail", {"name": _guy_name(guy)})
		fx.haptic(&"bail", 0.52))
	Events.jackpot.connect(func(source: StringName, amount: BigMoney, clean: bool) -> void:
		fx.request(&"jackpot", {"source": source, "amount": amount, "clean": clean})
		fx.haptic(&"jackpot", 1.0))
	Events.raid_started.connect(func() -> void:
		fx.request(&"mode", {"id": &"raid", "title": "RAID IN PROGRESS", "active": true})
		fx.haptic(&"mode", 0.88))
	Events.raid_ended.connect(func(survived: bool) -> void:
		fx.request(&"mode", {"id": &"raid", "title": "RAID SURVIVED" if survived \
				else "RAID TOOK THE NIGHT", "active": false, "survived": survived}))
	Events.tilted.connect(func() -> void:
		fx.request(&"mode", {"id": &"tilt", "title": "TILT", "active": true})
		fx.haptic(&"drain", 0.82))
	Events.tilt_warning.connect(func(count: int, max_count: int) -> void:
		fx.request(&"warning", {"title": "INSPECTOR WARNING  %d/%d" % [count, max_count]})
		fx.haptic(&"warning", 0.58))
	Game.heat.band_changed.connect(func(band: int) -> void:
		if band >= 3:
			fx.request(&"warning", {"title": "HEAT IS CLIMBING"})
			fx.haptic(&"warning", 0.66))
	Game.meeting_changed.connect(func(active: bool, _lit: bool) -> void:
		_on_mode_state(&"meeting", "FAMILY MEETING", {"active": active}))
	Game.smuggling_changed.connect(func(state: Dictionary) -> void:
		_on_mode_state(&"smuggling", "SMUGGLING RUN", state))
	Game.heist_changed.connect(func(state: Dictionary) -> void:
		_on_mode_state(&"heist", "HEIST IN PROGRESS", state))
	Game.empire_changed.connect(func(state: Dictionary) -> void:
		_on_mode_state(&"empire", "EMPIRE MODE", state))
	Game.sitdown_changed.connect(func(active: bool, _time_left: float) -> void:
		_on_mode_state(&"sitdown", "THE SIT-DOWN", {"active": active}))
	Game.boss_changed.connect(_on_boss_changed)
	Game.state_changed.connect(func(state: StringName) -> void:
		if state != &"night":
			_mode_active.clear()
			_last_boss_key = ""
			_last_impact_position = Vector2(-1.0, -1.0)
			if feedback != null:
				feedback.call("clear"))


func _screen_position(node: Node2D) -> Vector2:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return _effect_source()
	var viewport := node.get_viewport()
	if viewport == null:
		return _effect_source()
	return viewport.get_canvas_transform() * node.global_position


func _effect_source() -> Vector2:
	if _last_impact_position.x >= 0.0 and _last_impact_position.y >= 0.0:
		return _last_impact_position
	var viewport := get_viewport()
	return viewport.get_visible_rect().size * Vector2(0.5, 0.56) if viewport != null \
			else Vector2(540.0, 1080.0)


func _guy_name(guy: Dictionary) -> String:
	var name := String(guy.get("name", ""))
	return name if not name.is_empty() else "A GUY"


func _on_mode_state(id: StringName, title: String, state: Dictionary) -> void:
	var active := bool(state.get("active", false))
	var was_active := bool(_mode_active.get(id, false))
	_mode_active[id] = active
	if active and not was_active:
		fx.request(&"mode", {"id": id, "title": title, "active": true})
		fx.haptic(&"mode", 0.72)


func _on_boss_changed(state: Dictionary) -> void:
	var active := bool(state.get("active", false))
	if not active:
		_last_boss_key = ""
		if bool(state.get("won", false)):
			fx.request(&"boss", {"name": state.get("name", "THE BOSS"), "active": false,
					"won": true, "title": "BOSS DOWN"})
			fx.haptic(&"boss", 1.0)
		return
	var key := "%s:%d" % [String(state.get("id", "boss")), int(state.get("phase", 1))]
	if key == _last_boss_key:
		return
	_last_boss_key = key
	fx.request(&"boss", state)
	fx.haptic(&"boss", 0.92)
