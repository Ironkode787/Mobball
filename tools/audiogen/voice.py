"""The muted-brass mob — the specialists' speaking voices (docs/08 §5).

There is no voice acting in this game and there never will be. Every character speaks
through one instrument (Big Sal is a tuba, Nussbaum a clarinet, Rosa an alto sax) and
the subtitle carries the actual joke. The gag only lands if what comes out is
unmistakably *speech* and unmistakably *not a tune*, so this module is a prosody
generator that happens to be wearing a horn.

The model
---------
A phrase is 3-7 **syllables**, and a syllable is three curves that move together:

* **pitch** — a continuous contour, never a note. Each syllable has a target drawn by a
  random walk in *fractional* semitones, the voice *glides* into it over the front of
  the syllable (``porta``), and the whole phrase drifts downward (declination) the way
  a spoken sentence does. Nothing is quantised anywhere: the moment two syllables land
  a clean third apart the ear hears a melody and the character stops talking.
* **loudness** — a bump per syllable that never returns to silence between them. That
  floor is the difference between a mumble and a row of staccato notes, and the mumble
  is the whole joke.
* **the mute** — a swept bandpass standing in for a plunger over the bell. Its centre
  opens and closes once per syllable; that is the "wah", and it is what the ear reads
  as vowels. Brass gets the most of it, the reeds and strings less, because their own
  formants are already doing some of the work.

Mood is the *shape* of all three: a greeting climbs at the end (a hail), a quip is
faster and lands flat (a punchline), a grumble is slow, low, and falls off a cliff.

One speaker breaks the model on purpose. Skids is a bicycle bell, and a bell is struck
rather than blown, so his phrase spends the same contours differently: the syllable
onsets become three dings and the sigh underneath carries the loudness and the vowels
(:func:`_bell_and_sigh`). The prosody is identical; only the instrument disagrees.

Determinism, as everywhere in this generator: the seed is derived from the speaker and
the mood, so a phrase is the same phrase on every machine, forever.
"""

from __future__ import annotations

from typing import NamedTuple

import numpy as np

from .analysis import envelope, lufs_integrated, peak_db, spectral_centroid
from .synth import (
	SR, bandpass, biquad, bl_pulse, bl_saw, comb_ff, db2lin, dc_remove, fade_edges,
	formants, lowpass, modal, n_of, noise, rng, room, smoothstep, soft_limit,
	sweep_filter, t_axis, unit,
)

# Dialogue is levelled by K-weighted loudness rather than by peak: a tuba and an oboe
# normalised to the same peak are nowhere near the same loudness, and a phrase bank that
# changes volume when the speaker changes is a bank nobody can mix under.
VOICE_LUFS = -20.0
VOICE_PEAK_CAP_DB = -3.5

MOOD_NAMES = ("greeting", "quip", "grumble")


class Mood(NamedTuple):
	"""The prosody of one kind of utterance, independent of who is speaking."""
	syllables: tuple[int, int]
	syllable_s: tuple[float, float]
	length_s: float          # phrase length before the speaker's own rate is applied
	declination: float       # semitones the phrase sags over its length
	final: float             # semitones the last syllable adds — up asks, down closes
	shift: float             # semitones the whole phrase sits off the speaker's centre
	floor: float             # the mumble floor between syllables
	open_bias: float         # how far open the mute sits on average, -1..+1
	release_s: float


MOODS: dict[str, Mood] = {
	# A hail across a room: mid-length, opens up, and turns up at the end because it is
	# half a question ("hey — you made it?").
	"greeting": Mood((4, 6), (0.13, 0.21), 0.86, 1.1, 3.2, 2.0, 0.30, 0.16, 0.26),
	# The one-liner. Quicker, more syllables, a hard accent early and a flat landing —
	# a punchline that rises is a punchline nobody laughs at.
	"quip": Mood((5, 7), (0.10, 0.16), 0.80, 2.4, -1.6, 0.0, 0.26, 0.00, 0.22),
	# Complaining. Slow, low, closed down, and it falls off the end the way a man walks
	# away mid-sentence.
	"grumble": Mood((3, 5), (0.17, 0.27), 0.92, 4.2, -3.6, -3.2, 0.34, -0.24, 0.34),
}


class Speaker(NamedTuple):
	"""One specialist. ``instrument`` picks the tone generator; everything else is how
	this particular guy uses it."""
	name: str
	instrument: str
	centre: float            # Hz the voice sits around
	span: float              # semitones the contour may wander
	porta: float             # 0..1 of each syllable spent gliding into its target
	vib_hz: float
	vib_cents: float
	wah: tuple[float, float]  # mute closed / mute open, in Hz
	wah_mix: float           # how much of the tone goes through the mute
	wah_q: float
	rate: float              # phrase length multiplier — how fast this one talks
	room_wet: float
	shelf_db: float = 0.0    # low shelf under 170 Hz — see _finish_voice
	strikes: int = 0         # >0 = struck, not blown: see _bell_and_sigh


# docs/08 §5. One instrument per specialist, and the instrument IS the character.
SPEAKERS: tuple[Speaker, ...] = (
	# Skids does not talk. He rings his bell and he sighs, and you know exactly what he
	# meant. docs/08 §5 hangs "a bicycle bell and a sigh" on the Inspector; the roster
	# gives the same instrument to Skids (specs/m2-content.md §2), and one bank serves
	# both — nobody is going to confuse a bell with a tuba.
	Speaker("skids", "bicycle_bell", 2280.0, 3.0, 0.10, 0.0, 0.0, (360.0, 2100.0), 1.0, 1.9, 1.00, 0.20, 0.0, 3),
	# Big Sal is a tuba: three words, all of them low, none of them fast.
	Speaker("big_sal", "tuba", 82.41, 5.0, 0.42, 4.4, 26.0, (250.0, 900.0), 0.75, 2.2, 1.18, 0.13, -6.5),
	# Nussbaum's clarinet is hollow (odd harmonics only) and never stops moving.
	Speaker("nussbaum", "clarinet", 293.66, 8.0, 0.30, 5.6, 20.0, (520.0, 1950.0), 0.55, 2.6, 0.88, 0.15),
	# Rosa: alto sax, breathy, takes her time, and bends into everything.
	Speaker("rosa", "alto_sax", 329.63, 7.0, 0.52, 5.0, 30.0, (600.0, 2250.0), 0.60, 2.4, 1.06, 0.16),
	# Whispers Cohen glisses — docs/08 §5 says so — so almost the whole syllable is the
	# slide, and he sits high enough that you hear every inch of it.
	Speaker("cohen", "violin", 587.33, 9.0, 0.86, 6.2, 34.0, (800.0, 2950.0), 0.45, 2.2, 1.00, 0.20),
	# The Professor's oboe: nasal, exact, no glide worth mentioning, no vibrato early.
	Speaker("professor", "oboe", 440.00, 6.5, 0.22, 5.2, 14.0, (900.0, 3050.0), 0.50, 3.0, 0.96, 0.14),
	# The Consigliere is a cello. Measured. You wait for him.
	Speaker("consigliere", "cello", 146.83, 6.0, 0.55, 4.6, 22.0, (340.0, 1300.0), 0.55, 2.3, 1.16, 0.18, -4.5),
	# Manny's cornet: bright, stabby, fast, and with the buzz that made docs/08 call it
	# "kazoo-ish" in the first place.
	Speaker("manny", "cornet", 466.16, 8.5, 0.26, 5.8, 24.0, (820.0, 3200.0), 0.80, 2.8, 0.84, 0.14),
	# Eddie Odds slides everything, because a trombone player cannot help it.
	Speaker("eddie", "trombone", 174.61, 10.0, 0.94, 4.8, 28.0, (420.0, 1700.0), 0.78, 2.4, 1.10, 0.16, -3.0),
)

SPEAKER_BY_NAME: dict[str, Speaker] = {s.name: s for s in SPEAKERS}


# ----------------------------------------------------------------- the contours


def _smooth(x: np.ndarray, ms: float) -> np.ndarray:
	"""Moving average. Every contour goes through this: a piecewise curve has corners,
	and a corner in a pitch contour is a click in the tone that follows it."""
	w = max(3, n_of(ms * 1e-3))
	pad = np.concatenate([np.full(w, x[0]), x, np.full(w, x[-1])])
	kernel = np.ones(w) / w
	return np.convolve(pad, kernel, mode="same")[w: w + len(x)]


def _glide(targets: np.ndarray, starts: np.ndarray, lengths: np.ndarray, n: int,
           porta: float, first: float) -> np.ndarray:
	"""Piecewise contour: glide into each syllable's target, then hold it.

	``porta`` is the fraction of the syllable spent arriving. At 0.2 the voice snaps to
	a pitch and sits on it (an oboe); at 0.9 it is still moving when the next syllable
	starts (a trombone, or Cohen's violin) and no discrete pitch is ever heard at all.
	"""
	out = np.full(n, first)
	prev = first
	for target, start, length in zip(targets, starts, lengths):
		end = min(start + length, n)
		if end <= start:
			continue
		ramp = max(2, int(length * porta))
		ramp = min(ramp, end - start)
		out[start: start + ramp] = prev + (target - prev) * smoothstep(ramp)
		if start + ramp < end:
			out[start + ramp: end] = target
		prev = target
	last_end = int(min(starts[-1] + lengths[-1], n))
	if last_end < n:
		out[last_end:] = prev
	return out


class Phrase(NamedTuple):
	freq: np.ndarray        # instantaneous frequency, Hz
	amp: np.ndarray         # 0..1 loudness contour
	mute: np.ndarray        # mute centre frequency, Hz
	n: int
	starts: np.ndarray      # syllable onsets, in samples
	lengths: np.ndarray     # ...and how long each one lasts
	accent: int             # which syllable carries the stress


def _phrase(sp: Speaker, mood_name: str, gen: np.random.Generator) -> Phrase:
	"""Draw one utterance and render its three contours at sample rate."""
	m = MOODS[mood_name]
	count = int(gen.integers(m.syllables[0], m.syllables[1] + 1))
	accent = int(gen.integers(0, max(1, count - 1)))     # never the last one

	raw = np.array([float(gen.uniform(*m.syllable_s)) for _ in range(count)])
	raw[accent] *= 1.25
	raw[-1] *= 1.30                                      # phrase-final lengthening
	body_s = m.length_s * sp.rate
	durs = raw * (body_s / float(raw.sum()))
	release_s = m.release_s * (0.8 + 0.4 * sp.rate)
	n = n_of(body_s + release_s)

	lengths = np.array([max(2, n_of(d)) for d in durs])
	starts = np.concatenate([[0], np.cumsum(lengths)[:-1]])

	# Pitch: a random walk in fractional semitones, so no two syllables ever land an
	# interval apart. Declination is added on top and the mood's final gesture is put
	# on the last syllable, where a speaker actually puts it.
	step = np.array([float(gen.normal(0.0, sp.span * 0.22)) for _ in range(count)])
	walk = np.cumsum(step)
	walk -= walk.mean()
	walk = np.clip(walk, -sp.span * 0.5, sp.span * 0.5)
	walk[accent] += sp.span * 0.18
	walk += m.shift - m.declination * np.linspace(0.0, 1.0, count)
	walk[-1] += m.final

	semis = _smooth(_glide(walk, starts, lengths, n, sp.porta, float(walk[0]) - 1.2), 22.0)
	t = t_axis(n)
	vib_in = np.clip((t - 0.22) / max(body_s - 0.22, 1e-3), 0.0, 1.0) ** 1.5
	vib = 1.0 + (sp.vib_cents / 1200.0) * np.log(2.0) * vib_in * np.sin(2.0 * np.pi * sp.vib_hz * t)
	freq = sp.centre * (2.0 ** (semis / 12.0)) * vib

	# Loudness: one bump per syllable, and it never comes back to zero in between.
	amp = np.full(n, m.floor)
	for i, (start, length) in enumerate(zip(starts, lengths)):
		end = min(start + length, n)
		if end <= start:
			continue
		peak = (1.0 if i == accent else float(gen.uniform(0.62, 0.90)))
		bump = np.sin(np.pi * np.linspace(0.0, 1.0, end - start)) ** 0.6
		amp[start: end] = m.floor + (peak - m.floor) * bump
	body_n = int(min(starts[-1] + lengths[-1], n))
	amp[:n_of(0.012)] *= smoothstep(max(1, n_of(0.012)))
	if body_n < n:
		tail = n - body_n
		amp[body_n:] = amp[body_n - 1] * (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, tail))) ** 1.4
	amp = _smooth(amp, 14.0)

	# The mute: open and close once per syllable. The accented syllable opens widest,
	# which is what makes one syllable of a mumble sound like the important one.
	vowels = np.array([float(np.clip(gen.uniform(0.10, 0.95) + m.open_bias, 0.05, 1.0))
	                   for _ in range(count)])
	vowels[accent] = float(np.clip(0.95 + m.open_bias * 0.5, 0.3, 1.0))
	openness = _smooth(_glide(vowels, starts, lengths, n, 0.55, 0.12), 26.0)
	lo, hi = sp.wah
	mute = lo * (hi / lo) ** np.clip(openness, 0.0, 1.0)
	return Phrase(freq, amp, mute, n, starts, lengths, accent)


# --------------------------------------------------------------------- the horns

# Each of these takes the phrase's instantaneous frequency and returns a *sustained*
# tone at unit peak. The envelope, the mute and the room are applied afterwards, so
# these are only ever about timbre.


def _brass_tone(f: np.ndarray, n: int, gen: np.random.Generator, detune: float,
                spec, top_hz: float, mute_delay: float, rasp: float = 0.0) -> np.ndarray:
	out = np.zeros(n)
	for cents in (-detune, 0.0, detune):
		out += bl_saw(f * (2.0 ** (cents / 1200.0)), cap=34)
	out /= 3.0
	voiced = formants(out, spec) + 0.42 * out
	if mute_delay > 0.0:
		voiced = comb_ff(voiced, mute_delay, 0.52)          # the cup of the mute
	breath = bandpass(noise(n, gen), 1600.0, 6200.0, order=2) * 0.06
	voiced = lowpass(voiced + breath, top_hz, order=2)
	if rasp > 0.0:
		# The buzz that made docs/08 call Manny "kazoo-ish": the lips rattling in the
		# cup, which is distortion of the tone rather than anything added to it.
		voiced = voiced + rasp * np.tanh(voiced * 3.2)
	return unit(voiced)


def _reed_tone(f: np.ndarray, n: int, gen: np.random.Generator, duty: float,
               spec, top_hz: float, breath: float) -> np.ndarray:
	# Duty is the whole identity of a reed here: 0.5 is a square (odd harmonics only,
	# the clarinet's hollow register) and 0.12 is the thin nasal pulse of a double reed.
	out = bl_pulse(f, n, duty=duty, cap=44)
	voiced = formants(out, spec) + 0.36 * out
	air = bandpass(noise(n, gen), 1800.0, 7200.0, order=2) * breath
	return unit(lowpass(voiced + air, top_hz, order=2))


def _bowed_tone(f: np.ndarray, n: int, gen: np.random.Generator, detune: float,
                spec, top_hz: float, rosin: float) -> np.ndarray:
	out = np.zeros(n)
	for cents in (-detune, 0.0, detune * 0.6):
		out += bl_saw(f * (2.0 ** (cents / 1200.0)), cap=48)
	out /= 3.0
	voiced = formants(out, spec) + 0.46 * out
	# Rosin: the bow biting, which is the only thing that stops a sawtooth through a
	# body filter from sounding like a sawtooth through a body filter.
	scrape = bandpass(noise(n, gen), 1100.0, 6800.0, order=2) * rosin
	return unit(lowpass(voiced + scrape, top_hz, order=2))


def _bell_and_sigh(sp: Speaker, ph: Phrase, gen: np.random.Generator) -> np.ndarray:
	"""Skids. docs/08 §5: a bicycle bell and a sigh, and that is the whole vocabulary.

	Everything else in the bank is *blown* — a continuous tone shaped by a mute. A bell
	is *struck*, so the prosody has to arrive somewhere else: the phrase's syllable
	onsets become the dings (a handful of them, not one per syllable — a man ringing a
	bell six times is a man having an argument), the pitch contour is sampled at each
	strike instead of glided through, and the sigh underneath carries the loudness and
	the vowel contour that make it read as a sentence rather than as a doorbell.

	The sigh is the line. The bell is the punctuation.
	"""
	out = np.zeros(ph.n)
	count = len(ph.starts)
	# Evenly spread strikes, always including the first and the last syllable, plus the
	# accent — the two places a person actually rings a bell.
	picks = set(np.round(np.linspace(0, count - 1, min(sp.strikes, count))).astype(int).tolist())
	picks.add(ph.accent)
	for i in sorted(picks):
		start = int(ph.starts[i])
		f0 = float(ph.freq[min(start + 16, ph.n - 1)])
		ring = min(n_of(0.34), ph.n - start)
		if ring < n_of(0.02):
			continue
		# A pressed-steel dome, not a tuned bar: the partials are wide and irrational,
		# the strike is over in a millisecond, and the top of it is gone almost at once.
		exc = np.zeros(ring)
		k = max(3, n_of(0.0006))
		exc[:k] = noise(k, gen) * np.hanning(k)
		exc = bandpass(exc, 1800.0, 13000.0, order=2)
		ting = modal(exc, [
			(f0, 0.070, 1.00),
			(f0 * 1.0031, 0.066, 0.62),       # the dome is never quite round: it beats
			(f0 * 1.617, 0.038, 0.44),
			(f0 * 2.341, 0.022, 0.30),
			(f0 * 3.602, 0.012, 0.16),
			(f0 * 0.402, 0.028, 0.14),        # the spring and the thumb lever under it
		])
		level = 1.0 if i == ph.accent else float(gen.uniform(0.55, 0.85))
		out[start: start + ring] += unit(ting) * level

	# The sigh: breath through a slack mouth, following the vowel contour so the phrase
	# still has shape, and swelling into the release where the shoulders drop.
	sigh = sweep_filter(noise(ph.n, gen), ph.mute * 0.85, q=1.6, kind="bp", block=64)
	sigh = lowpass(sigh, 3200.0, order=2)
	# Just enough unswept breath to stop the sweep reading as a filter sweep. More than
	# this and the vowels disappear under it, which is the one thing the sigh is for.
	sigh += 0.16 * bandpass(noise(ph.n, gen), 900.0, 4200.0, order=2)
	body = int(min(ph.starts[-1] + ph.lengths[-1], ph.n))
	swell = np.ones(ph.n)
	if body < ph.n:
		swell[body:] = np.linspace(1.0, 2.4, ph.n - body)
	# A struck voice has a far bigger crest factor than a blown one, and the loudness
	# match at the end of the chain can only spend so much before it hits the peak cap —
	# so a bell left un-rounded lands audibly quieter than the rest of the bank. Taking
	# the tips off is also what a pressed-steel dome and a room actually do to a hard
	# strike, so this buys the level back without inventing anything.
	return soft_limit(unit(out), -1.0, knee_db=11.0) + 0.42 * unit(sigh * ph.amp * swell)


def _tone(sp: Speaker, f: np.ndarray, n: int, gen: np.random.Generator) -> np.ndarray:
	match sp.instrument:
		case "tuba":
			return _brass_tone(f, n, gen, 6.0,
			                   [(210.0, 2.0, 1.00), (480.0, 2.4, 0.55), (900.0, 3.0, 0.20)],
			                   1400.0, 1.0 / 190.0)
		case "trombone":
			return _brass_tone(f, n, gen, 7.0,
			                   [(520.0, 2.2, 1.00), (1180.0, 2.8, 0.48), (2100.0, 3.4, 0.16)],
			                   3200.0, 1.0 / 420.0)
		case "cornet":
			return _brass_tone(f, n, gen, 8.0,
			                   [(1150.0, 2.8, 1.00), (2350.0, 3.6, 0.42), (640.0, 2.2, 0.40)],
			                   5200.0, 1.0 / 690.0, rasp=0.22)
		case "clarinet":
			return _reed_tone(f, n, gen, 0.50,
			                  [(1480.0, 2.6, 1.00), (2600.0, 3.6, 0.28)], 3600.0, 0.045)
		case "oboe":
			return _reed_tone(f, n, gen, 0.14,
			                  [(1420.0, 3.2, 1.00), (2980.0, 4.0, 0.52), (620.0, 2.4, 0.28)],
			                  5200.0, 0.055)
		case "alto_sax":
			return _reed_tone(f, n, gen, 0.32,
			                  [(700.0, 2.8, 1.00), (1420.0, 3.6, 0.58), (2600.0, 4.2, 0.20)],
			                  4400.0, 0.085)
		case "violin":
			return _bowed_tone(f, n, gen, 9.0,
			                   [(460.0, 2.4, 0.60), (1300.0, 3.0, 1.00), (2900.0, 4.0, 0.34)],
			                   6200.0, 0.075)
		case "cello":
			return _bowed_tone(f, n, gen, 7.0,
			                   [(230.0, 2.2, 0.75), (420.0, 2.6, 1.00), (980.0, 3.2, 0.34)],
			                   3200.0, 0.060)
	raise ValueError(f"unknown instrument {sp.instrument!r}")


# ------------------------------------------------------------------- the phrase


def _sweep_mute(x: np.ndarray, centre: np.ndarray, q: float, mix: float) -> np.ndarray:
	"""The plunger over the bell: a bandpass whose centre follows the vowel contour.

	Blended rather than swapped in. A pure bandpass at Q 2.5 is a kazoo; the point is a
	horn with a hand in front of it, which is most of the horn plus a moving emphasis.
	"""
	wet = sweep_filter(x, centre, q=q, kind="bp", block=64)
	wet = unit(wet) * float(np.max(np.abs(x)) + 1e-12)
	return (1.0 - mix) * x + mix * wet


def _finish_voice(x: np.ndarray, wet: float, shelf_db: float) -> np.ndarray:
	y = room(x, wet=wet, rt60=0.52, predelay=0.012, damp_hz=5600.0)
	# The low voices get their bottom octave taken off. Two reasons, and they point the
	# same way: the target device reproduces nothing under ~400 Hz, so a tuba voiced on
	# its fundamental is a tuba nobody hears; and that fundamental is what sets the peak,
	# so leaving it in costs the loudness-match several dB it has to spend somewhere. A
	# tuba on a phone *is* its harmonics — take the 82 Hz away and Big Sal gets louder
	# and clearer at once.
	if abs(shelf_db) > 0.01:
		y = biquad(y, "lowshelf", 170.0, 0.7, shelf_db)
	y = dc_remove(y, 40.0)
	y = fade_edges(y, ms_in=3.0, ms_out=8.0)
	loud = lufs_integrated(y, SR)
	if loud > -190.0:
		y = y * db2lin(VOICE_LUFS - loud)
	peak = peak_db(y)
	if peak > VOICE_PEAK_CAP_DB:
		y = y * db2lin(VOICE_PEAK_CAP_DB - peak)
	return y


def render(speaker: str, mood: str) -> np.ndarray:
	"""One phrase: ``render("big_sal", "grumble")``."""
	sp = SPEAKER_BY_NAME[speaker]
	gen = rng(f"voice_{speaker}_{mood}")
	ph = _phrase(sp, mood, gen)
	# A struck voice brings its own envelope and its own vowels; a blown one is a
	# sustained tone that the mute and the loudness contour have to shape.
	if sp.strikes > 0:
		return _finish_voice(_bell_and_sigh(sp, ph, gen), sp.room_wet, sp.shelf_db)
	tone = _tone(sp, ph.freq, ph.n, gen)
	tone = _sweep_mute(tone, ph.mute, sp.wah_q, sp.wah_mix)
	return _finish_voice(tone * ph.amp, sp.room_wet, sp.shelf_db)


def report(x: np.ndarray) -> dict:
	"""Numeric proof that a phrase is speech rather than a held note.

	Nobody can listen to CI, and "it sounds like a guy talking" is exactly the kind of
	claim that quietly stops being true. Two measurements stand in for the ear:

	* ``wah`` — the ratio of the brightest 60 ms window's spectral centroid to the
	  dullest. A mute that is not moving scores 1.0; vowels score well above it.
	* ``bumps`` — how many times the loudness contour crosses its own mean, halved. A
	  sustained note scores 1; an utterance scores at least its syllable count (vibrato
	  ripple inflates it, which is fine — this is a floor, not a transcript).
	"""
	env = envelope(x, 30.0)
	mid = float(np.mean(env))
	crossings = int(np.count_nonzero(np.diff(np.signbit(env - mid))))
	win = n_of(0.060)
	cents = []
	for start in range(0, max(1, len(x) - win), win // 2):
		seg = x[start: start + win]
		if float(np.sqrt(np.mean(np.square(seg)))) < 0.02 * float(np.max(np.abs(x)) + 1e-12):
			continue
		c = spectral_centroid(seg, SR)
		if c > 0.0:
			cents.append(c)
	spread = (max(cents) / max(min(cents), 1e-9)) if len(cents) >= 2 else 1.0
	return {
		"seconds": len(x) / SR,
		"peak_db": peak_db(x),
		"lufs": lufs_integrated(x, SR),
		"centroid_hz": spectral_centroid(x, SR),
		"wah": float(spread),
		"bumps": max(1, crossings // 2),
	}


def files() -> list[tuple[str, str, str]]:
	"""Every file the bank ships, as (stem, speaker, mood).

	The index in the filename *is* the mood index — AudioDirector maps a mood name to it
	— so this order is the contract with game/audio/audio_director.gd.
	"""
	out: list[tuple[str, str, str]] = []
	for sp in SPEAKERS:
		for i, mood in enumerate(MOOD_NAMES):
			out.append((f"{sp.name}_{i}", sp.name, mood))
	return out
