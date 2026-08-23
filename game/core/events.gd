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

# --- M1 session & economy flow (specs/m1-hook.md) ---
signal night_started(night_no: int)
signal night_ended(summary: Dictionary)
signal upgrade_purchased(id: String, level: int)
signal rank_changed(rank: int)
signal respect_changed(total: int)
signal raid_started
signal raid_ended(survived: bool)
signal job_assigned(id: String)
signal job_completed(id: String, respect: int)
signal laundered(amount: BigMoney)
signal combo_changed(count: int)
signal skill_shot
signal guy_pinched(guy: Dictionary)
signal guy_bailed(guy: Dictionary)
signal dirty_earned(amount: BigMoney, group: StringName)
signal storefront_collected(id: StringName)
## Game.boot() finished restoring a career (fresh or from a save). Anything that mirrors
## Stats into the world — the table's hardware above all — re-reads on this. Purchases
## fire upgrade_purchased; a RESTORED save fires only this (first device save bug: the
## table refreshed on purchases and at its own _ready, which runs before the load).
signal session_booted
