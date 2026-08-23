extends Node
## AudioDirector autoload. Gameplay calls AudioDirector.play(&"event") and never touches
## files. Event → asset mapping is owned by the audio workstream (specs/audio-pipeline.md).
## Missing assets fail silent (logged once) so gameplay never depends on audio being built.
##
## Everything under assets/audio/ is synthesised by tools/audiogen — no samples, no
## licences. Regenerate with `python3 tools/audiogen/generate.py`.
##
## Two things beyond one-shots and the score live here as of wave 3:
##   * `play(event, {"impact": 0..1})` picks a velocity layer (docs/08 §8). The medium
##     layer is the event's original file, so a call without `impact` is unchanged.
##   * `say(specialist, mood)` plays the muted-brass phrase bank (docs/08 §5) on a
##     channel of its own — one wiseguy at a time.
##
## Wave 4 adds the two pieces of the endgame that are mix automation rather than files:
##   * `rico_dropout(step)` — the wiretap phase of the RICO raid (docs/05 §9). The Feds
##     cut wires; wires do not fade, so every step is instant, and step 0 puts the mix
##     back exactly as it was.
##   * `play_farewell()` — Skip Town (docs/08 §1): the stem stack shed one player at a
##     time on the beat grid, the last bass note left ringing alone, and a train.
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
const VOICE_DIR := "res://assets/audio/voice/"
const MUSIC_ROOT := "res://assets/audio/music/"
## City 1's folder, kept as a name because it is the default and half the codebase says it.
const MUSIC_DIR := MUSIC_ROOT + "city1/"

## docs/08 §7 — one arrangement per city, same slots, its own tempo and key. Swapped by
## `music_set_city`; index order is the prestige order from docs/06 §4.
const CITY_DIRS: PackedStringArray = ["city1", "city2"]
## Each city's tempo, because the Skip Town sequence is written in beats, not seconds.
const CITY_BPM: PackedFloat32Array = [92.0, 104.0]
## A city may add ONE bed stem: something that is the room rather than the band, and so
## plays whenever anything plays. City 2 is a 1927 record and its bed is the record.
## Empty means the city has no bed.
const CITY_BEDS: PackedStringArray = ["", "11_crackle"]

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
	# specs/m2-content.md §1/§4 — the Club deck, the casino and the Family Meeting
	"wheel_clatter", "chip_stack", "card_riffle", "reel_stop", "jackpot",
	"meeting_start", "meeting_jackpot", "meeting_end", "radio_squelch", "staircase_crest",
	# specs/m3-fall-rise.md AUDIO-4 — the endgame: the Commission fights, the Docks, the
	# Penthouse, the dome, the heists, the election, Empire Mode and Skip Town.
	"boss_start", "boss_phase", "boss_beaten", "wrench_telegraph",
	"crane_telegraph", "crane_pull", "container_break", "pier_splash",
	"smuggling_start", "shipment_out", "chair_take", "sitdown", "dome_loop",
	"heist_start", "heist_beat", "heist_blown", "election_win",
	"empire_start", "empire_end", "reunion_start",
	"briefcase_drop", "briefcase_leave", "skip_town", "train_away",
]

## Assets built as seamless loops rather than one-shots. Pass `{"loop": true}` to
## `play()` and the voice repeats until you stop it (keep the returned player).
const LOOPABLE_EVENTS: PackedStringArray = ["bill_counter", "siren", "wheel_clatter"]

# --- velocity layers -------------------------------------------------------------

## docs/08 §8. Three files per physical event — soft, medium, hard — chosen by the
## `impact` option (0..1). The MEDIUM entry is the event's own filename, because the
## medium layer *is* the file that already shipped: a `play()` with no `impact` loads
## exactly what it always loaded and sounds exactly as it always sounded.
const IMPACT_LAYERS := {
	&"flipper_up": ["flipper_up_soft", "flipper_up", "flipper_up_hard"],
	&"bumper_hit": ["bumper_hit_soft", "bumper_hit", "bumper_hit_hard"],
	&"sling_hit": ["sling_hit_soft", "sling_hit", "sling_hit_hard"],
}

## Where one rung ends and the next begins. Uneven on purpose: most contacts in a ball's
## life are middling, so the medium layer owns the middle half of the range and the two
## ends are reserved for hits that really are gentle or really are violent.
const IMPACT_SOFT_MAX := 0.28
const IMPACT_HARD_MIN := 0.72

## Within a rung, where the hit sat still counts for something — a 0.30 bumper and a
## 0.70 bumper are both "medium" but they are not the same hit. The position inside the
## rung tilts pitch and level a little, on top of (not instead of) the usual random
## jitter, so repeats at one impact still vary.
const IMPACT_PITCH_TILT := 0.022        # octaves, ±: about a quarter tone at the edges
const IMPACT_DB_TILT := 1.5             # dB, ±

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
	# Wave 3. The Club's brass is tuned (F major over the score's D minor for the
	# jackpot, D minor for the meeting), and staircase_crest is a D7 bar that has to
	# agree with the chime unit two octaves below it.
	&"jackpot": 0.005, &"meeting_start": 0.004, &"meeting_jackpot": 0.005,
	&"meeting_end": 0.004, &"staircase_crest": 0.006,
	&"wheel_clatter": 0.0,
	&"reel_stop": 0.045, &"chip_stack": 0.060, &"card_riffle": 0.055,
	&"radio_squelch": 0.030,
	# Wave 4. Anything with brass, a bell or a cadence in it is tuned to the score and
	# gets almost none: the dome's D6 is the crown of the tuned set and a detuned Empire
	# Mode chord over the full stack is the single most audible mistake available here.
	&"boss_start": 0.006, &"boss_phase": 0.006, &"boss_beaten": 0.005,
	&"dome_loop": 0.004, &"election_win": 0.005, &"empire_start": 0.004,
	&"empire_end": 0.005, &"reunion_start": 0.005, &"shipment_out": 0.008,
	&"sitdown": 0.006, &"heist_blown": 0.008, &"heist_start": 0.010,
	&"heist_beat": 0.006, &"briefcase_leave": 0.010,
	# Three files whose LENGTH is a contract, so playback rate has to stay at 1.0: the
	# two telegraphs are exactly as long as the tells they cover (sammy.gd's 2 s wrench,
	# the crane's warning before the pull), and skip_town/train_away are timed against
	# play_farewell()'s scripted sequence.
	&"wrench_telegraph": 0.0, &"crane_telegraph": 0.0,
	&"skip_town": 0.0, &"train_away": 0.0,
	# Foley that fires often enough to need variety.
	&"crane_pull": 0.045, &"container_break": 0.045, &"pier_splash": 0.035,
	&"chair_take": 0.040, &"briefcase_drop": 0.035, &"smuggling_start": 0.020,
}

# --- specialist voices -----------------------------------------------------------

## docs/08 §5, the muted-brass mob. One instrument per specialist; the phrase bank is
## three files each and the index in the filename is the index into VOICE_MOODS.
const SPECIALISTS: PackedStringArray = [
	"skids", "big_sal", "nussbaum", "rosa", "cohen", "professor", "consigliere",
	"manny", "eddie",
]
const VOICE_MOODS: PackedStringArray = ["greeting", "quip", "grumble"]
const VOICE_DEFAULT_MOOD := &"quip"

## Wiseguys talk over each other; the mixer does not. One voice channel, and a new
## say() takes it from whoever had it.
const VOICE_PITCH_JITTER := 0.012

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
	# Wave 3: the money, the brass and the police are fiction; the wheel and the reels
	# are hardware bolted to the playfield, so they stay on Mechanics with the rest of
	# the machine.
	"chip_stack", "card_riffle", "jackpot", "meeting_start", "meeting_jackpot",
	"meeting_end", "radio_squelch", "staircase_crest",
	# Wave 4: the story's events — a rival arriving, a chair being taken, a heist, an
	# election, an empire, a train leaving. What stays on Mechanics is what is bolted to
	# the playfield: the wrench on your linkage, the crane and its magnet, a container
	# stack going over and the water under the pier are all things the *machine* does.
	"boss_start", "boss_phase", "boss_beaten", "smuggling_start", "shipment_out",
	"chair_take", "sitdown", "dome_loop", "heist_start", "heist_beat", "heist_blown",
	"election_win", "empire_start", "empire_end", "reunion_start",
	"briefcase_drop", "briefcase_leave", "skip_town", "train_away",
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

# --- the RICO wiretap (docs/05 §9) ------------------------------------------------
## Three cuts, in a fixed order, and nothing between them:
##   1  the Fiction bus — the story goes quiet and the machine keeps working
##   2  + the comfort instruments (docs/08 §4's three: vibes, organ, strings)
##   3  + everything else, leaving the Mechanics bus and one stem: the bass.
## The bass IS the heartbeat here. The game has no separate heartbeat stem — docs/08 §4's
## Heat-90 kick lives inside 09_tense — and the bass is what the whole score is built on
## top of, so it is the honest thing to leave beating under a dead mix.
const RICO_STEPS := 3
const RICO_HEARTBEAT := IDX_BASS

# --- Skip Town (docs/08 §1) -------------------------------------------------------
## When each player packs up, in beats from the start of the sequence. Bar-aware in the
## only way that is cheap and honest: the interval asked for is ~1.6 s, one beat here is
## 0.652 s, and 1.6 s is not a whole number of beats — so the sheds are quantised to the
## grid and alternate 2-3-2-3 beats, which averages 1.63 s and lands every exit on a
## beat. A player leaves on a beat or he is not a player.
const FAREWELL_SHED_BEATS: PackedInt32Array = [0, 2, 5, 7, 10, 12, 15]
## Eight beats — two bars — of the bass on its own before it lets go, and the train
## arriving two beats into that last fade rather than after silence.
const FAREWELL_BASS_BEAT := 23
const FAREWELL_TRAIN_BEAT := 25
## Sharper than any music fade: a stem going out here is a man packing an instrument
## away, not a mix moving. The last note is the exception — it is the note ending, so it
## gets a fade of its own, more than three times longer.
const FAREWELL_FADE_SECONDS := 0.45
const FAREWELL_LAST_FADE_SECONDS := 1.60
## Only used if train_away is missing: the sequence still has to report a length.
const FAREWELL_TRAIN_SECONDS := 3.80
const FAREWELL_TRAIN_EVENT := &"train_away"

var _missing_logged: Dictionary = {}
var _sfx: Dictionary = {}                       # StringName -> AudioStream
var _sfx_looping: Dictionary = {}               # StringName -> looping copy
var _phrases: Dictionary = {}                   # "big_sal_0" -> AudioStream
var _voices: Array[AudioStreamPlayer] = []
var _voice_started: PackedFloat64Array = []
var _speaker: AudioStreamPlayer                 # the one channel say() talks on
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

var _city := 0
var _bed_index := -1                            # the city's bed stem, or -1 if it has none

var _rico_step := 0

var _farewell_active := false
var _farewell_t := 0.0
var _farewell_lead := 0.0                       # wait for the next beat before shed #1
var _farewell_shed := 0                         # players who have packed up, from the top
var _farewell_bass_gone := false
var _farewell_train_played := false
var _farewell_total := 0.0


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
	_build_speaker()
	_warm_sfx_cache()


# =============================================================== public API =====


## Fire a one-shot sound effect.
## opts: `pitch_jitter` (octaves, default 0.05), `pitch_scale` (explicit, skips jitter),
## `volume_db`, `bus`, `loop` (LOOPABLE_EVENTS only — keep the returned player and
## stop() it yourself), `impact` (0..1, IMPACT_LAYERS events only — how hard the thing
## was hit; picks the velocity layer). Returns the voice it grabbed, or null if the
## asset is missing.
##
## `impact` is additive to everything else: leaving it out is the whole of the old
## behaviour, down to which file gets loaded.
func play(event: StringName, opts: Dictionary = {}) -> AudioStreamPlayer:
	_ensure_init()
	var asset: StringName = event
	var tilt := 0.0
	if opts.has("impact") and IMPACT_LAYERS.has(event):
		var hit: float = clampf(float(opts["impact"]), 0.0, 1.0)
		var rung: int = _impact_rung(hit)
		asset = StringName((IMPACT_LAYERS[event] as Array)[rung])
		tilt = _impact_tilt(hit, rung)
	var stream: AudioStream = (_looping_stream(asset) if bool(opts.get("loop", false))
		else _sfx_stream(asset))
	if stream == null:
		return null

	var voice: AudioStreamPlayer = _take_voice()
	if voice == null:
		return null

	voice.stream = stream
	voice.bus = _bus_for(event, opts)
	voice.volume_db = float(opts.get("volume_db", 0.0)) + tilt * IMPACT_DB_TILT
	voice.pitch_scale = clampf(_pitch_for(event, opts) * pow(2.0, tilt * IMPACT_PITCH_TILT),
		PITCH_MIN, PITCH_MAX)
	# In the headless test runner the scene tree is not live yet; configuring the voice
	# is still worth doing (and testable) but play() would push an engine error.
	if voice.is_inside_tree():
		voice.play()
	return voice


## A specialist says something (docs/08 §5). No words — one instrument, three phrases,
## and the subtitle carries the joke.
##
## `specialist` is a SPECIALISTS name, `mood` one of VOICE_MOODS (unknown moods fall
## back to "quip" rather than going silent — a missing line is worse than the wrong one).
## Plays on the Fiction bus, on a channel of its own: one wiseguy at a time, and a new
## say() takes the floor from whoever had it. Returns the player, or null if the bank is
## missing that phrase.
func say(specialist: StringName, mood: StringName = VOICE_DEFAULT_MOOD) -> AudioStreamPlayer:
	_ensure_init()
	var index := VOICE_MOODS.find(String(mood))
	if index < 0:
		index = VOICE_MOODS.find(String(VOICE_DEFAULT_MOOD))
	var stream: AudioStream = _phrase_stream(specialist, maxi(index, 0))
	if stream == null:
		return null
	if _speaker == null:
		return null
	_speaker.stop()
	_speaker.stream = stream
	_speaker.volume_db = 0.0
	_speaker.pitch_scale = clampf(
		pow(2.0, _rng.randf_range(-VOICE_PITCH_JITTER, VOICE_PITCH_JITTER)),
		PITCH_MIN, PITCH_MAX)
	if _speaker.is_inside_tree():
		_speaker.play()
	return _speaker


## Cut the current specialist off mid-sentence. Safe when nobody is talking.
func voice_stop() -> void:
	_ensure_init()
	if _speaker != null:
		_speaker.stop()


## Is somebody talking right now?
func is_speaking() -> bool:
	return _speaker != null and _speaker.playing


## Silence every one-shot voice, including whoever was talking. Music is unaffected.
func stop_all() -> void:
	_ensure_init()
	for voice in _voices:
		voice.stop()
	if _speaker != null:
		_speaker.stop()


## Start the stem stack. Idempotent: calling it while playing does nothing.
func music_start() -> void:
	_ensure_init()
	if _farewell_active:
		return
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
##
## Refused outright during `play_farewell()` — see there.
func music_set_level(level: int) -> void:
	_ensure_init()
	if _farewell_active:
		return
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
## before the assets exist, and headless. Refused during `play_farewell()` — see there.
func music_set_state(state: StringName) -> void:
	_ensure_init()
	if _farewell_active:
		return
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
##
## The one music call the farewell does NOT refuse: it cancels the sequence and then
## does its job. Refusing to stop audio while a scene is being torn down would be a bug
## wearing a feature's coat.
func music_stop(fade: bool = true) -> void:
	_ensure_init()
	if _farewell_active:
		farewell_stop()
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


## docs/08 §7 — swap the whole arrangement for another city's.
##
## A city is a different song at a different tempo in a different key, so this is a
## rebuild and not a crossfade: nothing can be sample-locked to a stack it is not part
## of. The requested level and state survive, so the new city comes up playing whatever
## the game had asked for — a prestige into New Carthage at level 1 hears one tuba.
##
## Idempotent, clamped, and refused during `play_farewell()`: the farewell is the sound
## of THIS city ending and the next one starts after it, not underneath it. Safe with no
## assets — a city whose folder is empty is silent rather than broken.
func music_set_city(index: int) -> void:
	_ensure_init()
	if _farewell_active:
		return
	var want: int = clampi(index, 0, CITY_DIRS.size() - 1)
	if want == _city:
		return
	# "Had a stack" rather than "was playing": a stopped stack is still the arrangement
	# the game is holding, and `is_music_playing()` is false in a headless run even when
	# the player has been told to play. Rebuilding is cheap and a silent rebuilt stack
	# costs nothing; not rebuilding costs the next music_set_level() its music.
	var had_stack := _music_sync != null
	_teardown_music()
	_city = want
	if had_stack:
		music_start()


## Which city's arrangement is loaded (0 = the launch city).
func music_city() -> int:
	return _city


## docs/05 §9 — the RICO wiretap phase. The Feds are cutting wires.
##
## `step` 0 is the full mix; 1, 2 and 3 take progressively more of it away in a fixed
## order (RICO_STEPS above). Every step is INSTANT — no fades anywhere — because a fade
## is a mixing desk and this is a pair of pliers; the whole phase reads as equipment
## failing rather than as music ducking, and docs/08 §4 wants exactly that.
##
## `rico_dropout(0)` restores the mix EXACTLY, including the music level and state the
## game asked for while the wires were cut: every stem target is a pure function of
## level and state (`_stem_target_for`), so the restore is not a saved snapshot that can
## drift — it is the same function, evaluated again.
##
## Idempotent, safe before music_start(), safe with no assets, safe headless. Gameplay
## keeps its own visual/haptic redundancy for this phase (docs/08 §6): losing audio is
## the point, so nothing here may be the only channel a cue arrives on.
func rico_dropout(step: int) -> void:
	_ensure_init()
	var want: int = clampi(step, 0, RICO_STEPS)
	if want == _rico_step:
		return
	_rico_step = want
	_apply_rico_buses()
	_apply_mix_now()


## Which cut the wiretap is on: 0 = nothing cut.
func rico_step() -> int:
	return _rico_step


## docs/08 §1 — Skip Town: the band packs up. Returns the sequence's length in seconds
## so the flow lane can time the cutscene against it instead of guessing.
##
## One player leaves every two or three beats, top of the stack downwards, each with a
## fade far sharper than a music fade; the bass is left alone for two bars; then the
## last note lets go and a train takes the city away with it. The band that sheds is the
## band the empire actually earned — the sequence starts from the calm level mix, so a
## player who skips town at R4 hears four instruments leave, not eight.
##
## Callable once: while it runs, a second call changes nothing and returns the time
## REMAINING. `music_set_level`, `music_set_state` and `music_start` are REFUSED (not
## queued) for the duration — this is the last thing that happens in a city and nothing
## the game has to say about empire size or Heat can be more important than it. The two
## ways out are `farewell_stop()` and `music_stop()`, which cancel it.
##
## A dropped wiretap is lifted first: Skip Town is what docs/06 §1 offers you after a
## failed RICO raid, and a muted Fiction bus would eat the train.
func play_farewell() -> float:
	_ensure_init()
	if _farewell_active:
		return maxf(_farewell_total - _farewell_t, 0.0)
	rico_dropout(0)
	_build_music()
	_music_stopping = false
	if _music_player != null and not _music_player.playing and _music_player.is_inside_tree():
		_music_player.play()
	_farewell_active = true
	_farewell_t = 0.0
	_farewell_shed = 0
	_farewell_bass_gone = false
	_farewell_train_played = false
	_farewell_lead = _seconds_to_next_beat()
	_farewell_total = (_farewell_lead + float(FAREWELL_TRAIN_BEAT) * _sec_per_beat()
		+ _train_seconds())
	_fade_seconds = FAREWELL_FADE_SECONDS
	_recompute_targets()
	set_process(true)
	return _farewell_total


## Is the farewell running? True from `play_farewell()` until the train has finished.
func is_farewell_playing() -> bool:
	return _farewell_active


## Abandon the farewell (the player skipped the cutscene). Music control comes back and
## the stack returns to whatever level and state ask for, with an ordinary fade.
func farewell_stop() -> void:
	_ensure_init()
	if not _farewell_active:
		return
	_farewell_active = false
	_farewell_t = 0.0
	_farewell_shed = 0
	_farewell_bass_gone = false
	_farewell_train_played = false
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


## The one channel say() speaks on. Deliberately NOT out of the voice pool: a phrase is
## a second long and the pool steals its oldest player under load, so a specialist
## talking through a busy moment would be cut off by bumper hits.
func _build_speaker() -> void:
	_speaker = AudioStreamPlayer.new()
	_speaker.name = "Speaker"
	_speaker.bus = BUS_FICTION
	add_child(_speaker)


func _warm_sfx_cache() -> void:
	# Silent: a missing asset is only worth a log line when something actually asks
	# for it, and boot-time noise for assets nobody plays helps nobody.
	for event in EVENTS:
		var path := SFX_DIR + event + ".wav"
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path)
			if stream != null:
				_sfx[StringName(event)] = stream
	# The soft and hard rungs are not events, so the loop above misses them; warming
	# them here keeps the first hard bumper of a Night off the loader.
	for event: StringName in IMPACT_LAYERS:
		for asset: String in IMPACT_LAYERS[event]:
			var path := SFX_DIR + asset + ".wav"
			if not _sfx.has(StringName(asset)) and ResourceLoader.exists(path):
				var stream: AudioStream = load(path)
				if stream != null:
					_sfx[StringName(asset)] = stream


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


## The phrase bank is loaded on demand and cached: 24 short files that only matter on
## the Count screen and at a handful of story beats are not worth warming at boot.
func _phrase_stream(specialist: StringName, index: int) -> AudioStream:
	var key := StringName("%s_%d" % [specialist, index])
	if _phrases.has(key):
		return _phrases[key]
	var path := VOICE_DIR + String(key) + ".wav"
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		if stream != null:
			_phrases[key] = stream
			return stream
	if not _missing_logged.has(key):
		_missing_logged[key] = true
		print("[audio] no voice phrase yet for: ", key)
	return null


## Which rung of a velocity ladder a 0..1 impact lands on.
func _impact_rung(hit: float) -> int:
	if hit < IMPACT_SOFT_MAX:
		return 0
	if hit >= IMPACT_HARD_MIN:
		return 2
	return 1


## Where inside its rung the hit sat, remapped to -1..+1. This is what stops a rung
## from being a step function: the top of "soft" and the bottom of "medium" meet in the
## middle instead of jumping.
func _impact_tilt(hit: float, rung: int) -> float:
	var lo := 0.0
	var hi := 1.0
	match rung:
		0:
			hi = IMPACT_SOFT_MAX
		1:
			lo = IMPACT_SOFT_MAX
			hi = IMPACT_HARD_MIN
		_:
			lo = IMPACT_HARD_MIN
	if hi - lo < 0.0001:
		return 0.0
	return clampf((hit - lo) / (hi - lo), 0.0, 1.0) * 2.0 - 1.0


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


func _music_dir() -> String:
	return MUSIC_ROOT + CITY_DIRS[_city] + "/"


## Everything the current city puts on the synchronized player, in slot order: the level
## stack, the two state layers, and the city's bed if it has one.
func _city_stems() -> PackedStringArray:
	var names := PackedStringArray()
	names.append_array(STEMS)
	names.append_array(STATE_STEMS)
	if not CITY_BEDS[_city].is_empty():
		names.append(CITY_BEDS[_city])
	return names


## Drop the current city's players so another city's can be built. Detached before being
## freed so `get_node("Music")` cannot hand out a corpse in the frame after the swap.
func _teardown_music() -> void:
	for player in [_music_player, _piano_player]:
		if player == null:
			continue
		player.stop()
		remove_child(player)
		player.queue_free()
	_music_player = null
	_piano_player = null
	_music_sync = null
	_all_stems = PackedStringArray()
	_stem_slot = PackedInt32Array()
	_stem_db = PackedFloat32Array()
	_stem_target_db = PackedFloat32Array()
	_bed_index = -1
	_piano_db = SILENT_DB
	_piano_target_db = SILENT_DB
	set_process(false)


func _build_music() -> bool:
	if _music_sync != null:
		return true

	_all_stems = _city_stems()
	_bed_index = (_all_stems.size() - 1 if not CITY_BEDS[_city].is_empty() else -1)

	# A stem that is missing gets slot -1 and is simply skipped; the rest still play,
	# so a half-built assets/ folder costs you instruments, not the score.
	var slots: PackedInt32Array = []
	var streams: Array[AudioStream] = []
	for stem in _all_stems:
		var path := _music_dir() + stem + ".ogg"
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
		var key := StringName("__music_" + CITY_DIRS[_city])
		if not _missing_logged.has(key):
			_missing_logged[key] = true
			print("[audio] no music stems yet in ", _music_dir())
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
##
## A city that never wrote its own piano borrows the launch city's rather than counting
## the take in silence: the Count screen is a ritual, not part of the city's arrangement.
func _build_piano() -> bool:
	if _piano_player != null:
		return true
	var path := _music_dir() + COUNT_PIANO + ".ogg"
	if not ResourceLoader.exists(path):
		path = MUSIC_DIR + COUNT_PIANO + ".ogg"
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
## level, the requested state, the wiretap and the farewell — so they compose instead of
## fighting, any order of calls lands on the same mix, and lifting the wiretap restores
## the mix by re-evaluating rather than by remembering.
##
## Precedence is the order the game happens in: the farewell is the end of a city and
## overrides everything, the wiretap overrides the level/state mix, and the level/state
## mix is what the game normally asks for.
func _stem_target_for(index: int) -> float:
	if _farewell_active:
		return _farewell_stem_db(index)
	return _rico_stem_db(index, _mix_stem_db(index))


## docs/05 §9. What the wiretap leaves of a stem that would otherwise sit at `db`.
func _rico_stem_db(index: int, db: float) -> float:
	if _rico_step <= 1:
		return db
	if _rico_step == 2:
		return SILENT_DB if HOT_DUCKED.has(index) else db
	return db if index == RICO_HEARTBEAT else SILENT_DB


## docs/08 §1. The stack shedding: the calm level mix minus whoever has already left.
##
## Deliberately NOT the current state mix. A farewell during Heat or a raid would
## otherwise shed an ostinato and a halftime kit, and the moment being paid off here is
## the empire's growth run backwards — which is what `music_set_level` measures.
func _farewell_stem_db(index: int) -> float:
	if _farewell_bass_gone:
		return SILENT_DB
	if index == _bed_index:
		# The players leave; the record keeps turning until the last note is over. It is
		# the only thing in the mix that is not a person.
		return AUDIBLE_DB if _music_level > 0 else SILENT_DB
	if index >= STEMS.size():
		return SILENT_DB
	if index >= STEMS.size() - _farewell_shed or index >= _music_level:
		return SILENT_DB
	return AUDIBLE_DB


func _mix_stem_db(index: int) -> float:
	if _music_stopping:
		return SILENT_DB
	if index == _bed_index:
		# The bed is the room, not a player: it is up whenever the band is up at all,
		# through Heat and through a raid, and it goes when the music goes. The Count is
		# the exception — that screen is a different record.
		return (AUDIBLE_DB if _music_level > 0 and _music_state != STATE_COUNT
			else SILENT_DB)
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
	# The Count's piano is a comfort instrument by any reading, so the second cut takes
	# it; a farewell never has one on top of it at all.
	var count_up: bool = (_music_state == STATE_COUNT and not _music_stopping
		and not _farewell_active and _rico_step < 2)
	_piano_target_db = PIANO_DB if count_up else SILENT_DB
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


## Recompute the mix and land on it in one frame. This is what makes the wiretap read as
## a cut wire rather than as a fader: no fade, in either direction.
func _apply_mix_now() -> void:
	_recompute_targets()
	if _music_sync != null:
		for i in _stem_db.size():
			_stem_db[i] = _stem_target_db[i]
			if _stem_slot[i] >= 0:
				_music_sync.set_sync_stream_volume(_stem_slot[i], _stem_db[i])
	if _piano_player != null:
		_piano_db = _piano_target_db
		_piano_player.volume_db = _piano_db


## Buses the wiretap takes wholesale. Mute rather than volume: the options-screen
## sliders keep working underneath, and lifting the cut cannot lose the player's levels.
func _apply_rico_buses() -> void:
	_set_bus_mute(BUS_FICTION, _rico_step >= 1)
	_set_bus_mute(BUS_UI, _rico_step >= RICO_STEPS)


func _set_bus_mute(bus: StringName, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, muted)


func _sec_per_beat() -> float:
	return 60.0 / CITY_BPM[_city]


## How long until the stack's next beat line, so the first player packs up ON one.
## Headless (and before the score is running) there is no position to read and the
## answer is zero, which is the right answer: nothing is playing to be out of time with.
func _seconds_to_next_beat() -> float:
	if _music_player == null or not _music_player.playing:
		return 0.0
	var beat: float = _sec_per_beat()
	var into: float = fposmod(_music_player.get_playback_position(), beat)
	return 0.0 if into < 0.001 else beat - into


func _train_seconds() -> float:
	var stream: AudioStream = _sfx_stream(FAREWELL_TRAIN_EVENT)
	return stream.get_length() if stream != null else FAREWELL_TRAIN_SECONDS


## One frame of the Skip Town sequence (docs/08 §1).
##
## Everything here is derived from one clock rather than from a chain of timers: how many
## players have left is a function of elapsed time, so a dropped frame costs timing
## accuracy and never costs a stem.
func _advance_farewell(delta: float) -> void:
	_farewell_t += delta
	var t: float = _farewell_t - _farewell_lead
	var beat: float = _sec_per_beat()
	var gone := 0
	for at in FAREWELL_SHED_BEATS:
		if t >= float(at) * beat:
			gone += 1
	if gone != _farewell_shed:
		_farewell_shed = gone
		_fade_seconds = FAREWELL_FADE_SECONDS
		_recompute_targets()
	if not _farewell_bass_gone and t >= float(FAREWELL_BASS_BEAT) * beat:
		_farewell_bass_gone = true
		_fade_seconds = FAREWELL_LAST_FADE_SECONDS
		_recompute_targets()
	if not _farewell_train_played and t >= float(FAREWELL_TRAIN_BEAT) * beat:
		_farewell_train_played = true
		play(FAREWELL_TRAIN_EVENT)
	if _farewell_t >= _farewell_total:
		_end_farewell()


## The city is over. The stack is silent, stopped, at level 0 and calm: whatever the next
## city wants, it asks for from there.
func _end_farewell() -> void:
	_farewell_active = false
	_farewell_t = 0.0
	_farewell_shed = 0
	_farewell_bass_gone = false
	_farewell_train_played = false
	_fade_seconds = MUSIC_FADE_SECONDS
	_music_level = 0
	_music_state = STATE_CALM
	_music_stopping = false
	_apply_stem_db_now(SILENT_DB)
	if _music_player != null:
		_music_player.stop()
	if _piano_player != null:
		_piano_db = SILENT_DB
		_piano_target_db = SILENT_DB
		_piano_player.volume_db = SILENT_DB
		_piano_player.stop()


func _process(delta: float) -> void:
	if _farewell_active:
		_advance_farewell(delta)
	if _music_sync == null and _piano_player == null:
		if not _farewell_active:
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
	if moving or _farewell_active:
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
