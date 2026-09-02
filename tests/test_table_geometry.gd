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
	_progression_control_zone(t)
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

## The progression table is deliberately a different physical machine from the M0 feel
## fixture. Guard its own lower-field promises: higher control, two viable feeds, and an
## authored centre drain rather than accidental empty space below the bats.
func _progression_control_zone(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	t.ok(ProgressionTable.FLIPPER_PIVOT_L.y <= AlleyDebugTable.FLIPPER_PIVOT_L.y - 60.0,
			"the progression bats establish a materially higher control line")
	t.near(ProgressionTable.FLIPPER_PIVOT_L.x + ProgressionTable.FLIPPER_PIVOT_R.x,
			ProgressionTable.MIRROR_X * 2.0, 0.01, "the main bats mirror about the drain")
	t.near(ProgressionTable.FLIPPER_PIVOT_L.y, ProgressionTable.FLIPPER_PIVOT_R.y,
			0.01, "the main bats share a cradle line")

	var wall_face := ProgressionTable.PLAY_LEFT + ProgressionTable.OUTER_THICK * 0.5
	var guide_left := ProgressionTable.OUTLANE_X - ProgressionTable.GUIDE_THICK * 0.5
	var guide_right := ProgressionTable.OUTLANE_X + ProgressionTable.GUIDE_THICK * 0.5
	t.ok(guide_left - wall_face >= dia + 20.0,
			"the redesigned left outlane passes a ball with room")
	t.ok(ProgressionTable.SLING_OUTER_BOTTOM.x - guide_right >= dia + 20.0,
			"the redesigned left inlane passes a ball with room")
	var floor_to_pivot := ProgressionTable.INLANE_END.distance_to(
			ProgressionTable.FLIPPER_PIVOT_L)
	t.ok(floor_to_pivot <= ProgressionTable.GUIDE_THICK * 0.5 + Feel.FLIPPER_PIVOT_RADIUS,
			"the new return feed meets the flipper pivot")

	var reach := Feel.FLIPPER_LENGTH * ProgressionTable.FLIPPER_SCALE \
			* cos(deg_to_rad(Feel.FLIPPER_REST_DEG))
	var tip := Feel.FLIPPER_TIP_RADIUS * ProgressionTable.FLIPPER_SCALE
	var tip_l := ProgressionTable.FLIPPER_PIVOT_L.x + reach + tip
	var tip_r := ProgressionTable.FLIPPER_PIVOT_R.x - reach - tip
	var gap := tip_r - tip_l
	t.ok(gap >= dia + 20.0 and gap <= dia + 45.0,
			"the new centre drain mouth is playable (%.0f px)" % gap)
	t.near(ProgressionTable.CENTRE_DRAIN_AT.x, ProgressionTable.MIRROR_X, 0.01,
			"the visible centre grate sits under the bat gap")
	var tip_drop := ProgressionTable.FLIPPER_PIVOT_L.y \
			+ Feel.FLIPPER_LENGTH * ProgressionTable.FLIPPER_SCALE \
			* sin(deg_to_rad(Feel.FLIPPER_REST_DEG))
	var drain_top := ProgressionTable.CENTRE_DRAIN_AT.y \
			- ProgressionTable.CENTRE_DRAIN_SIZE.y * 0.5
	t.ok(drain_top - Feel.BALL_RADIUS - tip_drop >= Feel.BALL_RADIUS,
			"the centre drain switch sits below the resting bat tips")

	# The shell and plunge gate still share the cabinet frame with the feel fixture.
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

	# the Truck Route is the numbers lane's twin down the right side
	var guide_r_face: float = ProgressionTable.LANE_GUIDE_R_X + ProgressionTable.GUIDE_THICK * 0.5
	var right_lane: float = ProgressionTable.PLAY_RIGHT - guide_r_face
	t.ok(right_lane >= dia + 20.0, "truck route lane %.0f px wide" % right_lane)

	# the inner ring meets both lane guides tangentially, so the channel never necks down
	var ring_c: Vector2 = ProgressionTable.INNER_ARC_CENTER
	var ring_r: float = ProgressionTable.INNER_ARC_RADIUS
	t.near(ring_c.x - ring_r, ProgressionTable.LANE_GUIDE_X, 0.001, "ring meets the left guide")
	t.near(ring_c.x + ring_r, ProgressionTable.LANE_GUIDE_R_X, 0.001, "ring meets the right guide")
	t.near(ring_c.y, ProgressionTable.LANE_GUIDE_TOP, 0.001, "guides start at the ring's equator")
	var arch_top: float = ProgressionTable.ARCH_CENTER.y \
			- ProgressionTable.ARCH_CENTER.distance_to(ProgressionTable.ARCH_A) \
			+ ProgressionTable.OUTER_THICK * 0.5
	var ring_top: float = ring_c.y - ring_r - ProgressionTable.GUIDE_THICK * 0.5
	t.ok(ring_top - arch_top >= dia + 20.0,
			"orbit channel %.0f px deep over the top lanes" % (ring_top - arch_top))

	# the top lanes hang off the ring and open onto the bumper nest
	for i in range(ProgressionTable.ROLLOVER_POST_FROM.size() - 1):
		var gap_from: float = ProgressionTable.ROLLOVER_POST_FROM[i].distance_to(
				ProgressionTable.ROLLOVER_POST_FROM[i + 1]) - ProgressionTable.ROLLOVER_POST_THICK
		var gap_to: float = ProgressionTable.ROLLOVER_POST_TO[i].distance_to(
				ProgressionTable.ROLLOVER_POST_TO[i + 1]) - ProgressionTable.ROLLOVER_POST_THICK
		var lane: float = minf(gap_from, gap_to)
		t.ok(lane >= dia + 20.0, "top lane %d is %.0f px at its narrow end" % [i + 1, lane])
	for top: Vector2 in ProgressionTable.ROLLOVER_POST_FROM:
		t.near(ring_c.distance_to(top), ring_r, 0.5, "post at %s hangs from the ring" % str(top))
	for i in range(ProgressionTable.ROLLOVER_AT.size()):
		var at: Vector2 = ProgressionTable.ROLLOVER_AT[i]
		var lo: float = maxf(ProgressionTable.ROLLOVER_POST_FROM[i].x, ProgressionTable.ROLLOVER_POST_TO[i].x)
		var hi: float = minf(ProgressionTable.ROLLOVER_POST_FROM[i + 1].x, ProgressionTable.ROLLOVER_POST_TO[i + 1].x)
		t.ok(at.x > lo and at.x < hi, "rollover %d sits inside its lane" % (i + 1))

	# the storefront banks must leave real routes through the midfield, not a wall: the
	# closest approach of any two target rows passes a ball with room
	var half := Storefront.TARGET_PITCH + Storefront.TARGET_LENGTH * 0.5
	for i in range(ProgressionTable.STOREFRONT_AT.size()):
		for j in range(i + 1, ProgressionTable.STOREFRONT_AT.size()):
			var a := _bank_ends(i, half)
			var b := _bank_ends(j, half)
			var closest: Vector2 = Geometry2D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])[0]
			var other: Vector2 = Geometry2D.get_closest_points_between_segments(a[0], a[1], b[0], b[1])[1]
			var gap: float = closest.distance_to(other) - 20.0
			t.ok(gap >= dia + 20.0,
					"storefront route %d/%d is %.0f px" % [i + 1, j + 1, gap])
	var leftmost: float = INF
	for i in range(ProgressionTable.STOREFRONT_AT.size()):
		leftmost = minf(leftmost, ProgressionTable.STOREFRONT_AT[i].x - half)
	t.ok(leftmost - (ProgressionTable.LANE_GUIDE_X + ProgressionTable.GUIDE_THICK * 0.5)
			>= dia + 20.0, "the route between the numbers lane and the Block passes a ball")

	# Lucky's lower end and the docks roof: a route, never a V a ball can wedge into
	var lucky := _bank_ends(0, half)
	var low: Vector2 = lucky[0] if lucky[0].y > lucky[1].y else lucky[1]
	var roof_y: float = Docks.ROOF_FROM.y + (low.x - Docks.ROOF_FROM.x) \
			* (Docks.ROOF_TO.y - Docks.ROOF_FROM.y) / (Docks.ROOF_TO.x - Docks.ROOF_FROM.x)
	var roof_gap: float = roof_y - Docks.WALL_THICK * 0.5 - low.y - 10.0
	t.ok(roof_gap >= dia + 20.0, "Lucky's clears the docks roof by %.0f px" % roof_gap)

	# the centre alley under Nonna's stays open felt down to the flippers: neither side bank's
	# inner end reaches into the 80 px column on the mirror line
	var alley := 40.0
	for i in [0, 2]:
		var ends := _bank_ends(i, half)
		var inner: float = INF
		for e: Vector2 in ends:
			inner = minf(inner, absf(e.x - ProgressionTable.MIRROR_X))
		t.ok(inner - 10.0 >= alley, "bank %d reaches to %.0f px of the centre alley" % [i + 1, inner])


## The two ends of a storefront's target row in table space (thickness not included).
func _bank_ends(i: int, half: float) -> Array:
	var at: Vector2 = ProgressionTable.STOREFRONT_AT[i]
	var facing: Vector2 = (ProgressionTable.STOREFRONT_FACING[i] as Vector2).normalized()
	var rot: float = facing.angle() - PI * 0.5 + deg_to_rad(ProgressionTable.STOREFRONT_RAKE[i])
	var axis := Vector2.RIGHT.rotated(rot) * half
	return [at - axis, at + axis]


## A gap is either a route or a wall — never ball-sized, which is where a ball wedges and
## the night quietly ends.
func _progression_has_no_pinch_points(t: TestCtx) -> void:
	var dia := Feel.BALL_RADIUS * 2.0
	var ring_c: Vector2 = ProgressionTable.INNER_ARC_CENTER
	var ring_inner: float = ProgressionTable.INNER_ARC_RADIUS - ProgressionTable.GUIDE_THICK * 0.5

	# the top-lane posts start on the ring: either inside its thickness (a wall) or a full ball
	# clear of it (a route), never a slot
	for top: Vector2 in ProgressionTable.ROLLOVER_POST_FROM:
		var clearance: float = ring_inner - ring_c.distance_to(top) \
				- ProgressionTable.ROLLOVER_POST_THICK * 0.5
		t.ok(clearance >= dia or clearance <= 0.0,
				"post at %s leaves a %.0f px pinch under the ring" % [str(top), clearance])

	# the outer posts and the ring's arms make a notch each side of the lanes; its floor
	# opening (post bottom to the arm) must pass a ball, not hold one
	var posts_to: Array = ProgressionTable.ROLLOVER_POST_TO
	for side in [[0, -1.0], [posts_to.size() - 1, 1.0]]:
		var bottom: Vector2 = posts_to[side[0]]
		var dy: float = ring_c.y - bottom.y
		var arm_x: float = ring_c.x + float(side[1]) * sqrt(maxf(
				ProgressionTable.INNER_ARC_RADIUS * ProgressionTable.INNER_ARC_RADIUS - dy * dy, 0.0))
		var opening: float = absf(arm_x - bottom.x) - ProgressionTable.GUIDE_THICK * 0.5 \
				- ProgressionTable.ROLLOVER_POST_THICK * 0.5
		t.ok(opening >= dia + 20.0, "notch beside post %d opens %.0f px" % [side[0] + 1, opening])

	# Fat Tony's is sealed against the truck-route guide so nothing can crawl in behind it
	var half := Storefront.TARGET_PITCH + Storefront.TARGET_LENGTH * 0.5
	var pawn: Vector2 = ProgressionTable.STOREFRONT_AT[2]
	var guide_r_face: float = ProgressionTable.LANE_GUIDE_R_X - ProgressionTable.GUIDE_THICK * 0.5
	t.ok(guide_r_face - (pawn.x + half) < dia,
			"Fat Tony's leaves a %.0f px slot against the truck-route guide"
			% (guide_r_face - (pawn.x + half)))

	# the payphones are close enough together to read as one bank and to seal, and each
	# one's back is sealed against the guide
	var wire: Array = ProgressionTable.WIRE_AT
	for i in range(wire.size() - 1):
		var gap: float = wire[i + 1].distance_to(wire[i]) \
				- (ProgressionTable.WIRE_LENGTHS[i] + ProgressionTable.WIRE_LENGTHS[i + 1]) * 0.5
		t.ok(gap < dia, "payphones %d and %d leave a %.0f px slot" % [i + 1, i + 2, gap])
	for i in range(wire.size()):
		var reach: float = absf(ProgressionTable.WIRE_FACE.y) * ProgressionTable.WIRE_LENGTHS[i] * 0.5
		var behind: float = guide_r_face - (wire[i].x + reach)
		t.ok(behind < dia and behind >= 0.0, "payphone %d sits %.0f px off the guide" % [i + 1, behind])
