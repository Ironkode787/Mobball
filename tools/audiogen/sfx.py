"""One function per §4 event.

House rules, applied everywhere:

* **Exciter -> resonator.** Nothing is an oscillator you can hear as an oscillator. A
  short shaped noise/contact pulse drives a bank of tuned modes with *different* decay
  times, which is what makes a hit read as an object rather than a tone: highs die in
  10 ms, the body rings for 100, the low mode hangs on.
* **Mode gains are energy shares** (see :func:`synth.modal`), so the bright short modes
  survive. This matters more than it sounds: the target device is a phone speaker with
  nothing below ~400 Hz, and a flipper built to look right on a spectrum analyser is
  inaudible on it.
* **No baked variation.** Every render is deterministic and identical. Per-hit variety
  is AudioDirector's job (`pitch_jitter`), not the file's — 40 cash ticks a second must
  not be 40 copies of the same *recording plus different noise*, they must be the same
  file pitched differently.
* **Dry and close.** Mechanical events get 6-10% room; only the bell/chime/knocker
  family, which is fiction rather than machinery, gets more.

Peak targets form a deliberate ladder (knocker loudest at the -1.5 dBFS ceiling, cash
tick and wall tap far below) so the game doesn't have to ride volume_db on every call.
"""

from __future__ import annotations

from typing import NamedTuple

import numpy as np

from .synth import (
	SR, add_at, asr_env, bandpass, biquad, bl_saw, blend, circular_bandpass, comb_ff,
	dc_remove, exp_decay, expline, fade_edges, fold_tail, formants, highpass, lowpass,
	modal, n_of, noise, normalize_peak, perc_env, phase_of, rng, room, sine,
	sweep_filter, t_axis, unit,
)

# Contact time of a real striker is ~0.1 ms; ramping the exciter over that keeps the
# file starting at true zero without dulling the transient.
_CONTACT_MS = 0.12


def _ramp_in(x: np.ndarray, ms: float = _CONTACT_MS) -> np.ndarray:
	k = max(2, n_of(ms * 1e-3))
	if k < len(x):
		x = x.copy()
		x[:k] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, k))
	return x


def _hit(n: int, gen: np.random.Generator, ms: float = 2.0, lo: float = 300.0,
         hi: float = 9000.0, sharp: float = 5.0, click: float = 0.0,
         click_ms: float = 0.18) -> np.ndarray:
	"""A contact pulse: brief band-limited noise, optionally plus a hard click.

	``sharp`` sets how fast the burst collapses; ``click`` adds a half-cosine impulse
	whose width sets its brightness.
	"""
	x = np.zeros(n)
	k = min(n, max(3, n_of(ms * 1e-3)))
	burst = noise(k, gen) * np.exp(-np.linspace(0.0, sharp, k))
	x[:k] = burst
	x = bandpass(x, lo, hi, order=2)
	if click > 0.0:
		c = min(n, max(3, n_of(click_ms * 1e-3)))
		x[:c] += click * np.sin(np.linspace(0.0, np.pi, c))
	peak = float(np.max(np.abs(x)))
	if peak > 1e-12:
		x /= peak
	return _ramp_in(x)


def _taper(x: np.ndarray, frac: float) -> np.ndarray:
	"""Raised-cosine down to true zero over the last ``frac`` of the buffer.

	Long enough to read as "the sound decaying", short enough not to shorten it. Every
	file ends at exactly 0 — a ringing tail chopped by a 3 ms fade is an audible click,
	and a bell is still 30 dB up when its notated length runs out.
	"""
	k = int(len(x) * frac)
	if k < 4:
		return x
	y = x.copy()
	y[len(x) - k:] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, k))) ** 1.3
	return y


def _finish(x: np.ndarray, target_db: float, wet: float = 0.08, rt60: float = 0.32,
            predelay: float = 0.008, tilt_db: float = 0.0, taper: float = 0.18) -> np.ndarray:
	"""Room, presence tilt, DC removal, safe tail, level."""
	y = room(x, wet=wet, rt60=rt60, predelay=predelay, damp_hz=6200.0)
	if abs(tilt_db) > 0.01:
		y = biquad(y, "highshelf", 1800.0, 0.7, tilt_db)
	y = dc_remove(y, 22.0)
	y = _taper(y, taper)
	y = fade_edges(y, ms_in=0.0, ms_out=1.5)
	return normalize_peak(y, target_db)


def _finish_loop(x: np.ndarray, loop_n: int, target_db: float, wet: float = 0.08,
                 rt60: float = 0.32, predelay: float = 0.008,
                 tilt_db: float = 0.0) -> np.ndarray:
	"""Level and polish for a sound that has to join itself — no taper, no fade.

	The buffer handed in is *one period followed by silence*, rendered long enough for
	the room to die out. Everything applied before the fold is linear and time-invariant,
	so folding the overhang back onto the head reproduces exactly what an infinitely
	repeating input would have produced (music.py §wraparound, same argument). After the
	fold the only legal processing is circular or memoryless, which is why the DC removal
	here is an FFT-domain filter rather than the causal ``dc_remove`` used everywhere else:
	a causal high-pass has a start-up transient, and that transient *is* the loop click.
	"""
	y = room(x, wet=wet, rt60=rt60, predelay=predelay, damp_hz=6200.0)
	if abs(tilt_db) > 0.01:
		y = biquad(y, "highshelf", 1800.0, 0.7, tilt_db)
	y = fold_tail(y, loop_n)
	y = circular_bandpass(y - float(np.mean(y)), 26.0, 19500.0, slope=1.5)
	return normalize_peak(y, target_db)


# --------------------------------------------------------------- shared voices

# Every voice below returns a unit-peak buffer, so a mix gain of 0.5 in a composite
# event means "half as loud" rather than "half of whatever a modal bank happened to
# produce". Raw ``modal()`` output is scaled by the mode energies and can be 60x unity;
# mixing those against each other by eye is how a cash register ends up being 90 % bell.


def _metal_ping(n: int, gen: np.random.Generator, f0: float, tau: float = 0.09,
                bright: float = 1.0) -> np.ndarray:
	"""A small struck disc — a coin, a washer, the end of a spring.

	Coin partials are wildly inharmonic (a flat disc's modes are Bessel zeros, not
	integers); using 2.28/3.61/5.02 is what stops a coin from sounding like a bell.
	"""
	exc = _hit(n, gen, ms=0.35, lo=1200.0, hi=11000.0, sharp=10.0, click=0.55, click_ms=0.09)
	ping = modal(exc, [
		(f0, tau, 1.00),
		(f0 * 1.004, tau * 0.92, 0.55),           # the disc is never perfectly round
		(f0 * 2.28, tau * 0.55 * bright, 0.34),
		(f0 * 3.61, tau * 0.34 * bright, 0.18),
		(f0 * 5.02, tau * 0.20 * bright, 0.08),
	])
	# You are not holding it to your ear: the top of a coin's partial set is gone by
	# the time it reaches the far side of a room, and leaving it in makes a till full
	# of money sound like a till full of broken glass.
	return unit(lowpass(ping, 7600.0, order=2))


def _paper(n: int, gen: np.random.Generator, lo: float = 1500.0, hi: float = 8000.0,
           tau: float = 0.02, grip: float = 0.0) -> np.ndarray:
	"""A sheet of paper moving: filtered noise with the stick-slip grain of fibre.

	``grip`` modulates the noise with a low-rate random walk, which is the difference
	between "paper sliding" and "white noise fading out".
	"""
	x = bandpass(noise(n, gen), lo, hi, order=2) * perc_env(n, 0.0015, tau, 1.0)
	if grip > 0.0:
		walk = lowpass(noise(n, gen), 90.0, order=2)
		walk /= float(np.max(np.abs(walk))) + 1e-12
		x *= 1.0 + grip * walk
	return unit(x)


def _brass(f: float, n: int, gen: np.random.Generator, velocity: float = 1.0,
           rip_cents: float = 70.0, attack: float = 0.022, release: float = 0.09,
           bright: float = 1.0, bend: np.ndarray | None = None) -> np.ndarray:
	"""Three detuned saws through a brass formant bank, with a rip into the attack.

	Same voice as the 08_full section (music.py) so a fanfare over the score reads as
	the same band, not a second one.
	"""
	t = t_axis(n)
	rip = np.ones(n)
	rk = min(n, max(2, n_of(0.026)))
	rip[:rk] = np.linspace(2.0 ** (-rip_cents / 1200.0), 1.0, rk)
	if bend is not None:
		rip = rip * bend
	out = np.zeros(n)
	for cents in (-8.0, 0.0, 8.0):
		out += bl_saw(f * rip * (2.0 ** (cents / 1200.0)), n, cap=34)
	out /= 3.0
	voiced = formants(out, [(1250.0 * bright, 2.6, 1.00), (2400.0 * bright, 3.4, 0.30),
	                        (620.0, 2.2, 0.45)]) + 0.4 * out
	breath = bandpass(noise(n, gen), 1800.0, 6200.0, order=2) * 0.06
	# A section playing into a room, not a solo bell of a trumpet pointed at a mic.
	voiced = lowpass(voiced + breath, 5400.0 * bright, order=2)
	env = asr_env(n, attack, release, 1.5)
	bite = 1.0 + 0.55 * np.exp(-t / 0.028)
	return unit(voiced * env * bite, velocity)


def _drum(f0: float, n: int, gen: np.random.Generator, velocity: float = 1.0,
          tau: float = 0.36, head_hz: float = 800.0) -> np.ndarray:
	"""Tuned membrane: the circular-drum mode ratios, plus the beater on the head."""
	exc = np.zeros(n)
	k = max(3, n_of(0.0035))
	exc[:k] = noise(k, gen) * np.hanning(k)
	exc = lowpass(exc, head_hz * 1.2, order=2)
	ratios = [1.00, 1.504, 1.742, 2.00, 2.30, 2.66]
	taus = [1.00, 0.70, 0.54, 0.40, 0.28, 0.19]
	gains = [1.00, 0.60, 0.42, 0.30, 0.20, 0.12]
	drum = modal(exc, [(f0 * r, tau * tt, g) for r, tt, g in zip(ratios, taus, gains)])
	head = lowpass(noise(n, gen), head_hz, order=2) * perc_env(n, 0.001, 0.028, 1.4)
	return unit(blend(drum, head, 0.22) * asr_env(n, 0.001, 0.05, 2.0), velocity)


# ------------------------------------------------------- wave 3: impact layers

# docs/08 §8 asks for velocity layers on the physical events. Three files per family,
# picked at play time by `AudioDirector.play(event, {"impact": 0..1})`; the MEDIUM layer
# *is* the original file — same seed, same numbers, byte-identical output — so nothing
# that plays `bumper_hit` today changes, and the two new files are only what a softer or
# a harder hit sounds like.
#
# Brightness is the variable, not level. A harder strike has a shorter contact time and
# puts far more energy into the high modes: the exciter's band opens up, the click
# sharpens, the top of the modal bank gains and rings longer, the presence tilt follows.
# generate.py measures all three spectral centroids and fails the build unless they rise
# strictly with impact — "we normalised it louder" is not a velocity layer.


class Layer(NamedTuple):
	"""One rung of a velocity ladder. Every multiplier is 1.0 (and every offset 0.0) on
	the medium rung, so the medium render reduces to the original code exactly.

	All three rungs of a family share one seed, and that is load-bearing rather than
	lazy. ``_hit`` peak-normalises a 1-2 ms noise burst, so *which* burst you draw sets
	the click/noise balance of the exciter and moves the finished centroid by up to an
	octave — more than the physics does. With three different seeds the measured
	brightness ordering is a coin toss; with one, the only thing that varies between the
	rungs is how hard the thing was hit, which is the point. It is also what really
	happens: the same bumper, struck harder."""
	seed: str
	peak_db: float
	dur: float = 1.0        # length: a soft hit is over sooner
	ms: float = 1.0         # exciter contact time — longer means softer and duller
	hi: float = 1.0         # top of the exciter's band
	click: float = 1.0      # the hard contact impulse riding on it
	top: float = 1.0        # gain of the modes above ~1 kHz
	top_tau: float = 1.0    # ...and how long they are allowed to ring
	tilt: float = 0.0       # added presence shelf, dB
	air: float = 1.0        # the noise layers on top of the body


# ------------------------------------------------------------------- flippers


def _flipper_up_layer(L: Layer) -> np.ndarray:
	"""Solenoid clack + bat body knock. The up-stroke is the violent one: the coil
	slams the armature into its stop and the bat rings underneath."""
	gen = rng(L.seed)
	n = n_of(0.26 * L.dur)
	exc = _hit(n, gen, ms=1.3 * L.ms, lo=380.0, hi=8500.0 * L.hi, sharp=6.0,
	           click=0.85 * L.click)
	body = modal(exc, [
		(88.0, 0.052, 0.30),      # coil thunk through the cabinet
		(196.0, 0.075, 0.55),     # bat body
		(432.0, 0.044, 0.50),
		(883.0, 0.021, 0.55),
		(1615.0, 0.017 * L.top_tau, 0.70 * L.top),    # armature
		(2455.0, 0.0095 * L.top_tau, 0.75 * L.top),
		(3810.0, 0.0055 * L.top_tau, 0.45 * L.top),
	])
	air = lowpass(noise(n, gen), 5600.0) * perc_env(n, 0.0006, 0.009, 1.4) * (0.35 * L.air)
	return _finish(body + air, L.peak_db, wet=0.07, tilt_db=2.5 + L.tilt)


def flipper_up() -> np.ndarray:
	return _flipper_up_layer(Layer("flipper_up", -2.5))


def flipper_up_soft() -> np.ndarray:
	"""A tap: the coil barely gets moving and the armature never really cracks."""
	return _flipper_up_layer(Layer("flipper_up", -7.0, dur=0.78, ms=1.55, hi=0.44,
	                               click=0.38, top=0.40, top_tau=0.70, tilt=-2.5, air=0.42))


def flipper_up_hard() -> np.ndarray:
	"""Full stroke into the stop, with the bat already loaded."""
	return _flipper_up_layer(Layer("flipper_up", -2.0, dur=1.12, ms=0.70, hi=1.38,
	                               click=1.30, top=1.60, top_tau=1.32, tilt=2.5, air=1.55))


def flipper_down() -> np.ndarray:
	"""Return spring; the bat lands on the rest post. Duller, shorter, softer."""
	gen = rng("flipper_down")
	n = n_of(0.19)
	exc = _hit(n, gen, ms=1.8, lo=190.0, hi=4400.0, sharp=5.0, click=0.45)
	body = modal(exc, [
		(74.0, 0.045, 0.28),
		(178.0, 0.060, 0.58),
		(392.0, 0.034, 0.50),
		(762.0, 0.019, 0.46),
		(1455.0, 0.011, 0.42),
		(2300.0, 0.006, 0.20),
	])
	return _finish(body, -8.0, wet=0.06, tilt_db=1.5)


# ------------------------------------------------------------------- hardware


def _bumper_layer(L: Layer) -> np.ndarray:
	"""Pop bumper: skin slap on the ring, springy 180 Hz body, metal shimmer."""
	gen = rng(L.seed)
	n = n_of(0.44 * L.dur)
	exc = _hit(n, gen, ms=2.4 * L.ms, lo=850.0, hi=7000.0 * L.hi, sharp=4.5,
	           click=0.60 * L.click)
	body = modal(exc, [
		(180.0, 0.220, 0.80),     # the spring the spec asks for
		(432.0, 0.120, 0.55),
		(975.0, 0.055, 0.60),
		(2310.0, 0.026 * L.top_tau, 0.62 * L.top),
		(3160.0, 0.042 * L.top_tau, 0.35 * L.top),    # ring metal
		(5400.0, 0.014 * L.top_tau, 0.18 * L.top),
	])
	# the "pop": a fast pitch drop, the air the skirt shoves out of the way
	drop_n = n_of(0.055)
	pop = np.zeros(n)
	pop[:drop_n] = sine(expline(drop_n, 340.0, 148.0)) * exp_decay(drop_n, 0.016) ** 1.2
	slap = bandpass(noise(n, gen), 1400.0, 6000.0, order=2) * perc_env(n, 0.0008, 0.013, 1.6) * (1.1 * L.air)
	return _finish(body + 0.9 * pop + slap, L.peak_db, wet=0.09, rt60=0.36,
	               tilt_db=2.0 + L.tilt)


def bumper_hit() -> np.ndarray:
	return _bumper_layer(Layer("bumper_hit", -1.8))


def bumper_hit_soft() -> np.ndarray:
	"""A graze off the skirt: the spring answers, the ring never gets going."""
	return _bumper_layer(Layer("bumper_hit", -6.0, dur=0.74, ms=1.70, hi=0.34,
	                           click=0.32, top=0.28, top_tau=0.66, tilt=-3.0, air=0.32))


def bumper_hit_hard() -> np.ndarray:
	"""Straight into the skirt at speed — the whole ring assembly lets go."""
	return _bumper_layer(Layer("bumper_hit", -1.7, dur=1.10, ms=0.68, hi=1.48,
	                           click=1.35, top=1.65, top_tau=1.32, tilt=2.5, air=1.60))


def _sling_layer(L: Layer) -> np.ndarray:
	"""Slingshot: rubber snap into a small kicker plate. Snappier and higher than a bumper."""
	gen = rng(L.seed)
	n = n_of(0.24 * L.dur)
	exc = _hit(n, gen, ms=1.4 * L.ms, lo=700.0, hi=9500.0 * L.hi, sharp=6.0,
	           click=0.70 * L.click)
	body = modal(exc, [
		(142.0, 0.048, 0.30),
		(318.0, 0.080, 0.65),
		(792.0, 0.044, 0.60),
		(1885.0, 0.022 * L.top_tau, 0.70 * L.top),
		(3980.0, 0.011 * L.top_tau, 0.45 * L.top),
		(6300.0, 0.006 * L.top_tau, 0.22 * L.top),
	])
	twang_n = n_of(0.09)
	twang = np.zeros(n)
	twang[:twang_n] = sine(expline(twang_n, 262.0, 178.0)) * exp_decay(twang_n, 0.026) * 1.1
	return _finish(body + twang, L.peak_db, wet=0.07, tilt_db=2.0 + L.tilt)


def sling_hit() -> np.ndarray:
	return _sling_layer(Layer("sling_hit", -3.0))


def sling_hit_soft() -> np.ndarray:
	"""The ball leans on the rubber instead of hitting it; the plate hardly moves."""
	return _sling_layer(Layer("sling_hit", -7.5, dur=0.80, ms=1.60, hi=0.38,
	                          click=0.34, top=0.30, top_tau=0.66, tilt=-3.0, air=0.40))


def sling_hit_hard() -> np.ndarray:
	"""Hit square and thrown: the rubber cracks and the plate rings with it."""
	return _sling_layer(Layer("sling_hit", -2.4, dur=1.06, ms=0.60, hi=1.60,
	                          click=1.40, top=2.30, top_tau=1.45, tilt=4.0, air=1.70))


def wall_tap() -> np.ndarray:
	"""Ball glancing a rail. Tiny, high, and quiet — it fires constantly."""
	gen = rng("wall_tap")
	n = n_of(0.085)
	exc = _hit(n, gen, ms=0.6, lo=520.0, hi=7000.0, sharp=7.0, click=0.5)
	body = modal(exc, [
		(331.0, 0.028, 0.40),
		(762.0, 0.020, 0.70),
		(1833.0, 0.012, 0.75),
		(3405.0, 0.007, 0.45),
	])
	return _finish(body, -16.0, wet=0.05, rt60=0.24, taper=0.25)


# -------------------------------------------------------------------- plunger


def plunger_pull() -> np.ndarray:
	"""One ratchet detent. Four of these fire while the player charges, so keep it small."""
	gen = rng("plunger_pull")
	n = n_of(0.06)
	exc = _hit(n, gen, ms=0.7, lo=800.0, hi=9500.0, sharp=8.0, click=0.55)
	body = modal(exc, [
		(618.0, 0.0140, 0.50),
		(1180.0, 0.0100, 0.85),
		(2655.0, 0.0060, 0.55),
		(4310.0, 0.0035, 0.28),
	])
	return _finish(body, -9.0, wet=0.05, rt60=0.22, taper=0.25)


def plunger_launch() -> np.ndarray:
	"""Spring release: a dispersive boing, the rod hitting its stop, then the ball leaving."""
	gen = rng("plunger_launch")
	n = n_of(0.58)
	# spring: descending chirp through a comb, with the flutter a real coil has
	boing_n = n_of(0.40)
	t = t_axis(boing_n)
	f = 640.0 / (1.0 + t * 16.0) + 132.0
	flutter = 1.0 + 0.35 * np.sin(2.0 * np.pi * np.cumsum(expline(boing_n, 34.0, 7.0)) / SR)
	boing = np.sin(phase_of(f)) * exp_decay(boing_n, 0.115) * flutter
	boing = comb_ff(boing, 1.0 / 213.0, 0.72)
	boing = bandpass(boing, 120.0, 5200.0, order=2)
	spring = np.zeros(n)
	add_at(spring, boing, 0, 1.2)
	# rod slams the stop
	exc = _hit(n, gen, ms=2.0, lo=200.0, hi=6500.0, sharp=5.0, click=0.8)
	stop = modal(exc, [
		(86.0, 0.090, 0.35),
		(238.0, 0.070, 0.60),
		(521.0, 0.040, 0.55),
		(1150.0, 0.020, 0.55),
		(2480.0, 0.009, 0.35),
	])
	# ball departs
	tick = np.zeros(n)
	add_at(tick, modal(_hit(n_of(0.05), gen, ms=0.5, lo=1500.0, hi=9000.0, click=0.4),
	                   [(2100.0, 0.006, 0.6), (4600.0, 0.003, 0.35)]), n_of(0.012), 0.30)
	return _finish(spring + stop + tick, -3.0, wet=0.09, rt60=0.34, tilt_db=1.5)


# ------------------------------------------------------------------ ball life


def ball_spawn() -> np.ndarray:
	"""Trough kicks the ball into the shooter lane; it rattles down the rail."""
	gen = rng("ball_spawn")
	n = n_of(0.42)
	exc = _hit(n, gen, ms=2.6, lo=160.0, hi=5200.0, sharp=4.0, click=0.5)
	thunk = modal(exc, [
		(95.0, 0.080, 0.30),
		(232.0, 0.100, 0.60),
		(561.0, 0.055, 0.55),
		(1392.0, 0.025, 0.55),
		(2800.0, 0.012, 0.30),
	])
	roll_env = perc_env(n, 0.020, 0.150, 1.0)
	wobble = 1.0 + 0.5 * np.sin(2.0 * np.pi * 27.0 * t_axis(n)) * np.exp(-t_axis(n) * 6.0)
	roll = bandpass(noise(n, gen), 420.0, 3200.0, order=2) * roll_env * wobble * 0.9
	return _finish(thunk + roll, -6.0, wet=0.10, rt60=0.38, tilt_db=1.5)


def drain() -> np.ndarray:
	"""Hollow grate thud plus the low rumble of the ball disappearing under the playfield.

	The mid "grate rattle" layer is not decoration: without it the whole event lives
	below 300 Hz and the player loses the most important negative feedback in the game
	on any device without a woofer.
	"""
	gen = rng("drain")
	n = n_of(0.98)
	exc = _hit(n, gen, ms=4.5, lo=110.0, hi=2600.0, sharp=3.2, click=0.42)
	body = modal(exc, [
		(118.0, 0.260, 0.85),
		(262.0, 0.160, 0.60),
		(388.0, 0.100, 0.50),
		(690.0, 0.048, 0.45),
		(1310.0, 0.022, 0.35),
		(2400.0, 0.010, 0.22),
	])
	body = comb_ff(body, 1.0 / 86.0, 0.62)          # the hollow cabinet under the table
	grate = bandpass(noise(n, gen), 900.0, 3600.0, order=2)
	grate *= perc_env(n, 0.004, 0.045, 1.2) * (1.0 + 0.6 * np.sin(2.0 * np.pi * 41.0 * t_axis(n)))
	rumble = lowpass(noise(n, gen), 190.0, order=4) * perc_env(n, 0.010, 0.230, 0.9) * 3.0
	sag_n = n_of(0.30)
	sag = np.zeros(n)
	sag[:sag_n] = sine(expline(sag_n, 92.0, 49.0)) * exp_decay(sag_n, 0.085) * 1.8
	return _finish(body + rumble + sag + 0.55 * grate, -3.5, wet=0.12, rt60=0.5, tilt_db=1.0)


def nudge_thump() -> np.ndarray:
	"""A palm on the cabinet: mostly body, a little hand."""
	gen = rng("nudge_thump")
	n = n_of(0.34)
	exc = _hit(n, gen, ms=5.0, lo=55.0, hi=1600.0, sharp=3.0, click=0.25)
	body = modal(exc, [
		(68.0, 0.130, 0.85),
		(146.0, 0.085, 0.60),
		(301.0, 0.045, 0.45),
		(520.0, 0.024, 0.35),
		(940.0, 0.012, 0.25),
	])
	slap = bandpass(noise(n, gen), 900.0, 3600.0, order=2) * perc_env(n, 0.002, 0.011, 1.5) * 1.5
	return _finish(body + slap, -4.5, wet=0.08, rt60=0.36, tilt_db=1.0)


# ------------------------------------------------------------- bells and tilt


def _desk_bell(n: int, gen: np.random.Generator, f0: float = 1046.5,
               tail: float = 1.0) -> np.ndarray:
	"""Struck dome bell: inharmonic partials, two of them slightly detuned so the
	bell beats instead of sitting still."""
	exc = _hit(n, gen, ms=0.8, lo=1800.0, hi=12000.0, sharp=9.0, click=0.9)
	partials = [
		(1.000, 0.50, 0.90), (1.0016, 0.47, 0.62),   # beating pair
		(2.021, 0.38, 0.55), (2.028, 0.35, 0.30),
		(2.795, 0.27, 0.44),
		(4.112, 0.19, 0.26),
		(5.431, 0.14, 0.19),
		(8.137, 0.09, 0.11),
	]
	spec = [(f0 * r, tau * tail, g) for r, tau, g in partials]
	bell = modal(exc, spec)
	strike = modal(exc, [(f0 * 0.19, 0.045, 0.16), (f0 * 3.4, 0.012, 0.12)])
	return bell + strike


def tilt_warning() -> np.ndarray:
	"""Single desk bell — the warning you get before the machine gives up on you."""
	gen = rng("tilt_warning")
	n = n_of(2.05)
	return _finish(_desk_bell(n, gen, 1046.5, 1.0), -3.0, wet=0.16, rt60=0.55,
	               predelay=0.011, taper=0.22)


def tilt() -> np.ndarray:
	"""Bell, then the machine dies: a detuned pair sagging an octave and a half in 700 ms."""
	gen = rng("tilt")
	n = n_of(1.4)
	out = _desk_bell(n, gen, 1046.5, 0.42) * 0.85

	fall_n = n_of(0.70)
	start = n_of(0.13)
	f_lo = expline(fall_n, 332.0, 62.0)
	pair = (np.sin(phase_of(f_lo)) + np.sin(phase_of(f_lo * 1.0081)) * 0.9
	        + 0.30 * np.sin(phase_of(f_lo * 2.0)))
	# the motor spinning down, and the tone going dark with it
	am = 1.0 + 0.28 * np.sin(2.0 * np.pi * np.cumsum(expline(fall_n, 26.0, 5.0)) / SR)
	env = np.concatenate([
		0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, n_of(0.02))),
		np.ones(fall_n - n_of(0.02)),
	]) * np.linspace(1.0, 0.0, fall_n) ** 1.6
	fall = np.clip(pair * am * env, -3.0, 3.0)
	fall = sweep_filter(fall, expline(fall_n, 3200.0, 300.0), q=0.9, kind="lp")
	add_at(out, fall, start, 1.6)
	return _finish(out, -2.0, wet=0.13, rt60=0.5, taper=0.20)


def knocker() -> np.ndarray:
	"""The replay knocker: a solenoid hammer against the inside of the cabinet.

	Biggest transient in the set — crest factor is the whole point, so it gets no
	compression and the tightest exciter of any event.
	"""
	gen = rng("knocker")
	n = n_of(0.40)
	exc = _hit(n, gen, ms=1.1, lo=260.0, hi=9500.0, sharp=7.0, click=1.0, click_ms=0.14)
	box = modal(exc, [
		(92.0, 0.095, 0.60),
		(176.0, 0.070, 0.70),
		(331.0, 0.050, 0.65),
		(642.0, 0.030, 0.62),
		(1255.0, 0.018, 0.60),
		(2412.0, 0.010, 0.50),
		(4180.0, 0.006, 0.32),
	])
	crack = bandpass(noise(n, gen), 2400.0, 7200.0, order=2) * perc_env(n, 0.0004, 0.0055, 1.8) * 2.2
	return _finish(box + crack, -1.5, wet=0.12, rt60=0.42, predelay=0.010, tilt_db=2.0)


def cash_tick() -> np.ndarray:
	"""Mechanical counter wheel advancing one digit. Fires per dollar, so: 38 ms, gentle."""
	gen = rng("cash_tick")
	n = n_of(0.038)
	exc = _hit(n, gen, ms=0.30, lo=1100.0, hi=9500.0, sharp=10.0, click=0.60, click_ms=0.10)
	body = modal(exc, [
		(942.0, 0.0090, 0.50),
		(1824.0, 0.0055, 0.85),
		(3452.0, 0.0035, 0.50),
		(6210.0, 0.0020, 0.22),
	])
	return _finish(body, -11.0, wet=0.03, rt60=0.18, taper=0.30)


# --------------------------------------------------------------------- chimes


def _chime(f0: float, seed: str, tail: float) -> np.ndarray:
	"""Gottlieb-style plated bar chime: struck bar partials (1 : 2.76 : 5.40 : 8.93)
	with a mallet click and a slow beat between two nearly-coincident fundamentals."""
	gen = rng(seed)
	n = n_of(2.3)
	exc = _hit(n, gen, ms=0.7, lo=1400.0, hi=11000.0, sharp=8.0, click=0.75)
	partials = [
		(1.0000, 0.50, 1.00),
		(1.0021, 0.47, 0.55),     # beating partner -> the chime "breathes"
		(2.7580, 0.26, 0.42),
		(2.7640, 0.24, 0.21),
		(5.4040, 0.14, 0.22),
		(8.9330, 0.08, 0.12),
		(13.340, 0.04, 0.06),
	]
	spec = [(f0 * r, tau * tail, g) for r, tau, g in partials]
	bar = modal(exc, spec)
	# the plate the bar is bolted to, plus the mallet itself
	plate = modal(exc, [(f0 * 0.503, 0.10, 0.09), (f0 * 1.99, 0.055, 0.06)])
	mallet = bandpass(noise(n, gen), 3000.0, 9000.0, order=2) * perc_env(n, 0.0004, 0.004, 2.0) * 0.55
	return _finish(bar + plate + mallet, -4.0, wet=0.15, rt60=0.6, predelay=0.012, taper=0.22)


def chime_a() -> np.ndarray:
	return _chime(587.33, "chime_a", 1.00)   # D5


def chime_b() -> np.ndarray:
	return _chime(698.46, "chime_b", 0.93)   # F5


def chime_c() -> np.ndarray:
	return _chime(880.00, "chime_c", 0.86)   # A5


# ============================================ wave 2 — mechanics (spec §1) =====


def rollover_click() -> np.ndarray:
	"""Leaf switch under a lane star: two thin bronze blades touching.

	A rollover fires several times a ball, often two in a row, so this is deliberately
	one of the quietest things in the set — it is punctuation, not an event.
	"""
	gen = rng("rollover_click")
	n = n_of(0.048)
	exc = _hit(n, gen, ms=0.35, lo=900.0, hi=9000.0, sharp=11.0, click=0.45, click_ms=0.09)
	blades = modal(exc, [
		(1465.0, 0.0075, 0.85),      # the blade pair itself
		(2870.0, 0.0045, 0.60),
		(5240.0, 0.0022, 0.30),
		(408.0, 0.0130, 0.22),       # the plastic lane guide it is screwed to
	])
	return _finish(blades, -12.0, wet=0.04, rt60=0.18, taper=0.30)


def spinner_tick() -> np.ndarray:
	"""One blade of the spinner passing its wire stop. Fires per segment at high rate,
	so: 30 ms, no low end at all, and the smallest peak in the game."""
	gen = rng("spinner_tick")
	n = n_of(0.030)
	exc = _hit(n, gen, ms=0.22, lo=1800.0, hi=12000.0, sharp=13.0, click=0.55, click_ms=0.07)
	wire = modal(exc, [
		(2640.0, 0.0055, 0.70),
		(4190.0, 0.0032, 0.85),
		(6980.0, 0.0018, 0.45),
		(9750.0, 0.0011, 0.20),
	])
	return _finish(wire, -14.0, wet=0.03, rt60=0.15, tilt_db=2.0, taper=0.32)


def _drop_target(n: int, gen: np.random.Generator, detune: float = 1.0) -> np.ndarray:
	"""One plastic drop target falling into its housing: face slap, then the housing."""
	exc = _hit(n, gen, ms=1.1, lo=320.0, hi=8000.0, sharp=6.0, click=0.7)
	return unit(modal(exc, [
		(214.0 * detune, 0.052, 0.55),      # steel housing
		(496.0 * detune, 0.034, 0.60),
		(1128.0 * detune, 0.019, 0.70),     # the target face
		(2340.0 * detune, 0.010, 0.55),
		(4260.0 * detune, 0.005, 0.28),
	]))


def drop_clack() -> np.ndarray:
	"""A single drop target going down."""
	gen = rng("drop_clack")
	n = n_of(0.15)
	body = _drop_target(n, gen)
	spring = np.zeros(n)
	sk = n_of(0.035)
	spring[:sk] = sine(expline(sk, 780.0, 430.0)) * exp_decay(sk, 0.010) * 0.5
	return _finish(body + spring, -6.5, wet=0.06, rt60=0.24, tilt_db=1.5, taper=0.24)


def drop_bank_down() -> np.ndarray:
	"""The third target of a bank falling — the bank is complete.

	Three targets do not fall at once; the ball knocks the last one and the bank's own
	linkage drags the rest with it a few milliseconds later. That stagger is the whole
	difference between "a bank went down" and "something broke".
	"""
	gen = rng("drop_bank_down")
	n = n_of(0.52)
	out = np.zeros(n)
	tn = n_of(0.20)
	for i, (delay, detune, gain) in enumerate([(0.0, 1.00, 1.00), (0.013, 0.94, 0.78),
	                                           (0.027, 1.07, 0.66)]):
		add_at(out, _drop_target(tn, gen, detune), n_of(delay), gain)
	# the linkage bar bottoming out under the playfield — the meat of it
	exc = _hit(n, gen, ms=3.2, lo=90.0, hi=3200.0, sharp=3.6, click=0.55)
	thunk = unit(modal(exc, [
		(96.0, 0.105, 0.60),
		(188.0, 0.080, 0.65),
		(377.0, 0.048, 0.60),
		(742.0, 0.026, 0.50),
		(1490.0, 0.013, 0.34),
	]))
	add_at(out, thunk, n_of(0.020), 1.15)
	rattle = unit(bandpass(noise(n, gen), 700.0, 4200.0, order=2)
	              * perc_env(n, 0.008, 0.055, 1.1))
	return _finish(out + 0.16 * rattle, -3.0, wet=0.09, rt60=0.36, tilt_db=0.5)


def drop_bank_reset() -> np.ndarray:
	"""The reset solenoid dragging the bank back up: ratchet, ratchet, latch.

	The ticks accelerate — a solenoid pulls hardest at the end of its stroke — and the
	latch that catches the bank at the top is the punctuation the player listens for.
	"""
	gen = rng("drop_bank_reset")
	n = n_of(0.46)
	out = np.zeros(n)
	tick_n = n_of(0.045)
	t0 = 0.012
	gap = 0.048
	for i in range(7):
		exc = _hit(tick_n, gen, ms=0.45, lo=900.0, hi=9500.0, sharp=9.0, click=0.5)
		tick = unit(modal(exc, [
			(842.0 * (1.0 + 0.02 * i), 0.0090, 0.55),
			(1690.0 * (1.0 + 0.02 * i), 0.0055, 0.80),
			(3420.0, 0.0030, 0.45),
			(6100.0, 0.0016, 0.20),
		]))
		add_at(out, tick, n_of(t0), 0.32 + 0.045 * i)
		t0 += gap
		gap *= 0.86                       # the pull speeds up as the armature closes
	# the bank latching home
	latch_n = n_of(0.22)
	exc = _hit(latch_n, gen, ms=2.0, lo=180.0, hi=6000.0, sharp=5.0, click=0.85)
	latch = unit(modal(exc, [
		(126.0, 0.070, 0.55),
		(272.0, 0.050, 0.60),
		(588.0, 0.030, 0.60),
		(1240.0, 0.017, 0.55),
		(2610.0, 0.008, 0.35),
	]))
	add_at(out, latch, n_of(t0 + 0.010), 1.00)
	return _finish(out, -5.5, wet=0.07, rt60=0.30, tilt_db=1.5)


def kickback() -> np.ndarray:
	"""Outlane kickback: a big coil throwing the ball back up the lane.

	The biggest mechanical event after the knocker, and lower than it — the knocker is
	a hammer on a hollow box at head height, this is a solenoid in the bottom corner of
	a cabinet full of wood.
	"""
	gen = rng("kickback")
	n = n_of(0.52)
	exc = _hit(n, gen, ms=1.6, lo=140.0, hi=7500.0, sharp=5.5, click=0.95, click_ms=0.16)
	# Tuned like the knocker's box rather than an octave under it: a phone speaker
	# reproduces nothing below ~400 Hz, so a kickback voiced at 58 Hz is a kickback the
	# player never hears. The weight has to live in the 120-400 Hz band and the crack
	# above it, with just enough sub to be felt on a device that has any.
	boom = unit(modal(exc, [
		(67.0, 0.140, 0.42),          # the cabinet, felt more than heard
		(122.0, 0.115, 0.72),
		(236.0, 0.078, 0.80),
		(461.0, 0.050, 0.68),
		(905.0, 0.028, 0.60),
		(1815.0, 0.015, 0.52),
		(3410.0, 0.007, 0.34),
	]))
	# the coil's own thump: a fast pitch collapse as the armature slams home
	drop_n = n_of(0.09)
	slam = np.zeros(n)
	slam[:drop_n] = sine(expline(drop_n, 232.0, 78.0)) * exp_decay(drop_n, 0.026) ** 1.1
	# the ball leaving, hard
	launch = np.zeros(n)
	add_at(launch, unit(modal(_hit(n_of(0.07), gen, ms=0.6, lo=1400.0, hi=9500.0, click=0.5),
	                          [(1980.0, 0.008, 0.6), (4350.0, 0.004, 0.4)])), n_of(0.018), 0.30)
	crack = unit(bandpass(noise(n, gen), 1800.0, 6800.0, order=2)
	             * perc_env(n, 0.0006, 0.0075, 1.7))
	air = unit(lowpass(noise(n, gen), 4200.0) * perc_env(n, 0.001, 0.016, 1.3))
	return _finish(boom + 0.42 * slam + launch + 0.34 * crack + 0.18 * air, -1.8,
	               wet=0.11, rt60=0.44, predelay=0.010, tilt_db=2.0)


def orbit_whoosh() -> np.ndarray:
	"""The ball taking the full orbit: air past the wire, and the lane going by.

	Doppler-ish by construction — the band centre rises as the ball comes at you and
	falls as it leaves, and the level follows the same arc a beat behind. No pitched
	material at all, so it can play under anything.
	"""
	gen = rng("orbit_whoosh")
	n = n_of(0.40)
	t = t_axis(n)
	arc = np.sin(np.pi * np.clip(t / (n / SR), 0.0, 1.0)) ** 0.85
	centre = 430.0 + 2350.0 * arc ** 1.35
	air = sweep_filter(noise(n, gen), centre, q=1.35, kind="bp")
	# A resonant bandpass on its own still passes plenty of hiss two octaves up; the
	# tracking lowpass is what turns "noise with a filter on it" into moving air.
	air = sweep_filter(air, centre * 1.35, q=0.72, kind="lp")
	air = lowpass(air, 6200.0, order=2)
	air = unit(air * arc * (1.0 + 0.10 * np.sin(2.0 * np.pi * 7.0 * t)))
	# the rail underneath: a narrow resonance that tracks with it, an octave down
	rail = unit(sweep_filter(noise(n, gen), centre * 0.5, q=4.0, kind="bp") * arc)
	# and the wire form ringing very faintly as the ball passes each post
	posts = np.zeros(n)
	for i, frac in enumerate([0.18, 0.40, 0.62, 0.83]):
		ping = unit(modal(_hit(n_of(0.04), gen, ms=0.35, lo=2000.0, hi=11000.0, click=0.4),
		                  [(3150.0 + 220.0 * i, 0.006, 0.55), (5400.0, 0.003, 0.3)]))
		add_at(posts, ping, int(frac * n),
		       0.16 * float(np.interp(frac, [0, 0.5, 1], [0.5, 1.0, 0.5])))
	out = air + 0.55 * rail + posts
	return _finish(out, -6.0, wet=0.10, rt60=0.40, tilt_db=-1.0, taper=0.10)


# ============================================== wave 2 — fiction (spec §1) =====


def _register_bell(n: int, gen: np.random.Generator, f0: float = 1320.0,
                   tail: float = 1.0) -> np.ndarray:
	"""The bell inside a cash register: small, bright, struck hard, dies fast."""
	exc = _hit(n, gen, ms=0.5, lo=2200.0, hi=13000.0, sharp=10.0, click=0.95)
	partials = [
		(1.000, 0.42, 1.00), (1.0027, 0.39, 0.55),
		(2.412, 0.22, 0.50), (2.421, 0.20, 0.26),
		(3.905, 0.13, 0.32),
		(5.836, 0.075, 0.18),
		(8.410, 0.042, 0.10),
	]
	return unit(modal(exc, [(f0 * r, tau * tail, g) for r, tau, g in partials]))


def _coin_pour(n: int, gen: np.random.Generator, count: int, spread: float,
               start: float = 0.0, f_lo: float = 1400.0, f_hi: float = 3200.0,
               decay: float = 1.0) -> np.ndarray:
	"""``count`` coins landing on each other over ``spread`` seconds, thinning out."""
	out = np.zeros(n)
	ping_n = n_of(0.13)
	for i in range(count):
		frac = (i / max(count - 1, 1)) ** 0.72          # dense at first, then scattered
		at = start + frac * spread + float(gen.uniform(-0.004, 0.004))
		f0 = float(gen.uniform(f_lo, f_hi))
		gain = (1.0 - 0.75 * frac) ** decay * float(gen.uniform(0.55, 1.0))
		add_at(out, _metal_ping(ping_n, gen, f0, tau=float(gen.uniform(0.035, 0.085))),
		       n_of(at), gain)
	return unit(out)


def storefront_collect() -> np.ndarray:
	"""Cha-ching. The single most-taught association in the game (docs/08 §3), so it
	gets the most construction: drawer mechanism, the bell struck twice, the drawer
	hitting its stop, and the till's coins jumping as it lands."""
	gen = rng("storefront_collect")
	n = n_of(1.10)
	out = np.zeros(n)
	# "cha" — the mechanism releasing and the drawer starting to move
	exc = _hit(n_of(0.16), gen, ms=2.2, lo=260.0, hi=7000.0, sharp=6.0, click=0.6)
	add_at(out, unit(modal(exc, [
		(196.0, 0.038, 0.50), (455.0, 0.026, 0.55),
		(1010.0, 0.014, 0.60), (2180.0, 0.008, 0.35),
	])), 0, 0.62)
	# "-ching" — the bell, struck twice, the second lighter
	add_at(out, _register_bell(n_of(0.9), gen, 1320.0, 1.00), n_of(0.045), 1.00)
	add_at(out, _register_bell(n_of(0.7), gen, 1332.0, 0.80), n_of(0.122), 0.46)
	# the drawer runs out and hits its stop
	stop_n = n_of(0.30)
	sexc = _hit(stop_n, gen, ms=3.0, lo=110.0, hi=3600.0, sharp=4.0, click=0.5)
	add_at(out, unit(modal(sexc, [
		(102.0, 0.086, 0.55), (208.0, 0.060, 0.60), (412.0, 0.036, 0.50),
		(824.0, 0.020, 0.38), (1660.0, 0.010, 0.24),
	])), n_of(0.185), 0.88)
	# and the money in it
	add_at(out, _coin_pour(n_of(0.75), gen, 16, 0.34, f_lo=1900.0, f_hi=4600.0),
	       n_of(0.205), 0.34)
	return _finish(out, -2.6, wet=0.13, rt60=0.46, predelay=0.011, tilt_db=1.5, taper=0.16)


def laundromat_wash() -> np.ndarray:
	"""A front-loader mid-cycle: water sloshing round a steel drum, then draining back.

	The tumble is what sells it — a slow swell in the band centre twice over the sound,
	because the drum turns twice, and a comb at the drum's own resonance underneath.
	"""
	gen = rng("laundromat_wash")
	n = n_of(0.50)
	t = t_axis(n)
	dur = n / SR
	arc = np.sin(np.pi * np.clip(t / dur, 0.0, 1.0)) ** 0.7
	tumble = 0.5 + 0.5 * np.sin(2.0 * np.pi * 3.6 * t - np.pi / 2.0)
	centre = 300.0 + 780.0 * (0.35 + 0.65 * tumble) * (0.5 + 0.5 * arc)
	water = sweep_filter(noise(n, gen), centre, q=0.85, kind="bp")
	# Water is a low sound. Everything above about 2 kHz here is the noise source
	# showing through, and it is the difference between a wash cycle and a hi-hat.
	water = lowpass(water, 2100.0, order=4)
	water *= arc * (0.55 + 0.45 * tumble)
	water = unit(comb_ff(water, 1.0 / 128.0, 0.55))    # the drum
	# bubbles: small low resonances popping as air comes up through the water
	bubbles = np.zeros(n)
	for i in range(9):
		at = float(gen.uniform(0.05, 0.42))
		f0 = float(gen.uniform(260.0, 900.0))
		bn = n_of(0.05)
		blip = sine(expline(bn, f0 * 0.72, f0 * 1.45)) * exp_decay(bn, 0.011)
		add_at(bubbles, blip, n_of(at), float(gen.uniform(0.25, 0.6)))
	rumble = unit(lowpass(noise(n, gen), 380.0, order=4) * arc)
	out = water + 0.22 * unit(bubbles) + 0.30 * rumble
	return _finish(out, -8.0, wet=0.12, rt60=0.42, tilt_db=-2.0, taper=0.14)


def bribe_paid() -> np.ndarray:
	"""A stack of bills counted into a hand, and the radio letting it go.

	Two halves that have to stay separate: the riffle is close and dry, the squelch is
	small-speaker and band-limited, because it comes out of a car window.
	"""
	gen = rng("bribe_paid")
	n = n_of(0.82)
	out = np.zeros(n)
	# riffle: bill edges snapping past a thumb, accelerating
	at = 0.005
	gap = 0.036
	for i in range(13):
		flick = _paper(n_of(0.045), gen, 1500.0, 7500.0, tau=0.0045, grip=0.35)
		add_at(out, flick, n_of(at), 0.30 + 0.26 * (i / 12.0))
		at += gap
		gap *= 0.965
	out += 0.16 * _paper(n, gen, 900.0, 5200.0, tau=0.20, grip=0.6)
	# police radio: a squelch tail and a two-tone chirp through a 300-3000 Hz speaker
	radio_n = n_of(0.34)
	chirp = sine(expline(radio_n, 1380.0, 760.0)) * asr_env(radio_n, 0.008, 0.05, 1.4)
	chirp += 0.5 * sine(expline(radio_n, 2070.0, 1140.0)) * asr_env(radio_n, 0.010, 0.05, 1.4)
	hiss = bandpass(noise(radio_n, gen), 900.0, 3400.0, order=2) * perc_env(radio_n, 0.002, 0.030, 1.3)
	radio = bandpass(chirp + 0.9 * hiss, 340.0, 2900.0, order=4)
	radio = comb_ff(radio, 1.0 / 470.0, 0.45)          # the little speaker's box
	# Saturation is what a two-inch speaker in a car door does, but it also flattens the
	# crest factor, and a squelch loud enough to set this file's peak would leave a bribe
	# the loudest thing in the game by RMS. The riffle is the event; the radio is the
	# punctuation, so it stays under it.
	radio = unit(np.tanh(radio * 1.5))
	add_at(out, radio, n_of(0.46), 0.55)
	# Peaks below the ladder's usual level for its rank, on purpose: the peak ladder is
	# calibrated on transients with a 18-22 dB crest, and a riffle is a continuous zip
	# with about half that. Normalised to the same peak as its neighbours it would be
	# the loudest thing in the game, which is not what a bribe is.
	return _finish(out, -10.0, wet=0.08, rt60=0.34, tilt_db=-1.0)


def _cell_door(n: int, gen: np.random.Generator, gain_low: float = 1.0) -> np.ndarray:
	"""Barred steel door into a steel frame. Long, ringing, unpleasant."""
	exc = _hit(n, gen, ms=2.6, lo=90.0, hi=8000.0, sharp=4.5, click=0.9, click_ms=0.13)
	clank = modal(exc, [
		(112.0, 0.230 * gain_low, 0.62),
		(247.0, 0.170, 0.55),
		(431.0, 0.135, 0.60),
		(795.0, 0.095, 0.62),
		(1523.0, 0.060, 0.58),
		(2870.0, 0.032, 0.42),
		(4610.0, 0.018, 0.26),
	])
	bolt = modal(_hit(n, gen, ms=0.5, lo=1500.0, hi=11000.0, sharp=9.0, click=0.6),
	             [(2240.0, 0.011, 0.5), (3980.0, 0.006, 0.4), (6900.0, 0.003, 0.2)])
	return unit(unit(clank) + 0.35 * unit(bolt))


def guy_pinched() -> np.ndarray:
	"""Mugshot: the flash goes off, then the door closes behind him."""
	gen = rng("guy_pinched")
	n = n_of(0.70)
	out = np.zeros(n)
	# flashbulb: a hard bright pop, then the capacitor whining back up to charge
	pop_n = n_of(0.10)
	pop = _hit(pop_n, gen, ms=0.9, lo=1200.0, hi=14000.0, sharp=8.0, click=1.0, click_ms=0.10)
	pop = unit(modal(pop, [(1880.0, 0.016, 0.7), (3640.0, 0.009, 0.8), (7100.0, 0.005, 0.5)]))
	add_at(out, pop, 0, 0.62)
	whine_n = n_of(0.30)
	whine = unit(sine(expline(whine_n, 3900.0, 8200.0)) * expline(whine_n, 0.22, 0.02)
	             + 0.4 * sine(expline(whine_n, 7800.0, 16400.0)) * expline(whine_n, 0.10, 0.01))
	add_at(out, whine, n_of(0.030), 0.10)
	add_at(out, _cell_door(n_of(0.62), gen), n_of(0.135), 1.00)
	return _finish(out, -3.2, wet=0.14, rt60=0.62, predelay=0.013, tilt_db=1.0, taper=0.16)


def _stamp(n: int, gen: np.random.Generator, punch: float = 1.0) -> np.ndarray:
	"""Something wooden driven into something soft, on a desk with a drawer in it."""
	exc = _hit(n, gen, ms=2.4, lo=120.0, hi=5200.0, sharp=4.2, click=0.65)
	body = modal(exc, [
		(96.0, 0.075, 0.60),           # the desk
		(207.0, 0.050, 0.55),
		(423.0, 0.028, 0.45),
		(880.0, 0.015, 0.38),
		(1810.0, 0.008, 0.26),
	])
	tk = modal(_hit(n, gen, ms=0.4, lo=1600.0, hi=11000.0, sharp=9.0, click=0.7),
	           [(2480.0, 0.007, 0.6), (4700.0, 0.004, 0.4)])
	return unit(unit(body) + punch * 0.45 * unit(tk))


def bail_paid() -> np.ndarray:
	"""The clerk stamps the release, you put the money on the counter."""
	gen = rng("bail_paid")
	n = n_of(0.72)
	out = _stamp(n, gen, punch=0.7)
	out += 0.13 * _paper(n, gen, 1200.0, 6000.0, tau=0.05, grip=0.4)
	add_at(out, _coin_pour(n_of(0.5), gen, 6, 0.16, f_lo=1400.0, f_hi=2900.0), n_of(0.19), 0.20)
	return _finish(out, -4.5, wet=0.11, rt60=0.44, tilt_db=0.5)


def safe_open() -> np.ndarray:
	"""The offline-collect banner: a heavy door swinging, and what is behind it.

	The creak is a relaxation oscillation — the hinge grabs and slips a few hundred
	times a second — so it is built as a narrow resonance swept by a jittering envelope,
	not as noise with a filter on it. That is why it rises in pitch as it slows down.
	"""
	gen = rng("safe_open")
	n = n_of(1.65)
	out = np.zeros(n)
	# handle turning
	add_at(out, unit(modal(_hit(n_of(0.2), gen, ms=1.4, lo=400.0, hi=8000.0, sharp=6.0, click=0.5),
	                       [(318.0, 0.030, 0.5), (742.0, 0.018, 0.6), (1630.0, 0.010, 0.4)])),
	       0, 0.42)
	# creak
	creak_n = n_of(0.62)
	ct = t_axis(creak_n)
	grab = lowpass(noise(creak_n, gen), 34.0, order=2)
	grab /= float(np.max(np.abs(grab))) + 1e-12
	slip = expline(creak_n, 520.0, 1180.0) * (1.0 + 0.28 * grab)
	creak = sweep_filter(noise(creak_n, gen), slip, q=13.0, kind="bp")
	creak *= asr_env(creak_n, 0.09, 0.20, 1.3) * (0.45 + 0.55 * (0.5 + 0.5 * grab))
	creak = unit(highpass(creak, 260.0, order=2))
	add_at(out, creak, n_of(0.13), 0.72)
	# and the door landing on its stop
	clunk_n = n_of(0.55)
	cexc = _hit(clunk_n, gen, ms=4.0, lo=60.0, hi=3000.0, sharp=3.2, click=0.55)
	add_at(out, unit(modal(cexc, [
		(58.0, 0.170, 0.48), (112.0, 0.135, 0.72), (218.0, 0.088, 0.68),
		(428.0, 0.055, 0.55), (840.0, 0.028, 0.40), (1620.0, 0.014, 0.26),
	])), n_of(0.76), 1.00)
	add_at(out, _coin_pour(n_of(0.7), gen, 11, 0.30, f_lo=1600.0, f_hi=3900.0),
	       n_of(0.86), 0.26)
	return _finish(out, -3.5, wet=0.15, rt60=0.70, predelay=0.014, taper=0.18)


def stamp_thunk() -> np.ndarray:
	"""Ledger purchase: a pin punched into cork through a card.

	Cork is the point — it is almost all damping, so the modes are wide and short and
	the sound is over before it rings. If this rings, it is a nail in a wall instead.
	"""
	gen = rng("stamp_thunk")
	n = n_of(0.30)
	out = _stamp(n, gen, punch=1.0)
	cork = unit(lowpass(noise(n, gen), 900.0, order=2) * perc_env(n, 0.0008, 0.014, 1.5))
	out += 0.55 * cork
	out += 0.26 * _paper(n, gen, 1800.0, 7500.0, tau=0.012, grip=0.3)
	return _finish(out, -5.0, wet=0.07, rt60=0.30, taper=0.22)


def paper_slip() -> np.ndarray:
	"""A slip of paper pulled across a desk."""
	gen = rng("paper_slip")
	n = n_of(0.34)
	t = t_axis(n)
	arc = np.sin(np.pi * np.clip(t / (n / SR), 0.0, 1.0)) ** 0.8
	slide = _paper(n, gen, 1800.0, 9000.0, tau=0.40, grip=0.85) * arc
	slide = sweep_filter(slide, 2400.0 + 2600.0 * arc, q=0.8, kind="bp")
	return _finish(slide, -13.0, wet=0.06, rt60=0.26, tilt_db=1.5, taper=0.22)


def job_done() -> np.ndarray:
	"""A job comes back done: a two-note brass "bup!" and the bell on the desk."""
	gen = rng("job_done")
	n = n_of(0.62)
	out = np.zeros(n)
	add_at(out, _brass(587.33, n_of(0.13), gen, 0.95, rip_cents=90.0,
	                   attack=0.012, release=0.055), 0, 1.0)          # D5
	add_at(out, _brass(880.00, n_of(0.20), gen, 1.00, rip_cents=45.0,
	                   attack=0.010, release=0.075), n_of(0.085), 1.0)  # A5
	add_at(out, unit(_desk_bell(n_of(0.5), gen, 1760.0, 0.34)), n_of(0.10), 0.26)
	return _finish(out, -4.0, wet=0.13, rt60=0.48, predelay=0.011, tilt_db=1.0, taper=0.18)


def skill_shot_ding() -> np.ndarray:
	"""Two small bright bells a fifth apart. Deliberately an octave above the tilt
	warning and half its length — the two must never be confused."""
	gen = rng("skill_shot_ding")
	n = n_of(1.15)
	out = unit(_desk_bell(n, gen, 1174.66, 0.30)) * 0.80              # D6
	add_at(out, unit(_desk_bell(n_of(1.0), gen, 1760.00, 0.34)), n_of(0.088), 1.0)   # A6
	return _finish(out, -3.5, wet=0.17, rt60=0.60, predelay=0.012, tilt_db=1.5, taper=0.20)


def _combo_blip(f0: float, seed: str, level_db: float) -> np.ndarray:
	"""A struck bar the size of a matchstick: the combo family.

	Tuned deliberately to the chime pitches an octave up (D-F-A) so a combo landing on
	top of a Wire draw is a chord and not a mistake. The fundamental carries most of the
	energy — the whole point is that this reads as a *pitch*.
	"""
	gen = rng(seed)
	n = n_of(0.30)
	exc = _hit(n, gen, ms=0.4, lo=1500.0, hi=12000.0, sharp=9.0, click=0.6)
	bar = unit(modal(exc, [
		(f0, 0.130, 1.00),
		(f0 * 1.0018, 0.120, 0.42),
		(f0 * 2.758, 0.045, 0.30),
		(f0 * 5.404, 0.020, 0.13),
	]))
	# a whisper of a bend into the note, over before the pitch can be measured
	bk = n_of(0.010)
	bend = np.zeros(n)
	bend[:bk] = sine(expline(bk, f0 * 0.62, f0 * 0.98)) * exp_decay(bk, 0.004)
	return _finish(bar + 0.18 * unit(bend), level_db, wet=0.11, rt60=0.42,
	               predelay=0.010, tilt_db=1.0, taper=0.24)


def combo_2() -> np.ndarray:
	return _combo_blip(1174.66, "combo_2", -5.0)      # D6


def combo_3() -> np.ndarray:
	return _combo_blip(1396.91, "combo_3", -4.6)      # F6


def combo_4() -> np.ndarray:
	return _combo_blip(1760.00, "combo_4", -4.2)      # A6


def headline_sting() -> np.ndarray:
	"""The morning paper: seven keys, the carriage coming back, the sheet pulled out."""
	gen = rng("headline_sting")
	n = n_of(0.90)
	out = np.zeros(n)
	at = 0.010
	for i in range(7):
		key_n = n_of(0.10)
		exc = _hit(key_n, gen, ms=0.7, lo=600.0, hi=10000.0, sharp=8.0, click=0.75)
		# typebar into the platen: a hard rubber roller in a steel frame
		key = unit(modal(exc, [
			(268.0, 0.024, 0.42),
			(915.0 * (1.0 + 0.03 * (i % 3)), 0.014, 0.65),
			(2110.0, 0.008, 0.62),
			(4380.0, 0.004, 0.30),
			(7900.0, 0.002, 0.10),
		]))
		add_at(out, key, n_of(at), 0.72 + 0.22 * float(gen.uniform(0.0, 1.0)))
		at += 0.058 + float(gen.uniform(-0.011, 0.014))
	# carriage return: the bell, then the carriage running back on its rail
	add_at(out, unit(_desk_bell(n_of(0.5), gen, 2093.0, 0.26)), n_of(0.505), 0.62)
	ret_n = n_of(0.22)
	rail = sweep_filter(noise(ret_n, gen), expline(ret_n, 2600.0, 900.0), q=1.1, kind="bp")
	rail = unit(rail * asr_env(ret_n, 0.012, 0.09, 1.3))
	add_at(out, rail, n_of(0.545), 0.30)
	add_at(out, unit(modal(_hit(n_of(0.1), gen, ms=1.2, lo=300.0, hi=6000.0, click=0.6),
	                       [(184.0, 0.030, 0.5), (492.0, 0.018, 0.5), (1180.0, 0.010, 0.4)])),
	       n_of(0.700), 0.72)
	# and the sheet coming out
	whoosh_n = n_of(0.24)
	sheet = _paper(whoosh_n, gen, 1400.0, 9500.0, tau=0.30, grip=0.7)
	sheet *= np.sin(np.pi * np.linspace(0.0, 1.0, whoosh_n)) ** 0.8
	add_at(out, unit(sweep_filter(sheet, expline(whoosh_n, 1400.0, 4200.0), q=0.8, kind="bp")),
	       n_of(0.655), 0.34)
	return _finish(out, -3.5, wet=0.12, rt60=0.44, tilt_db=1.5, taper=0.14)


def rankup_fanfare() -> np.ndarray:
	"""Three notes and a drum. Layers over the knocker, so it starts a beat behind it
	and lives above 300 Hz — the knocker owns the bottom of that moment."""
	gen = rng("rankup_fanfare")
	n = n_of(2.00)
	out = np.zeros(n)
	# D4 - A4 - D5, the oldest fanfare there is, then the chord underneath it
	for at, note_f, dur, vel in [(0.035, 293.66, 0.24, 0.88),
	                             (0.235, 440.00, 0.24, 0.94),
	                             (0.435, 587.33, 1.35, 1.00)]:
		add_at(out, _brass(note_f, n_of(dur), gen, vel, rip_cents=85.0,
		                   attack=0.018, release=0.10), n_of(at), 0.85)
	for f, gain, at in [(880.00, 0.42, 0.470), (698.46, 0.46, 0.455), (293.66, 0.40, 0.450)]:
		add_at(out, _brass(f, n_of(1.28), gen, 0.80, rip_cents=35.0,
		                   attack=0.032, release=0.22), n_of(at), gain)
	add_at(out, _drum(73.42, n_of(1.1), gen, 1.0, tau=0.34, head_hz=700.0), n_of(0.430), 0.75)
	add_at(out, _drum(73.42, n_of(0.6), gen, 0.55, tau=0.26, head_hz=700.0), n_of(0.030), 0.45)
	return _finish(out, -1.6, wet=0.18, rt60=0.85, predelay=0.014, tilt_db=1.0, taper=0.16)


def coin_drop() -> np.ndarray:
	"""One coin dropped on a hard surface: the strike, a few bounces, then the spin.

	The bounce intervals shorten geometrically and the spin at the end is the rim
	rattling faster and faster until it lies flat — the sound everyone recognises and
	nobody can describe.
	"""
	gen = rng("coin_drop")
	n = n_of(0.58)
	out = np.zeros(n)
	f0 = 2760.0
	at = 0.0
	gap = 0.082
	for i in range(6):
		add_at(out, _metal_ping(n_of(0.22), gen, f0 * (1.0 + 0.004 * i), tau=0.10 * (0.88 ** i)),
		       n_of(at), 1.0 * (0.66 ** i))
		at += gap
		gap *= 0.68
	# settling: the rim contact rate runs away as the coin lies down
	spin_n = n_of(0.20)
	rate = expline(spin_n, 42.0, 190.0)
	phase = 2.0 * np.pi * np.cumsum(rate) / SR
	knock = np.maximum(0.0, np.sin(phase)) ** 12.0
	spin = unit(modal(knock * np.linspace(1.0, 0.0, spin_n) ** 1.6,
	                  [(f0 * 0.98, 0.010, 0.7), (f0 * 2.28, 0.006, 0.5),
	                   (f0 * 3.61, 0.003, 0.3)]))
	add_at(out, spin, n_of(at), 0.42)
	return _finish(out, -7.0, wet=0.09, rt60=0.36, tilt_db=1.5, taper=0.16)


# ------------------------------------------------------------- looping events

# These two are designed to be played with AudioStreamWAV.loop_mode = LOOP_FORWARD, so
# they get the music treatment instead of the one-shot treatment: every component is
# built to be exactly periodic over the file, the room tail is folded back onto the head
# (:func:`_finish_loop`), and there is no taper at either end.

BILL_COUNTER_SECONDS = 1.2
SIREN_SECONDS = 7.0

# Bills per loop and motor revolutions per loop. Integers, so both land back where they
# started: 72 bills over 1.2 s is 60 sheets a second, which is what a real counter does.
_BILL_FLAPS = 72
_BILL_MOTOR_CYCLES = 36


def bill_counter() -> np.ndarray:
	"""The Count's percussion: a stack of bills going through a counter.

	Not a noise loop — a pulse train. Each sheet is one flick of paper released off a
	rubber roller, and the pitch you hear is the sheet rate, exactly as it is on the
	real machine. The motor whirr under it is a circularly-filtered noise bed plus its
	own tonal harmonics, all snapped to whole cycles per loop.
	"""
	gen = rng("bill_counter")
	loop_n = n_of(BILL_COUNTER_SECONDS)
	n = loop_n + n_of(0.5)
	out = np.zeros(n)

	step = loop_n / float(_BILL_FLAPS)
	flick_n = n_of(0.020)
	for i in range(_BILL_FLAPS):
		flick = _paper(flick_n, gen, 1200.0, 6800.0, tau=0.0035, grip=0.25)
		# the roller's own contact, tuned slightly differently for every sheet
		tick = unit(modal(_hit(flick_n, gen, ms=0.25, lo=900.0, hi=9000.0,
		                       sharp=11.0, click=0.4),
		                  [(1180.0 * float(gen.uniform(0.94, 1.06)), 0.0035, 0.55),
		                   (2430.0, 0.0020, 0.45),
		                   (4900.0, 0.0011, 0.22)]))
		gain = 0.82 + 0.18 * float(gen.uniform(0.0, 1.0))
		add_at(out, 0.55 * flick + 0.30 * tick, int(round(i * step)), gain)

	# motor: broadband whirr plus the tonal harmonics of the drive
	t = np.arange(loop_n, dtype=np.float64)
	whirr = circular_bandpass(noise(loop_n, gen), 240.0, 2600.0, slope=1.4)
	whirr /= float(np.std(whirr)) + 1e-12
	hum = np.zeros(loop_n)
	# Harmonics only: the drive's 30 Hz fundamental is below anything the target device
	# reproduces, so putting energy there just eats headroom the flaps could have used.
	# The rolloff is written into the gains rather than taken with a lowpass, because a
	# causal filter run over a single period leaves a start-up transient at the seam.
	for k, g in [(2, 0.55), (3, 0.34), (4, 0.20), (6, 0.10)]:
		hum += g * np.sin(2.0 * np.pi * _BILL_MOTOR_CYCLES * k * t / loop_n
		                  + 0.7 * k)
	motor = 0.16 * whirr + 0.5 * hum
	out[:loop_n] += motor * (float(np.max(np.abs(out))) * 0.85
	                         / (float(np.max(np.abs(motor))) + 1e-12))
	return _finish_loop(out, loop_n, -7.0, wet=0.07, rt60=0.28, tilt_db=1.0)


def siren() -> np.ndarray:
	"""A period siren, several streets away, wailing once per loop.

	Two things make this sound like distance rather than like a quiet siren: everything
	above ~2.2 kHz is gone (air absorbs it long before you do) and the reverberant field
	is louder than the direct sound. The tone itself is an electromechanical chopper —
	a dozen harmonics off one rising-falling fundamental, not a modulated sine.

	The wail is phase-locked to the loop: the frequency contour is scaled by a hair so
	the total phase accumulated across the file is an exact multiple of 2 pi. Without
	that the fundamental restarts mid-cycle every 7 seconds, and *that* is audible even
	when the amplitude matches perfectly.
	"""
	gen = rng("siren")
	loop_n = n_of(SIREN_SECONDS)
	n = loop_n + n_of(2.2)
	t = np.arange(loop_n, dtype=np.float64) / SR
	dur = loop_n / SR

	# one up-and-down wail per loop; the rise is quicker than the fall
	shape = 0.5 - 0.5 * np.cos(2.0 * np.pi * t / dur)
	f = 372.0 + 356.0 * shape ** 1.25
	total_phase = 2.0 * np.pi * float(np.sum(f)) / SR
	cycles = max(1.0, round(total_phase / (2.0 * np.pi)))
	f *= (2.0 * np.pi * cycles) / total_phase          # -> exactly periodic
	phase = 2.0 * np.pi * np.cumsum(f) / SR

	horn = np.zeros(loop_n)
	for k in range(1, 13):
		if float(np.max(f)) * k > 0.45 * SR:
			break
		horn += (1.0 / k ** 0.92) * np.sin(k * phase + 0.4 * k)
	# the swell as it points this way, and the chopper's port modulation — 12 whole
	# cycles per loop, so the modulator comes back to where it started too
	swell = 0.72 + 0.28 * shape
	port = 1.0 + 0.06 * np.sin(2.0 * np.pi * 12.0 * t / dur)
	horn *= swell * port

	# a second unit further off, half a loop out of step, so the street is never empty
	far = np.roll(horn, loop_n // 2) * 0.34

	# wind between here and there
	wind = circular_bandpass(noise(loop_n, gen), 200.0, 1400.0, slope=1.2)
	wind /= float(np.std(wind)) + 1e-12
	wind *= 0.05 * (0.6 + 0.4 * shape)

	# Everything above is exactly periodic; everything below is linear and
	# time-invariant, applied to one period followed by silence so that the fold in
	# _finish_loop reconstructs the steady state. Running the horn's resonance over the
	# bare period instead would truncate its tail and put that missing tail at the seam.
	src = np.zeros(n)
	src[:loop_n] = horn + far + wind * float(np.max(np.abs(horn)))
	src = formants(src, [(880.0, 1.6, 1.00), (1560.0, 2.2, 0.45)]) + 0.55 * src
	# distance: the top of the spectrum simply does not arrive
	src = lowpass(src, 2150.0, order=4)
	src = highpass(src, 170.0, order=2)
	return _finish_loop(src, loop_n, -9.0, wet=0.55, rt60=1.55, predelay=0.028)


# ------------------------------------------------------------------ the raid


def raid_start() -> np.ndarray:
	"""Somebody kicks the door in, the drum lands, and the siren comes up the street."""
	gen = rng("raid_start")
	n = n_of(1.50)
	out = np.zeros(n)
	# door: a heavy slab into a frame, with the frame losing
	slam_n = n_of(0.85)
	exc = _hit(slam_n, gen, ms=5.0, lo=48.0, hi=4200.0, sharp=3.0, click=0.9, click_ms=0.20)
	add_at(out, unit(modal(exc, [
		(52.0, 0.215, 0.45), (104.0, 0.165, 0.72), (196.0, 0.112, 0.78),
		(378.0, 0.070, 0.62), (735.0, 0.038, 0.50), (1420.0, 0.019, 0.38),
		(2740.0, 0.010, 0.24),
	])), 0, 1.00)
	splinter = unit(bandpass(noise(slam_n, gen), 1600.0, 7000.0, order=2)
	                * perc_env(slam_n, 0.001, 0.030, 1.4))
	add_at(out, splinter, 0, 0.40)
	# the drum
	add_at(out, _drum(73.42, n_of(1.2), gen, 1.0, tau=0.42, head_hz=760.0), n_of(0.055), 0.62)
	add_at(out, _drum(110.00, n_of(0.7), gen, 0.6, tau=0.30, head_hz=900.0), n_of(0.062), 0.34)
	# siren coming up: a short wail rising, arriving late and loud
	sw_n = n_of(1.05)
	st = t_axis(sw_n)
	sf = expline(sw_n, 320.0, 690.0)
	sph = 2.0 * np.pi * np.cumsum(sf) / SR
	wail = np.zeros(sw_n)
	for k in range(1, 10):
		wail += (1.0 / k ** 0.9) * np.sin(k * sph + 0.4 * k)
	wail = formants(wail, [(880.0, 1.6, 1.0), (1560.0, 2.2, 0.45)]) + 0.5 * wail
	wail *= (st / (sw_n / SR)) ** 1.5 * asr_env(sw_n, 0.10, 0.14, 1.2)
	wail = unit(lowpass(wail, 3200.0, order=4))
	add_at(out, wail, n_of(0.42), 0.40)
	return _finish(out, -1.7, wet=0.16, rt60=0.80, predelay=0.013, tilt_db=1.5, taper=0.14)


def raid_win() -> np.ndarray:
	"""They found nothing. Brass up a fourth, and the till opens anyway."""
	gen = rng("raid_win")
	n = n_of(1.50)
	out = np.zeros(n)
	for at, chord, dur, vel in [(0.000, (293.66, 440.00, 698.46), 0.30, 0.90),
	                            (0.230, (391.99, 587.33, 880.00), 1.05, 1.00)]:
		for i, f in enumerate(chord):
			add_at(out, _brass(f, n_of(dur), gen, vel * (1.0 - 0.05 * i),
			                   rip_cents=75.0 if at == 0.0 else 40.0,
			                   attack=0.016, release=0.10 + 0.10 * at),
			       n_of(at), 0.62)
	add_at(out, _drum(73.42, n_of(0.9), gen, 0.8, tau=0.30, head_hz=700.0), n_of(0.225), 0.58)
	add_at(out, _register_bell(n_of(0.8), gen, 1320.0, 0.9), n_of(0.470), 0.34)
	add_at(out, _coin_pour(n_of(0.7), gen, 12, 0.30, f_lo=2000.0, f_hi=4500.0),
	       n_of(0.560), 0.22)
	return _finish(out, -2.2, wet=0.17, rt60=0.78, predelay=0.013, tilt_db=1.0, taper=0.16)


def raid_lose() -> np.ndarray:
	"""They found it. The band sags a minor third and the door does the rest."""
	gen = rng("raid_lose")
	n = n_of(1.50)
	out = np.zeros(n)
	sag_n = n_of(0.95)
	# a slow collapse of a minor third, arriving late so the chord is heard first
	hold = n_of(0.30)
	bend = np.ones(sag_n)
	bend[hold:] = expline(sag_n - hold, 1.0, 2.0 ** (-3.0 / 12.0))
	for i, f in enumerate((293.66, 349.23, 440.00)):          # D4 F4 A4
		add_at(out, _brass(f, sag_n, gen, 0.92 - 0.06 * i, rip_cents=25.0,
		                   attack=0.030, release=0.34, bright=0.86, bend=bend),
		       n_of(0.010), 0.60)
	# and an octave under it, so the sag is felt as well as heard
	add_at(out, _brass(146.83, sag_n, gen, 0.75, rip_cents=20.0, attack=0.036,
	                   release=0.34, bright=0.75, bend=bend), n_of(0.010), 0.40)
	add_at(out, _cell_door(n_of(0.62), gen, gain_low=1.25), n_of(0.870), 0.85)
	return _finish(out, -2.4, wet=0.15, rt60=0.72, predelay=0.013, taper=0.16)


# ================================= wave 3 — the Club deck (specs/m2-content §1) =====


WHEEL_CLATTER_SECONDS = 2.0

# Frets the ball crosses per loop, and turns the wheel itself makes underneath it. Both
# integers, so the tick train and the near/far swell both come back to where they began.
_WHEEL_FRETS = 34
_WHEEL_TURNS = 4


def wheel_clatter() -> np.ndarray:
	"""The ball riding the pockets of the roulette wheel — a loop, not a one-shot.

	The whole sound is the fret train: a real wheel's noise *is* the ball crossing the
	pocket separators, and the pitch you hear is that rate. A loop cannot slow down, so
	this is the ball at its cruising canter and the deck fades it out when the wheel
	takes the shot; the near/far swell (the wheel turning under it) is what keeps two
	seconds of the same rate from reading as a machine fault.
	"""
	gen = rng("wheel_clatter")
	loop_n = n_of(WHEEL_CLATTER_SECONDS)
	n = loop_n + n_of(0.45)
	out = np.zeros(n)

	step = loop_n / float(_WHEEL_FRETS)
	tick_n = n_of(0.035)
	for i in range(_WHEEL_FRETS):
		# No two frets are the same and the ball never hits one square.
		f0 = 1180.0 * float(gen.uniform(0.90, 1.12))
		tick = unit(modal(_hit(tick_n, gen, ms=0.30, lo=750.0, hi=9000.0,
		                       sharp=11.0, click=0.45, click_ms=0.08),
		                  [(f0, 0.0075, 0.55),
		                   (f0 * 2.14, 0.0040, 0.60),
		                   (f0 * 3.90, 0.0022, 0.18),
		                   (405.0, 0.0110, 0.26)]))     # the bowl the frets are set into
		near = 0.5 + 0.5 * np.cos(2.0 * np.pi * _WHEEL_TURNS * i / _WHEEL_FRETS)
		add_at(out, tick, int(round(i * step)),
		       (0.60 + 0.40 * near) * float(gen.uniform(0.86, 1.0)))

	# the ball rolling on the track between frets: circularly filtered, so it stays
	# exactly periodic, and swelling with the same rotation the ticks do
	t = np.arange(loop_n, dtype=np.float64)
	roll = circular_bandpass(noise(loop_n, gen), 520.0, 3400.0, slope=1.3)
	roll /= float(np.std(roll)) + 1e-12
	swell = 0.55 + 0.45 * np.cos(2.0 * np.pi * _WHEEL_TURNS * t / loop_n)
	roll *= swell
	out[:loop_n] += roll * (float(np.max(np.abs(out))) * 0.30
	                        / (float(np.max(np.abs(roll))) + 1e-12))
	out = comb_ff(out, 1.0 / 196.0, 0.42)        # the wooden bowl under all of it
	# A wooden bowl is not a hi-hat. Everything past ~6 kHz here is the exciter showing
	# through, and on a phone speaker it is the only part that survives — so it goes.
	out = lowpass(out, 6200.0, order=2)
	return _finish_loop(out, loop_n, -8.0, wet=0.11, rt60=0.36, tilt_db=-1.0)


def chip_stack() -> np.ndarray:
	"""A short stack of clay chips dropped onto felt.

	Clay is the point. A poker chip has almost no ring — its modes are low-Q and gone
	inside 15 ms — so a stack lands as a run of dull knocks with the table under them.
	Give it plastic modes instead and you get a checkers set.
	"""
	gen = rng("chip_stack")
	n = n_of(0.36)
	out = np.zeros(n)
	at = 0.004
	gap = 0.032
	for i in range(6):
		d = float(gen.uniform(0.94, 1.09))
		chip_n = n_of(0.09)
		exc = _hit(chip_n, gen, ms=0.85, lo=340.0, hi=5200.0, sharp=8.0, click=0.55)
		chip = unit(modal(exc, [
			(268.0, 0.0140, 0.35),
			(742.0 * d, 0.0090, 0.70),
			(1490.0 * d, 0.0048, 0.55),
			(2680.0 * d, 0.0026, 0.26),
		]))
		add_at(out, chip, n_of(at), 0.62 + 0.38 * (i / 5.0))
		at += gap
		gap *= 0.88                       # the stack settles faster as it gets shorter
	felt = unit(lowpass(noise(n, gen), 620.0, order=2) * perc_env(n, 0.002, 0.030, 1.2))
	return _finish(out + 0.20 * felt, -9.0, wet=0.06, rt60=0.26, tilt_db=-1.0, taper=0.22)


def card_riffle() -> np.ndarray:
	"""A deck riffled and bridged: the edges off the thumb, then the cards falling in.

	The riffle accelerates — the thumb releases faster as the packet thins — and the
	bridge at the end is what stops it sounding like a zip. Nothing below a kilohertz;
	this has to cut through a full table without taking up any room.
	"""
	gen = rng("card_riffle")
	n = n_of(0.55)
	out = np.zeros(n)
	at = 0.012
	gap = 0.0148
	for i in range(26):
		snap = _paper(n_of(0.022), gen, 2200.0, 9000.0, tau=0.0024, grip=0.30)
		add_at(out, snap, n_of(at), 0.55 + 0.45 * float(np.sin(np.pi * i / 25.0)))
		at += gap
		gap *= 0.978
	# the packet springing back together, and the deck squaring on the table
	out += 0.15 * _paper(n, gen, 1300.0, 9000.0, tau=0.10, grip=0.60)
	square_n = n_of(0.12)
	square = unit(modal(_hit(square_n, gen, ms=1.4, lo=260.0, hi=6000.0, sharp=6.0, click=0.45),
	                    [(196.0, 0.020, 0.45), (520.0, 0.012, 0.55), (1240.0, 0.007, 0.40)]))
	add_at(out, square, n_of(0.435), 0.42)
	return _finish(out, -11.0, wet=0.07, rt60=0.28, tilt_db=-0.5, taper=0.18)


def reel_stop() -> np.ndarray:
	"""One slot column locking: the pawl drops into its notch and the drum settles.

	Deliberately nothing like `drop_clack`. That is a plastic target face slapping a
	housing; this is a steel pawl in a heavy geared drum, so it is lower, longer, and
	arrives in two parts. The player has to be able to tell a target going down from a
	column locking without looking at either.
	"""
	gen = rng("reel_stop")
	n = n_of(0.26)
	exc = _hit(n, gen, ms=2.2, lo=90.0, hi=3400.0, sharp=4.0, click=0.72, click_ms=0.16)
	pawl = unit(modal(exc, [
		(78.0, 0.075, 0.55),
		(163.0, 0.055, 0.80),
		(324.0, 0.034, 0.60),
		(628.0, 0.019, 0.45),
		(1210.0, 0.009, 0.26),
	]))
	rim_n = n_of(0.13)
	rim = unit(modal(_hit(rim_n, gen, ms=1.4, lo=200.0, hi=2600.0, sharp=5.0, click=0.35),
	                 [(214.0, 0.030, 0.60), (455.0, 0.018, 0.45), (900.0, 0.009, 0.25)]))
	add_at(pawl, rim, n_of(0.032), 0.42)
	return _finish(pawl, -5.5, wet=0.07, rt60=0.28, tilt_db=-1.5, taper=0.22)


def jackpot() -> np.ndarray:
	"""The slots pay: the bell, the band, and a great deal of money hitting a tray.

	Loud, and deliberately *not* the loudest thing in the game. The knocker is still the
	rank-up king (docs/08 §2) and rankup_fanfare is its partner, so this sits under both
	of them on the peak ladder and under the fanfare by RMS as well. A jackpot you hear
	over a rank-up has stolen the biggest moment in the career.

	Harmony: F major — the relative major of the score's D minor — so a jackpot landing
	anywhere in the eight bars is consonant with whatever the band is on.
	"""
	gen = rng("jackpot")
	n = n_of(1.80)
	out = np.zeros(n)
	# the machine announcing itself: the register bell struck three times, fast
	for i, at in enumerate((0.000, 0.082, 0.166)):
		add_at(out, _register_bell(n_of(1.05), gen, 1320.0 * (1.0 + 0.006 * i), 0.90),
		       n_of(at), 1.00 - 0.20 * i)
	for i, f in enumerate((349.23, 440.00, 523.25, 698.46)):        # F4 A4 C5 F5
		add_at(out, _brass(f, n_of(1.05), gen, 0.92 - 0.05 * i, rip_cents=60.0,
		                   attack=0.020, release=0.30),
		       n_of(0.150 + 0.012 * i), 0.44)
	add_at(out, _drum(87.31, n_of(0.90), gen, 0.85, tau=0.30, head_hz=720.0), n_of(0.145), 0.50)
	# the payout: a long cascade into the tray, thinning the way real coins do
	add_at(out, _coin_pour(n_of(1.35), gen, 46, 0.98, f_lo=1700.0, f_hi=4800.0, decay=0.8),
	       n_of(0.230), 0.52)
	return _finish(out, -1.7, wet=0.16, rt60=0.72, predelay=0.013, tilt_db=1.0, taper=0.16)


def meeting_start() -> np.ndarray:
	"""The Family Meeting opens: the room stands up as the second guy walks in.

	D minor, the band's own key, so it can land on any bar of the score without a clash.
	The chord arrives one voice at a time from the bottom, which is what a section
	entering sounds like and what a single stab never does.
	"""
	gen = rng("meeting_start")
	n = n_of(1.40)
	out = np.zeros(n)
	for at, f, dur, vel in [(0.000, 146.83, 1.05, 0.86),      # D3
	                        (0.075, 220.00, 0.98, 0.90),      # A3
	                        (0.150, 293.66, 0.92, 0.94),      # D4
	                        (0.225, 349.23, 0.86, 1.00)]:     # F4
		add_at(out, _brass(f, n_of(dur), gen, vel, rip_cents=70.0,
		                   attack=0.024, release=0.24), n_of(at), 0.55)
	add_at(out, _drum(73.42, n_of(1.05), gen, 1.0, tau=0.36, head_hz=700.0), n_of(0.010), 0.72)
	add_at(out, _drum(110.00, n_of(0.60), gen, 0.55, tau=0.24, head_hz=880.0), n_of(0.235), 0.40)
	return _finish(out, -2.6, wet=0.17, rt60=0.80, predelay=0.013, tilt_db=1.0, taper=0.16)


def meeting_jackpot() -> np.ndarray:
	"""The back room pays while both guys are still out there.

	Short on purpose: it re-arms every time the ball comes back, and a two-second
	fanfare that repeats is a two-second fanfare the player learns to dread.
	"""
	gen = rng("meeting_jackpot")
	n = n_of(0.85)
	out = np.zeros(n)
	for at, f, dur in [(0.000, 587.33, 0.16), (0.070, 698.46, 0.16), (0.140, 880.00, 0.52)]:
		add_at(out, _brass(f, n_of(dur), gen, 0.95, rip_cents=55.0,
		                   attack=0.012, release=0.10), n_of(at), 0.90)
	add_at(out, _register_bell(n_of(0.55), gen, 1760.0, 0.55), n_of(0.145), 0.42)
	add_at(out, _coin_pour(n_of(0.45), gen, 9, 0.22, f_lo=2100.0, f_hi=4600.0), n_of(0.195), 0.26)
	return _finish(out, -3.2, wet=0.13, rt60=0.52, predelay=0.011, tilt_db=1.5, taper=0.18)


def meeting_end() -> np.ndarray:
	"""One ball left. The meeting is over and somebody came home.

	Wistful is a specific construction, not a mood label. The section is gone and one
	darkened horn is left holding the line; it falls A4-G4-F4 instead of arriving; the
	last note lets itself down about a sixth of a semitone the way a player does; and
	the pad underneath is a Dm6 shell — D, F and the natural sixth B — which is the
	chord the entire score is built on and the one chord that never sounds finished.
	"""
	gen = rng("meeting_end")
	n = n_of(1.60)
	out = np.zeros(n)
	fall_n = n_of(0.86)
	bend = np.ones(fall_n)
	hold = n_of(0.34)
	bend[hold:] = expline(fall_n - hold, 1.0, 2.0 ** (-18.0 / 1200.0))
	for at, f, dur, vel, bnd in [(0.000, 440.00, 0.26, 0.72, None),
	                             (0.190, 392.00, 0.26, 0.66, None),
	                             (0.380, 349.23, 0.86, 0.78, bend)]:
		add_at(out, _brass(f, n_of(dur), gen, vel, rip_cents=20.0, attack=0.045,
		                   release=0.30, bright=0.72, bend=bnd), n_of(at), 0.85)
	for i, f in enumerate((146.83, 174.61, 246.94)):        # D3 F3 B3 — the Dm6 shell
		add_at(out, _brass(f, n_of(1.05), gen, 0.52 - 0.05 * i, rip_cents=12.0,
		                   attack=0.16, release=0.46, bright=0.66), n_of(0.36 + 0.02 * i), 0.34)
	return _finish(out, -4.5, wet=0.21, rt60=1.05, predelay=0.016, tilt_db=-1.5, taper=0.20)


def radio_squelch() -> np.ndarray:
	"""A cop radio keying up two streets away — the telegraph before a raid.

	The same construction as the squelch buried inside `bribe_paid`, on its own and
	shorter: the carrier breaks squelch (a burst of hiss cut off dead), a two-tone
	chirp, then the hiss of it unkeying. Band-limited to 340-2900 Hz and saturated,
	because it is coming out of a two-inch speaker in a car door.
	"""
	gen = rng("radio_squelch")
	n = n_of(0.30)
	out = np.zeros(n)
	burst = bandpass(noise(n, gen), 900.0, 3600.0, order=2) * perc_env(n, 0.0015, 0.014, 1.6)
	add_at(out, unit(burst), 0, 0.85)
	chirp_n = n_of(0.16)
	chirp = sine(expline(chirp_n, 1520.0, 880.0)) * asr_env(chirp_n, 0.006, 0.040, 1.4)
	chirp += 0.45 * sine(expline(chirp_n, 2280.0, 1320.0)) * asr_env(chirp_n, 0.008, 0.040, 1.4)
	add_at(out, unit(chirp), n_of(0.028), 1.00)
	tail_n = n_of(0.09)
	tail = bandpass(noise(tail_n, gen), 1100.0, 3200.0, order=2) * perc_env(tail_n, 0.002, 0.022, 1.2)
	add_at(out, unit(tail), n_of(0.185), 0.45)
	out = bandpass(out, 340.0, 2900.0, order=4)
	out = comb_ff(out, 1.0 / 470.0, 0.45)
	# Saturation is what a two-inch speaker in a car door does, and it also flattens the
	# crest factor: normalised to a transient's peak this would be the densest thing in
	# the game by RMS. A telegraph warns, it does not announce, so it sits well down the
	# ladder — the same trade `bribe_paid` makes for the same reason.
	out = unit(np.tanh(out * 1.35))
	return _finish(out, -11.5, wet=0.06, rt60=0.26, tilt_db=-1.0, taper=0.20)


def staircase_crest() -> np.ndarray:
	"""The top of the Staircase: air up the wireform, then the bell over the door.

	The Club has been borrowing `skill_shot_ding` for this, which is exactly the
	collision docs/08 §2 forbids — two different achievements taught with one sound.
	This is the same *family* as the chime unit (a struck bar, so it agrees with the
	score) an octave above it at D7, and it arrives on the back of a rising rush that
	the skill shot has nothing like. The whoosh is what the player actually hears first;
	the bar is the receipt.
	"""
	gen = rng("staircase_crest")
	n = n_of(0.90)
	out = np.zeros(n)

	# the climb: a filtered rush that only ever goes up
	climb_n = n_of(0.42)
	ramp = np.linspace(0.0, 1.0, climb_n) ** 0.85
	centre = 520.0 * (1.0 + 6.5 * ramp)
	air = sweep_filter(noise(climb_n, gen), centre, q=1.5, kind="bp")
	air = sweep_filter(air, centre * 1.45, q=0.75, kind="lp")
	air = unit(air * (ramp ** 1.4) * asr_env(climb_n, 0.020, 0.090, 1.2))
	add_at(out, air, 0, 0.55)
	# the ball ticking off the stair rungs on the way up, closer together as it goes
	for i, frac in enumerate((0.20, 0.42, 0.61, 0.77, 0.90)):
		ping = unit(modal(_hit(n_of(0.035), gen, ms=0.30, lo=2200.0, hi=12000.0,
		                       sharp=11.0, click=0.40, click_ms=0.07),
		                  [(2960.0 + 540.0 * i, 0.0050, 0.60),
		                   (5300.0 + 700.0 * i, 0.0025, 0.30)]))
		add_at(out, ping, int(frac * climb_n), 0.14 + 0.055 * i)

	# and the bar at the top: D7, the chime unit's D two octaves up
	f0 = 2349.32
	bell_n = n_of(0.50)
	bexc = _hit(bell_n, gen, ms=0.50, lo=2400.0, hi=14000.0, sharp=10.0, click=0.85)
	bell = modal(bexc, [
		(f0, 0.160, 1.00),
		(f0 * 1.0024, 0.150, 0.55),      # the beating partner, as on every bar in the set
		(f0 * 2.758, 0.070, 0.34),
		(f0 * 5.404, 0.028, 0.14),
	])
	shimmer = 1.0 + 0.10 * np.sin(2.0 * np.pi * 7.5 * t_axis(bell_n))
	add_at(out, unit(bell * shimmer), n_of(0.40), 1.00)
	return _finish(out, -3.0, wet=0.15, rt60=0.58, predelay=0.011, tilt_db=1.5, taper=0.18)


# ============================ wave 4 — the endgame (specs/m3-fall-rise.md AUDIO-4) =====

# The last of the vocabulary: the Commission fights, the Docks, the Penthouse, the dome,
# the heists, the election, Empire Mode, the Reunion, the briefcases and Skip Town. Every
# one of these was already being *called* by shipped code and failing silent.
#
# Two ladder claims are new and both are asserted in generate.py rather than asserted
# here in prose: `dome_loop` is the biggest PITCHED sound in the game and still sits under
# the knocker, and `empire_start` — everything lit, x10 on everything — sits under the
# rank-up pair. Telegraphs (wrench, crane) sit far down the ladder for the reason
# `radio_squelch` does: a warning warns, it does not announce.


def _gong(n: int, gen: np.random.Generator, f0: float = 174.61, tau: float = 1.0,
          bright: float = 1.0) -> np.ndarray:
	"""A struck plate: many inharmonic modes and no pitch you could name.

	A bell has a note; a tam-tam has a *cloud*, and that is the difference between a boss
	arriving and a boss arriving musically. The ratios are deliberately not small
	integers, and the top of the bank rings shorter than the bottom, so the strike is
	bright and what hangs afterwards is dark.
	"""
	exc = _hit(n, gen, ms=3.2, lo=110.0, hi=9000.0, sharp=3.4, click=0.55, click_ms=0.22)
	ratios = (1.000, 1.412, 1.732, 2.093, 2.614, 3.147,
	          3.712, 4.391, 5.128, 6.017, 7.114, 8.423)
	spec = []
	for i, r in enumerate(ratios):
		detune = 1.0 + 0.004 * float(gen.uniform(-1.0, 1.0))
		spec.append((f0 * r * detune,
		             tau / (1.0 + 0.55 * i),
		             (0.88 ** i) * (bright if i >= 5 else 1.0)))
	return unit(modal(exc, spec))


def _tower_bell(n: int, gen: np.random.Generator, f0: float = 220.0,
                tail: float = 1.0) -> np.ndarray:
	"""A cast bronze bell in a tower — the civic one, not the one on a desk.

	A tuned cast bell has a partial set nothing else has: a hum an octave BELOW the note
	you think you hear, the prime, a minor-third tierce, the quint, and the nominal an
	octave up. That tierce is why every big bell in the world sounds sad, and it is the
	reason an election win in this game can be a bell and still not be a celebration.
	"""
	exc = _hit(n, gen, ms=2.6, lo=90.0, hi=7000.0, sharp=4.0, click=0.75, click_ms=0.18)
	partials = [
		(0.500, 1.00, 0.55),      # hum
		(1.000, 0.86, 1.00),      # prime
		(1.0024, 0.83, 0.52),     # ...beating against itself
		(1.189, 0.62, 0.72),      # tierce: the minor third
		(1.498, 0.44, 0.50),      # quint
		(2.000, 0.34, 0.62),      # nominal
		(2.505, 0.22, 0.34),
		(3.011, 0.15, 0.24),
		(4.166, 0.09, 0.14),
	]
	return unit(modal(exc, [(f0 * r, 1.55 * tail * tt, g) for r, tt, g in partials]))


def _glass(n: int, gen: np.random.Generator, f0: float = 2680.0,
           tau: float = 0.05) -> np.ndarray:
	"""A tumbler set down on wood: a thin high ring on a dull knock."""
	exc = _hit(n, gen, ms=0.9, lo=900.0, hi=12000.0, sharp=8.0, click=0.7, click_ms=0.10)
	return unit(modal(exc, [
		(f0, tau, 0.75),
		(f0 * 1.0035, tau * 0.94, 0.40),
		(f0 * 2.72, tau * 0.42, 0.28),
		(f0 * 5.10, tau * 0.20, 0.10),
		(f0 * 0.11, tau * 1.6, 0.30),        # the wood it lands on
	]))


def _kicker(n: int, gen: np.random.Generator, velocity: float = 1.0) -> np.ndarray:
	"""A trough coil throwing a steel ball: the solenoid, then the ball leaving."""
	coil = unit(modal(_hit(n, gen, ms=1.6, lo=150.0, hi=6000.0, sharp=5.5,
	                       click=0.85, click_ms=0.13),
	                  [(148.0, 0.045, 0.60), (296.0, 0.028, 0.62), (592.0, 0.016, 0.50),
	                   (1180.0, 0.008, 0.34), (2360.0, 0.004, 0.20)]))
	ball = _metal_ping(n, gen, 3480.0, tau=0.030, bright=1.15)
	return unit(coil + 0.30 * ball, velocity)


def _scrape(n: int, gen: np.random.Generator, f_lo: float, f_hi: float,
            q: float = 9.0, walk_hz: float = 70.0, depth: float = 0.25) -> np.ndarray:
	"""Stick-slip: something hard dragged over something hard.

	Built as a narrow resonance swept by a jittering envelope rather than as noise with
	a filter on it — the same argument `safe_open`'s creak makes. Filtered noise gives
	you a hiss that fades; a grabbing resonance gives you friction.
	"""
	grab = lowpass(noise(n, gen), walk_hz, order=2)
	grab /= float(np.max(np.abs(grab))) + 1e-12
	swept = sweep_filter(noise(n, gen), expline(n, f_lo, f_hi) * (1.0 + depth * grab),
	                     q=q, kind="bp")
	swept *= 0.45 + 0.55 * (0.5 + 0.5 * grab)
	return unit(highpass(swept, 260.0, order=2))


def _far_horn(n: int, gen: np.random.Generator, freqs, sag_cents: float = 45.0,
              attack: float = 0.10, release: float = 0.35) -> np.ndarray:
	"""A multi-note horn heard from a long way off.

	Distance is two things and neither of them is "quieter": everything above ~2 kHz
	never arrives (air absorbs it first), and the reverberant field is louder than the
	direct sound. The chord is what makes it a *train* horn rather than a foghorn — a
	single pipe is a boat, three or four pipes beating against each other is a
	locomotive — and the whole chord sags together at the end because the thing making
	it is moving away from you.
	"""
	sag = np.ones(n)
	hold = min(n - 1, n_of(0.55 * n / SR))
	sag[hold:] = expline(n - hold, 1.0, 2.0 ** (-sag_cents / 1200.0))
	out = np.zeros(n)
	for i, f in enumerate(freqs):
		voice = np.zeros(n)
		for k, g in ((1, 1.00), (2, 0.42), (3, 0.24), (4, 0.13), (5, 0.07), (6, 0.04)):
			voice += g * np.sin(phase_of(f * k * sag) + 0.5 * k + 0.31 * i)
		out += voice * (0.92 ** i)
	out *= asr_env(n, attack, release, 1.4)
	# the reed noise in the throat of the horn, and then the air between here and there
	out += 0.05 * bandpass(noise(n, gen), 300.0, 1800.0, order=2) * asr_env(n, attack, release, 1.4)
	return unit(lowpass(out, 2050.0, order=4))


def boss_start() -> np.ndarray:
	"""A rival family walks in and the room gets colder (docs/05 §6).

	Three things and no more: a plate struck once and left to hang, the two D's of the
	score's own key from the low brass with a slow rip on them, and the drum.
	`boss_fight.gd` fires this and the knocker on the same frame, so it deliberately owns
	the bottom of the spectrum and leaves the transient to the knocker.
	"""
	gen = rng("boss_start")
	n = n_of(1.60)
	out = np.zeros(n)
	add_at(out, _gong(n_of(1.50), gen, 174.61, tau=1.10), 0, 0.85)
	for at, f, vel in ((0.055, 73.42, 0.95), (0.075, 146.83, 0.82)):
		add_at(out, _brass(f, n_of(1.25), gen, vel, rip_cents=110.0, attack=0.055,
		                   release=0.42, bright=0.70), n_of(at), 0.62)
	add_at(out, _drum(55.00, n_of(1.05), gen, 1.0, tau=0.44, head_hz=620.0), n_of(0.020), 0.70)
	return _finish(out, -2.4, wet=0.20, rt60=1.05, predelay=0.015, tilt_db=-1.5, taper=0.18)


def boss_phase() -> np.ndarray:
	"""He changes his mind about you: the fight turns over into its next phase.

	A minor second held against itself — D and Eb in the same octave, the most
	uncomfortable interval two horns can play — with the plate choked underneath it.
	Short, because it fires between phases while the ball is still live.
	"""
	gen = rng("boss_phase")
	n = n_of(0.90)
	out = np.zeros(n)
	for at, f, vel in ((0.000, 146.83, 0.92), (0.030, 155.56, 0.86)):       # D3, Eb3
		add_at(out, _brass(f, n_of(0.60), gen, vel, rip_cents=45.0, attack=0.018,
		                   release=0.16, bright=0.82), n_of(at), 0.70)
	add_at(out, _gong(n_of(0.34), gen, 233.08, tau=0.14, bright=1.25), n_of(0.150), 0.55)
	add_at(out, _drum(73.42, n_of(0.55), gen, 0.85, tau=0.26, head_hz=700.0), 0, 0.60)
	return _finish(out, -3.2, wet=0.14, rt60=0.62, predelay=0.012, taper=0.20)


def boss_beaten() -> np.ndarray:
	"""He is down: the oldest cadence there is, in the score's own key.

	A7 into Dm — bars 6 and 7 of the loop are already those two chords — so the win lands
	*inside* the music instead of on top of it. No major lift: the dome is the only place
	in the game that gets one, and it has to stay the only one for that to mean anything.
	"""
	gen = rng("boss_beaten")
	n = n_of(1.90)
	out = np.zeros(n)
	for i, f in enumerate((220.00, 277.18, 329.63)):                 # A3 C#4 E4 — the A7
		add_at(out, _brass(f, n_of(0.32), gen, 0.86 - 0.05 * i, rip_cents=55.0,
		                   attack=0.018, release=0.12), n_of(0.010 + 0.010 * i), 0.55)
	for i, f in enumerate((146.83, 293.66, 349.23, 440.00)):          # D3 D4 F4 A4 — home
		add_at(out, _brass(f, n_of(1.28), gen, 0.95 - 0.04 * i, rip_cents=35.0,
		                   attack=0.026, release=0.40), n_of(0.300 + 0.012 * i), 0.50)
	add_at(out, _drum(73.42, n_of(1.10), gen, 1.0, tau=0.38, head_hz=700.0), n_of(0.295), 0.72)
	add_at(out, _gong(n_of(1.35), gen, 146.83, tau=0.90, bright=0.80), n_of(0.290), 0.34)
	return _finish(out, -2.1, wet=0.19, rt60=0.98, predelay=0.014, tilt_db=0.5, taper=0.16)


def wrench_telegraph() -> np.ndarray:
	"""Sammy's crew getting a spanner onto your flipper linkage (docs/05 §6, R3).

	Mechanical, and pointedly not police: no tone, no two-tone chirp, nothing that could
	be mistaken for the raid family. It is a wrench chattering round a bolt head — the
	rate rises as the thread bites — with the linkage rattling in sympathy underneath,
	and it ends on the clamp that is about to cost you a flipper. Two seconds, because
	that is exactly how long `sammy.gd` telegraphs for: the sound and the tell are the
	same object.
	"""
	gen = rng("wrench_telegraph")
	n = n_of(2.00)
	out = np.zeros(n)
	at = 0.030
	gap = 0.130
	for i in range(22):
		tick_n = n_of(0.09)
		f0 = 2050.0 * float(gen.uniform(0.86, 1.18))
		spanner = unit(modal(_hit(tick_n, gen, ms=0.55, lo=700.0, hi=9000.0,
		                          sharp=9.0, click=0.55, click_ms=0.10),
		                     [(f0, 0.0085, 0.55), (f0 * 1.87, 0.0048, 0.60),
		                      (f0 * 3.42, 0.0026, 0.28), (452.0, 0.0160, 0.34)]))
		add_at(out, spanner, n_of(at),
		       (0.30 + 0.55 * (i / 21.0)) * float(gen.uniform(0.72, 1.0)))
		at += gap
		gap *= 0.958
	rattle = np.zeros(n)
	for i in range(34):
		rat_n = n_of(0.05)
		f0 = float(gen.uniform(620.0, 1550.0))
		add_at(rattle, unit(modal(_hit(rat_n, gen, ms=0.40, lo=400.0, hi=6000.0,
		                               sharp=10.0, click=0.30),
		                          [(f0, 0.0060, 0.60), (f0 * 2.4, 0.0030, 0.30)])),
		       n_of(float(gen.uniform(0.05, 1.42))), float(gen.uniform(0.10, 0.34)))
	out += 0.55 * rattle
	clamp = unit(modal(_hit(n_of(0.42), gen, ms=2.6, lo=90.0, hi=4200.0, sharp=4.0,
	                        click=0.80, click_ms=0.16),
	                   [(118.0, 0.075, 0.60), (243.0, 0.048, 0.62), (486.0, 0.028, 0.52),
	                    (960.0, 0.015, 0.38), (1880.0, 0.008, 0.22)]))
	add_at(out, clamp, n_of(1.46), 1.00)
	return _finish(out, -6.0, wet=0.09, rt60=0.36, tilt_db=-1.0, taper=0.14)


def crane_telegraph() -> np.ndarray:
	"""The gantry warning you before the magnet takes the ball (specs/m3 TABLE-3).

	Industrial: a contactor coil energising (mains buzz swelling as the field builds),
	the gantry motor spinning up a fifth, and two strikes on a small steel bell bolted
	to the frame. It is a warning, so it sits low on the ladder — the pull is the loud
	one — and it is nothing like `radio_squelch`: this is a machine announcing that it
	is about to move, not a man telling another man to move.

	1.2 s, because that is `CraneMagnet.TELEGRAPH`: like the wrench, the sound and the
	tell are the same object, and a warning still sounding when the thing it warned about
	happens has stopped being a warning.
	"""
	gen = rng("crane_telegraph")
	n = n_of(1.20)
	t = t_axis(n)
	out = np.zeros(n)
	swell = np.clip(t / 0.55, 0.0, 1.0) ** 1.4
	coil = np.zeros(n)
	for k, g in ((1, 1.00), (2, 0.55), (3, 0.42), (4, 0.22), (5, 0.16), (7, 0.09)):
		coil += g * np.sin(2.0 * np.pi * 120.0 * k * t + 0.6 * k)
	out += 0.55 * unit(coil * swell * asr_env(n, 0.020, 0.22, 1.2))
	whirr = bl_saw(expline(n, 62.0, 96.0), n, cap=26)
	teeth = 0.34 * sine(expline(n, 780.0, 1180.0)) + 0.14 * sine(expline(n, 1560.0, 2360.0))
	motor = lowpass(whirr + teeth, 2600.0, order=2) * swell * asr_env(n, 0.050, 0.30, 1.2)
	out += 0.42 * unit(motor)
	for at in (0.08, 0.52):
		add_at(out, _register_bell(n_of(0.50), gen, 940.0, 0.42), n_of(at), 0.62)
	return _finish(out, -7.0, wet=0.10, rt60=0.44, tilt_db=-1.5, taper=0.18)


def crane_pull() -> np.ndarray:
	"""The magnet takes it: the contactor slams shut and the ball arrives on the face."""
	gen = rng("crane_pull")
	n = n_of(0.70)
	out = np.zeros(n)
	add_at(out, unit(modal(_hit(n_of(0.30), gen, ms=2.0, lo=70.0, hi=5000.0, sharp=4.5,
	                            click=0.85, click_ms=0.15),
	                       [(96.0, 0.055, 0.62), (188.0, 0.038, 0.68), (372.0, 0.022, 0.55),
	                        (742.0, 0.012, 0.40), (1490.0, 0.006, 0.24)])), 0, 1.00)
	add_at(out, _metal_ping(n_of(0.34), gen, 3120.0, tau=0.055, bright=1.10), n_of(0.052), 0.42)
	hum_n = n_of(0.46)
	ht = t_axis(hum_n)
	hum = (np.sin(2.0 * np.pi * 120.0 * ht) + 0.45 * np.sin(2.0 * np.pi * 240.0 * ht)
	       + 0.22 * np.sin(2.0 * np.pi * 360.0 * ht))
	add_at(out, unit(hum * asr_env(hum_n, 0.010, 0.20, 1.3)), n_of(0.040), 0.26)
	return _finish(out, -4.5, wet=0.08, rt60=0.34, tilt_db=-1.0, taper=0.20)


def container_break() -> np.ndarray:
	"""A stack of containers coming apart — a steel box is a drum you can walk inside.

	The body modes are low and long because the box is huge and empty, the seam lets go
	as a metal tear rather than a crack, and the load lands afterwards. It has to be
	tellable from `drop_bank_down` by size alone: that is a plastic target face going
	over, this is four tonnes of corrugated steel changing its mind.
	"""
	gen = rng("container_break")
	n = n_of(0.95)
	out = np.zeros(n)
	add_at(out, unit(modal(_hit(n_of(0.72), gen, ms=4.5, lo=48.0, hi=5200.0, sharp=3.2,
	                            click=0.85, click_ms=0.20),
	                       [(63.0, 0.190, 0.50), (97.0, 0.150, 0.62), (154.0, 0.110, 0.66),
	                        (268.0, 0.075, 0.60), (443.0, 0.048, 0.52), (826.0, 0.026, 0.42),
	                        (1610.0, 0.013, 0.28), (3120.0, 0.007, 0.16)])), 0, 1.00)
	tear_n = n_of(0.30)
	tear = sweep_filter(noise(tear_n, gen), expline(tear_n, 3400.0, 1250.0), q=1.2, kind="bp")
	add_at(out, unit(tear * perc_env(tear_n, 0.004, 0.070, 1.2)), n_of(0.055), 0.30)
	for i, at in enumerate((0.180, 0.245, 0.330, 0.415)):
		crate_n = n_of(0.26)
		f0 = 150.0 * float(gen.uniform(0.86, 1.22))
		add_at(out, unit(modal(_hit(crate_n, gen, ms=2.4, lo=100.0, hi=4000.0,
		                            sharp=4.5, click=0.50),
		                       [(f0, 0.050, 0.60), (f0 * 2.35, 0.026, 0.50),
		                        (f0 * 4.10, 0.012, 0.30)])), n_of(at), 0.34 - 0.05 * i)
	return _finish(out, -4.0, wet=0.12, rt60=0.55, tilt_db=-1.0, taper=0.18)


def pier_splash() -> np.ndarray:
	"""Off the pier edge and into the harbour — the Docks' own drain.

	A splash is three events and everybody only remembers one: the impact (broadband,
	over in 40 ms), the cavity collapsing behind it — a bubble whose pitch RISES as it
	shrinks, which is the "ploop", and getting that direction wrong is the most obvious
	mistake a water sound can make — and the wash spreading out afterwards. Sits below
	`drain` on the ladder on purpose: losing the ball down the middle is still worse.
	"""
	gen = rng("pier_splash")
	n = n_of(1.10)
	out = np.zeros(n)
	imp_n = n_of(0.22)
	add_at(out, unit(bandpass(noise(imp_n, gen), 420.0, 7200.0, order=2)
	                 * perc_env(imp_n, 0.0015, 0.032, 1.5)), 0, 0.95)
	for at, f0, f1, tau, g in ((0.028, 380.0, 880.0, 0.070, 1.00),
	                           (0.150, 620.0, 1180.0, 0.030, 0.36),
	                           (0.235, 900.0, 1620.0, 0.020, 0.22)):
		b_n = n_of(0.22)
		add_at(out, unit(sine(expline(b_n, f0, f1)) * perc_env(b_n, 0.0022, tau, 1.1)),
		       n_of(at), g)
	wash_n = n_of(0.70)
	wash = sweep_filter(noise(wash_n, gen), expline(wash_n, 2600.0, 700.0), q=0.8, kind="bp")
	add_at(out, unit(lowpass(wash * asr_env(wash_n, 0.030, 0.42, 1.4), 5200.0, order=2)),
	       n_of(0.030), 0.40)
	swell_n = n_of(0.82)
	add_at(out, unit(lowpass(noise(swell_n, gen), 420.0, order=4)
	                 * asr_env(swell_n, 0.12, 0.42, 1.2)), n_of(0.20), 0.22)
	return _finish(out, -3.8, wet=0.14, rt60=0.60, tilt_db=-1.5, taper=0.20)


def smuggling_start() -> np.ndarray:
	"""The run is on: the shutter goes up and the crew starts moving crates.

	No horn — `train_away` owns the only horn in the game and a second one two streets
	from it would blur both. A rolling steel shutter accelerating into its top stop is a
	sound nothing else in the set makes, which is the whole requirement.
	"""
	gen = rng("smuggling_start")
	n = n_of(1.20)
	out = np.zeros(n)
	at = 0.010
	gap = 0.040
	for i in range(19):
		slat_n = n_of(0.06)
		f0 = 1420.0 * float(gen.uniform(0.90, 1.14))
		add_at(out, unit(modal(_hit(slat_n, gen, ms=0.45, lo=600.0, hi=8000.0,
		                            sharp=10.0, click=0.40),
		                       [(f0, 0.0060, 0.55), (f0 * 2.1, 0.0032, 0.45),
		                        (330.0, 0.0120, 0.30)])), n_of(at), 0.34 + 0.30 * (i / 18.0))
		at += gap
		gap *= 0.945
	add_at(out, unit(modal(_hit(n_of(0.26), gen, ms=2.2, lo=120.0, hi=4600.0,
	                            sharp=4.5, click=0.60),
	                       [(148.0, 0.055, 0.55), (306.0, 0.032, 0.60),
	                        (612.0, 0.018, 0.42)])), n_of(at), 0.72)
	add_at(out, unit(modal(_hit(n_of(0.30), gen, ms=3.0, lo=90.0, hi=3200.0,
	                            sharp=4.0, click=0.45),
	                       [(112.0, 0.070, 0.60), (231.0, 0.040, 0.50),
	                        (498.0, 0.020, 0.34)])), n_of(0.760), 0.55)
	add_at(out, _brass(98.00, n_of(0.58), gen, 0.60, rip_cents=30.0, attack=0.050,
	                   release=0.26, bright=0.62), n_of(0.640), 0.34)
	return _finish(out, -5.0, wet=0.10, rt60=0.48, tilt_db=-1.0, taper=0.18)


def shipment_out() -> np.ndarray:
	"""The load is away and the money is real (`night.gd` settles the shipment on it).

	The hatch closes on it, the dock bell rings it off, and the low brass takes it out to
	sea in open fifths. Deliberately not a cha-ching: `storefront_collect` owns the
	register and nothing else in the game may borrow it (docs/08 §2).
	"""
	gen = rng("shipment_out")
	n = n_of(1.50)
	out = np.zeros(n)
	add_at(out, unit(modal(_hit(n_of(0.60), gen, ms=4.0, lo=55.0, hi=4000.0, sharp=3.4,
	                            click=0.80, click_ms=0.18),
	                       [(74.0, 0.150, 0.52), (139.0, 0.105, 0.66), (262.0, 0.068, 0.60),
	                        (505.0, 0.038, 0.48), (980.0, 0.020, 0.32)])), 0, 0.95)
	for i, at in enumerate((0.240, 0.400)):
		add_at(out, _register_bell(n_of(0.70), gen, 1180.0 + 14.0 * i, 0.72),
		       n_of(at), 0.50 - 0.10 * i)
	for i, f in enumerate((110.00, 164.81, 220.00)):            # A2 E3 A3 — open, leaving
		add_at(out, _brass(f, n_of(0.92), gen, 0.78 - 0.06 * i, rip_cents=40.0,
		                   attack=0.040, release=0.34, bright=0.78),
		       n_of(0.360 + 0.014 * i), 0.46)
	add_at(out, _coin_pour(n_of(0.58), gen, 8, 0.26, f_lo=1500.0, f_hi=3400.0), n_of(0.620), 0.20)
	return _finish(out, -3.4, wet=0.16, rt60=0.75, predelay=0.013, tilt_db=0.5, taper=0.16)


def chair_take() -> np.ndarray:
	"""A chair comes back from the long table and somebody takes it (docs/02 R6).

	The Penthouse is the quiet room — the most dangerous room in the game is the calmest
	— so this is a small sound in a big space: hardwood legs on marble for a tenth of a
	second, the frame taking a man's weight, and a glass touching the table because he
	was holding one.
	"""
	gen = rng("chair_take")
	n = n_of(0.75)
	out = np.zeros(n)
	sc_n = n_of(0.16)
	add_at(out, _scrape(sc_n, gen, 900.0, 2100.0, q=9.0, walk_hz=70.0, depth=0.25)
	       * asr_env(sc_n, 0.010, 0.060, 1.3), 0, 0.62)
	add_at(out, unit(modal(_hit(n_of(0.34), gen, ms=2.6, lo=110.0, hi=3600.0,
	                            sharp=4.2, click=0.50),
	                       [(128.0, 0.060, 0.58), (272.0, 0.036, 0.60),
	                        (556.0, 0.020, 0.44), (1090.0, 0.010, 0.28)])), n_of(0.150), 1.00)
	add_at(out, _glass(n_of(0.30), gen, 2680.0, tau=0.045), n_of(0.300), 0.22)
	return _finish(out, -4.1, wet=0.18, rt60=0.85, predelay=0.016, tilt_db=0.5, taper=0.22)


def sitdown() -> np.ndarray:
	"""The Sit-Down: the door closes, the glass goes down, nobody talks for a while.

	Heat freezes for sixty seconds, so the sound has to *lower* the room — the opposite
	of every other reward in the game. A padded door, a tumbler on wood, and two horns
	holding an open fifth with no rip on them at all: the only sound in the set that
	arrives by getting quieter.
	"""
	gen = rng("sitdown")
	n = n_of(1.60)
	out = np.zeros(n)
	add_at(out, unit(modal(_hit(n_of(0.40), gen, ms=6.0, lo=40.0, hi=2200.0,
	                            sharp=3.0, click=0.35),
	                       [(68.0, 0.110, 0.60), (126.0, 0.070, 0.55), (247.0, 0.040, 0.42),
	                        (496.0, 0.020, 0.26)])), 0, 0.85)
	add_at(out, unit(modal(_hit(n_of(0.12), gen, ms=0.5, lo=1400.0, hi=9000.0,
	                            sharp=9.0, click=0.55),
	                       [(1880.0, 0.008, 0.55), (3420.0, 0.004, 0.35)])), n_of(0.070), 0.30)
	add_at(out, _glass(n_of(0.42), gen, 2260.0, tau=0.060), n_of(0.330), 0.44)
	for i, f in enumerate((73.42, 110.00, 146.83)):            # D2 A2 D3 — an open fifth
		add_at(out, _brass(f, n_of(1.15), gen, 0.62 - 0.06 * i, rip_cents=0.0,
		                   attack=0.22, release=0.52, bright=0.55),
		       n_of(0.240 + 0.030 * i), 0.44)
	return _finish(out, -3.6, wet=0.22, rt60=1.15, predelay=0.018, tilt_db=-2.5, taper=0.22)


def dome_loop() -> np.ndarray:
	"""CITY HALL: the longest shot in the game, made (docs/02 R7).

	The one moment allowed to leave the key. Everything else in KINGPIN is D minor or its
	relative major; the dome lifts to D MAJOR — the same D the band is already sitting on,
	with the third raised — so it does not modulate away from the score so much as switch
	a light on inside it. That lift is spent here and nowhere else.

	Three layers: the ball going round the dome (a rush that only ever rises), a
	glockenspiel arpeggio up the triad, and a bell at D6 landing on a brass chord. Under
	the knocker on the ladder and over everything else that has a pitch.
	"""
	gen = rng("dome_loop")
	n = n_of(2.10)
	out = np.zeros(n)
	climb_n = n_of(0.52)
	ramp = np.linspace(0.0, 1.0, climb_n) ** 0.80
	centre = 620.0 * (1.0 + 7.0 * ramp)
	air = sweep_filter(noise(climb_n, gen), centre, q=1.6, kind="bp")
	air = sweep_filter(air, centre * 1.50, q=0.70, kind="lp")
	add_at(out, unit(air * (ramp ** 1.3) * asr_env(climb_n, 0.025, 0.10, 1.2)), 0, 0.42)
	for i, f in enumerate((587.33, 739.99, 880.00, 1174.66)):        # D5 F#5 A5 D6
		g_n = n_of(0.70)
		add_at(out, unit(modal(_hit(g_n, gen, ms=0.40, lo=1800.0, hi=13000.0,
		                            sharp=10.0, click=0.80),
		                       [(f, 0.115, 1.00), (f * 1.0022, 0.108, 0.50),
		                        (f * 2.758, 0.048, 0.30), (f * 5.404, 0.020, 0.12)])),
		       n_of(0.240 + 0.075 * i), 0.30 + 0.09 * i)
	bell_n = n_of(1.35)
	bell = modal(_hit(bell_n, gen, ms=0.55, lo=2000.0, hi=14000.0, sharp=9.0, click=0.90),
	             [(1174.66, 0.520, 1.00), (1177.20, 0.500, 0.55),
	              (1174.66 * 2.758, 0.190, 0.28), (1174.66 * 5.404, 0.070, 0.10)])
	add_at(out, unit(bell * (1.0 + 0.09 * np.sin(2.0 * np.pi * 6.0 * t_axis(bell_n)))),
	       n_of(0.560), 1.00)
	for i, f in enumerate((146.83, 293.66, 369.99, 440.00)):         # D3 D4 F#4 A4
		add_at(out, _brass(f, n_of(1.15), gen, 0.88 - 0.05 * i, rip_cents=50.0,
		                   attack=0.028, release=0.44, bright=0.92),
		       n_of(0.545 + 0.012 * i), 0.34)
	add_at(out, _drum(73.42, n_of(1.10), gen, 0.90, tau=0.36, head_hz=720.0), n_of(0.540), 0.50)
	return _finish(out, -1.55, wet=0.20, rt60=0.95, predelay=0.014, tilt_db=1.5, taper=0.16)


def heist_start() -> np.ndarray:
	"""The crew moves (docs/05 §5). Nobody says anything, because nobody has to.

	The quietest "mode starting" sound in the game and the only one built out of
	*restraint*: a watch ticked three times, a car door pushed to rather than slammed,
	and a single muted horn on the tonic. Loud is what `heist_blown` is for.
	"""
	gen = rng("heist_start")
	n = n_of(1.50)
	out = np.zeros(n)
	for i, at in enumerate((0.000, 0.230, 0.460)):
		tick_n = n_of(0.06)
		add_at(out, unit(modal(_hit(tick_n, gen, ms=0.30, lo=1600.0, hi=11000.0,
		                            sharp=11.0, click=0.50, click_ms=0.07),
		                       [(3180.0, 0.0035, 0.60), (5960.0, 0.0018, 0.35),
		                        (980.0, 0.0080, 0.25)])), n_of(at), 0.34 - 0.04 * i)
	add_at(out, unit(modal(_hit(n_of(0.36), gen, ms=5.0, lo=45.0, hi=2600.0,
	                            sharp=3.2, click=0.45),
	                       [(78.0, 0.095, 0.62), (148.0, 0.062, 0.55), (292.0, 0.034, 0.42),
	                        (588.0, 0.017, 0.26)])), n_of(0.560), 0.85)
	add_at(out, _paper(n_of(0.40), gen, 1100.0, 6000.0, tau=0.09, grip=0.55), n_of(0.640), 0.22)
	add_at(out, _brass(146.83, n_of(0.86), gen, 0.72, rip_cents=25.0, attack=0.070,
	                   release=0.34, bright=0.58), n_of(0.600), 0.55)
	return _finish(out, -4.4, wet=0.16, rt60=0.72, predelay=0.014, tilt_db=-2.0, taper=0.20)


def heist_beat() -> np.ndarray:
	"""One beat of the sequence lands: a tumbler drops and the crew moves on.

	It fires five or six times inside a heist, so it is punctuation and it is short — the
	same argument `rollover_click` makes. The confirming ping is A5, the chime unit's own
	A, so a beat landing under a Wire draw is a unison and not a wrong note.
	"""
	gen = rng("heist_beat")
	n = n_of(0.34)
	out = np.zeros(n)
	add_at(out, unit(modal(_hit(n_of(0.16), gen, ms=0.9, lo=500.0, hi=7000.0,
	                            sharp=7.0, click=0.70, click_ms=0.11),
	                       [(305.0, 0.0180, 0.55), (712.0, 0.0100, 0.60),
	                        (1520.0, 0.0055, 0.42), (2980.0, 0.0028, 0.22)])), 0, 1.00)
	ping_n = n_of(0.26)
	add_at(out, unit(modal(_hit(ping_n, gen, ms=0.35, lo=1600.0, hi=12000.0,
	                            sharp=10.0, click=0.75),
	                       [(880.00, 0.070, 1.00), (880.00 * 1.0024, 0.066, 0.50),
	                        (880.00 * 2.758, 0.026, 0.22)])), n_of(0.038), 0.60)
	return _finish(out, -7.05, wet=0.10, rt60=0.34, tilt_db=0.5, taper=0.24)


def heist_blown() -> np.ndarray:
	"""It went loud. Somebody hit a sensor and the building found out.

	An alarm bell hammering on its gong twice a second (the real ones strike about
	that fast and never quite the same twice), a tritone in the brass — D against Ab,
	the interval a plan makes when it stops working — and the door that ends it.
	"""
	gen = rng("heist_blown")
	n = n_of(1.50)
	out = np.zeros(n)
	for i, at in enumerate((0.000, 0.135, 0.270, 0.405, 0.540)):
		add_at(out, _desk_bell(n_of(0.52), gen, 1810.0 * (1.0 + 0.004 * (i % 3)), 0.30),
		       n_of(at), 0.72 - 0.05 * i)
	for i, f in enumerate((146.83, 207.65, 293.66)):                # D3 Ab3 D4 — a tritone
		add_at(out, _brass(f, n_of(1.05), gen, 0.90 - 0.06 * i, rip_cents=80.0,
		                   attack=0.020, release=0.30, bright=0.86),
		       n_of(0.030 + 0.014 * i), 0.50)
	add_at(out, _cell_door(n_of(0.60), gen, gain_low=1.15), n_of(0.820), 0.62)
	return _finish(out, -2.8, wet=0.15, rt60=0.70, predelay=0.013, tilt_db=1.0, taper=0.16)


def election_win() -> np.ndarray:
	"""The Puppet Mayor takes City Hall (docs/05 §8).

	A civic tower bell struck twice — its tierce is a minor third, so the biggest public
	victory in the game still has something wrong with it — with an F major flourish over
	the top, the score's relative major, the same key the casino pays in. The crowd is
	paper: a thousand ballots and a ticker-tape window, which is the only honest way to
	do a crowd without a crowd.
	"""
	gen = rng("election_win")
	n = n_of(2.00)
	out = np.zeros(n)
	add_at(out, _tower_bell(n_of(1.85), gen, 174.61, tail=1.00), 0, 1.00)
	add_at(out, _tower_bell(n_of(1.40), gen, 175.30, tail=0.80), n_of(0.480), 0.52)
	for i, f in enumerate((349.23, 523.25, 698.46)):                # F4 C5 F5
		add_at(out, _brass(f, n_of(1.05), gen, 0.86 - 0.05 * i, rip_cents=65.0,
		                   attack=0.022, release=0.32), n_of(0.220 + 0.012 * i), 0.40)
	add_at(out, _drum(87.31, n_of(0.95), gen, 0.85, tau=0.32, head_hz=740.0), n_of(0.215), 0.46)
	# The ticker is confetti, not the event: at any more than this the paper owns the
	# spectrum and the bell — which is the whole reason this sound is a bell — becomes
	# something happening behind it.
	ticker = np.zeros(n)
	for i in range(26):
		add_at(ticker, _paper(n_of(0.16), gen, 1400.0, 7200.0, tau=0.030, grip=0.60),
		       n_of(float(gen.uniform(0.24, 1.60))), float(gen.uniform(0.18, 0.50)))
	out += 0.18 * unit(ticker)
	return _finish(out, -1.95, wet=0.20, rt60=1.00, predelay=0.015, tilt_db=0.5, taper=0.16)


def empire_start() -> np.ndarray:
	"""EMPIRE MODE. Every feature lit, every stem playing, x10 on everything (docs/02 R7).

	The biggest sound in the game that is not the knocker, and it gets there by *width*
	rather than by level: a timpani roll under a plate swelling into a struck bell, the
	whole horn section on a Dm add9 spread over three octaves, and the drum. The peak
	still sits under the rank-up pair — the ladder is a promise about which sound wins
	when two land on the same frame, and a mode starting never beats a career moving.
	"""
	gen = rng("empire_start")
	n = n_of(2.20)
	out = np.zeros(n)
	roll = np.zeros(n)
	at = 0.010
	gap = 0.058
	for i in range(14):
		add_at(roll, _drum(58.27, n_of(0.55), gen, 0.35 + 0.65 * (i / 13.0),
		                   tau=0.24, head_hz=560.0), n_of(at), 0.30 + 0.70 * (i / 13.0))
		at += gap
		gap *= 0.955
	out += 0.62 * unit(roll)
	swell_n = n_of(0.70)
	add_at(out, _gong(swell_n, gen, 155.56, tau=0.55, bright=1.15)
	       * np.linspace(0.0, 1.0, swell_n) ** 1.6, 0, 0.55)
	add_at(out, _gong(n_of(1.55), gen, 220.00, tau=1.05, bright=1.30), n_of(0.700), 0.72)
	for i, f in enumerate((73.42, 146.83, 220.00, 293.66, 349.23, 440.00, 587.33)):
		add_at(out, _brass(f, n_of(1.45), gen, 0.94 - 0.035 * i, rip_cents=70.0,
		                   attack=0.022, release=0.40), n_of(0.700 + 0.010 * i), 0.34)
	add_at(out, _brass(659.26, n_of(1.30), gen, 0.60, rip_cents=45.0, attack=0.045,
	                   release=0.40), n_of(0.790), 0.24)        # the add9, up top
	add_at(out, _drum(73.42, n_of(1.30), gen, 1.0, tau=0.42, head_hz=720.0), n_of(0.695), 0.72)
	add_at(out, _register_bell(n_of(1.10), gen, 1760.0, 1.00), n_of(0.705), 0.34)
	return _finish(out, -1.65, wet=0.22, rt60=1.15, predelay=0.016, tilt_db=1.0, taper=0.16)


def empire_end() -> np.ndarray:
	"""Sixty seconds are up and the city goes back to being a city.

	The reverse of the start and built from the same parts, played backwards in shape:
	the chord sags a whole tone instead of arriving, the plate is struck once and damped
	rather than swelled, and the last thing in it is one coin, because there is always
	one still rolling when the lights come up.
	"""
	gen = rng("empire_end")
	n = n_of(1.80)
	out = np.zeros(n)
	sag_n = n_of(1.15)
	hold = n_of(0.34)
	bend = np.ones(sag_n)
	bend[hold:] = expline(sag_n - hold, 1.0, 2.0 ** (-2.0 / 12.0))
	for i, f in enumerate((146.83, 293.66, 349.23, 440.00)):
		add_at(out, _brass(f, sag_n, gen, 0.82 - 0.06 * i, rip_cents=18.0, attack=0.045,
		                   release=0.46, bright=0.70, bend=bend), n_of(0.010), 0.52)
	add_at(out, _gong(n_of(0.90), gen, 130.81, tau=0.42, bright=0.75), n_of(0.020), 0.44)
	add_at(out, _metal_ping(n_of(0.55), gen, 2740.0, tau=0.085), n_of(1.170), 0.26)
	return _finish(out, -4.05, wet=0.20, rt60=1.05, predelay=0.015, tilt_db=-1.5, taper=0.18)


def reunion_start() -> np.ndarray:
	"""The five-ball Family Reunion: the trough empties and everybody is on the table.

	Five kicks, accelerating, because the trough fires as fast as it can reload — and
	then the family chord, Dm with the sixth in it, the same voicing `meeting_end` leaves
	unresolved. This one resolves.
	"""
	gen = rng("reunion_start")
	n = n_of(1.60)
	out = np.zeros(n)
	at = 0.010
	gap = 0.135
	for i in range(5):
		add_at(out, _kicker(n_of(0.34), gen, 0.80 + 0.05 * i), n_of(at), 0.72 + 0.07 * i)
		at += gap
		gap *= 0.90
	for i, f in enumerate((146.83, 220.00, 293.66, 349.23, 246.94)):   # D A D F B — Dm6
		add_at(out, _brass(f, n_of(1.05), gen, 0.84 - 0.05 * i, rip_cents=45.0,
		                   attack=0.030, release=0.36, bright=0.88),
		       n_of(0.480 + 0.014 * i), 0.44)
	add_at(out, _drum(73.42, n_of(1.00), gen, 0.90, tau=0.34, head_hz=700.0), n_of(0.475), 0.55)
	return _finish(out, -2.55, wet=0.18, rt60=0.88, predelay=0.014, tilt_db=0.5, taper=0.16)


def briefcase_drop() -> np.ndarray:
	"""A mystery briefcase lands on the playfield (docs/03 §3).

	Leather is nearly all damping: the modes are wide, low and gone inside 60 ms, and
	what you actually hear is the two latches rattling and whatever is inside it
	shifting. If this rings, it is a suitcase made of wood.
	"""
	gen = rng("briefcase_drop")
	n = n_of(0.62)
	out = np.zeros(n)
	add_at(out, unit(modal(_hit(n_of(0.28), gen, ms=5.5, lo=50.0, hi=2400.0,
	                            sharp=3.0, click=0.40),
	                       [(84.0, 0.055, 0.62), (163.0, 0.036, 0.52), (330.0, 0.020, 0.38),
	                        (690.0, 0.010, 0.22)])), 0, 1.00)
	for at, det in ((0.024, 1.00), (0.041, 1.06)):
		add_at(out, unit(modal(_hit(n_of(0.14), gen, ms=0.40, lo=1300.0, hi=10000.0,
		                            sharp=10.0, click=0.55),
		                       [(2340.0 * det, 0.0060, 0.60), (4180.0 * det, 0.0030, 0.35),
		                        (7600.0 * det, 0.0016, 0.15)])), n_of(at), 0.34)
	add_at(out, _paper(n_of(0.26), gen, 900.0, 5200.0, tau=0.045, grip=0.50), n_of(0.030), 0.20)
	return _finish(out, -5.5, wet=0.09, rt60=0.38, tilt_db=-1.5, taper=0.22)


def briefcase_leave() -> np.ndarray:
	"""Nobody opened it, so it goes away again — and it takes whatever was in it.

	Two latches snapping shut, leather dragged off a surface, and a two-note fall on a
	single muted horn: A3 down to F3, the smallest possible way to say "that was yours".
	The quietest event in the wave, because a missed opportunity does not get a fanfare.
	"""
	gen = rng("briefcase_leave")
	n = n_of(0.85)
	out = np.zeros(n)
	for at, det in ((0.000, 1.00), (0.062, 0.96)):
		add_at(out, unit(modal(_hit(n_of(0.16), gen, ms=0.45, lo=1200.0, hi=9500.0,
		                            sharp=9.0, click=0.65),
		                       [(1980.0 * det, 0.0075, 0.62), (3640.0 * det, 0.0038, 0.36),
		                        (6900.0 * det, 0.0018, 0.16)])), n_of(at), 0.72)
	drag_n = n_of(0.30)
	add_at(out, _scrape(drag_n, gen, 620.0, 300.0, q=4.0, walk_hz=45.0, depth=0.35)
	       * asr_env(drag_n, 0.030, 0.16, 1.2), n_of(0.140), 0.30)
	for at, f in ((0.230, 220.00), (0.400, 174.61)):                 # A3 -> F3
		add_at(out, _brass(f, n_of(0.42), gen, 0.62, rip_cents=15.0, attack=0.055,
		                   release=0.22, bright=0.54), n_of(at), 0.50)
	return _finish(out, -7.5, wet=0.17, rt60=0.72, predelay=0.014, tilt_db=-2.0, taper=0.22)


def skip_town() -> np.ndarray:
	"""One held note, and the game's saddest sequence starts under it (docs/06 §1).

	This is the handoff: `AudioDirector.play_farewell()` sheds the band stem by stem
	behind it, so the event itself has to be the *least* eventful thing in the set — a
	single bowed D3, the note the whole score is built on, swelling in over a quarter of
	a second and taking two more to leave. No percussion, no bell, nothing that could be
	read as a reward. The last thing you hear before the band starts packing up.
	"""
	gen = rng("skip_town")
	n = n_of(2.60)
	t = t_axis(n)
	f0 = 146.83
	# bowed rather than blown: a saw through a body, with the bow's own noise on it and
	# a vibrato that only arrives once the note is already sounding
	vib = 1.0 + 0.0035 * np.sin(2.0 * np.pi * 4.4 * t) * np.clip((t - 0.55) / 0.9, 0.0, 1.0)
	string = bl_saw(f0 * vib, n, cap=40) + 0.5 * bl_saw(f0 * 2.0 * vib, n, cap=24)
	body = formants(string, [(320.0, 3.2, 1.00), (640.0, 2.6, 0.45), (1180.0, 3.0, 0.22)])
	bow = bandpass(noise(n, gen), 900.0, 4200.0, order=2) * 0.05
	tone = lowpass(body + 0.55 * string + bow, 3400.0, order=2)
	env = asr_env(n, 0.26, 1.35, 1.6) * (0.88 + 0.12 * np.sin(2.0 * np.pi * 0.5 * t))
	# Peak-placed well under its neighbours on purpose: this is a continuous tone with
	# an 11 dB crest, and normalising it to a transient's peak would make the quietest
	# moment in the game the loudest thing in the set (the `bribe_paid` trade).
	return _finish(unit(tone * env), -6.0, wet=0.26, rt60=1.45, predelay=0.020,
	               tilt_db=-2.5, taper=0.24)


def train_away() -> np.ndarray:
	"""The train window: the last four seconds of a city (docs/06 §1).

	Two horn calls and the rail underneath them. The horn is a chord — one pipe is a
	boat, three or four beating against each other is a locomotive — pitched on the
	score's own D minor seventh, band-limited to 2 kHz and mostly reverb, because it is
	already a long way off when you hear it. The rail is bogies, not sleepers: four
	wheels cross each joint, so the clicks come in pairs of pairs, and the pattern slows
	by a hair across the file because the whole thing is still accelerating away.

	`AudioDirector.play_farewell()` fires this last, over the fade of the final bass
	note, and returns when it has finished.
	"""
	gen = rng("train_away")
	n = n_of(3.80)
	out = np.zeros(n)
	# the rail: bogie pairs, quieter and duller as the train goes
	period = 0.470
	at = 0.060
	i = 0
	while at < 3.30:
		away = at / 3.30
		for pair, offset in enumerate((0.0, 0.082)):
			for wheel, w_off in enumerate((0.0, 0.030)):
				click_n = n_of(0.09)
				f0 = 720.0 * float(gen.uniform(0.88, 1.16))
				click = unit(modal(_hit(click_n, gen, ms=0.9, lo=180.0, hi=5200.0,
				                        sharp=7.0, click=0.60, click_ms=0.12),
				                   [(f0, 0.0130, 0.55), (f0 * 2.05, 0.0070, 0.50),
				                    (f0 * 3.85, 0.0035, 0.26), (168.0, 0.0260, 0.40)]))
				add_at(out, click, n_of(at + offset + w_off),
				       (0.80 - 0.52 * away) * (1.0 - 0.14 * pair) * (1.0 - 0.20 * wheel))
		at += period * (1.0 + 0.020 * i)
		i += 1
	# the roll of the wheels between the joints, and the air moving with it
	roll = bandpass(noise(n, gen), 90.0, 1600.0, order=2)
	roll *= (0.42 - 0.30 * np.linspace(0.0, 1.0, n)) * (0.75 + 0.25 * np.sin(2.0 * np.pi * 2.13 * t_axis(n)))
	out += 0.55 * unit(roll)
	# and the horn: long, short, the way a grade crossing is called
	horn_a = _far_horn(n_of(1.30), gen, (146.83, 174.61, 220.00, 261.63),
	                   sag_cents=40.0, attack=0.16, release=0.55)
	add_at(out, horn_a, n_of(0.420), 0.95)
	horn_b = _far_horn(n_of(0.85), gen, (146.83, 174.61, 220.00, 261.63),
	                   sag_cents=70.0, attack=0.13, release=0.42)
	add_at(out, horn_b, n_of(2.020), 0.62)
	return _finish(out, -7.0, wet=0.42, rt60=1.70, predelay=0.026, tilt_db=-3.0, taper=0.22)


# ------------------------------------------------------------------- registry

# Events that are designed to be looped rather than fired once. AudioDirector sets
# loop_mode on these; generate.py holds them to the music loop-seam standard.
LOOP_EVENTS: dict[str, float] = {
	"bill_counter": BILL_COUNTER_SECONDS,
	"siren": SIREN_SECONDS,
	"wheel_clatter": WHEEL_CLATTER_SECONDS,
}

# docs/08 §8 velocity layers: family -> (soft, medium, hard) file stems, quietest first.
# The medium entry is the family's own event name, because the medium layer IS the file
# that already shipped. AudioDirector picks a rung from the `impact` option.
VELOCITY_LAYERS: dict[str, tuple[str, str, str]] = {
	"flipper_up": ("flipper_up_soft", "flipper_up", "flipper_up_hard"),
	"bumper_hit": ("bumper_hit_soft", "bumper_hit", "bumper_hit_hard"),
	"sling_hit": ("sling_hit_soft", "sling_hit", "sling_hit_hard"),
}

# Order matches specs/audio-pipeline.md §4.
EVENTS: dict[str, callable] = {
	"flipper_up": flipper_up,
	"flipper_down": flipper_down,
	"bumper_hit": bumper_hit,
	"sling_hit": sling_hit,
	"plunger_pull": plunger_pull,
	"plunger_launch": plunger_launch,
	"ball_spawn": ball_spawn,
	"drain": drain,
	"nudge_thump": nudge_thump,
	"tilt_warning": tilt_warning,
	"tilt": tilt,
	"knocker": knocker,
	"cash_tick": cash_tick,
	"chime_a": chime_a,
	"chime_b": chime_b,
	"chime_c": chime_c,
	"wall_tap": wall_tap,
	# --- wave 2, specs/audio-wave2.md §1: mechanics ---
	"rollover_click": rollover_click,
	"spinner_tick": spinner_tick,
	"drop_clack": drop_clack,
	"drop_bank_down": drop_bank_down,
	"drop_bank_reset": drop_bank_reset,
	"kickback": kickback,
	"orbit_whoosh": orbit_whoosh,
	# --- wave 2: fiction ---
	"storefront_collect": storefront_collect,
	"laundromat_wash": laundromat_wash,
	"bribe_paid": bribe_paid,
	"guy_pinched": guy_pinched,
	"bail_paid": bail_paid,
	"safe_open": safe_open,
	"stamp_thunk": stamp_thunk,
	"paper_slip": paper_slip,
	"job_done": job_done,
	"skill_shot_ding": skill_shot_ding,
	"combo_2": combo_2,
	"combo_3": combo_3,
	"combo_4": combo_4,
	"headline_sting": headline_sting,
	"rankup_fanfare": rankup_fanfare,
	"bill_counter": bill_counter,
	"coin_drop": coin_drop,
	"siren": siren,
	"raid_start": raid_start,
	"raid_win": raid_win,
	"raid_lose": raid_lose,
	# --- wave 3, specs/m2-content.md §1/§4: the Club deck ---
	"wheel_clatter": wheel_clatter,
	"chip_stack": chip_stack,
	"card_riffle": card_riffle,
	"reel_stop": reel_stop,
	"jackpot": jackpot,
	"meeting_start": meeting_start,
	"meeting_jackpot": meeting_jackpot,
	"meeting_end": meeting_end,
	"radio_squelch": radio_squelch,
	"staircase_crest": staircase_crest,
	# --- wave 4, specs/m3-fall-rise.md AUDIO-4: the endgame ---
	"boss_start": boss_start,
	"boss_phase": boss_phase,
	"boss_beaten": boss_beaten,
	"wrench_telegraph": wrench_telegraph,
	"crane_telegraph": crane_telegraph,
	"crane_pull": crane_pull,
	"container_break": container_break,
	"pier_splash": pier_splash,
	"smuggling_start": smuggling_start,
	"shipment_out": shipment_out,
	"chair_take": chair_take,
	"sitdown": sitdown,
	"dome_loop": dome_loop,
	"heist_start": heist_start,
	"heist_beat": heist_beat,
	"heist_blown": heist_blown,
	"election_win": election_win,
	"empire_start": empire_start,
	"empire_end": empire_end,
	"reunion_start": reunion_start,
	"briefcase_drop": briefcase_drop,
	"briefcase_leave": briefcase_leave,
	"skip_town": skip_town,
	"train_away": train_away,
	# --- wave 3: velocity layers (docs/08 §8). Not events — extra rungs under three
	# events that already exist, so they are rendered here but never named by gameplay.
	"flipper_up_soft": flipper_up_soft,
	"flipper_up_hard": flipper_up_hard,
	"bumper_hit_soft": bumper_hit_soft,
	"bumper_hit_hard": bumper_hit_hard,
	"sling_hit_soft": sling_hit_soft,
	"sling_hit_hard": sling_hit_hard,
}

# Pitched events, and what they must actually measure. combo_* are the chime pitches an
# octave up, so a combo landing on a Wire draw harmonises instead of clashing; verified
# by autocorrelation in generate.py rather than by assertion.
PITCHED_EVENTS: dict[str, tuple[float, float]] = {
	# event: (target Hz, seconds into the file to start measuring)
	"chime_a": (587.33, 0.05),
	"chime_b": (698.46, 0.05),
	"chime_c": (880.00, 0.05),
	"combo_2": (1174.66, 0.03),
	"combo_3": (1396.91, 0.03),
	"combo_4": (1760.00, 0.03),
	"skill_shot_ding": (1760.00, 0.12),
	"tilt_warning": (1046.50, 0.05),
	# The Club's own bar, two octaves above chime_a — measured after the whoosh has
	# finished so nothing but the bar is left in the window.
	"staircase_crest": (2349.32, 0.42),
	# Wave 4. The dome's bell is D6, one octave over the chime unit's D5 and one under
	# the Club's D7 — the three tuned rewards of the table are the same note in three
	# registers. Measured late, once the horns are into their release and the bell is
	# the only thing left holding that pitch.
	"dome_loop": (1174.66, 1.40),
	# The Skip Town note IS the score's tonic: D3, the note the bass line walks from.
	# Nothing else in the file lives inside the search band, so this measures the note
	# itself rather than a partial of it.
	"skip_town": (146.83, 0.70),
}


def render(event: str) -> np.ndarray:
	return EVENTS[event]()
