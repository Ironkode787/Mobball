extends Node3D
## Screenshot rig for the 3D machine (tools/shot.sh out.png res://tests/shot_machine.tscn).
##   SHOT_VIEW=bare|block|full     which career stage is on the table
##   SHOT_BALL=x,z                 where to park the ball (plan units); default at the flippers
##   SHOT_CAM=low|high|deck        camera framing

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const BLOCK_SET: Array = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers", &"spinner_numbers",
	&"orbit_left", &"orbit_right", &"wire_bank", &"laundromat_loop", &"storefront_laundromat",
	&"storefront_pizzeria", &"storefront_pawn", &"bribe_target", &"kickback_left",
]

var table: ProgressionTable = null
var camera: CameraRig = null
var _at: Vector3 = Vector3.ZERO


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	var view := OS.get_environment("SHOT_VIEW")
	match view:
		"bare":
			pass
		"block":
			table.force_hardware(BLOCK_SET, true)
		_:
			table.debug_all_hardware = true
	table.refresh_hardware()
	camera = CameraRig.new()
	camera.name = "CameraRig"
	table.add_child(camera)
	var cam := OS.get_environment("SHOT_CAM")
	if cam == "high":
		camera.frame_length = 11.5
		camera.pitch_deg = 30.0
	elif cam == "deck":
		camera.frame_length = 6.0
	var ball_env := OS.get_environment("SHOT_BALL")
	var plan := Vector2(0.4, 3.9)
	if ball_env.contains(","):
		var parts := ball_env.split(",")
		plan = Vector2(parts[0].to_float(), parts[1].to_float())
	_at = Layout.p3(plan, table.floor_height_at(plan) + Feel.BALL_RADIUS + 0.01)
	var ball := table.spawn_ball()
	ball.place(_at)
	camera.set_target(ball)


func _physics_process(_delta: float) -> void:
	var b := table.ball
	if b != null and is_instance_valid(b):
		b.place(_at)
