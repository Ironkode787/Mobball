extends RefCounted
## Guards the audio contract from specs/audio-pipeline.md §6.
##
## Two things are being protected here. One: gameplay is allowed to call
## AudioDirector.play() for any §4 event and get a sound, so every event needs a file
## on disk. Two: the stem stack is sample-locked, which only works if all eight stems
## are exactly the same length — a stem one frame short would drift a whole beat out
## over a few minutes of play.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/city1/"

const EVENTS: PackedStringArray = [
	"flipper_up", "flipper_down", "bumper_hit", "sling_hit", "plunger_pull",
	"plunger_launch", "ball_spawn", "drain", "nudge_thump", "tilt_warning", "tilt",
	"knocker", "cash_tick", "chime_a", "chime_b", "chime_c", "wall_tap",
]

const STEMS: PackedStringArray = [
	"01_bass", "02_drums", "03_vibes", "04_trumpet",
	"05_organ", "06_barisax", "07_strings", "08_full",
]

## 92 BPM, 8 bars of 4/4: round(44100 * 32 * 60 / 92) frames.
const LOOP_FRAMES := 920348
const LOOP_SECONDS := float(LOOP_FRAMES) / 44100.0
const LENGTH_TOLERANCE := 0.001     # 1 ms, per spec §6


func run(t: TestCtx) -> void:
	_test_sfx_present(t)
	_test_stems_present(t)
	_test_stems_same_length(t)
	_test_director(t)


func _test_sfx_present(t: TestCtx) -> void:
	for event in EVENTS:
		var path := SFX_DIR + event + ".wav"
		t.ok(ResourceLoader.exists(path), "missing SFX asset for event %s" % event)
		var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
		t.ok(stream is AudioStreamWAV, "%s did not import as an AudioStreamWAV" % event)
		if stream != null:
			t.ok(stream.get_length() > 0.01, "%s is empty" % event)
			t.ok(stream.get_length() < 4.0, "%s is too long for a one-shot" % event)


func _test_stems_present(t: TestCtx) -> void:
	for stem in STEMS:
		var path := MUSIC_DIR + stem + ".ogg"
		t.ok(ResourceLoader.exists(path), "missing music stem %s" % stem)
		if ResourceLoader.exists(path):
			t.ok(load(path) is AudioStreamOggVorbis,
				"%s did not import as an AudioStreamOggVorbis" % stem)


func _test_stems_same_length(t: TestCtx) -> void:
	var lengths: PackedFloat64Array = []
	for stem in STEMS:
		var path := MUSIC_DIR + stem + ".ogg"
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			continue
		lengths.append(stream.get_length())
	t.eq(lengths.size(), STEMS.size(), "not every stem loaded")
	if lengths.is_empty():
		return
	for i in lengths.size():
		t.near(lengths[i], LOOP_SECONDS, LENGTH_TOLERANCE,
			"stem %s is %.4f s, expected the 8-bar loop" % [STEMS[i], lengths[i]])
		t.near(lengths[i], lengths[0], LENGTH_TOLERANCE,
			"stem %s does not match %s — the stack would drift" % [STEMS[i], STEMS[0]])


func _test_director(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var director: Node = tree.root.get_node_or_null("AudioDirector") if tree != null else null
	t.ok(director != null, "AudioDirector autoload is missing")
	if director == null:
		return

	# Every event resolves to a voice, on the right bus, at a sane pitch. (This is also
	# what brings the director up: _ready() never fires under the bare-SceneTree runner,
	# so the director initialises itself on first use.)
	for event in EVENTS:
		var voice: AudioStreamPlayer = director.play(StringName(event))
		t.ok(voice != null, "play(%s) returned no voice" % event)
		if voice == null:
			continue
		t.ok(voice.stream != null, "play(%s) left the voice without a stream" % event)
		t.ok(voice.pitch_scale > 0.5 and voice.pitch_scale < 2.0,
			"play(%s) produced a wild pitch (%f)" % [event, voice.pitch_scale])
		var want_fiction: bool = event in ["chime_a", "chime_b", "chime_c", "knocker", "cash_tick"]
		t.eq(String(voice.bus), "Fiction" if want_fiction else "Mechanics",
			"play(%s) went to the wrong bus" % event)

	for bus in ["Master", "Music", "Mechanics", "Fiction", "UI"]:
		t.ok(AudioServer.get_bus_index(bus) >= 0, "bus %s was not created at runtime" % bus)
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -4.0, 0.01,
		"music bus should carry the trim that keeps the full stack under the ceiling")

	# Options are honoured.
	var quiet: AudioStreamPlayer = director.play(&"bumper_hit", {"volume_db": -12.0, "bus": &"UI"})
	t.near(quiet.volume_db, -12.0, 0.001, "volume_db option ignored")
	t.eq(String(quiet.bus), "UI", "bus option ignored")
	var exact: AudioStreamPlayer = director.play(&"bumper_hit", {"pitch_scale": 1.25})
	t.near(exact.pitch_scale, 1.25, 0.001, "pitch_scale option ignored")
	var flat: AudioStreamPlayer = director.play(&"bumper_hit", {"pitch_jitter": 0.0})
	t.near(flat.pitch_scale, 1.0, 0.001, "pitch_jitter 0 should not detune")

	# Jitter actually varies, and stays inside the requested ±octaves.
	var seen := {}
	for i in 24:
		var v: AudioStreamPlayer = director.play(&"flipper_up", {"pitch_jitter": 0.05})
		seen[snappedf(v.pitch_scale, 0.0001)] = true
		t.ok(absf(log(v.pitch_scale) / log(2.0)) <= 0.0501,
			"pitch jitter left the ±0.05 octave window")
	t.ok(seen.size() > 1, "pitch jitter produced the same pitch every time")

	# A missing event must fail silent, not crash.
	t.eq(director.play(&"definitely_not_a_real_event"), null,
		"unknown event should fail silent")

	# Music: build, level, fade, stop — all must be safe headless.
	director.music_start()
	t.eq(director.music_level(), 0, "music should start silent and be faded up")
	director.music_set_level(3)
	t.eq(director.music_level(), 3, "music_set_level did not take")
	director.music_set_level(99)
	t.eq(director.music_level(), STEMS.size(), "music_set_level should clamp to the stack size")
	director.music_set_level(0)
	director.music_stop(false)
	t.ok(not director.is_music_playing(), "music_stop(false) should stop immediately")
	director.stop_all()
