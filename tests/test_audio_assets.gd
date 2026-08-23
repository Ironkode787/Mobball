extends RefCounted
## Guards the audio contract from specs/audio-pipeline.md §6, specs/audio-wave2.md §3
## and the wave-3 additions (docs/08 §5 voices, §8 velocity layers).
##
## Five things are being protected here. One: gameplay is allowed to call
## AudioDirector.play() for any event in the vocabulary and get a sound, so every event
## needs a file on disk. Two: the stem stack is sample-locked, which only works if every
## stem in the AudioStreamSynchronized — including the two wave-2 state layers — is
## exactly the same length; a stem one frame short would drift a whole beat out over a
## few minutes of play. Three: the events designed as loops have to actually join
## themselves, checked on the decoded samples rather than on the generator's word.
## Four: the peak ladder is a real claim about which sound wins when two land together,
## so the orderings that matter are measured off the committed samples. Five: the phrase
## bank is complete — a specialist with a missing mood is a character who goes quiet.

const SFX_DIR := "res://assets/audio/sfx/"
const VOICE_DIR := "res://assets/audio/voice/"
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
	# specs/m2-content.md §1/§4 — the Club deck
	"wheel_clatter", "chip_stack", "card_riffle", "reel_stop", "jackpot",
	"meeting_start", "meeting_jackpot", "meeting_end", "radio_squelch", "staircase_crest",
	# specs/m3-fall-rise.md AUDIO-4 — the endgame
	"boss_start", "boss_phase", "boss_beaten", "wrench_telegraph",
	"crane_telegraph", "crane_pull", "container_break", "pier_splash",
	"smuggling_start", "shipment_out", "chair_take", "sitdown", "dome_loop",
	"heist_start", "heist_beat", "heist_blown", "election_win",
	"empire_start", "empire_end", "reunion_start",
	"briefcase_drop", "briefcase_leave", "skip_town", "train_away",
]

## Loops, not one-shots: exempt from the one-shot length cap and held to a seam check.
const LOOP_EVENTS: PackedStringArray = ["bill_counter", "siren", "wheel_clatter"]

const FICTION_EVENTS: PackedStringArray = [
	"chime_a", "chime_b", "chime_c", "knocker", "cash_tick",
	"storefront_collect", "laundromat_wash", "bribe_paid", "guy_pinched", "bail_paid",
	"safe_open", "stamp_thunk", "paper_slip", "job_done", "skill_shot_ding",
	"combo_2", "combo_3", "combo_4", "headline_sting", "rankup_fanfare", "bill_counter",
	"coin_drop", "siren", "raid_start", "raid_win", "raid_lose",
	"chip_stack", "card_riffle", "jackpot", "meeting_start", "meeting_jackpot",
	"meeting_end", "radio_squelch", "staircase_crest",
	"boss_start", "boss_phase", "boss_beaten", "smuggling_start", "shipment_out",
	"chair_take", "sitdown", "dome_loop", "heist_start", "heist_beat", "heist_blown",
	"election_win", "empire_start", "empire_end", "reunion_start",
	"briefcase_drop", "briefcase_leave", "skip_town", "train_away",
]

## docs/08 §8. Quietest first; the middle entry is the event's own file.
const IMPACT_FAMILIES := {
	"flipper_up": ["flipper_up_soft", "flipper_up", "flipper_up_hard"],
	"bumper_hit": ["bumper_hit_soft", "bumper_hit", "bumper_hit_hard"],
	"sling_hit": ["sling_hit_soft", "sling_hit", "sling_hit_hard"],
}

## docs/08 §5. Nine specialists, three moods each; the filename index IS the mood index.
const SPECIALISTS: PackedStringArray = [
	"skids", "big_sal", "nussbaum", "rosa", "cohen", "professor", "consigliere",
	"manny", "eddie",
]
## Index order is the contract: <specialist>_0 is the greeting, _1 the quip, _2 the grumble.
const MOOD_NAMES: PackedStringArray = ["greeting", "quip", "grumble"]
## Phrases are subtitled one-liners, not speeches (docs/08 §5).
const VOICE_MIN_SECONDS := 0.80
const VOICE_MAX_SECONDS := 1.60

## Ordering claims the peak ladder makes, loudest first in each pair. The rank-up pair
## owns the top of the ladder: the knocker is "you won something real" and nothing the
## casino does is allowed to be bigger than it.
const PEAK_ORDER: Array = [
	["knocker", "rankup_fanfare"],
	["rankup_fanfare", "jackpot"],
	["jackpot", "meeting_start"],
	["meeting_start", "meeting_jackpot"],
	["meeting_jackpot", "meeting_end"],
	["knocker", "bumper_hit_hard"],
	["knocker", "staircase_crest"],
	["staircase_crest", "reel_stop"],
	["reel_stop", "wheel_clatter"],
	# Wave 4. The two that carry design weight: the dome loop is the biggest PITCHED
	# sound in the game and still loses to the knocker, and Empire Mode — everything lit,
	# x10 on everything — still loses to the rank-up pair, because a mode starting never
	# outranks a career moving. The telegraphs sit under what they telegraph.
	["knocker", "dome_loop"],
	["dome_loop", "rankup_fanfare"],
	["rankup_fanfare", "empire_start"],
	["empire_start", "jackpot"],
	["jackpot", "election_win"],
	["election_win", "boss_beaten"],
	["boss_beaten", "boss_start"],
	["boss_start", "boss_phase"],
	["boss_phase", "wrench_telegraph"],
	["empire_start", "empire_end"],
	["reunion_start", "heist_blown"],
	["heist_blown", "heist_start"],
	["heist_start", "heist_beat"],
	["drain", "pier_splash"],
	["pier_splash", "container_break"],
	["crane_pull", "crane_telegraph"],
	["shipment_out", "smuggling_start"],
	["sitdown", "chair_take"],
	["skip_town", "train_away"],
	["briefcase_drop", "briefcase_leave"],
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
	_test_impact_layers(t)
	_test_peak_ladder(t)
	_test_voice_bank(t)
	_test_stems_present(t)
	_test_stems_same_length(t)
	_test_count_piano(t)
	_test_director(t)
	_test_say(t)
	_test_music_states(t)
	_test_rico_dropout(t)
	_test_farewell(t)


## The 16-bit PCM payload of a committed WAV, read straight off disk.
##
## Not via load(): every one-shot in the set imports as QOA to keep the Android build
## small, and QOA bytes cannot be decoded from GDScript. The claims below (the peak
## ladder, layer brightness, "this voice is not silence") are claims about what the
## generator committed, so the committed file is the honest thing to measure. The one
## place the *imported* PCM has to be read instead is the loop-seam check, because
## there the import format is itself the thing under test.
func _pcm_of(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return PackedByteArray()
	var pos := 12
	while pos + 8 <= bytes.size():
		var id: String = bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size: int = bytes.decode_u32(pos + 4)
		if id == "data":
			return bytes.slice(pos + 8, mini(pos + 8 + size, bytes.size()))
		pos += 8 + size + (size & 1)
	return PackedByteArray()


## Peak sample as a linear 0..1 amplitude. `stride` > 1 samples the file instead of
## reading all of it — enough for "is anything in there", not enough for an ordering
## claim, so the ladder uses the default.
func _peak_of(path: String, stride: int = 1) -> float:
	var data: PackedByteArray = _pcm_of(path)
	if data.is_empty():
		return -1.0
	var frames: int = data.size() / 2
	var peak := 0.0
	var i := 0
	while i < frames:
		var s: float = absf(float(data.decode_s16(i * 2)))
		if s > peak:
			peak = s
		i += stride
	return peak / 32768.0


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


## docs/08 §8 velocity layers, as files on disk.
##
## The strict three-step brightness ordering is gated in tools/audiogen/generate.py,
## which has an FFT and measures the spectral centroid properly (it fails the build
## unless each step is >= 1.12x). What is worth re-proving here, on the PCM Godot
## actually imported, is the part a player would notice if it broke: the ladder rises
## in level and in length, and the hard layer really is *brighter* than the soft one
## rather than merely louder — which is the whole reason there are three files instead
## of one and a volume_db.
func _test_impact_layers(t: TestCtx) -> void:
	for family: String in IMPACT_FAMILIES:
		var stems: Array = IMPACT_FAMILIES[family]
		t.eq(stems[1], family, "the medium rung of %s must be the event's own file" % family)
		var peaks := PackedFloat64Array()
		var lengths := PackedFloat64Array()
		var bright := PackedFloat64Array()
		for stem: String in stems:
			var path := SFX_DIR + stem + ".wav"
			t.ok(ResourceLoader.exists(path), "missing impact layer %s" % stem)
			if not ResourceLoader.exists(path):
				continue
			var wav: AudioStreamWAV = load(path)
			t.ok(wav != null, "%s did not import as an AudioStreamWAV" % stem)
			if wav == null:
				continue
			t.ok(not wav.stereo, "%s should be mono" % stem)
			t.ok(_pcm_of(path).size() > 1000, "%s has no readable PCM payload" % stem)
			peaks.append(_peak_of(path))
			lengths.append(wav.get_length())
			bright.append(_high_fraction(path))
		if peaks.size() != 3:
			continue
		for i in 2:
			t.ok(peaks[i] < peaks[i + 1],
				"%s: %s (%.4f) should be quieter than %s (%.4f)"
					% [family, stems[i], peaks[i], stems[i + 1], peaks[i + 1]])
			t.ok(lengths[i] < lengths[i + 1],
				"%s: %s (%.3f s) should be shorter than %s (%.3f s)"
					% [family, stems[i], lengths[i], stems[i + 1], lengths[i + 1]])
		t.ok(bright[2] > bright[0] * 1.5,
			"%s: the hard layer is not meaningfully brighter than the soft one (%.3f vs %.3f of energy above 1.2 kHz) — that is one sound at two volumes"
				% [family, bright[2], bright[0]])


## Fraction of a file's energy above ~1.2 kHz, via a 2-pole Butterworth high-pass run
## over the PCM. Gain- and length-invariant, which is exactly what a brightness
## comparison between two differently-normalised files of different lengths needs.
func _high_fraction(path: String) -> float:
	# Butterworth high-pass, fc = 1200 Hz at 44.1 kHz, as direct-form-I coefficients.
	const B0 := 0.88610561
	const B1 := -1.77221122
	const B2 := 0.88610561
	const A1 := -1.75919695
	const A2 := 0.78522550
	var data: PackedByteArray = _pcm_of(path)
	if data.is_empty():
		return 0.0
	var frames: int = data.size() / 2
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var total := 0.0
	var high := 0.0
	for i in frames:
		var x: float = float(data.decode_s16(i * 2)) / 32768.0
		var y: float = B0 * x + B1 * x1 + B2 * x2 - A1 * y1 - A2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		total += x * x
		high += y * y
	return high / maxf(total, 1e-12)


## The peak ladder is a design claim: when two sounds land on the same frame, the one
## that is supposed to win does. Measured off the imported PCM so the claim survives
## any change to the generator that forgets about it.
func _test_peak_ladder(t: TestCtx) -> void:
	var peaks := {}
	for pair: Array in PEAK_ORDER:
		for name: String in pair:
			if not peaks.has(name):
				peaks[name] = _peak_of(SFX_DIR + name + ".wav")
	for pair: Array in PEAK_ORDER:
		var loud: float = peaks[pair[0]]
		var quiet: float = peaks[pair[1]]
		t.ok(loud > 0.0 and quiet > 0.0,
			"peak ladder: %s or %s did not import as readable PCM" % [pair[0], pair[1]])
		if loud <= 0.0 or quiet <= 0.0:
			continue
		t.ok(loud > quiet,
			"peak ladder: %s (%.4f) must stay above %s (%.4f)"
				% [pair[0], loud, pair[1], quiet])


## docs/08 §5: eight specialists, three moods each, and no gaps. A specialist whose
## grumble is missing is a character who goes silent exactly when he is annoyed.
func _test_voice_bank(t: TestCtx) -> void:
	for who in SPECIALISTS:
		for mood in MOOD_NAMES.size():
			var path := VOICE_DIR + "%s_%d.wav" % [who, mood]
			t.ok(ResourceLoader.exists(path), "missing voice phrase %s_%d" % [who, mood])
			if not ResourceLoader.exists(path):
				continue
			var wav: AudioStreamWAV = load(path)
			t.ok(wav is AudioStreamWAV, "%s_%d did not import as an AudioStreamWAV" % [who, mood])
			if wav == null:
				continue
			t.ok(not wav.stereo, "%s_%d should be mono" % [who, mood])
			t.eq(wav.loop_mode, AudioStreamWAV.LOOP_DISABLED,
				"%s_%d is a line, not a loop" % [who, mood])
			var seconds := wav.get_length()
			t.ok(seconds >= VOICE_MIN_SECONDS and seconds <= VOICE_MAX_SECONDS,
				"%s_%d is %.2f s, outside the %.1f-%.1f s phrase window"
					% [who, mood, seconds, VOICE_MIN_SECONDS, VOICE_MAX_SECONDS])
			# Not silent, and roughly at the bank's level. Strided: this is a "somebody
			# is in there" check, and 24 files at full rate is a lot of GDScript.
			t.ok(_peak_of(path, 7) > 0.10,
				"%s_%d is effectively silent" % [who, mood])


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

	# Velocity layers (docs/08 §8). The contract that matters most is the negative one:
	# a call with no `impact` must load exactly the file it always loaded.
	# Headless never marks a player as `playing`, so the pool hands out the same voice
	# every call: everything below reads what it needs off the voice *immediately*, and
	# never holds two players expecting them to be different objects.
	for family: String in IMPACT_FAMILIES:
		var stems: Array = IMPACT_FAMILIES[family]
		var event := StringName(family)
		var base: AudioStream = load(SFX_DIR + family + ".wav")
		var soft_file: AudioStream = load(SFX_DIR + stems[0] + ".wav")
		var hard_file: AudioStream = load(SFX_DIR + stems[2] + ".wav")

		var plain: AudioStreamPlayer = director.play(event)
		t.eq(plain.stream, base, "play(%s) with no impact changed which file it plays" % family)
		t.near(plain.volume_db, 0.0, 0.001, "play(%s) with no impact moved the level" % family)

		t.eq(director.play(event, {"impact": 0.0}).stream, soft_file,
			"impact 0.0 should pick the soft layer of %s" % family)
		t.eq(director.play(event, {"impact": 0.5}).stream, base,
			"impact 0.5 should pick the medium layer of %s, which is the base file" % family)
		var hard: AudioStreamPlayer = director.play(event, {"impact": 1.0})
		t.eq(hard.stream, hard_file, "impact 1.0 should pick the hard layer of %s" % family)
		t.eq(String(hard.bus), "Mechanics", "a layered %s still belongs on its event's bus" % family)
		# Out of range is clamped, not wrapped or refused.
		t.eq(director.play(event, {"impact": -3.0}).stream, soft_file,
			"impact below 0 should clamp to the soft layer of %s" % family)
		t.eq(director.play(event, {"impact": 9.0}).stream, hard_file,
			"impact above 1 should clamp to the hard layer of %s" % family)

		# Inside a rung the position still counts, so the ladder has no audible steps in
		# it: the bottom of the hard rung is quieter and flatter than the top of it.
		var low: AudioStreamPlayer = director.play(event, {"impact": 0.72, "pitch_jitter": 0.0})
		var low_db: float = low.volume_db
		var low_pitch: float = low.pitch_scale
		var high: AudioStreamPlayer = director.play(event, {"impact": 1.0, "pitch_jitter": 0.0})
		t.ok(low_db < high.volume_db,
			"%s: the bottom of the hard rung (%.2f dB) should sit under the top of it (%.2f dB)"
				% [family, low_db, high.volume_db])
		t.ok(low_pitch < high.pitch_scale,
			"%s: the within-rung tilt should reach pitch as well as level" % family)
		var middle: AudioStreamPlayer = director.play(event, {"impact": 0.5, "pitch_jitter": 0.0})
		t.near(middle.pitch_scale, 1.0, 0.001, "%s: the middle of a rung should be untilted" % family)
		t.near(middle.volume_db, 0.0, 0.001, "%s: the middle of a rung should be at unity" % family)
	# An event with no ladder ignores the option rather than failing.
	var unlayered: AudioStreamPlayer = director.play(&"knocker", {"impact": 1.0})
	t.eq(unlayered.stream, load(SFX_DIR + "knocker.wav"),
		"impact on an event with no velocity layers should be ignored")
	t.near(unlayered.volume_db, 0.0, 0.001, "impact should not move the level of an unlayered event")
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


## docs/08 §5 — AudioDirector.say(). The rules that matter: every specialist can be
## asked for every mood, a bad mood name still produces a line, and only one wiseguy
## holds the floor at a time.
func _test_say(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var director: Node = tree.root.get_node_or_null("AudioDirector") if tree != null else null
	if director == null:
		return

	for who in SPECIALISTS:
		for mood in MOOD_NAMES.size():
			var label: String = MOOD_NAMES[mood]
			var said: AudioStreamPlayer = director.say(StringName(who), StringName(label))
			t.ok(said != null, "say(%s, %s) produced nothing" % [who, label])
			if said == null:
				continue
			t.eq(said.stream, load(VOICE_DIR + "%s_%d.wav" % [who, mood]),
				"say(%s, %s) played the wrong phrase" % [who, label])
			t.eq(String(said.bus), "Fiction", "the mob speaks on the Fiction bus")
			t.ok(said.pitch_scale > 0.9 and said.pitch_scale < 1.1,
				"say(%s) detuned the voice past recognition (%f)" % [who, said.pitch_scale])

	# Default mood, and the fallback: a wrong mood name still says something, because a
	# character who goes silent reads as a bug and a wrong line reads as a character.
	t.eq(director.say(&"rosa").stream, load(VOICE_DIR + "rosa_1.wav"),
		"say() should default to the quip")
	t.eq(director.say(&"rosa", &"apoplectic").stream, load(VOICE_DIR + "rosa_1.wav"),
		"an unknown mood should fall back to the quip, not to silence")

	# One channel: the second guy takes the floor from the first, and it is not one of
	# the 24 pooled voices, so a busy playfield cannot steal a line mid-sentence.
	var first: AudioStreamPlayer = director.say(&"big_sal", &"grumble")
	var second: AudioStreamPlayer = director.say(&"manny", &"quip")
	t.eq(first, second, "say() should reuse one voice channel, interrupting the last speaker")
	t.eq(second.stream, load(VOICE_DIR + "manny_1.wav"), "the new speaker should be the one heard")
	for i in 24:
		director.play(&"bumper_hit")
	t.eq(director.say(&"cohen", &"greeting").stream, load(VOICE_DIR + "cohen_0.wav"),
		"a full voice pool must not touch the speaker channel")

	# Unknown specialists fail silent, exactly like unknown events.
	t.eq(director.say(&"the_rat"), null, "an unknown specialist should fail silent")
	director.voice_stop()
	t.ok(not director.is_speaking(), "voice_stop should end the line")
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


## docs/05 §9 — the RICO wiretap. Three things are being protected.
##
## One: the cuts are INSTANT. Every assertion below is made without calling _process()
## in between, because a wire being cut does not fade and the whole phase reads wrong if
## it does. Two: the order is fixed — Fiction, then the comfort instruments, then
## everything but the machine and the bass. Three, and the one that would actually break
## a run: lifting the dropout restores the mix EXACTLY, including any level or state
## change the game made while the wires were cut.
func _test_rico_dropout(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var director: Node = tree.root.get_node_or_null("AudioDirector") if tree != null else null
	if director == null:
		return
	var fiction := AudioServer.get_bus_index("Fiction")
	var ui := AudioServer.get_bus_index("UI")

	director.music_start()
	var sync: AudioStreamSynchronized = (director.get_node_or_null("Music")
		as AudioStreamPlayer).stream as AudioStreamSynchronized
	if sync == null:
		return
	var level := 7
	director.music_set_level(level)
	director.music_set_state(&"hot")
	director._process(4.0)
	t.eq(director.rico_step(), 0, "the wiretap should start lifted")
	var before := PackedFloat32Array()
	for i in SYNCED_STEMS.size():
		before.append(sync.get_sync_stream_volume(i))

	# Step 1 — the story goes quiet and the machine carries on. The score is untouched:
	# the fiction lives on a bus, so cutting it costs nothing in the stack.
	director.rico_dropout(1)
	t.eq(director.rico_step(), 1, "rico_dropout(1) did not take")
	t.ok(AudioServer.is_bus_mute(fiction), "step 1 should cut the Fiction bus")
	t.ok(not AudioServer.is_bus_mute(ui), "step 1 should leave the UI bus alone")
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), before[i], 0.01,
			"step 1 should not touch the score (%s)" % SYNCED_STEMS[i])

	# Step 2 — the comfort instruments go, and they go now, not over a fade.
	director.rico_dropout(2)
	for i in SYNCED_STEMS.size():
		var comfort: bool = i == 2 or i == 4 or i == 6
		t.near(sync.get_sync_stream_volume(i), -80.0 if comfort else before[i], 0.01,
			"step 2 should take exactly the comfort stems (%s)" % SYNCED_STEMS[i])

	# Step 3 — everything but the Mechanics bus and the heartbeat.
	director.rico_dropout(3)
	t.ok(AudioServer.is_bus_mute(ui), "step 3 should cut the UI bus too")
	t.ok(AudioServer.is_bus_mute(fiction), "step 3 should keep the Fiction bus cut")
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), before[0] if i == 0 else -80.0, 0.01,
			"step 3 should leave only the bass (%s)" % SYNCED_STEMS[i])

	# Idempotent, and out of range clamps rather than wrapping.
	director.rico_dropout(3)
	director.rico_dropout(99)
	t.eq(director.rico_step(), 3, "a step past the end should clamp to the last cut")
	t.near(sync.get_sync_stream_volume(1), -80.0, 0.01, "a clamped step changed the mix")

	# A level change made while the wires are cut is remembered, not applied...
	director.music_set_level(3)
	t.eq(director.music_level(), 3, "music_set_level should still be accepted mid-dropout")
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), before[0] if i == 0 else -80.0, 0.01,
			"a level change must not escape the dropout (%s)" % SYNCED_STEMS[i])

	# ...and lifting the dropout lands on the mix the game asked for, in one frame.
	director.rico_dropout(0)
	t.eq(director.rico_step(), 0, "rico_dropout(0) did not lift")
	t.ok(not AudioServer.is_bus_mute(fiction), "lifting should un-cut the Fiction bus")
	t.ok(not AudioServer.is_bus_mute(ui), "lifting should un-cut the UI bus")
	t.eq(String(director.music_state()), "hot", "the dropout ate the music state")
	var want := _expected_mix("hot", 3)
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), want[i], 0.01,
			"lifting should restore the level/state mix exactly (%s)" % SYNCED_STEMS[i])

	# And a full round trip with nothing else happening restores byte-for-byte.
	director.music_set_level(level)
	director._process(4.0)
	director.rico_dropout(3)
	director.rico_dropout(0)
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), before[i], 0.01,
			"a dropout round trip changed the mix (%s)" % SYNCED_STEMS[i])
	director.music_set_state(&"calm")
	director.music_stop(false)
	director.stop_all()


## Step the director's clock in small slices, asserting on the way that no stem ever
## gets LOUDER. The farewell only takes things away; a stem coming back up would mean a
## level or state call had leaked into the sequence.
func _farewell_run(t: TestCtx, director: Node, sync: AudioStreamSynchronized,
		seconds: float, label: String) -> void:
	var was := PackedFloat32Array()
	for i in SYNCED_STEMS.size():
		was.append(sync.get_sync_stream_volume(i))
	var left := seconds
	while left > 0.0:
		var step: float = minf(0.02, left)
		director._process(step)
		left -= step
		for i in SYNCED_STEMS.size():
			var now: float = sync.get_sync_stream_volume(i)
			if now > was[i] + 0.001:
				t.ok(false, "%s: %s came back up (%.1f -> %.1f dB)"
					% [label, SYNCED_STEMS[i], was[i], now])
			was[i] = now


## docs/08 §1 — Skip Town, the game's saddest musical moment, as a dB trajectory.
##
## The claims: eight players leave one at a time from the top of the stack, on the beat
## grid, each with a fade sharper than a music fade; the bass is alone for two bars; the
## train closes it; and the sequence owns music control while it runs, so nothing the
## rest of the game says can put an instrument back.
func _test_farewell(t: TestCtx) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var director: Node = tree.root.get_node_or_null("AudioDirector") if tree != null else null
	if director == null:
		return
	var train: AudioStream = load(SFX_DIR + "train_away.wav")
	for child in director.get_children():
		var voice := child as AudioStreamPlayer
		if voice != null and String(voice.name).begins_with("Voice"):
			voice.stream = null

	director.music_start()
	var sync: AudioStreamSynchronized = (director.get_node_or_null("Music")
		as AudioStreamPlayer).stream as AudioStreamSynchronized
	if sync == null:
		return
	director.music_set_state(&"calm")
	director.music_set_level(LEVEL_STEMS)
	director._process(4.0)
	for i in LEVEL_STEMS:
		t.near(sync.get_sync_stream_volume(i), 0.0, 0.01,
			"the whole band should be up before the farewell (%s)" % SYNCED_STEMS[i])

	var total: float = director.play_farewell()
	t.ok(director.is_farewell_playing(), "play_farewell() did not start the sequence")
	# Seven exits on the beat grid, two bars of bass, and a train: about twenty seconds.
	t.ok(total > 18.0 and total < 22.0,
		"the farewell should run about 20 s, got %.2f" % total)
	t.near(director.play_farewell(), total, 0.05,
		"a second call should report the time left, not start a second farewell")

	# Music control belongs to the sequence now.
	director.music_set_level(2)
	t.eq(director.music_level(), LEVEL_STEMS, "music_set_level should be refused mid-farewell")
	director.music_set_state(&"raid")
	t.eq(String(director.music_state()), "calm", "music_set_state should be refused mid-farewell")

	# The shed: after each exit's fade has run, that stem is gone and everything below it
	# is still playing. The beats are FAREWELL_SHED_BEATS; a beat is 60/92 s.
	var beat := 60.0 / 92.0
	var shed_at: PackedInt32Array = [0, 2, 5, 7, 10, 12, 15]
	var at := 0.0
	for k in shed_at.size():
		var mark: float = float(shed_at[k]) * beat + 0.55
		_farewell_run(t, director, sync, mark - at, "shed %d" % (k + 1))
		at = mark
		var alive: int = LEVEL_STEMS - (k + 1)
		for i in SYNCED_STEMS.size():
			t.near(sync.get_sync_stream_volume(i), 0.0 if i < alive else -80.0, 0.5,
				"after exit %d, %s should be %s" % [k + 1, SYNCED_STEMS[i],
					"playing" if i < alive else "gone"])
		t.ok(director.is_farewell_playing(), "the farewell ended early at exit %d" % (k + 1))

	# The bass rings alone for two bars — and it is still ringing a bar and a half in.
	_farewell_run(t, director, sync, 6.0 * beat, "bass alone")
	at += 6.0 * beat
	t.near(sync.get_sync_stream_volume(0), 0.0, 0.01, "the last bass note should ring alone")
	var heard_train := false
	for child in director.get_children():
		var voice := child as AudioStreamPlayer
		if voice != null and voice.stream == train:
			heard_train = true
	t.ok(not heard_train, "the train arrived before the bass had finished")

	# Then it lets go, over a fade of its own that is longer than the exits were.
	_farewell_run(t, director, sync, 25.0 * beat - at + 0.1, "the last note")
	at = 25.0 * beat + 0.1
	t.near(sync.get_sync_stream_volume(0), -80.0, 1.0, "the last note should have let go")
	for child in director.get_children():
		var voice := child as AudioStreamPlayer
		if voice != null and voice.stream == train:
			heard_train = true
	t.ok(heard_train, "the farewell should end on the train")

	# And when the train has gone, so has the city: silent, stopped, level 0, calm.
	director._process(total - at + 0.5)
	t.ok(not director.is_farewell_playing(), "the farewell should end itself")
	t.eq(director.music_level(), 0, "a city that is over is at level 0")
	t.eq(String(director.music_state()), "calm", "a city that is over is calm")
	t.ok(not director.is_music_playing(), "the stack should be stopped when the train has gone")
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), -80.0, 0.01,
			"nothing should be left playing after the farewell (%s)" % SYNCED_STEMS[i])

	# Control is back.
	director.music_start()
	director.music_set_level(4)
	t.eq(director.music_level(), 4, "music control should return after the farewell")

	# The two ways to abandon it. farewell_stop() hands the stack back to level/state...
	director._process(4.0)
	director.play_farewell()
	director._process(2.0)
	director.farewell_stop()
	t.ok(not director.is_farewell_playing(), "farewell_stop() did not cancel the sequence")
	director.music_set_level(5)
	director._process(4.0)
	var back := _expected_mix("calm", 5)
	for i in SYNCED_STEMS.size():
		t.near(sync.get_sync_stream_volume(i), back[i], 0.01,
			"cancelling should hand the stack back to level/state (%s)" % SYNCED_STEMS[i])

	# ...and music_stop() is allowed to interrupt it, because a scene tearing down must
	# never be refused.
	director.play_farewell()
	director._process(1.0)
	director.music_stop(false)
	t.ok(not director.is_farewell_playing(), "music_stop() should cancel a running farewell")
	t.ok(not director.is_music_playing(), "music_stop(false) should still stop immediately")
	director.stop_all()
