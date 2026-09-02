extends Node2D
## Screenshot rig for the 3D playfield (tools/shot.sh ... res://tests/shot_table3d.tscn).
## Builds the same table + CameraRig + TableView3D trio the session builds, forces a career
## stage's hardware on, parks the ball where the view wants it and lets the camera frame it.
##
##   SHOT3D_VIEW=bare    (default) the R0 alley, ball at the flippers
##   SHOT3D_VIEW=block   an R3 Block: bumpers, slings, spinner, wire, storefronts, orbit
##   SHOT3D_VIEW=full    everything on, ball at the flippers
##   SHOT3D_VIEW=deck    everything on, ball on the Club deck
##   SHOT3D_VIEW=stairs  everything on, ball mid-Staircase
##   SHOT3D_VIEW=dome    everything on, ball under City Hall

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

const BLOCK_SET: Array = [
	&"inlane_guides", &"slingshots", &"bumper_2", &"bumper_3", &"rollovers", &"spinner_numbers",
	&"orbit_left", &"wire_bank", &"laundromat_loop", &"storefront_laundromat",
	&"storefront_pizzeria", &"storefront_pawn", &"bribe_target", &"kickback_left",
]
const VIEWS := {
	&"bare": Vector2(420.0, 1500.0),
	&"block": Vector2(600.0, 1400.0),
	&"full": Vector2(420.0, 1500.0),
	&"deck": Vector2(880.0, -560.0),
	&"stairs": Vector2(968.0, 210.0),
	&"dome": Vector2(520.0, -1000.0),
}

var table: ProgressionTable = null
var camera: CameraRig = null
var view3d: TableView3D = null
var _at: Vector2 = Vector2.ZERO


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	table.auto_respawn = false
	var view := StringName(OS.get_environment("SHOT3D_VIEW"))
	if view == &"":
		view = &"bare"
	match view:
		&"bare":
			pass
		&"block":
			table.force_hardware(BLOCK_SET, true)
		_:
			table.debug_all_hardware = true
			table.force_hardware([
				ClubDeck.ID_DECK, ClubDeck.ID_STAIRCASE, ClubDeck.ID_ROULETTE, ClubDeck.ID_REELS,
				ClubDeck.ID_HIGH_ROLLER, ClubDeck.ID_BACKROOM, ClubDeck.ID_FLIPPERS,
				Docks.ID_DOCKS, Docks.ID_CONTAINERS, Docks.ID_CRANE, Docks.ID_CARGO_RAMP,
				Penthouse.ID_PENTHOUSE, Penthouse.ID_CHAIRS, Penthouse.ID_SITDOWN, Penthouse.ID_STAIRS,
				CityHall.ID_CITY_HALL, CityHall.ID_LOOP,
			], true)
	table.refresh_hardware()
	view3d = TableView3D.new()
	add_child(view3d)
	view3d.setup(table, camera)
	_at = VIEWS.get(view, VIEWS[&"bare"])
	var ball := table.spawn_ball()
	ball.place(_at)
	camera.set_target(ball)


func _physics_process(_delta: float) -> void:
	var b := table.ball
	if b != null and is_instance_valid(b):
		b.place(_at)
