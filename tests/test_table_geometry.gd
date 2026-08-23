extends RefCounted
## Invariants of the M0 table layout that keep a 56 px ball out of trouble: every lane wide
## enough to pass, every wall thick enough not to be crossed in one 120 Hz tick, and the arch
## actually a circle through the three authored points.


func run(t: TestCtx) -> void:
	_walls_are_thick(t)
	_arch_is_a_circle(t)
	_lanes_fit_a_ball(t)
	_flippers(t)
	_mirror(t)
	_progression_keeps_the_alley(t)
	_progression_lanes_fit_a_ball(t)
	_progression_has_no_pinch_points(t)


func _walls_are_thick(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	var body := StaticBody2D.new()
	var b := WallBuilder.new(body)
	b.bar(Vector2.ZERO, Vector2(100.0, 0.0), 2.0)              # deliberately too thin
	b.bar(Vector2.ZERO, Vector2(0.0, 100.0), 40.0)
	b.arc(Vector2.ZERO, 200.0, 0.0, PI, 8, 24.0)
	b.chain(PackedVector2Array([Vector2.ZERO]), 30.0)          # degenerate: no shapes

	t.eq(b.chains.size(), 3, "degenerate chains are dropped")
	for c: Dictionary in b.chains:
		t.ok(float(c["thickness"]) >= WallBuilder.MIN_THICKNESS,
				"chain thickness clamped up to the minimum")
	t.ok(WallBuilder.MIN_THICKNESS >= 12.0, "walls are never thinner than 12 px")

	var shapes := 0
	for child in body.get_children():
		var cs: CollisionShape2D = child
		var cap: CapsuleShape2D = cs.shape
		t.ok(cap != null, "wall segments are capsules (no seams, no sharp joins)")
		if cap != null:
			t.ok(cap.radius * 2.0 >= WallBuilder.MIN_THICKNESS, "capsule honours the minimum")
			t.ok(cap.height >= cap.radius * 2.0, "capsule is at least as long as it is wide")
		shapes += 1
	t.eq(shapes, 1 + 1 + 8, "one capsule per polyline segment")
	t.ok(dia > WallBuilder.MIN_THICKNESS, "sanity: the ball is bigger than a wall is thick")
	body.free()


func _arch_is_a_circle(t: TestCtx) -> void:
	var a := AlleyDebugTable.ARCH_A
	var b := AlleyDebugTable.ARCH_B
	var c := AlleyDebugTable.ARCH_C
	var centre := AlleyDebugTable._circumcenter(a, b, c)
	var r := centre.distance_to(a)
	t.near(centre.distance_to(b), r, 0.01, "arch passes through its apex")
	t.near(centre.distance_to(c), r, 0.01, "arch passes through its right foot")
	t.ok(centre.y > b.y, "arch bulges upward")
	t.near(centre.x, (a.x + c.x) * 0.5, 0.01, "arch feet are level, so the centre is between them")

	# the shooter lane's ceiling must clear the divider by more than a ball
	var dx: float = AlleyDebugTable.DIVIDER_X - centre.x
	var ceiling: float = centre.y - sqrt(r * r - dx * dx)
	var divider_cap: float = AlleyDebugTable.DIVIDER_TOP - AlleyDebugTable.DIVIDER_THICK * 0.5
	t.ok(divider_cap - ceiling > Feel.BALL_RADIUS * 2.0 + 20.0,
			"gate opening (%.0f px) passes a ball with room to spare" % (divider_cap - ceiling))


func _lanes_fit_a_ball(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	var lane := AlleyDebugTable.LANE_RIGHT - AlleyDebugTable.LANE_LEFT
	t.ok(lane >= dia + 20.0, "shooter lane %.0f px wide" % lane)

	var guide_face: float = AlleyDebugTable.OUTLANE_X + AlleyDebugTable.GUIDE_THICK * 0.5
	var outlane: float = AlleyDebugTable.OUTLANE_X - AlleyDebugTable.GUIDE_THICK * 0.5 - AlleyDebugTable.PLAY_LEFT
	var inlane: float = AlleyDebugTable.SLING_OUTER_BOTTOM.x - guide_face
	t.ok(outlane >= dia + 20.0, "outlane %.0f px wide" % outlane)
	t.ok(inlane >= dia + 20.0, "inlane %.0f px wide" % inlane)

	# the inlane floor has to run out from under the slingshot, not seal against it
	var floor_from := Vector2(AlleyDebugTable.OUTLANE_X, AlleyDebugTable.OUTLANE_BOTTOM)
	var floor_to := AlleyDebugTable.INLANE_END
	var span := floor_to - floor_from
	var at_sling: float = floor_from.y + (AlleyDebugTable.SLING_OUTER_BOTTOM.x - floor_from.x) * span.y / span.x
	var head: float = at_sling - AlleyDebugTable.GUIDE_THICK * 0.5 / cos(span.angle()) - AlleyDebugTable.SLING_OUTER_BOTTOM.y
	t.ok(head >= dia, "inlane exit clears the slingshot corner by %.0f px" % head)

	# ...and it has to meet the flipper pivot without leaving a hole to fall into
	var gap := floor_to.distance_to(AlleyDebugTable.FLIPPER_PIVOT_L)
	t.ok(gap <= AlleyDebugTable.GUIDE_THICK * 0.5 + Feel.FLIPPER_PIVOT_RADIUS,
			"inlane guide overlaps the flipper pivot (gap %.1f px)" % gap)


func _flippers(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	var reach := Feel.FLIPPER_LENGTH * cos(deg_to_rad(Feel.FLIPPER_REST_DEG))
	var tip_l: float = AlleyDebugTable.FLIPPER_PIVOT_L.x + reach + Feel.FLIPPER_TIP_RADIUS
	var tip_r: float = AlleyDebugTable.FLIPPER_PIVOT_R.x - reach - Feel.FLIPPER_TIP_RADIUS
	var gap := tip_r - tip_l
	t.ok(gap > dia, "the drain gap (%.0f px) passes a ball" % gap)
	t.ok(gap < dia + 40.0, "the drain gap is not a barn door (%.0f px)" % gap)

	var drop: float = AlleyDebugTable.FLIPPER_PIVOT_L.y + Feel.FLIPPER_LENGTH * sin(deg_to_rad(Feel.FLIPPER_REST_DEG))
	t.ok(AlleyDebugTable.DRAIN_Y - drop > Feel.BALL_RADIUS * 2.0,
			"the drain sits clear below the bat tips")
	t.ok(Feel.FLIPPER_UP_TIME <= 0.045, "full extension inside the 45 ms feel budget")
	t.ok(Feel.FLIPPER_UP_EASE > 1.0, "the up-stroke front-loads its travel")
	t.ok(Feel.FLIPPER_PIVOT_RADIUS > Feel.FLIPPER_TIP_RADIUS, "the bat tapers toward the tip")


func _mirror(t: TestCtx) -> void:
	var m: float = AlleyDebugTable.MIRROR_X
	t.near(AlleyDebugTable.FLIPPER_PIVOT_L.x + AlleyDebugTable.FLIPPER_PIVOT_R.x, m * 2.0, 0.01,
			"flipper pivots mirror about the playfield centre")
	t.near(AlleyDebugTable.FLIPPER_PIVOT_L.y, AlleyDebugTable.FLIPPER_PIVOT_R.y, 0.01,
			"flipper pivots are level")
	t.ok(AlleyDebugTable.SLING_OUTER_BOTTOM.x < AlleyDebugTable.SLING_INNER.x,
			"the slingshot's kicker face points inward")
	# CLASSIC kick (device-feedback fix): the face normal must throw up-and-across —
	# a left sling that kicks toward its own outlane is a drain machine.
	var edge: Vector2 = AlleyDebugTable.SLING_OUTER_TOP - AlleyDebugTable.SLING_INNER
	var n: Vector2 = Vector2(-edge.y, edge.x).normalized()
	t.ok(n.x > 0.4 and n.y < -0.4,
			"left sling kicks up-and-inward (normal %s)" % n)
	# no surface may be shallower than its own friction coefficient or a ball parks on it
	var rake: float = absf(AlleyDebugTable.SLING_OUTER_TOP.y - AlleyDebugTable.SLING_INNER.y) \
			/ absf(AlleyDebugTable.SLING_INNER.x - AlleyDebugTable.SLING_OUTER_TOP.x)
	t.ok(rake > Feel.RUBBER_FRICTION + 0.15,
			"slingshot kicker face (slope %.2f) outruns rubber friction %.2f" % [rake, Feel.RUBBER_FRICTION])
	var floor_span := AlleyDebugTable.INLANE_END - Vector2(AlleyDebugTable.OUTLANE_X, AlleyDebugTable.OUTLANE_BOTTOM)
	t.ok(absf(floor_span.y / floor_span.x) > Feel.WALL_FRICTION + 0.15,
			"inlane floor (slope %.2f) delivers the ball instead of holding it" % absf(floor_span.y / floor_span.x))
	t.near(AlleyDebugTable.SLING_OUTER_TOP.x, AlleyDebugTable.SLING_OUTER_BOTTOM.x, 0.01,
			"the slingshot's outer edge is vertical — it is the inlane's inner wall")


# ------------------------------------------------------------ progression table

## The M1 table inherits the M0 lower third whole. These are tuned numbers with reasons
## written down in segments/alley_debug.gd's header; if one of them ever drifts apart from
## the other table, the feel sims and the growth sim would be measuring two machines.
func _progression_keeps_the_alley(t: TestCtx) -> void:
	t.eq(ProgressionTable.FLIPPER_PIVOT_L, AlleyDebugTable.FLIPPER_PIVOT_L, "left flipper pivot")
	t.eq(ProgressionTable.FLIPPER_PIVOT_R, AlleyDebugTable.FLIPPER_PIVOT_R, "right flipper pivot")
	t.eq(ProgressionTable.SLING_OUTER_TOP, AlleyDebugTable.SLING_OUTER_TOP, "slingshot outer top")
	t.eq(ProgressionTable.SLING_OUTER_BOTTOM, AlleyDebugTable.SLING_OUTER_BOTTOM, "slingshot outer bottom")
	t.eq(ProgressionTable.SLING_INNER, AlleyDebugTable.SLING_INNER, "slingshot inner vertex")
	t.eq(ProgressionTable.INLANE_END, AlleyDebugTable.INLANE_END, "inlane floor end")
	t.eq(ProgressionTable.OUTLANE_X, AlleyDebugTable.OUTLANE_X, "outlane guide x")
	t.eq(ProgressionTable.OUTLANE_TOP, AlleyDebugTable.OUTLANE_TOP, "outlane guide top")
	t.eq(ProgressionTable.OUTLANE_BOTTOM, AlleyDebugTable.OUTLANE_BOTTOM, "outlane guide bottom")
	t.eq(ProgressionTable.DRAIN_Y, AlleyDebugTable.DRAIN_Y, "drain line")
	t.eq(ProgressionTable.DIVIDER_TOP, AlleyDebugTable.DIVIDER_TOP, "divider cap (the plunge fix)")
	t.eq(ProgressionTable.DIVIDER_THICK, AlleyDebugTable.DIVIDER_THICK, "divider thickness")
	t.eq(ProgressionTable.GATE_TOP, AlleyDebugTable.GATE_TOP, "one-way gate top")
	t.eq(ProgressionTable.GATE_BOTTOM, AlleyDebugTable.GATE_BOTTOM, "one-way gate bottom")
	t.eq(ProgressionTable.ARCH_A, AlleyDebugTable.ARCH_A, "arch left foot")
	t.eq(ProgressionTable.ARCH_B, AlleyDebugTable.ARCH_B, "arch apex")
	t.eq(ProgressionTable.ARCH_C, AlleyDebugTable.ARCH_C, "arch right foot")
	t.eq(ProgressionTable.MIRROR_X, AlleyDebugTable.MIRROR_X, "playfield mirror line")

	var centre := ProgressionTable.circumcenter(
			ProgressionTable.ARCH_A, ProgressionTable.ARCH_B, ProgressionTable.ARCH_C)
	t.near(centre.x, ProgressionTable.ARCH_CENTER.x, 0.001, "cached arch centre x")
	t.near(centre.y, ProgressionTable.ARCH_CENTER.y, 0.001, "cached arch centre y")


## Every lane the M1 table adds has to pass a 56 px ball with room to spare.
func _progression_lanes_fit_a_ball(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	var wall_face: float = ProgressionTable.PLAY_LEFT + ProgressionTable.OUTER_THICK * 0.5
	var guide_face: float = ProgressionTable.LANE_GUIDE_X - ProgressionTable.GUIDE_THICK * 0.5
	t.near(guide_face - wall_face, ProgressionTable.CHANNEL_WIDTH, 0.001,
			"the numbers lane is CHANNEL_WIDTH wide")
	t.ok(guide_face - wall_face >= dia + 20.0,
			"numbers lane %.0f px wide" % (guide_face - wall_face))

	# the getaway arc keeps the same channel width all the way round the top
	var arch_inner: float = ProgressionTable.ARCH_CENTER.distance_to(ProgressionTable.ARCH_A) \
			- ProgressionTable.OUTER_THICK * 0.5
	var arc_outer: float = ProgressionTable.ORBIT_ARC_RADIUS + ProgressionTable.GUIDE_THICK * 0.5
	t.ok(arch_inner - arc_outer >= dia + 20.0,
			"orbit channel %.0f px wide at the arch" % (arch_inner - arc_outer))

	var posts: PackedFloat32Array = ProgressionTable.ROLLOVER_POST_X
	for i in range(posts.size() - 1):
		var lane: float = posts[i + 1] - posts[i] - ProgressionTable.ROLLOVER_POST_THICK
		t.ok(lane >= dia + 20.0, "top lane %d is %.0f px wide" % [i + 1, lane])

	# the storefront banks must leave real routes through the midfield, not a wall
	var half := Storefront.TARGET_PITCH + Storefront.TARGET_LENGTH * 0.5
	var edges: Array[Vector2] = []
	for i in range(ProgressionTable.STOREFRONT_AT.size()):
		var centre: Vector2 = ProgressionTable.STOREFRONT_AT[i]
		var reach: float = half * cos(deg_to_rad(ProgressionTable.STOREFRONT_RAKE[i]))
		edges.append(Vector2(centre.x - reach, centre.x + reach))
	for i in range(edges.size() - 1):
		var gap: float = edges[i + 1].x - edges[i].y
		t.ok(gap >= dia + 20.0, "midfield gap %d is %.0f px" % [i + 1, gap])
	t.ok(edges[0].x - (ProgressionTable.LANE_GUIDE_X + ProgressionTable.GUIDE_THICK * 0.5)
			>= dia + 20.0, "the route between the numbers lane and Lucky's passes a ball")


## A gap is either a route or a wall — never ball-sized, which is where a ball wedges and
## the night quietly ends.
func _progression_has_no_pinch_points(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	var centre: Vector2 = ProgressionTable.ARCH_CENTER
	var arc_inner: float = ProgressionTable.ORBIT_ARC_RADIUS - ProgressionTable.GUIDE_THICK * 0.5

	# the top-lane posts sit inside the getaway arc: prove they are clear of it
	for x: float in ProgressionTable.ROLLOVER_POST_X:
		var top := Vector2(x, ProgressionTable.ROLLOVER_POST_TOP)
		var clearance: float = arc_inner - centre.distance_to(top) \
				- ProgressionTable.ROLLOVER_POST_THICK * 0.5
		t.ok(clearance >= dia or clearance <= 0.0,
				"post at x=%.0f leaves a %.0f px pinch under the orbit arc" % [x, clearance])

	# the right-hand storefront and the wire bank stop short of the divider by less than a
	# ball, so nothing can crawl in behind them
	var half := Storefront.TARGET_PITCH + Storefront.TARGET_LENGTH * 0.5
	var pawn: Vector2 = ProgressionTable.STOREFRONT_AT[2]
	var pawn_right: float = pawn.x + half * cos(deg_to_rad(ProgressionTable.STOREFRONT_RAKE[2]))
	t.ok(ProgressionTable.PLAY_RIGHT - pawn_right < dia,
			"Fat Tony's leaves a %.0f px slot against the divider"
			% (ProgressionTable.PLAY_RIGHT - pawn_right))

	# the payphones are close enough together to read as one bank and to seal
	var wire: PackedFloat32Array = ProgressionTable.WIRE_Y
	for i in range(wire.size() - 1):
		var gap: float = wire[i + 1] - wire[i] - ProgressionTable.TARGET_LENGTH
		t.ok(gap < dia, "payphones %d and %d leave a %.0f px slot" % [i + 1, i + 2, gap])

	# the wire bank still leaves the right-hand lane open
	var corridor: float = ProgressionTable.PLAY_RIGHT - ProgressionTable.WIRE_X \
			- Feel.BALL_RADIUS * 0.5
	t.ok(corridor >= dia, "the lane outside the payphones is %.0f px" % corridor)
