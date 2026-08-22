extends Node
## The Feel autoload: every gameplay tuning constant lives here, plus code-registered
## input actions. M0's whole job is iterating these numbers.
##
## Godot 2D combines surface materials as: bounce = clamp(a + b, 0, 1), friction = min(a, b).
## That is why the ball carries friction 1.0 (so each surface decides) and bounce 0.0.

# --- ball ---
const BALL_RADIUS := 28.0
const BALL_MAX_SPEED := 4000.0
const BALL_MASS := 1.0
const BALL_LINEAR_DAMP := 0.06
const BALL_FRICTION := 1.0
const BALL_BOUNCE := 0.0

# --- surfaces ---
const WALL_FRICTION := 0.14
const WALL_BOUNCE := 0.28
const RUBBER_FRICTION := 0.45
const RUBBER_BOUNCE := 0.42
const FLIPPER_FRICTION := 0.78
const FLIPPER_BOUNCE := 0.10

# --- flippers ---
const FLIPPER_LENGTH := 165.0
const FLIPPER_PIVOT_RADIUS := 26.0
const FLIPPER_TIP_RADIUS := 16.0
const FLIPPER_REST_DEG := 28.0        # below horizontal, resting
const FLIPPER_UP_DEG := -26.0         # above horizontal, fully flipped
const FLIPPER_UP_TIME := 0.042        # seconds to full extension
const FLIPPER_DOWN_TIME := 0.075
const FLIPPER_UP_EASE := 1.45         # >1 = fast start (ease-out); 1 = linear
const FLIPPER_DOWN_EASE := 1.8        # >1 = slow start (ease-in) on the return
const INPUT_BUFFER := 0.05            # seconds of early-press forgiveness

# --- plunger ---
const PLUNGER_MAX_IMPULSE := 3900.0
const PLUNGER_CHARGE_TIME := 0.9
const PLUNGER_DETENTS := 4            # audible ratchet clicks across the pull
const PLUNGER_REST_SPEED := 60.0      # ball must be this calm to be plungeable

# --- nudge / tilt ---
const NUDGE_IMPULSE := 260.0
const NUDGE_UP_BIAS := 0.35           # how much of a side nudge lifts the ball
const NUDGE_VISUAL_OFFSET := 6.0      # px the cabinet kicks on screen
const NUDGE_SPRING := 640.0           # cabinet spring constant (1/s^2)
const NUDGE_DAMP := 22.0              # cabinet damping (1/s)
const NUDGE_COOLDOWN := 0.12
const TILT_MAX_WARNINGS := 3
const TILT_DECAY_SECONDS := 7.0

# --- hardware ---
const BUMPER_RADIUS := 46.0
const BUMPER_IMPULSE := 900.0
const BUMPER_COOLDOWN := 0.10
const BUMPER_VALUE := 10
const SLING_IMPULSE := 750.0
const SLING_COOLDOWN := 0.08
const SLING_VALUE := 5

# --- table service ---
const RESPAWN_DELAY := 1.0

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


## Rest/extended rotation of a flipper bat, in radians, for the given side.
## Geometry always points along local +X; the right bat is the same shape turned around.
func flipper_rest_rotation(side: StringName) -> float:
	if side == &"right":
		return PI - deg_to_rad(FLIPPER_REST_DEG)
	return deg_to_rad(FLIPPER_REST_DEG)


func flipper_up_rotation(side: StringName) -> float:
	if side == &"right":
		return PI + deg_to_rad(-FLIPPER_UP_DEG)
	return deg_to_rad(FLIPPER_UP_DEG)


func ball_material() -> PhysicsMaterial:
	return make_material(BALL_FRICTION, BALL_BOUNCE)


func make_material(friction: float, bounce: float) -> PhysicsMaterial:
	var m := PhysicsMaterial.new()
	m.friction = friction
	m.bounce = bounce
	return m
