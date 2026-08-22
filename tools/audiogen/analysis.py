"""Measurement tools — the ears we don't have.

Nobody can listen to CI, so every render is checked numerically instead: level and
crest factor catch dead or crushed files, spectral centroid catches "everything turned
into a thud", decay time catches runaway resonators, autocorrelation pitch proves the
bass is actually in tune, and the loop report proves a stem joins itself cleanly.
"""

from __future__ import annotations

import math

import numpy as np

from .synth import SR, biquad

# ---------------------------------------------------------------- basic levels


def peak_db(x: np.ndarray) -> float:
	p = float(np.max(np.abs(x))) if x.size else 0.0
	return 20.0 * math.log10(p) if p > 1e-12 else -200.0


def rms_db(x: np.ndarray) -> float:
	r = float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0
	return 20.0 * math.log10(r) if r > 1e-12 else -200.0


def crest_db(x: np.ndarray) -> float:
	return peak_db(x) - rms_db(x)


def dc_offset(x: np.ndarray) -> float:
	return float(np.mean(x)) if x.size else 0.0


def zero_crossing_rate(x: np.ndarray, sr: int = SR) -> float:
	if x.size < 2:
		return 0.0
	return float(np.count_nonzero(np.diff(np.signbit(x)))) * sr / x.size


def spectral_centroid(x: np.ndarray, sr: int = SR) -> float:
	if x.size < 64:
		return 0.0
	n = min(x.size, 1 << 18)
	seg = x[:n] * np.hanning(n)
	mag = np.abs(np.fft.rfft(seg))
	f = np.fft.rfftfreq(n, 1.0 / sr)
	total = float(np.sum(mag))
	return float(np.sum(f * mag) / total) if total > 1e-12 else 0.0


def envelope(x: np.ndarray, win_ms: float = 5.0, sr: int = SR) -> np.ndarray:
	w = max(4, int(win_ms * 1e-3 * sr))
	pad = np.pad(np.square(x), (0, w), mode="constant")
	kernel = np.ones(w) / w
	return np.sqrt(np.convolve(pad, kernel, mode="valid")[: len(x)])


def decay_time(x: np.ndarray, drop_db: float = 40.0, sr: int = SR) -> float:
	"""Seconds from the envelope peak until it falls ``drop_db`` below it."""
	env = envelope(x, 5.0, sr)
	if env.size == 0:
		return 0.0
	i_peak = int(np.argmax(env))
	target = env[i_peak] * (10.0 ** (-drop_db / 20.0))
	below = np.nonzero(env[i_peak:] < target)[0]
	if below.size == 0:
		return (len(env) - i_peak) / sr
	return float(below[0]) / sr


# ------------------------------------------------------------------ pitch


def pitch_autocorr(x: np.ndarray, sr: int = SR, fmin: float = 35.0,
                   fmax: float = 1400.0) -> float:
	"""Fundamental in Hz, refined on a high-order autocorrelation peak.

	The coarse peak fixes the octave; the refinement then measures the m-th period
	(m chosen so m periods span ~0.2 s) which multiplies lag resolution by m. With
	parabolic interpolation on top this resolves well under one cent at bass pitches.
	"""
	x = np.asarray(x, dtype=np.float64)
	x = x - float(np.mean(x))
	n = x.size
	if n < 2048 or float(np.max(np.abs(x))) < 1e-9:
		return 0.0
	nfft = 1 << int(math.ceil(math.log2(2 * n)))
	spec = np.fft.rfft(x, nfft)
	ac = np.fft.irfft(spec * np.conj(spec), nfft)[:n]
	if ac[0] <= 0.0:
		return 0.0
	ac = ac / ac[0]

	def refine(arr: np.ndarray, k: int) -> float:
		if k <= 0 or k >= len(arr) - 1:
			return float(k)
		y0, y1, y2 = arr[k - 1], arr[k], arr[k + 1]
		den = y0 - 2.0 * y1 + y2
		if abs(den) < 1e-18:
			return float(k)
		return float(k) + 0.5 * (y0 - y2) / den

	lag_min = max(2, int(sr / fmax))
	lag_max = min(int(sr / fmin), n - 2)
	if lag_max <= lag_min + 2:
		return 0.0
	k = lag_min + int(np.argmax(ac[lag_min:lag_max]))
	coarse_lag = refine(ac, k)
	if coarse_lag <= 0.0:
		return 0.0

	m = max(1, int((0.20 * sr) / coarse_lag))
	while m > 1 and m * coarse_lag > n * 0.45:
		m -= 1
	if m == 1:
		return sr / coarse_lag
	centre = m * coarse_lag
	half = max(3.0, coarse_lag * 0.25)
	lo = max(lag_min, int(centre - half))
	hi = min(n - 2, int(centre + half))
	if hi <= lo + 2:
		return sr / coarse_lag
	k2 = lo + int(np.argmax(ac[lo:hi]))
	return float(m) * sr / refine(ac, k2)


# ------------------------------------------------------------------- loudness


def _k_weight(x: np.ndarray, sr: int) -> np.ndarray:
	"""ITU-R BS.1770-4 K-weighting (shelf + high-pass), designed at ``sr``."""
	y = biquad(x, "highshelf", 1681.9744509555319, 0.7071752369554193,
	           3.999843853973347, sr=sr)
	return biquad(y, "hp", 38.13547087602444, 0.5003270373238773, sr=sr)


def lufs_integrated(data: np.ndarray, sr: int = SR) -> float:
	"""Gated integrated loudness (LUFS). ``data`` is (n,) mono or (n, ch)."""
	arr = np.atleast_2d(np.asarray(data, dtype=np.float64).T).T
	if arr.ndim == 1:
		arr = arr[:, None]
	n, ch = arr.shape
	block = int(0.400 * sr)
	hop = int(0.100 * sr)
	if n < block:
		return -200.0
	weights = [1.0, 1.0, 1.0, 1.41, 1.41]
	z = np.zeros((n - block) // hop + 1)
	for c in range(ch):
		y = _k_weight(arr[:, c], sr)
		sq = np.square(y)
		csum = np.concatenate([[0.0], np.cumsum(sq)])
		starts = np.arange(0, n - block + 1, hop)
		mean_sq = (csum[starts + block] - csum[starts]) / block
		z += weights[min(c, 4)] * mean_sq[: len(z)]
	with np.errstate(divide="ignore"):
		loud = -0.691 + 10.0 * np.log10(np.maximum(z, 1e-20))
	keep = loud > -70.0
	if not np.any(keep):
		return -200.0
	gamma = -0.691 + 10.0 * math.log10(float(np.mean(z[keep]))) - 10.0
	keep2 = keep & (loud > gamma)
	if not np.any(keep2):
		keep2 = keep
	return float(-0.691 + 10.0 * math.log10(float(np.mean(z[keep2]))))


# ---------------------------------------------------------------------- loops


def loop_report(data: np.ndarray, edge: int = 64) -> dict:
	"""Numeric proof that a buffer joins itself without a click.

	``wrap_ratio`` compares the step across the loop point with the loudest step the
	signal makes anywhere (99.9th percentile). Below ~1 means the join is quieter
	than ordinary programme material and is inaudible. ``edge_rms_ratio`` guards the
	other failure mode: a "seamless" loop that is only seamless because both ends
	faded to silence.
	"""
	arr = np.asarray(data, dtype=np.float64)
	if arr.ndim == 1:
		arr = arr[:, None]
	overall = float(np.sqrt(np.mean(np.square(arr)))) + 1e-15
	worst_ratio = 0.0
	worst_edge = 1e9
	wrap_abs = 0.0
	for c in range(arr.shape[1]):
		x = arr[:, c]
		steps = np.abs(np.diff(x))
		typical = float(np.percentile(steps, 99.9)) + 1e-12
		wrap = abs(float(x[0]) - float(x[-1]))
		wrap_abs = max(wrap_abs, wrap)
		worst_ratio = max(worst_ratio, wrap / typical)
		head = float(np.sqrt(np.mean(np.square(x[:edge]))))
		tail = float(np.sqrt(np.mean(np.square(x[-edge:]))))
		worst_edge = min(worst_edge, min(head, tail) / overall)
	return {
		"wrap_step": wrap_abs,
		"wrap_ratio": worst_ratio,
		"edge_rms_ratio": worst_edge,
	}


# -------------------------------------------------------------------- summary


def sanity(x: np.ndarray) -> list[str]:
	"""Problems worth failing a build over."""
	issues: list[str] = []
	flat = np.asarray(x, dtype=np.float64).reshape(-1)
	if flat.size == 0:
		return ["empty buffer"]
	if not np.all(np.isfinite(flat)):
		issues.append("non-finite samples")
	peak = float(np.max(np.abs(flat)))
	if peak < 1e-4:
		issues.append("effectively silent")
	if peak >= 0.9999:
		issues.append("clipped at full scale")
	if abs(float(np.mean(flat))) > 0.01 * max(peak, 1e-9) + 1e-5:
		issues.append("DC offset")
	return issues


def describe(data: np.ndarray, sr: int = SR) -> dict:
	arr = np.asarray(data, dtype=np.float64)
	mono = arr if arr.ndim == 1 else np.mean(arr, axis=1)
	return {
		"frames": int(arr.shape[0]),
		"channels": 1 if arr.ndim == 1 else int(arr.shape[1]),
		"seconds": arr.shape[0] / sr,
		"peak_db": peak_db(arr),
		"rms_db": rms_db(arr),
		"crest_db": crest_db(arr),
		"centroid_hz": spectral_centroid(mono, sr),
		"decay_s": decay_time(mono, 40.0, sr),
		"zcr_hz": zero_crossing_rate(mono, sr),
		"dc": dc_offset(mono),
		"issues": sanity(arr),
	}
