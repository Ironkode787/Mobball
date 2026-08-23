class_name CityHall
extends Node2D
## CITY HALL — the dome (docs/02 §2 R7, specs/m3-fall-rise.md sub-wave B).
##
## The last thing bolted to this machine, and the only one that is not a room: there is
## nothing to stand on up here, no floor, no toys, no walls. There is one golden rail that
## leaves the Club's ceiling channel, runs under the dome, climbs the far side, crosses the
## sky over the top of it and comes back down onto the deck. That is the whole of it.
##
## **The gate is the point.** The mouth demands 1350 px/s *along the rail* — half again what
## the Penthouse asks for and nearly three times a staircase arrival. The three shots that
## share this channel are a ladder, and the ladder is read off one number:
##
##   under ~985 px/s     the ball runs out of channel and drops into the roulette bowl
##   ~985 – 1350 px/s    the Penthouse wireform takes it (its mouth is further west)
##   over 1350 px/s      the dome takes it, because its mouth is the one you meet first
##
## The dome's mouth has to be the eastern one or the ladder cannot exist: the Penthouse's
## gate is the lower of the two, so if a westbound ball met it first it would take everything
## and the dome would never fire once. The size of the gap between the two numbers is a
## measured thing rather than a taste: the Penthouse's nominal 900 becomes about 985 by the
## time a ball has fallen the 100 px between the two mouths, and a dome gate set anywhere
## near that left the Penthouse with a 30 px/s window — buying the crown would have quietly
## taken the room below it out of the game.
##
## Nothing is refused rudely: a ball that is not fast enough is simply not picked up, and
## carries on down the channel it was already in. There is no way to fail this shot that
## costs a ball — only ways to fail it that cost the lap.
##
## **Nothing up here can trap a ball**, by construction rather than by tuning: the dome has
## no collision geometry at all. The building is paint and the loop is a wireform, so the
## only thing in the sky that can touch the ball is a rail with two ends on it.
##
## Money: one switch. A closed lap pays `TableScore.DOME_LOOP` in the `penthouse` group and
## reports `dome_loop_completed`. The City Hall Circuit (docs/02 §2 R7 — orbit, staircase,
## penthouse gate, dome loop, chained) is the flow lane's to count: this reports one shot.

## The lap closed — the ball has come over the top and is on its way home. `speed` is the
## rail speed at the moment it closed.
signal loop_completed(speed: float)
## The rail put the ball back on the Club deck.
signal returned_home(at: Vector2)

# ------------------------------------------------------------------ hardware ids
const ID_CITY_HALL := &"city_hall"
## The lane's own id: switch ids are `dome_loop_entry` (the mouth) and `dome_loop` (the lap).
const ID_LOOP := &"dome_loop"

# ------------------------------------------------------------------ the loop
## The rail is a circle round the dome, entered from below-right and left down its east
## side. 240° rather than a full turn on purpose: a full circle ends where it started,
## pointing back up into the dome, and the only way off it would be to reverse.
const DOME_CENTER := Vector2(520.0, -1140.0)
const LOOP_RADIUS := 210.0
const LOOP_FROM_DEG := 120.0
const LOOP_TO_DEG := 360.0
const LOOP_STEPS := 32

## The mouth sits in the Club's ceiling channel, east of the Penthouse's — in the rounded
## corner itself, where a ball coming off the deck's right lane is still turning west. The
## two mouths are deliberately edge-to-edge and never overlapping: whichever one takes the
## ball, it is the one the ball's own pace chose.
const MOUTH_AT := Vector2(892.0, -806.0)
const MOUTH_SIZE := Vector2(86.0, 84.0)
const ENTRY_SPEED := 1350.0
## Gentler than the Penthouse's rake: this rail is nearly twice as long, and a lap has to be
## survivable by a shot that only just made the gate.
const CLIMB_GRAVITY := 400.0
const MAX_SPEED := 1400.0
## Delivered, not fired: the crown hands the ball back to the deck's left bat at a pace it
## can be caught at. Winning the hardest shot in the game must not then cost the ball.
const RELEASE_SPEED := 440.0

## The climb out of the channel is a cubic Bézier so the rail leaves along the direction the
## ball is actually travelling and arrives along the circle's own tangent — the two controls
## are those tangents, 200 px long. A hand-laid polyline here put a 20° kink in the middle
## of the fastest shot on the table.
const APPROACH_C1 := Vector2(704.0, -874.0)
const APPROACH_C2 := Vector2(588.2, -858.135)
const APPROACH_STEPS := 10

## Down the east side of the dome and onto the deck, crossing over the Club's ceiling and its
## roulette wheel on the way — a wireform passes over the playfield, that is what it is for,
## and every holder up there ignores a ball that is already held.
##
## Where it *lets go* is the part that had to be measured. The deck's left lane is 100 px
## wide between the wall and the slot reels, with the High Roller sitting in the middle of it,
## so the release point is the one spot that is clear of all three: 70 px below the saucer
## (and falling away from it), 22 px clear of the reels, and drifting toward the wall rather
## than the machines. An earlier draft let go 60 px further right and put the ball to sleep on
## the cap of the top-left reel — the crown shot, ending in a coil search.
const RETURN_PATH: PackedVector2Array = [
	Vector2(730.0, -900.0), Vector2(690.0, -700.0), Vector2(648.0, -575.0),
	Vector2(608.0, -470.0), Vector2(588.0, -400.0),
]

# ------------------------------------------------------------------ the building
## All paint. The drum and the dome sit inside the rail with 60 px to spare all round.
const DRUM_HALF := 150.0
const DRUM_TOP := -1120.0
const DRUM_BOTTOM := -968.0
const DOME_R := 150.0
const FINIAL_TOP := -1318.0
const STEPS_HALF := 190.0

## The sky the dome stands in. It joins the Club's own backdrop at its top edge (-898), so
## the camera never finds a seam between the two once it climbs this high.
const SKY_LEFT := 22.0
const SKY_RIGHT := 1058.0
## Painted well past the top of `bounds()` on purpose: the game's camera clamps to the
## bounds and can never see the edge, but a hand-parked camera (a screenshot, a debug scene)
## can, and a machine that ends in a grey rectangle photographs badly.
const SKY_TOP := -1580.0
const SKY_BOTTOM := -886.0

# ------------------------------------------------------------------ look (docs/07 §1)
## Gold leaf is brass with the light on it; the rim glow is three arcs, not a shader.
const COL_LEAF := Color("E8C64A")

var loop: RampLane = null

var _present: bool = false
var _ball: Ball = null
var _close_s: float = 0.0
var _lapped: bool = false
var _flash: float = 0.0


# ====================================================================== build =====


func _ready() -> void:
	var path := loop_path()
	_close_s = _length_to(path, APPROACH_STEPS + LOOP_STEPS)
	loop = RampLane.new()
	loop.name = "DomeLoop"
	loop.entry_speed = ENTRY_SPEED
	loop.climb_gravity = CLIMB_GRAVITY
	loop.max_speed = MAX_SPEED
	loop.release_speed = RELEASE_SPEED
	loop.entry_center = MOUTH_AT
	loop.entry_size = MOUTH_SIZE
	loop.abort_at = RETURN_PATH[RETURN_PATH.size() - 1]
	loop.color = COL_LEAF
	loop.configure(ID_LOOP, path)
	add_child(loop)
	loop.crested.connect(_on_crested)


## The whole rail: the Bézier climb out of the ceiling channel, the circle round the dome,
## and the run down its east side onto the deck. Built from the constants above so the
## drawing and the physics can never disagree about where the loop is.
static func loop_path() -> PackedVector2Array:
	var pts := PackedVector2Array()
	var entry := polar(LOOP_FROM_DEG)
	for i in range(APPROACH_STEPS):
		pts.append(_bezier(MOUTH_AT, APPROACH_C1, APPROACH_C2, entry,
				float(i) / float(APPROACH_STEPS)))
	for i in range(LOOP_STEPS + 1):
		pts.append(polar(lerpf(LOOP_FROM_DEG, LOOP_TO_DEG, float(i) / float(LOOP_STEPS))))
	pts.append_array(RETURN_PATH)
	return pts


static func polar(degrees: float) -> Vector2:
	var a := deg_to_rad(degrees)
	return DOME_CENTER + Vector2(cos(a), sin(a)) * LOOP_RADIUS


static func _bezier(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, u: float) -> Vector2:
	var v := 1.0 - u
	return p0 * (v * v * v) + p1 * (3.0 * v * v * u) + p2 * (3.0 * v * u * u) + p3 * (u * u * u)


static func _length_to(pts: PackedVector2Array, upto: int) -> float:
	var s := 0.0
	for i in range(mini(upto, pts.size() - 1)):
		s += pts[i].distance_to(pts[i + 1])
	return s


# ================================================================== the table =====


func set_ball(b: Ball) -> void:
	_ball = b
	if loop != null:
		loop.set_ball(b)


func bounds() -> Rect2:
	return Rect2(Vector2(DOME_CENTER.x - LOOP_RADIUS - 52.0, FINIAL_TOP - 74.0),
			Vector2((LOOP_RADIUS + 52.0) * 2.0, DRUM_BOTTOM + 40.0 - (FINIAL_TOP - 74.0)))


## Where the lap closes, as an arc length along the rail. The lap is the circle; the run
## home afterwards is delivery, and a player who has come over the top has already made it.
func close_length() -> float:
	return _close_s


func holds_ball() -> bool:
	return loop != null and loop.riding()


## A ball on the rail is travelling, not resting — but the coils downstairs only know that a
## ball is motionless and high up, and a lap that crosses the top of the dome at walking pace
## looks exactly like that from below.
func search_exempt(ball: Ball) -> bool:
	if ball == null or not is_instance_valid(ball) or not _present:
		return false
	return BallHold.is_held(ball) and holds_ball()


func _physics_process(_delta: float) -> void:
	if not _present or loop == null:
		return
	if not loop.riding():
		_lapped = false
		return
	if not _lapped and loop.progress() >= _close_s:
		_lapped = true
		_crown(absf(loop.ride_speed()))


## Over the top and home free. One switch, one signal, one sound — and the sound is the
## dome's own: nothing else on this table means "you just did the hardest thing on it".
func _crown(speed: float) -> void:
	_flash = 1.0
	AudioDirector.play(&"dome_loop")
	TableScore.earn(TableScore.GROUP_PENTHOUSE, TableScore.DOME_LOOP, ID_LOOP, _ball, speed)
	loop_completed.emit(speed)
	queue_redraw()


func _on_crested(_speed: float) -> void:
	AudioDirector.play(&"wall_tap")
	returned_home.emit(RETURN_PATH[RETURN_PATH.size() - 1])


# =================================================================== dormancy =====


func set_hardware_active(active: bool) -> void:
	_present = active
	visible = active
	_lapped = false
	if loop != null:
		loop.set_hardware_active(active)
	queue_redraw()


func is_hardware_active() -> bool:
	return _present


# ==================================================================== drawing =====


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 1.2, 0.0)
		queue_redraw()


func _draw() -> void:
	_draw_sky()
	_draw_building()
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, Vector2(DOME_CENTER.x - 96.0, DRUM_BOTTOM - 26.0), "CITY HALL",
				HORIZONTAL_ALIGNMENT_LEFT, -1.0, 30, COL_LEAF.lerp(Feel.COL_NEWSPRINT, 0.25))


## The last of the night sky. The Club paints the board behind its own deck; above that
## there was nothing to see until the dome was bought, so this is where the machine ends.
func _draw_sky() -> void:
	draw_rect(Rect2(Vector2(SKY_LEFT, SKY_TOP), Vector2(SKY_RIGHT - SKY_LEFT,
			SKY_BOTTOM - SKY_TOP)), Feel.COL_INK.darkened(0.25))
	# searchlights over the civic district — two slow wedges painted onto the board
	for i in range(2):
		var base := Vector2(lerpf(SKY_LEFT + 120.0, SKY_RIGHT - 120.0, float(i)), SKY_BOTTOM)
		var tip := base + Vector2(-60.0 + 120.0 * float(i), -430.0)
		draw_colored_polygon(PackedVector2Array([
			base + Vector2(-16.0, 0.0), base + Vector2(16.0, 0.0),
			tip + Vector2(54.0, 0.0), tip + Vector2(-54.0, 0.0),
		]), Color(COL_LEAF.r, COL_LEAF.g, COL_LEAF.b, 0.05))
	for i in range(11):
		var p := Vector2(SKY_LEFT + 60.0 + fmod(float(i) * 197.0, SKY_RIGHT - SKY_LEFT - 120.0),
				SKY_TOP + 40.0 + fmod(float(i) * 131.0, 380.0))
		draw_circle(p, 2.0 + fmod(float(i), 2.0), Feel.COL_NEWSPRINT.darkened(0.55))


## Gold leaf on ink: a drum with pilasters, a ribbed dome, a lantern and a finial, and a rim
## that glows — three arcs of falling alpha rather than a shader, because this table runs on
## GL Compatibility and a low-end phone.
func _draw_building() -> void:
	var spring := Vector2(DOME_CENTER.x, DRUM_TOP)
	var ink := Feel.COL_INK.lightened(0.10)
	var leaf := COL_LEAF.lerp(Feel.COL_NEWSPRINT, _flash * 0.7)

	# steps and the drum
	draw_rect(Rect2(Vector2(DOME_CENTER.x - STEPS_HALF, DRUM_BOTTOM - 6.0),
			Vector2(STEPS_HALF * 2.0, 22.0)), ink.darkened(0.25))
	draw_rect(Rect2(Vector2(DOME_CENTER.x - DRUM_HALF, DRUM_TOP),
			Vector2(DRUM_HALF * 2.0, DRUM_BOTTOM - DRUM_TOP)), ink)
	for i in range(7):
		var x := lerpf(DOME_CENTER.x - DRUM_HALF + 22.0, DOME_CENTER.x + DRUM_HALF - 22.0,
				float(i) / 6.0)
		draw_line(Vector2(x, DRUM_TOP + 14.0), Vector2(x, DRUM_BOTTOM - 12.0),
				leaf.darkened(0.45), 6.0)
	draw_line(Vector2(DOME_CENTER.x - DRUM_HALF, DRUM_TOP),
			Vector2(DOME_CENTER.x + DRUM_HALF, DRUM_TOP), leaf.darkened(0.2), 5.0)

	# the dome itself, ribbed, with the glowing rim over it
	var cap := PackedVector2Array()
	for i in range(25):
		var a := lerpf(PI, TAU, float(i) / 24.0)
		cap.append(spring + Vector2(cos(a), sin(a)) * DOME_R)
	draw_colored_polygon(cap, ink.lightened(0.05))
	for i in range(5):
		var a := lerpf(PI + 0.28, TAU - 0.28, float(i) / 4.0)
		draw_line(spring, spring + Vector2(cos(a), sin(a)) * (DOME_R - 4.0),
				leaf.darkened(0.35), 4.0)
	for i in range(3):
		var glow := Color(leaf.r, leaf.g, leaf.b, (0.55 - 0.15 * float(i)) * (0.55 + _flash * 0.45))
		draw_arc(spring, DOME_R + float(i) * 5.0, PI, TAU, 40, glow, 7.0 - float(i) * 2.0)

	# lantern and finial
	draw_rect(Rect2(Vector2(DOME_CENTER.x - 22.0, spring.y - DOME_R - 34.0), Vector2(44.0, 34.0)),
			ink.lightened(0.08))
	draw_rect(Rect2(Vector2(DOME_CENTER.x - 22.0, spring.y - DOME_R - 34.0), Vector2(44.0, 34.0)),
			leaf.darkened(0.2), false, 3.0)
	draw_line(Vector2(DOME_CENTER.x, spring.y - DOME_R - 34.0),
			Vector2(DOME_CENTER.x, FINIAL_TOP), leaf, 4.0)
	draw_circle(Vector2(DOME_CENTER.x, FINIAL_TOP), 9.0 + _flash * 5.0, leaf)
