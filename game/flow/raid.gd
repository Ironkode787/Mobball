class_name RaidMode
extends Node
## RAID (docs/05 §2, specs/m1-hook.md Lane 1 "Raid v1"). Heat hit 100; keep the guy alive
## for 45 seconds.
##
## The mode owns the clock, the Captain's magnet and the telegraph; the NightController
## owns the consequences (payout, confiscation, heat reset) so all money stays on one path.
## Cop targets and the red wash belong to the table — this asks for them through
## `set_raid_active()` and shrugs if the table has not shipped it yet.

## survived = true ("Beat the Rap"), false = busted.
signal finished(survived: bool)

const DURATION := 45.0
## The Captain yanks the ball drain-ward on this period, telegraphed a beat early.
const MAGNET_PERIOD := 6.0
const TELEGRAPH := 1.2
const MAGNET_IMPULSE := 620.0
## Table tint while the sirens are on.
const DARKEN := Color(0.62, 0.48, 0.52, 1.0)

var active: bool = false
## Seconds of survival pinball. Defaults to the design's 45; the flow sim shortens it so a
## headless run does not have to spend three quarters of a minute of wall clock per branch.
var duration: float = DURATION
var time_left: float = DURATION

var _table: Node2D = null
var _next_magnet: float = MAGNET_PERIOD
var _telegraphed: bool = false


func _ready() -> void:
	set_physics_process(false)


func begin(table: Node2D) -> void:
	if active:
		return
	_table = table
	active = true
	time_left = duration
	_next_magnet = MAGNET_PERIOD
	_telegraphed = false
	TableAPI.call_if(_table, "set_raid_active", [true])
	AudioDirector.play(&"raid_start")
	AudioDirector.music_set_state(&"raid")
	Events.raid_started.emit()
	set_physics_process(true)


## The guy on the table just drained: the raid is lost.
func on_guy_lost() -> void:
	if not active:
		return
	_end(false)


## Shut the mode down without deciding an outcome (Night torn down mid-raid).
func abort() -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	_release_table()


func _physics_process(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	if time_left <= 0.0:
		_end(true)
		return

	var since := duration - time_left
	if not _telegraphed and since >= _next_magnet - TELEGRAPH:
		_telegraphed = true
		AudioDirector.play(&"siren")
	if since >= _next_magnet:
		_next_magnet += MAGNET_PERIOD
		_telegraphed = false
		_pull_ball()


## The Captain's magnet: a drain-ward tug, counterable with a flip or a Lean. The table owns
## the hardware if it has one (`magnet_pull`); otherwise flow tugs the ball itself.
func _pull_ball() -> void:
	if _table == null or not is_instance_valid(_table):
		return
	if _table.has_method("magnet_pull"):
		_table.call("magnet_pull")
		return
	var b := TableAPI.ball(_table)
	if b == null:
		return
	var target := _drain_point()
	var dir := (target - b.global_position)
	if dir.length() < 1.0:
		return
	b.kick(dir.normalized() * MAGNET_IMPULSE)


func _drain_point() -> Vector2:
	var r := TableAPI.bounds(_table, Rect2(Vector2(40.0, 0.0), Vector2(900.0, 1900.0)))
	return Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y)


func _end(survived: bool) -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	_release_table()
	finished.emit(survived)


func _release_table() -> void:
	TableAPI.call_if(_table, "set_raid_active", [false])
