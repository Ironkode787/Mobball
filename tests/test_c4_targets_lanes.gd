extends RefCounted
## C4 draw-edge state adapters. These checks exercise presentation metadata without entering
## any hardware into the scene tree, so collision, timing, scoring, and signal owners remain
## covered by the established geometry and simulation suites.


func run(t: TestCtx) -> void:
	_drop_targets(t)
	_target_bank(t)
	_rollover_and_spinner(t)
	_orbit_and_ramp(t)
	_one_way_gate(t)


func _drop_targets(t: TestCtx) -> void:
	var drop := DropTarget.new()
	t.eq(drop.visual_state()["state"], &"idle", "raised drop target starts idle")
	drop._pulse = 1.0
	t.eq(drop.visual_state()["state"], &"active", "drop target pulse is active")
	drop._pulse = 0.0
	drop.down = true
	var down := drop.visual_state()
	t.eq(down["state"], &"completed", "down target is completed")
	t.eq(down["mark"], &"marked_stamp", "down target has a non-color stamp")
	drop.set_hardware_active(false)
	t.eq(drop.visual_state()["state"], &"disabled", "absent drop target is disabled")
	drop.free()

	var standup := StandupTarget.new()
	t.eq(standup.visual_state()["state"], &"idle", "unmarked standup starts idle")
	standup.set_marked(true)
	t.eq(standup.visual_state()["state"], &"completed", "marked standup is completed")
	standup.set_hardware_active(false)
	t.eq(standup.visual_state()["state"], &"disabled", "absent standup is disabled")
	standup.free()


func _target_bank(t: TestCtx) -> void:
	var bank := TargetBank.new()
	var a := StandupTarget.new()
	var b := StandupTarget.new()
	bank.add_target(a)
	bank.add_target(b)
	t.eq(bank.visual_state()["state"], &"idle", "empty marked bank starts idle")
	a.set_marked(true)
	t.eq(bank.marked_count(), 1, "bank sees one marked target")
	t.eq(bank.visual_state()["state"], &"active", "partially marked bank is active")
	b.set_marked(true)
	t.eq(bank.is_complete(), true, "bank completion bookkeeping is unchanged")
	t.eq(bank.visual_state()["state"], &"completed", "fully marked bank is completed")
	bank.set_hardware_active(false)
	t.eq(bank.visual_state()["state"], &"disabled", "absent bank is disabled")
	bank.free()


func _rollover_and_spinner(t: TestCtx) -> void:
	var rollover := Rollover.new()
	t.eq(rollover.visual_state()["state"], &"idle", "unlit rollover starts idle")
	rollover.set_lit(true)
	t.eq(rollover.visual_state()["state"], &"armed", "lit rollover is armed")
	rollover._flash = 1.0
	t.eq(rollover.visual_state()["state"], &"active", "rolled rollover is active")
	rollover.set_hardware_active(false)
	t.eq(rollover.visual_state()["state"], &"disabled", "absent rollover is disabled")
	rollover.free()

	var spinner := Spinner.new()
	t.eq(spinner.visual_state()["state"], &"idle", "stopped spinner starts idle")
	spinner.kick(18.0)
	t.eq(spinner.visual_state()["state"], &"active", "spinning spinner is active")
	spinner._vel = 0.0
	spinner.spins_total = 1
	t.eq(spinner.visual_state()["state"], &"completed", "settled spinner keeps a completion mark")
	spinner.set_hardware_active(false)
	t.eq(spinner.visual_state()["state"], &"disabled", "absent spinner is disabled")
	spinner.free()


func _orbit_and_ramp(t: TestCtx) -> void:
	var orbit := OrbitLane.new()
	orbit.configure(&"test_orbit", Vector2(0.0, 0.0), Vector2(80.0, 30.0),
		Vector2(0.0, -300.0), 30.0)
	t.eq(orbit.visual_state()["state"], &"idle", "orbit starts idle")
	orbit._entered_at = 0.0
	t.eq(orbit.visual_state()["state"], &"armed", "entered orbit is armed")
	orbit._entered_at = -1000.0
	orbit._flash = 1.0
	t.eq(orbit.visual_state()["state"], &"completed", "completed orbit flashes as completed")
	orbit.set_hardware_active(false)
	t.eq(orbit.visual_state()["state"], &"disabled", "absent orbit is disabled")
	orbit.free()

	var ramp := RampLane.new()
	var path := PackedVector2Array([Vector2(10.0, 120.0), Vector2(110.0, 20.0), Vector2(210.0, -40.0)])
	ramp.configure(&"test_ramp", path)
	t.eq(ramp.visual_state()["state"], &"armed", "available ramp is armed")
	t.near(ramp.length(), path[0].distance_to(path[1]) + path[1].distance_to(path[2]), 0.001,
		"ramp arc length remains authored")
	t.ok(ramp.point_at(0.0).distance_to(path[0]) < 0.001, "ramp entry point is unchanged")
	t.ok(ramp.tangent_at(0.0).dot(Vector2(1.0, -1.0).normalized()) > 0.99,
		"ramp tangent follows its authored entry segment")
	t.near(ramp.project(path[1]), path[0].distance_to(path[1]), 0.001,
		"ramp projection stays arc-length based")
	ramp.set_hardware_active(false)
	t.eq(ramp.visual_state()["state"], &"disabled", "absent ramp is disabled")
	ramp.free()


func _one_way_gate(t: TestCtx) -> void:
	var gate := OneWayGate.new()
	gate.configure(&"test_gate", Vector2(-40.0, 0.0), Vector2(40.0, 0.0), 16.0, Vector2.UP)
	t.eq(gate.visual_state()["state"], &"idle", "closed gate starts idle")
	gate._open = true
	t.eq(gate.visual_state()["state"], &"armed", "open gate exposes an armed cue")
	t.near(gate.side_of(Vector2(0.0, 20.0)), -20.0, 0.001, "gate side distance uses its latch normal")
	gate._open = false
	gate.set_hardware_active(false)
	t.eq(gate.visual_state()["state"], &"disabled", "absent gate is disabled")
	gate.free()
