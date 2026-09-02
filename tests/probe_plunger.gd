extends Node2D
## Dev probe (not a gate): launches the ball at a sweep of plunger powers on the progression
## table and reports where each one ends up — which top lane it dropped into, whether it
## orbited to the left lane, or whether it fell back down the right side. Run:
##   godot --headless --path . res://tests/probe_plunger.tscn
## Used to pick the Drop-Off's starter power bands after a layout change.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const POWERS: PackedFloat32Array = [0.88, 0.90, 0.92, 0.93, 0.94, 0.95, 0.96, 0.97, 0.98, 0.99, 1.00]
const WATCH_TICKS := 900

var table: ProgressionTable = null
var _rollover: int = -1
var _orbit: bool = false


func _ready() -> void:
	table = TABLE_SCENE.instantiate()
	table.name = "Table"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = true
	table.refresh_hardware()
	table.rollover_rolled.connect(func(i: int, _lit: bool) -> void:
		if _rollover < 0:
			_rollover = i)
	table.orbit_completed.connect(func() -> void: _orbit = true)
	_run()


func _run() -> void:
	for p in POWERS:
		_rollover = -1
		_orbit = false
		table.despawn_ball()
		var b := table.spawn_ball()
		for i in range(12):
			await get_tree().physics_frame
		table.plunger.launch(p)
		var low_x := INF
		var min_y := INF
		var gate_speed := -1.0
		for i in range(WATCH_TICKS):
			await get_tree().physics_frame
			if b == null or not is_instance_valid(b):
				break
			if gate_speed < 0.0 and b.global_position.x < ProgressionTable.DIVIDER_X:
				gate_speed = b.speed()
			low_x = minf(low_x, b.global_position.x)
			min_y = minf(min_y, b.global_position.y)
		var where := "lane %d" % (_rollover + 1) if _rollover >= 0 else "no lane"
		if _orbit:
			where += " + ORBIT"
		var endp := b.global_position if (b != null and is_instance_valid(b)) else Vector2.INF
		var end_speed := b.speed() if (b != null and is_instance_valid(b)) else 0.0
		print("power %.2f -> %s   (gate speed %.0f, min y %.0f, leftmost x %.0f, ended %s at %.0f px/s)" % [p, where, gate_speed, min_y, low_x, endp, end_speed])
	get_tree().quit(0)
