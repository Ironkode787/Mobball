extends Node
## AudioDirector autoload. Gameplay calls AudioDirector.play(&"event") and never touches
## files. Event → asset mapping is owned by the audio workstream (specs/audio-pipeline.md).
## Missing assets fail silent (logged once) so gameplay never depends on audio being built.
##
## Everything under assets/audio/ is synthesised by tools/audiogen — no samples, no
## licences. Regenerate with `python3 tools/audiogen/generate.py`.
##
## Three Godot 4.5 details this file depends on, all verified headless:
##   * AudioStreamSynchronized.set_sync_stream_volume() takes DECIBELS, not a linear
##     gain. Passing 0.0 expecting silence gives full level instead; -80 is silence.
##     Volume changes apply live during playback, which is what makes the fades work.
##   * An imported .ogg loads with loop = false. The flag has to be set on the loaded
##     resource, otherwise the stack plays through once and stops.
##   * load() hands out one shared instance per path, so mutating a stream (loop_mode,
##     loop_end) changes it for every voice already holding it. The looping variants of
##     bill_counter/siren are duplicate()s for exactly that reason.

# --- assets ---------------------------------------------------------------------
const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/city1/"

## City-1 stem stack, in the order they fade in as the empire grows (docs/08 §1).
## These eight are what `music_set_level` moves; index order is load-bearing below.
const STEMS: PackedStringArray = [
	"01_bass", "02_drums", "03_vibes", "04_trumpet",
	"05_organ", "06_barisax", "07_strings", "08_full",
]

## State layers (specs/audio-wave2.md §2). Same length, same key, same tempo, and they
## live on the SAME AudioStreamSynchronized — that is the only way they can drop in
## mid-bar without a flam. `music_set_level` never touches them; `music_set_state` does.
const STATE_STEMS: PackedStringArray = ["09_tense", "10_raid_drums"]

## The Count's piano is deliberately NOT in the synchronized stack: it is a different
## tempo and a different loop length, and it plays when the band does not.
const COUNT_PIANO := "count_piano"

const IDX_BASS := 0
const IDX_DRUMS := 1
const IDX_TENSE := 8
const IDX_RAID_DRUMS := 9
## Heat thins the comfort instruments (docs/08 §4): vibes, organ, strings.
const HOT_DUCKED: PackedInt32Array = [2, 4, 6]

## Every event with an asset. Used for warm-up and by tests/test_audio_assets.gd.
const EVENTS: PackedStringArray = [
	# specs/audio-pipeline.md §4
	"flipper_up", "flipper_down", "bumper_hit", "sling_hit", "plunger_pull",
	"plunger_launch", "ball_spawn", "drain", "nudge_thump", "tilt_warning", "tilt",
	"knocker", "cash_tick", "chime_a", "chime_b", "chime_c", "wall_tap",
	# specs/audio-wave2.md §1 — mechanics
	"rollover_click", "spinner_tick", "drop_clack", "drop_bank_down", "drop_bank_reset",
	"kickback", "orbit_whoosh",
	# specs/audio-wave2.md §1 — fiction
	"storefront_collect", "laundromat_wash", "bribe_paid", "guy_pinched", "bail_paid",
	"safe_open", "stamp_thunk", "paper_slip", "job_done", "skill_shot_ding",
	"combo_2", "combo_3", "combo_4", "headline_sting", "rankup_fanfare", "bill_counter",
	"coin_drop", "siren", "raid_start", "raid_win", "raid_lose",
]

## Assets built as seamless loops rather than one-shots. Pass `{"loop": true}` to
## `play()` and the voice repeats until you stop it (keep the returned player).
const LOOPABLE_EVENTS: PackedStringArray = ["bill_counter", "siren"]

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
	# The combo family is tuned to the chimes an octave up; detuning it would undo the
	# only reason those three pitches were chosen. Same for anything with brass in it.
	&"combo_2": 0.005, &"combo_3": 0.005, &"combo_4": 0.005,
	&"skill_shot_ding": 0.006, &"rankup_fanfare": 0.004, &"headline_sting": 0.005,
	&"job_done": 0.010, &"raid_win": 0.010, &"raid_lose": 0.010,
	&"storefront_collect": 0.020,
	# Loops: pitch is playback rate, so jitter would change how long a loop takes to
	# come round. The Count's bill counter has to stay in time with itself.
	&"bill_counter": 0.0, &"siren": 0.0,
	# These fire many times a second, so they get more variety, not less.
	&"spinner_tick": 0.090, &"rollover_click": 0.070, &"coin_drop": 0.050,
}

# --- buses ----------------------------------------------------------------------
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_MECHANICS := &"Mechanics"
const BUS_FICTION := &"Fiction"
const BUS_UI := &"UI"

## The machine is a physical object in the room; the story is not (docs/08 §2).
## Everything the *fiction* makes — money, paper, police, brass — goes to Fiction;
## everything the *machine* makes stays on Mechanics.
const FICTION_EVENTS: PackedStringArray = [
	"chime_a", "chime_b", "chime_c", "knocker", "cash_tick",
	"storefront_collect", "laundromat_wash", "bribe_paid", "guy_pinched", "bail_paid",
	"safe_open", "stamp_thunk", "paper_slip", "job_done", "skill_shot_ding",
	"combo_2", "combo_3", "combo_4", "headline_sting", "rankup_fanfare", "bill_counter",
	"coin_drop", "siren", "raid_start", "raid_win", "raid_lose",
]

## All eight stems at unity sum to about +1 dBFS, so the music bus carries the trim
## that keeps the full stack under the ceiling and leaves room for the table on top.
const MUSIC_BUS_DB := -4.0

## Master ceiling (docs/08 §6). Four buses summing at once cannot be proved to stay
## under 0 dBFS by level ladders alone; this catches the coincidences.
const MASTER_CEILING_DB := -0.5

# --- music ----------------------------------------------------------------------
const MUSIC_FADE_SECONDS := 1.5
const SILENT_DB := -80.0
const AUDIBLE_DB := 0.0

## specs/audio-wave2.md §2. `music_set_state` composes WITH `music_set_level`: calm and
## hot are the level mix (hot adds the ostinato and thins three comfort stems), raid
## overrides it outright, and count ducks the lot and puts the piano on top.
const STATE_CALM := &"calm"
const STATE_HOT := &"hot"
const STATE_RAID := &"raid"
const STATE_COUNT := &"count"
const MUSIC_STATES: PackedStringArray = ["calm", "hot", "raid", "count"]

const HOT_DUCK_DB := -4.0
const RAID_DUCK_DB := -60.0
## The raid is a hard cut, so it moves fast; The Count is a held breath, so it does not.
const RAID_FADE_SECONDS := 0.4
const COUNT_FADE_SECONDS := 1.0
const PIANO_DB := 0.0

var _missing_logged: Dictionary = {}
var _sfx: Dictionary = {}                       # StringName -> AudioStream
var _sfx_looping: Dictionary = {}               # StringName -> looping copy
var _voices: Array[AudioStreamPlayer] = []
var _voice_started: PackedFloat64Array = []
var _rng := RandomNumberGenerator.new()

var _music_player: AudioStreamPlayer
var _music_sync: AudioStreamSynchronized
var _all_stems: PackedStringArray = []          # STEMS + STATE_STEMS
var _stem_slot: PackedInt32Array = []           # stem index -> slot in the sync, or -1
var _stem_db: PackedFloat32Array = []
var _stem_target_db: PackedFloat32Array = []
var _music_level := 0
var _music_state: StringName = STATE_CALM
var _music_stopping := false
var _fade_seconds := MUSIC_FADE_SECONDS
var _piano_player: AudioStreamPlayer
var _piano_db := SILENT_DB
var _piano_target_db := SILENT_DB
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
## `volume_db`, `bus`, `loop` (LOOPABLE_EVENTS only — keep the returned player and
## stop() it yourself). Returns the voice it grabbed, or null if the asset is missing.
func play(event: StringName, opts: Dictionary = {}) -> AudioStreamPlayer:
	_ensure_init()
	var stream: AudioStream = (_looping_stream(event) if bool(opts.get("loop", false))
		else _sfx_stream(event))
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
	var built := _build_music()
	if _music_state == STATE_COUNT:
		_build_piano()
	_music_stopping = false
	# Clearing _music_stopping changes what every target should be, and _build_music
	# only recomputes on the first call — so recompute here too, or a start after a
	# faded stop comes back up silent.
	_recompute_targets()
	if not built:
		if _piano_player != null:
			set_process(true)
		return
	if not _music_player.playing and _music_player.is_inside_tree():
		_music_player.play()
	set_process(true)


## `level` = how many stems are audible, 0 through STEMS.size(). Level n means the
## first n stems of the stack; the rest fade out. Fades take MUSIC_FADE_SECONDS.
## The current state still has the last word: setting a level during a raid or The
## Count is remembered and applied when that state ends.
func music_set_level(level: int) -> void:
	_ensure_init()
	_music_level = clampi(level, 0, STEMS.size())
	_music_stopping = false
	_fade_seconds = MUSIC_FADE_SECONDS
	_recompute_targets()
	set_process(true)


## Currently requested level (not the same as "done fading").
func music_level() -> int:
	return _music_level


func is_music_playing() -> bool:
	return _music_player != null and _music_player.playing


## specs/audio-wave2.md §2 — calm | hot | raid | count.
##
## Every state is a set of volume targets over ONE always-running synchronized player.
## Nothing here stops or restarts it, and nothing reseeks it: the eight-bar stack and
## the two state layers stay sample-locked through every transition, so the raid kit
## drops in exactly on the bar it was already playing on. Stopping the player and
## starting a different one is the obvious implementation and it flams every time.
##
## Idempotent (re-entering the same state does nothing) and safe before music_start(),
## before the assets exist, and headless.
func music_set_state(state: StringName) -> void:
	_ensure_init()
	if not MUSIC_STATES.has(String(state)):
		if not _missing_logged.has(state):
			_missing_logged[state] = true
			print("[audio] unknown music state: ", state)
		return
	if state == _music_state:
		return
	_fade_seconds = _fade_seconds_for(_music_state, state)
	_music_state = state
	_music_stopping = false
	if state == STATE_COUNT:
		_build_piano()
	_recompute_targets()
	set_process(true)


## Currently requested state (not the same as "done fading").
func music_state() -> StringName:
	return _music_state


## Fade the stack out and stop it. `fade` false stops immediately.
func music_stop(fade: bool = true) -> void:
	_ensure_init()
	if _music_player == null and _piano_player == null:
		return
	_music_level = 0
	if not fade:
		_music_stopping = false
		_apply_stem_db_now(SILENT_DB)
		if _music_player != null:
			_music_player.stop()
		if _piano_player != null:
			_piano_db = SILENT_DB
			_piano_target_db = SILENT_DB
			_piano_player.volume_db = SILENT_DB
			_piano_player.stop()
		set_process(false)
		return
	# _music_stopping overrides every target, so the state survives the stop: a later
	# music_start() comes back up in whatever state the game is actually in.
	_music_stopping = true
	_fade_seconds = MUSIC_FADE_SECONDS
	_recompute_targets()
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
	_ensure_master_limiter()


## Limiter on master, per docs/08 §6 — the phone-speaker safety net.
##
## The four families are mixed to sit together, not to be summed with a calculator:
## the raid mix alone peaks around -1 dBFS after the music trim, and a knocker landing
## on the same sample would put the sum over. Every family's peak ladder is set on the
## assumption that this exists, so it is created here rather than left to a project
## setting somebody else owns.
func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index(BUS_MASTER)
	if master < 0:
		return
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			return
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = MASTER_CEILING_DB
	limiter.release = 0.10
	AudioServer.add_bus_effect(master, limiter)


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


## A looping copy of a LOOPABLE_EVENTS asset, built once and cached.
##
## The copy matters: the cached stream is shared by every voice, so flipping loop_mode
## on it would leave a siren looping the next time anything played it as a one-shot.
func _looping_stream(event: StringName) -> AudioStream:
	if _sfx_looping.has(event):
		return _sfx_looping[event]
	var base: AudioStream = _sfx_stream(event)
	if base == null:
		return null
	if not (base is AudioStreamWAV):
		return base
	var wav: AudioStreamWAV = (base as AudioStreamWAV).duplicate()
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = int(round(base.get_length() * float(wav.mix_rate)))
	_sfx_looping[event] = wav
	return wav


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

	_all_stems = PackedStringArray()
	_all_stems.append_array(STEMS)
	_all_stems.append_array(STATE_STEMS)

	# A stem that is missing gets slot -1 and is simply skipped; the rest still play,
	# so a half-built assets/ folder costs you instruments, not the score.
	var slots: PackedInt32Array = []
	var streams: Array[AudioStream] = []
	for stem in _all_stems:
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
	for i in _all_stems.size():
		_stem_db.append(SILENT_DB)
		_stem_target_db.append(SILENT_DB)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "Music"
	_music_player.bus = BUS_MUSIC
	_music_player.stream = _music_sync
	add_child(_music_player)
	_recompute_targets()
	return true


## The Count's piano gets its own player: different length, different tempo, and it has
## to keep running while the synchronized stack sits at -80 dB underneath it.
func _build_piano() -> bool:
	if _piano_player != null:
		return true
	var path := MUSIC_DIR + COUNT_PIANO + ".ogg"
	var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
	if stream == null:
		if not _missing_logged.has(&"__piano"):
			_missing_logged[&"__piano"] = true
			print("[audio] no asset yet for ", path)
		return false
	if stream is AudioStreamOggVorbis:
		stream.loop = true
		stream.loop_offset = 0.0
	_piano_player = AudioStreamPlayer.new()
	_piano_player.name = "CountPiano"
	_piano_player.bus = BUS_MUSIC
	_piano_player.stream = stream
	_piano_player.volume_db = SILENT_DB
	add_child(_piano_player)
	return true


## The whole mix table, in one place: every target is a pure function of the requested
## level and the requested state, so the two compose instead of fighting and any order
## of calls lands on the same mix.
func _stem_target_for(index: int) -> float:
	if _music_stopping:
		return SILENT_DB
	match _music_state:
		STATE_COUNT:
			return SILENT_DB
		STATE_RAID:
			# Overrides the level mix outright: however big the empire got, a raid is
			# bass, the halftime kit and the ostinato, and nothing else.
			if index == IDX_BASS or index == IDX_TENSE or index == IDX_RAID_DRUMS:
				return AUDIBLE_DB
			if index == IDX_DRUMS:
				return SILENT_DB
			return RAID_DUCK_DB
		STATE_HOT:
			if index == IDX_TENSE:
				return AUDIBLE_DB
			if index == IDX_RAID_DRUMS or index >= STEMS.size():
				return SILENT_DB
			if index >= _music_level:
				return SILENT_DB
			return HOT_DUCK_DB if HOT_DUCKED.has(index) else AUDIBLE_DB
		_:
			if index >= STEMS.size():
				return SILENT_DB
			return AUDIBLE_DB if index < _music_level else SILENT_DB


func _recompute_targets() -> void:
	if _music_sync != null:
		for i in _stem_target_db.size():
			_stem_target_db[i] = _stem_target_for(i)
	if _piano_player == null:
		return
	_piano_target_db = (PIANO_DB if _music_state == STATE_COUNT and not _music_stopping
		else SILENT_DB)
	if _piano_target_db > SILENT_DB and not _piano_player.playing \
			and _piano_player.is_inside_tree():
		_piano_player.volume_db = _piano_db
		_piano_player.play()


func _fade_seconds_for(from_state: StringName, to_state: StringName) -> float:
	if from_state == STATE_COUNT or to_state == STATE_COUNT:
		return COUNT_FADE_SECONDS
	if from_state == STATE_RAID or to_state == STATE_RAID:
		return RAID_FADE_SECONDS
	return MUSIC_FADE_SECONDS


func _apply_stem_db_now(db: float) -> void:
	if _music_sync == null:
		return
	for i in _stem_db.size():
		_stem_db[i] = db
		_stem_target_db[i] = db
		if _stem_slot[i] >= 0:
			_music_sync.set_sync_stream_volume(_stem_slot[i], db)


func _process(delta: float) -> void:
	if _music_sync == null and _piano_player == null:
		set_process(false)
		return
	# A linear ramp in dB is an exponential ramp in amplitude — the shape a fader has,
	# and the one that makes a stem arrive rather than suddenly appear.
	var step: float = (AUDIBLE_DB - SILENT_DB) * delta / maxf(_fade_seconds, 0.01)
	var moving := false
	if _music_sync != null:
		for i in _stem_db.size():
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
	if _piano_player != null and not is_equal_approx(_piano_db, _piano_target_db):
		_piano_db = move_toward(_piano_db, _piano_target_db, step)
		_piano_player.volume_db = _piano_db
		if not is_equal_approx(_piano_db, _piano_target_db):
			moving = true
	if moving:
		return
	# Faded all the way out: nothing left to hear, so stop paying for it.
	if _piano_player != null and _piano_player.playing \
			and is_equal_approx(_piano_target_db, SILENT_DB):
		_piano_player.stop()
	if _music_stopping:
		if _music_player != null:
			_music_player.stop()
		_music_stopping = false
	set_process(false)
