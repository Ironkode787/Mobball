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


# ------------------------------------------------------------------- flippers


def flipper_up() -> np.ndarray:
	"""Solenoid clack + bat body knock. The up-stroke is the violent one: the coil
	slams the armature into its stop and the bat rings underneath."""
	gen = rng("flipper_up")
	n = n_of(0.26)
	exc = _hit(n, gen, ms=1.3, lo=380.0, hi=8500.0, sharp=6.0, click=0.85)
	body = modal(exc, [
		(88.0, 0.052, 0.30),      # coil thunk through the cabinet
		(196.0, 0.075, 0.55),     # bat body
		(432.0, 0.044, 0.50),
		(883.0, 0.021, 0.55),
		(1615.0, 0.017, 0.70),    # armature
		(2455.0, 0.0095, 0.75),
		(3810.0, 0.0055, 0.45),
	])
	air = lowpass(noise(n, gen), 5600.0) * perc_env(n, 0.0006, 0.009, 1.4) * 0.35
	return _finish(body + air, -2.5, wet=0.07, tilt_db=2.5)


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


def bumper_hit() -> np.ndarray:
	"""Pop bumper: skin slap on the ring, springy 180 Hz body, metal shimmer."""
	gen = rng("bumper_hit")
	n = n_of(0.44)
	exc = _hit(n, gen, ms=2.4, lo=850.0, hi=7000.0, sharp=4.5, click=0.60)
	body = modal(exc, [
		(180.0, 0.220, 0.80),     # the spring the spec asks for
		(432.0, 0.120, 0.55),
		(975.0, 0.055, 0.60),
		(2310.0, 0.026, 0.62),
		(3160.0, 0.042, 0.35),    # ring metal
		(5400.0, 0.014, 0.18),
	])
	# the "pop": a fast pitch drop, the air the skirt shoves out of the way
	drop_n = n_of(0.055)
	pop = np.zeros(n)
	pop[:drop_n] = sine(expline(drop_n, 340.0, 148.0)) * exp_decay(drop_n, 0.016) ** 1.2
	slap = bandpass(noise(n, gen), 1400.0, 6000.0, order=2) * perc_env(n, 0.0008, 0.013, 1.6) * 1.1
	return _finish(body + 0.9 * pop + slap, -1.8, wet=0.09, rt60=0.36, tilt_db=2.0)


def sling_hit() -> np.ndarray:
	"""Slingshot: rubber snap into a small kicker plate. Snappier and higher than a bumper."""
	gen = rng("sling_hit")
	n = n_of(0.24)
	exc = _hit(n, gen, ms=1.4, lo=700.0, hi=9500.0, sharp=6.0, click=0.70)
	body = modal(exc, [
		(142.0, 0.048, 0.30),
		(318.0, 0.080, 0.65),
		(792.0, 0.044, 0.60),
		(1885.0, 0.022, 0.70),
		(3980.0, 0.011, 0.45),
		(6300.0, 0.006, 0.22),
	])
	twang_n = n_of(0.09)
	twang = np.zeros(n)
	twang[:twang_n] = sine(expline(twang_n, 262.0, 178.0)) * exp_decay(twang_n, 0.026) * 1.1
	return _finish(body + twang, -3.0, wet=0.07, tilt_db=2.0)


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


# ------------------------------------------------------------------- registry

# Events that are designed to be looped rather than fired once. AudioDirector sets
# loop_mode on these; generate.py holds them to the music loop-seam standard.
LOOP_EVENTS: dict[str, float] = {
	"bill_counter": BILL_COUNTER_SECONDS,
	"siren": SIREN_SECONDS,
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
}


def render(event: str) -> np.ndarray:
	return EVENTS[event]()
