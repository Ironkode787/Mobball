extends Node
## Dev probe (not a gate): boots the main scene for a while and prints render statistics —
## frame time, draw calls, primitives, lights — so a graphics change can be compared under
## the same software GL:  tools/perf.sh
var _frames := 0
var _t := 0.0
var _warm := 60
var _samples: PackedFloat32Array = []
var _gpu := 0.0
var _cpu := 0.0

func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var ps: PackedScene = load("res://game/main.tscn")
	var main := ps.instantiate()
	add_child(main)
	# the whole machine, as a late-career night has it
	var table := main.find_child("Table", true, false)
	if table != null and table is ProgressionTable:
		(table as ProgressionTable).debug_all_hardware = true
		(table as ProgressionTable).refresh_hardware()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

func _process(delta: float) -> void:
	_frames += 1
	if _frames <= _warm:
		return
	_samples.append(delta * 1000.0)
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
	_cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
	_t += delta
	if _samples.size() >= int(OS.get_environment("PERF_FRAMES").to_int() if OS.get_environment("PERF_FRAMES") != "" else 240):
		_samples.sort()
		var sum := 0.0
		for s in _samples:
			sum += s
		var lights := 0
		var shadowed := 0
		var stack: Array[Node] = [get_tree().root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is Light3D and (n as Light3D).is_visible_in_tree():
				lights += 1
				if (n as Light3D).shadow_enabled:
					shadowed += 1
		var vp := get_viewport()
		print("perf: frame avg %.1f ms  p50 %.1f  p90 %.1f | render cpu %.1f ms gpu %.1f ms | draw calls %d | primitives %d | objects %d | lights %d (%d shadowed) | vram %.0f MB | size %s scale %.2f glow %s" % [
			sum / _samples.size(), _samples[_samples.size() / 2], _samples[int(_samples.size() * 0.9)],
			_cpu / _samples.size(), _gpu / _samples.size(),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			lights, shadowed,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			str(vp.size), vp.scaling_3d_scale, str(vp.world_3d.environment.glow_enabled if vp.world_3d != null and vp.world_3d.environment != null else "?")])
		get_tree().quit()
