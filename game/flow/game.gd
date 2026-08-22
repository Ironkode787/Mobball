extends Node
## The Game autoload — owns the session (specs/m1-hook.md). This stub fixes the public
## surface and implements the SINGLE MONEY PATH; the flow workstream owns the internals
## (state machine, nights, bench, count, save) and must preserve this surface.

signal state_changed(state: StringName)

var wallet := Wallet.new()
var heat := HeatMeter.new()
var stats := Stats.new()
var respect: int = 0
var rank: int = 0
var night_no: int = 0
var bench: RefCounted = null
var state: StringName = &"attract":
	set(v):
		if state == v:
			return
		state = v
		state_changed.emit(v)


func _process(delta: float) -> void:
	heat.tick(delta)


## THE single money path: every dirty payout on the table flows through here.
## base_value × stats add/mult × heat multiplier → wallet; the same post-multiplier
## amount feeds the heat window (hot money is what raises heat, docs/03 §4).
## Flow workstream extends this with the combo multiplier and job hooks.
func earn_switch(group: StringName, base_value: BigMoney, _meta: Dictionary = {}) -> BigMoney:
	var v := base_value.add(stats.value_add(group))
	v = v.mul(stats.value_mult(group))
	if group != &"all":
		v = v.mul(stats.value_mult(&"all"))
	v = v.mul(heat.multiplier())
	wallet.earn_dirty(v)
	heat.on_dirty_earned(v, Rates.rank_scale(rank))
	Events.dirty_earned.emit(v, group)
	return v
