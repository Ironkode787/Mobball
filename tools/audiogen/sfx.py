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
	SR, add_at, bandpass, biquad, comb_ff, dc_remove, exp_decay, expline, fade_edges,
	highpass, lowpass, modal, n_of, noise, normalize_peak, perc_env, phase_of, rng,
	room, sine, sweep_filter, t_axis,
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


# ------------------------------------------------------------------- registry

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
}


def render(event: str) -> np.ndarray:
	return EVENTS[event]()
