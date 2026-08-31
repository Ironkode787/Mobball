class_name ClubDeck
extends Node2D
## THE CLUB — the upper deck (docs/02 §2 R4). The table stops being one screen tall here.
##
## The deck is a half-width mini-playfield in negative-y space, biased right: the left half
## of the sky stays empty on purpose, because the Docks and the Penthouse dock there in M3.
## Everything is built in code in the main table's coordinate space, so the deck's geometry
## and its `_draw()` come from the same numbers as the rest of the machine — no scene file to
## drift, no offset to get wrong.
##
## Reaching it: **the Staircase**, a wireform up the right-hand corridor past the payphones.
## Its mouth is a speed gate, not a switch — you need real pace up that lane, which at R4
## means a clean flip off the left bat. A shot that does not have it is simply not taken, and
## the ball carries on up the corridor and comes back down. Leaving it: the deck has no
## floor. Anything that gets below the mini-bats is caught by the return lane and delivered
## to the right inlane downstairs, never to the drain line — falling off the Club costs you
## the trip, not the ball.
##
## The deck's own flow is a single orbit: mini-flipper → up the right lane → round the
## rounded corner → left along the ceiling channel → off the end of the guide and into the
## roulette bowl. The wheel is the deck's sink and its flagship toy; the slots are the centre
## bank, the back room hides behind the middle reel, and the High Roller sits at the top of
## the left lane. The staircase arrives *into the ceiling channel*, so every trip upstairs
## feeds the wheel: the house greets you at the door.
##
## Money: none of it is decided here. Landing a pocket and dropping a reel pay a courtesy
## switch through TableScore (groups `casino` and `ramps`); the bet, the odds and the wash
## belong to the flow lane (specs/m2-empire.md: hardware reports outcomes, flow owns money).

## Which pocket took the ball, and whether it was one of the house's three.
signal roulette_landed(pocket: int, house: bool)
## The set of cleared reels changed.
signal reels_state(cleared_columns: Array)
## A High Roller hold ended. `steps` is how many rungs of the 1×/2×/3×/5× ladder it climbed.
signal high_roller_held(steps: int)
## The back room took the ball (flow starts the Family Meeting from here).
signal backroom_entered()
## A completed climb: the mouth was taken and the top was reached.
signal staircase_climbed(speed: float)
## The return lane put the ball back on the main playfield.
signal returned_home(at: Vector2)

# ------------------------------------------------------------------ hardware ids
const ID_DECK := &"club_deck"
const ID_STAIRCASE := &"staircase_ramp"
const ID_ROULETTE := &"roulette_wheel"
const ID_REELS := &"slot_reels"
const ID_HIGH_ROLLER := &"high_roller_saucer"
const ID_BACKROOM := &"backroom_saucer"
const ID_FLIPPERS := &"club_flippers"

# ------------------------------------------------------------------ the shell
const DECK_LEFT := 520.0
const DECK_RIGHT := 1040.0
const DECK_TOP := -880.0
const DECK_BOTTOM := -40.0
const WALL_THICK := 36.0
const GUIDE_THICK := 18.0
## Where the right wall gives way to the rounded corner that turns a right-lane shot into an
## orbit. Same trick as the M1 arch: the outer wall does the steering.
const CORNER_CENTER := Vector2(860.0, -700.0)
const CORNER_RADIUS := 180.0
## The ceiling channel's floor. Concentric with the corner, then straight, and it stops over
## the wheel so the ball runs out of guide and drops in.
const ORBIT_GUIDE_RADIUS := 72.0
## The guide stops **short of its own apex**. A circular turn from a vertical lane into a
## horizontal one has a level tangent at the top, and a 20 px level shelf under top-down
## gravity is a place a ball sits down for good — a soak found the ball asleep on it for the
## whole rest of the night. Ending the arc at -70° and joining a raked straight leaves a
## ridge instead of a shelf: every surface in the channel falls away toward the wheel.
const ORBIT_GUIDE_TO_DEG := -70.0
const ORBIT_GUIDE_END := Vector2(770.0, -730.0)

# ------------------------------------------------------------------ hardware
const WHEEL_AT := Vector2(712.0, -610.0)
const REELS_AT := Vector2(790.0, -330.0)
const BACKROOM_AT := Vector2(790.0, -455.0)
const BACKROOM_R := 40.0
const HIGH_ROLLER_AT := Vector2(588.0, -470.0)
const HIGH_ROLLER_R := 40.0
const HIGH_ROLLER_STEPS: PackedFloat32Array = [1.0, 2.0, 3.0, 5.0]
const FLIPPER_PIVOT_L := Vector2(608.0, -150.0)
const FLIPPER_PIVOT_R := Vector2(952.0, -150.0)
const FLIPPER_SCALE := 0.8
## The deck's answer to the M1 inlane guides: the wall runs into the flipper pivot so there
## is no notch beside the bat for a ball to sit down in.
const CHEEK_TOP_Y := -250.0
const CHEEK_END := Vector2(598.0, -162.0)

# ------------------------------------------------------------------ getting up and down
## Mouth of the Staircase: the aimed gap between Lucky's low facade and Fat Tony's pawnshop.
## It is a centre-right jackpot shot now, not a hidden switch in the shooter gutter.
const STAIR_MOUTH := Vector2(695.0, 1250.0)
const STAIR_ENTRY_SPEED := 1650.0
const STAIR_CLIMB_GRAVITY := 460.0
const STAIR_MAX_SPEED := 1800.0
## The last few feet of the wireform are a brake, so every arrival steps off the stairs at
## the same pace: fast enough to clear the channel guide, slow enough to drop into the wheel
## rather than sail over it. Come up the Staircase and the house deals you in — that is the
## whole point of the shot.
const STAIR_RELEASE_SPEED := 480.0
const STAIR_PATH: PackedVector2Array = [
	Vector2(695.0, 1250.0), Vector2(690.0, 1110.0), Vector2(700.0, 950.0),
	Vector2(735.0, 795.0), Vector2(720.0, 630.0), Vector2(760.0, 470.0),
	Vector2(820.0, 300.0), Vector2(875.0, 100.0), Vector2(900.0, -140.0),
	Vector2(900.0, -390.0), Vector2(880.0, -620.0), Vector2(850.0, -760.0),
	Vector2(830.0, -815.0),
]
## The way down. It stays clear of the shooter-lane column so the one-way gate's latch never
## sees it, and it lands in the right inlane — a ramp return that feeds the drain is a bug.
const RETURN_PATH: PackedVector2Array = [
	Vector2(560.0, -30.0), Vector2(950.0, 30.0), Vector2(962.0, 240.0),
	Vector2(950.0, 600.0), Vector2(930.0, 1000.0), Vector2(918.0, 1300.0),
	Vector2(870.0, 1420.0), Vector2(780.0, 1480.0),
]
const RETURN_CATCH_AT := Vector2(780.0, -44.0)
const RETURN_CATCH_SIZE := Vector2(490.0, 56.0)
const RETURN_MIN_FORWARD := 700.0
const RETURN_MAX_SPEED := 1400.0
const RETURN_RELEASE_SPEED := 430.0
const RETURN_GRAVITY := 900.0

# ------------------------------------------------------------------ look (docs/07 §1)
const COL_VIOLET := Color("8C4DFF")
const COL_NEON_ROSE := Color("FF2E63")

var roulette: RouletteWheel = null
var reels: SlotReels = null
var high_roller: HoldSaucer = null
var backroom: HoldSaucer = null
var staircase: RampLane = null
var return_lane: RampLane = null
var flipper_left: Flipper = null
var flipper_right: Flipper = null

var _present: bool = false
var _flippers_live: bool = false
var _shell: WallPiece = null
var _guide: WallPiece = null
var _cheeks: WallPiece = null
var _main_left: Flipper = null
var _main_right: Flipper = null
var _ball: Ball = null


# ====================================================================== build =====


func _ready() -> void:
	_build_shell()
	_build_orbit_guide()
	_build_roulette()
	_build_reels()
	_build_saucers()
	_build_flippers()
	_build_ramps()


func _build_shell() -> void:
	_shell = WallPiece.new()
	_shell.name = "DeckShell"
	add_child(_shell)
	var pts := PackedVector2Array()
	pts.append(Vector2(DECK_RIGHT, DECK_BOTTOM))
	pts.append(Vector2(DECK_RIGHT, CORNER_CENTER.y))
	for i in range(13):
		var a := lerpf(0.0, -PI * 0.5, float(i) / 12.0)
		pts.append(CORNER_CENTER + Vector2(cos(a), sin(a)) * CORNER_RADIUS)
	pts.append(Vector2(DECK_LEFT, DECK_TOP))
	pts.append(Vector2(DECK_LEFT, DECK_BOTTOM))
	_shell.chain(pts, WALL_THICK)
	# The deck has no floor — everything below the bats belongs to the return lane. This is
	# the backstop under it: nothing can leave the Club except down the stairs.
	_shell.bar(Vector2(DECK_LEFT, -6.0), Vector2(DECK_RIGHT, -6.0), 24.0)

	_cheeks = WallPiece.new()
	_cheeks.name = "DeckCheeks"
	add_child(_cheeks)
	_cheeks.bar(Vector2(DECK_LEFT + WALL_THICK * 0.5, CHEEK_TOP_Y), CHEEK_END, 16.0)
	_cheeks.bar(Vector2(DECK_RIGHT - WALL_THICK * 0.5, CHEEK_TOP_Y),
			Vector2(_mirror_x(CHEEK_END.x), CHEEK_END.y), 16.0)


func _build_orbit_guide() -> void:
	_guide = WallPiece.new()
	_guide.name = "OrbitGuide"
	add_child(_guide)
	var pts := PackedVector2Array()
	for i in range(11):
		var a := lerpf(0.0, deg_to_rad(ORBIT_GUIDE_TO_DEG), float(i) / 10.0)
		pts.append(CORNER_CENTER + Vector2(cos(a), sin(a)) * ORBIT_GUIDE_RADIUS)
	pts.append(ORBIT_GUIDE_END)
	_guide.chain(pts, GUIDE_THICK)


func _build_roulette() -> void:
	roulette = RouletteWheel.new()
	roulette.name = "Roulette"
	roulette.id = ID_ROULETTE
	roulette.position = WHEEL_AT
	add_child(roulette)
	roulette.landed.connect(func(pocket: int, house: bool) -> void:
		roulette_landed.emit(pocket, house))


func _build_reels() -> void:
	reels = SlotReels.new()
	reels.name = "SlotReels"
	reels.id = ID_REELS
	reels.position = REELS_AT
	add_child(reels)
	reels.state_changed.connect(func(cols: Array) -> void: reels_state.emit(cols))


func _build_saucers() -> void:
	high_roller = HoldSaucer.new()
	high_roller.name = "HighRoller"
	high_roller.steps = HIGH_ROLLER_STEPS
	high_roller.eject_speed = 900.0
	high_roller.eject_heat = 150.0
	high_roller.configure(ID_HIGH_ROLLER, HIGH_ROLLER_AT, HIGH_ROLLER_R, Vector2(0.80, -0.60))
	add_child(high_roller)
	high_roller.ejected.connect(func(steps: int) -> void: high_roller_held.emit(steps))

	backroom = HoldSaucer.new()
	backroom.name = "Backroom"
	backroom.hold_seconds = 0.8
	backroom.eject_speed = 620.0
	backroom.configure(ID_BACKROOM, BACKROOM_AT, BACKROOM_R, Vector2(0.18, 1.0))
	add_child(backroom)
	backroom.captured.connect(func() -> void: backroom_entered.emit())


func _build_flippers() -> void:
	flipper_left = _make_flipper(&"left", FLIPPER_PIVOT_L, "ClubFlipperLeft")
	flipper_right = _make_flipper(&"right", FLIPPER_PIVOT_R, "ClubFlipperRight")


func _make_flipper(side: StringName, at: Vector2, node_name: String) -> Flipper:
	var f := Flipper.new()
	f.side = side
	f.size_scale = FLIPPER_SCALE
	f.name = node_name
	f.position = at
	add_child(f)
	return f


func _build_ramps() -> void:
	staircase = RampLane.new()
	staircase.name = "Staircase"
	staircase.entry_speed = STAIR_ENTRY_SPEED
	staircase.climb_gravity = STAIR_CLIMB_GRAVITY
	staircase.max_speed = STAIR_MAX_SPEED
	staircase.release_speed = STAIR_RELEASE_SPEED
	staircase.entry_center = STAIR_MOUTH
	staircase.abort_at = STAIR_MOUTH
	staircase.color = Feel.COL_BRASS.darkened(0.25)
	staircase.configure(ID_STAIRCASE, STAIR_PATH)
	add_child(staircase)
	staircase.crested.connect(_on_staircase_crested)

	return_lane = RampLane.new()
	return_lane.name = "ReturnLane"
	return_lane.entry_speed = -100000.0        # the deck's floor: it takes anything
	return_lane.climb_gravity = RETURN_GRAVITY
	return_lane.max_speed = RETURN_MAX_SPEED
	return_lane.min_forward = RETURN_MIN_FORWARD
	return_lane.release_speed = RETURN_RELEASE_SPEED
	return_lane.entry_center = RETURN_CATCH_AT
	return_lane.entry_size = RETURN_CATCH_SIZE
	return_lane.abort_at = RETURN_PATH[RETURN_PATH.size() - 1]
	return_lane.color = COL_VIOLET.darkened(0.35)
	return_lane.configure(&"club_return", RETURN_PATH)
	add_child(return_lane)
	return_lane.crested.connect(_on_returned)


# ================================================================== the table =====


## The main table's bats: the Club's pair rides their button state, so there is one input
## path with one buffer rather than a second reader of the same actions.
func bind_flippers(left: Flipper, right: Flipper) -> void:
	_main_left = left
	_main_right = right


func set_ball(b: Ball) -> void:
	_ball = b
	for holder: Node in [roulette, high_roller, backroom, staircase, return_lane]:
		if holder != null:
			holder.call(&"set_ball", b)


## Every switchable piece of the Club, as the table's `_register` wants them: each id also
## needs `club_deck` itself, because a roulette wheel with no deck under it is not hardware.
func pieces() -> Array[Dictionary]:
	return [
		{"ids": [ID_ROULETTE], "node": roulette},
		{"ids": [ID_REELS], "node": reels},
		{"ids": [ID_HIGH_ROLLER], "node": high_roller},
		{"ids": [ID_BACKROOM], "node": backroom},
		{"ids": [ID_STAIRCASE], "node": staircase},
		{"ids": [ID_FLIPPERS], "node": flipper_left},
		{"ids": [ID_FLIPPERS], "node": flipper_right},
	]


func bounds() -> Rect2:
	return Rect2(Vector2(DECK_LEFT, DECK_TOP),
			Vector2(DECK_RIGHT - DECK_LEFT, DECK_BOTTOM - DECK_TOP))


## Is a ball resting here on purpose? The main table's ball search hunts anything motionless
## above the flipper line, and on this deck that would kick a cradled ball off a mini-bat or
## rob a saucer mid-hold.
func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball):
		return false
	if not _present:
		return false
	if BallHold.is_held(ball):
		return true
	var p := ball.global_position
	if p.y < FLIPPER_PIVOT_L.y - 60.0 or p.y > 0.0:
		return false
	return p.x > FLIPPER_PIVOT_L.x - 60.0 and p.x < FLIPPER_PIVOT_R.x + 60.0


func holds_ball() -> bool:
	if roulette != null and roulette.holds_ball():
		return true
	if high_roller != null and high_roller.holds_ball():
		return true
	if backroom != null and backroom.holds_ball():
		return true
	if staircase != null and staircase.riding():
		return true
	return return_lane != null and return_lane.riding()


func _physics_process(_delta: float) -> void:
	if not _flippers_live:
		return
	if _main_left != null and flipper_left != null:
		flipper_left.set_pressed(_main_left.is_held())
	if _main_right != null and flipper_right != null:
		flipper_right.set_pressed(_main_right.is_held())


func _on_staircase_crested(speed: float) -> void:
	AudioDirector.play(&"staircase_crest")
	TableScore.earn(TableScore.GROUP_RAMPS, TableScore.RAMP_CLIMB, ID_STAIRCASE, _ball, speed)
	staircase_climbed.emit(speed)


func _on_returned(_speed: float) -> void:
	AudioDirector.play(&"wall_tap")
	returned_home.emit(RETURN_PATH[RETURN_PATH.size() - 1])


# =================================================================== dormancy =====


## The deck's structure. Sub-hardware is switched by the table, which knows the owned set;
## this only owns the shell, the guide and the ramps that make the deck a place.
func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	for piece: Node in [_shell, _guide, _cheeks, return_lane]:
		if piece != null:
			Dormant.apply(piece, active)
	if not active:
		_flippers_live = false
		_release_everything()


func is_hardware_active() -> bool:
	return _present


## Called by the table after it has applied the owned set to the sub-pieces.
func set_flippers_live(live: bool) -> void:
	_flippers_live = live and _present
	if not _flippers_live and flipper_left != null and flipper_right != null:
		flipper_left.set_pressed(false)
		flipper_right.set_pressed(false)


## Switching the deck off while it has the ball would leave it standing in the sky where the
## Club used to be. Each holder hands the ball back where it stood; then it is put down
## downstairs, at the foot of the stairs, whatever was holding it.
func _release_everything() -> void:
	var was_holding := holds_ball()
	for holder: Node in [roulette, high_roller, backroom, staircase, return_lane]:
		if holder != null and holder.has_method(&"set_hardware_active"):
			holder.call(&"set_hardware_active", false)
	if was_holding and _ball != null and is_instance_valid(_ball):
		BallHold.release(_ball, RETURN_PATH[RETURN_PATH.size() - 1], Vector2.ZERO)


# =================================================================== geometry =====


func _mirror_x(x: float) -> float:
	return (FLIPPER_PIVOT_L.x + FLIPPER_PIVOT_R.x) - x


func felt_polygon() -> PackedVector2Array:
	var inset := WALL_THICK * 0.5
	var pts := PackedVector2Array()
	pts.append(Vector2(DECK_RIGHT - inset, DECK_BOTTOM))
	pts.append(Vector2(DECK_RIGHT - inset, CORNER_CENTER.y))
	for i in range(13):
		var a := lerpf(0.0, -PI * 0.5, float(i) / 12.0)
		pts.append(CORNER_CENTER + Vector2(cos(a), sin(a)) * (CORNER_RADIUS - inset))
	pts.append(Vector2(DECK_LEFT + inset, DECK_TOP + inset))
	pts.append(Vector2(DECK_LEFT + inset, DECK_BOTTOM))
	return pts


# ==================================================================== drawing =====


func _draw() -> void:
	_draw_backdrop()
	var felt := Feel.COL_FELT.lerp(COL_VIOLET, 0.22)
	draw_colored_polygon(felt_polygon(), felt)
	_draw_room_inlay()
	var font := ThemeDB.fallback_font
	if font != null:
		var sign := Rect2(DECK_LEFT + 32.0, DECK_TOP + 28.0, 256.0, 70.0)
		draw_rect(sign, Feel.COL_INK.darkened(0.18))
		draw_rect(sign, COL_NEON_ROSE.darkened(0.10), false, 4.0)
		draw_string(font, sign.position + Vector2(0.0, 50.0), "THE CLUB",
			HORIZONTAL_ALIGNMENT_CENTER, sign.size.x, 38, COL_NEON_ROSE)
		draw_string(font, sign.position + Vector2(0.0, 68.0), "R4  /  CAPO  /  EARNED DECK",
			HORIZONTAL_ALIGNMENT_CENTER, sign.size.x, 12, Feel.COL_BRASS)
		draw_string(font, Vector2(DECK_LEFT + 54.0, -246.0), "HOUSE FLOOR",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, Feel.COL_BRASS.darkened(0.32))


## Casino carpet and a small proscenium organize the wheel, reels and bats as a room rather
## than loose hardware on violet felt. Reserved colors remain tied to their actual modes.
func _draw_room_inlay() -> void:
	# Broad carpet runner from the bats to the wheel.
	var runner := PackedVector2Array([
		Vector2(662.0, -68.0), Vector2(914.0, -68.0),
		Vector2(886.0, -690.0), Vector2(688.0, -690.0),
	])
	draw_colored_polygon(runner, Color(COL_VIOLET.r, COL_VIOLET.g, COL_VIOLET.b, 0.09))
	draw_polyline(PackedVector2Array([
		Vector2(662.0, -68.0), Vector2(688.0, -690.0),
	]), COL_VIOLET.darkened(0.46), 4.0)
	draw_polyline(PackedVector2Array([
		Vector2(914.0, -68.0), Vector2(886.0, -690.0),
	]), COL_VIOLET.darkened(0.46), 4.0)
	for i in range(8):
		var y := -112.0 - float(i) * 68.0
		var x := 788.0 + (8.0 if i % 2 == 0 else -8.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(x, y - 10.0), Vector2(x + 10.0, y),
			Vector2(x, y + 10.0), Vector2(x - 10.0, y),
		]), Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.18))

	# Roulette is the visual sun of the Club even before the wheel is bought.
	for i in range(12):
		var a := float(i) * TAU / 12.0
		draw_line(WHEEL_AT + Vector2(cos(a), sin(a)) * 86.0,
				WHEEL_AT + Vector2(cos(a), sin(a)) * 110.0,
				Color(Feel.COL_BRASS.r, Feel.COL_BRASS.g, Feel.COL_BRASS.b, 0.16), 3.0)
	draw_arc(WHEEL_AT, 112.0, 0.0, TAU, 40, Feel.COL_BRASS.darkened(0.62), 3.0)

	# A stage around the slot bank gives its three columns one clear silhouette.
	var stage := Rect2(Vector2(680.0, -420.0), Vector2(220.0, 196.0))
	draw_rect(stage, Color(Feel.COL_INK.r, Feel.COL_INK.g, Feel.COL_INK.b, 0.22))
	draw_rect(stage, Feel.COL_BRASS.darkened(0.62), false, 3.0)
	for i in range(7):
		var x := lerpf(stage.position.x + 14.0, stage.end.x - 14.0, float(i) / 6.0)
		draw_circle(Vector2(x, stage.position.y + 10.0), 3.0, Feel.COL_BRASS.darkened(0.35))

	# Brass fascia and violet aisle markers make the deck edge read as a second storey.
	draw_line(Vector2(DECK_LEFT + 30.0, DECK_BOTTOM - 22.0),
			Vector2(DECK_RIGHT - 30.0, DECK_BOTTOM - 22.0), COL_NEON_ROSE.darkened(0.55), 5.0)
	for i in range(7):
		var y := lerpf(DECK_TOP + 120.0, DECK_BOTTOM - 90.0, float(i) / 6.0)
		draw_line(Vector2(DECK_LEFT + 26.0, y), Vector2(DECK_LEFT + 48.0, y - 4.0),
				COL_VIOLET.darkened(0.40), 3.0)

	# State marks sit beside, never on top of, the child hardware. Every cue uses the C2
	# mark/pattern vocabulary so state survives grayscale and reduced effects. A missing child
	# is N/A at this draw edge; the shell never invents a transition for it.
	var cues: Array[Dictionary] = []
	if roulette != null and roulette.has_method(&"visual_token"):
		cues.append({"at": WHEEL_AT + Vector2(0.0, -132.0), "token": roulette.visual_token()})
	if reels != null and reels.has_method(&"visual_token"):
		cues.append({"at": REELS_AT + Vector2(0.0, -112.0), "token": reels.visual_token()})
	if high_roller != null and high_roller.has_method(&"visual_token"):
		cues.append({"at": HIGH_ROLLER_AT + Vector2(-48.0, 0.0), "token": high_roller.visual_token()})
	if backroom != null and backroom.has_method(&"visual_token"):
		cues.append({"at": BACKROOM_AT + Vector2(48.0, 0.0), "token": backroom.visual_token()})
	if staircase != null and staircase.has_method(&"visual_token"):
		cues.append({"at": STAIR_PATH[0] + Vector2(-28.0, 0.0), "token": staircase.visual_token()})
	if return_lane != null and return_lane.has_method(&"visual_token"):
		cues.append({"at": RETURN_PATH[RETURN_PATH.size() - 1] + Vector2(22.0, 0.0),
				"token": return_lane.visual_token()})
	for cue_data: Dictionary in cues:
		var token: Dictionary = cue_data["token"]
		var at: Vector2 = cue_data["at"]
		var state := String(token.get("state", &"idle"))
		var mark := String(token.get("mark", &"outline"))
		var pattern := String(token.get("pattern", &"stable_outline"))
		var cue_col := Feel.COL_BRASS.darkened(0.46)
		if state == "armed":
			cue_col = Feel.COL_BRASS
		elif state == "active":
			cue_col = COL_NEON_ROSE
		elif state == "completed":
			cue_col = Feel.COL_NEWSPRINT
		elif state == "disabled":
			cue_col = Feel.COL_NEWSPRINT.darkened(0.46)
		elif state == "danger":
			cue_col = Feel.COL_DIRTY
		var cue := Color(cue_col.r, cue_col.g, cue_col.b, 0.78)
		var radius := 12.0
		if mark == "invitation_pin":
			draw_circle(at, radius * 0.36, cue)
			draw_line(at + Vector2(0.0, radius * 0.30), at + Vector2(0.0, radius), cue, 3.0)
		elif mark == "contact_pulse" or mark == "held_ring":
			draw_arc(at, radius, 0.0, TAU, 20, cue, 3.0)
			draw_circle(at, radius * 0.20, cue)
		elif mark == "check_stamp" or mark == "marked_stamp":
			draw_rect(Rect2(at - Vector2(radius, radius), Vector2(radius * 2.0, radius * 2.0)),
					cue, false, 3.0)
			draw_line(at + Vector2(-radius * 0.52, 0.0), at + Vector2(-radius * 0.10, radius * 0.40),
					cue, 3.0)
			draw_line(at + Vector2(-radius * 0.10, radius * 0.40), at + Vector2(radius * 0.56, -radius * 0.48),
					cue, 3.0)
		elif mark == "lock_offline":
			draw_rect(Rect2(at - Vector2(radius * 0.72, radius * 0.34), Vector2(radius * 1.44, radius * 0.90)),
					cue, false, 3.0)
			draw_arc(at + Vector2(0.0, -radius * 0.25), radius * 0.42, PI, TAU, 12, cue, 3.0)
		elif mark == "offline_cross":
			draw_line(at + Vector2(-radius * 0.72, -radius * 0.72),
				at + Vector2(radius * 0.72, radius * 0.72), cue, 3.0)
			draw_line(at + Vector2(radius * 0.72, -radius * 0.72),
				at + Vector2(-radius * 0.72, radius * 0.72), cue, 3.0)
		elif mark == "cooldown_clock":
			draw_arc(at, radius, -PI * 0.5, PI, 16, cue, 3.0)
			draw_line(at, at + Vector2(0.0, -radius * 0.52), cue, 2.0)
			draw_line(at, at + Vector2(radius * 0.34, radius * 0.20), cue, 2.0)
		elif mark == "hazard_hatch" or mark == "telegraph_hatch" or mark == "jam_alert" \
				or pattern == "hazard_hatch" or pattern == "telegraph_hatch":
			draw_arc(at, radius, 0.0, TAU, 20, cue, 3.0)
			for hatch in range(3):
				var hy := at.y - radius * 0.62 + float(hatch) * radius * 0.52
				draw_line(Vector2(at.x - radius * 0.68, hy), Vector2(at.x + radius * 0.68, hy - radius * 0.36), cue, 2.0)
		else:
			# `outline` and any future C2 mark remain a stable, non-color cue.
			draw_arc(at, radius, 0.0, TAU, 20, cue, 3.0)


## Once the table has an upstairs, the space around it is in shot. This is the back of the
## machine behind the deck — dark board, a hint of a skyline, the scaffolding that holds the
## Club up. The left half stays deliberately bare: the Docks and the Penthouse build there.
func _draw_backdrop() -> void:
	var top := DECK_TOP - WALL_THICK * 0.5
	var wide := Rect2(Vector2(ProgressionTable.PLAY_LEFT - 18.0, top),
			Vector2(DECK_RIGHT + 18.0 - ProgressionTable.PLAY_LEFT + 18.0, -top + 6.0))
	draw_rect(wide, Feel.COL_INK.darkened(0.25))
	for i in range(7):
		var x := lerpf(wide.position.x + 40.0, DECK_LEFT - 40.0, float(i) / 6.0)
		var h := 120.0 + fmod(float(i) * 137.0, 190.0)
		draw_rect(Rect2(Vector2(x, -h), Vector2(46.0, h)), Feel.COL_INK.lightened(0.06))
		for w in range(3):
			var wy := -h + 26.0 + float(w) * 34.0
			if wy > -14.0:
				break
			var lit := (i + w) % 3 != 0
			draw_rect(Rect2(Vector2(x + 12.0, wy), Vector2(10.0, 12.0)),
					Feel.COL_BRASS.darkened(0.15) if lit else Feel.COL_INK.lightened(0.12))
	# the deck's underside: girders, because a second storey has to stand on something
	for i in range(6):
		var gx := lerpf(DECK_LEFT + 20.0, DECK_RIGHT - 20.0, float(i) / 5.0)
		draw_line(Vector2(gx, DECK_BOTTOM), Vector2(gx - 18.0, 4.0),
				Feel.COL_INK.lightened(0.14), 7.0)
	# A few right-side windows establish the Club as an earned upper district. They are broad,
	# static patches of light in the backdrop, not a lane, guide, or activation signal; the left
	# half remains deliberately quiet for the Docks and Penthouse composition.
	for i in range(4):
		var x := lerpf(DECK_LEFT + 270.0, DECK_RIGHT - 36.0, float(i) / 3.0)
		var y := -150.0 - float(i % 2) * 88.0
		draw_rect(Rect2(Vector2(x, y), Vector2(28.0, 46.0)),
				Color(COL_VIOLET.r, COL_VIOLET.g, COL_VIOLET.b, 0.10))
