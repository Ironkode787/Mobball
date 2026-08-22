extends Node
## AudioDirector autoload. Gameplay calls AudioDirector.play(&"event") and never touches
## files. Event → asset mapping is owned by the audio workstream (specs/audio-pipeline.md).
## Missing assets fail silent (logged once) so gameplay never depends on audio being built.
##
## Everything under assets/audio/ is synthesised by tools/audiogen — no samples, no
## licences. Regenerate with `python3 tools/audiogen/generate.py`.
##
## Two Godot 4.5 details this file depends on, both verified headless:
##   * AudioStreamSynchronized.set_sync_stream_volume() takes DECIBELS, not a linear
##     gain. Passing 0.0 expecting silence gives full level instead; -80 is silence.
##     Volume changes apply live during playback, which is what makes the fades work.
##   * An imported .ogg loads with loop = false. The flag has to be set on the loaded
##     resource, otherwise the stack plays through once and stops.

# --- assets ---------------------------------------------------------------------
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/city1/"

## City-1 stem stack, in the order they fade in as the empire grows (docs/08 §1).
const STEMS: PackedStringArray = [
	"01_bass", "02_drums", "03_vibes", "04_trumpet",
	"05_organ", "06_barisax", "07_strings", "08_full",
]

## Every §4 event. Used for warm-up and by tests/test_audio_assets.gd.
const EVENTS: PackedStringArray = [
	"flipper_up", "flipper_down", "bumper_hit", "sling_hit", "plunger_pull",
	"plunger_launch", "ball_spawn", "drain", "nudge_thump", "tilt_warning", "tilt",
	"knocker", "cash_tick", "chime_a", "chime_b", "chime_c", "wall_tap",
]

# --- voices ---------------------------------------------------------------------
const MAX_VOICES := 24
## pitch_jitter is measured in octaves: 0.05 is ±60 cents, enough that two flipper
## hits in a row are never the same sound, small enough that nothing sounds broken.
const DEFAULT_PITCH_JITTER := 0.05
const PITCH_MIN := 0.5
const PITCH_MAX := 2.0

## Pitched events get much less jitter — the chimes are tuned to D5/F5/A5 and have to
## agree with the music, and a detuned replay knocker sounds like a fault, not variety.
const EVENT_PITCH_JITTER := {
	&"chime_a": 0.008, &"chime_b": 0.008, &"chime_c": 0.008,
	&"tilt_warning": 0.010, &"tilt": 0.010, &"knocker": 0.020,
	&"cash_tick": 0.060,
}

# --- buses ----------------------------------------------------------------------
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_MECHANICS := &"Mechanics"
const BUS_FICTION := &"Fiction"
const BUS_UI := &"UI"

## The machine is a physical object in the room; the story is not (docs/08 §2).
const FICTION_EVENTS: PackedStringArray = [
	"chime_a", "chime_b", "chime_c", "knocker", "cash_tick",
]

## All eight stems at unity sum to about +1 dBFS, so the music bus carries the trim
## that keeps the full stack under the ceiling and leaves room for the table on top.
const MUSIC_BUS_DB := -4.0

# --- music ----------------------------------------------------------------------
const MUSIC_FADE_SECONDS := 1.5
const SILENT_DB := -80.0
const AUDIBLE_DB := 0.0

var _missing_logged: Dictionary = {}
var _sfx: Dictionary = {}                       # StringName -> AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _voice_started: PackedFloat64Array = []
var _rng := RandomNumberGenerator.new()

var _music_player: AudioStreamPlayer
var _music_sync: AudioStreamSynchronized
var _stem_slot: PackedInt32Array = []           # stem index -> slot in the sync, or -1
var _stem_db: PackedFloat32Array = []
var _stem_target_db: PackedFloat32Array = []
var _music_level := 0
var _music_stopping := false
var _initialised := false


func _ready() -> void:
	_ensure_init()
	set_process(false)


## Autoloads get _ready() from the running scene tree, and the headless test runner
## (a bare SceneTree script) never gets that far. Setting up on first use instead means
## the same code paths are exercised in CI as in the game.
func _ensure_init() -> void:
	if _initialised:
		return
	_initialised = true
	_rng.randomize()
	_ensure_buses()
	_build_voice_pool()
	_warm_sfx_cache()


# =============================================================== public API =====


## Fire a one-shot sound effect.
## opts: `pitch_jitter` (octaves, default 0.05), `pitch_scale` (explicit, skips jitter),
## `volume_db`, `bus`. Returns the voice it grabbed, or null if the asset is missing.
func play(event: StringName, opts: Dictionary = {}) -> AudioStreamPlayer:
	_ensure_init()
	var stream: AudioStream = _sfx_stream(event)
	if stream == null:
		return null

	var voice: AudioStreamPlayer = _take_voice()
	if voice == null:
		return null

	voice.stream = stream
	voice.bus = _bus_for(event, opts)
	voice.volume_db = float(opts.get("volume_db", 0.0))
	voice.pitch_scale = _pitch_for(event, opts)
	# In the headless test runner the scene tree is not live yet; configuring the voice
	# is still worth doing (and testable) but play() would push an engine error.
	if voice.is_inside_tree():
		voice.play()
	return voice


## Silence every one-shot voice. Music is unaffected.
func stop_all() -> void:
	_ensure_init()
	for voice in _voices:
		voice.stop()


## Start the stem stack. Idempotent: calling it while playing does nothing.
func music_start() -> void:
	_ensure_init()
	if not _build_music():
		return
	_music_stopping = false
	if not _music_player.playing and _music_player.is_inside_tree():
		_music_player.play()
	set_process(true)


## `level` = how many stems are audible, 0 through STEMS.size(). Level n means the
## first n stems of the stack; the rest fade out. Fades take MUSIC_FADE_SECONDS.
func music_set_level(level: int) -> void:
	_ensure_init()
	_music_level = clampi(level, 0, STEMS.size())
	if _music_sync == null:
		return
	for i in STEMS.size():
		_stem_target_db[i] = AUDIBLE_DB if i < _music_level else SILENT_DB
	_music_stopping = false
	set_process(true)


## Currently requested level (not the same as "done fading").
func music_level() -> int:
	return _music_level


func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing


## CONTRACT STUB (specs/audio-wave2.md §2): state mixes over the synced stack.
## calm | hot | raid | count. The audio workstream's wave-2 delivery replaces this
## no-op with the real per-state mix; gameplay may call it freely today.
func music_set_state(_state: StringName) -> void:
	pass


## Fade the stack out and stop it. `fade` false stops immediately.
func music_stop(fade: bool = true) -> void:
	_ensure_init()
	if _music_player == null:
		return
	_music_level = 0
	if not fade:
		_apply_stem_db_now(SILENT_DB)
		_music_player.stop()
		_music_stopping = false
		set_process(false)
		return
	for i in STEMS.size():
		_stem_target_db[i] = SILENT_DB
	_music_stopping = true
	set_process(true)


## Per-family volume, for the options screen and for state mixes (docs/08 §4).
func set_bus_volume_db(bus: StringName, db: float) -> void:
	_ensure_init()
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)


# ================================================================ internals =====


func _ensure_buses() -> void:
	for bus in [BUS_MUSIC, BUS_MECHANICS, BUS_FICTION, BUS_UI]:
		if AudioServer.get_bus_index(bus) >= 0:
			continue
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus)
		AudioServer.set_bus_send(idx, BUS_MASTER)
	set_bus_volume_db(BUS_MUSIC, MUSIC_BUS_DB)


func _build_voice_pool() -> void:
	_voice_started.resize(MAX_VOICES)
	for i in MAX_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%02d" % i
		voice.bus = BUS_MECHANICS
		add_child(voice)
		_voices.append(voice)
		_voice_started[i] = -1.0


func _warm_sfx_cache() -> void:
	# Silent: a missing asset is only worth a log line when something actually asks
	# for it, and boot-time noise for assets nobody plays helps nobody.
	for event in EVENTS:
		var path := SFX_DIR + event + ".wav"
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream != null:
				_sfx[StringName(event)] = stream


func _sfx_stream(event: StringName) -> AudioStream:
	if _sfx.has(event):
		return _sfx[event]
	var path := SFX_DIR + String(event) + ".wav"
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		if stream != null:
			_sfx[event] = stream
			return stream
	if not _missing_logged.has(event):
		_missing_logged[event] = true
		print("[audio] no asset yet for event: ", event)
	return null


func _take_voice() -> AudioStreamPlayer:
	var now := Time.get_ticks_msec() / 1000.0
	var oldest := 0
	for i in _voices.size():
		if not _voices[i].playing:
			_voice_started[i] = now
			return _voices[i]
		if _voice_started[i] < _voice_started[oldest]:
			oldest = i
	# All 24 busy: steal the one that has been running longest. At this density the
	# stolen voice is the least likely to still be carrying information.
	_voices[oldest].stop()
	_voice_started[oldest] = now
	return _voices[oldest]


func _bus_for(event: StringName, opts: Dictionary) -> StringName:
	if opts.has("bus"):
		return StringName(opts["bus"])
	if FICTION_EVENTS.has(String(event)):
		return BUS_FICTION
	return BUS_MECHANICS


func _pitch_for(event: StringName, opts: Dictionary) -> float:
	if opts.has("pitch_scale"):
		return clampf(float(opts["pitch_scale"]), PITCH_MIN, PITCH_MAX)
	var jitter := float(opts.get("pitch_jitter",
		EVENT_PITCH_JITTER.get(event, DEFAULT_PITCH_JITTER)))
	if jitter <= 0.0:
		return 1.0
	return clampf(pow(2.0, _rng.randf_range(-jitter, jitter)), PITCH_MIN, PITCH_MAX)


func _build_music() -> bool:
	if _music_sync != null:
		return true

	# A stem that is missing gets slot -1 and is simply skipped; the rest still play,
	# so a half-built assets/ folder costs you instruments, not the score.
	var slots: PackedInt32Array = []
	var streams: Array[AudioStream] = []
	for stem in STEMS:
		var path := MUSIC_DIR + stem + ".ogg"
		var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
		if stream == null:
			slots.append(-1)
			continue
		# Imported OGGs default to loop = false; without this the score plays once.
		if stream is AudioStreamOggVorbis:
			stream.loop = true
			stream.loop_offset = 0.0
		slots.append(streams.size())
		streams.append(stream)

	if streams.is_empty():
		if not _missing_logged.has(&"__music"):
			_missing_logged[&"__music"] = true
			print("[audio] no music stems yet in ", MUSIC_DIR)
		return false

	var sync := AudioStreamSynchronized.new()
	sync.stream_count = streams.size()
	for slot in streams.size():
		sync.set_sync_stream(slot, streams[slot])
		sync.set_sync_stream_volume(slot, SILENT_DB)

	_music_sync = sync
	_stem_slot = slots
	_stem_db = PackedFloat32Array()
	_stem_target_db = PackedFloat32Array()
	for i in STEMS.size():
		_stem_db.append(SILENT_DB)
		_stem_target_db.append(AUDIBLE_DB if i < _music_level else SILENT_DB)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.bus = BUS_MUSIC
	_music_player.stream = _music_sync
	add_child(_music_player)
	return true


func _apply_stem_db_now(db: float) -> void:
	for i in STEMS.size():
		_stem_db[i] = db
		_stem_target_db[i] = db
		if _stem_slot[i] >= 0:
			_music_sync.set_sync_stream_volume(_stem_slot[i], db)


func _process(delta: float) -> void:
	if _music_sync == null:
		set_process(false)
		return
	# A linear ramp in dB is an exponential ramp in amplitude — the shape a fader has,
	# and the one that makes a stem arrive rather than suddenly appear.
	var step: float = (AUDIBLE_DB - SILENT_DB) * delta / MUSIC_FADE_SECONDS
	var moving := false
	for i in STEMS.size():
		var current: float = _stem_db[i]
		var target: float = _stem_target_db[i]
		if is_equal_approx(current, target):
			continue
		current = move_toward(current, target, step)
		_stem_db[i] = current
		if _stem_slot[i] >= 0:
			_music_sync.set_sync_stream_volume(_stem_slot[i], current)
		if not is_equal_approx(current, target):
			moving = true
	if moving:
		return
	if _music_stopping:
		_music_player.stop()
		_music_stopping = false
	set_process(false)
