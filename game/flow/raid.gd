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
const MAGNET_IMPULSE := 6.2
## The siren sits under the mode, not on top of it.
const SIREN_DB := -6.0
## Table tint while the sirens are on.
const DARKEN := Color(0.62, 0.48, 0.52, 1.0)

var active: bool = false
## Seconds of survival pinball. Defaults to the design's 45; the flow sim shortens it so a
## headless run does not have to spend three quarters of a minute of wall clock per branch.
var duration: float = DURATION
var time_left: float = DURATION

var _table: Node3D = null
var _next_magnet: float = MAGNET_PERIOD
var _telegraphed: bool = false
## One looping wail under the whole mode, stopped when the mode ends (specs/audio-wave2 §1:
## `siren` is a 7 s loopable bed, not a per-telegraph chirp).
var _siren: AudioStreamPlayer = null


func _ready() -> void:
	set_physics_process(false)


func begin(table: Node3D) -> void:
	if active:
		return
	_table = table
	active = true
	time_left = duration
	_next_magnet = MAGNET_PERIOD
	_telegraphed = false
	TableAPI.call_if(_table, "set_raid_active", [true])
	AudioDirector.play(&"raid_start")
	_siren = AudioDirector.play(&"siren", {"loop": true, "volume_db": SIREN_DB})
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
		# A table with its own magnet draws and sounds the warning itself; without one,
		# flow still owes the player a beat of notice before the yank.
		if not _has_table_magnet():
			AudioDirector.play(&"siren", {"volume_db": SIREN_DB})
	if since >= _next_magnet:
		_next_magnet += MAGNET_PERIOD
		_telegraphed = false
		_pull_ball()


func _has_table_magnet() -> bool:
	return _table != null and is_instance_valid(_table) and _table.has_method("magnet_pull")


## The Captain's magnet: a drain-ward tug, counterable with a flip or a Lean. The table owns
## the hardware if it has one (`magnet_pull`); otherwise flow tugs the ball itself.
func _pull_ball() -> void:
	if _table == null or not is_instance_valid(_table):
		return
	if _has_table_magnet():
		_table.call("magnet_pull")
		return
	var b := TableAPI.ball(_table)
	if b == null:
		return
	var here := Layout.plan(b.table_position())
	var dir := _drain_point() - here
	if dir.length() < 0.01:
		return
	b.kick(Vector3(dir.x, 0.0, dir.y).normalized() * MAGNET_IMPULSE)


func _drain_point() -> Vector2:
	return Layout.CENTRE_DRAIN_AT


func _end(survived: bool) -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	_release_table()
	finished.emit(survived)


func _release_table() -> void:
	TableAPI.call_if(_table, "set_raid_active", [false])
	if _siren != null and is_instance_valid(_siren):
		_siren.stop()
	_siren = null
