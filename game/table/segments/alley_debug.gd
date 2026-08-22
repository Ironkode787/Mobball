class_name AlleyDebugTable
extends TableSegment
## The M0 debug table: one screen, 1080×1920, everything built in code so the collision
## geometry and the `_draw()` are generated from the same numbers and can't drift.
##
## Layout notes where this deviates from specs/m0-feel.md (physics demanded it, topology is
## unchanged):
##   · flipper pivots moved out to x=293/687 so the *surface* gap between the bat tips is the
##     ~66 px the spec asks for (the spec's 312/668 leaves only 33 px — a 56 px ball can't drain).
##   · slingshots moved inward so their outer edge forms the inlane's inner wall; at the
##     spec's x=196 the sling sat inside the inlane and sealed it shut.
##   · the lane/playfield divider is 20 px thick (spec: 6) — nothing thinner than 12 px is
##     allowed to be a wall here — and its top sits at y=430 rather than y=340: at 340 the
##     wall's cap stands inside the curve a launched ball traces round the arch, and every
##     full-power plunge smashed into it instead of feeding the playfield.

signal ball_spawned(ball: Ball)
signal ball_lost(ball: Ball)

const BALL_SCENE := preload("res://game/core/ball.tscn")
const FLIPPER_SCENE := preload("res://game/table/hardware/flipper.tscn")
const BUMPER_SCENE := preload("res://game/table/hardware/bumper.tscn")
const SLING_SCENE := preload("res://game/table/hardware/slingshot.tscn")

# --- playfield frame ---
const PLAY_LEFT := 40.0
const PLAY_RIGHT := 933.0
const PLAY_BOTTOM := 1894.0
const ARCH_A := Vector2(40.0, 460.0)
const ARCH_B := Vector2(490.0, 60.0)
const ARCH_C := Vector2(1040.0, 460.0)
const OUTER_THICK := 36.0
const GUIDE_THICK := 18.0

# --- shooter lane ---
const DIVIDER_X := 943.0
const DIVIDER_THICK := 20.0
const DIVIDER_TOP := 430.0
const DIVIDER_BOTTOM := 1845.0
const LANE_FLOOR_Y := 1858.0
const LANE_LEFT := 953.0
const LANE_RIGHT := 1040.0
const GATE_TOP := 258.0
const GATE_BOTTOM := 418.0

# --- lower playfield ---
const FLIPPER_PIVOT_L := Vector2(293.0, 1700.0)
const FLIPPER_PIVOT_R := Vector2(687.0, 1700.0)
const OUTLANE_X := 150.0
const OUTLANE_TOP := 1440.0
const OUTLANE_BOTTOM := 1580.0
const INLANE_END := Vector2(296.0, 1668.0)
const SLING_CORNER := Vector2(256.0, 1430.0)
const SLING_TOP := Vector2(368.0, 1430.0)
const SLING_BOTTOM := Vector2(256.0, 1560.0)
const MIRROR_X := 490.0

const DRAIN_Y := 1880.0
const DRAIN_HEIGHT := 24.0

var flipper_left: Flipper = null
var flipper_right: Flipper = null
var plunger: Plunger = null
var ball: Ball = null
var auto_respawn: bool = true
var balls_served: int = 0

var _walls: WallBuilder = null
var _gate: StaticBody2D = null
var _gate_closed: bool = true
var _from_lane: bool = false
var _respawn_in: float = -1.0
var _arch_center: Vector2 = Vector2.ZERO
var _arch_radius: float = 0.0
var _bumpers: Array[Bumper] = []


func segment_id() -> StringName:
	return &"alley_debug"


func bounds() -> Rect2:
	return Rect2(Vector2(PLAY_LEFT, 0.0), Vector2(LANE_RIGHT - PLAY_LEFT, PLAY_BOTTOM))


func spawn_point() -> Vector2:
	return Vector2((LANE_LEFT + LANE_RIGHT) * 0.5, LANE_FLOOR_Y - OUTER_THICK * 0.5 - Feel.BALL_RADIUS - 4.0)


func lane_rect() -> Rect2:
	return Rect2(Vector2(LANE_LEFT - 6.0, 240.0), Vector2(LANE_RIGHT - LANE_LEFT + 12.0, 1620.0))


func _ready() -> void:
	_arch_center = _circumcenter(ARCH_A, ARCH_B, ARCH_C)
	_arch_radius = _arch_center.distance_to(ARCH_A)
	_build_walls()
	_build_gate()
	_build_hardware()
	_build_flippers()
	_build_drain()
	plunger = Plunger.new()
	plunger.name = "Plunger"
	plunger.lane_rect = lane_rect()
	add_child(plunger)
	queue_redraw()


# ---------------------------------------------------------------- geometry

func _build_walls() -> void:
	var body := StaticBody2D.new()
	body.name = "Walls"
	body.collision_layer = Feel.LAYER_WALLS
	body.collision_mask = 0
	body.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, Feel.WALL_BOUNCE)
	add_child(body)
	_walls = WallBuilder.new(body)

	var off := OUTER_THICK * 0.5
	var a0 := _arch_angle(ARCH_A)
	var a1 := _arch_angle(ARCH_C)
	var r_out := _arch_radius + off
	var arch_start := _arch_center + Vector2(cos(a0), sin(a0)) * r_out
	var arch_end := _arch_center + Vector2(cos(a1), sin(a1)) * r_out

	_walls.arc(_arch_center, r_out, a0, a1, 56, OUTER_THICK)
	_walls.bar(Vector2(PLAY_LEFT - off, PLAY_BOTTOM + off), arch_start, OUTER_THICK)
	_walls.bar(Vector2(LANE_RIGHT + off, PLAY_BOTTOM + off), arch_end, OUTER_THICK)
	_walls.bar(Vector2(PLAY_LEFT - off, PLAY_BOTTOM + off),
			Vector2(PLAY_RIGHT, PLAY_BOTTOM + off), OUTER_THICK)
	_walls.bar(Vector2(DIVIDER_X, LANE_FLOOR_Y),
			Vector2(LANE_RIGHT + off, LANE_FLOOR_Y), OUTER_THICK)

	# lane / playfield divider
	_walls.bar(Vector2(DIVIDER_X, DIVIDER_TOP), Vector2(DIVIDER_X, DIVIDER_BOTTOM), DIVIDER_THICK)

	# in/out lane guides, both sides
	for s in [1.0, -1.0]:
		_walls.bar(_mx(OUTLANE_X, s, OUTLANE_TOP), _mx(OUTLANE_X, s, OUTLANE_BOTTOM), GUIDE_THICK)
		_walls.bar(_mx(OUTLANE_X, s, OUTLANE_BOTTOM),
				_mx(INLANE_END.x, s, INLANE_END.y), GUIDE_THICK)


func _build_gate() -> void:
	_gate = StaticBody2D.new()
	_gate.name = "OneWayGate"
	_gate.collision_layer = Feel.LAYER_WALLS
	_gate.collision_mask = 0
	_gate.physics_material_override = Feel.make_material(Feel.WALL_FRICTION, 0.1)
	add_child(_gate)
	var b := WallBuilder.new(_gate)
	b.bar(Vector2(DIVIDER_X, GATE_TOP), Vector2(DIVIDER_X, GATE_BOTTOM), 12.0)


func _build_hardware() -> void:
	var centers := [Vector2(490.0, 460.0), Vector2(368.0, 640.0), Vector2(612.0, 640.0)]
	for i in range(centers.size()):
		var b: Bumper = BUMPER_SCENE.instantiate()
		b.id = StringName("bumper_%d" % (i + 1))
		b.value = Feel.BUMPER_VALUE
		b.position = centers[i]
		b.name = "Bumper%d" % (i + 1)
		add_child(b)
		_bumpers.append(b)

	for s in [1.0, -1.0]:
		var sl: Slingshot = SLING_SCENE.instantiate()
		var id := &"sling_l" if s > 0.0 else &"sling_r"
		sl.configure(id,
			_mx(SLING_CORNER.x, s, SLING_CORNER.y),
			_mx(SLING_TOP.x, s, SLING_TOP.y),
			_mx(SLING_BOTTOM.x, s, SLING_BOTTOM.y))
		sl.value = Feel.SLING_VALUE
		sl.name = "SlingL" if s > 0.0 else "SlingR"
		add_child(sl)


func _build_flippers() -> void:
	flipper_left = FLIPPER_SCENE.instantiate()
	flipper_left.side = &"left"
	flipper_left.name = "FlipperLeft"
	flipper_left.position = FLIPPER_PIVOT_L
	add_child(flipper_left)

	flipper_right = FLIPPER_SCENE.instantiate()
	flipper_right.side = &"right"
	flipper_right.name = "FlipperRight"
	flipper_right.position = FLIPPER_PIVOT_R
	add_child(flipper_right)


func _build_drain() -> void:
	var area := Area2D.new()
	area.name = "Drain"
	area.collision_layer = Feel.LAYER_ZONES
	area.collision_mask = Feel.LAYER_BALL
	area.monitorable = false
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(PLAY_RIGHT - PLAY_LEFT, DRAIN_HEIGHT)
	cs.shape = rect
	cs.position = Vector2((PLAY_LEFT + PLAY_RIGHT) * 0.5, DRAIN_Y + DRAIN_HEIGHT * 0.5)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_drain_entered)


func _mx(x: float, s: float, y: float) -> Vector2:
	return Vector2(x if s > 0.0 else MIRROR_X * 2.0 - x, y)


func _arch_angle(p: Vector2) -> float:
	return (p - _arch_center).angle()


static func _circumcenter(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	var d := 2.0 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
	if absf(d) < 0.0001:
		return (a + b + c) / 3.0
	var a2 := a.length_squared()
	var b2 := b.length_squared()
	var c2 := c.length_squared()
	return Vector2(
		(a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
		(a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d
	)


# ---------------------------------------------------------------- ball service

func spawn_ball() -> Ball:
	despawn_ball()
	_respawn_in = -1.0
	var b: Ball = BALL_SCENE.instantiate()
	b.name = "Ball"
	b.position = spawn_point()
	add_child(b)
	ball = b
	balls_served += 1
	_from_lane = true
	_bind_ball()
	AudioDirector.play(&"ball_spawn")
	Events.ball_spawned.emit(b)
	ball_spawned.emit(b)
	return b


func despawn_ball() -> void:
	_respawn_in = -1.0
	if ball != null and is_instance_valid(ball):
		ball.queue_free()
	ball = null
	_bind_ball()


func _bind_ball() -> void:
	if flipper_left != null:
		flipper_left.set_ball(ball)
	if flipper_right != null:
		flipper_right.set_ball(ball)
	if plunger != null:
		plunger.set_ball(ball)


func _on_drain_entered(body: Node2D) -> void:
	if not (body is Ball) or body != ball:
		return
	var lost: Ball = body
	ball = null
	_bind_ball()
	lost.queue_free()
	AudioDirector.play(&"drain")
	Events.ball_drained.emit(lost)
	ball_lost.emit(lost)
	if auto_respawn:
		_respawn_in = Feel.RESPAWN_DELAY


func _physics_process(delta: float) -> void:
	if _respawn_in > 0.0:
		if not auto_respawn:
			_respawn_in = -1.0
		else:
			_respawn_in -= delta
			if _respawn_in <= 0.0:
				_respawn_in = -1.0
				spawn_ball()
	_update_gate()


## One-way gate: the arch dumps the ball leftward into the playfield and it must never get
## back into the shooter lane. Latched on where the ball came from, and only ever toggled
## while the ball is clear of the blade so the flap can't materialise inside it.
func _update_gate() -> void:
	if _gate == null:
		return
	var want_closed := true
	if ball != null and is_instance_valid(ball):
		var p := ball.global_position
		if p.x > LANE_RIGHT - 55.0:
			_from_lane = true
		elif p.x < DIVIDER_X - 53.0:
			_from_lane = false
		var in_window := p.x > DIVIDER_X - 63.0 and p.y > GATE_TOP - 52.0 and p.y < GATE_BOTTOM + 62.0
		want_closed = not (_from_lane and in_window)
		if want_closed and absf(p.x - DIVIDER_X) < 50.0:
			want_closed = _gate_closed        # hold: never close on top of the ball
	if want_closed == _gate_closed:
		return
	_gate_closed = want_closed
	_gate.collision_layer = Feel.LAYER_WALLS if want_closed else 0
	if not want_closed:
		AudioDirector.play(&"wall_tap")


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var a0 := _arch_angle(ARCH_A)
	var a1 := _arch_angle(ARCH_C)
	var felt := PackedVector2Array()
	felt.append(Vector2(PLAY_LEFT, PLAY_BOTTOM))
	felt.append(ARCH_A)
	for i in range(41):
		var ang := lerpf(a0, a1, float(i) / 40.0)
		felt.append(_arch_center + Vector2(cos(ang), sin(ang)) * _arch_radius)
	felt.append(Vector2(LANE_RIGHT, PLAY_BOTTOM))
	draw_colored_polygon(felt, Feel.COL_FELT)

	draw_rect(Rect2(Vector2(LANE_LEFT, DIVIDER_TOP), Vector2(LANE_RIGHT - LANE_LEFT,
			LANE_FLOOR_Y - DIVIDER_TOP)), Feel.COL_FELT.darkened(0.25))

	# lane markings so power bands are readable while playing
	for i in range(1, 4):
		var y := LANE_FLOOR_Y - float(i) * 380.0
		draw_line(Vector2(LANE_LEFT + 6.0, y), Vector2(LANE_RIGHT - 6.0, y),
				Feel.COL_BRASS.darkened(0.5), 2.0)

	if _walls != null:
		_walls.draw_into(self, Feel.COL_INK.lightened(0.12), Feel.COL_INK)

	var gate_col := Feel.COL_BRASS if _gate_closed else Feel.COL_BRASS.darkened(0.6)
	draw_line(Vector2(DIVIDER_X, GATE_TOP), Vector2(DIVIDER_X, GATE_BOTTOM), gate_col, 12.0)

	draw_line(Vector2(PLAY_LEFT, DRAIN_Y), Vector2(PLAY_RIGHT, DRAIN_Y),
			Feel.COL_DIRTY.darkened(0.35), 3.0)
