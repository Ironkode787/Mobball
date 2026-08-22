class_name Main
extends Node2D
## M0 wiring: table + camera + input + nudge + debug HUD. Everything is assembled in code so
## the scene file stays a stub and the runtime tree is the single source of truth.

@export var auto_start: bool = true
@export var show_hud: bool = true

var table: AlleyDebugTable = null
var camera: CameraRig = null
var input: InputController = null
var nudge: NudgeController = null
var hud: DebugHUD = null

const TABLE_SCENE := preload("res://game/table/segments/alley_debug.tscn")


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
	input.bind(table.flipper_left, table.flipper_right, table.plunger, nudge)

	if show_hud:
		hud = DebugHUD.new()
		hud.name = "HUD"
		add_child(hud)
		hud.bind(table, nudge)

	table.ball_spawned.connect(_on_ball_spawned)
	table.ball_lost.connect(_on_ball_lost)
	Events.tilted.connect(_on_tilted)

	if auto_start:
		table.spawn_ball()


func _on_ball_spawned(ball: Ball) -> void:
	nudge.set_ball(ball)
	camera.set_target(ball)


func _on_ball_lost(_ball: Ball) -> void:
	nudge.set_ball(null)
	nudge.clear_tilt()
	table.flipper_left.revive()
	table.flipper_right.revive()
	if table.plunger != null:
		table.plunger.enabled = true


## TILT: the guy's flippers are dead until he's pinched (docs/01 §5).
func _on_tilted() -> void:
	table.flipper_left.kill()
	table.flipper_right.kill()
