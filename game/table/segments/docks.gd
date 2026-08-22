class_name Docks
extends Node2D
## THE DOCKS — the lower-left yard (docs/02 §2 R5, specs/m3-fall-rise.md TABLE-3).
##
## The Club grew the table upward; the Docks grows it *sideways into the danger*. It is a
## walled yard carved out of the field left of the block, and the only way in is down the
## numbers lane: a raked one-way blade at the bottom of that lane catches anything coming
## home and tips it through the dock mouth. Miss the lane and you never see the yard; take
## the lane and you are committed.
##
## Inside, one line of six crates in three stacks lies along the quay's own rake — a solid
## deck of cargo the ball has to break through. Which stack you clear decides where you land
## (that is the whole shot):
##
##   * stacks 1 and 2 open onto the **quay**, which falls away to the **cargo ramp** and
##     ships the load back to midfield. This is the paying line.
##   * stack 3 stands over the **harbour**. Clear it and the ball goes straight off the pier.
##
## And over all of it the **crane** patrols its gantry, winds up for 1.2 visible seconds, and
## swings whatever it is holding out over the water. That telegraph is the zone's whole
## difficulty: the pier is a real drain — it pinches the ball exactly like the storm grate
## downstairs — and no kickback reaches it, so the answer is to be gone before the hook drops.
##
## Geometry rules inherited from the M1/M2 lanes, all of them load-bearing here:
##   * the roof, the crate deck and the quay share ONE rake (12°), so every lane between them
##     is the same width end to end and nothing converges into a wedge;
##   * that rake outruns wall friction (0.14), so nothing parks on the roof or the quay;
##   * the strip left between the roof and Lucky's underside is narrower than a ball at every
##     x — a wall, not a slot;
##   * every gap in the standing crate deck is a wall, and every hole a cleared stack opens is
##     wider than `dia + 20`.
##
## Money: crates pay `smuggling` through TableScore like any other switch. The timed runs,
## the hot cargo and the heat are the flow lane's (FLOW-3).

## The ball came in off the numbers lane.
signal docks_entered()
## A stack went down (0..2), and the set of cleared stacks changed.
signal stack_cleared(stack: int)
signal containers_state(cleared_stacks: Array)
## The crane wound up / actually swung.
signal crane_telegraph()
signal crane_pulled()
## The ball went off the pier. The table turns this into a drain exactly like the storm grate.
signal pier_fall(ball: Ball)
## The cargo made it out: the ramp crested back onto the main field.
signal cargo_shipped(speed: float)

# ------------------------------------------------------------------ hardware ids
const ID_DOCKS := &"docks"
const ID_CONTAINERS := &"containers"
const ID_CRANE := &"crane"
const ID_CARGO_RAMP := &"cargo_ramp"

# ------------------------------------------------------------------ the yard
## Everything in here is parallel: 12° is the yard's rake, and the roof, the crate deck and
## the quay all use it so their lanes never pinch.
const RAKE_DEG := 12.0
const WALL_THICK := 22.0
const GUIDE_THICK := 18.0

const ROOF_FROM := Vector2(157.0, 1146.0)
const ROOF_TO := Vector2(420.0, 1202.0)
## The dock mouth: the yard's left wall simply is not there between the roof and the quay
## wall. It does not need to be — the blade outside it is the gate. A doorway with a lintel
## would put its sill *below* the blade's right end, and a ball squirted back out of the yard
## would then land in the numbers lane above the blade and climb it. With the mouth open to
## the roof, anything leaving high lands on the solid blade and is tipped straight back in.
const MOUTH_TOP := 1146.0
const MOUTH_BOTTOM := 1272.0
const LEFT_LOW_FROM := Vector2(157.0, 1272.0)
const LEFT_LOW_TO := Vector2(157.0, 1390.0)
const RIGHT_FROM := Vector2(420.0, 1202.0)
const RIGHT_TO := Vector2(420.0, 1400.0)
const QUAY_FROM := Vector2(166.0, 1380.0)
const QUAY_TO := Vector2(300.0, 1408.0)
## The harbour bed. It stops short of the slingshot's tip so a kicked ball still has its sky.
const BED_FROM := Vector2(312.0, 1397.0)
const BED_TO := Vector2(420.0, 1397.0)
const BED_THICK := 13.0

## The gate off the numbers lane. Raked at 20°, well past wall friction, so a ball coming
## home is *tipped* through the mouth rather than merely stopped over it.
##
## It hangs this low for a reason the geometry will not let you argue with: the numbers lane's
## own guide stops at y=1180 (M1, and not ours to move), and a ball riding the blade has to
## pass *under* that guide's rounded end to reach the mouth. Higher up, the 37 px it needs
## between the two is not there and the ball simply parks in the corner.
const BLADE_FROM := Vector2(58.0, 1226.0)
const BLADE_TO := Vector2(150.0, 1260.0)
const BLADE_THICK := 16.0

const CRATES_ORIGIN := Vector2(191.0, 1276.0)

## The harbour: the pier edge is the quay's right end, and everything past it is water.
const WATER_AT := Vector2(355.0, 1362.0)
const WATER_SIZE := Vector2(108.0, 64.0)

const GANTRY_FROM := Vector2(186.0, 1180.0)
const GANTRY_TO := Vector2(400.0, 1226.0)

## The cargo ramp's mouth sits on the quay, before the pier: roll off the deck with any pace
## at all and the hoist takes you; dribble, and the water takes you.
const CARGO_MOUTH_AT := Vector2(240.0, 1350.0)
const CARGO_MOUTH_SIZE := Vector2(88.0, 64.0)
const CARGO_ENTRY_SPEED := 350.0
## A powered hoist, not a wireform: the climb costs far less than the Club's staircase does.
const CARGO_CLIMB_GRAVITY := 55.0
const CARGO_MAX_SPEED := 1200.0
const CARGO_RELEASE_SPEED := 400.0
const CARGO_PATH: PackedVector2Array = [
	Vector2(240.0, 1350.0), Vector2(300.0, 1368.0), Vector2(360.0, 1340.0),
	Vector2(420.0, 1276.0), Vector2(455.0, 1192.0), Vector2(480.0, 1102.0),
	Vector2(490.0, 1024.0),
]

# ------------------------------------------------------------------ look (docs/07 §1)
const COL_RUST := Color("A9552E")
const COL_WATER := Color("173A4A")

var containers: ContainerStacks = null
var crane: CraneMagnet = null
var cargo_ramp: RampLane = null
var gate: OneWayGate = null
var pier: Area2D = null

var _present: bool = false
var _shell: WallPiece = null
var _ball: Ball = null
var _was_outside: bool = true


# ====================================================================== build =====


func _ready() -> void:
	_build_shell()
	_build_gate()
	_build_containers()
	_build_crane()
	_build_cargo_ramp()
	_build_pier()


func _build_shell() -> void:
	_shell = WallPiece.new()
	_shell.name = "DocksShell"
	_shell.color = Feel.COL_INK.lightened(0.16)
	add_child(_shell)
	_shell.bar(ROOF_FROM, ROOF_TO, WALL_THICK)
	_shell.bar(LEFT_LOW_FROM, LEFT_LOW_TO, GUIDE_THICK)
	_shell.bar(RIGHT_FROM, RIGHT_TO, WALL_THICK)
	_shell.bar(QUAY_FROM, QUAY_TO, 20.0)
	_shell.bar(BED_FROM, BED_TO, BED_THICK)


func _build_gate() -> void:
	gate = OneWayGate.new()
	gate.name = "DockGate"
	gate.color = COL_RUST.lightened(0.2)
	# Open from below: a ball flipped up the numbers lane goes straight through, and the same
	# ball coming home lands on a solid blade that is raked into the mouth.
	gate.configure(&"dock_gate", BLADE_FROM, BLADE_TO, BLADE_THICK, Vector2.DOWN)
	add_child(gate)


func _build_containers() -> void:
	containers = ContainerStacks.new()
	containers.name = "Containers"
	containers.configure(ID_CONTAINERS, CRATES_ORIGIN)
	add_child(containers)
	containers.stack_cleared.connect(func(s: int) -> void: stack_cleared.emit(s))
	containers.state_changed.connect(func(cleared: Array) -> void: containers_state.emit(cleared))


func _build_crane() -> void:
	crane = CraneMagnet.new()
	crane.name = "Crane"
	crane.configure(ID_CRANE, GANTRY_FROM, GANTRY_TO, yard_rect(), WATER_AT)
	add_child(crane)
	crane.telegraph_started.connect(func() -> void: crane_telegraph.emit())
	crane.pulled.connect(func(_b: Ball) -> void: crane_pulled.emit())


func _build_cargo_ramp() -> void:
	cargo_ramp = RampLane.new()
	cargo_ramp.name = "CargoRamp"
	cargo_ramp.entry_speed = CARGO_ENTRY_SPEED
	cargo_ramp.climb_gravity = CARGO_CLIMB_GRAVITY
	cargo_ramp.max_speed = CARGO_MAX_SPEED
	cargo_ramp.release_speed = CARGO_RELEASE_SPEED
	cargo_ramp.min_forward = 240.0
	cargo_ramp.entry_center = CARGO_MOUTH_AT
	cargo_ramp.entry_size = CARGO_MOUTH_SIZE
	cargo_ramp.abort_at = QUAY_FROM + Vector2(30.0, -34.0)
	cargo_ramp.color = COL_RUST
	cargo_ramp.configure(ID_CARGO_RAMP, CARGO_PATH)
	add_child(cargo_ramp)
	cargo_ramp.crested.connect(_on_cargo_crested)


## The pier edge. Same shape as the storm grate downstairs — an Area2D that reports the ball
## and lets the table do the losing, so a fall here costs a ball exactly like a drain does.
func _build_pier() -> void:
	pier = Area2D.new()
	pier.name = "Pier"
	pier.collision_layer = Feel.LAYER_ZONES
	pier.collision_mask = Feel.LAYER_BALL
	pier.monitorable = false
	pier.position = WATER_AT
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = WATER_SIZE
	cs.shape = rect
	pier.add_child(cs)
	add_child(pier)
	pier.body_entered.connect(_on_pier_entered)


# ================================================================== the table =====


func set_ball(b: Ball) -> void:
	_ball = b
	if b == null or not is_instance_valid(b):
		_was_outside = true
	for holder: Node in [cargo_ramp, crane, gate]:
		if holder != null:
			holder.call(&"set_ball", b)


## Every switchable piece of the yard, as the table's `_register` wants them: each one also
## needs `docks` itself, because a crane with no yard under it is not hardware.
func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_CONTAINERS], "node": containers},
		{"ids": [ID_CRANE], "node": crane},
		{"ids": [ID_CARGO_RAMP], "node": cargo_ramp},
	]


func bounds() -> Rect2:
	return Rect2(Vector2(ROOF_FROM.x - WALL_THICK, ROOF_FROM.y - WALL_THICK),
			Vector2(RIGHT_TO.x + WALL_THICK - ROOF_FROM.x + WALL_THICK,
			BED_TO.y + WALL_THICK - ROOF_FROM.y + WALL_THICK))


## The yard's interior, used by the crane to decide what is in reach.
func yard_rect() -> Rect2:
	return Rect2(Vector2(LEFT_LOW_FROM.x, ROOF_FROM.y),
			Vector2(RIGHT_TO.x - LEFT_LOW_FROM.x, BED_TO.y - ROOF_FROM.y))


func holds_ball() -> bool:
	return cargo_ramp != null and cargo_ramp.riding()


## Is a ball resting here on purpose? Only a ball on the hoist; everything else in the yard
## is fair game for the coils, and a wedge in here is exactly what they are for.
func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	return BallHold.is_held(ball) and holds_ball()


func _physics_process(_delta: float) -> void:
	if not _present or _ball == null or not is_instance_valid(_ball):
		return
	var inside := yard_rect().has_point(_ball.global_position)
	if inside and _was_outside:
		AudioDirector.play(&"wall_tap")
		docks_entered.emit()
	_was_outside = not inside


func _on_cargo_crested(speed: float) -> void:
	AudioDirector.play(&"orbit_whoosh")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, ID_CARGO_RAMP, _ball, speed)
	cargo_shipped.emit(speed)


func _on_pier_entered(body: Node2D) -> void:
	if not (body is Ball) or not _present:
		return
	pier_fall.emit(body as Ball)


# =================================================================== dormancy =====


## The yard's structure. Sub-hardware is switched by the table, which knows the owned set;
## this owns the shell, the gate and the pier — the things that make the yard a place.
func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_was_outside = true
	for piece: Node in [_shell, gate]:
		if piece != null:
			Dormant.apply(piece, active)
	if pier != null:
		pier.collision_layer = Feel.LAYER_ZONES if active else 0
		pier.collision_mask = Feel.LAYER_BALL if active else 0
	if not active:
		_release_everything()


func is_hardware_active() -> bool:
	return _present


## Switching the yard off while the hoist has the ball would leave it riding a ramp that is
## not there. It is put down on the quay instead, and the quay is inside the yard that just
## went away — so it is put down where the mouth is, on the main field's side of the wall.
func _release_everything() -> void:
	if cargo_ramp != null and cargo_ramp.riding() and _ball != null and is_instance_valid(_ball):
		BallHold.release(_ball, Vector2(103.0, MOUTH_BOTTOM + 60.0), Vector2.ZERO)
	if cargo_ramp != null:
		cargo_ramp.set_hardware_active(false)
	if crane != null:
		crane.set_active(false)


# ==================================================================== drawing =====


func _draw() -> void:
	_draw_yard()
	_draw_water()
	var font := ThemeDB.fallback_font
	if font != null:
		draw_set_transform(ROOF_FROM + Vector2(16.0, 34.0), deg_to_rad(RAKE_DEG), Vector2.ONE)
		draw_string(font, Vector2.ZERO, "THE DOCKS", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 26,
				COL_RUST.lightened(0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Wet concrete under a sodium light: the yard reads colder and dirtier than the felt around
## it, so the player can see where the gated area begins without a label.
func _draw_yard() -> void:
	var pts := PackedVector2Array([
		ROOF_FROM + Vector2(0.0, WALL_THICK * 0.5),
		ROOF_TO + Vector2(0.0, WALL_THICK * 0.5),
		Vector2(RIGHT_TO.x - WALL_THICK * 0.5, RIGHT_TO.y),
		Vector2(LEFT_LOW_TO.x + GUIDE_THICK * 0.5, RIGHT_TO.y),
	])
	draw_colored_polygon(pts, Feel.COL_FELT.lerp(COL_WATER, 0.45))
	# quay boards, and a bollard so the pier edge reads as an edge
	for i in range(7):
		var t := (float(i) + 0.5) / 7.0
		var a := QUAY_FROM.lerp(QUAY_TO, t)
		draw_line(a + Vector2(0.0, -12.0), a + Vector2(0.0, 12.0),
				Feel.COL_INK.lightened(0.10), 3.0)
	draw_line(QUAY_TO, QUAY_TO + Vector2(0.0, 26.0), COL_RUST.darkened(0.2), 6.0)
	draw_circle(QUAY_TO + Vector2(-14.0, -20.0), 9.0, COL_RUST)


func _draw_water() -> void:
	var r := Rect2(WATER_AT - WATER_SIZE * 0.5, WATER_SIZE)
	draw_rect(r, COL_WATER.darkened(0.35))
	for i in range(5):
		var y := lerpf(r.position.y + 12.0, r.end.y - 10.0, float(i) / 4.0)
		var w := r.size.x * (0.34 + 0.12 * float(i % 3))
		var x := r.position.x + 12.0 + float((i * 37) % 40)
		draw_line(Vector2(x, y), Vector2(minf(x + w, r.end.x - 8.0), y),
				COL_WATER.lightened(0.28), 3.0)
	draw_rect(r, COL_WATER.lightened(0.10), false, 2.0)
