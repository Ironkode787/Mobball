extends RefCounted
## The Inspector's suspicion meter (game/core/tilt_meter.gd).


func run(t: TestCtx) -> void:
	_warnings(t)
	_decay(t)
	_reset(t)
	_defaults(t)


func _warnings(t: TestCtx) -> void:
	var m := TiltMeter.new(3, 7.0)
	t.eq(m.lean(), &"warning", "first lean is a warning")
	t.eq(m.lean(), &"warning", "second lean is a warning")
	t.eq(m.lean(), &"warning", "third lean is a warning")
	t.eq(m.warnings, 3, "three warnings banked")
	t.ok(not m.tilted, "three leans is still legal")
	t.eq(m.lean(), &"tilt", "the fourth lean tilts")
	t.ok(m.tilted, "meter reports tilted")
	t.eq(m.lean(), &"ignored", "leaning after a tilt does nothing")
	t.eq(m.warnings, 4, "a tilted meter stops counting")


func _decay(t: TestCtx) -> void:
	var m := TiltMeter.new(3, 2.0)
	m.lean()
	m.lean()
	t.eq(m.warnings, 2, "two leans banked")
	t.ok(not m.advance(1.0), "half a decay window bleeds nothing off")
	t.eq(m.warnings, 2, "still two")
	t.near(m.decay_fraction(), 0.5, 1e-6, "halfway to the next decay")
	t.ok(m.advance(1.0), "the full window bleeds one off")
	t.eq(m.warnings, 1, "down to one")
	t.ok(m.advance(2.0), "another window bleeds the last one")
	t.eq(m.warnings, 0, "clean sheet")
	t.ok(not m.advance(10.0), "an empty meter has nothing to decay")
	t.eq(m.warnings, 0, "and never goes negative")

	# a fresh lean restarts the clock — no free half-decays
	m.lean()
	m.advance(1.9)
	m.lean()
	t.near(m.decay_fraction(), 0.0, 1e-6, "leaning resets the decay clock")

	var tilted_meter := TiltMeter.new(1, 1.0)
	tilted_meter.lean()
	tilted_meter.lean()
	t.ok(tilted_meter.tilted, "meter tilted")
	t.ok(not tilted_meter.advance(100.0), "a tilt never decays away on its own")
	t.ok(tilted_meter.tilted, "still tilted after a long wait")


func _reset(t: TestCtx) -> void:
	var m := TiltMeter.new(3, 7.0)
	for i in range(6):
		m.lean()
	t.ok(m.tilted, "tilted after six leans")
	m.reset()
	t.ok(not m.tilted, "reset clears the tilt")
	t.eq(m.warnings, 0, "reset clears the warnings")
	t.near(m.decay_fraction(), 0.0, 1e-6, "reset clears the decay clock")
	t.eq(m.lean(), &"warning", "the meter works again after a reset")


func _defaults(t: TestCtx) -> void:
	var m := TiltMeter.new()
	t.eq(m.max_warnings, Feel.TILT_MAX_WARNINGS, "defaults come from Feel")
	t.near(m.decay_seconds, Feel.TILT_DECAY_SECONDS, 1e-6, "decay default comes from Feel")
	for i in range(Feel.TILT_MAX_WARNINGS):
		t.eq(m.lean(), &"warning", "lean %d is only a warning" % (i + 1))
	t.eq(m.lean(), &"tilt", "one past TILT_MAX_WARNINGS tilts")
