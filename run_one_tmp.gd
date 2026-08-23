extends SceneTree
## Scratch: run only the test files named in ONLY_TESTS (comma separated).


func _initialize() -> void:
	var t := TestCtx.new()
	var names := OS.get_environment("ONLY_TESTS").split(",", false)
	for n in names:
		var script: GDScript = load("res://tests/%s" % n)
		if script == null:
			t.begin(n)
			t.fail("failed to load script")
			continue
		var inst: Object = script.new()
		t.begin(n)
		print("running ", n)
		inst.run(t)
		print("done ", n)
	print("checks: %d  failures: %d" % [t.checks, t.failures.size()])
	for msg in t.failures:
		printerr("FAIL  " + msg)
	quit(0 if t.failures.is_empty() else 1)
