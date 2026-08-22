"""DSP toolkit for KINGPIN's audio generator.

Everything the game hears is built from the primitives in this module: oscillators,
noise, envelopes, biquad/Butterworth filters, modal resonators, Karplus-Strong strings,
FM operators, formant banks and a cheap Schroeder room.

Conventions
-----------
* Signals are float64 numpy arrays, mono unless a function says otherwise.
* Nothing here reads a global RNG: callers pass a seeded ``numpy.random.Generator``
  (see :func:`rng`) so a full render is bit-for-bit reproducible.
* "tau" always means the exponential time constant in seconds; "t60" the time to
  -60 dB.
"""

from __future__ import annotations

import hashlib
import math

import numpy as np
from scipy import signal

SR = 44100
MASTER_SEED = 0x4B494E47  # "KING"


# --------------------------------------------------------------------------- rng


def rng(name: str) -> np.random.Generator:
	"""A generator seeded from ``name`` only.

	Deriving the seed from the caller's name (rather than drawing from one shared
	stream) keeps every sound independent: editing the bumper cannot shift the noise
	the snare gets.
	"""
	digest = hashlib.blake2b(name.encode("utf-8"), digest_size=8).digest()
	return np.random.default_rng(int.from_bytes(digest, "big") ^ MASTER_SEED)


# ------------------------------------------------------------------- conversions


def db2lin(db: float) -> float:
	return float(10.0 ** (db / 20.0))


def n_of(seconds: float, sr: int = SR) -> int:
	return int(round(seconds * sr))


def t_axis(n: int, sr: int = SR) -> np.ndarray:
	return np.arange(n, dtype=np.float64) / sr


# -------------------------------------------------------------------- envelopes


def exp_decay(n: int, tau: float, sr: int = SR) -> np.ndarray:
	return np.exp(-t_axis(n, sr) / max(tau, 1e-6))


def perc_env(n: int, attack: float, tau: float, curve: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Attack ramp (raised cosine) into an exponential tail. ``curve`` > 1 = snappier."""
	env = exp_decay(n, tau, sr) ** curve
	a = max(1, n_of(attack, sr))
	if a > 1 and a <= n:
		env[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, a))
	return env


def asr_env(n: int, attack: float, release: float, curve: float = 2.0, sr: int = SR) -> np.ndarray:
	"""Attack / sustain / release with smooth (raised-cosine) shoulders."""
	a = min(max(1, n_of(attack, sr)), n)
	r = min(max(1, n_of(release, sr)), max(1, n - a))
	env = np.ones(n)
	env[:a] = (0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, a))) ** (1.0 / curve)
	if r > 0:
		env[n - r :] *= (0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, r))) ** curve
	return env


def expline(n: int, v0: float, v1: float) -> np.ndarray:
	"""Geometric ramp — the right shape for frequency and filter sweeps."""
	v0 = max(v0, 1e-6)
	v1 = max(v1, 1e-6)
	return np.exp(np.linspace(math.log(v0), math.log(v1), n))


def smoothstep(n: int) -> np.ndarray:
	x = np.linspace(0.0, 1.0, n)
	return x * x * (3.0 - 2.0 * x)


# ------------------------------------------------------------------ oscillators


def phase_of(freq: np.ndarray | float, n: int | None = None, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
	"""Integrate an instantaneous-frequency array into phase (radians)."""
	if np.isscalar(freq):
		assert n is not None
		return phase0 + 2.0 * np.pi * float(freq) * t_axis(n, sr)
	f = np.asarray(freq, dtype=np.float64)
	return phase0 + 2.0 * np.pi * np.cumsum(f) / sr


def sine(freq: np.ndarray | float, n: int | None = None, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
	return np.sin(phase_of(freq, n, phase0, sr))


def _harmonic_limit(freq: np.ndarray | float, cap: int, sr: int) -> int:
	fmax = float(np.max(freq)) if not np.isscalar(freq) else float(freq)
	fmax = max(fmax, 1.0)
	return int(max(1, min(cap, math.floor(0.45 * sr / fmax))))


def bl_saw(freq: np.ndarray | float, n: int | None = None, phase0: float = 0.0,
           cap: int = 48, sr: int = SR) -> np.ndarray:
	"""Band-limited sawtooth by additive synthesis (tracks vibrato exactly)."""
	ph = phase_of(freq, n, phase0, sr)
	k_max = _harmonic_limit(freq, cap, sr)
	out = np.zeros_like(ph)
	for k in range(1, k_max + 1):
		out += np.sin(k * ph) / k
	return out * (2.0 / np.pi)


def bl_pulse(freq: np.ndarray | float, n: int, duty: float = 0.3, phase0: float = 0.0,
             cap: int = 40, sr: int = SR) -> np.ndarray:
	"""Band-limited pulse — two saws offset by the duty cycle."""
	ph = phase_of(freq, n, phase0, sr)
	k_max = _harmonic_limit(freq, cap, sr)
	out = np.zeros_like(ph)
	shift = 2.0 * np.pi * duty
	for k in range(1, k_max + 1):
		out += (np.sin(k * ph) - np.sin(k * ph + k * shift)) / k
	return out * (2.0 / np.pi)


def fm(freq: np.ndarray | float, n: int, ratio: float, index: np.ndarray | float,
       phase0: float = 0.0, mod_phase0: float = 0.0, sr: int = SR) -> np.ndarray:
	"""One-operator FM: carrier ``freq``, modulator ``ratio*freq``, ``index`` in radians."""
	car = phase_of(freq, n, phase0, sr)
	mod = phase_of(np.asarray(freq) * ratio if not np.isscalar(freq) else freq * ratio,
	               n, mod_phase0, sr)
	return np.sin(car + np.asarray(index) * np.sin(mod))


def noise(n: int, gen: np.random.Generator) -> np.ndarray:
	return gen.standard_normal(n)


# ---------------------------------------------------------------------- filters


def _biquad(kind: str, f0: float, q: float, gain_db: float = 0.0, sr: int = SR):
	f0 = float(np.clip(f0, 5.0, 0.48 * sr))
	q = max(q, 0.05)
	w0 = 2.0 * np.pi * f0 / sr
	cw, sw = math.cos(w0), math.sin(w0)
	alpha = sw / (2.0 * q)
	if kind == "lp":
		b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "hp":
		b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "bp":  # constant peak gain = 1
		b = [alpha, 0.0, -alpha]
		a = [1 + alpha, -2 * cw, 1 - alpha]
	elif kind == "peak":
		amp = 10.0 ** (gain_db / 40.0)
		b = [1 + alpha * amp, -2 * cw, 1 - alpha * amp]
		a = [1 + alpha / amp, -2 * cw, 1 - alpha / amp]
	elif kind == "lowshelf":
		amp = 10.0 ** (gain_db / 40.0)
		beta = 2.0 * math.sqrt(amp) * alpha
		b = [amp * ((amp + 1) - (amp - 1) * cw + beta),
		     2 * amp * ((amp - 1) - (amp + 1) * cw),
		     amp * ((amp + 1) - (amp - 1) * cw - beta)]
		a = [(amp + 1) + (amp - 1) * cw + beta,
		     -2 * ((amp - 1) + (amp + 1) * cw),
		     (amp + 1) + (amp - 1) * cw - beta]
	elif kind == "highshelf":
		amp = 10.0 ** (gain_db / 40.0)
		beta = 2.0 * math.sqrt(amp) * alpha
		b = [amp * ((amp + 1) + (amp - 1) * cw + beta),
		     -2 * amp * ((amp - 1) + (amp + 1) * cw),
		     amp * ((amp + 1) + (amp - 1) * cw - beta)]
		a = [(amp + 1) - (amp - 1) * cw + beta,
		     2 * ((amp - 1) - (amp + 1) * cw),
		     (amp + 1) - (amp - 1) * cw - beta]
	else:
		raise ValueError(f"unknown biquad kind {kind!r}")
	a = np.asarray(a, dtype=np.float64)
	b = np.asarray(b, dtype=np.float64)
	return b / a[0], a / a[0]


def biquad(x: np.ndarray, kind: str, f0: float, q: float = 0.707, gain_db: float = 0.0,
           sr: int = SR) -> np.ndarray:
	b, a = _biquad(kind, f0, q, gain_db, sr)
	return signal.lfilter(b, a, x)


def lowpass(x: np.ndarray, fc: float, order: int = 4, sr: int = SR) -> np.ndarray:
	sos = signal.butter(order, min(fc, 0.47 * sr), btype="low", fs=sr, output="sos")
	return signal.sosfilt(sos, x)


def highpass(x: np.ndarray, fc: float, order: int = 4, sr: int = SR) -> np.ndarray:
	sos = signal.butter(order, max(fc, 5.0), btype="high", fs=sr, output="sos")
	return signal.sosfilt(sos, x)


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2, sr: int = SR) -> np.ndarray:
	lo = max(lo, 5.0)
	hi = min(hi, 0.47 * sr)
	if hi <= lo * 1.02:
		hi = lo * 1.05
	sos = signal.butter(order, [lo, hi], btype="band", fs=sr, output="sos")
	return signal.sosfilt(sos, x)


def sweep_filter(x: np.ndarray, fc: np.ndarray, q: float = 1.0, kind: str = "bp",
                 gain_db: float = 0.0, block: int = 96, sr: int = SR) -> np.ndarray:
	"""Time-varying biquad: recoefficient every ``block`` samples, carrying state.

	Cheap and click-free at these block sizes — the alternative (per-sample state
	variable filter in Python) costs 100x for no audible gain.
	"""
	n = len(x)
	fc = np.asarray(fc, dtype=np.float64)
	if fc.size == 1:
		fc = np.full(n, float(fc))
	out = np.empty(n)
	zi = np.zeros(2)
	pos = 0
	while pos < n:
		end = min(pos + block, n)
		b, a = _biquad(kind, float(np.mean(fc[pos:end])), q, gain_db, sr)
		out[pos:end], zi = signal.lfilter(b, a, x[pos:end], zi=zi)
		pos = end
	return out


def circular_bandpass(x: np.ndarray, lo: float, hi: float, sr: int = SR,
                      slope: float = 1.5) -> np.ndarray:
	"""FFT-domain bandpass. Circular by construction, so a noise bed filtered with
	this stays *exactly* periodic over the buffer — the only way to get a seamless
	looping noise wash."""
	n = len(x)
	f = np.fft.rfftfreq(n, 1.0 / sr)
	hi_roll = 1.0 / np.sqrt(1.0 + (np.maximum(f, 1e-9) / hi) ** (2.0 * slope))
	lo_roll = 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1e-9)) ** (2.0 * slope))
	return np.fft.irfft(np.fft.rfft(x) * hi_roll * lo_roll, n)


# --------------------------------------------------------- resonators / modality


def mode(x: np.ndarray, freq: float, tau: float, sr: int = SR) -> np.ndarray:
	"""One resonant mode: a 2-pole filter whose ring decays with time constant ``tau``.

	The impulse response is ~ exp(-t/tau)*sin(2*pi*freq*t), normalised to unit peak
	so mode gains behave like mix levels.
	"""
	freq = float(np.clip(freq, 5.0, 0.48 * sr))
	r = math.exp(-1.0 / (max(tau, 1e-4) * sr))
	w = 2.0 * np.pi * freq / sr
	b = np.array([math.sin(w), 0.0])
	a = np.array([1.0, -2.0 * r * math.cos(w), r * r])
	return signal.lfilter(b, a, x)


def modal(exciter: np.ndarray, spec, sr: int = SR) -> np.ndarray:
	"""Exciter -> bank of tuned modes. ``spec`` = iterable of (freq, tau, gain).

	``gain`` is the mode's *energy* share, not its peak amplitude: the amplitude is
	scaled by 1/sqrt(tau) so a 10 ms mode at gain 0.5 is as loud, to the ear, as a
	100 ms mode at gain 0.5. Specifying peak amplitude instead buries every short
	bright mode under the long low ones, and the result is a set of thuds that
	disappear entirely on a phone speaker.
	"""
	out = np.zeros(len(exciter))
	for freq, tau, gain in spec:
		out += (gain / math.sqrt(max(tau, 1e-5))) * mode(exciter, freq, tau, sr)
	return out


def formants(x: np.ndarray, spec, sr: int = SR) -> np.ndarray:
	"""Parallel resonant bandpasses. ``spec`` = iterable of (freq, q, gain_lin)."""
	out = np.zeros(len(x))
	for freq, q, gain in spec:
		out += gain * biquad(x, "bp", freq, q, sr=sr)
	return out


# -------------------------------------------------------------- delay-line stuff


def _comb_fb(x: np.ndarray, delay: int, g: float) -> np.ndarray:
	"""y[i] = x[i] + g*y[i-delay], vectorised in blocks of ``delay`` (exact)."""
	y = x.astype(np.float64, copy=True)
	n = len(y)
	for start in range(delay, n, delay):
		end = min(start + delay, n)
		y[start:end] += g * y[start - delay : end - delay]
	return y


def _allpass(x: np.ndarray, delay: int, g: float) -> np.ndarray:
	"""Schroeder allpass: y[i] = -g*x[i] + x[i-delay] + g*y[i-delay]."""
	n = len(x)
	y = -g * x
	y[delay:] += x[: n - delay]
	for start in range(delay, n, delay):
		end = min(start + delay, n)
		y[start:end] += g * y[start - delay : end - delay]
	return y


def comb_ff(x: np.ndarray, delay_s: float, g: float = 0.7, sr: int = SR) -> np.ndarray:
	"""Feed-forward comb — the "mute"/"pipe" colour."""
	d = max(1, n_of(delay_s, sr))
	y = x.copy()
	y[d:] += g * x[: len(x) - d]
	return y


def fractional_delay(x: np.ndarray, delay_samples: np.ndarray) -> np.ndarray:
	"""Read x at a time-varying fractional delay (linear interp). Used for chorus."""
	n = len(x)
	idx = np.arange(n, dtype=np.float64) - np.asarray(delay_samples, dtype=np.float64)
	np.clip(idx, 0.0, n - 1.0001, out=idx)
	return np.interp(idx, np.arange(n, dtype=np.float64), x)


def chorus(x: np.ndarray, gen: np.random.Generator, voices: int = 3, base_ms: float = 16.0,
           depth_ms: float = 2.4, rate: float = 0.31, mix: float = 0.5,
           sr: int = SR) -> np.ndarray:
	n = len(x)
	t = t_axis(n, sr)
	wet = np.zeros(n)
	for v in range(voices):
		phase = 2.0 * np.pi * v / voices + float(gen.uniform(0.0, 0.7))
		rt = rate * (1.0 + 0.23 * v)
		d = (base_ms + 3.0 * v + depth_ms * np.sin(2.0 * np.pi * rt * t + phase)) * 1e-3 * sr
		wet += fractional_delay(x, d)
	wet /= voices
	return (1.0 - mix) * x + mix * wet


def schroeder_reverb(x: np.ndarray, rt60: float = 0.9, predelay: float = 0.012,
                     damp_hz: float = 5200.0, spread: float = 1.0, sr: int = SR) -> np.ndarray:
	"""Small-room Schroeder reverb: 4 parallel combs -> 2 series allpasses.

	Cheap, mono-in/mono-out; call twice with different ``spread`` for a stereo pair.
	"""
	comb_ms = np.array([29.7, 37.1, 41.1, 43.7]) * spread
	ap_ms = np.array([5.0, 1.7]) * spread
	pre = max(0, n_of(predelay, sr))
	src = np.concatenate([np.zeros(pre), lowpass(x, damp_hz, order=2, sr=sr)])[: len(x)]
	if len(src) < len(x):
		src = np.concatenate([src, np.zeros(len(x) - len(src))])
	acc = np.zeros(len(x))
	for ms in comb_ms:
		d = max(1, n_of(ms * 1e-3, sr))
		g = 10.0 ** (-3.0 * d / (sr * max(rt60, 0.05)))
		acc += _comb_fb(src, d, min(g, 0.98))
	acc *= 0.25
	for ms in ap_ms:
		acc = _allpass(acc, max(1, n_of(ms * 1e-3, sr)), 0.62)
	return lowpass(acc, damp_hz * 1.4, order=2, sr=sr)


def room(x: np.ndarray, wet: float = 0.14, rt60: float = 0.85, predelay: float = 0.012,
         damp_hz: float = 5200.0, sr: int = SR) -> np.ndarray:
	"""Dry + a little room. ``wet`` is the wet gain relative to a level-matched tail."""
	r = schroeder_reverb(x, rt60, predelay, damp_hz, 1.0, sr)
	peak = float(np.max(np.abs(r))) + 1e-12
	dry_peak = float(np.max(np.abs(x))) + 1e-12
	return x + r * (wet * dry_peak / peak)


def stereo_room(xl: np.ndarray, xr: np.ndarray, wet: float = 0.14, rt60: float = 0.85,
                predelay: float = 0.012, damp_hz: float = 5200.0, sr: int = SR):
	mono = 0.5 * (xl + xr)
	rl = schroeder_reverb(mono, rt60, predelay, damp_hz, 1.0, sr)
	rr = schroeder_reverb(mono, rt60, predelay * 1.31, damp_hz, 1.11, sr)
	peak = max(float(np.max(np.abs(rl))), float(np.max(np.abs(rr)))) + 1e-12
	dry_peak = max(float(np.max(np.abs(xl))), float(np.max(np.abs(xr)))) + 1e-12
	k = wet * dry_peak / peak
	return xl + rl * k, xr + rr * k


# ------------------------------------------------------------- Karplus-Strong


def karplus_strong(freq: float, n: int, exciter: np.ndarray, t60: float = 1.2,
                   damping: float = 0.55, sr: int = SR) -> np.ndarray:
	"""Extended Karplus-Strong, tuned to well under a cent.

	Loop: delay(L) -> one-pole lowpass (``damping``, this is what makes the highs die
	long before the fundamental does) -> loop gain -> first-order allpass supplying the
	fractional delay D.

	Tuning is the whole game here. Both the lowpass and the allpass contribute phase
	delay at the fundamental, so the integer delay is set to
	``L = floor(period - pd_lowpass) - 1`` and the allpass is asked for whatever is
	left over; the total loop delay then equals ``sr/freq`` exactly. Naive integer-delay
	KS is up to 40 cents flat at D2, which on a walking bass line is unlistenable.

	``t60`` is the fundamental's -60 dB time; the loop gain is corrected for the
	lowpass's own attenuation at the fundamental so the decay is what you asked for.
	"""
	freq = float(freq)
	w0 = 2.0 * np.pi * freq / sr
	a = float(np.clip(damping, 0.0, 0.95))
	# phase delay (samples) of y[i] = (1-a)x[i] + a*y[i-1] at the fundamental
	pd_lp = math.atan2(a * math.sin(w0), 1.0 - a * math.cos(w0)) / w0 if a > 0.0 else 0.0
	loop = sr / freq - pd_lp
	length = int(math.floor(loop)) - 1
	frac = loop - length                    # in [1, 2): the sweet spot for a 1st-order allpass
	assert length >= 2, f"frequency {freq} too high for a KS loop at {sr} Hz"
	c = (1.0 - frac) / (1.0 + frac)
	# loop gain, compensated for the lowpass's magnitude at the fundamental
	lp_mag = (1.0 - a) / math.sqrt(1.0 - 2.0 * a * math.cos(w0) + a * a) if a > 0.0 else 1.0
	g = (10.0 ** (-3.0 / (max(freq, 1e-6) * max(t60, 1e-3)))) / max(lp_mag, 1e-9)
	g = min(g, 0.99995)

	buf = [0.0] * length
	out = np.zeros(n)
	exc = np.zeros(n)
	m = min(len(exciter), n)
	exc[:m] = exciter[:m]
	exc_list = exc.tolist()
	res = [0.0] * n

	idx = 0
	lp = 0.0            # one-pole lowpass state
	ap_x = 0.0          # allpass input memory
	ap_y = 0.0          # allpass output memory
	one_minus_a = 1.0 - a

	for i in range(n):
		v = buf[idx]
		lp = one_minus_a * v + a * lp
		y = g * lp
		ap_out = c * y + ap_x - c * ap_y
		ap_x = y
		ap_y = ap_out
		res[i] = ap_out
		buf[idx] = ap_out + exc_list[i]
		idx += 1
		if idx == length:
			idx = 0
	out[:] = res
	return out


# ------------------------------------------------------------------ mastering


def dc_remove(x: np.ndarray, fc: float = 18.0, sr: int = SR) -> np.ndarray:
	return highpass(x - float(np.mean(x)), fc, order=2, sr=sr)


def fade_edges(x: np.ndarray, ms_in: float = 1.5, ms_out: float = 3.0, sr: int = SR) -> np.ndarray:
	y = x.copy()
	a = min(n_of(ms_in * 1e-3, sr), len(y) // 2)
	b = min(n_of(ms_out * 1e-3, sr), len(y) // 2)
	if a > 1:
		y[:a] *= 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, a))
	if b > 1:
		y[len(y) - b :] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, b))
	return y


def normalize_peak(x: np.ndarray, target_db: float = -1.5) -> np.ndarray:
	peak = float(np.max(np.abs(x)))
	if peak < 1e-9:
		return x
	return x * (db2lin(target_db) / peak)


def unit(x: np.ndarray, level: float = 1.0) -> np.ndarray:
	"""Scale to a known peak. Every instrument returns notes normalised this way so a
	mix gain of 0.5 means "half as loud", not "half of whatever this happened to be"."""
	peak = float(np.max(np.abs(x)))
	if peak < 1e-12:
		return x
	return x * (level / peak)


def soft_limit(x: np.ndarray, ceiling_db: float = -1.5, knee_db: float = 6.0) -> np.ndarray:
	"""Memoryless soft-knee limiter.

	Memoryless matters: a look-ahead limiter has state, so its output would not be
	periodic and the loop seam would move. A waveshaper applied to a periodic signal
	stays exactly periodic, so this is the only kind of level control allowed after the
	loop has been folded.
	"""
	ceil = db2lin(ceiling_db)
	thr = ceil * db2lin(-knee_db)
	a = np.abs(x)
	over = a > thr
	if not np.any(over):
		return x
	y = np.array(x, dtype=np.float64, copy=True)
	span = ceil - thr
	y[over] = np.sign(x[over]) * (thr + span * np.tanh((a[over] - thr) / span))
	return y


def pan(x: np.ndarray, position: float = 0.0):
	"""Constant-power pan. -1 = hard left, +1 = hard right."""
	p = (float(np.clip(position, -1.0, 1.0)) + 1.0) * 0.25 * np.pi
	return x * math.cos(p), x * math.sin(p)


def widen(xl: np.ndarray, xr: np.ndarray, amount: float = 0.25):
	"""Mid/side widening. ``amount`` 0 = untouched, 1 = doubled sides."""
	mid = 0.5 * (xl + xr)
	side = 0.5 * (xl - xr) * (1.0 + amount)
	return mid + side, mid - side


def blend(base: np.ndarray, extra: np.ndarray, ratio: float) -> np.ndarray:
	"""Mix ``extra`` under ``base`` at ``ratio`` of base's peak.

	Needed whenever a resonator is driven by a *sustained* signal rather than a strike:
	a Q-27 body mode fed a held string has a gain of ~30, so absolute mode gains are
	meaningless there and relative levels are the only sane control.
	"""
	bp = float(np.max(np.abs(base))) + 1e-12
	ep = float(np.max(np.abs(extra))) + 1e-12
	return base + extra * (ratio * bp / ep)


def add_at(buf: np.ndarray, x: np.ndarray, start: int, gain: float = 1.0) -> None:
	"""Mix ``x`` into ``buf`` at sample ``start``, clipping to the buffer end."""
	if start >= len(buf) or len(x) == 0:
		return
	if start < 0:
		x = x[-start:]
		start = 0
		if len(x) == 0:
			return
	end = min(start + len(x), len(buf))
	buf[start:end] += gain * x[: end - start]


def fold_tail(buf: np.ndarray, loop_len: int) -> np.ndarray:
	"""Wrap everything past ``loop_len`` back onto the head.

	This is what makes the loops seamless: a note (or reverb tail) that rings past the
	last bar reappears at bar 1, exactly as it would if the loop were really playing
	twice. Periodic summation commutes with the LTI processing applied before it, so
	the result is bit-identical to an infinitely repeating render.
	"""
	out = buf[:loop_len].copy()
	pos = loop_len
	while pos < len(buf):
		seg = buf[pos : pos + loop_len]
		out[: len(seg)] += seg
		pos += loop_len
	return out
