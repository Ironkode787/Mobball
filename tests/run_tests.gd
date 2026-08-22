extends SceneTree
## Headless test runner. Discovers tests/test_*.gd; each must define
## `func run(t: TestCtx) -> void`. Exits non-zero on any failure.


func _initialize() -> void:
	var t := TestCtx.new()
	var dir := DirAccess.open("res://tests")
	if dir == null:
		push_error("cannot open res://tests")
		quit(2)
		return
	var names: PackedStringArray = []
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if f.begins_with("test_") and f.ends_with(".gd"):
			names.append(f)
		f = dir.get_next()
	dir.list_dir_end()
	names.sort()

	var ran := 0
	for n in names:
		var script: GDScript = load("res://tests/%s" % n)
		if script == null:
			t.begin(n)
			t.fail("failed to load script")
			continue
		var inst: Object = script.new()
		if not inst.has_method("run"):
			t.begin(n)
			t.fail("no run(t) method")
			continue
		t.begin(n)
		inst.run(t)
		ran += 1

	print("---")
	print("test files: %d  checks: %d  failures: %d" % [ran, t.checks, t.failures.size()])
	for msg in t.failures:
		printerr("FAIL  " + msg)
	if t.failures.is_empty():
		print("OK")
	quit(0 if t.failures.is_empty() else 1)
