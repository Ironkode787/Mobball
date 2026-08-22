extends Node
## Screenshot harness: instances a scene (SHOT_SCENE env or main), waits for it to settle,
## saves a PNG to SHOT_PATH, quits. Run via tools/shot.sh under xvfb.


func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	if scene_path.is_empty():
		scene_path = "res://game/main.tscn"
	var ps: PackedScene = load(scene_path)
	if ps == null:
		printerr("shot: cannot load scene ", scene_path)
		get_tree().quit(2)
		return
	add_child(ps.instantiate())
	_capture()


func _capture() -> void:
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 90
	for i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var out := OS.get_environment("SHOT_PATH")
	if out.is_empty():
		out = "/tmp/shot.png"
	var err := img.save_png(out)
	print("shot: saved ", out, " err=", err)
	get_tree().quit(0 if err == OK else 1)
