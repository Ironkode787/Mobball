extends Node2D
## Evidence-only C6 capture rig. It stages real Docks children in a deterministic shot and
## records paint-only Federal/construction states. It never edits parent Docks geometry or
## invokes gameplay actions beyond the existing debug hardware/raid presentation hooks.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const DOCKS_IDS: Array[StringName] = [
	&"docks", &"containers", &"crane", &"cargo_ramp",
]

var table: ProgressionTable = null
var camera: CameraRig = null
var _view: StringName = &"docks"
var _mode: StringName = &"color"
var _ball_at := Vector2(232.0, 1300.0)


func _ready() -> void:
	_view = StringName(OS.get_environment("C6_VIEW"))
	if not [&"docks", &"federal", &"construction"].has(_view):
		_view = &"docks"
	_mode = StringName(OS.get_environment("C6_MODE"))
	if _mode == &"":
		_mode = &"color"
	if Presentation != null and Presentation.fx != null:
		Presentation.fx.reduced_motion = _mode == &"reduced_motion"
		Presentation.fx.reduced_flash = _mode == &"reduced_flash"
		Presentation.fx.haptics_enabled = _mode != &"haptics_off"
		Presentation.fx.subtitles_enabled = _mode != &"subtitles_off"
	table = TABLE_SCENE.instantiate()
	table.name = "C6EvidenceTable"
	add_child(table)
	table.auto_respawn = false
	camera = CameraRig.new()
	camera.name = "C6EvidenceCamera"
	camera.auto_bounds = true
	camera.follow_enabled = false
	add_child(camera)
	_stage_view()
	print("C6 stage display=%s motion=%s flash=%s jobs=%d" % [DisplayServer.get_name(),
			str(Presentation.fx.reduced_motion if Presentation != null and Presentation.fx != null else false),
			str(Presentation.fx.reduced_flash if Presentation != null and Presentation.fx != null else false),
			table.construction.building() if table.construction != null else -1])
	var ball := table.spawn_ball()
	ball.place(_ball_at)
	camera.set_target(ball)
	if table.docks != null:
		table.docks.set_ball(ball)
	await get_tree().process_frame
	_capture()


func _stage_view() -> void:
	match _view:
		&"federal":
			table.force_hardware(DOCKS_IDS)
			table.set_federal_raid(3)
			table.spawn_briefcase(Vector2(540.0, 1030.0))
			_ball_at = Vector2(540.0, 1030.0)
			camera.static_center = Vector2(540.0, 1120.0)
			camera.static_zoom = 1.18
		&"construction":
			table.force_hardware([])
			table.construction.enabled = true
			table.force_hardware(DOCKS_IDS)
			_ball_at = Vector2(240.0, 1300.0)
			camera.static_center = Vector2(288.0, 1272.0)
			camera.static_zoom = 1.85
		_: 
			table.force_hardware(DOCKS_IDS)
			if table.docks != null and table.docks.containers != null:
				table.docks.containers.target_at(1, 0).drop()
			if table.docks != null and table.docks.crane != null:
				table.docks.crane._telegraphing = true
				table.docks.crane._phase = CraneMagnet.PERIOD - CraneMagnet.TELEGRAPH * 0.5
			_ball_at = Vector2(232.0, 1300.0)
			camera.static_center = Vector2(288.0, 1272.0)
			camera.static_zoom = 1.85
	camera.zoom = Vector2.ONE * camera.static_zoom
	camera.position = camera.static_center


func _physics_process(_delta: float) -> void:
	var ball := table.ball
	if ball != null and is_instance_valid(ball):
		ball.place(_ball_at)


func _capture() -> void:
	var frames := int(OS.get_environment("C6_FRAMES")) if OS.get_environment("C6_FRAMES") != "" else 30
	for i in range(frames):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if _mode == &"grayscale":
		_apply_grayscale(image)
	var out := OS.get_environment("C6_CAPTURE_PATH")
	if out.is_empty():
		out = "user://c6-late-props.png"
	var err := image.save_png(out)
	print("C6 CAPTURE view=%s mode=%s path=%s size=%dx%d err=%d sensory=%s" % [
		_view, _mode, out, image.get_width(), image.get_height(), err,
		str(SensoryAudit.snapshot(get_tree().root, Presentation.budget))])
	get_tree().quit(0 if err == OK else 1)


func _apply_grayscale(image: Image) -> void:
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var value := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			image.set_pixel(x, y, Color(value, value, value, c.a))
