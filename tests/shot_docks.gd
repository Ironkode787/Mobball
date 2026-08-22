extends Node2D
## Screenshot rig for the M3 rooms (tools/shot.sh SHOT_SCENE=res://tests/shot_docks.tscn).
##
## Same trick as tests/shot_club.gd: the table alone has no camera and the session's camera
## parks at the bottom of the field, so neither can photograph a yard behind a gate or a room
## in negative-y space. This builds the table + CameraRig pair, forces the rings on, and parks
## the ball where the shot wants it.
##
## Not a sim: it lives outside tests/sim/ so tools/check.sh does not try to run it.
##
##   SHOT_DOCKS_VIEW=docks      (default) the yard, camera down on the lower field
##   SHOT_DOCKS_VIEW=penthouse  the Commission's room at the top of the table
##   SHOT_DOCKS_VIEW=whole      the whole machine at once, zoomed out to the camera's bounds

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

const RINGS: Array[StringName] = [
	&"club_deck", &"staircase_ramp", &"roulette_wheel", &"slot_reels",
	&"high_roller_saucer", &"backroom_saucer", &"club_flippers",
	&"docks", &"containers", &"crane", &"cargo_ramp", &"orbit_right",
	&"penthouse", &"commission_chairs", &"sitdown_saucer", &"penthouse_stairs",
]

## Where the ball is parked for each view, and how far in to zoom. The rooms are small next
## to a 2.8-screen table, so the default frame reduces them to a smudge in a corner.
const VIEWS := {
	&"docks": {"at": Vector2(232.0, 1300.0), "zoom": 2.1, "centre": Vector2(288.0, 1272.0)},
	&"penthouse": {"at": Vector2(300.0, -700.0), "zoom": 1.45, "centre": Vector2(276.0, -676.0)},
	&"whole": {"at": Vector2(490.0, 520.0), "zoom": 0.0, "centre": Vector2.ZERO},
}

var table: ProgressionTable = null
var camera: CameraRig = null

var _at: Vector2 = Vector2.ZERO
var _hold: bool = true


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.force_hardware(RINGS)
	var view := StringName(OS.get_environment("SHOT_DOCKS_VIEW"))
	if not VIEWS.has(view):
		view = &"docks"
	var cfg: Dictionary = VIEWS[view]
	_at = cfg["at"]
	# Every view parks the camera by hand: the rig's job in the game is to chase a ball and
	# keep the bats on screen, and neither is what a photograph of a room wants.
	_hold = true
	camera.follow_enabled = false
	var frame: Vector2 = cfg["centre"]
	var zoom: float = cfg["zoom"]
	if zoom <= 0.0:
		# The whole machine at once: the point of this shot is that the camera's own bounds
		# now span the Penthouse ceiling to the storm grate.
		var b := table.bounds()
		zoom = minf(1080.0 / b.size.x, 1920.0 / b.size.y) * 0.94
		frame = b.get_center()
	camera.static_zoom = zoom
	camera.zoom = Vector2(zoom, zoom)
	camera.static_center = frame
	camera.position = frame
	# a couple of chairs claimed and a stack broken open, so the shot shows the rooms in use
	if table.penthouse != null:
		table.penthouse.chairs.targets()[0].set_marked(true)
		table.penthouse.chairs.targets()[3].set_marked(true)
	if table.docks != null:
		table.docks.containers.target_at(1, 0).drop()
	var ball := table.spawn_ball()
	ball.place(_at)
	camera.set_target(ball)


## Held in place: this is a photograph of a frame, not of a rally.
func _physics_process(_delta: float) -> void:
	var b := table.ball
	if _hold and b != null and is_instance_valid(b):
		b.place(_at)
