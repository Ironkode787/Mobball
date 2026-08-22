extends Node2D
## Screenshot rig for the Club (tools/shot.sh SHOT_SCENE=res://tests/shot_club.tscn).
##
## The table alone has no camera, and `game/main.tscn` parks its one at the bottom of the
## table until a ball goes upstairs — so neither of them can photograph a deck in negative-y
## space. This builds the same table + CameraRig pair the session builds, forces the Club's
## hardware on, and parks the ball wherever the shot wants it so the camera frames that.
##
## Not a sim: it lives outside tests/sim/ so `tools/check.sh` does not try to run it, and it
## quits when tools/shot_capture.gd has taken its picture.
##
##   SHOT_CLUB_VIEW=deck    (default) the ball on the upper deck, camera at the top
##   SHOT_CLUB_VIEW=stairs  mid-climb, the ball on the Staircase over the arch
##   SHOT_CLUB_VIEW=table   the ball at the flippers, camera parked on the main field

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

const VIEWS := {
	&"deck": Vector2(880.0, -560.0),
	&"stairs": Vector2(968.0, 210.0),
	&"table": Vector2(420.0, 1500.0),
}

var table: ProgressionTable = null
var camera: CameraRig = null

var _at: Vector2 = Vector2.ZERO


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.force_hardware([
		ClubDeck.ID_DECK, ClubDeck.ID_STAIRCASE, ClubDeck.ID_ROULETTE, ClubDeck.ID_REELS,
		ClubDeck.ID_HIGH_ROLLER, ClubDeck.ID_BACKROOM, ClubDeck.ID_FLIPPERS,
	])
	var view := StringName(OS.get_environment("SHOT_CLUB_VIEW"))
	_at = VIEWS.get(view, VIEWS[&"deck"])
	var ball := table.spawn_ball()
	ball.place(_at)
	camera.set_target(ball)


## Held in place: this is a photograph of a frame, not of a rally.
func _physics_process(_delta: float) -> void:
	var b := table.ball
	if b != null and is_instance_valid(b):
		b.place(_at)
