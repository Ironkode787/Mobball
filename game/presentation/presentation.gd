extends Node
## Process-wide presentation services. No physics or economy code depends on this node.

const GAMEPLAY_FEEDBACK := preload("res://game/presentation/gameplay_feedback.gd")
const SUBTITLE_LAYER := preload("res://game/presentation/subtitle_layer.gd")
const TABLE_VISUAL_STATE := preload("res://game/presentation/table_visual_state.gd")

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
var _last_tail_state: Dictionary = {}
var _last_rico_phase_key := ""
var _rico_context_active := false
var _federal_pending := false
var _last_chairs_claimed := 0
var _chairs_all_seen := false
var _phone_ringing := false


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
		_request_effect(&"impact", {"id": id, "strength": strength,
				"screen_position": _last_impact_position}, &"switch_hit", {
				"haptic": {"pattern": &"impact", "strength": clampf(strength / 1800.0, 0.24, 0.72)}})
		fx.haptic(&"impact", clampf(strength / 1800.0, 0.24, 0.72)))
	Events.dirty_earned.connect(func(amount: BigMoney, group: StringName) -> void:
		if group != &"idle":
			_request_effect(&"currency", {"currency": &"dirty", "amount": amount, "group": group,
					"screen_position": _effect_source()}, &"dirty_earned", {
					"destination_class": &"hud_dirty", "haptic": {}}))
	Events.laundered.connect(func(amount: BigMoney) -> void:
		_request_effect(&"currency", {"currency": &"clean", "amount": amount,
				"screen_position": _effect_source()}, &"laundered", {"destination_class": &"hud_clean", "haptic": {}})
		_request_effect(&"launder", {"amount": amount}, &"laundered", {
				"destination_class": &"ceremony", "haptic": {"pattern": &"launder", "strength": 0.46}})
		fx.haptic(&"launder", 0.46))
	Events.clean_earned.connect(func(amount: BigMoney, source: StringName) -> void:
		_request_effect(&"currency", {"currency": &"clean", "amount": amount, "source": source,
				"screen_position": _effect_source()}, &"clean_earned", {
				"destination_class": &"hud_clean", "haptic": {}}))
	Events.combo_changed.connect(func(count: int) -> void:
		_request_effect(&"combo", {"count": count}, &"combo_changed", {
				"destination_class": &"reward", "haptic": {"pattern": &"combo",
				"strength": clampf(0.35 + float(count) * 0.11, 0.0, 0.88)}})
		if count >= 2:
			fx.haptic(&"combo", clampf(0.35 + float(count) * 0.11, 0.0, 0.88)))
	Events.rank_changed.connect(func(rank: int) -> void:
		if Game.state == &"night":
			_request_effect(&"rank", {"rank": rank, "title": Headlines.rank_title(rank)}, &"rank_changed", {
					"destination_class": &"ceremony", "haptic": {"pattern": &"rank", "strength": 0.88}})
			fx.haptic(&"rank", 0.88))
	Events.upgrade_purchased.connect(func(id: String, level: int) -> void:
		if level != 1:
			return
		var definition := Upgrades.shared().def(id)
		var specialist: Dictionary = definition.get("specialist", {})
		var speaker := StringName(str(specialist.get("id", "")))
		if not speaker.is_empty() and AudioDirector.SPECIALISTS.has(str(speaker)):
			AudioDirector.say(speaker, &"greeting"))
	Events.ball_drained.connect(func(ball: Node2D) -> void:
		var at := _screen_position(ball)
		_request_effect(&"drain", {"screen_position": at}, &"ball_drained", {
				"destination_class": &"consequence", "haptic": {"pattern": &"drain", "strength": 0.78}})
		fx.haptic(&"drain", 0.78))
	Events.guy_pinched.connect(func(guy: Dictionary) -> void:
		_request_effect(&"pinch", {"name": _guy_name(guy)}, &"guy_pinched", {
				"destination_class": &"consequence", "haptic": {"pattern": &"pinch", "strength": 0.82}})
		fx.haptic(&"pinch", 0.82))
	Events.guy_bailed.connect(func(guy: Dictionary) -> void:
		_request_effect(&"bail", {"name": _guy_name(guy)}, &"guy_bailed", {
				"destination_class": &"consequence", "haptic": {"pattern": &"bail", "strength": 0.52}})
		fx.haptic(&"bail", 0.52))
	Events.jackpot.connect(func(source: StringName, amount: BigMoney, clean: bool) -> void:
		_request_effect(&"jackpot", {"source": source, "amount": amount, "clean": clean}, &"jackpot", {
				"destination_class": &"ceremony", "haptic": {"pattern": &"jackpot", "strength": 1.0}})
		fx.haptic(&"jackpot", 1.0))
	Events.raid_started.connect(func() -> void:
		# Rico raises the same core event but has its own federal phase contract. The
		# pending latch is the only source-backed discriminator available at this edge.
		if Game.rico_pending():
			_rico_context_active = true
			return
		_request_effect(&"mode", {"id": &"raid", "title": "RAID IN PROGRESS", "active": true}, &"raid_started", {
				"destination_class": &"ceremony", "haptic": {"pattern": &"mode", "strength": 0.88}})
		fx.haptic(&"mode", 0.88))
	Events.raid_ended.connect(func(survived: bool) -> void:
		if _rico_context_active:
			_request_effect(&"mode", {"id": &"rico_result", "title": "RICO SURVIVED" if survived \
					else "RICO LOST", "active": false, "survived": survived}, &"rico_finished", {
					"_feedback_level": &"reward" if survived else &"consequence",
					"_feedback_state": &"completed", "destination_class": &"ceremony",
					"_feedback_priority": 3 if survived else 2, "haptic": {}})
			_rico_context_active = false
			_last_rico_phase_key = ""
			return
		_request_effect(&"mode", {"id": &"raid", "title": "RAID SURVIVED" if survived \
				else "RAID TOOK THE NIGHT", "active": false, "survived": survived}, &"raid_ended", {
				"destination_class": &"ceremony", "haptic": {}}))
	Events.tilted.connect(func() -> void:
		_request_effect(&"mode", {"id": &"tilt", "title": "TILT", "active": true}, &"tilted", {
				"destination_class": &"ceremony", "haptic": {"pattern": &"drain", "strength": 0.82}})
		fx.haptic(&"drain", 0.82))
	Events.tilt_warning.connect(func(count: int, max_count: int) -> void:
		_request_effect(&"warning", {"title": "INSPECTOR WARNING  %d/%d" % [count, max_count]}, &"tilt_warning", {
				"destination_class": &"consequence", "haptic": {"pattern": &"warning", "strength": 0.58}})
		fx.haptic(&"warning", 0.58))
	Game.heat.band_changed.connect(func(band: int) -> void:
		if band >= 3:
			_request_effect(&"warning", {"title": "HEAT IS CLIMBING", "band": band}, &"heat_band_changed", {
					"destination_class": &"consequence", "haptic": {"pattern": &"warning", "strength": 0.66}})
			fx.haptic(&"warning", 0.66))
	Game.meeting_changed.connect(func(active: bool, _lit: bool) -> void:
		_on_mode_state(&"meeting", "FAMILY MEETING", {"active": active}))
	Game.smuggling_changed.connect(func(state: Dictionary) -> void:
		_on_smuggling_state(state))
	Game.heist_changed.connect(func(state: Dictionary) -> void:
		_on_heist_state(state))
	Game.empire_changed.connect(func(state: Dictionary) -> void:
		_on_empire_state(state))
	Game.sitdown_changed.connect(func(active: bool, _time_left: float) -> void:
		_on_sitdown_state(active))
	Game.casino_resolved.connect(_on_casino_resolved)
	Game.wire_drawn.connect(_on_wire_drawn)
	Game.collection_changed.connect(_on_collection_changed)
	Game.chairs_changed.connect(_on_chairs_changed)
	Game.election_changed.connect(_on_election_changed)
	Game.federal_changed.connect(_on_federal_changed)
	Game.briefcase_opened.connect(_on_briefcase_opened)
	Game.phone_changed.connect(_on_phone_changed)
	Game.rat_changed.connect(_on_rat_changed)
	Game.boss_changed.connect(_on_boss_changed)
	Game.state_changed.connect(func(state: StringName) -> void:
		if state != &"night":
			_mode_active.clear()
			_last_boss_key = ""
			_last_tail_state.clear()
			_last_rico_phase_key = ""
			_rico_context_active = false
			_federal_pending = false
			_last_chairs_claimed = 0
			_chairs_all_seen = false
			_phone_ringing = false
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
	var name := str(guy.get("name", ""))
	return name if not name.is_empty() else "A GUY"


func _on_mode_state(id: StringName, title: String, state: Dictionary) -> void:
	var active := bool(state.get("active", false))
	var was_active := bool(_mode_active.get(id, false))
	_mode_active[id] = active
	if active and not was_active:
		_request_effect(&"mode", {"id": id, "title": title, "active": true}, id, {
				"destination_class": &"ceremony", "haptic": {"pattern": &"mode", "strength": 0.72}})
		fx.haptic(&"mode", 0.72)


func _on_boss_changed(state: Dictionary) -> void:
	var active := bool(state.get("active", false))
	if not active:
		_last_boss_key = ""
		if bool(state.get("won", false)):
			_request_effect(&"boss", {"name": state.get("name", "THE BOSS"), "active": false,
					"won": true, "title": "BOSS DOWN"}, &"boss_finished", {
					"_feedback_level": &"ceremony", "_feedback_state": &"completed",
					"destination_class": &"ceremony", "haptic": {"pattern": &"boss", "strength": 1.0}})
			fx.haptic(&"boss", 1.0)
		elif state.has("won"):
			_request_effect(&"boss", {"name": state.get("name", "THE BOSS"), "active": false,
					"won": false, "title": "BOSS ESCAPED"}, &"boss_finished", {
					"_feedback_level": &"ceremony", "_feedback_state": &"completed",
					"destination_class": &"ceremony", "haptic": {}})
		return
	var key := "%s:%d" % [str(state.get("id", "boss")), int(state.get("phase", 1))]
	if key == _last_boss_key:
		return
	_last_boss_key = key
	_request_effect(&"boss", state, &"boss_changed", {
				"destination_class": &"ceremony", "suppression": &"same_key",
				"haptic": {"pattern": &"boss", "strength": 0.92}})
	fx.haptic(&"boss", 0.92)


func _on_smuggling_state(state: Dictionary) -> void:
	var previous: Dictionary = _last_tail_state.get("smuggling", {})
	var active := bool(state.get("active", false))
	var was_active := bool(previous.get("active", false))
	var cleared := int(state.get("cleared", 0))
	var old_cleared := int(previous.get("cleared", 0))
	if active and not was_active:
		_request_effect(&"mode", {"id": &"smuggling", "title": "SMUGGLING RUN", "active": true},
				&"smuggling_started", {"destination_class": &"ceremony",
				"haptic": {"pattern": &"mode", "strength": 0.72}})
		fx.haptic(&"mode", 0.72)
	elif active and (cleared > old_cleared or bool(state.get("hot", false)) and \
				not bool(previous.get("hot", false))):
		_request_effect(&"mode", {"id": &"smuggling_progress", "title": "SMUGGLING %d/%d" % [cleared,
					SmugglingRun.STACKS], "active": true, "state": state.duplicate(true)},
				&"smuggling_changed", {"_feedback_level": &"reward", "_feedback_state": &"active",
				"destination_class": &"source", "haptic": {}})
	elif bool(state.get("shipped", false)):
		_request_effect(&"mode", {"id": &"smuggling_result", "title": "SMUGGLING SHIPPED",
				"active": false, "hot": bool(state.get("hot", false))}, &"smuggling_shipment", {
				"_feedback_level": &"reward", "_feedback_state": &"completed",
				"destination_class": &"ceremony", "haptic": {}})
	elif was_active and not active:
		_request_effect(&"mode", {"id": &"smuggling_result", "title": "SMUGGLING LAPSED",
				"active": false}, &"smuggling_lapsed", {"_feedback_level": &"consequence",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})
	_last_tail_state["smuggling"] = state.duplicate(true)
	_mode_active[&"smuggling"] = active


func _on_empire_state(state: Dictionary) -> void:
	var previous: Dictionary = _last_tail_state.get("empire", {})
	var active := bool(state.get("active", false))
	var was_active := bool(previous.get("active", false))
	var leg := int(state.get("leg", 0))
	var old_leg := int(previous.get("leg", 0))
	var paid: Variant = state.get("paid", null)
	if active and not was_active:
		_request_effect(&"mode", {"id": &"empire", "title": "EMPIRE MODE", "active": true},
				&"empire_started", {"destination_class": &"ceremony",
				"haptic": {"pattern": &"mode", "strength": 0.72}})
		fx.haptic(&"mode", 0.72)
	elif not active and paid != null:
		_request_effect(&"mode", {"id": &"empire_result", "title": "EMPIRE DIVIDEND", "active": false,
				"paid": paid}, &"empire_finished", {"_feedback_level": &"reward",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})
	elif not active and leg > 0 and leg != old_leg:
		_request_effect(&"mode", {"id": &"empire_leg", "title": "EMPIRE LEG %d/%d" % [leg,
					int(state.get("legs", 4))], "active": true, "leg": leg}, &"empire_leg", {
				"_feedback_level": &"reward", "_feedback_state": &"active",
				"destination_class": &"source", "haptic": {}})
	_last_tail_state["empire"] = state.duplicate(true)
	_mode_active[&"empire"] = active


func _on_heist_state(state: Dictionary) -> void:
	var previous: Dictionary = _last_tail_state.get("heist", {})
	var active := bool(state.get("active", false))
	var was_active := bool(previous.get("active", false))
	if active and not was_active:
		_request_effect(&"mode", {"id": &"heist", "title": "HEIST IN PROGRESS", "active": true},
				&"heist_started", {"destination_class": &"ceremony",
				"haptic": {"pattern": &"mode", "strength": 0.72}})
		fx.haptic(&"mode", 0.72)
	elif active and (int(state.get("beat", 0)) != int(previous.get("beat", 0)) or \
				int(state.get("hits", 0)) != int(previous.get("hits", 0)) or \
				int(state.get("blown", 0)) != int(previous.get("blown", 0))):
		var blown := int(state.get("blown", 0))
		var improved := int(state.get("beat", 0)) != int(previous.get("beat", 0)) or \
				int(state.get("hits", 0)) > int(previous.get("hits", 0))
		_request_effect(&"mode", {"id": &"heist_progress", "title": "HEIST BEAT %d/%d" % [
					int(state.get("beat", 0)) + 1, int(state.get("beats", 0))], "active": true,
					"blown": blown}, &"heist_changed", {"_feedback_level": &"reward" if improved \
					else &"consequence", "_feedback_state": &"active", "destination_class": &"source",
					"haptic": {}})
	elif not active and state.has("result"):
		var result: Dictionary = state.get("result", {})
		var cleared := bool(result.get("cleared", false))
		_request_effect(&"mode", {"id": &"heist_result", "title": "HEIST CLEARED" if cleared \
				else "HEIST BLOWN", "active": false, "result": result.duplicate(true)},
				&"heist_finished", {"_feedback_level": &"reward" if cleared else &"consequence",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})
	_last_tail_state["heist"] = state.duplicate(true)
	_mode_active[&"heist"] = active


func _on_sitdown_state(active: bool) -> void:
	var previous := bool(_mode_active.get(&"sitdown", false))
	_mode_active[&"sitdown"] = active
	if active and not previous:
		_request_effect(&"mode", {"id": &"sitdown", "title": "THE SIT-DOWN", "active": true},
				&"sitdown_started", {"destination_class": &"ceremony",
				"haptic": {"pattern": &"mode", "strength": 0.72}})
		fx.haptic(&"mode", 0.72)
	elif previous and not active:
		_request_effect(&"mode", {"id": &"sitdown_result", "title": "SIT-DOWN EXPIRED",
				"active": false}, &"sitdown_expired", {"_feedback_level": &"consequence",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})


func _on_casino_resolved(result: Dictionary) -> void:
	if bool(result.get("jackpot", false)) or not bool(result.get("bet", false)):
		return
	var won: Variant = result.get("won", null)
	var has_win := won is BigMoney and (won as BigMoney).is_positive()
	var title := "CASINO WIN" if has_win else "CASINO LOSS"
	var payload := {"id": &"casino_result", "title": title, "active": false,
			"result": result.duplicate(true), "clean": bool(result.get("clean", false)),
			"comped": bool(result.get("comped", false)), "multiplier": float(result.get("multiplier", 1.0))}
	_request_effect(&"mode", payload, &"casino_resolved", {"_feedback_level": &"reward" if has_win \
			else &"consequence", "_feedback_state": &"completed", "destination_class": &"ceremony",
			"_feedback_priority": 1 if has_win else 2, "haptic": {}})
	if bool(result.get("cooler", false)):
		_request_effect(&"mode", {"id": &"casino_cooler", "title": "COOLER APOLOGY", "active": false,
				"result": result.duplicate(true)}, &"casino_cooler", {"_feedback_level": &"reward",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})


func _on_wire_drawn(result: Dictionary) -> void:
	var hit := StringName(result.get("hit", WireDraws.HIT_NONE))
	var won := hit != WireDraws.HIT_NONE
	var title := "WIRE EXACT" if hit == WireDraws.HIT_EXACT else "WIRE HIT" if won else "WIRE MISSED"
	_request_effect(&"mode", {"id": &"wire_result", "title": title, "active": false,
			"result": result.duplicate(true)}, &"wire_drawn", {"_feedback_level": &"reward" if won \
			else &"consequence", "_feedback_state": &"completed", "destination_class": &"source" \
			if won else &"ceremony", "_feedback_priority": 1 if won else 2, "haptic": {}})


func _on_collection_changed(active: bool, collected: int) -> void:
	var previous: Dictionary = _last_tail_state.get("collection", {})
	var was_active := bool(previous.get("active", false))
	var old_count := int(previous.get("collected", -1))
	if active and not was_active:
		_request_effect(&"mode", {"id": &"collection", "title": "COLLECTION ROUND", "active": true},
				&"collection_started", {"destination_class": &"ceremony", "haptic": {}})
	elif active and collected != old_count:
		_request_effect(&"mode", {"id": &"collection_progress", "title": "COLLECTION %d/3" % collected,
				"active": true}, &"collection_changed", {"_feedback_level": &"reward",
				"_feedback_state": &"active", "destination_class": &"source", "haptic": {}})
	elif not active and collected >= 3 and (was_active or old_count != collected):
		_request_effect(&"mode", {"id": &"collection_result", "title": "COLLECTION COMPLETE",
				"active": false}, &"collection_complete", {"_feedback_level": &"reward",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})
	elif not active and was_active:
		_request_effect(&"mode", {"id": &"collection_result", "title": "COLLECTION TIMED OUT",
				"active": false}, &"collection_timeout", {"_feedback_level": &"consequence",
				"_feedback_state": &"completed", "destination_class": &"ceremony", "haptic": {}})
	_last_tail_state["collection"] = {"active": active, "collected": collected}


func _on_chairs_changed(state: Dictionary) -> void:
	var claimed := int(state.get("claimed", 0))
	var tonight := int(state.get("tonight", 0))
	if claimed > _last_chairs_claimed and tonight > 0:
		_request_effect(&"mode", {"id": &"chair_claimed", "title": "CHAIR CLAIMED  %d/%d" % [claimed,
					int(state.get("chairs", 5))], "active": false}, &"chair_taken", {
				"_feedback_level": &"reward", "_feedback_state": &"completed",
				"destination_class": &"source", "haptic": {}})
		if claimed >= int(state.get("chairs", 5)) and not _chairs_all_seen:
			_chairs_all_seen = true
			_request_effect(&"mode", {"id": &"chairs_all", "title": "FIVE CHAIRS CLAIMED", "active": false},
					&"chairs_all_five", {"_feedback_level": &"ceremony", "_feedback_state": &"completed",
					"destination_class": &"ceremony", "_feedback_priority": 3, "haptic": {}})
	_last_chairs_claimed = maxi(_last_chairs_claimed, claimed)


func _on_election_changed(state: Dictionary) -> void:
	var what := StringName(state.get("what", ""))
	var result_meta: Dictionary = state.get("result", {})
	var result_key := str(result_meta.get("won", "")) if not result_meta.is_empty() else ""
	var key := "%s:%s:%s:%s:%s" % [what, str(state.get("district", "")),
				str(state.get("votes", 0)), str(state.get("term_left", 0)), result_key]
	if what == &"" or key == str(_last_tail_state.get("election_key", "")):
		return
	_last_tail_state["election_key"] = key
	match what:
		&"unlocked":
			_request_effect(&"mode", {"id": &"election", "title": "ELECTIONS UNLOCKED", "active": true},
					&"election_unlocked", {"destination_class": &"ceremony", "haptic": {}})
		&"open":
			_request_effect(&"mode", {"id": &"election", "title": "ELECTION OPEN", "active": true},
					&"election_open", {"destination_class": &"ceremony", "haptic": {}})
		&"canvassed":
			_request_effect(&"mode", {"id": &"election_canvass", "title": "CANVASSED%s" % \
					(("  ·  " + str(state.get("district", ""))).to_upper() if not str(state.get("district", "")).is_empty() else ""),
					"active": false}, &"election_canvassed", {"_feedback_level": &"reward",
					"_feedback_state": &"completed", "destination_class": &"source", "haptic": {}})
		&"settled":
			var result: Dictionary = state.get("result", {})
			var won := bool(result.get("won", false))
			_request_effect(&"mode", {"id": &"election_result", "title": "ELECTION WON" if won else "ELECTION LOST",
					"active": false, "result": result.duplicate(true)}, &"election_settled", {
					"_feedback_level": &"reward" if won else &"consequence", "_feedback_state": &"completed",
					"destination_class": &"ceremony", "_feedback_priority": 1 if won else 2, "haptic": {}})


func _on_federal_changed(state: Dictionary) -> void:
	if bool(state.get("rico", false)) and state.has("rico_state"):
		_on_rico_state(state)
		return
	var pending := bool(state.get("rico", false))
	if pending and not _federal_pending:
		_request_effect(&"warning", {"title": "FEDERAL AT THE DOOR", "federal": state.duplicate(true)},
				&"federal_pending", {"destination_class": &"consequence", "haptic": {
					"pattern": &"warning", "strength": 0.66}})
		fx.haptic(&"warning", 0.66)
	_federal_pending = pending


func _on_rico_state(envelope: Dictionary) -> void:
	var state: Dictionary = envelope.get("rico_state", {})
	var phase := int(state.get("phase", 0))
	if phase <= 0:
		return
	_rico_context_active = true
	var key := "%d" % phase
	if key == _last_rico_phase_key:
		return
	_last_rico_phase_key = key
	_request_effect(&"mode", {"id": &"rico_phase", "title": "RICO · PHASE %d/%d · %s" % [phase,
				int(state.get("phases", 3)), str(state.get("line", ""))], "active": true,
				"phase": phase, "phases": int(state.get("phases", 3)), "line": state.get("line", ""),
				"wiretap": int(state.get("wiretap", 0)), "time_left": float(state.get("time_left", 0.0))},
				&"federal_rico_phase", {"destination_class": &"ceremony", "suppression": &"same_key",
				"haptic": {"pattern": &"mode", "strength": 0.72}})
	fx.haptic(&"mode", 0.72)


func _on_briefcase_opened(result: Dictionary) -> void:
	var kind := StringName(result.get("kind", ""))
	if kind == Briefcases.SETUP:
		_request_effect(&"mode", {"id": &"briefcase_setup", "title": "BRIEFCASE STUNG", "active": false},
				&"briefcase_opened", {"_feedback_level": &"consequence", "_feedback_state": &"completed",
				"destination_class": &"ceremony", "haptic": {}})
	elif kind == Briefcases.BOON:
		var boon := str(result.get("boon", "BOON")).to_upper()
		_request_effect(&"mode", {"id": &"briefcase_boon", "title": "BOON · " + boon, "active": false},
				&"briefcase_opened", {"_feedback_level": &"reward", "_feedback_state": &"completed",
				"destination_class": &"ceremony", "haptic": {}})


func _on_phone_changed(state: Dictionary) -> void:
	if bool(state.get("ringing", false)):
		if _phone_ringing:
			return
		_phone_ringing = true
		_request_effect(&"mode", {"id": &"phone", "title": "PHONE RINGING", "active": true},
				&"phone_ringing", {"destination_class": &"ceremony", "suppression": &"same_key", "haptic": {}})
		return
	_phone_ringing = false
	if bool(state.get("answered", false)):
		var caller := str(state.get("caller", "CALL")).to_upper()
		_request_effect(&"mode", {"id": &"phone_answered", "title": "CALL ANSWERED · " + caller,
				"active": false}, &"phone_answered", {"_feedback_level": &"reward",
				"_feedback_state": &"completed", "destination_class": &"source", "haptic": {}})
	elif bool(state.get("missed", false)):
		_request_effect(&"mode", {"id": &"phone_missed", "title": "PHONE MISSED", "active": false},
				&"phone_missed", {"_feedback_level": &"consequence", "_feedback_state": &"completed",
				"destination_class": &"ceremony", "haptic": {}})


func _on_rat_changed(state: Dictionary) -> void:
	var previous: Dictionary = _last_tail_state.get("rat", {})
	if bool(state.get("active", false)) and not bool(previous.get("active", false)):
		_request_effect(&"mode", {"id": &"rat", "title": "SOMETHING'S OFF", "active": true},
				&"rat_night", {"destination_class": &"ceremony", "haptic": {}})
	if state.has("clue") and str(state.get("clue", "")) != str(previous.get("clue", "")):
		_request_effect(&"mode", {"id": &"rat_clue", "title": str(state.get("line", "CLUE")),
				"active": true}, &"rat_clue", {"_feedback_level": &"reward", "_feedback_state": &"active",
				"destination_class": &"ceremony", "haptic": {}})
	if state.has("result"):
		var result: Dictionary = state.get("result", {})
		var right := bool(result.get("right", false))
		_request_effect(&"mode", {"id": &"rat_result", "title": "RAT CAUGHT" if right else "WRONG NAME",
				"active": false, "result": result.duplicate(true)}, &"rat_accusation", {
				"_feedback_level": &"reward" if right else &"consequence", "_feedback_state": &"completed",
				"destination_class": &"ceremony", "_feedback_priority": 3 if right else 2, "haptic": {}})
	_last_tail_state["rat"] = state.duplicate(true)


func _request_effect(kind: StringName, payload: Dictionary = {}, event_id: StringName = &"",
			overrides: Dictionary = {}) -> void:
	# Metadata is derived by the draw-only feedback consumer; authored event payloads remain intact.
	var contract_payload := payload.duplicate(true)
	if event_id != &"":
		contract_payload["_event_id"] = event_id
	for key: Variant in overrides:
		var metadata_key := str(key)
		if not metadata_key.begins_with("_"):
			metadata_key = "_" + metadata_key
		contract_payload[metadata_key] = overrides[key]
	var request := payload.duplicate(true)
	request["_presentation"] = effect_contract(kind, contract_payload)
	fx.request(kind, request)


func effect_contract(kind: StringName, payload: Dictionary = {}) -> Dictionary:
	var contract := TABLE_VISUAL_STATE.feedback_contract(kind, payload)
	var source: Variant = payload.get("screen_position", _effect_source())
	contract["source"] = source if source is Vector2 else _effect_source()
	return contract
