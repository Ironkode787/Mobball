"""The city-1 stem stack — "Eastport '72".

Eight instruments, one 8-bar loop, 92 BPM swung D minor. The composition is fixed by
specs/audio-pipeline.md §3; everything here is about *voicing* it.

Two structural ideas run through the whole file:

**Wraparound rendering.** Every stem is rendered into a buffer that runs four seconds
past the last bar, and the overhang is then folded back onto the head
(:func:`synth.fold_tail`). A cymbal struck on the last beat, the trumpet's final A3, the
reverb tail — all of it reappears at bar 1 exactly as it would if the loop were really
playing twice. Periodic summation commutes with the linear processing applied before it,
so the result is identical to an infinite render. That is why these loops need no
crossfade and have no seam.

**Periodic modulation.** Tremolo and rotary rates are snapped to an integer number of
cycles per loop (5.5 Hz becomes 5.5105 Hz), so the modulators are periodic too. An
un-snapped LFO would put a phase jump at the loop point that no amount of careful
note-placement could hide.
"""

from __future__ import annotations

import math

import numpy as np

from . import theory as th
from .synth import (
	SR, add_at, asr_env, bandpass, bl_pulse, bl_saw, blend, chorus, circular_bandpass,
	comb_ff, db2lin, dc_remove, exp_decay, expline, fm, fold_tail, formants, highpass,
	karplus_strong, lowpass, modal, n_of, noise, pan, perc_env, phase_of, rng,
	smoothstep, soft_limit, stereo_room, sweep_filter, t_axis, unit, widen,
)

N = th.LOOP_FRAMES
TAIL = n_of(th.TAIL_SECONDS)
TOTAL = N + TAIL

# Integrated-loudness ladder (LUFS). Bass and drums are the floor of the mix; every
# stem above them is additive sparkle, so the stack stays legible as it grows and lands
# near -14 LUFS when all eight are up.
STEM_LUFS = {
	"01_bass": -20.5,
	"02_drums": -20.0,
	"03_vibes": -25.5,
	"04_trumpet": -23.0,
	"05_organ": -26.5,
	"06_barisax": -25.0,
	"07_strings": -26.5,
	"08_full": -23.0,
	# Wave 2. The ostinato is quieter than anything it plays under (spec §2: "sits UNDER
	# the band") but has to still carry a raid, where it is one of only three things
	# left; the raid kit replaces the brushes and is the loudest thing in the stack.
	"09_tense": -24.0,
	"10_raid_drums": -19.0,
}

# The Count's piano is not in the synchronized stack and never plays with the band, so
# it is levelled as a solo instrument rather than as a layer.
COUNT_PIANO_LUFS = -21.5

PEAK_CEILING_DB = -1.5


# ------------------------------------------------------------------ scaffolding


def _buf() -> np.ndarray:
	return np.zeros(TOTAL)


def periodic_lfo(target_hz: float, phase: float = 0.0, n: int = TOTAL) -> np.ndarray:
	"""A sine LFO snapped to an integer cycle count per loop, so it is loop-periodic."""
	cycles = max(1, int(round(target_hz * th.LOOP_SECONDS)))
	w = 2.0 * np.pi * cycles / N
	return np.sin(w * np.arange(n) + phase)


def _place(left: np.ndarray, right: np.ndarray, mono: np.ndarray, start: int,
           gain: float = 1.0, position: float = 0.0, loop_n: int = N) -> None:
	"""Mix a note into the stereo pair, panned.

	A note whose humanised timing lands *before* bar 1 belongs to the end of the loop,
	not to sample 0: placing it at ``start + loop_n`` lets it ring past the loop end and
	fold back onto the head, which is where it would be if the loop were really playing.
	Just clipping it to zero instead leaves the head starting mid-attack — a step at
	sample 0 that reads as a click on every repeat.
	"""
	if start < 0:
		start += loop_n
	l, r = pan(mono, position)
	add_at(left, l, start, gain)
	add_at(right, r, start, gain)


def _detune(gen: np.random.Generator, spread: float = 4.0) -> float:
	"""±spread cents, seeded. De-sterilises chords without breaking determinism."""
	return float(gen.uniform(-spread, spread))


# ==================================================================== 01 — bass


def bass_note(freq: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Upright bass: Karplus-Strong string, soft thump transient, body resonance."""
	# Pluck: a short, dark noise burst — flesh on a thick gut string, not a pick.
	k = n_of(0.0075)
	exc = np.zeros(n)
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = lowpass(exc, 1350.0, order=2)
	# Plucking position: a notch where the finger is, about a quarter along the string.
	exc = comb_ff(exc, (1.0 / freq) * 0.24, -0.8)
	exc *= velocity / (float(np.max(np.abs(exc))) + 1e-12)

	t60 = float(np.interp(freq, [60.0, 110.0, 220.0], [1.35, 1.15, 0.85]))
	damp = float(np.interp(freq, [60.0, 110.0, 220.0], [0.62, 0.56, 0.46]))
	string = karplus_strong(freq, n, exc, t60=t60, damping=damp)

	# The body: a big wooden box with a couple of strong low modes. Driven by the held
	# string rather than a strike, so it is mixed by relative level, not mode gain.
	body = modal(string, [(103.0, 0.085, 0.30), (147.0, 0.065, 0.22), (196.0, 0.045, 0.14)])
	out = blend(string, body, 0.38)
	# Thump: the string slapping toward the fingerboard on release.
	tk = min(n_of(0.09), n)
	thump = np.zeros(n)
	thump[:tk] = np.sin(phase_of(expline(tk, freq * 1.9, freq * 0.98))) * exp_decay(tk, 0.022)
	out = blend(out, thump, 0.30)
	out = lowpass(out, 3200.0, order=2)
	return unit(out * asr_env(n, 0.001, 0.055, 2.0), velocity)


def stem_bass() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_bass")
	left, right = _buf(), _buf()
	ring = n_of(1.35)
	for bar in range(1, th.BARS + 1):
		for beat in range(4):
			name = th.BASS_LINE[bar - 1][beat]
			f = th.freq(name, _detune(gen, 2.5))
			# Walking bass breathes: 1 and 3 lean in, 2 and 4 hang back a hair.
			vel = [1.0, 0.86, 0.94, 0.88][beat] * (1.0 + 0.05 * np.sin(bar * 1.7))
			start = th.beat_sample(th.bar_beat(bar, beat + 1)) + int(gen.integers(-90, 90))
			_place(left, right, bass_note(f, ring, vel, gen), start, 1.0, -0.05)
	left, right = stereo_room(left, right, wet=0.09, rt60=0.7, predelay=0.014, damp_hz=3600.0)
	return highpass(left, 30.0, 2), highpass(right, 30.0, 2)


# =================================================================== 02 — drums


def _ride(n: int, gen: np.random.Generator, bell: float = 0.0) -> np.ndarray:
	"""Ride cymbal: inharmonic metal modes plus a bandpassed shimmer."""
	exc = np.zeros(n)
	k = n_of(0.0006)
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = bandpass(exc, 1800.0, 13000.0, order=2)
	ratios = [1.00, 1.47, 2.09, 2.81, 3.63, 4.55, 5.71, 7.02, 8.65]
	taus = [0.95, 0.80, 0.66, 0.52, 0.40, 0.30, 0.22, 0.16, 0.11]
	gains = [0.55, 0.48, 0.42, 0.38, 0.32, 0.26, 0.21, 0.16, 0.12]
	f0 = 428.0
	metal = modal(exc, [(f0 * r, tau, g) for r, tau, g in zip(ratios, taus, gains)])
	shimmer = bandpass(noise(n, gen), 3600.0, 11000.0, order=2) * perc_env(n, 0.0008, 0.16, 1.0)
	out = blend(metal, shimmer, 0.5)
	if bell > 0.0:
		out = blend(out, modal(exc, [(1180.0, 1.1, 0.5), (2360.0, 0.7, 0.3),
		                             (3460.0, 0.45, 0.2)]), bell)
	return unit(out * asr_env(n, 0.0005, 0.02, 2.0))


def _cross_stick(n: int, gen: np.random.Generator) -> np.ndarray:
	"""Stick laid on the head, shaft cracked against the rim."""
	exc = np.zeros(n)
	k = n_of(0.0008)
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = bandpass(exc, 700.0, 9000.0, order=2)
	exc[:6] += 0.7 * np.sin(np.linspace(0.0, np.pi, 6))
	return unit(modal(exc, [
		(418.0, 0.050, 0.70),
		(892.0, 0.028, 0.45),
		(1725.0, 0.018, 0.85),
		(2570.0, 0.010, 0.45),
		(3820.0, 0.006, 0.22),
	]))


def _kick(n: int, gen: np.random.Generator) -> np.ndarray:
	"""Soft jazz kick — felt beater, tuned high, no click to speak of."""
	drop = n_of(0.07)
	f = np.full(n, 46.0)
	f[:drop] = expline(drop, 118.0, 46.0)
	body = np.sin(phase_of(f)) * perc_env(n, 0.0015, 0.075, 1.0)
	beater = lowpass(noise(n, gen), 1400.0, order=2) * perc_env(n, 0.0004, 0.006, 1.6)
	return unit(blend(body, beater, 0.22))


def _brush_bed(gen: np.random.Generator, channel: int) -> np.ndarray:
	"""The circular brush wash. FFT-filtered so it is *exactly* loop-periodic — a
	time-domain filter would leave a step at the seam that no fold can fix."""
	bed = circular_bandpass(noise(N, gen), 1250.0, 6800.0, slope=1.6)
	bed /= float(np.std(bed)) + 1e-12
	t = np.arange(N)
	# two swirls per bar, plus a second harmonic so the circle isn't a pure sine
	swirl = (0.50 * np.sin(2.0 * np.pi * 16.0 * t / N + channel * 0.9)
	         + 0.18 * np.sin(2.0 * np.pi * 32.0 * t / N + 1.3 + channel * 0.5))
	return bed * (0.55 + 0.45 * (0.5 + 0.5 * swirl))


def stem_drums() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_drums")
	left, right = _buf(), _buf()
	ride_n = n_of(1.1)
	stick_n = n_of(0.28)
	kick_n = n_of(0.34)

	for bar in range(1, th.BARS + 1):
		# swing ride: 1, 2, 2a, 3, 4, 4a — the "a"s are the swung eighths
		for beat, vel, bell in [(1.0, 1.00, 0.22), (2.0, 0.74, 0.0), (2.5, 0.55, 0.0),
		                        (3.0, 0.86, 0.0), (4.0, 0.74, 0.0), (4.5, 0.58, 0.0)]:
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-110, 110))
			swing_lift = 1.06 if beat in (2.5, 4.5) else 1.0
			_place(left, right, _ride(ride_n, gen, bell), start,
			       vel * swing_lift * 0.50, 0.26)
		for beat in (2.0, 4.0):
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-70, 70))
			vel = 0.9 if beat == 2.0 else 0.82
			_place(left, right, _cross_stick(stick_n, gen), start, vel * 0.46, -0.18)
		for beat in (1.0, 3.0):
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-60, 60))
			vel = 0.85 if beat == 1.0 else 0.66
			_place(left, right, _kick(kick_n, gen), start, vel * 0.85, 0.0)

	# Brush bed 20 dB under the kit's peak: a continuous wash sitting a dozen dB under
	# the sticks, which is what a pair of brushes on a coated head actually sounds like.
	bed_l = _brush_bed(rng("brush_l"), 0)
	bed_r = _brush_bed(rng("brush_r"), 1)
	kit_peak = float(np.max(np.abs(left[:N])))
	bed_gain = kit_peak * db2lin(-20.0) / (float(np.max(np.abs(bed_l))) + 1e-12)
	left[:N] += bed_l * bed_gain
	right[:N] += bed_r * bed_gain

	left, right = stereo_room(left, right, wet=0.13, rt60=0.85, predelay=0.012, damp_hz=7200.0)
	return highpass(left, 32.0, 2), highpass(right, 32.0, 2)


# =================================================================== 03 — vibes


def _vibe_note(f: float, n: int, velocity: float) -> np.ndarray:
	"""FM vibraphone: ratio 4 with a slightly inharmonic partner, bar ring on top."""
	index = 2.4 * exp_decay(n, 0.085) + 0.15
	tone = fm(f, n, 4.0, index)
	tone += 0.32 * fm(f * 1.0009, n, 4.03, index * 0.75)
	tone += 0.20 * np.sin(phase_of(f * 4.0, n)) * exp_decay(n, 0.42)
	tone += 0.10 * np.sin(phase_of(f * 9.2, n)) * exp_decay(n, 0.14)
	env = perc_env(n, 0.0025, 0.62, 1.0) * asr_env(n, 0.001, 0.08, 2.0)
	return unit(tone * env, velocity)


def stem_vibes() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_vibes")
	left, right = _buf(), _buf()
	ring = n_of(1.7)
	for bar in range(1, th.BARS + 1):
		voicing = th.voicing_of_bar(bar)
		for beat, vel, spread in [(2.0, 0.92, 0.010), (4.5, 0.62, 0.006)]:
			base = th.beat_sample(th.bar_beat(bar, beat))
			for i, name in enumerate(voicing):
				f = th.freq(name, _detune(gen, 4.0))
				# a little roll across the voicing, low note first, spread across the field
				start = base + n_of(spread * i) + int(gen.integers(-40, 40))
				position = -0.30 + 0.20 * i
				_place(left, right, _vibe_note(f, ring, vel * (1.0 - 0.06 * i)),
				       start, 0.5, position)

	# motor tremolo: one modulator for the whole instrument, snapped to the loop
	trem = 1.0 - 0.42 * (0.5 + 0.5 * periodic_lfo(5.5))
	left *= trem
	right *= 1.0 - 0.42 * (0.5 + 0.5 * periodic_lfo(5.5, phase=0.35))
	left, right = stereo_room(left, right, wet=0.17, rt60=1.05, predelay=0.014, damp_hz=6800.0)
	return highpass(left, 60.0, 2), highpass(right, 60.0, 2)


# ================================================================= 04 — trumpet


def _trumpet_note(f: float, n: int, velocity: float, wah: bool,
                  gen: np.random.Generator) -> np.ndarray:
	"""Muted trumpet: saw through the mute's comb and formants, vibrato arriving late."""
	t = t_axis(n)
	dur = n / SR
	# vibrato only after the note has settled — the tell of a real player
	vib_delay = min(0.28, dur * 0.42)
	vib_amt = np.clip((t - vib_delay) / max(dur - vib_delay, 1e-3), 0.0, 1.0) ** 1.5
	vib = 1.0 + (22.0 / 1200.0) * np.log(2.0) * vib_amt * np.sin(2.0 * np.pi * 5.4 * t)
	# the attack scoops up into the note
	scoop = np.ones(n)
	sk = min(n, n_of(0.035))
	scoop[:sk] = np.linspace(2.0 ** (-38.0 / 1200.0), 1.0, sk)
	freq = f * vib * scoop

	tone = bl_saw(freq, cap=40)
	tone = highpass(tone, f * 0.85, order=2)
	tone = comb_ff(tone, 1.0 / 640.0, 0.55)            # cup of the mute
	voiced = formants(tone, [(1880.0, 3.4, 1.00), (920.0, 2.4, 0.60), (3320.0, 4.0, 0.22)])
	if wah:
		# slow bandpass sweep: open, peak, close
		half = n // 2
		centre = np.concatenate([expline(half, 520.0, 2250.0),
		                         expline(n - half, 2250.0, 760.0)])
		voiced = 0.45 * voiced + 1.15 * sweep_filter(tone, centre, q=3.2, kind="bp")
	env = asr_env(n, 0.042, 0.075, 1.6) * (1.0 - 0.06 * np.sin(2.0 * np.pi * 5.4 * t))
	air = bandpass(noise(n, gen), 2200.0, 6500.0, order=2) * env
	blip = 1.0 + 0.35 * np.exp(-t / 0.02)              # the pip of the tongue
	return unit(blend(voiced, air, 0.10) * env * blip, velocity)


def stem_trumpet() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_trumpet")
	left, right = _buf(), _buf()
	for i, (beat, name, dur, wah) in enumerate(th.TRUMPET_LINE):
		start, length = th.beat_span(beat, dur)
		n = length + n_of(0.16)
		f = th.freq(name, _detune(gen, 3.0))
		vel = 0.80 + 0.20 * (0.5 + 0.5 * np.sin(i * 0.9))
		if dur >= 1.5:
			vel *= 1.06
		_place(left, right, _trumpet_note(f, n, vel, wah, gen),
		       start + int(gen.integers(-120, 120)), 0.42, 0.04)
	left, right = stereo_room(left, right, wet=0.16, rt60=0.95, predelay=0.013, damp_hz=5200.0)
	return highpass(left, 90.0, 2), highpass(right, 90.0, 2)


# =================================================================== 05 — organ


def _organ_voice(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Drawbars 16' 8' 4' 2-2/3' plus the key click of a real contact."""
	# 16' 8' 4' 2-2/3'. The 16' is deliberately restrained: at this voicing it sits
	# right on top of the upright bass and turns the low mid to mud if you draw it out.
	drawbars = [(0.5, 0.45), (1.0, 1.00), (2.0, 0.72), (3.0, 0.48)]
	out = np.zeros(n)
	for ratio, gain in drawbars:
		out += gain * np.sin(phase_of(f * ratio, n, phase0=float(gen.uniform(0, 6.28))))
	click = np.zeros(n)
	ck = min(n, n_of(0.004))
	click[:ck] = noise(ck, gen) * np.exp(-np.linspace(0.0, 5.0, ck))
	return unit(blend(out, click, 0.18), velocity)


def stem_organ() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_organ")
	left, right = _buf(), _buf()
	for bar in range(1, th.BARS + 1):
		# low-mid voicing: the comping chord dropped an octave so it sits under the vibes
		voicing = [f"{name[:-1]}{int(name[-1]) - 1}" for name in th.voicing_of_bar(bar)]
		start, length = th.beat_span(th.bar_beat(bar, 1.0), 3.85)
		n = length + n_of(0.12)
		for i, name in enumerate(voicing):
			f = th.freq(name, _detune(gen, 3.5))
			voice = _organ_voice(f, n, 0.9 - 0.05 * i, gen) * asr_env(n, 0.018, 0.10, 1.4)
			_place(left, right, voice, start, 0.34, -0.35 + 0.24 * i)
		if bar in (2, 4, 6):
			s2, l2 = th.beat_span(th.bar_beat(bar, 4.5), 0.4)
			n2 = l2 + n_of(0.05)
			for i, name in enumerate(voicing):
				f = th.freq(name, _detune(gen, 3.5))
				stab = _organ_voice(f, n2, 1.0, gen) * asr_env(n2, 0.006, 0.045, 1.2)
				_place(left, right, stab, s2, 0.40, -0.30 + 0.20 * i)

	# Leslie: amplitude and a touch of pitch, opposite phase on the two channels
	rot = periodic_lfo(5.7)
	rot_q = periodic_lfo(5.7, phase=np.pi / 2.0)
	left *= 1.0 + 0.26 * rot
	right *= 1.0 - 0.26 * rot
	doppler = 1.0 + 0.0035 * rot_q
	idx = np.clip(np.cumsum(doppler), 0, TOTAL - 1.001)
	base = np.arange(TOTAL, dtype=np.float64)
	left = np.interp(idx, base, left)
	right = np.interp(np.clip(np.cumsum(2.0 - doppler), 0, TOTAL - 1.001), base, right)

	left, right = stereo_room(left, right, wet=0.15, rt60=1.0, predelay=0.015, damp_hz=5600.0)
	return highpass(left, 95.0, 2), highpass(right, 95.0, 2)


# ================================================================= 06 — barisax


def _sax_note(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Bari sax: saw body, two formants, and enough breath to hear the reed."""
	t = t_axis(n)
	dur = n / SR
	vib_amt = np.clip((t - min(0.22, dur * 0.5)) / max(dur, 1e-3), 0.0, 1.0)
	vib = 1.0 + 0.006 * vib_amt * np.sin(2.0 * np.pi * 4.8 * t)
	scoop = np.ones(n)
	sk = min(n, n_of(0.045))
	scoop[:sk] = np.linspace(2.0 ** (-45.0 / 1200.0), 1.0, sk)
	tone = bl_saw(f * vib * scoop, cap=56)
	tone = lowpass(tone, 2600.0, order=2)
	voiced = formants(tone, [(470.0, 3.0, 1.00), (1180.0, 4.0, 0.62)]) + 0.35 * tone
	breath = bandpass(noise(n, gen), 1400.0, 5200.0, order=2)
	breath *= 0.4 + 1.0 * np.exp(-t / 0.035)
	growl = 1.0 + 0.07 * np.sin(2.0 * np.pi * 31.0 * t)
	env = asr_env(n, 0.028, 0.075, 1.5)
	return unit(blend(voiced, breath, 0.12) * env * growl, velocity)


def stem_barisax() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_barisax")
	left, right = _buf(), _buf()
	# one-bar riff, transposed to each bar's chord root, octave 2
	riff = [(1.0, "root", 1.0, 1.00), (2.5, "root", 0.5, 0.78),
	        (3.0, "b3", 0.5, 0.84), (4.0, "fifth", 1.0, 0.92)]
	for bar in range(1, th.BARS + 1):
		root = th.root_note(bar, 2)
		for beat, degree, dur, vel in riff:
			f = th.transpose(root, th.RIFF_DEGREES[degree]) * 2.0 ** (_detune(gen, 3.0) / 1200.0)
			start, length = th.beat_span(th.bar_beat(bar, beat), dur * 0.92)
			n = length + n_of(0.10)
			_place(left, right, _sax_note(f, n, vel, gen),
			       start + int(gen.integers(-100, 100)), 0.5, -0.28)
	left, right = stereo_room(left, right, wet=0.13, rt60=0.85, predelay=0.013, damp_hz=4600.0)
	return highpass(left, 45.0, 2), highpass(right, 45.0, 2)


# ================================================================= 07 — strings


def stem_strings() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_strings")
	left, right = _buf(), _buf()
	desks = [-11.0, -5.5, 0.0, 5.5, 11.0]
	positions = [-0.55, -0.28, 0.0, 0.28, 0.55]
	for beat, name, dur, vel in th.STRING_LINE:
		start, length = th.beat_span(beat, dur)
		n = length + n_of(0.55)
		for cents, position in zip(desks, positions):
			f = th.freq(name, cents + _detune(gen, 4.0))
			saw = bl_saw(f * (1.0 + 0.0012 * np.sin(2.0 * np.pi * float(gen.uniform(4.0, 5.6))
			                                        * t_axis(n) + float(gen.uniform(0, 6.28)))),
			             cap=30)
			env = np.ones(n)
			a = min(n, n_of(0.40))
			env[:a] = smoothstep(a)
			r = min(n - a, n_of(0.50))
			if r > 1:
				env[n - r:] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, r))) ** 1.4
			# the bow digs in as the section swells
			bright = expline(n, 1700.0, 3400.0)
			voice = sweep_filter(saw, bright, q=0.75, kind="lp") * env
			_place(left, right, voice, start, vel * 0.16, position)
		# a quiet octave below for weight, centre
		f_sub = th.freq(name, _detune(gen, 3.0)) * 0.5
		sub = bl_saw(np.full(n, f_sub), cap=24)
		env = np.ones(n)
		a = min(n, n_of(0.45))
		env[:a] = smoothstep(a)
		r = min(n - a, n_of(0.5))
		env[n - r:] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, r))) ** 1.4
		_place(left, right, lowpass(sub, 1400.0, order=2) * env, start, vel * 0.055, 0.0)

	left = chorus(left, rng("chorus_l"), voices=3, base_ms=15.0, depth_ms=2.6, rate=0.29, mix=0.42)
	right = chorus(right, rng("chorus_r"), voices=3, base_ms=18.0, depth_ms=2.9, rate=0.34, mix=0.42)
	left, right = widen(left, right, 0.30)
	left, right = stereo_room(left, right, wet=0.20, rt60=1.35, predelay=0.018, damp_hz=4800.0)
	return highpass(left, 70.0, 2), highpass(right, 70.0, 2)


# ==================================================================== 08 — full


def _brass_note(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Three detuned saws through a brass formant, with a rip into the attack."""
	t = t_axis(n)
	rip = np.ones(n)
	rk = min(n, n_of(0.028))
	rip[:rk] = np.linspace(2.0 ** (-70.0 / 1200.0), 1.0, rk)
	out = np.zeros(n)
	for cents in (-7.0, 0.0, 7.0):
		out += bl_saw(f * rip * (2.0 ** ((cents + _detune(gen, 3.0)) / 1200.0)), n, cap=34)
	out /= 3.0
	voiced = formants(out, [(1250.0, 2.6, 1.00), (2400.0, 3.4, 0.45), (620.0, 2.2, 0.40)])
	voiced += 0.4 * out
	env = asr_env(n, 0.026, 0.12, 1.5)
	bite = 1.0 + 0.5 * np.exp(-t / 0.03)
	return unit(voiced * env * bite, velocity)


def _timpani(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	exc = np.zeros(n)
	k = n_of(0.004)
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = lowpass(exc, 900.0, order=2)
	ratios = [1.00, 1.504, 1.742, 2.00, 2.30, 2.66]
	taus = [0.70, 0.50, 0.38, 0.28, 0.20, 0.14]
	gains = [1.00, 0.60, 0.42, 0.30, 0.20, 0.12]
	drum = modal(exc, [(f * r, tau, g) for r, tau, g in zip(ratios, taus, gains)])
	head = lowpass(noise(n, gen), 700.0, order=2) * perc_env(n, 0.001, 0.030, 1.4)
	return unit(blend(drum, head, 0.20) * asr_env(n, 0.001, 0.05, 2.0), velocity)


def _choir_note(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Choir "ah": two detuned voices through /a/ formants, breath on top."""
	t = t_axis(n)
	dur = n / SR
	vib_amt = np.clip((t - min(0.45, dur * 0.4)) / max(dur, 1e-3), 0.0, 1.0)
	out = np.zeros(n)
	for cents in (-9.0, 9.0):
		vib = 1.0 + 0.0045 * vib_amt * np.sin(2.0 * np.pi * 5.0 * t + float(gen.uniform(0, 6.28)))
		out += bl_pulse(f * vib * (2.0 ** ((cents + _detune(gen, 4.0)) / 1200.0)), n, duty=0.42, cap=28)
	out /= 2.0
	voiced = formants(out, [(730.0, 8.0, 1.00), (1090.0, 9.0, 0.72),
	                        (2440.0, 11.0, 0.30), (3400.0, 12.0, 0.16)])
	breath = bandpass(noise(n, gen), 2000.0, 7000.0, order=2) * 0.03
	env = np.ones(n)
	a = min(n, n_of(0.35))
	env[:a] = smoothstep(a)
	r = min(n - a, n_of(0.45))
	env[n - r:] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, r))) ** 1.3
	return unit(blend(voiced, breath * env, 0.10) * env, velocity)


def stem_full() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_full")
	left, right = _buf(), _buf()

	# tutti brass stabs, beat 1 of bars 1/3/5/6/7
	for bar in (1, 3, 5, 6, 7):
		start, length = th.beat_span(th.bar_beat(bar, 1.0), 0.62)
		n = length + n_of(0.18)
		voicing = th.voicing_of_bar(bar)
		for i, name in enumerate(voicing):
			f = th.freq(name, _detune(gen, 3.0))
			_place(left, right, _brass_note(f, n, 0.95 - 0.05 * i, gen),
			       start + int(gen.integers(-70, 70)), 0.52, -0.5 + 0.33 * i)
		# root an octave down, centred, for the floor of the stab
		_place(left, right, _brass_note(th.freq(voicing[0]) * 0.5, n, 0.7, gen), start, 0.34, 0.0)

	# timpani roll on D through bar 8, crescendo into the turnaround
	roll_start = th.beat_time(th.bar_beat(8, 1.0))
	roll_end = th.beat_time(th.bar_beat(8, 4.999))
	strokes = 30
	tn = n_of(0.55)
	f_timp = th.freq("D2")
	for s in range(strokes):
		frac = s / (strokes - 1.0)
		t0 = roll_start + (roll_end - roll_start) * frac
		vel = (0.22 + 0.78 * frac ** 1.4) * (1.0 if s % 2 == 0 else 0.82)
		start = int(round(t0 * SR)) + int(gen.integers(-120, 120))
		_place(left, right, _timpani(f_timp, tn, vel, gen), start, 0.16, 0.0)
	# and the hit that lands on the downbeat of the next time around
	_place(left, right, _timpani(f_timp, n_of(1.1), 1.0, gen), N, 0.20, 0.0)

	# choir "ah" across bars 7-8, resolving over the loop point
	for bar, extra in ((7, 0.0), (8, 0.45)):
		start, length = th.beat_span(th.bar_beat(bar, 1.0), 4.0)
		n = length + n_of(0.5 + extra)
		for i, name in enumerate(th.voicing_of_bar(bar)):
			f = th.freq(name, _detune(gen, 5.0))
			_place(left, right, _choir_note(f, n, 0.55 - 0.04 * i, gen),
			       start, 0.46, -0.45 + 0.30 * i)

	left, right = widen(left, right, 0.22)
	left, right = stereo_room(left, right, wet=0.19, rt60=1.25, predelay=0.016, damp_hz=5400.0)
	return highpass(left, 40.0, 2), highpass(right, 40.0, 2)


# ================================================================== 09 — tense


def _tense_string(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""Low strings, staccato: the bow bites, the note speaks, the bow leaves.

	Three things make this read as menace rather than as a short note — the friction
	burst at the attack (that is the bow catching the string, and without it a staccato
	note is just an envelope), the filter closing over the note's length, and the fact
	that it never resolves anywhere.
	"""
	tone = np.zeros(n)
	for cents in (-8.0, 0.0, 8.0):
		tone += bl_saw(f * (2.0 ** ((cents + _detune(gen, 2.5)) / 1200.0)), n, cap=24)
	tone /= 3.0
	bite = bandpass(noise(n, gen), 950.0, 4400.0, order=2) * perc_env(n, 0.0012, 0.016, 1.7)
	voiced = sweep_filter(tone, expline(n, 1450.0, 460.0), q=0.85, kind="lp")
	env = asr_env(n, 0.014, 0.085, 1.9)
	return unit(blend(voiced, bite, 0.16) * env, velocity)


def _muted_tick(n: int, gen: np.random.Generator, f0: float, tau: float) -> np.ndarray:
	"""Stick on a muted rim. Nothing under a kilohertz, nothing that rings."""
	exc = np.zeros(n)
	k = max(3, n_of(0.0005))
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = bandpass(exc, 1600.0, 11000.0, order=2)
	return unit(modal(exc, [
		(f0, tau, 0.60),
		(f0 * 1.93, tau * 0.62, 0.85),
		(f0 * 3.41, tau * 0.36, 0.50),
		(f0 * 5.80, tau * 0.20, 0.24),
	]))


def stem_tense() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_tense")
	left, right = _buf(), _buf()

	for bar in range(1, th.BARS + 1):
		for beat, name, dur, vel in th.TENSE_BARS[bar - 1]:
			f = th.freq(name, _detune(gen, 2.0))
			start, length = th.beat_span(th.bar_beat(bar, beat), dur)
			n = length + n_of(0.24)
			jitter = int(gen.integers(-70, 70))
			_place(left, right, _tense_string(f, n, vel, gen), start + jitter, 0.52, -0.14)
			# an octave double, well under it, so the pedal has an edge on a phone
			_place(left, right, _tense_string(f * 2.0, n, vel * 0.55, gen),
			       start + jitter, 0.20, 0.16)
		for beat in th.TENSE_TICK_BEATS:
			vel = th.TENSE_TICK_ACCENT.get(beat, 0.55)
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-90, 90))
			f0 = 2380.0 if beat in th.TENSE_TICK_ACCENT else 2610.0
			# Down-beats one side, swung off-beats the other: two hands, one clock.
			off_beat = beat % 1.0 != 0.0
			_place(left, right, _muted_tick(n_of(0.09), gen, f0, 0.0075),
			       start, vel * 0.22, 0.34 if off_beat else -0.30)

	# The room the Heat mix wants is a small one (docs/08 §4: "the room gets smaller"),
	# so this stem gets less reverb than anything else in the stack, not more.
	left, right = stereo_room(left, right, wet=0.07, rt60=0.45, predelay=0.009, damp_hz=3400.0)
	return highpass(left, 42.0, 2), highpass(right, 42.0, 2)


# ============================================================ 10 — raid drums


def _big_kick(n: int, gen: np.random.Generator, velocity: float = 1.0) -> np.ndarray:
	"""Not the brush kit's felt beater: a hard beater on a big open drum."""
	drop = n_of(0.055)
	f = np.full(n, 44.0)
	f[:drop] = expline(drop, 165.0, 44.0)
	body = np.sin(phase_of(f)) * perc_env(n, 0.0012, 0.135, 0.95)
	click = bandpass(noise(n, gen), 1400.0, 5200.0, order=2) * perc_env(n, 0.0004, 0.0055, 1.8)
	skin = lowpass(noise(n, gen), 900.0, order=2) * perc_env(n, 0.0008, 0.020, 1.3)
	return unit(blend(blend(body, skin, 0.28), click, 0.16), velocity)


def _raid_snare(n: int, gen: np.random.Generator, velocity: float = 1.0) -> np.ndarray:
	"""Splashy: a wide-open snare with the strainer loose, and a splash cymbal on it.

	The wires are a separate layer with their own, longer envelope — a snare where the
	buzz decays with the shell is a tom with an attitude, not a snare.
	"""
	exc = np.zeros(n)
	k = max(3, n_of(0.0012))
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = bandpass(exc, 300.0, 9000.0, order=2)
	shell = modal(exc, [(186.0, 0.075, 0.80), (331.0, 0.055, 0.60),
	                    (498.0, 0.036, 0.45), (842.0, 0.020, 0.30)])
	wires = bandpass(noise(n, gen), 2600.0, 11000.0, order=2) * perc_env(n, 0.0012, 0.115, 0.85)
	splash = modal(exc, [(612.0, 0.34, 0.40), (1043.0, 0.28, 0.42), (1687.0, 0.22, 0.38),
	                     (2590.0, 0.17, 0.32), (3910.0, 0.12, 0.24), (5720.0, 0.08, 0.16)])
	out = blend(unit(shell), unit(wires), 0.72)
	return unit(blend(out, unit(splash), 0.46), velocity)


def _tom(f0: float, n: int, gen: np.random.Generator, velocity: float = 1.0) -> np.ndarray:
	"""Tuned tom: membrane modes plus the beater, with the head's pitch bend at the hit."""
	exc = np.zeros(n)
	k = max(3, n_of(0.0025))
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = lowpass(exc, 1600.0, order=2)
	ratios = [1.00, 1.504, 1.742, 2.00, 2.44]
	taus = [0.30, 0.21, 0.16, 0.12, 0.08]
	gains = [1.00, 0.55, 0.38, 0.26, 0.15]
	drum = modal(exc, [(f0 * r, tau, g) for r, tau, g in zip(ratios, taus, gains)])
	# the head is stretched at the moment of impact and relaxes over ~40 ms
	bend_n = min(n, n_of(0.045))
	bend = np.zeros(n)
	bend[:bend_n] = np.sin(phase_of(expline(bend_n, f0 * 1.32, f0))) * exp_decay(bend_n, 0.014)
	beater = lowpass(noise(n, gen), 2600.0, order=2) * perc_env(n, 0.0006, 0.011, 1.5)
	out = blend(blend(unit(drum), unit(bend), 0.34), unit(beater), 0.20)
	return unit(out * asr_env(n, 0.001, 0.06, 2.0), velocity)


TOM_HZ = {"hi": 196.00, "mid": 146.83, "lo": 110.00}     # G3, D3, A2
TOM_PAN = {"hi": 0.34, "mid": 0.02, "lo": -0.32}


def stem_raid_drums() -> tuple[np.ndarray, np.ndarray]:
	gen = rng("stem_raid_drums")
	left, right = _buf(), _buf()
	kick_n = n_of(0.70)
	snare_n = n_of(1.10)
	tom_n = n_of(0.55)

	for bar in range(1, th.BARS + 1):
		fill = bar in th.RAID_FILL_BARS
		for beat in th.RAID_KICK_BEATS:
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-50, 50))
			vel = 1.0 if beat == 1.0 else 0.92
			_place(left, right, _big_kick(kick_n, gen, vel), start, 0.90, 0.0)
		for beat, vel in th.RAID_KICK_PICKUP:
			if fill:
				continue
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-50, 50))
			_place(left, right, _big_kick(kick_n, gen, vel), start, 0.60, 0.0)
		for beat in th.RAID_SNARE_BEATS:
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-60, 60))
			_place(left, right, _raid_snare(snare_n, gen, 1.0), start, 0.62, -0.10)
		for beat, voice, vel in (th.RAID_FILL if fill else th.RAID_TOM_PATTERN):
			start = th.beat_sample(th.bar_beat(bar, beat)) + int(gen.integers(-70, 70))
			_place(left, right, _tom(TOM_HZ[voice], tom_n, gen, vel), start,
			       0.46, TOM_PAN[voice])
		# the fill bars end on the downbeat of the next bar
		if fill:
			_place(left, right, _big_kick(kick_n, gen, 1.0),
			       th.beat_sample(th.bar_beat(bar, 5.0)), 0.90, 0.0)

	left, right = widen(left, right, 0.18)
	left, right = stereo_room(left, right, wet=0.15, rt60=1.10, predelay=0.014, damp_hz=6400.0)
	return highpass(left, 30.0, 2), highpass(right, 30.0, 2)


# ======================================================= count_piano (unsynced)


def piano_note(f: float, n: int, velocity: float, gen: np.random.Generator) -> np.ndarray:
	"""A struck string over a soundboard: three strings a unison, felt, stiffness.

	Inharmonicity is the whole difference between a piano and an organ. A real string
	resists bending, so partial k sits at ``k*f*sqrt(1 + B k^2)`` rather than at ``k*f``;
	B falls as the strings get shorter and thinner up the keyboard. That stretch is why
	the partials of a low D and a high D never quite line up, and it is what a listener
	hears as "piano" before they hear anything else.

	Two more things earn their keep: each partial gets its *own* decay (the top of the
	spectrum is gone in half a second while the fundamental hangs on for three, which is
	the shape of a piano note), and the three strings of a unison are detuned by under a
	cent so the note breathes instead of sitting still.
	"""
	t = t_axis(n)
	stiff = float(np.interp(f, [55.0, 110.0, 220.0, 440.0, 880.0],
	                        [4.2e-4, 2.4e-4, 1.4e-4, 0.9e-4, 0.7e-4]))
	tau1 = float(np.interp(f, [55.0, 110.0, 220.0, 440.0, 880.0],
	                       [3.4, 2.8, 2.1, 1.5, 1.0]))
	# harder blows are brighter, exactly as the hammer's contact time gets shorter
	tilt = 1.55 - 0.55 * velocity
	strings = [(-0.65, 0.88), (0.0, 1.00), (0.72, 0.84)]

	out = np.zeros(n)
	for k in range(1, 19):
		fk = k * math.sqrt(1.0 + stiff * k * k)
		if f * fk > 0.45 * SR:
			break
		amp = 1.0 / (k ** tilt)
		if amp < 6e-4:
			break
		env = np.exp(-t / (tau1 / (1.0 + 0.95 * (k - 1) ** 0.72)))
		partial = np.zeros(n)
		for cents, g in strings:
			partial += g * np.sin(phase_of(f * fk * 2.0 ** ((cents + _detune(gen, 0.5)) / 1200.0),
			                               n, phase0=float(gen.uniform(0.0, 6.28))))
		out += amp * partial * env

	# hammer felt on the string, and the case around it
	hammer = lowpass(noise(n, gen), 2600.0, order=2) * perc_env(n, 0.0006, 0.0075, 1.6)
	out = blend(out, hammer, 0.14)
	board = modal(out, [(97.0, 0.075, 0.30), (148.0, 0.055, 0.22), (231.0, 0.038, 0.15)])
	out = blend(out, board, 0.22)
	return unit(lowpass(out, 9500.0, order=2) * asr_env(n, 0.0012, 0.10, 2.0), velocity)


def stem_count_piano() -> tuple[np.ndarray, np.ndarray]:
	"""Solo piano, its own 4-bar loop at 55 BPM — it never syncs with the band."""
	gen = rng("stem_count_piano")
	loop_n = th.COUNT_FRAMES
	total = loop_n + n_of(5.0)
	left, right = np.zeros(total), np.zeros(total)

	for beat, names, dur, vel in th.COUNT_PIANO_LINE:
		start = th.count_beat_sample(beat)
		length = th.count_beat_sample(beat + dur) - start
		n = length + n_of(2.2)                       # the note rings past its notation
		# the hand rolls very slightly, and lands a touch before or after the beat
		lean = int(gen.integers(-1400, 1400))
		for i, name in enumerate(names):
			f = th.freq(name, _detune(gen, 2.0))
			midi = th.note_to_midi(name)
			position = float(np.clip((midi - 62) / 34.0, -0.45, 0.45))
			v = vel * (1.0 - 0.05 * i)
			_place(left, right, piano_note(f, n, v, gen),
			       start + lean + n_of(0.011 * i) + int(gen.integers(-500, 500)),
			       1.0, position, loop_n=loop_n)

	left, right = stereo_room(left, right, wet=0.22, rt60=1.55, predelay=0.020, damp_hz=4200.0)
	return highpass(left, 34.0, 2), highpass(right, 34.0, 2)


# ================================================================== the stack

STEMS = {
	"01_bass": stem_bass,
	"02_drums": stem_drums,
	"03_vibes": stem_vibes,
	"04_trumpet": stem_trumpet,
	"05_organ": stem_organ,
	"06_barisax": stem_barisax,
	"07_strings": stem_strings,
	"08_full": stem_full,
	"09_tense": stem_tense,
	"10_raid_drums": stem_raid_drums,
}

# Not in the synchronized stack: its own tempo, its own loop length, its own level.
COUNT_PIANO = "count_piano"


def _level_to(stereo: np.ndarray, target_lufs: float) -> np.ndarray:
	"""Hit a loudness target *through* the limiter.

	Scaling to target and then clipping the peaks back (which is what a plain
	peak-normalise does) leaves a transient stem like the drums 8 dB under everything
	else. Converges in two or three passes.
	"""
	from .analysis import lufs_integrated

	for _ in range(6):
		measured = lufs_integrated(stereo, SR)
		if measured <= -180.0:
			break
		error = target_lufs - measured
		stereo = soft_limit(stereo * db2lin(error), PEAK_CEILING_DB, knee_db=7.0)
		if abs(error) < 0.1:
			break
	return stereo


def render_stem(name: str) -> np.ndarray:
	"""Render one synced stem to an (N, 2) float array, loop-folded and level-matched."""
	left, right = STEMS[name]()
	assert len(left) == TOTAL and len(right) == TOTAL, "stem rendered at the wrong length"
	left = dc_remove(left, 24.0)
	right = dc_remove(right, 24.0)
	# Everything above this line is linear and time-invariant, so folding here is exact.
	stereo = np.stack([fold_tail(left, N), fold_tail(right, N)], axis=1)
	assert stereo.shape[0] == N, "fold produced the wrong frame count"
	return _level_to(stereo, STEM_LUFS[name])


def render_count_piano() -> np.ndarray:
	"""Render the unsynced piano to a (COUNT_FRAMES, 2) float array."""
	loop_n = th.COUNT_FRAMES
	left, right = stem_count_piano()
	left = dc_remove(left, 24.0)
	right = dc_remove(right, 24.0)
	stereo = np.stack([fold_tail(left, loop_n), fold_tail(right, loop_n)], axis=1)
	assert stereo.shape[0] == loop_n, "fold produced the wrong frame count"
	return _level_to(stereo, COUNT_PIANO_LUFS)
