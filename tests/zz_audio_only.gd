extends SceneTree
func _initialize() -> void:
	var t := TestCtx.new()
	var dir := DirAccess.open("res://tests")
	var names: PackedStringArray = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()
	for n in names:
		var script: GDScript = load("res://tests/%s" % n)
		var inst: Object = script.new()
		t.begin(n)
		var t0 := Time.get_ticks_msec()
		print("RUN ", n)
		inst.run(t)
		print("   done ", n, " in ", Time.get_ticks_msec() - t0, " ms")
	quit(0)
