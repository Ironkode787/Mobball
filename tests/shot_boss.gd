extends Node2D
## Screenshot rig for the Commission fights (tools/shot.sh SHOT_SCENE=res://tests/shot_boss.tscn).
##
## Same trick as tests/shot_club.gd: the table on its own has no camera, so this builds the
## table + CameraRig pair a session builds, forces the hardware on, stands up ONE boss phase
## through the table's own boss API and parks the ball where the shot wants it. It photographs
## the hardware, not a fight — no session, no NightController, no money.
##
##   SHOT_BOSS_PHASE=sammy1    (default) the sedan crossing the waist, a bat jammed
##   SHOT_BOSS_PHASE=sammy2    three goons in front of the cans
##   SHOT_BOSS_PHASE=sammy3    the sedan parked centre, the other bat jammed
##   SHOT_BOSS_PHASE=butcher1  the meat truck in the orbit channel, freezer filling
##   SHOT_BOSS_PHASE=butcher2  the truck parked behind its back door
##   SHOT_BOSS_PHASE=butcher3  the frenzy: armor off, the freezer full

const TABLE_SCENE := preload("res://game/table/table_main.tscn")

var table: ProgressionTable = null
var camera: CameraRig = null

var _at: Vector2 = Vector2(490.0, 1100.0)
var _jam: StringName = &""


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	camera = CameraRig.new()
	camera.name = "CameraRig"
	add_child(camera)
	table.auto_respawn = false
	# The table applied the owned set in its own `_ready()`, so the bypass has to be followed
	# by a re-read or the photograph is of a bare alley with a boss standing in it.
	table.debug_all_hardware = true
	table.refresh_hardware()

	var phase := StringName(OS.get_environment("SHOT_BOSS_PHASE"))
	match phase:
		&"sammy2":
			table.set_boss_goons(true)
			table.set_boss_meter("3 GOONS STANDING   ·   CANS ARMORED", 1.0)
			_at = Vector2(490.0, 860.0)
			_jam = &"right"
		&"sammy3":
			table.set_boss_target(&"sedan", &"park", 3, 0.0)
			table.set_boss_meter("SAMMY PARKED   ·   3 PANELS", 0.75)  # phase 3
			_at = Vector2(300.0, 1040.0)
			_jam = &"right"
		&"butcher1":
			table.set_boss_target(&"truck", &"run", 3, ButcherFight.ORBIT_SPEED)
			table.set_boss_meter("COLD STORAGE   $12.4K", 0.55)
			_at = Vector2(300.0, 900.0)
		&"butcher2":
			table.set_boss_target(&"truck", &"park", 0, 0.0)
			table.set_boss_door(true)
			table.set_boss_meter("COLD STORAGE   $31.8K", 0.9)
			_at = Vector2(490.0, 1400.0)
		&"butcher3":
			table.set_boss_meter("BUMPER FRENZY   $31.8K   x2", 1.0)
			_at = Vector2(490.0, 820.0)
		_:
			table.set_boss_target(&"sedan", &"run", 4, 0.0)
			table.set_boss_meter("SAMMY'S SEDAN   ·   4 PANELS", 0.4)
			_at = Vector2(300.0, 1060.0)
			_jam = &"left"

	var ball := table.spawn_ball()
	ball.place(_at)
	camera.set_target(ball)


## Held in place: a photograph of a frame, not of a rally. The wrench is re-applied every tick
## because a jam is a countdown and this shot is supposed to last as long as the shutter does.
func _physics_process(_delta: float) -> void:
	var b := table.ball
	if b != null and is_instance_valid(b):
		b.place(_at)
	if _jam == &"":
		return
	var f: Flipper = table.flipper_right if _jam == &"right" else table.flipper_left
	if f != null and is_instance_valid(f):
		f.jam(0.5)
