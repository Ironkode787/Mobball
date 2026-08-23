extends SceneTree
## Headless test runner. Discovers tests/test_*.gd; each must define
## `func run(t: TestCtx) -> void`. Exits non-zero on any failure.
##
## Watchdog: a RUNTIME error inside a test's run() aborts _initialize() before quit()
## ever executes, which used to hang the runner forever (META-3 finding). _process keeps
## iterating either way, so it quits with rc=3 if the suite never finished.

const WATCHDOG_SECONDS := 180.0

var _finished := false
var _started_msec := 0


func _process(_delta: float) -> bool:
	if _finished:
		return false
	if Time.get_ticks_msec() - _started_msec > WATCHDOG_SECONDS * 1000.0:
		printerr("run_tests: watchdog fired — a test aborted mid-run (runtime error?). rc=3")
		quit(3)
		return true
	return false


func _initialize() -> void:
	_started_msec = Time.get_ticks_msec()
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
	_finished = true
	quit(0 if t.failures.is_empty() else 1)
