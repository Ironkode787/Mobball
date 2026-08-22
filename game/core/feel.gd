extends Node
## The Feel autoload: every gameplay tuning constant lives here, plus code-registered
## input actions. M0's whole job is iterating these numbers.

# --- ball ---
const BALL_RADIUS := 28.0
const BALL_MAX_SPEED := 4200.0
const BALL_MASS := 1.0

# --- flippers ---
const FLIPPER_LENGTH := 165.0
const FLIPPER_REST_DEG := 28.0        # below horizontal, resting
const FLIPPER_UP_DEG := -26.0         # above horizontal, fully flipped
const FLIPPER_UP_TIME := 0.042        # seconds to full extension
const FLIPPER_DOWN_TIME := 0.075
const INPUT_BUFFER := 0.05            # seconds of early-press forgiveness

# --- plunger ---
const PLUNGER_MAX_IMPULSE := 3400.0
const PLUNGER_CHARGE_TIME := 0.9

# --- nudge / tilt ---
const NUDGE_IMPULSE := 260.0
const TILT_MAX_WARNINGS := 3
const TILT_DECAY_SECONDS := 7.0

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
