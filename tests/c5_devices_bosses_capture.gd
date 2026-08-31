extends Node
## Evidence-only C5 capture rig. It stages existing table APIs and saves one frame; it does
## not ship or alter table behavior. Use C5_VIEW=club|penthouse|boss and C5_MODE=color|
## reduced_motion|reduced_flash|grayscale|haptics_off|subtitles_off.

const TABLE_SCENE := preload("res://game/table/table_main.tscn")
const CLUB_HARDWARE: Array[StringName] = [
	ClubDeck.ID_DECK, ClubDeck.ID_STAIRCASE, ClubDeck.ID_ROULETTE, ClubDeck.ID_REELS,
	ClubDeck.ID_HIGH_ROLLER, ClubDeck.ID_BACKROOM, ClubDeck.ID_FLIPPERS,
]
const PENTHOUSE_HARDWARE: Array[StringName] = [
	ClubDeck.ID_DECK, Penthouse.ID_PENTHOUSE, Penthouse.ID_CHAIRS,
	Penthouse.ID_SITDOWN, Penthouse.ID_STAIRS,
]

var table: ProgressionTable = null
var camera: CameraRig = null
var _ball: Ball = null
var _ball_at := Vector2.ZERO
var _mode := &"color"


func _ready() -> void:
	_mode = StringName(OS.get_environment("C5_MODE"))
	if _mode == &"":
		_mode = &"color"
	if Presentation != null and Presentation.fx != null:
		Presentation.fx.reduced_motion = _mode == &"reduced_motion"
		Presentation.fx.reduced_flash = _mode == &"reduced_flash"
		Presentation.fx.haptics_enabled = _mode != &"haptics_off"
		Presentation.fx.subtitles_enabled = _mode != &"subtitles_off"
	table = TABLE_SCENE.instantiate()
	table.name = "C5CaptureTable"
	add_child(table)
	table.auto_respawn = false
	table.debug_all_hardware = true
	camera = CameraRig.new()
	camera.name = "C5CaptureCamera"
	camera.auto_bounds = false
	camera.follow_enabled = false
	add_child(camera)
	_stage_view(StringName(OS.get_environment("C5_VIEW")))
	_ball = table.spawn_ball()
	_ball.place(_ball_at)
	await get_tree().process_frame
	_capture()


func _stage_view(view: StringName) -> void:
	match view:
		&"penthouse":
			table.force_hardware(PENTHOUSE_HARDWARE)
			_ball_at = Vector2(276.0, -704.0)
			camera.static_center = Vector2(276.0, -680.0)
			camera.static_zoom = 1.16
			camera.zoom = Vector2.ONE * camera.static_zoom
			camera.position = camera.static_center
			if table.penthouse != null and table.penthouse.chairs != null:
				table.penthouse.chairs.targets()[1].set_marked(true)
				table.penthouse.chairs.targets()[3].set_marked(true)
			if table.penthouse != null and table.penthouse.sitdown != null:
				table.penthouse.sitdown.queue_redraw()
		_: 
			table.force_hardware(CLUB_HARDWARE)
			if view == &"boss":
				table.set_boss_target(&"sedan", &"park", 4, 0.0)
				_ball_at = Vector2(490.0, 1060.0)
				camera.static_center = Vector2(490.0, 920.0)
				camera.static_zoom = 1.65
				camera.zoom = Vector2.ONE * camera.static_zoom
				camera.position = camera.static_center
			else:
				_ball_at = ClubDeck.WHEEL_AT
				camera.static_center = Vector2(780.0, -520.0)
				camera.static_zoom = 1.06
				camera.zoom = Vector2.ONE * camera.static_zoom
				camera.position = camera.static_center
				if table.club != null and table.club.reels != null:
					table.club.reels.target_at(0, 0).drop()
					table.club.reels.target_at(1, 0).drop()


func _physics_process(_delta: float) -> void:
	if _ball != null and is_instance_valid(_ball):
		_ball.place(_ball_at)


func _capture() -> void:
	var frames := int(OS.get_environment("C5_FRAMES")) if OS.get_environment("C5_FRAMES") != "" else 30
	for i in range(frames):
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	if _mode == &"grayscale":
		_to_grayscale(image)
	var out := OS.get_environment("C5_CAPTURE_PATH")
	if out.is_empty():
		out = "user://c5-capture.png"
	var err := image.save_png(out)
	print("C5 CAPTURE view=%s mode=%s path=%s size=%dx%d err=%d" % [
		OS.get_environment("C5_VIEW"), _mode, out, image.get_width(), image.get_height(), err])
	get_tree().quit(0 if err == OK else 1)


func _to_grayscale(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var source := image.get_pixel(x, y)
			var luminance := source.r * 0.299 + source.g * 0.587 + source.b * 0.114
			image.set_pixel(x, y, Color(luminance, luminance, luminance, source.a))
