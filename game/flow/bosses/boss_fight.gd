class_name BossFight
extends Node
## A Commission encounter (docs/05 §6, specs/m2-content.md §5). The shared frame; the two
## fights are `sammy.gd` and `butcher.gd`.
##
## A fight REPLACES a Night. The state stays `&"night"` and the NightController still fields
## guys, serves balls and pinches whoever drains — what changes is that the economy is off
## (`economy_paused`, read by `Game.earn_switch`), there is no clock, and the table is wearing
## somebody else's hardware. Pressure is mechanical: the sedan moves, the wrench comes out,
## the cans are worthless. Beating him is the rank-up ceremony (`Commission.rank_cap`), losing
## him costs nothing but the Night.
##
## Same division of labour as the raid: the mode owns the phases and the telegraphs, the table
## owns the hardware (`set_boss_target` / `set_boss_goons` / `set_boss_door`), and `Game` owns
## every cent that moves. Nothing in here touches a wallet.

## The fight is over. `won` false is a loss, which is only ever "the Night ran out".
signal finished(won: bool)
## Phase, hits, meter — whatever the HUD and The Count want to show.
signal changed(state: Dictionary)

## Where the two fights live. Loaded by path rather than by class so this base file does not
## have to name its own subclasses (a parse-time cycle).
const SCRIPTS := {
	Commission.SAMMY: "res://game/flow/bosses/sammy.gd",
	Commission.BUTCHER: "res://game/flow/bosses/butcher.gd",
}

## Beat between phases: the old hardware goes down, the next comes up, nobody is cheated by
## a target appearing under a ball already in flight.
const PHASE_BEAT := 1.4

var id: StringName = &""
var boss_name: String = ""
## ★ Reputation Precedes You (docs/06 §3): the city's first fight opens at this phase instead
## of at the beginning. 1 is every fight as shipped.
var start_phase: int = 1
var phases: int = 3
## Read by `Game.earn_switch`: while a fight is live the table earns nothing at all.
var economy_paused: bool = true
var active: bool = false
var won: bool = false
## Decided but not finished: the Butcher is beaten when his door goes the second time, and
## his last phase is the payout lap. A Night that runs out after this still won the fight.
var secured: bool = false
## 0 before the first phase, 1..phases while fighting, phases+1 once he is down.
var phase: int = 0

var table: Node3D = null
## The NightController running this Night (typed loosely — night.gd and this file must not
## reference each other's classes).
var night: Node = null

var _beat_left: float = 0.0
var _next_phase: int = 0


func _ready() -> void:
	set_physics_process(false)


## The fight for a Commission id, or null if that boss has no script yet.
static func make(fight_id: StringName) -> BossFight:
	var path := String(SCRIPTS.get(fight_id, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var script: GDScript = load(path)
	if script == null:
		return null
	var made: Object = script.new()
	var fight := made as BossFight
	if fight == null:
		return null
	fight.id = fight_id
	fight.boss_name = String(Commission.fight(fight_id).get("name", String(fight_id)))
	return fight


# ================================================================== lifecycle =====


func begin(p_table: Node3D, p_night: Node) -> void:
	if active:
		return
	table = p_table
	night = p_night
	active = true
	won = false
	secured = false
	phase = 0
	TableAPI.call_if(table, "clear_boss")
	_connect_table(&"boss_hit", _on_boss_hit)
	_connect_table(&"boss_shrugged", _on_boss_shrugged)
	_connect_table(&"boss_down", _on_boss_down)
	AudioDirector.play(&"boss_start")
	AudioDirector.play(&"knocker")
	AudioDirector.music_set_state(&"hot")
	set_physics_process(true)
	_go_to_phase(clampi(start_phase, 1, phases))


## Shut the fight down without deciding it (the Night was torn down mid-fight).
func abort() -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	_release()


## The Night ran out. He wins unless the fight was already decided.
func lose() -> void:
	if not active:
		return
	_end(secured)


func _end(victory: bool) -> void:
	if not active:
		return
	active = false
	won = victory
	set_physics_process(false)
	_release()
	finished.emit(victory)


func _release() -> void:
	economy_paused = false
	_on_release()
	TableAPI.call_if(table, "clear_boss")
	for row: Array in [[&"boss_hit", _on_boss_hit], [&"boss_shrugged", _on_boss_shrugged],
			[&"boss_down", _on_boss_down]]:
		if table != null and is_instance_valid(table) and table.has_signal(row[0]) \
				and table.is_connected(row[0], row[1]):
			table.disconnect(row[0], row[1])


# ==================================================================== phases =====


func _physics_process(delta: float) -> void:
	if not active:
		return
	if _beat_left > 0.0:
		_beat_left -= delta
		if _beat_left <= 0.0:
			_beat_left = 0.0
			_start_phase(_next_phase)
		return
	_tick(delta)


## Take the current phase down and bring the next one up after a beat.
func _go_to_phase(n: int) -> void:
	_next_phase = n
	_beat_left = PHASE_BEAT if phase > 0 else 0.01
	TableAPI.call_if(table, "clear_boss")
	if phase > 0:
		AudioDirector.play(&"boss_phase")
		AudioDirector.play(&"drop_bank_reset")


func _start_phase(n: int) -> void:
	phase = n
	if n > phases:
		_win()
		return
	_enter_phase(n)
	announce()


## He's down: the ceremony is the NightController's and `Game`'s, not this file's.
func _win() -> void:
	AudioDirector.play(&"boss_beaten")
	_end(true)


## Push the fight's shape at whoever is drawing it.
func announce() -> void:
	var s := state()
	changed.emit(s)
	if Game != null:
		Game.boss_changed.emit(s)


func state() -> Dictionary:
	return {
		"id": id,
		"name": boss_name,
		"phase": mini(phase, phases),
		"phases": phases,
		"active": active,
		"won": won,
		"line": phase_line(),
	}


# ============================================================ subclass surface =====
##
## Everything below is what a fight overrides. The base class does nothing, so a half-written
## boss is a boss who stands there — never a crash mid-Night.


func _enter_phase(_n: int) -> void:
	pass


func _tick(_delta: float) -> void:
	pass


func _on_release() -> void:
	pass


## One line for the HUD: what is being asked of the player right now.
func phase_line() -> String:
	return ""


func _on_hit(_kind: StringName, _hits_left: int, _speed: float) -> void:
	pass


func _on_shrug(_kind: StringName, _speed: float) -> void:
	pass


func _on_down(_kind: StringName) -> void:
	pass


## A switch the paused economy refused to pay, with what it would have been worth. The
## Butcher's cold storage is built out of exactly this (specs/m2-content.md §5).
func on_denied(_group: StringName, _value: BigMoney) -> void:
	pass


## Forwarded by the NightController: the top lanes, for the Butcher's hidden ×2.
func on_rollover(_index: int, _was_lit: bool) -> void:
	pass


## Forwarded by the NightController: a guy just went inside. A fight is not lost by a pinch —
## the Night has three of them — but a phase may want to reset its hardware.
func on_guy_lost() -> void:
	pass


# ==================================================================== helpers =====


func _on_boss_hit(kind: StringName, hits_left: int, speed: float) -> void:
	if active and _beat_left <= 0.0:
		_on_hit(kind, hits_left, speed)


func _on_boss_shrugged(kind: StringName, speed: float) -> void:
	if active:
		_on_shrug(kind, speed)


func _on_boss_down(kind: StringName) -> void:
	if active and _beat_left <= 0.0:
		_on_down(kind)


func _connect_table(signal_name: StringName, to: Callable) -> bool:
	if table == null or not is_instance_valid(table) or not table.has_signal(signal_name):
		return false
	if not table.is_connected(signal_name, to):
		table.connect(signal_name, to)
	return true


## Put a wrench through one bat. The Night owns the flippers and Sammy's Spare, so it decides
## what actually lands; this is the ask. Returns whether the jam took.
func _jam(side: StringName, seconds: float) -> bool:
	if night == null or not is_instance_valid(night) or not night.has_method("jam_flipper"):
		return false
	return bool(night.call("jam_flipper", side, seconds))


func _telegraph(side: StringName, seconds: float) -> void:
	if night != null and is_instance_valid(night) and night.has_method("telegraph_flipper"):
		night.call("telegraph_flipper", side, seconds)
