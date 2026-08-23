class_name RicoRaid
extends Node
## THE RICO RAID (docs/05 §9). Two minutes, three phases, and the whole city in the room. It
## REPLACES a Night: the guys are fielded as usual and the economy stays on, but this is what
## the Night is, and it ends the moment the last man is inside.
##
## Same division of labour as `RaidMode`, which this is the big brother of: the mode owns the
## phases, the telegraphs and the magnet; the NightController owns the consequences; the table
## owns its own hardware and shrugs if it has not grown it yet.
##
##   1. **STREET SWEEP** — every cop on the block, working twice as fast.
##   2. **THE WIRETAP** — the mix comes apart one bus at a time (`AudioDirector.rico_dropout`,
##      docs/08 §4). Losing the audio IS the phase, so every cue in it is also visual: the
##      magnet keeps its on-table telegraph and the HUD keeps the clock. Nothing in this
##      phase may arrive on the audio channel alone.
##   3. **THE DIRECTOR** — he does not send anybody. He pulls the ball himself, twice a beat.

## survived = true (UNTOUCHABLE), false = the case sticks.
signal finished(survived: bool)
## Phase, seconds, wiretap step — HUD fodder, and the redundancy phase 2 depends on.
signal changed(state: Dictionary)

const DURATION := 120.0
const PHASES := 3
## The Captain's magnet, phase by phase: the sweep is a raid, the wiretap is quiet, and the
## Director is two hands on the ball.
const MAGNET_PERIOD := 6.0
const DIRECTOR_PERIOD := 3.0
const DIRECTOR_PULLS := 2
const DIRECTOR_PULL_GAP := 0.35
const TELEGRAPH := 1.2
const MAGNET_IMPULSE := 700.0
const SIREN_DB := -4.0

## Phase 1 asks the table to run its raid hardware at double speed.
const SWEEP_SPEED := 2.0

var active: bool = false
var duration: float = DURATION
var time_left: float = DURATION
var phase: int = 0
## 0 = the mix is whole; 1..3 are the wires the Feds have cut.
var wiretap_step: int = 0

var _table: Node2D = null
var _phase_left: float = 0.0
var _next_magnet: float = MAGNET_PERIOD
var _telegraphed: bool = false
var _since: float = 0.0
var _siren: AudioStreamPlayer = null
## Queued extra pulls for the Director's double yank.
var _extra_pull: float = -1.0
var _extra_left: int = 0


func _ready() -> void:
	set_physics_process(false)


func begin(table: Node2D) -> void:
	if active:
		return
	_table = table
	active = true
	time_left = duration
	phase = 0
	wiretap_step = 0
	_since = 0.0
	_next_magnet = MAGNET_PERIOD
	_telegraphed = false
	TableAPI.call_if(_table, "set_raid_active", [true])
	AudioDirector.play(&"rico_start")
	AudioDirector.play(&"raid_start")
	_siren = AudioDirector.play(&"siren", {"loop": true, "volume_db": SIREN_DB})
	AudioDirector.music_set_state(&"raid")
	Events.raid_started.emit()
	set_physics_process(true)
	_enter_phase(1)


## The last guy went inside: the case sticks.
func on_guy_lost() -> void:
	if active:
		_end(false)


## Torn down without a verdict (the Night was stopped mid-raid).
func abort() -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	_release()


func phase_line() -> String:
	match phase:
		1:
			return "STREET SWEEP"
		2:
			return "WIRETAP"
		3:
			return "THE DIRECTOR"
	return ""


func state() -> Dictionary:
	return {
		"active": active,
		"phase": phase,
		"phases": PHASES,
		"line": phase_line(),
		"time_left": time_left,
		"wiretap": wiretap_step,
	}


# ==================================================================== the phases =====


func _physics_process(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	_since += delta
	if time_left <= 0.0:
		_end(true)
		return

	_phase_left -= delta
	if _phase_left <= 0.0 and phase < PHASES:
		_enter_phase(phase + 1)

	if phase == 2:
		_tick_wiretap()
	_tick_magnet(delta)


func _enter_phase(n: int) -> void:
	phase = n
	_phase_left = duration / float(PHASES)
	_next_magnet = _since + _period()
	_telegraphed = false
	match n:
		1:
			# Every cop on the block, at double time. The table owns the hardware; a table
			# that cannot run it faster simply runs it at one.
			TableAPI.call_if(_table, "set_raid_speed", [SWEEP_SPEED])
		2:
			TableAPI.call_if(_table, "set_raid_speed", [1.0])
			_set_wiretap(1)
		3:
			# The wires come back — he wants you to hear this part.
			_set_wiretap(0)
			AudioDirector.play(&"rico_director")
			AudioDirector.play(&"knocker")
	AudioDirector.play(&"boss_phase")
	changed.emit(state())


## The mix comes apart across the phase, one bus per third of it.
func _tick_wiretap() -> void:
	var into := 1.0 - clampf(_phase_left / maxf(duration / float(PHASES), 0.001), 0.0, 1.0)
	_set_wiretap(1 + int(into * float(AudioDirector.RICO_STEPS - 1) + 0.0001))


func _set_wiretap(step: int) -> void:
	var want := clampi(step, 0, AudioDirector.RICO_STEPS)
	if want == wiretap_step:
		return
	wiretap_step = want
	# The audio lane owns the dropout itself (docs/08 §4). Guarded, because a director that
	# has not grown it yet must cost the phase its sound, never the Night.
	if AudioDirector.has_method("rico_dropout"):
		AudioDirector.call("rico_dropout", wiretap_step)
	changed.emit(state())


func _period() -> float:
	return DIRECTOR_PERIOD if phase >= PHASES else MAGNET_PERIOD


## The magnet, with the Director's second hand on it in the last phase.
func _tick_magnet(delta: float) -> void:
	if _extra_left > 0:
		_extra_pull -= delta
		if _extra_pull <= 0.0:
			_extra_left -= 1
			_extra_pull = DIRECTOR_PULL_GAP
			_pull_ball()
	if not _telegraphed and _since >= _next_magnet - TELEGRAPH:
		_telegraphed = true
		# The telegraph is the table's when it has a magnet of its own; without one flow owes
		# the player the warning itself — and in phase 2 that warning cannot be audio alone,
		# which is what `changed` is for.
		if not _has_table_magnet():
			AudioDirector.play(&"siren", {"volume_db": SIREN_DB})
		changed.emit(state())
	if _since < _next_magnet:
		return
	_next_magnet = _since + _period()
	_telegraphed = false
	_pull_ball()
	if phase >= PHASES:
		_extra_left = DIRECTOR_PULLS - 1
		_extra_pull = DIRECTOR_PULL_GAP


func _has_table_magnet() -> bool:
	return _table != null and is_instance_valid(_table) and _table.has_method("magnet_pull")


func _pull_ball() -> void:
	if _table == null or not is_instance_valid(_table):
		return
	if _has_table_magnet():
		_table.call("magnet_pull")
		return
	var b := TableAPI.ball(_table)
	if b == null:
		return
	var r := TableAPI.bounds(_table, Rect2(Vector2(40.0, 0.0), Vector2(900.0, 1900.0)))
	var target := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y)
	var dir := target - b.global_position
	if dir.length() < 1.0:
		return
	b.kick(dir.normalized() * MAGNET_IMPULSE)


func _end(survived: bool) -> void:
	if not active:
		return
	active = false
	set_physics_process(false)
	_release()
	finished.emit(survived)


func _release() -> void:
	_set_wiretap(0)
	TableAPI.call_if(_table, "set_raid_speed", [1.0])
	TableAPI.call_if(_table, "set_raid_active", [false])
	if _siren != null and is_instance_valid(_siren):
		_siren.stop()
	_siren = null
