extends RefCounted
## C6 draw-edge checks. These exercise state metadata and paint-only boundaries without
## entering a gameplay scene, leaving the established docks simulation as the physics oracle.


func run(t: TestCtx) -> void:
	_containers(t)
	_crane(t)
	_briefcase(t)
	_construction(t)
	_federal(t)
	_preservation(t)


func _containers(t: TestCtx) -> void:
	var stacks := ContainerStacks.new()
	t.eq(stacks.visual_state()["state"], &"armed", "standing cargo starts as an armed invitation")
	stacks._reset_in.resize(ContainerStacks.STACKS)
	stacks._targets.resize(ContainerStacks.STACKS * ContainerStacks.PER_STACK)
	for i in stacks._targets.size():
		stacks._targets[i] = DropTarget.new()
	stacks.target_at(1, 0).down = true
	t.eq(stacks.visual_state(1)["state"], &"active", "a partly-cleared stack is active")
	stacks.target_at(1, 1).down = true
	t.eq(stacks.visual_state(1)["state"], &"completed", "a clear stack is completed")
	t.eq(stacks.visual_state(1)["mark"], &"marked_stamp", "a clear stack has a stamp cue")
	stacks.set_hardware_active(false)
	t.eq(stacks.visual_state()["state"], &"disabled", "dormant cargo is disabled")
	t.eq(stacks.targets().size(), ContainerStacks.STACKS * ContainerStacks.PER_STACK,
			"cargo state reads do not alter the six-target bank")
	stacks.free()


func _crane(t: TestCtx) -> void:
	var crane := CraneMagnet.new()
	t.eq(crane.visual_state()["state"], &"disabled", "inactive crane is disabled")
	crane.set_active(true)
	t.eq(crane.visual_state()["state"], &"idle", "patrolling crane is idle")
	crane._telegraphing = true
	t.eq(crane.visual_state()["state"], &"danger", "crane telegraph is danger")
	t.eq(crane.visual_state()["mark"], &"telegraph_hatch", "telegraph has a hatch cue")
	crane._telegraphing = false
	crane._flash = 1.0
	t.eq(crane.visual_state()["state"], &"completed", "crane pull has a result cue")
	crane.free()


func _briefcase(t: TestCtx) -> void:
	var case := Briefcase.new()
	t.eq(case.visual_state()["state"], &"disabled", "undropped briefcase is disabled")
	case._live = true
	case._left = Briefcase.LIFETIME
	t.eq(case.visual_state()["state"], &"armed", "live briefcase is armed")
	case._live = false
	case._resolution = &"collected"
	t.eq(case.visual_state()["state"], &"completed", "collected case keeps a completion cue")
	t.eq(case.get_child_count(), 0, "briefcase has no collider children")
	case.free()


func _construction(t: TestCtx) -> void:
	var build := BuildIn.new()
	t.eq(build.visual_state()["state"], &"idle", "idle construction overlay is quiet")
	var node := Node2D.new()
	build._jobs.append({"node": node, "rect": Rect2(0.0, 0.0, 96.0, 96.0), "t": 0.1, "seed": 1})
	t.eq(build.visual_state()["state"], &"active", "construction overlay is active while a job runs")
	t.ok(build.is_building(node), "construction job remains queryable")
	t.eq(BuildIn.DURATION, 1.2, "construction duration remains 1.2 seconds")
	node.free()
	build.free()


func _federal(t: TestCtx) -> void:
	var vans := FederalVans.new()
	t.eq(vans.visual_state()["state"], &"disabled", "federal vans start off")
	vans.set_active(true)
	t.eq(vans.visual_state()["state"], &"active", "federal vans are an active atmosphere cue")
	t.ok(vans.visual_state()["modifiers"][&"raid_phase"], "federal vans expose the raid modifier")
	t.eq(vans.get_child_count(), 0, "federal vans remain paint-only")
	vans.free()


func _preservation(t: TestCtx) -> void:
	t.eq(ContainerStacks.STACKS, 3, "docks keeps three cargo stacks")
	t.eq(ContainerStacks.PER_STACK, 2, "docks keeps two crates per stack")
	t.eq(CraneMagnet.PERIOD, 7.0, "crane cycle remains seven seconds")
	t.eq(CraneMagnet.TELEGRAPH, 1.2, "crane warning remains 1.2 seconds")
	t.eq(CraneMagnet.IMPULSE, 900.0, "crane impulse remains authored")
	t.eq(Briefcase.LIFETIME, 60.0, "briefcase lifetime remains one minute")
	t.eq(Briefcase.WALK_SECONDS, 0.8, "briefcase walk-off remains cosmetic")
	t.eq(BuildIn.DURATION, 1.2, "build-in duration remains authored")
	t.eq(FederalVans.SWEEP_PERIOD, 5.5,
			"federal sweep period remains authored")
