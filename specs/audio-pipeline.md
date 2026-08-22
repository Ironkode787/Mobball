# SPEC — Audio synthesis pipeline (audio workstream)

Owner lane: `tools/audiogen/`, `assets/audio/`, `game/audio/`. Design context:
`docs/08-AUDIO.md`. **Strategy change vs. that doc: we compose and synthesize everything
ourselves** — no downloaded samples anywhere. Every sound ships from
`tools/audiogen/generate.py` (Python 3.11, numpy/scipy/soundfile available; no ffmpeg).
We own the copyright on every byte of audio.

## 1. Generator contract

- `python3 tools/audiogen/generate.py [--only sfx|music] [--out assets/audio]`
- Deterministic: fixed RNG seed; running twice produces identical files.
- SFX → `assets/audio/sfx/<event>.wav` (44.1 kHz, 16-bit PCM, mono).
- Music → `assets/audio/music/city1/<stem>.ogg` (44.1 kHz, Vorbis ~q0.6, stereo).
- Every file peak-normalized to −1.5 dBFS max, DC-removed, fade-safe ends (≤ 3 ms ramps,
  except designed loops which must be click-free seamless).
- Prints a manifest (name, duration, peak dB, RMS) and writes it to
  `assets/audio/MANIFEST.txt`. Generated audio IS committed to the repo.
- Structure the code as a small library: `synth.py` (oscillators, noise, envelopes, filters
  via scipy.signal, Karplus-Strong, FM operators, formant/wah filter, reverb via cheap
  Schroeder), `sfx.py` (one function per event), `music.py` (sequencer + instruments),
  `theory.py` (note→freq, swing timing), `generate.py` (CLI).

## 2. Quality bar (this is the part that matters)

No raw test-tone oscillators. Physical events use **exciter → resonator** construction
(filtered noise/impulse into 2–4 tuned resonant modes with distinct decays). Pitched
instruments need: envelope curvature, vibrato/tremolo where idiomatic, velocity variation,
and a touch of room (short Schroeder reverb, pre-delay ~12 ms, wet ≤ 18%). Listen-test by
rendering; iterate until nothing sounds like a sine beep. Slight per-render random detune
(±4 cents, seeded) inside chords to de-sterilize.

## 3. Music — city 1 stem stack ("Eastport '72")

Fixed musical spec (composed by design — implement exactly, voice tastefully):

- 92 BPM, swing (off-beat eighths at 2/3 position), key D minor, 8-bar loop, 4/4.
- **All stems exactly the same length**: `N = round(44100 * 32 * 60 / 92)` frames, seamless
  loops (crossfade-free: compose to the bar, ring out into loop start via wraparound render).
- Chords (2 beats per symbol = half-bar): bars 1–2 `Dm6`, 3–4 `Gm7`, 5 `Bb7`, 6 `A7`,
  7 `Dm6`, 8 `A7` (turnaround).

Stems (filename → content):

| stem | instrument (synthesis) | material |
|------|------------------------|----------|
| `01_bass.ogg` | upright bass — Karplus-Strong, lowpassed, soft thump attack | walking quarters: D2 F2 A2 B2 · D3 C3 B2 A2 · G2 Bb2 D3 E3 · G2 F2 E2 D2 · Bb2 D3 F3 Ab3 · A2 C#3 E3 G3 · D3 A2 F2 E2 · A2 G2 F2 E2 |
| `02_drums.ogg` | brush kit — kick: sine drop; snare/brush: shaped noise; ride: metallic partials + noise | swing ride on 1, 2, 2a, 3, 4, 4a; cross-stick 2 & 4; soft kick 1 & 3; continuous circular brush bed at −20 dB |
| `03_vibes.ogg` | vibraphone — FM (ratio 4.0 + slight inharmonic), tremolo 5.5 Hz | comp chords on beat 2 and the "and" of 4, voicings: Dm6 = D4 F4 A4 B4, Gm7 = G3 Bb3 D4 F4, Bb7 = Bb3 D4 F4 Ab4, A7 = A3 C#4 E4 G4 |
| `04_trumpet.ogg` | muted trumpet — saw + comb + slow bandpass "wah" sweep on held notes, vibrato late | melody (beat, dur): b3 D4·1, b4 F4·.5 G4·.5 — b5 A4·2(wah) b7.5 G4·.5 b8 F4·1 — b9 G4·1.5 F4·.5 G4·1 Bb4·1 — b13 A4·.5 G4·.5 F4·1 D4·2 — b17 F4·1 Ab4·1 G4·.5 F4·.5 D4·1 — b21 E4·1.5 C#4·.5 E4·1 G4·1 — b25 A4·2(wah) F4·1 E4·.5 D4·.5 — b29 D4·1 C#4·1 A3·2 |
| `05_organ.ogg` | drawbar organ — additive 16'+8'+4'+2⅔', rotary am/fm ~5.7 Hz | whole-bar pads of each chord (low-mid voicing), plus a staccato stab on the "and of 4" of bars 2/4/6 |
| `06_barisax.ogg` | bari sax — saw + breath noise + 2 formants | 1-bar riff transposed to each half-bar chord root: root·1 on b1, rest, root·.5 on b2.5, b3·.5 on b3, fifth·1 on b4 (octave 2) |
| `07_strings.ogg` | ensemble — 5 detuned saws, slow attack (400 ms), chorus | long tones: D5 (bars 1–2), F5 (3–4), F5→E5 (5–6), A4 (7), E5 resolving D5 (8), swelling mp→mf |
| `08_full.ogg` | brass section (3-saw stack + formant) + timpani (tuned drum) + choir "ah" (formant synth) | tutti stabs beat 1 of bars 1/3/5/6/7 on the current chord, timpani D roll through bar 8, choir pad bars 7–8 |

Rough loudness ladder: each stem mixed to sit together at −14 LUFS-ish combined; bass/drums
foundation, later stems additive sparkle. Ship a `99_preview_full.ogg` (all stems summed) for
listening checks — not loaded by the game.

## 4. SFX event vocabulary (v1 — the AudioDirector contract)

`flipper_up` `flipper_down` `bumper_hit` `sling_hit` `plunger_pull` `plunger_launch`
`ball_spawn` `drain` `nudge_thump` `tilt_warning` `tilt` `knocker` `cash_tick`
`chime_a` `chime_b` `chime_c` `wall_tap`

Character notes: flipper = solenoid clack + bat body knock (two-mode resonator), up harder
than down; bumper = ringing pop with springy 180 Hz mode + skin slap; drain = hollow grate
thud + short low rumble; tilt_warning = single desk bell; tilt = bell + sad power-down
(descending detuned pair, 700 ms); knocker = the classic replay THWACK (hard impulse into
wood box modes) — biggest transient in the set; cash_tick = tiny mechanical counter click
(used per-$ tick at high rate, so ≤ 40 ms, gentle); chimes = Gottlieb-style plated bar
chimes, three pitches (D5, F5, A5, inharmonic bell partials).

## 5. game/audio/audio_director.gd (upgrade in place)

Keep the public API, extend it:

- `play(event, opts={})` — opts: `pitch_jitter` (default 0.05 → random_pitch via
  ±cents), `volume_db`, `bus`. Pool `AudioStreamPlayer`s (cap 24 voices, steal oldest).
- Buses: create at runtime if absent: `Music`, `Mechanics`, `Fiction`, `UI` under Master
  (AudioServer API) and route: mechanical events → Mechanics, chimes/knocker/cash → Fiction.
- Music: `music_start()`, `music_set_level(level: int)` — level 0–7 = how many stems are
  audible; implement with one `AudioStreamSynchronized` (all 8 stems, sample-locked) and
  per-layer volume fades (1.5 s). `music_stop()`. Missing stem files → fail silent.
- Everything must work headless (no audible output in CI is fine; code paths must not error).

## 6. Acceptance

- `python3 tools/audiogen/generate.py` runs clean in ≤ ~120 s, writes all §3 + §4 files +
  manifest; loops verified seamless (assert first/last 64 samples continuity vs wraparound
  render, not silence-padded).
- A `tests/test_audio_assets.gd` that asserts: every §4 event has a WAV on disk, every §3
  stem OGG exists, and all stems load with identical length in frames (via AudioStreamOggVorbis
  length within 1 ms tolerance).
- `bash tools/check.sh` green. Boot smoke must show zero "[audio] no asset yet" lines for §4
  events fired by the M0 table (coordinate: those events are exactly the ones in
  `specs/m0-feel.md`).
- Report (final message): rough LUFS/peak per stem, total assets size (keep < 12 MB), and
  three things you'd improve with more time.
