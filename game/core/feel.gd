extends Node
## The Feel autoload: every gameplay tuning constant lives here, plus code-registered
## input actions.
##
## Units: the machine is built at 1 unit = 10 cm, real pinball scale (a 20.25" × 42"
## playfield is 5.14 × 10.7 units, the ball is 0.27 across). The playfield root is inclined
## PLAYFIELD_PITCH_DEG so the project's 98.1 u/s² gravity gives the ball the same downhill
## pull a real machine has; every constant below is in units, seconds and radians.
##
## Physics material rule (Jolt): the ball carries friction 1.0 and bounce 0.0 so each surface
## decides what a contact does.

# --- table ---
const PLAYFIELD_PITCH_DEG := 6.5

# --- ball ---
const BALL_RADIUS := 0.135
const BALL_MAX_SPEED := 80.0          # 8 m/s: a hard flip, never a bullet
const BALL_MASS := 1.0
const BALL_LINEAR_DAMP := 0.02
const BALL_ANGULAR_DAMP := 0.05
const BALL_FRICTION := 1.0
const BALL_BOUNCE := 0.0

# --- surfaces ---
const FELT_FRICTION := 0.09       # waxed hardwood, not cloth: a plunged ball skids, then rolls
const FELT_BOUNCE := 0.02
const WALL_FRICTION := 0.14
const WALL_BOUNCE := 0.18
const RUBBER_FRICTION := 0.40
const RUBBER_BOUNCE := 0.58
const STEEL_FRICTION := 0.08
const STEEL_BOUNCE := 0.15
const FLIPPER_FRICTION := 0.70
const FLIPPER_BOUNCE := 0.12

# --- flippers ---
const FLIPPER_LENGTH := 0.78
const FLIPPER_PIVOT_RADIUS := 0.115
const FLIPPER_TIP_RADIUS := 0.07
const FLIPPER_HEIGHT := 0.26
const FLIPPER_REST_DEG := 30.0        # below horizontal, resting
const FLIPPER_UP_DEG := -24.0         # above horizontal, fully flipped
const FLIPPER_UP_TIME := 0.045        # seconds to full extension
const FLIPPER_DOWN_TIME := 0.080
const FLIPPER_UP_EASE := 1.45         # >1 = fast start (ease-out); 1 = linear
const FLIPPER_DOWN_EASE := 1.8        # >1 = slow start (ease-in) on the return
const INPUT_BUFFER := 0.05            # seconds of early-press forgiveness

# --- plunger ---
const PLUNGER_MAX_IMPULSE := 34.0     # u/s straight up the shooter lane at full pull
const PLUNGER_CHARGE_TIME := 0.9
const PLUNGER_DETENTS := 4
const PLUNGER_REST_SPEED := 1.4       # ball must be this calm to be plungeable

# --- nudge / tilt ---
const NUDGE_IMPULSE := 4.0
const NUDGE_UP_BIAS := 0.35
const NUDGE_VISUAL_OFFSET := 0.06     # camera kick, units
const NUDGE_SPRING := 640.0
const NUDGE_DAMP := 22.0
const NUDGE_COOLDOWN := 0.12
const TILT_MAX_WARNINGS := 3
const TILT_DECAY_SECONDS := 7.0

# --- hardware ---
const BUMPER_RADIUS := 0.29
const BUMPER_IMPULSE := 22.0
const BUMPER_COOLDOWN := 0.10
const HARDWARE_STALL_SPEED := 0.8     # a ball asleep on live hardware gets popped loose
const FLIPPER_PIVOT_POP := 5.0
const FLIPPER_PIVOT_STALL_SECONDS := 2.0
const BUMPER_VALUE := 10
# A real slingshot is a switch behind the rubber and a kicker arm: nothing happens until the
# ball actually compresses the long face hard enough to close the switch, then the arm throws
# the ball out perpendicular to the rubber at the kicker's own pace, keeping most of the slide
# the ball had along the band. The short faces and the posts are plain rubber.
const SLING_KICK_SPEED := 24.0        # u/s out along the face normal, whatever came in
const SLING_KICK_GAIN := 0.25         # plus this share of the approach speed
const SLING_TRIGGER_SPEED := 2.5      # approach speed that closes the switch; slower is silent rubber
const SLING_TANGENT_KEEP := 0.8       # how much of the slide along the rubber survives the throw
const SLING_COOLDOWN := 0.12          # the arm's dead time
const SLING_VALUE := 5
const KICKBACK_IMPULSE := 30.0
const MAGNET_IMPULSE := 9.0

# --- table service ---
const RESPAWN_DELAY := 1.0
const BALL_SEARCH_DELAY := 5.0
const BALL_SEARCH_REPEAT := 2.5
const BALL_SEARCH_SPEED := 0.5
const BALL_SEARCH_IMPULSE := 10.0

# --- physics layer bits (mirrors project.godot layer_names) ---
const LAYER_WALLS := 1 << 0
const LAYER_BALL := 1 << 1
const LAYER_FLIPPERS := 1 << 2
const LAYER_HARDWARE := 1 << 3
const LAYER_ZONES := 1 << 4
const BALL_MASK := LAYER_WALLS | LAYER_FLIPPERS | LAYER_HARDWARE

# --- palette (docs/07 §1) ---
const COL_INK := Color("12100E")
const COL_NEWSPRINT := Color("F2E8D5")
const COL_FELT := Color("1E3D2F")
const COL_BRASS := Color("C9A227")
const COL_DIRTY := Color("E23D3D")
const COL_CLEAN := Color("3FBF6F")
const COL_VIOLET := Color("8C4DFF")
const COL_NEON_ROSE := Color("FF2E63")
const COL_NEON_TEAL := Color("2EE6D6")
const COL_COP := Color("3A8DFF")

# --- desktop dev keys (touch zones handled by InputController) ---
const _KEYS := {
	&"flipper_left": [KEY_A, KEY_LEFT],
	&"flipper_right": [KEY_D, KEY_RIGHT],
	&"plunger": [KEY_SPACE],
	&"nudge_left": [KEY_Q],
	&"nudge_right": [KEY_E],
	&"nudge_up": [KEY_W],
}


func _enter_tree() -> void:
	for action: StringName in _KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: Key in _KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action, ev)


## Rest/extended yaw of a flipper bat for the given side. Geometry always points along local
## +X; the right bat is the same shape turned around. Yaw about +Y: a bat resting "down" (tip
## toward the player, +z) needs a negative yaw on the left and PI + positive on the right.
func flipper_rest_rotation(side: StringName) -> float:
	if side == &"right":
		return PI + deg_to_rad(FLIPPER_REST_DEG)
	return -deg_to_rad(FLIPPER_REST_DEG)


func flipper_up_rotation(side: StringName) -> float:
	if side == &"right":
		return PI + deg_to_rad(FLIPPER_UP_DEG)
	return -deg_to_rad(FLIPPER_UP_DEG)


func ball_material() -> PhysicsMaterial:
	return make_material(BALL_FRICTION, BALL_BOUNCE)


func make_material(friction: float, bounce: float) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = bounce
	return m


## Gravity component along the inclined playfield (toward the player, +z in table space).
func slope_gravity() -> float:
	return float(ProjectSettings.get_setting("physics/3d/default_gravity", 98.1)) \
			* sin(deg_to_rad(PLAYFIELD_PITCH_DEG))
