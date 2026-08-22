extends RefCounted
## Guards the audio contract from specs/audio-pipeline.md §6 and specs/audio-wave2.md §3.
##
## Three things are being protected here. One: gameplay is allowed to call
## AudioDirector.play() for any event in the vocabulary and get a sound, so every event
## needs a file on disk. Two: the stem stack is sample-locked, which only works if every
## stem in the AudioStreamSynchronized — including the two wave-2 state layers — is
## exactly the same length; a stem one frame short would drift a whole beat out over a
## few minutes of play. Three: the two events designed as loops have to actually join
## themselves, checked on the decoded samples rather than on the generator's word.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/city1/"

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

## Loops, not one-shots: exempt from the one-shot length cap and held to a seam check.
const LOOP_EVENTS: PackedStringArray = ["bill_counter", "siren"]

const FICTION_EVENTS: PackedStringArray = [
	"chime_a", "chime_b", "chime_c", "knocker", "cash_tick",
	"storefront_collect", "laundromat_wash", "bribe_paid", "guy_pinched", "bail_paid",
	"safe_open", "stamp_thunk", "paper_slip", "job_done", "skill_shot_ding",
	"combo_2", "combo_3", "combo_4", "headline_sting", "rankup_fanfare", "bill_counter",
	"coin_drop", "siren", "raid_start", "raid_win", "raid_lose",
]

## Everything on one AudioStreamSynchronized — the level stack plus the state layers.
const SYNCED_STEMS: PackedStringArray = [
	"01_bass", "02_drums", "03_vibes", "04_trumpet",
	"05_organ", "06_barisax", "07_strings", "08_full",
	"09_tense", "10_raid_drums",
]
const LEVEL_STEMS := 8

## 92 BPM, 8 bars of 4/4: round(44100 * 32 * 60 / 92) frames.
const LOOP_FRAMES := 920348
const LOOP_SECONDS := float(LOOP_FRAMES) / 44100.0
const LENGTH_TOLERANCE := 0.001     # 1 ms, per spec §6

## The Count's piano is deliberately NOT synced: 55 BPM, 4 bars.
const COUNT_PIANO := "count_piano"
const COUNT_FRAMES := 769745
const COUNT_SECONDS := float(COUNT_FRAMES) / 44100.0

## The seam step, over the largest step the file makes anywhere. Below 1.0 means the
## join is quieter than ordinary programme material inside the loop, i.e. inaudible.
const SEAM_RATIO_MAX := 1.5
## ...and both ends have to actually be ringing. A loop that is only seamless because
## it faded to silence at both ends is a one-shot with extra steps.
const SEAM_EDGE_RMS_MIN := 0.02


func run(t: TestCtx) -> void:
	_test_sfx_present(t)
	_test_loop_seams(t)
	_test_stems_present(t)
	_test_stems_same_length(t)
	_test_count_piano(t)
	_test_director(t)
	_test_music_states(t)


func _test_sfx_present(t: TestCtx) -> void:
	for event in EVENTS:
		var path := SFX_DIR + event + ".wav"
		t.ok(ResourceLoader.exists(path), "missing SFX asset for event %s" % event)
		var stream: AudioStream = load(path) if ResourceLoader.exists(path) else null
		t.ok(stream is AudioStreamWAV, "%s did not import as an AudioStreamWAV" % event)
		if stream == null:
			continue
		t.ok(stream.get_length() > 0.01, "%s is empty" % event)
		if event in LOOP_EVENTS:
			t.ok(stream.get_length() < 10.0, "%s is too long even for a loop" % event)
		else:
			t.ok(stream.get_length() < 4.0, "%s is too long for a one-shot" % event)


## Decoded-seam check on the two designed loops (specs/audio-wave2.md §3).
##
## Reads the samples the engine will actually play — the imported AudioStreamWAV's own
## PCM — and compares the step across the loop point with the largest step the file
## makes anywhere inside itself. A click at the join shows up here as a step several
## times bigger than anything in the programme material.
func _test_loop_seams(t: TestCtx) -> void:
	for event in LOOP_EVENTS:
		var path := SFX_DIR + event + ".wav"
		if not ResourceLoader.exists(path):
			continue
		var wav: AudioStreamWAV = load(path)
		if wav == null:
			continue
		# QOA is lossy and its predictor state does not survive the jump back to
		# loop_begin, so a designed loop has to import as PCM. This also makes the data
		# below readable as plain signed 16-bit.
		t.eq(wav.format, AudioStreamWAV.FORMAT_16_BITS,
			"%s must import as 16-bit PCM (compress/mode=0) to loop cleanly" % event)
		t.ok(not wav.stereo, "%s should be mono" % event)
		if wav.format != AudioStreamWAV.FORMAT_16_BITS or wav.stereo:
			continue

		var data: PackedByteArray = wav.data
		var frames: int = data.size() / 2
		t.ok(frames > 1000, "%s decoded to %d frames" % [event, frames])
		if frames <= 1000:
			continue

		var first: float = float(data.decode_s16(0)) / 32768.0
		var last: float = float(data.decode_s16((frames - 1) * 2)) / 32768.0
		var seam: float = absf(first - last)

		var biggest := 0.0
		var sum_sq := 0.0
		var prev: float = first
		for i in range(1, frames):
			var s: float = float(data.decode_s16(i * 2)) / 32768.0
			var step: float = absf(s - prev)
			if step > biggest:
				biggest = step
			sum_sq += s * s
			prev = s
		var ratio: float = seam / maxf(biggest, 1e-9)
		t.ok(ratio <= SEAM_RATIO_MAX,
			"%s loop seam steps %.5f, %.2fx the biggest step inside the file — a click"
				% [event, seam, ratio])

		# Both ends still ringing: a "seamless" loop that faded out at both ends is not
		# a loop, and the seam ratio above would happily pass it.
		var overall: float = sqrt(sum_sq / float(frames - 1)) + 1e-12
		var head := 0.0
		var tail := 0.0
		for i in 64:
			var h: float = float(data.decode_s16(i * 2)) / 32768.0
			var l: float = float(data.decode_s16((frames - 1 - i) * 2)) / 32768.0
			head += h * h
			tail += l * l
		var edge: float = minf(sqrt(head / 64.0), sqrt(tail / 64.0)) / overall
		t.ok(edge >= SEAM_EDGE_RMS_MIN,
			"%s loop edges are near-silent (%.4f of file RMS) — a faded loop, not a seamless one"
				% [event, edge])


func _test_stems_present(t: TestCtx) -> void:
	for stem in SYNCED_STEMS:
		var path := MUSIC_DIR + stem + ".ogg"
		t.ok(ResourceLoader.exists(path), "missing music stem %s" % stem)
		if ResourceLoader.exists(path):
			t.ok(load(path) is AudioStreamOggVorbis,
				"%s did not import as an AudioStreamOggVorbis" % stem)


func _test_stems_same_length(t: TestCtx) -> void:
	var lengths: PackedFloat64Array = []
	for stem in SYNCED_STEMS:
		var path := MUSIC_DIR + stem + ".ogg"
		if not ResourceLoader.exists(path):
			continue
		var stream: AudioStream = load(path)
		if stream == null:
			continue
		lengths.append(stream.get_length())
	t.eq(lengths.size(), SYNCED_STEMS.size(), "not every stem loaded")
	if lengths.is_empty():
		return
	for i in lengths.size():
		t.near(lengths[i], LOOP_SECONDS, LENGTH_TOLERANCE,
			"stem %s is %.4f s, expected the 8-bar loop" % [SYNCED_STEMS[i], lengths[i]])
		t.near(lengths[i], lengths[0], LENGTH_TOLERANCE,
			"stem %s does not match %s — the stack would drift" % [SYNCED_STEMS[i], SYNCED_STEMS[0]])


func _test_count_piano(t: TestCtx) -> void:
	var path := MUSIC_DIR + COUNT_PIANO + ".ogg"
	t.ok(ResourceLoader.exists(path), "missing %s" % COUNT_PIANO)
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	t.ok(stream is AudioStreamOggVorbis, "%s did not import as an AudioStreamOggVorbis" % COUNT_PIANO)
	if stream == null:
		return
	t.near(stream.get_length(), COUNT_SECONDS, LENGTH_TOLERANCE,
		"%s is %.4f s, expected its own 4-bar loop at 55 BPM" % [COUNT_PIANO, stream.get_length()])
	# It must NOT match the band: it is a separate player at a separate tempo, and if it
	# ever ends up the same length that is a sign it got folded into the synced stack.
	t.ok(absf(stream.get_length() - LOOP_SECONDS) > 0.5,
		"%s should not be the band's loop length" % COUNT_PIANO)


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
		t.eq(String(voice.bus), "Fiction" if event in FICTION_EVENTS else "Mechanics",
			"play(%s) went to the wrong bus" % event)
	director.stop_all()

	for bus in ["Master", "Music", "Mechanics", "Fiction", "UI"]:
		t.ok(AudioServer.get_bus_index(bus) >= 0, "bus %s was not created at runtime" % bus)
	t.near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -4.0, 0.01,
		"music bus should carry the trim that keeps the full stack under the ceiling")

	# The master limiter (docs/08 §6) is what makes the per-family peak ladders safe to
	# sum; it must exist exactly once no matter how often the director re-initialises.
	var master := AudioServer.get_bus_index("Master")
	var limiters := 0
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			limiters += 1
	t.eq(limiters, 1, "Master should carry exactly one limiter")
	director._ensure_buses()
	var again := 0
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectHardLimiter:
			again += 1
	t.eq(again, 1, "re-running bus setup should not stack a second limiter")

	# Options are honoured.
	var quiet: AudioStreamPlayer = director.play(&"bumper_hit", {"volume_db": -12.0, "bus": &"UI"})
	t.near(quiet.volume_db, -12.0, 0.001, "volume_db option ignored")
	t.eq(String(quiet.bus), "UI", "bus option ignored")
	var exact: AudioStreamPlayer = director.play(&"bumper_hit", {"pitch_scale": 1.25})
	t.near(exact.pitch_scale, 1.25, 0.001, "pitch_scale option ignored")
	var flat: AudioStreamPlayer = director.play(&"bumper_hit", {"pitch_jitter": 0.0})
	t.near(flat.pitch_scale, 1.0, 0.001, "pitch_jitter 0 should not detune")

	# The looping events can be asked to loop, and asking must not infect the one-shot.
	for event in LOOP_EVENTS:
		var looped: AudioStreamPlayer = director.play(StringName(event), {"loop": true})
		t.ok(looped != null, "play(%s, loop) returned no voice" % event)
		if looped == null:
			continue
		var wav := looped.stream as AudioStreamWAV
		t.ok(wav != null, "%s looping variant is not an AudioStreamWAV" % event)
		if wav == null:
			continue
		t.eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD,
			"play(%s, loop) did not set loop_mode" % event)
		t.eq(wav.loop_begin, 0, "%s should loop from the top" % event)
		t.near(float(wav.loop_end) / float(wav.mix_rate), wav.get_length(), 0.001,
			"%s loop_end should be the end of the sample" % event)
		var oneshot: AudioStreamPlayer = director.play(StringName(event))
		var plain := oneshot.stream as AudioStreamWAV
		t.eq(plain.loop_mode, AudioStreamWAV.LOOP_DISABLED,
			"asking for a looping %s must not turn the shared one-shot into a loop" % event)
	director.stop_all()

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
	t.eq(director.music_level(), LEVEL_STEMS, "music_set_level should clamp to the stack size")
	director.music_set_level(0)
	director.music_stop(false)
	t.ok(not director.is_music_playing(), "music_stop(false) should stop immediately")
	director.stop_all()


## The mix specs/audio-wave2.md §2 asks for, per stem, in dB. `level` is what
## music_set_level was last given; the index order is the STEMS + STATE_STEMS order.
func _expected_mix(state: String, level: int) -> PackedFloat32Array:
	var db := PackedFloat32Array()
	for i in SYNCED_STEMS.size():
		var v := -80.0
		match state:
			"calm":
				v = 0.0 if i < level and i < LEVEL_STEMS else -80.0
			"hot":
				if i == 8:                       # 09_tense
					v = 0.0
				elif i >= LEVEL_STEMS or i >= level:
					v = -80.0
				elif i == 2 or i == 4 or i == 6:  # vibes, organ, strings
					v = -4.0
				else:
					v = 0.0
			"raid":
				if i == 0 or i == 8 or i == 9:   # bass, tense, raid drums
					v = 0.0
				elif i == 1:                     # 02_drums is replaced, not ducked
					v = -80.0
				else:
					v = -60.0
			"count":
				v = -80.0
		db.append(v)
	return db


## specs/audio-wave2.md §2: the state mix composes with music_set_level, is idempotent,
## and — the part that actually matters — never stops or rebuilds the synchronized
## player, because that is what holds the ten stems in sample lock.
##
## Headless never propagates ENTER_TREE, so `playing` is false for every player and
## cannot be asserted on. What CAN be asserted, and is worth more, is that the mix
## lands exactly on the spec's table and that the player and its stream are the same
## objects afterwards as before — a hard-cut implementation fails that immediately.
func _test_music_states(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var director: Node = tree.root.get_node_or_null("AudioDirector") if tree != null else null
	if director == null:
		return

	director.music_start()
	var player: AudioStreamPlayer = director.get_node_or_null("Music")
	t.ok(player != null, "the director should own one long-lived Music player")
	if player == null:
		return
	var sync: AudioStreamSynchronized = player.stream as AudioStreamSynchronized
	t.ok(sync != null, "the Music player should carry an AudioStreamSynchronized")
	if sync == null:
		return
	t.eq(sync.stream_count, SYNCED_STEMS.size(),
		"all %d stems belong on ONE synchronized stream" % SYNCED_STEMS.size())
	var player_id := player.get_instance_id()
	var sync_id := sync.get_instance_id()

	var level := 6
	director.music_set_level(level)
	director.music_set_state(&"calm")
	t.eq(String(director.music_state()), "calm", "music_set_state(calm) did not take")

	for state in ["hot", "raid", "count", "calm", "raid", "count", "hot", "calm"]:
		director.music_set_state(StringName(state))
		t.eq(String(director.music_state()), state, "music_set_state(%s) did not take" % state)
		# Idempotent: saying it twice is not a different mix.
		director.music_set_state(StringName(state))
		director._process(4.0)                   # drive the fades to completion
		var want := _expected_mix(state, level)
		for i in SYNCED_STEMS.size():
			t.near(sync.get_sync_stream_volume(i), want[i], 0.01,
				"state %s: %s should sit at %.0f dB, got %.1f"
					% [state, SYNCED_STEMS[i], want[i], sync.get_sync_stream_volume(i)])
		# Levels stay settable in every state, and are remembered rather than applied.
		director.music_set_level(4)
		t.eq(director.music_level(), 4, "music_set_level was refused during state %s" % state)
		director.music_set_level(level)
		director._process(4.0)
		for i in SYNCED_STEMS.size():
			t.near(sync.get_sync_stream_volume(i), want[i], 0.01,
				"state %s: a level change should not escape the state mix (%s)"
					% [state, SYNCED_STEMS[i]])

	# The Count puts the piano on top of a silent stack, and leaving takes it away.
	var piano: AudioStreamPlayer = director.get_node_or_null("CountPiano")
	t.ok(piano != null, "entering count should have built the piano player")
	if piano != null:
		t.eq(String(piano.bus), "Music", "the piano belongs on the Music bus")
		director.music_set_state(&"count")
		director._process(4.0)
		t.near(piano.volume_db, 0.0, 0.01, "the piano should be up in count")
		director.music_set_state(&"calm")
		director._process(4.0)
		t.near(piano.volume_db, -80.0, 0.01, "leaving count should take the piano away")

	# Unknown states are ignored, not crashed on, and do not disturb the current mix.
	director.music_set_state(&"going_legit_hours")
	t.eq(String(director.music_state()), "calm", "an unknown state should be ignored")

	# Returning to calm restored the level mix, and nothing was ever restarted.
	t.eq(director.music_level(), level, "the level survived the round trip through the states")
	t.eq(director.get_node_or_null("Music").get_instance_id(), player_id,
		"the Music player was replaced — the sample lock does not survive that")
	t.eq((director.get_node_or_null("Music").stream as AudioStreamSynchronized).get_instance_id(),
		sync_id, "the synchronized stream was rebuilt — every stem would restart")

	# A faded stop silences everything; starting again comes back to the same mix.
	director.music_stop(true)
	director._process(4.0)
	t.ok(not director.is_music_playing(), "a completed fade-out should stop the player")
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), -80.0, 0.01,
			"music_stop should silence %s" % SYNCED_STEMS[i])
	director.music_start()
	director.music_set_level(level)
	director._process(4.0)
	var calm := _expected_mix("calm", level)
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), calm[i], 0.01,
			"restarting after a faded stop should restore the mix (%s)" % SYNCED_STEMS[i])
	director.music_stop(false)
	director.stop_all()
