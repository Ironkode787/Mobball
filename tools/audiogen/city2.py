"""The city-2 stem stack — "New Carthage '27".

docs/08 §7: same system, new arrangement. Eight slots in the same order, the same two
state layers on top, the same wraparound rendering and the same loudness ladder as
city 1 — but a hot jazz combo playing a different tune, in a different key, at a
different tempo, off a wax record.

What carries over is the player's audio literacy: slot 1 is still the thing that walks,
slot 2 is still the thing that keeps time, slot 4 is still the voice that plays the tune,
slot 8 is still everybody at once. What changes is who is holding the instruments:

    01  tuba, two-beat            (an upright bass has not been invented for this band)
    02  trap kit: woodblock, press-rolled snare, Chinese crash
    03  banjo, four chunks to the bar
    04  cornet with a plunger
    05  stride piano
    06  clarinet obbligato
    07  tailgate trombones
    08  the whole front line, stop-time
    09  tense: tremolo banjo over a tuba pedal
    10  raid kit, halftime
    11  the Victrola itself — surface noise, and the thump of the eccentric once a turn

Slot 11 is the one structural addition, and it is city-2 only: a bed that plays whenever
anything plays, because the *record* is not one of the instruments and does not stop when
they do. `AudioDirector` treats it as a bed rather than as a level stem.

Two things about the medium, both of which are the arrangement rather than an effect:

**The horn.** An acoustically-recorded 1927 side has no microphone in it. Everything went
down a horn onto wax, which passes roughly 180 Hz to 3.5 kHz and rings at a few
frequencies of its own. That filter is applied per stem, before the loop fold, and it is
linear and time-invariant, so the fold stays exact (music.py, §wraparound).

**The wow.** A 78 turns 1.3 times a second and never quite evenly. That would normally be
a time-varying delay — which is *not* time-invariant, and folding after one would smear
the seam — so instead the speed variation is baked into each note at synthesis time from
one global curve with a whole number of cycles per loop. A note that rings past the last
bar reads the curve past the loop end, where it is exactly the curve at the head: the
fold is still exact, and the whole band wows together the way one turntable makes it.
The voices written here take the curve *inside* the note and wobble; the cornet borrows
city 1's muted-trumpet voice, which is built around a fixed frequency, so it takes the
curve's average over the note instead — which is most of what wow does to a melody
anyway: every note lands a few cents from where it was played.
"""

from __future__ import annotations

import numpy as np

from . import music
from . import theory as th
from .music import _level_to, _place, piano_note
from .synth import (
	SR, add_at, asr_env, bandpass, bl_pulse, bl_saw, blend, circular_bandpass, dc_remove,
	exp_decay, expline, fold_tail, formants, highpass, karplus_strong, lowpass, modal,
	n_of, noise, perc_env, phase_of, rng, stereo_room, t_axis, unit, widen,
)

# ------------------------------------------------------------------------- grid

BPM = 104.0
BARS = 8
BEATS_PER_BAR = 4
TOTAL_BEATS = BARS * BEATS_PER_BAR
SEC_PER_BEAT = 60.0 / BPM
LOOP_FRAMES = int(round(SR * TOTAL_BEATS * 60.0 / BPM))       # 814154
LOOP_SECONDS = LOOP_FRAMES / SR

# Hot jazz swings, but it swings stiffer than 1972 does: 0.60 rather than 2/3. The
# difference is small on paper and is most of what makes 1927 sound like 1927.
SWING = 0.60
TAIL_SECONDS = 4.0

N = LOOP_FRAMES
TAIL = n_of(TAIL_SECONDS)
TOTAL = N + TAIL

CITY_DIR = "city2"


def swing_position(frac: float) -> float:
	if frac < 0.5:
		return frac * (SWING / 0.5)
	return SWING + (frac - 0.5) * ((1.0 - SWING) / 0.5)


def beat_time(beat: float) -> float:
	b = beat - 1.0
	whole = float(np.floor(b))
	return (whole + swing_position(b - whole)) * SEC_PER_BEAT


def beat_sample(beat: float) -> int:
	return int(round(beat_time(beat) * SR))


def beat_span(beat: float, dur_beats: float) -> tuple[int, int]:
	start = beat_sample(beat)
	return start, max(1, beat_sample(beat + dur_beats) - start)


def bar_beat(bar: int, beat_in_bar: float) -> float:
	return (bar - 1) * BEATS_PER_BAR + beat_in_bar


def _buf() -> np.ndarray:
	return np.zeros(TOTAL)


def _detune(gen: np.random.Generator, spread: float = 4.0) -> float:
	return float(gen.uniform(-spread, spread))


def place(left: np.ndarray, right: np.ndarray, mono: np.ndarray, start: int,
          gain: float = 1.0, position: float = 0.0) -> None:
	"""city-1's `_place`, bound to this city's loop length."""
	_place(left, right, mono, start, gain, position, loop_n=N)


# ---------------------------------------------------------------------- harmony

# The same shape as city 1's eight bars (i - iv - VI7 - V - i - V), a fourth up and a
# tone quicker: the player who learned "the turnaround is bar 8" keeps that for free.
CHORD_BY_BAR = ["Gm6", "Gm6", "Cm7", "Cm7", "Eb7", "D7", "Gm6", "D7"]

# All four voicings live between G3 and Eb4 so the comping never jumps registers — a
# banjo player moves two fingers between these, which is exactly the point.
VOICINGS = {
	"Gm6": ["G3", "Bb3", "D4", "E4"],
	"Cm7": ["G3", "Bb3", "C4", "Eb4"],
	"Eb7": ["G3", "Bb3", "Db4", "Eb4"],
	"D7": ["F#3", "A3", "C4", "D4"],
}
ROOT_OF = {"Gm6": "G", "Cm7": "C", "Eb7": "Eb", "D7": "D"}


def chord_of_bar(bar: int) -> str:
	return CHORD_BY_BAR[(bar - 1) % BARS]


def voicing_of_bar(bar: int) -> list[str]:
	return VOICINGS[chord_of_bar(bar)]


# ------------------------------------------------------------------- the medium

# 78 rpm is 1.3 revolutions a second; over one loop that is a whole number of turns only
# if we make it one, so it is made one.
WOW_TURNS = max(1, int(round(1.30 * LOOP_SECONDS)))
WOW_CENTS = 6.5


def wow(start: int, n: int) -> np.ndarray:
	"""The turntable's speed, as a frequency multiplier, for `n` samples from `start`.

	Periodic over the loop by construction, so a note folded back onto the head carries
	the wow the head actually has.
	"""
	i = np.arange(start, start + n, dtype=np.float64)
	curve = (0.75 * np.sin(2.0 * np.pi * WOW_TURNS * i / N)
	         + 0.25 * np.sin(2.0 * np.pi * 3.0 * WOW_TURNS * i / N + 1.1))
	return 2.0 ** ((WOW_CENTS / 1200.0) * curve)


def horn(x: np.ndarray, presence: float = 1.0, low_hz: float = 175.0) -> np.ndarray:
	"""The recording horn: a band, three resonances and a little wax compression.

	Linear and time-invariant apart from the tanh, which is memoryless — so both are
	safe on either side of the loop fold.

	`low_hz` is 175 for everything except the two stems that carry the bottom of the mix
	(the tuba and the raid kit), which get 120. A wax side really did stop at about 175 Hz
	and a literal corner there leaves a phone speaker with nothing at all to move: this is
	the one place in the city where the device wins over the era.
	"""
	y = highpass(x, low_hz, order=2)
	y = lowpass(y, 3500.0, order=4)
	y = y + presence * 0.55 * formants(y, [(680.0, 3.0, 1.00), (1850.0, 4.0, 0.70),
	                                       (2800.0, 5.0, 0.40)])
	peak = float(np.max(np.abs(y))) + 1e-12
	return np.tanh(y * (0.9 / peak)) * peak


def _finish_stem(left: np.ndarray, right: np.ndarray, presence: float = 1.0,
                 wet: float = 0.14, rt60: float = 0.85, predelay: float = 0.014,
                 damp_hz: float = 4200.0,
                 low_hz: float = 175.0) -> tuple[np.ndarray, np.ndarray]:
	"""Room, then the horn. Every stem in the city ends here."""
	left, right = stereo_room(left, right, wet=wet, rt60=rt60, predelay=predelay,
	                          damp_hz=damp_hz)
	return horn(left, presence, low_hz), horn(right, presence, low_hz)


# ------------------------------------------------------------------ instruments


def tuba_note(f: float, n: int, velocity: float, gen: np.random.Generator,
              start: int = 0) -> np.ndarray:
	"""Bass tuba: a wide conical bore, so the fundamental is enormous and the top is not.

	The "pah" of the tongue at the front and the fall-away at the back are what separate
	a tuba from an organ pedal; the note also blooms slightly as the player gets air into
	it, which is the reason the envelope has an attack at all.
	"""
	freq = f * wow(start, n)
	tone = bl_saw(freq, cap=24) + 0.55 * np.sin(phase_of(freq))
	voiced = formants(tone, [(210.0, 2.2, 1.00), (520.0, 2.8, 0.42), (980.0, 3.4, 0.16)])
	voiced = lowpass(voiced + 0.5 * tone, 1400.0, order=2)
	breath = lowpass(noise(n, gen), 900.0, order=2) * perc_env(n, 0.004, 0.045, 1.2)
	env = asr_env(n, 0.030, 0.090, 1.6)
	bloom = 1.0 - 0.20 * np.exp(-t_axis(n) / 0.075)
	return unit(blend(voiced, breath, 0.10) * env * bloom, velocity)


def banjo_note(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Four-string banjo: a steel string over a drum head, which is why it has no sustain.

	Karplus-Strong with a hard pick and heavy damping gets the string; the head is a
	membrane bolted to the same bridge, so it is mixed in as a resonator rather than
	added as a sample. A banjo that rings for a second is a guitar.
	"""
	k = max(3, n_of(0.0016))
	exc = np.zeros(n)
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = bandpass(exc, 900.0, 9000.0, order=2)
	exc[:4] += 0.6 * np.sin(np.linspace(0.0, np.pi, 4))          # the pick itself
	exc *= velocity / (float(np.max(np.abs(exc))) + 1e-12)
	string = karplus_strong(f, n, exc, t60=0.42, damping=0.28)
	head = modal(string, [(312.0, 0.030, 0.30), (486.0, 0.020, 0.22), (742.0, 0.014, 0.14)])
	out = blend(string, head, 0.45)
	return unit(out * asr_env(n, 0.0008, 0.035, 2.0), velocity)


def clarinet_note(f: float, n: int, velocity: float, gen: np.random.Generator,
                  start: int = 0) -> np.ndarray:
	"""B-flat clarinet: a cylindrical pipe stopped at one end, so the even harmonics are
	almost missing — that hollow woody sound is a square wave's spectrum, not a saw's.

	The reed squeaks a little into the attack and the player's vibrato arrives late and
	stays narrow; a wide vibrato here would be a saxophone wearing a clarinet's coat.
	"""
	t = t_axis(n)
	dur = n / SR
	vib_amt = np.clip((t - min(0.30, dur * 0.5)) / max(dur, 1e-3), 0.0, 1.0)
	vib = 1.0 + 0.0042 * vib_amt * np.sin(2.0 * np.pi * 5.1 * t)
	freq = f * vib * wow(start, n)
	tone = bl_pulse(freq, n, duty=0.5, cap=30)                   # odd harmonics only
	voiced = formants(tone, [(1180.0, 2.6, 1.00), (2450.0, 3.6, 0.34)]) + 0.55 * tone
	voiced = lowpass(voiced, 3800.0, order=2)
	reed = bandpass(noise(n, gen), 1800.0, 6000.0, order=2) * (0.25 + np.exp(-t / 0.030))
	env = asr_env(n, 0.024, 0.065, 1.5)
	return unit(blend(voiced, reed, 0.08) * env, velocity)


def trombone_note(f_from: float, f_to: float, n: int, velocity: float,
                  gen: np.random.Generator, start: int = 0,
                  smear: float = 0.35) -> np.ndarray:
	"""Tailgate trombone: the slide goes where it is going and the note follows it.

	`smear` is the fraction of the note spent arriving. A trombone is the only brass that
	can do this and 1927 asks it to do almost nothing else.
	"""
	glide = min(max(n_of(smear * n / SR), 2), n)
	freq = np.full(n, f_to)
	freq[:glide] = expline(glide, f_from, f_to)
	freq = freq * wow(start, n)
	tone = bl_saw(freq, cap=30)
	voiced = formants(tone, [(520.0, 2.4, 1.00), (1180.0, 3.0, 0.55), (2100.0, 4.0, 0.20)])
	voiced = lowpass(voiced + 0.45 * tone, 3000.0, order=2)
	blat = 1.0 + 0.30 * np.exp(-t_axis(n) / 0.045)
	return unit(voiced * asr_env(n, 0.045, 0.120, 1.4) * blat, velocity)


def woodblock(n: int, gen: np.random.Generator, f0: float = 1180.0,
              velocity: float = 1.0) -> np.ndarray:
	"""A hollow block of rosewood hit with a stick. Almost no decay, all attack."""
	exc = np.zeros(n)
	k = max(3, n_of(0.0007))
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = bandpass(exc, 800.0, 11000.0, order=2)
	exc[:5] += 0.8 * np.sin(np.linspace(0.0, np.pi, 5))
	return unit(modal(exc, [
		(f0, 0.0130, 0.85),
		(f0 * 1.62, 0.0080, 0.55),
		(f0 * 2.71, 0.0044, 0.34),
		(f0 * 4.30, 0.0022, 0.16),
		(268.0, 0.0180, 0.22),                                   # the shell it sits in
	]), velocity)


def press_roll(n: int, gen: np.random.Generator, hits: int = 11,
               velocity: float = 1.0) -> np.ndarray:
	"""A snare press roll: many buzzed taps, accelerating, into an accent.

	1927's kit had no ride cymbal to speak of — time was kept on a woodblock and the
	snare filled the corners, so the roll does the work the brushes do in city 1.
	"""
	out = np.zeros(n)
	at = 0.0
	gap = 0.055
	for i in range(hits):
		tap = music._raid_snare(n_of(0.16), gen, 0.30 + 0.55 * (i / max(hits - 1, 1)))
		add_at(out, tap, n_of(at), 0.55)
		at += gap
		gap *= 0.94
	add_at(out, music._raid_snare(n_of(0.34), gen, 1.0), n_of(at), 1.0)
	return unit(out, velocity)


def crash(n: int, gen: np.random.Generator, velocity: float = 1.0) -> np.ndarray:
	"""A Chinese crash: a cymbal with a turned-up edge, so it is trashy and short."""
	metal = music._ride(n, gen, bell=0.0)
	return unit(metal * exp_decay(n, 0.32) * asr_env(n, 0.0006, 0.05, 2.0), velocity)


# ------------------------------------------------------------------- the parts

# 01 — tuba, two beats to the bar: root, then the fifth. (bar, beat, note, dur, vel)
TUBA_LINE = [
	(1, 1.0, "G2", 1.5, 1.00), (1, 3.0, "D2", 1.5, 0.88),
	(2, 1.0, "G2", 1.5, 0.96), (2, 3.0, "D3", 1.5, 0.84),
	(3, 1.0, "C2", 1.5, 1.00), (3, 3.0, "G2", 1.5, 0.88),
	(4, 1.0, "C2", 1.5, 0.96), (4, 3.0, "Eb2", 1.0, 0.86), (4, 4.5, "F2", 0.5, 0.70),
	(5, 1.0, "Eb2", 1.5, 1.00), (5, 3.0, "Bb2", 1.5, 0.88),
	(6, 1.0, "D2", 1.5, 1.00), (6, 3.0, "A2", 1.5, 0.88),
	(7, 1.0, "G2", 1.5, 1.00), (7, 3.0, "D2", 1.5, 0.88),
	(8, 1.0, "D2", 1.5, 0.96), (8, 3.0, "A2", 1.0, 0.86), (8, 4.5, "F#2", 0.5, 0.72),
]

# 04 — the cornet has the tune. (bar, beat, note, dur, wah)
CORNET_LINE = [
	(1, 1.0, "D4", 1.5, False), (1, 2.5, "F4", 0.5, False),
	(1, 3.0, "G4", 1.0, False), (1, 4.0, "Bb4", 1.0, False),
	(2, 1.0, "A4", 1.5, True), (2, 2.5, "G4", 0.5, False), (2, 3.0, "F4", 2.0, False),
	(3, 1.0, "Eb4", 1.0, False), (3, 2.0, "G4", 1.0, False), (3, 3.0, "C5", 2.0, True),
	(4, 1.0, "Bb4", 1.5, False), (4, 2.5, "G4", 0.5, False),
	(4, 3.0, "Eb4", 1.0, False), (4, 4.0, "F4", 1.0, False),
	(5, 1.0, "G4", 2.0, True), (5, 3.0, "Db5", 1.0, False), (5, 4.0, "Bb4", 1.0, False),
	(6, 1.0, "A4", 1.0, False), (6, 2.0, "F#4", 1.0, False),
	(6, 3.0, "D4", 1.5, False), (6, 4.5, "C5", 0.5, False),
	(7, 1.0, "Bb4", 2.0, True), (7, 3.0, "G4", 1.0, False), (7, 4.0, "D4", 1.0, False),
	(8, 1.0, "F#4", 1.0, False), (8, 2.0, "A4", 1.0, False),
	(8, 3.0, "C5", 1.0, False), (8, 4.0, "A4", 1.0, False),
]

# 06 — the clarinet weaves above it. (bar, beat, note, dur)
CLARINET_LINE = [
	(1, 2.0, "D5", 0.5), (1, 2.5, "F5", 0.5), (1, 3.0, "G5", 1.0), (1, 4.5, "F5", 0.5),
	(2, 1.0, "D5", 1.0), (2, 2.5, "Bb4", 0.5), (2, 3.0, "A4", 1.5),
	(3, 2.0, "G5", 0.5), (3, 2.5, "Eb5", 0.5), (3, 3.0, "C5", 1.0), (3, 4.0, "Bb4", 1.0),
	(4, 1.0, "G4", 1.0), (4, 2.5, "C5", 0.5), (4, 3.0, "Eb5", 2.0),
	(5, 1.5, "Db5", 0.5), (5, 2.0, "Bb4", 1.0), (5, 3.0, "G5", 1.0), (5, 4.0, "F5", 1.0),
	(6, 1.0, "D5", 1.0), (6, 2.5, "C5", 0.5), (6, 3.0, "A4", 1.0), (6, 4.0, "F#4", 1.0),
	(7, 2.0, "G5", 0.5), (7, 2.5, "D5", 0.5), (7, 3.0, "Bb4", 2.0),
	(8, 1.0, "A4", 1.0), (8, 2.0, "C5", 1.0), (8, 3.0, "D5", 2.0),
]

# 07 — tailgate: where the slide starts, where it lands, how long it takes.
# (bar, beat, from, to, dur, vel, smear)
TROMBONE_LINE = [
	(1, 3.0, "D3", "G3", 2.0, 0.80, 0.30),
	(2, 3.0, "G3", "Bb3", 2.0, 0.72, 0.28),
	(3, 1.0, "G3", "C3", 2.0, 0.82, 0.34),
	(4, 3.0, "C3", "Eb3", 2.0, 0.74, 0.30),
	(5, 1.0, "Bb2", "Eb3", 2.5, 0.86, 0.36),
	(6, 1.0, "A2", "D3", 2.5, 0.86, 0.36),
	(7, 1.0, "D3", "G3", 2.5, 0.80, 0.32),
	(8, 3.0, "A2", "F#3", 1.5, 0.90, 0.55),                      # the turnaround smear
]

# 08 — stop-time: everybody hits, everybody stops. (beat-in-bar, velocity)
TUTTI_HITS = [(1.0, 1.00), (2.5, 0.82), (4.0, 0.90)]


# ------------------------------------------------------------------- the stems


def stem_tuba() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("c2_tuba")
	left, right = _buf(), _buf()
	for bar, beat, name, dur, vel in TUBA_LINE:
		start, length = beat_span(bar_beat(bar, beat), dur * 0.86)
		n = length + n_of(0.22)
		f = th.freq(name, _detune(gen, 2.5))
		at = start + int(gen.integers(-70, 70))
		place(left, right, tuba_note(f, n, vel, gen, at), at, 1.0, -0.04)
	return _finish_stem(left, right, presence=0.7, wet=0.10, rt60=0.70, damp_hz=3000.0,
	                    low_hz=120.0)


def stem_kit() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("c2_kit")
	left, right = _buf(), _buf()
	block_n = n_of(0.20)
	kick_n = n_of(0.32)
	for bar in range(1, BARS + 1):
		for beat, vel in ((1.0, 1.00), (2.0, 0.72), (3.0, 0.88), (4.0, 0.70)):
			at = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-90, 90))
			place(left, right, woodblock(block_n, gen, 1180.0, vel), at, 0.50, 0.22)
		# the "and" of 2 and 4, softer and higher: the second block on the rail
		for beat in (2.5, 4.5):
			at = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-70, 70))
			place(left, right, woodblock(block_n, gen, 1620.0, 0.42), at, 0.34, 0.34)
		for beat in (1.0, 3.0):
			at = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-50, 50))
			place(left, right, music._kick(kick_n, gen), at,
			      0.80 if beat == 1.0 else 0.62, 0.0)
		if bar in (4, 8):
			at = beat_sample(bar_beat(bar, 3.0)) + int(gen.integers(-60, 60))
			place(left, right, press_roll(n_of(1.20), gen, 11, 0.9), at, 0.44, -0.16)
		if bar in (1, 5):
			at = beat_sample(bar_beat(bar, 1.0))
			place(left, right, crash(n_of(1.10), gen, 0.85), at, 0.36, -0.28)
	return _finish_stem(left, right, presence=1.0, wet=0.13, rt60=0.80, damp_hz=5200.0)


def stem_banjo() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("c2_banjo")
	left, right = _buf(), _buf()
	ring = n_of(0.52)
	for bar in range(1, BARS + 1):
		voicing = voicing_of_bar(bar)
		# Four to the bar, plus a lift on the "and" of 4 every other bar. The lift is
		# what a banjo player does to push into the next bar, and it is also what keeps
		# the loop point ringing: bar 8's lands a swung eighth before the seam, so the
		# head of the loop opens on a chord that is already sounding.
		chunks = [(1.0, 0.92), (2.0, 1.00), (3.0, 0.88), (4.0, 1.00)]
		if bar % 2 == 0:
			chunks.append((4.5, 0.68))
		for beat, vel in chunks:
			base = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-60, 60))
			up = beat in (2.0, 4.0, 4.5)
			for i, name in enumerate(voicing):
				# down-strokes run low to high, up-strokes high to low: that alternation
				# is the whole rhythmic engine of a four-string banjo.
				order = (len(voicing) - 1 - i) if up else i
				f = th.freq(voicing[order], _detune(gen, 5.0))
				at = base + n_of(0.0075 * i)
				place(left, right, banjo_note(f, ring, vel * (1.0 - 0.05 * i), gen),
				      at, 0.40, -0.22 + 0.14 * order)
	return _finish_stem(left, right, presence=1.0, wet=0.12, rt60=0.72, damp_hz=4800.0)


def stem_cornet() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("c2_cornet")
	left, right = _buf(), _buf()
	for i, (bar, beat, name, dur, wah) in enumerate(CORNET_LINE):
		start, length = beat_span(bar_beat(bar, beat), dur * 0.92)
		n = length + n_of(0.16)
		f = th.freq(name, _detune(gen, 3.0)) * float(np.mean(wow(start, n)))
		vel = 0.82 + 0.18 * (0.5 + 0.5 * np.sin(i * 0.8))
		at = start + int(gen.integers(-110, 110))
		place(left, right, music._trumpet_note(f, n, vel, wah, gen), at, 0.44, 0.06)
	return _finish_stem(left, right, presence=1.1, wet=0.15, rt60=0.90, damp_hz=4400.0)


def stem_stride() -> tuple[np.ndarray, np.ndarray]:
	"""Stride piano: the left hand walks the bass and the chords answer on 2 and 4.

	This is the comping slot, and stride is what comping *was* in 1927 — the piano is
	the rhythm section's other half, not a soloist.
	"""
	gen = rng("c2_stride")
	left, right = _buf(), _buf()
	for bar in range(1, BARS + 1):
		voicing = voicing_of_bar(bar)
		root = ROOT_OF[chord_of_bar(bar)]
		for beat, name in ((1.0, f"{root}2"), (3.0, f"{root}3")):
			start, length = beat_span(bar_beat(bar, beat), 0.9)
			n = length + n_of(1.1)
			f = th.freq(name, _detune(gen, 2.0))
			at = start + int(gen.integers(-120, 120))
			place(left, right, piano_note(f, n, 0.78, gen), at, 0.55, -0.30)
		for beat in (2.0, 4.0):
			start, length = beat_span(bar_beat(bar, beat), 0.8)
			n = length + n_of(0.8)
			lean = int(gen.integers(-90, 90))
			for i, name in enumerate(voicing):
				f = th.freq(name, _detune(gen, 2.5))
				place(left, right, piano_note(f, n, 0.60 - 0.04 * i, gen),
				      start + lean + n_of(0.008 * i), 0.42, 0.10 + 0.10 * i)
	return _finish_stem(left, right, presence=0.9, wet=0.16, rt60=0.95, damp_hz=4000.0)


def stem_clarinet() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("c2_clarinet")
	left, right = _buf(), _buf()
	for bar, beat, name, dur in CLARINET_LINE:
		start, length = beat_span(bar_beat(bar, beat), dur * 0.90)
		n = length + n_of(0.14)
		f = th.freq(name, _detune(gen, 3.0))
		at = start + int(gen.integers(-90, 90))
		place(left, right, clarinet_note(f, n, 0.86, gen, at), at, 0.40, -0.24)
	return _finish_stem(left, right, presence=1.1, wet=0.16, rt60=0.95, damp_hz=4600.0)


def stem_trombones() -> tuple[np.ndarray, np.ndarray]:
	"""Two trombones a sixth apart, smearing into everything they land on."""
	gen = rng("c2_trombones")
	left, right = _buf(), _buf()
	for bar, beat, f_from, f_to, dur, vel, smear in TROMBONE_LINE:
		start, length = beat_span(bar_beat(bar, beat), dur * 0.92)
		n = length + n_of(0.20)
		at = start + int(gen.integers(-100, 100))
		lo_from = th.freq(f_from, _detune(gen, 3.0))
		lo_to = th.freq(f_to, _detune(gen, 3.0))
		place(left, right, trombone_note(lo_from, lo_to, n, vel, gen, at, smear),
		      at, 0.46, -0.18)
		# the second chair, a sixth up and a hair behind
		place(left, right, trombone_note(lo_from * 1.6818, lo_to * 1.6818, n,
		                                 vel * 0.72, gen, at, smear),
		      at + n_of(0.014), 0.34, 0.20)
	return _finish_stem(left, right, presence=0.9, wet=0.18, rt60=1.05, damp_hz=3800.0)


def stem_tutti() -> tuple[np.ndarray, np.ndarray]:
	"""Everybody, stop-time: three hits a bar and silence in between.

	The city-1 slot 8 is a full band *plus* a choir — more of everything. Nineteen
	twenty-seven does the same job by taking things away between the hits, which is
	louder than playing through.
	"""
	gen = rng("c2_tutti")
	left, right = _buf(), _buf()
	for bar in range(1, BARS + 1):
		voicing = voicing_of_bar(bar)
		root = ROOT_OF[chord_of_bar(bar)]
		for beat, vel in TUTTI_HITS:
			start, length = beat_span(bar_beat(bar, beat), 0.55)
			n = length + n_of(0.30)
			lean = int(gen.integers(-60, 60))
			at = start + lean
			place(left, right, tuba_note(th.freq(f"{root}2", _detune(gen, 2.5)), n,
			                             vel, gen, at), at, 0.62, 0.0)
			for i, name in enumerate(voicing):
				f = th.freq(name, _detune(gen, 4.0))
				place(left, right, music._brass_note(f, n, vel * (0.92 - 0.05 * i), gen),
				      at + n_of(0.006 * i), 0.30, -0.34 + 0.22 * i)
			top = th.freq(voicing[-1], _detune(gen, 4.0)) * 2.0
			place(left, right, clarinet_note(top, n, vel * 0.72, gen, at), at, 0.26, 0.30)
			place(left, right, music._kick(n_of(0.34), gen), at, 0.70, 0.0)
			place(left, right, crash(n_of(0.75), gen, vel * 0.55), at, 0.22, -0.26)
	return _finish_stem(left, right, presence=1.0, wet=0.15, rt60=0.90, damp_hz=4600.0)


def stem_tense() -> tuple[np.ndarray, np.ndarray]:
	"""Heat, 1927: a tremolo banjo over a tuba pedal, and the block counting.

	Same job as city 1's ostinato — sit under the band and refuse to resolve — with the
	same trick: the pedal is the tonic and the tremolo is a minor second above the
	fifth, so it grinds against every chord in the loop without ever leaving the key.
	"""
	gen = rng("c2_tense")
	left, right = _buf(), _buf()
	ring = n_of(0.30)
	for bar in range(1, BARS + 1):
		start, length = beat_span(bar_beat(bar, 1.0), 4.0)
		n = length + n_of(0.6)
		at = start
		place(left, right, tuba_note(th.freq("G1", _detune(gen, 2.0)), n, 0.62, gen, at),
		      at, 0.55, 0.0)
		for step in range(16):
			beat = 1.0 + 0.25 * step
			tat = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-40, 40))
			name = "Eb4" if (step % 4) < 2 else "D4"
			f = th.freq(name, _detune(gen, 6.0))
			place(left, right, banjo_note(f, ring, 0.30 + 0.10 * (step % 2 == 0), gen),
			      tat, 0.30, 0.26 if step % 2 else -0.26)
		for beat in (1.0, 2.0, 3.0, 4.0):
			tat = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-40, 40))
			place(left, right, woodblock(n_of(0.16), gen, 940.0, 0.55), tat, 0.30, 0.0)
	return _finish_stem(left, right, presence=0.8, wet=0.17, rt60=1.00, damp_hz=3800.0)


def stem_raid_kit() -> tuple[np.ndarray, np.ndarray]:
	"""The raid kit, at this city's tempo: halftime, hard beater, open snare."""
	gen = rng("c2_raid_kit")
	left, right = _buf(), _buf()
	kick_n = n_of(0.70)
	snare_n = n_of(1.10)
	tom_n = n_of(0.55)
	for bar in range(1, BARS + 1):
		fill = bar in (4, 8)
		for beat, vel in ((1.0, 1.00), (3.0, 0.92)):
			at = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-50, 50))
			place(left, right, music._big_kick(kick_n, gen, vel), at, 0.90, 0.0)
		if not fill:
			at = beat_sample(bar_beat(bar, 4.5)) + int(gen.integers(-50, 50))
			place(left, right, music._big_kick(kick_n, gen, 0.62), at, 0.60, 0.0)
		at = beat_sample(bar_beat(bar, 3.0)) + int(gen.integers(-60, 60))
		place(left, right, music._raid_snare(snare_n, gen, 1.0), at, 0.62, -0.10)
		pattern = ([(1.5, "hi", 0.55), (2.5, "mid", 0.60), (4.0, "lo", 0.70)] if not fill
		           else [(3.5, "hi", 0.70), (3.75, "hi", 0.62), (4.0, "mid", 0.80),
		                 (4.5, "lo", 0.90)])
		for beat, voice, vel in pattern:
			at = beat_sample(bar_beat(bar, beat)) + int(gen.integers(-70, 70))
			place(left, right, music._tom(music.TOM_HZ[voice], tom_n, gen, vel), at,
			      0.46, music.TOM_PAN[voice])
	left, right = widen(left, right, 0.18)
	return _finish_stem(left, right, presence=1.0, wet=0.15, rt60=1.05, damp_hz=6000.0,
	                    low_hz=120.0)


def stem_crackle() -> tuple[np.ndarray, np.ndarray]:
	"""The record itself: surface noise, the eccentric thumping once a turn, and dust.

	City-2 only, and not a level stem — it plays whenever anything plays, because the
	record does not stop turning when the clarinet stops playing. Everything in it is
	built circularly (FFT-domain filtering, an integer number of turns per loop) so it
	is exactly periodic: this bed is audible for hours and a seam in it would be the
	most obvious fault in the game.
	"""
	gen = rng("c2_crackle")
	left = np.zeros(TOTAL)
	right = np.zeros(TOTAL)
	turns = np.arange(N, dtype=np.float64) * (2.0 * np.pi * WOW_TURNS / N)
	for channel, buf in ((0, left), (1, right)):
		hiss = circular_bandpass(noise(N, rng(f"c2_hiss_{channel}")), 900.0, 6500.0, slope=1.4)
		hiss /= float(np.std(hiss)) + 1e-12
		# the groove is not the same all the way round: once a turn it is a little louder
		buf[:N] += hiss * (0.55 + 0.20 * np.sin(turns + channel * 0.7)) * 0.30
		rumble = circular_bandpass(noise(N, rng(f"c2_rumble_{channel}")), 28.0, 190.0, slope=1.6)
		rumble /= float(np.std(rumble)) + 1e-12
		buf[:N] += rumble * 0.55
	# dust: sharp little ticks, one lot on every turn so the pattern comes back round
	tick_n = n_of(0.020)
	for turn in range(WOW_TURNS):
		base = int(turn * N / WOW_TURNS)
		for _ in range(3):
			at = base + int(gen.integers(0, N // WOW_TURNS))
			f0 = float(gen.uniform(1400.0, 5200.0))
			tick = unit(modal(np.concatenate([[1.0], np.zeros(tick_n - 1)]),
			                  [(f0, 0.0022, 0.8), (f0 * 2.3, 0.0011, 0.4)]))
			gain = float(gen.uniform(0.10, 0.55))
			place(left, right, tick, at % N, gain, float(gen.uniform(-0.5, 0.5)))
	# the eccentric: one soft thump per revolution, dead centre
	thump_n = n_of(0.09)
	for turn in range(WOW_TURNS):
		at = int(turn * N / WOW_TURNS)
		thump = np.sin(phase_of(expline(thump_n, 62.0, 38.0))) * perc_env(thump_n, 0.004, 0.022, 1.1)
		place(left, right, unit(thump), at, 0.30, 0.0)
	# No horn on the bed: the surface noise IS the horn's output, not something recorded
	# through it. Filtering it again would make it a hiss played on a gramophone.
	return highpass(left, 24.0, 2), highpass(right, 24.0, 2)


# ================================================================== the stack

STEMS = {
	"01_bass": stem_tuba,
	"02_drums": stem_kit,
	"03_vibes": stem_banjo,
	"04_trumpet": stem_cornet,
	"05_organ": stem_stride,
	"06_barisax": stem_clarinet,
	"07_strings": stem_trombones,
	"08_full": stem_tutti,
	"09_tense": stem_tense,
	"10_raid_drums": stem_raid_kit,
	"11_crackle": stem_crackle,
}

STEM_NAMES = ["01_bass", "02_drums", "03_vibes", "04_trumpet",
              "05_organ", "06_barisax", "07_strings", "08_full"]
STATE_STEM_NAMES = ["09_tense", "10_raid_drums"]
BED_STEM_NAME = "11_crackle"
SYNCED_STEM_NAMES = STEM_NAMES + STATE_STEM_NAMES + [BED_STEM_NAME]

# The same ladder city 1 uses, for the same reason: the stack has to stay legible as it
# grows. The bed is far below all of it — a record you can hear over the band is a fault.
STEM_LUFS = {
	"01_bass": -20.5,
	"02_drums": -20.0,
	"03_vibes": -25.5,
	"04_trumpet": -23.0,
	"05_organ": -26.5,
	"06_barisax": -25.0,
	"07_strings": -26.5,
	"08_full": -23.0,
	"09_tense": -24.0,
	"10_raid_drums": -19.0,
	"11_crackle": -33.0,
}


def render_stem(name: str) -> np.ndarray:
	"""Render one city-2 stem to an (N, 2) array, loop-folded and level-matched."""
	left, right = STEMS[name]()
	assert len(left) == TOTAL and len(right) == TOTAL, "stem rendered at the wrong length"
	left = dc_remove(left, 24.0)
	right = dc_remove(right, 24.0)
	stereo = np.stack([fold_tail(left, N), fold_tail(right, N)], axis=1)
	assert stereo.shape[0] == N, "fold produced the wrong frame count"
	return _level_to(stereo, STEM_LUFS[name])
