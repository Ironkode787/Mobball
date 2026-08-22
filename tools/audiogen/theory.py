"""Musical constants and timing for "Eastport '72" (city 1).

The composition is fixed by specs/audio-pipeline.md §3; this module owns the numbers
(tempo, swing grid, chord voicings, note names) so music.py can stay about *tone*.
"""

from __future__ import annotations

import math

SR = 44100
BPM = 92.0
BEATS_PER_BAR = 4
BARS = 8
TOTAL_BEATS = BARS * BEATS_PER_BAR                 # 32
SEC_PER_BEAT = 60.0 / BPM
SEC_PER_BAR = SEC_PER_BEAT * BEATS_PER_BAR

# Every stem is exactly this long. Spec §3: N = round(44100 * 32 * 60 / 92).
LOOP_FRAMES = int(round(SR * TOTAL_BEATS * 60.0 / BPM))   # 920348
LOOP_SECONDS = LOOP_FRAMES / SR

# Off-beat eighths land at 2/3 of the beat.
SWING = 2.0 / 3.0

# How far past the loop end we keep rendering before wrapping the tail onto the head.
TAIL_SECONDS = 4.0

_PITCH_CLASS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note_to_midi(name: str) -> int:
	"""'D2' -> 38, 'Bb3' -> 58, 'C#4' -> 61."""
	name = name.strip()
	pc = _PITCH_CLASS[name[0].upper()]
	i = 1
	while i < len(name) and name[i] in "#b":
		pc += 1 if name[i] == "#" else -1
		i += 1
	return (int(name[i:]) + 1) * 12 + pc


def midi_to_freq(midi: float) -> float:
	return 440.0 * (2.0 ** ((midi - 69.0) / 12.0))


def freq(name: str, cents: float = 0.0) -> float:
	return midi_to_freq(note_to_midi(name) + cents / 100.0)


def transpose(name: str, semitones: int) -> float:
	return midi_to_freq(note_to_midi(name) + semitones)


def cents_between(f_got: float, f_want: float) -> float:
	if f_got <= 0.0 or f_want <= 0.0:
		return float("inf")
	return 1200.0 * math.log2(f_got / f_want)


def swing_position(frac: float) -> float:
	"""Warp a within-beat fraction onto the swing grid (0 -> 0, .5 -> 2/3, 1 -> 1)."""
	if frac < 0.5:
		return frac * (SWING / 0.5)
	return SWING + (frac - 0.5) * ((1.0 - SWING) / 0.5)


def beat_time(beat: float) -> float:
	"""Seconds from loop start for a 1-based global beat number (b1 = 0.0 s)."""
	b = beat - 1.0
	whole = math.floor(b)
	return (whole + swing_position(b - whole)) * SEC_PER_BEAT


def beat_sample(beat: float) -> int:
	return int(round(beat_time(beat) * SR))


def beat_span(beat: float, dur_beats: float) -> tuple[int, int]:
	"""(start_sample, length_samples) for a note, swing applied at both ends."""
	start = beat_sample(beat)
	end = beat_sample(beat + dur_beats)
	return start, max(1, end - start)


def bar_beat(bar: int, beat_in_bar: float) -> float:
	"""1-based bar + 1-based beat -> global 1-based beat."""
	return (bar - 1) * BEATS_PER_BAR + beat_in_bar


# --------------------------------------------------------------------- harmony

# Spec §3: bars 1-2 Dm6, 3-4 Gm7, 5 Bb7, 6 A7, 7 Dm6, 8 A7 (turnaround).
CHORD_BY_BAR = ["Dm6", "Dm6", "Gm7", "Gm7", "Bb7", "A7", "Dm6", "A7"]

# Comping voicings, exactly as specified.
VOICINGS = {
	"Dm6": ["D4", "F4", "A4", "B4"],
	"Gm7": ["G3", "Bb3", "D4", "F4"],
	"Bb7": ["Bb3", "D4", "F4", "Ab4"],
	"A7": ["A3", "C#4", "E4", "G4"],
}

ROOT_OF = {"Dm6": "D", "Gm7": "G", "Bb7": "Bb", "A7": "A"}

# Semitones above the root used by the bari-sax riff (root, b3, fifth).
RIFF_DEGREES = {"root": 0, "b3": 3, "fifth": 7}


def chord_of_bar(bar: int) -> str:
	return CHORD_BY_BAR[(bar - 1) % BARS]


def voicing_of_bar(bar: int) -> list[str]:
	return VOICINGS[chord_of_bar(bar)]


def root_note(bar: int, octave: int) -> str:
	return f"{ROOT_OF[chord_of_bar(bar)]}{octave}"


# ------------------------------------------------------------------- the parts

# §3 bass: walking quarters, one line per bar.
BASS_LINE = [
	["D2", "F2", "A2", "B2"],
	["D3", "C3", "B2", "A2"],
	["G2", "Bb2", "D3", "E3"],
	["G2", "F2", "E2", "D2"],
	["Bb2", "D3", "F3", "Ab3"],
	["A2", "C#3", "E3", "G3"],
	["D3", "A2", "F2", "E2"],
	["A2", "G2", "F2", "E2"],
]

# §3 trumpet melody as (global beat, note, duration in beats, wah).
TRUMPET_LINE = [
	(3.0, "D4", 1.0, False),
	(4.0, "F4", 0.5, False),
	(4.5, "G4", 0.5, False),
	(5.0, "A4", 2.0, True),
	(7.5, "G4", 0.5, False),
	(8.0, "F4", 1.0, False),
	(9.0, "G4", 1.5, False),
	(10.5, "F4", 0.5, False),
	(11.0, "G4", 1.0, False),
	(12.0, "Bb4", 1.0, False),
	(13.0, "A4", 0.5, False),
	(13.5, "G4", 0.5, False),
	(14.0, "F4", 1.0, False),
	(15.0, "D4", 2.0, False),
	(17.0, "F4", 1.0, False),
	(18.0, "Ab4", 1.0, False),
	(19.0, "G4", 0.5, False),
	(19.5, "F4", 0.5, False),
	(20.0, "D4", 1.0, False),
	(21.0, "E4", 1.5, False),
	(22.5, "C#4", 0.5, False),
	(23.0, "E4", 1.0, False),
	(24.0, "G4", 1.0, False),
	(25.0, "A4", 2.0, True),
	(27.0, "F4", 1.0, False),
	(28.0, "E4", 0.5, False),
	(28.5, "D4", 0.5, False),
	(29.0, "D4", 1.0, False),
	(30.0, "C#4", 1.0, False),
	(31.0, "A3", 2.0, False),   # rings across the loop point into bar 1
]

# §3 strings: (global beat, note, duration in beats, velocity 0..1) — mp swelling to mf.
STRING_LINE = [
	(1.0, "D5", 8.0, 0.55),
	(9.0, "F5", 8.0, 0.62),
	(17.0, "F5", 4.0, 0.70),
	(21.0, "E5", 4.0, 0.74),
	(25.0, "A4", 4.0, 0.80),
	(29.0, "E5", 2.0, 0.86),
	(31.0, "D5", 2.0, 0.78),   # resolves, and rings into the D5 that opens the loop
]

STEM_NAMES = [
	"01_bass",
	"02_drums",
	"03_vibes",
	"04_trumpet",
	"05_organ",
	"06_barisax",
	"07_strings",
	"08_full",
]
