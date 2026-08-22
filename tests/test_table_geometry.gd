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
	var inlane: float = AlleyDebugTable.SLING_CORNER.x - guide_face
	t.ok(outlane >= dia + 20.0, "outlane %.0f px wide" % outlane)
	t.ok(inlane >= dia + 20.0, "inlane %.0f px wide" % inlane)

	# the inlane floor has to run out from under the slingshot, not seal against it
	var floor_from := Vector2(AlleyDebugTable.OUTLANE_X, AlleyDebugTable.OUTLANE_BOTTOM)
	var floor_to := AlleyDebugTable.INLANE_END
	var span := floor_to - floor_from
	var at_sling: float = floor_from.y + (AlleyDebugTable.SLING_BOTTOM.x - floor_from.x) * span.y / span.x
	var head: float = at_sling - AlleyDebugTable.GUIDE_THICK * 0.5 / cos(span.angle()) - AlleyDebugTable.SLING_BOTTOM.y
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
	t.ok(AlleyDebugTable.SLING_CORNER.x < AlleyDebugTable.SLING_TOP.x,
			"the slingshot's kicker face points inward")
	# no surface may be shallower than its own friction coefficient or a ball parks on it
	var rake: float = absf(AlleyDebugTable.SLING_CORNER.y - AlleyDebugTable.SLING_TOP.y) \
			/ absf(AlleyDebugTable.SLING_TOP.x - AlleyDebugTable.SLING_CORNER.x)
	t.ok(rake > Feel.RUBBER_FRICTION + 0.15,
			"slingshot top edge (slope %.2f) outruns rubber friction %.2f" % [rake, Feel.RUBBER_FRICTION])
	var floor_span := AlleyDebugTable.INLANE_END - Vector2(AlleyDebugTable.OUTLANE_X, AlleyDebugTable.OUTLANE_BOTTOM)
	t.ok(absf(floor_span.y / floor_span.x) > Feel.WALL_FRICTION + 0.15,
			"inlane floor (slope %.2f) delivers the ball instead of holding it" % absf(floor_span.y / floor_span.x))
	t.near(AlleyDebugTable.SLING_CORNER.x, AlleyDebugTable.SLING_BOTTOM.x, 0.01,
			"the slingshot's outer edge is vertical — it is the inlane's inner wall")
