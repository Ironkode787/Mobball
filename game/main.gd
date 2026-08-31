class_name Main
extends Node2D
## The session host: table + camera + input + nudge + the screens. Everything is assembled
## in code so the scene file stays a stub and the runtime tree is the single source of truth.
##
## `Game` (the autoload) owns the session model and the state machine; this node owns the
## scene tree and reacts to `Game.state_changed` by putting the right things on screen:
##
##     attract  → attract screen, no ball
##     night    → NightController drives the table, HUD visible
##     count    → The Count over a dead table
##     ledger   → the Ledger overlay on top of The Count
##
## `auto_start` false keeps the whole session out of the way (the M0 feel sims drive the
## table directly); `show_hud` false drops the HUD with it.

@export var auto_start: bool = true
@export var show_hud: bool = true

## The table root (`res://game/table/table_main.tscn`). Held loosely and talked to through
## `TableAPI`: the table lane owns that scene's class and its M1 API arrives in its own time.
var table: Node2D = null
var camera: CameraRig = null
var input: InputController = null
var nudge: NudgeController = null
var hud: GameHUD = null
var attract: AttractScreen = null
var count: CountScreen = null
var roll_call: RollCallScreen = null
var ledger: Node = null
var settings_sheet: SettingsSheet = null
var night: NightController = null
var onboarding: OnboardingCoach = null

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const LEDGER_SCENE_PATH := "res://game/ui/ledger/ledger.tscn"
## Debug: M cycles the empire's music level 0..8 so the growing band can be auditioned.
const MUSIC_LEVELS := 9

var _music_level: int = 2
var _ledger_missing_logged: bool = false
## The CanvasLayer the Ledger overlay rides (layer 2, above The Count's layer 1).
var _ledger_layer: CanvasLayer = null
## Presentation-only cover for screen swaps. State and gameplay continue to belong to Game.
var _transition_layer: CanvasLayer = null
var _transition: ScreenTransition = null
var _shown_state: StringName = &""
var _transitions_enabled := false
var _pending_state: StringName = &""
var _applying_state := false
var _owner_trace: Array[Dictionary] = []
var _owner_trace_sequence := 0
var _last_route_interaction := ""

const OWNER_TRACE_SCHEMA := "kingpin.main.owner-transition.v1"
const OWNER_TRACE_LIMIT := 256


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)

	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)

	nudge = NudgeController.new()
	nudge.name = "Nudge"
	add_child(nudge)
	nudge.shake_target = camera

	input = InputController.new()
	input.name = "InputController"
	add_child(input)
	input.bind(TableAPI.prop(table, "flipper_left") as Flipper,
			TableAPI.prop(table, "flipper_right") as Flipper,
			TableAPI.prop(table, "plunger") as Plunger, nudge)

	if table.has_signal("ball_spawned"):
		table.connect("ball_spawned", _on_ball_spawned)
	if table.has_signal("ball_lost"):
		table.connect("ball_lost", _on_ball_lost)
	Events.tilted.connect(_on_tilted)

	if show_hud:
		hud = GameHUD.new()
		hud.name = "HUD"
		add_child(hud)

	AudioDirector.music_start()
	AudioDirector.music_set_level(_music_level)
	_build_transition_layer()

	if auto_start:
		start_session()


## Boot the session model and start reacting to it. `_ready` calls this when `auto_start`
## is set; the flow sims call it directly so they can point the save file somewhere
## harmless instead of at the player's career.
func start_session(save_path: String = SaveGame.DEFAULT_PATH) -> void:
	_transitions_enabled = false
	_pending_state = &""
	_last_route_interaction = "boot"
	if not Game.state_changed.is_connected(_on_state_changed):
		Game.state_changed.connect(_on_state_changed)
	Game.boot(save_path)
	# boot() sets the stem count from the rank; keep the M debug key cycling from there.
	_music_level = AudioDirector.music_level()
	_shown_state = Game.state
	_applying_state = true
	_apply_state(Game.state)
	_applying_state = false
	_drain_state_changes()
	_record_owner_transition(&"session_started", Game.state)
	_transitions_enabled = true


func _exit_tree() -> void:
	_transitions_enabled = false
	_pending_state = &""
	if Game.state_changed.is_connected(_on_state_changed):
		Game.state_changed.disconnect(_on_state_changed)
	var old_night := night
	if old_night != null and is_instance_valid(old_night):
		old_night.stop()
		_dispose_owner(old_night)
	night = null
	if Game.night != null and (not is_instance_valid(Game.night) or Game.night == old_night):
		Game.night = null


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, \
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			if Game.is_booted():
				Game.save_now()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_M:
		_music_level = (_music_level + 1) % MUSIC_LEVELS
		AudioDirector.music_set_level(_music_level)


# ============================================================ table plumbing =====


func _on_ball_spawned(ball: Ball) -> void:
	nudge.set_ball(ball)
	camera.set_target(ball)


## Table housekeeping on every drain, Night or no Night: the guy is gone, so the flippers
## come back and the Inspector forgets. Who gets pinched is the NightController's business.
func _on_ball_lost(_ball: Ball) -> void:
	nudge.set_ball(null)
	nudge.clear_tilt()
	var left: Variant = TableAPI.prop(table, "flipper_left")
	var right: Variant = TableAPI.prop(table, "flipper_right")
	if left is Flipper:
		(left as Flipper).revive()
	if right is Flipper:
		(right as Flipper).revive()
	var plunger: Variant = TableAPI.prop(table, "plunger")
	if plunger is Plunger:
		(plunger as Plunger).enabled = true


## TILT: the guy's flippers are dead until he's pinched (docs/01 §5).
func _on_tilted() -> void:
	var left: Variant = TableAPI.prop(table, "flipper_left")
	var right: Variant = TableAPI.prop(table, "flipper_right")
	if left is Flipper:
		(left as Flipper).kill()
	if right is Flipper:
		(right as Flipper).kill()


# ============================================================== the screens =====


func _on_state_changed(state: StringName) -> void:
	_pending_state = state
	if _applying_state:
		return
	_drain_state_changes()


func _drain_state_changes() -> void:
	while _pending_state != &"":
		var state := _pending_state
		_pending_state = &""
		var previous := _shown_state
		_shown_state = state
		if _transitions_enabled and _transition != null and previous != state:
			_transition.play_reveal(previous, state)
		if previous != state:
			_release_route_focus()
		_applying_state = true
		_apply_state(state)
		_applying_state = false
		_record_owner_transition(&"state_applied", state)


func _build_transition_layer() -> void:
	_transition_layer = CanvasLayer.new()
	_transition_layer.name = "ScreenTransitionLayer"
	_transition_layer.layer = 100
	add_child(_transition_layer)
	_transition = ScreenTransition.new()
	_transition.name = "ScreenTransition"
	_transition_layer.add_child(_transition)


func _apply_state(state: StringName) -> void:
	var playing := state == &"night"
	var wants_attract := state == &"attract"
	var wants_roll_call := state == &"roll_call"
	var wants_count := state == &"count" or state == &"ledger"
	var wants_ledger := state == &"ledger"
	if settings_sheet != null and is_instance_valid(settings_sheet):
		_close_settings()
	# Remove old owners first. A queued child remains in the scene tree until the next
	# frame, which can otherwise produce two focusable screen roots during a handoff.
	if not wants_ledger:
		_want_ledger(false)
	if not wants_count:
		_want_count(false)
	if not playing:
		_want_night(false)
	if not wants_roll_call:
		_want_roll_call(false)
	if not wants_attract:
		_want_attract(false)
	# Create target owners only after all non-target owners have left the tree.
	_want_attract(wants_attract)
	_want_roll_call(wants_roll_call)
	_want_night(playing)
	_want_count(wants_count)
	_want_ledger(wants_ledger)
	if hud != null:
		hud.visible = playing
	if input != null:
		input.enabled = playing
	if nudge != null:
		nudge.enabled = playing


func _want_attract(on: bool) -> void:
	if on and _owner_is_live(attract):
		return
	if not on:
		_dispose_owner(attract)
		attract = null
		return
	if attract != null and is_instance_valid(attract):
		_dispose_owner(attract)
		attract = null
	attract = AttractScreen.new()
	attract.name = "Attract"
	attract.start_pressed.connect(func() -> void:
		_last_route_interaction = "ROLL CALL"
		Game.open_roll_call())
	attract.settings_pressed.connect(_open_settings)
	add_child(attract)


func _want_roll_call(on: bool) -> void:
	if on and _owner_is_live(roll_call):
		return
	if not on:
		_dispose_owner(roll_call)
		roll_call = null
		return
	if roll_call != null and is_instance_valid(roll_call):
		_dispose_owner(roll_call)
		roll_call = null
	roll_call = RollCallScreen.new()
	roll_call.name = "RollCall"
	roll_call.start_pressed.connect(func(lineup: Array[Dictionary]) -> void:
		_last_route_interaction = "START NIGHT"
		Game.start_prepared_night(lineup))
	add_child(roll_call)


func _want_night(on: bool) -> void:
	if on and _owner_is_live(night):
		return
	if not on:
		_dispose_owner(onboarding)
		onboarding = null
		var old_night := night
		if old_night != null and is_instance_valid(old_night):
			old_night.stop()
			_dispose_owner(old_night)
		night = null
		if Game.night == old_night or old_night == null:
			Game.night = null
		if hud != null:
			hud.night_controller = null
		return
	if night != null and is_instance_valid(night):
		_dispose_owner(night)
		night = null
	night = NightController.new()
	night.name = "Night"
	add_child(night)
	night.bind(table, nudge, input)
	Game.night = night
	if hud != null:
		hud.night_controller = night
		hud.refresh()
	night.start()
	if Game.night_no == 1:
		onboarding = OnboardingCoach.new()
		onboarding.name = "FirstNightCoach"
		add_child(onboarding)


func _want_count(on: bool) -> void:
	if on and _owner_is_live(count):
		return
	if not on:
		_dispose_owner(count)
		count = null
		return
	if count != null and is_instance_valid(count):
		_dispose_owner(count)
		count = null
	count = CountScreen.new()
	count.name = "Count"
	count.ledger_pressed.connect(func() -> void:
		_last_route_interaction = "THE LEDGER"
		Game.open_ledger())
	count.next_night_pressed.connect(func() -> void:
		_last_route_interaction = "NEXT NIGHT"
		Game.open_roll_call())
	count.boss_pressed.connect(func() -> void: Game.start_boss_night())
	count.heist_pressed.connect(func(target: StringName, approach: StringName,
			guy: Dictionary) -> void: Game.start_heist_night(target, approach, guy))
	count.skip_town_pressed.connect(func(keep: Dictionary) -> void: Game.skip_town(keep))
	count.settings_pressed.connect(_open_settings)
	add_child(count)


func _open_settings() -> void:
	if _owner_is_live(settings_sheet):
		return
	# Settings is a modal owner. Release the route's previous control before adding the
	# overlay so focus cannot remain on an underlying Count/Attract button.
	_release_route_focus()
	if settings_sheet != null and is_instance_valid(settings_sheet):
		_dispose_owner(settings_sheet)
		settings_sheet = null
	settings_sheet = SettingsSheet.new()
	settings_sheet.name = "Settings"
	settings_sheet.closed.connect(_close_settings)
	add_child(settings_sheet)
	_last_route_interaction = "settings_opened"
	_record_owner_transition(&"overlay_opened", Game.state)


func _close_settings() -> void:
	if settings_sheet == null or not is_instance_valid(settings_sheet):
		settings_sheet = null
		return
	_release_focus_for(settings_sheet)
	_dispose_owner(settings_sheet)
	settings_sheet = null
	_last_route_interaction = "settings_closed"
	_record_owner_transition(&"overlay_closed", Game.state)


## The Ledger belongs to the meta lane. Until it lands, opening it is a no-op that bounces
## straight back to The Count rather than a missing-resource error.
##
## The overlay rides its OWN CanvasLayer above The Count's: CountScreen is a CanvasLayer
## (layer 1), so a Control added to Main draws in the world canvas UNDERNEATH it — state
## flips to &"ledger" and nothing visibly happens. First device bug report; the desktop
## sims asserted state and `visible`, never pixels (tests/device_probe.tscn does now).
func _want_ledger(on: bool) -> void:
	if on and _owner_is_live(ledger) and _owner_is_live(_ledger_layer):
		return
	if not on:
		if ledger != null and is_instance_valid(ledger) and ledger.has_method("close"):
			ledger.call("close")
		_release_focus_for(ledger)
		_dispose_owner(ledger)
		_dispose_owner(_ledger_layer)
		_ledger_layer = null
		ledger = null
		return
	if ledger != null and is_instance_valid(ledger):
		_dispose_owner(ledger)
		ledger = null
	if _ledger_layer != null and is_instance_valid(_ledger_layer):
		_dispose_owner(_ledger_layer)
		_ledger_layer = null
	if not ResourceLoader.exists(LEDGER_SCENE_PATH):
		if not _ledger_missing_logged:
			_ledger_missing_logged = true
			print("[flow] no ledger scene yet at ", LEDGER_SCENE_PATH)
		Game.close_ledger()
		return
	var scene: PackedScene = load(LEDGER_SCENE_PATH)
	if scene == null:
		Game.close_ledger()
		return
	ledger = scene.instantiate()
	ledger.name = "Ledger"
	_ledger_layer = CanvasLayer.new()
	_ledger_layer.name = "LedgerLayer"
	# Above every screen: the HUD rides 10, The Count and the attract screen ride 20.
	_ledger_layer.layer = 30
	add_child(_ledger_layer)
	_ledger_layer.add_child(ledger)
	if ledger.has_signal("closed"):
		ledger.connect("closed", func() -> void:
			_last_route_interaction = "CLOSE"
			Game.close_ledger())
	if ledger.has_method("open"):
		ledger.call("open")
	_last_route_interaction = "ledger_opened"


func _owner_is_live(owner: Node) -> bool:
	return owner != null and is_instance_valid(owner) and owner.is_inside_tree() \
			and not owner.is_queued_for_deletion()


func _dispose_owner(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	_release_focus_for(owner)
	_disable_owner_process(owner)
	var parent := owner.get_parent()
	if parent != null:
		parent.remove_child(owner)
	owner.call_deferred("free")


func _disable_owner_process(owner: Node) -> void:
	owner.process_mode = Node.PROCESS_MODE_DISABLED
	for child: Node in owner.get_children():
		_disable_owner_process(child)


func _release_focus_for(owner: Node) -> void:
	if owner == null or not is_instance_valid(owner):
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var focus := viewport.gui_get_focus_owner()
	if focus == null or not is_instance_valid(focus):
		return
	if focus == owner or owner.is_ancestor_of(focus):
		viewport.gui_release_focus()


func _release_route_focus() -> void:
	var viewport := get_viewport()
	if viewport != null and viewport.gui_get_focus_owner() != null:
		viewport.gui_release_focus()


func owner_snapshot() -> Dictionary:
	var nodes: Array[Dictionary] = []
	for pair: Array in [["attract", attract], ["roll_call", roll_call], ["night", night],
			["count", count], ["ledger", ledger], ["settings", settings_sheet],
			["onboarding", onboarding]]:
		var node: Node = pair[1] as Node
		nodes.append({
			"owner": String(pair[0]),
			"present": node != null and is_instance_valid(node),
			"in_tree": _owner_is_live(node),
			"name": node.name if node != null and is_instance_valid(node) else "",
			"layer": int(node.layer) if node is CanvasLayer else -1,
		})
	var active := 0
	var primary_active := 0
	for node_record: Dictionary in nodes:
		if bool(node_record.get("in_tree", false)):
			active += 1
			if String(node_record.get("owner", "")) in ["attract", "roll_call", "night", "count"]:
				primary_active += 1
	var viewport := get_viewport()
	var focus := viewport.gui_get_focus_owner() if viewport != null else null
	var subtitle: Dictionary = {}
	if Presentation.subtitles != null and is_instance_valid(Presentation.subtitles):
		subtitle = Presentation.subtitles.call("snapshot")
	var toast_count := -1
	if Presentation.feedback != null and is_instance_valid(Presentation.feedback):
		toast_count = int(Presentation.feedback.call("active_count"))
	var actual_size := DisplayServer.window_get_size()
	var requested_size := _requested_capture_size(actual_size)
	var logical := viewport.get_visible_rect().size if viewport != null else Vector2.ZERO
	return {
		"schema": OWNER_TRACE_SCHEMA,
		"state": String(Game.state),
		"shown_state": String(_shown_state),
		"owners": nodes,
		"active_owner_count": active,
		"primary_owner_count": primary_active,
		"ledger_layer_count": 1 if _owner_is_live(_ledger_layer) else 0,
		"transition_visible": _transition != null and is_instance_valid(_transition) \
				and _transition.visible,
		"transition_input_blocked": _transition != null and is_instance_valid(_transition) \
				and _transition.visible and _transition.mouse_filter == Control.MOUSE_FILTER_STOP,
		"transitions_enabled": _transitions_enabled,
		"input_enabled": input != null and is_instance_valid(input) and input.enabled,
		"focus_owner": String(focus.get_path()) if focus != null and is_instance_valid(focus) \
				and focus.is_inside_tree() else "",
		"subtitle": subtitle,
		"toast_active_count": toast_count,
		"requested_physical_size": {"x": requested_size.x, "y": requested_size.y},
		"actual_physical_size": {"x": actual_size.x, "y": actual_size.y},
		"logical_viewport": {"x": logical.x, "y": logical.y},
		"profile": _route_profile(),
		"interaction": _last_route_interaction,
	}


func owner_transition_trace() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for record: Dictionary in _owner_trace:
		out.append(record.duplicate(true))
	return out


func clear_owner_transition_trace() -> void:
	_owner_trace.clear()
	_owner_trace_sequence = 0


func _record_owner_transition(event: StringName, state: StringName) -> void:
	var record := owner_snapshot()
	record["sequence"] = _owner_trace_sequence
	record["event"] = String(event)
	record["requested_state"] = String(state)
	_owner_trace_sequence += 1
	_owner_trace.append(record)
	if _owner_trace.size() > OWNER_TRACE_LIMIT:
		_owner_trace.pop_front()


func _requested_capture_size(actual: Vector2i) -> Vector2i:
	# Capture fixtures may state their requested physical size without changing the runtime
	# window. This keeps host-clamped diagnostics honest and defaults to the actual window.
	var raw := OS.get_environment("KINGPIN_REQUESTED_SIZE")
	if raw.is_empty():
		raw = OS.get_environment("KINGPIN_CAPTURE_REQUESTED_SIZE")
	if raw.is_empty():
		return actual
	var parts := raw.to_lower().replace(" ", "").split("x")
	if parts.size() != 2:
		return actual
	var width := int(parts[0])
	var height := int(parts[1])
	return Vector2i(width, height) if width > 0 and height > 0 else actual


func _route_profile() -> String:
	var width := DisplayServer.window_get_size().x
	return "compact" if width > 0 and width < 720 else "standard"
