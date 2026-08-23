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
var night: NightController = null

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const LEDGER_SCENE_PATH := "res://game/ui/ledger/ledger.tscn"
## Debug: M cycles the empire's music level 0..8 so the growing band can be auditioned.
const MUSIC_LEVELS := 9

var _music_level: int = 2
var _ledger_missing_logged: bool = false
## The CanvasLayer the Ledger overlay rides (layer 2, above The Count's layer 1).
var _ledger_layer: CanvasLayer = null


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

	if auto_start:
		start_session()


## Boot the session model and start reacting to it. `_ready` calls this when `auto_start`
## is set; the flow sims call it directly so they can point the save file somewhere
## harmless instead of at the player's career.
func start_session(save_path: String = SaveGame.DEFAULT_PATH) -> void:
	if not Game.state_changed.is_connected(_on_state_changed):
		Game.state_changed.connect(_on_state_changed)
	Game.boot(save_path)
	# boot() sets the stem count from the rank; keep the M debug key cycling from there.
	_music_level = AudioDirector.music_level()
	_apply_state(Game.state)


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
	_apply_state(state)


func _apply_state(state: StringName) -> void:
	var playing := state == &"night"
	_want_attract(state == &"attract")
	_want_roll_call(state == &"roll_call")
	_want_night(playing)
	_want_count(state == &"count" or state == &"ledger")
	_want_ledger(state == &"ledger")
	if hud != null:
		hud.visible = playing
	if input != null:
		input.enabled = playing
	if nudge != null:
		nudge.enabled = playing


func _want_attract(on: bool) -> void:
	if on == (attract != null and is_instance_valid(attract)):
		return
	if not on:
		attract.queue_free()
		attract = null
		return
	attract = AttractScreen.new()
	attract.name = "Attract"
	attract.start_pressed.connect(func() -> void: Game.open_roll_call())
	add_child(attract)


func _want_roll_call(on: bool) -> void:
	if on == (roll_call != null and is_instance_valid(roll_call)):
		return
	if not on:
		roll_call.queue_free()
		roll_call = null
		return
	roll_call = RollCallScreen.new()
	roll_call.name = "RollCall"
	roll_call.start_pressed.connect(func(lineup: Array[Dictionary]) -> void:
		Game.start_prepared_night(lineup))
	add_child(roll_call)


func _want_night(on: bool) -> void:
	if on == (night != null and is_instance_valid(night)):
		return
	if not on:
		night.stop()
		night.queue_free()
		night = null
		Game.night = null
		if hud != null:
			hud.night_controller = null
		return
	night = NightController.new()
	night.name = "Night"
	add_child(night)
	night.bind(table, nudge, input)
	Game.night = night
	if hud != null:
		hud.night_controller = night
		hud.refresh()
	night.start()


func _want_count(on: bool) -> void:
	if on == (count != null and is_instance_valid(count)):
		return
	if not on:
		count.queue_free()
		count = null
		return
	count = CountScreen.new()
	count.name = "Count"
	count.ledger_pressed.connect(func() -> void: Game.open_ledger())
	count.next_night_pressed.connect(func() -> void: Game.open_roll_call())
	count.boss_pressed.connect(func() -> void: Game.start_boss_night())
	count.heist_pressed.connect(func(target: StringName, approach: StringName,
			guy: Dictionary) -> void: Game.start_heist_night(target, approach, guy))
	count.skip_town_pressed.connect(func(keep: Dictionary) -> void: Game.skip_town(keep))
	add_child(count)


## The Ledger belongs to the meta lane. Until it lands, opening it is a no-op that bounces
## straight back to The Count rather than a missing-resource error.
##
## The overlay rides its OWN CanvasLayer above The Count's: CountScreen is a CanvasLayer
## (layer 1), so a Control added to Main draws in the world canvas UNDERNEATH it — state
## flips to &"ledger" and nothing visibly happens. First device bug report; the desktop
## sims asserted state and `visible`, never pixels (tests/device_probe.tscn does now).
func _want_ledger(on: bool) -> void:
	if on == (ledger != null and is_instance_valid(ledger)):
		return
	if not on:
		if ledger.has_method("close"):
			ledger.call("close")
		if _ledger_layer != null and is_instance_valid(_ledger_layer):
			_ledger_layer.queue_free()
		else:
			ledger.queue_free()
		_ledger_layer = null
		ledger = null
		return
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
		ledger.connect("closed", func() -> void: Game.close_ledger())
	if ledger.has_method("open"):
		ledger.call("open")
