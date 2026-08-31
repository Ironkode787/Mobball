extends Node
## Screenshot harness: instances a scene (SHOT_SCENE env or main), waits for it to settle,
## saves a PNG to SHOT_PATH, quits. Run via tools/shot.sh under xvfb.

var _captured_scene: Node = null

func _ready() -> void:
	var scene_path := OS.get_environment("SHOT_SCENE")
	if scene_path.is_empty():
		scene_path = "res://game/main.tscn"
	var ps: PackedScene = load(scene_path)
	if ps == null:
		printerr("shot: cannot load scene ", scene_path)
		get_tree().quit(2)
		return
	_captured_scene = ps.instantiate()
	add_child(_captured_scene)
	# Evidence scenes may need to finish a physics trace before the shared capture owner
	# samples its final viewport. This is an opt-in signal; ordinary shots retain their
	# existing process-frame behavior.
	if _captured_scene.has_method("wait_for_capture_ready"):
		print("shot: waiting for evidence route")
		await _captured_scene.wait_for_capture_ready()
		print("shot: evidence route ready")
	elif _captured_scene.has_signal("capture_ready"):
		await _captured_scene.capture_ready
	_capture()


func _capture() -> void:
	var frames := int(OS.get_environment("SHOT_FRAMES")) if OS.get_environment("SHOT_FRAMES") != "" else 90
	print("shot: settling ", frames, " process frames")
	for i in frames:
		await get_tree().process_frame
	print("shot: settling complete")
	var viewport := get_viewport()
	if viewport == null or viewport.get_texture() == null:
		printerr("shot: viewport texture unavailable; graphical capture is required")
		get_tree().quit(1)
		return
	var img := viewport.get_texture().get_image()
	if img == null or img.is_empty():
		printerr("shot: viewport image is empty")
		get_tree().quit(1)
		return
	var out := OS.get_environment("SHOT_PATH")
	if out.is_empty():
		out = "/tmp/shot.png"
	var err := img.save_png(out)
	print("shot: saved ", out, " err=", err)
	var capture_ok := err == OK
	if err == OK and _captured_scene != null and _captured_scene.has_method("finalize_canonical_capture"):
		_captured_scene.call("finalize_canonical_capture", out)
		if _captured_scene.has_method("capture_succeeded"):
			capture_ok = bool(_captured_scene.call("capture_succeeded"))
	get_tree().quit(0 if capture_ok else 1)
