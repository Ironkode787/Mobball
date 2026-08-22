extends Node
## Global signal bus. Cross-system events only — keep local wiring local.

# --- ball lifecycle ---
signal ball_spawned(ball: Node2D)
signal ball_launched(ball: Node2D, power: float)
signal ball_drained(ball: Node2D)

# --- player input results ---
signal flipper_fired(side: StringName)          # &"left" / &"right"
signal nudged(direction: Vector2)
signal tilt_warning(count: int, max_count: int)
signal tilted

# --- table switches (everything scoring flows through here) ---
signal switch_hit(id: StringName, ball: Node2D, strength: float)
