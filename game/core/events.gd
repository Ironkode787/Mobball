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

signal tilt_cleared

# --- plunger ---
signal plunger_charge_changed(power: float)

# --- table switches (everything scoring flows through here) ---
signal switch_hit(id: StringName, ball: Node2D, strength: float)
## Per-piece payout of a switch. Emitted alongside switch_hit so scoring consumers
## (debug HUD now, economy later) never have to own a hardware→value table.
signal scored(id: StringName, value: int)
