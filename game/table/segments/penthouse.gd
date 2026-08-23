class_name Penthouse
extends Node2D
## THE PENTHOUSE — the top floor (docs/02 §2 R6, specs/m3-fall-rise.md TABLE-3).
##
## The Club deck deliberately left the left half of the sky empty; this is what it was being
## kept for. A glass room over the skyline, quiet where everything below it is loud: five
## chairs around a long table — the Five Families — and the Sit-Down saucer at the low end of
## the floor where the negotiation happens.
##
## Getting up: **not** the staircase. The Penthouse hangs off the Club's own orbit — a
## wireform out of the deck's ceiling channel, taken only by a ball still carrying real lap
## pace. A staircase arrival (`ClubDeck.STAIR_RELEASE_SPEED`) is deliberately far too slow for
## it, so coming up the stairs still deals you into the wheel exactly as the Club intends; you
## have to earn the room with a lap. Getting down: the room's floor is a ridge, and its
## down-field side runs into a return wireform that puts the ball back on the deck, still in
## play. Falling out of the Penthouse costs you the room, never the ball.
##
## Two rows of chairs, offset, are the whole shot layout: the upper three leave two routes
## between them, the lower two leave three, and no route lines up with the one above it — so a
## ball entering the room has to be worked down rather than dropped through. Every chair is
## either raked past the friction slope or stood vertically, because five long bars across a
## room is five places for a night to end.
##
## Modes are FLOW-3's: this ships geometry, switches and signals. Chairs report through a
## TargetBank so "who is still standing" is one call, and the Sit-Down reports its capture.

## A chair was taken (0-based), and the whole Commission was seated.
signal chair_taken(index: int)
signal chairs_completed()
## The Sit-Down saucer has the ball. Flow starts the negotiation on this.
signal sitdown_entered()
## The ball arrived from the Club (crest) / left down the return lane.
signal penthouse_entered(speed: float)
signal penthouse_returned()

# ------------------------------------------------------------------ hardware ids
const ID_PENTHOUSE := &"penthouse"
const ID_CHAIRS := &"commission_chairs"
const ID_SITDOWN := &"sitdown_saucer"
const ID_STAIRS := &"penthouse_stairs"

# ------------------------------------------------------------------ the room
const ROOM_LEFT := 40.0
const ROOM_RIGHT := 512.0
const ROOM_TOP := -880.0
const ROOM_BOTTOM := -466.0
const WALL_THICK := 30.0
## The floor is a ridge, not a bowl: its apex sheds either way, and which way decides whether
## the ball gets the Sit-Down or the ride home.
const FLOOR_LEFT := Vector2(55.0, -486.0)
const FLOOR_APEX := Vector2(300.0, -540.0)
const FLOOR_RIGHT := Vector2(497.0, -490.0)
const FLOOR_THICK := 24.0

# ------------------------------------------------------------------ the Commission
const CHAIR_LENGTH := 50.0
const CHAIR_THICK := 18.0
const CHAIR_ROW_A_Y := -764.0
const CHAIR_ROW_B_Y := -644.0
const CHAIR_ROW_A_X: PackedFloat32Array = [132.0, 276.0, 420.0]
const CHAIR_ROW_B_X: PackedFloat32Array = [204.0, 348.0]
## A standup is rubber (0.30), not wall (0.14): 14° holds a ball on its back for the rest of
## the night — a soak found one asleep on a chair for 3.4 s and climbing. 22° is the rake the
## raid's cop targets already use for the same reason.
const CHAIR_ROW_A_RAKE: PackedFloat32Array = [22.0, -22.0, 22.0]
const CHAIR_ROW_B_RAKE: PackedFloat32Array = [-22.0, 22.0]
## The long table itself is paint — a collider in the middle of the room would be a shelf.
const TABLE_AT := Vector2(276.0, -704.0)
const TABLE_SIZE := Vector2(300.0, 70.0)

const SITDOWN_AT := Vector2(110.0, -540.0)
const SITDOWN_R := 40.0
const SITDOWN_HOLD := 1.0
const SITDOWN_EJECT := Vector2(0.55, -0.84)
const SITDOWN_SPEED := 760.0

# ------------------------------------------------------------------ getting up and down
## The mouth lies in the Club's ceiling channel, west of the rounded corner.
const STAIR_MOUTH := Vector2(800.0, -806.0)
const STAIR_MOUTH_SIZE := Vector2(96.0, 80.0)
## Far above `ClubDeck.STAIR_RELEASE_SPEED` (480) on purpose: the Club's own staircase must
## still feed the wheel, so only a lap with pace left in it is taken up here.
const STAIR_ENTRY_SPEED := 900.0
const STAIR_CLIMB_GRAVITY := 420.0
const STAIR_MAX_SPEED := 1700.0
const STAIR_RELEASE_SPEED := 420.0
const STAIR_PATH: PackedVector2Array = [
	Vector2(800.0, -806.0), Vector2(700.0, -826.0), Vector2(600.0, -846.0),
	Vector2(500.0, -852.0), Vector2(400.0, -844.0), Vector2(330.0, -812.0),
	Vector2(312.0, -770.0),
]
const RETURN_CATCH_AT := Vector2(430.0, -556.0)
const RETURN_CATCH_SIZE := Vector2(150.0, 72.0)
const RETURN_MIN_FORWARD := 560.0
const RETURN_MAX_SPEED := 1300.0
const RETURN_RELEASE_SPEED := 380.0
const RETURN_GRAVITY := 700.0
## Lands in the Club's left lane, above the mini bats: you come back down into play.
const RETURN_PATH: PackedVector2Array = [
	Vector2(430.0, -556.0), Vector2(497.0, -524.0), Vector2(545.0, -478.0),
	Vector2(585.0, -424.0), Vector2(604.0, -368.0), Vector2(610.0, -306.0),
]

# ------------------------------------------------------------------ look (docs/07 §1)
const COL_GLASS := Color("2A3550")

var chairs: TargetBank = null
var sitdown: HoldSaucer = null
var stairs: RampLane = null
var return_lane: RampLane = null

var _present: bool = false
var _shell: WallPiece = null
var _ball: Ball = null


# ====================================================================== build =====


func _ready() -> void:
	_build_shell()
	_build_chairs()
	_build_sitdown()
	_build_ramps()


func _build_shell() -> void:
	_shell = WallPiece.new()
	_shell.name = "PenthouseShell"
	_shell.color = COL_GLASS.lightened(0.10)
	add_child(_shell)
	_shell.bar(Vector2(ROOM_LEFT, ROOM_TOP), Vector2(ROOM_RIGHT, ROOM_TOP), WALL_THICK)
	_shell.bar(Vector2(ROOM_LEFT, ROOM_TOP), Vector2(ROOM_LEFT, ROOM_BOTTOM), WALL_THICK)
	_shell.bar(Vector2(ROOM_RIGHT, ROOM_TOP), Vector2(ROOM_RIGHT, ROOM_BOTTOM), WALL_THICK)
	_shell.chain(PackedVector2Array([FLOOR_LEFT, FLOOR_APEX, FLOOR_RIGHT]), FLOOR_THICK)


func _build_chairs() -> void:
	chairs = TargetBank.new()
	chairs.name = "CommissionChairs"
	chairs.id = ID_CHAIRS
	chairs.group = TableScore.GROUP_PENTHOUSE
	chairs.target_value = TableScore.PENTHOUSE_CHAIR
	# The table pays for a chair; claiming the Commission across Nights is FLOW-3's, so there
	# is no table-side completion bonus to double-count against it.
	chairs.complete_value = 0.0
	chairs.reset_seconds = 8.0
	add_child(chairs)
	for i in range(CHAIR_ROW_A_X.size()):
		chairs.add_target(_make_chair(i, Vector2(CHAIR_ROW_A_X[i], CHAIR_ROW_A_Y),
				CHAIR_ROW_A_RAKE[i]))
	for i in range(CHAIR_ROW_B_X.size()):
		chairs.add_target(_make_chair(CHAIR_ROW_A_X.size() + i,
				Vector2(CHAIR_ROW_B_X[i], CHAIR_ROW_B_Y), CHAIR_ROW_B_RAKE[i]))
	chairs.target_struck.connect(func(index: int) -> void:
		AudioDirector.play(&"chair_take")
		chair_taken.emit(index))
	chairs.bank_completed.connect(func() -> void: chairs_completed.emit())


func _make_chair(index: int, at: Vector2, rake_deg: float) -> StandupTarget:
	var t := StandupTarget.new()
	t.name = "Chair%d" % (index + 1)
	t.thickness = CHAIR_THICK
	t.configure(StringName("%s_%d" % [ID_CHAIRS, index + 1]), at,
			Vector2.UP.rotated(deg_to_rad(rake_deg)), CHAIR_LENGTH)
	return t


func _build_sitdown() -> void:
	sitdown = HoldSaucer.new()
	sitdown.name = "SitDown"
	sitdown.hold_seconds = SITDOWN_HOLD
	sitdown.eject_speed = SITDOWN_SPEED
	sitdown.configure(ID_SITDOWN, SITDOWN_AT, SITDOWN_R, SITDOWN_EJECT)
	add_child(sitdown)
	sitdown.captured.connect(func() -> void:
		AudioDirector.play(&"sitdown")
		sitdown_entered.emit())


func _build_ramps() -> void:
	stairs = RampLane.new()
	stairs.name = "PenthouseStairs"
	stairs.entry_speed = STAIR_ENTRY_SPEED
	stairs.climb_gravity = STAIR_CLIMB_GRAVITY
	stairs.max_speed = STAIR_MAX_SPEED
	stairs.release_speed = STAIR_RELEASE_SPEED
	stairs.entry_center = STAIR_MOUTH
	stairs.entry_size = STAIR_MOUTH_SIZE
	stairs.abort_at = STAIR_MOUTH
	stairs.color = Feel.COL_BRASS.lightened(0.10)
	stairs.configure(ID_STAIRS, STAIR_PATH)
	add_child(stairs)
	stairs.crested.connect(_on_stairs_crested)

	return_lane = RampLane.new()
	return_lane.name = "PenthouseReturn"
	return_lane.entry_speed = -100000.0        # the room's down-field lip: it takes anything
	return_lane.climb_gravity = RETURN_GRAVITY
	return_lane.max_speed = RETURN_MAX_SPEED
	return_lane.min_forward = RETURN_MIN_FORWARD
	return_lane.release_speed = RETURN_RELEASE_SPEED
	return_lane.entry_center = RETURN_CATCH_AT
	return_lane.entry_size = RETURN_CATCH_SIZE
	return_lane.abort_at = RETURN_PATH[RETURN_PATH.size() - 1]
	return_lane.color = COL_GLASS.lightened(0.35)
	return_lane.configure(&"penthouse_return", RETURN_PATH)
	add_child(return_lane)
	return_lane.crested.connect(_on_returned)


# ================================================================== the table =====


func set_ball(b: Ball) -> void:
	_ball = b
	for holder: Node in [sitdown, stairs, return_lane]:
		if holder != null:
			holder.call(&"set_ball", b)


## Every switchable piece of the room, as the table's `_register` wants them: each also needs
## `penthouse`, which in turn needs the Club under it — there is no other way up.
func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_CHAIRS], "node": chairs},
		{"ids": [ID_SITDOWN], "node": sitdown},
		{"ids": [ID_STAIRS], "node": stairs},
	]


func bounds() -> Rect2:
	return Rect2(Vector2(ROOM_LEFT - WALL_THICK * 0.5, ROOM_TOP - WALL_THICK * 0.5),
			Vector2(ROOM_RIGHT - ROOM_LEFT + WALL_THICK, ROOM_BOTTOM - ROOM_TOP + WALL_THICK))


func chairs_standing() -> int:
	if chairs == null:
		return 0
	return chairs.targets().size() - chairs.marked_count()


func holds_ball() -> bool:
	if sitdown != null and sitdown.holds_ball():
		return true
	if stairs != null and stairs.riding():
		return true
	return return_lane != null and return_lane.riding()


## A ball in the Sit-Down or on either wireform is resting on purpose; the coils downstairs
## must not reach up here and rob a negotiation mid-hold.
func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	return BallHold.is_held(ball) and holds_ball()


func _on_stairs_crested(speed: float) -> void:
	AudioDirector.play(&"staircase_crest")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, ID_STAIRS, _ball, speed)
	penthouse_entered.emit(speed)


func _on_returned(_speed: float) -> void:
	AudioDirector.play(&"wall_tap")
	penthouse_returned.emit()


# =================================================================== dormancy =====


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for piece: Node in [_shell, return_lane]:
		if piece != null:
			Dormant.apply(piece, active)
	if not active:
		_release_everything()


func is_hardware_active() -> bool:
	return _present


## Switching the room off while it holds the ball would leave it standing in the sky. Every
## holder hands it back, and then it is put down at the foot of the return — on the Club deck,
## which is the only place a ball up here can legally be.
func _release_everything() -> void:
	var was_holding := holds_ball()
	for holder: Node in [sitdown, stairs, return_lane]:
		if holder != null and holder.has_method(&"set_hardware_active"):
			holder.call(&"set_hardware_active", false)
	if was_holding and _ball != null and is_instance_valid(_ball):
		BallHold.release(_ball, RETURN_PATH[RETURN_PATH.size() - 1], Vector2.ZERO)


# ==================================================================== drawing =====


func _draw() -> void:
	var inset := WALL_THICK * 0.5
	var pts := PackedVector2Array([
		Vector2(ROOM_LEFT + inset, ROOM_TOP + inset),
		Vector2(ROOM_RIGHT - inset, ROOM_TOP + inset),
		Vector2(ROOM_RIGHT - inset, FLOOR_RIGHT.y),
		FLOOR_APEX, FLOOR_LEFT,
	])
	# Glass over the skyline: the room is a tint, not a lid, so the painted city behind the
	# Club still reads through it (docs/02 §4 "glassy and quiet").
	draw_colored_polygon(pts, Color(COL_GLASS.r, COL_GLASS.g, COL_GLASS.b, 0.82))
	# Floor-to-ceiling windows: a quiet skyline grid behind the dangerous furniture.
	for i in range(7):
		var x := lerpf(ROOM_LEFT + 60.0, ROOM_RIGHT - 60.0, float(i) / 6.0)
		draw_line(Vector2(x, ROOM_TOP + inset), Vector2(x - 26.0, FLOOR_APEX.y - 30.0),
				Color(1.0, 1.0, 1.0, 0.05), 18.0)
	for i in range(3):
		var y := ROOM_TOP + 118.0 + float(i) * 92.0
		draw_line(Vector2(ROOM_LEFT + inset, y), Vector2(ROOM_RIGHT - inset, y + 6.0),
				Color(Feel.COL_NEWSPRINT.r, Feel.COL_NEWSPRINT.g,
				Feel.COL_NEWSPRINT.b, 0.07), 3.0)
	# A long wool runner pulls the eye through the two offset chair rows to the Sit-Down.
	var runner := PackedVector2Array([
		Vector2(92.0, -834.0), Vector2(470.0, -834.0),
		Vector2(422.0, -560.0), Vector2(148.0, -560.0),
	])
	draw_colored_polygon(runner, Color(Feel.COL_INK.r, Feel.COL_INK.g, Feel.COL_INK.b, 0.20))
	draw_polyline(PackedVector2Array([
		runner[0], runner[1], runner[2], runner[3], runner[0],
	]), Feel.COL_BRASS.darkened(0.58), 3.0)
	_draw_long_table()
	var font := ThemeDB.fallback_font
	if font != null:
		var plaque := Rect2(ROOM_LEFT + 30.0, ROOM_TOP + 24.0, 284.0, 58.0)
		draw_rect(plaque, Color(Feel.COL_INK.r, Feel.COL_INK.g, Feel.COL_INK.b, 0.70))
		draw_rect(plaque, Feel.COL_BRASS.darkened(0.22), false, 3.0)
		draw_string(font, plaque.position + Vector2(0.0, 41.0), "THE PENTHOUSE",
				HORIZONTAL_ALIGNMENT_CENTER, plaque.size.x, 28, Feel.COL_BRASS)
		draw_string(font, Vector2(ROOM_LEFT + 84.0, -574.0), "SIT-DOWN",
				HORIZONTAL_ALIGNMENT_CENTER, 170.0, 14, Feel.COL_BRASS.darkened(0.38))


## The long table the five chairs sit around. Paint only — see TABLE_AT.
func _draw_long_table() -> void:
	var r := Rect2(TABLE_AT - TABLE_SIZE * 0.5, TABLE_SIZE)
	# Chamfered walnut table, one bold object in the calmest room on the machine.
	var chamfer := 14.0
	var top := PackedVector2Array([
		Vector2(r.position.x + chamfer, r.position.y),
		Vector2(r.end.x - chamfer, r.position.y), Vector2(r.end.x, r.position.y + chamfer),
		Vector2(r.end.x, r.end.y - chamfer), Vector2(r.end.x - chamfer, r.end.y),
		Vector2(r.position.x + chamfer, r.end.y), Vector2(r.position.x, r.end.y - chamfer),
		Vector2(r.position.x, r.position.y + chamfer),
	])
	draw_colored_polygon(top, Color("251711"))
	draw_polyline(PackedVector2Array([
		top[0], top[1], top[2], top[3], top[4], top[5], top[6], top[7], top[0],
	]), Feel.COL_BRASS.darkened(0.30), 3.0)
	draw_line(Vector2(r.position.x + 16.0, TABLE_AT.y), Vector2(r.end.x - 16.0, TABLE_AT.y),
			Feel.COL_BRASS.darkened(0.55), 2.0)
	# five place settings, one per chair, so an empty seat reads from the felt
	var seats: PackedFloat32Array = [0.14, 0.38, 0.62, 0.86, 0.5]
	for i in range(seats.size()):
		var above := i < 3
		var p := Vector2(lerpf(r.position.x + 20.0, r.end.x - 20.0, seats[i]),
				TABLE_AT.y + (-1.0 if above else 1.0) * TABLE_SIZE.y * 0.28)
		var taken := chairs != null and i < chairs.targets().size() and chairs.targets()[i].marked
		draw_circle(p, 9.0, Feel.COL_BRASS if taken else Feel.COL_INK.lightened(0.18))
