extends RefCounted


func run(t: TestCtx) -> void:
	var probe := TestCtx.new()
	probe.near(1.0, 1.001, 0.01)
	probe.near(0.0, 0.0, 0.0)
	t.eq(probe.failures.size(), 0, "finite values within tolerance pass")
	for args in [[NAN, 1.0, 0.01], [1.0, NAN, 0.01], [INF, INF, 0.01],
			[1.0, 1.0, NAN], [1.0, 1.0, INF], [1.0, 1.0, -0.01], [1.0, 2.0, 0.01]]:
		var before := probe.failures.size()
		probe.near(args[0], args[1], args[2])
		t.eq(probe.failures.size(), before + 1, "invalid or out-of-tolerance comparison fails")
	var checks := probe.checks
	probe.begin("fixture")
	probe.skip("needs a viewport")
	t.eq(probe.checks, checks, "a skip is not a passing assertion")
	t.eq(probe.skips, PackedStringArray(["fixture: needs a viewport"]), "skip names its test and reason")
