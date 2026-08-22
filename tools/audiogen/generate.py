#!/usr/bin/env python3
"""CLI: render every sound in the game.

    python3 tools/audiogen/generate.py [--only sfx|music] [--out assets/audio]

Deterministic — two runs produce byte-identical files. Every render is verified
numerically before it is allowed to land (levels, tuning, loop continuity), because
nobody is listening to CI.
"""

from __future__ import annotations

import argparse
import math
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

if __package__ in (None, ""):                      # allow `python3 tools/audiogen/generate.py`
	sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
	__package__ = "audiogen"

from . import music, sfx  # noqa: E402
from . import theory as th  # noqa: E402
from .analysis import (  # noqa: E402
	describe, loop_report, lufs_integrated, peak_db, pitch_autocorr, rms_db, sanity,
)
from .synth import SR, db2lin, n_of, rng  # noqa: E402

# libsndfile's compression_level runs 0 (best quality) .. 1 (smallest);
# Vorbis quality = 1 - compression_level, so this is the spec's ~q0.6.
VORBIS_COMPRESSION = 0.4

PEAK_CEILING_DB = -1.5
BASS_TUNING_TOLERANCE_CENTS = 5.0
LOOP_WRAP_RATIO_MAX = 1.5      # step across the seam vs. the loudest step in the file
LOOP_EDGE_RMS_MIN = 0.02       # both ends must actually be ringing, not faded to silence


class Failure(Exception):
	pass


# ------------------------------------------------------------------ file output


def write_wav(path: Path, mono: np.ndarray) -> dict:
	path.parent.mkdir(parents=True, exist_ok=True)
	sf.write(str(path), mono.astype(np.float32), SR, subtype="PCM_16")
	back, sr = sf.read(str(path), dtype="float64")
	if sr != SR:
		raise Failure(f"{path.name}: wrote {sr} Hz")
	info = describe(back, SR)
	info["name"] = path.name
	info["bytes"] = path.stat().st_size
	return info


def write_ogg(path: Path, stereo: np.ndarray) -> tuple[dict, np.ndarray]:
	path.parent.mkdir(parents=True, exist_ok=True)
	sf.write(str(path), stereo.astype(np.float32), SR, format="OGG", subtype="VORBIS",
	         compression_level=VORBIS_COMPRESSION)
	back, sr = sf.read(str(path), dtype="float64", always_2d=True)
	if sr != SR:
		raise Failure(f"{path.name}: wrote {sr} Hz")
	info = describe(back, SR)
	info["name"] = path.name
	info["bytes"] = path.stat().st_size
	info["lufs"] = lufs_integrated(back, SR)
	info.update(loop_report(back))
	return info, back


# ------------------------------------------------------------------- rendering


def render_sfx(out_dir: Path) -> list[dict]:
	rows: list[dict] = []
	for event in sfx.EVENTS:
		buf = sfx.render(event)
		issues = sanity(buf)
		if issues:
			raise Failure(f"{event}: {', '.join(issues)}")
		if peak_db(buf) > PEAK_CEILING_DB + 0.05:
			raise Failure(f"{event}: peak {peak_db(buf):.2f} dBFS exceeds the ceiling")
		info = write_wav(out_dir / f"{event}.wav", buf)
		if info["issues"]:
			raise Failure(f"{event}: after encode — {', '.join(info['issues'])}")
		rows.append(info)
		print(f"  sfx  {event:<15} {info['seconds']:5.3f}s  peak {info['peak_db']:6.2f} dB  "
		      f"rms {info['rms_db']:6.1f} dB  centroid {info['centroid_hz']:6.0f} Hz  "
		      f"decay {info['decay_s'] * 1000:5.0f} ms")
	return rows


def render_music(out_dir: Path) -> tuple[list[dict], np.ndarray]:
	rows: list[dict] = []
	mix = np.zeros((th.LOOP_FRAMES, 2))
	for name in th.STEM_NAMES:
		stereo = music.render_stem(name)
		if stereo.shape[0] != th.LOOP_FRAMES:
			raise Failure(f"{name}: {stereo.shape[0]} frames, expected {th.LOOP_FRAMES}")
		issues = sanity(stereo)
		if issues:
			raise Failure(f"{name}: {', '.join(issues)}")
		mix += stereo
		info, decoded = write_ogg(out_dir / f"{name}.ogg", stereo)
		if decoded.shape[0] != th.LOOP_FRAMES:
			raise Failure(f"{name}: decoded to {decoded.shape[0]} frames, "
			              f"expected {th.LOOP_FRAMES} — Vorbis padding broke the loop")
		if info["wrap_ratio"] > LOOP_WRAP_RATIO_MAX:
			raise Failure(f"{name}: loop seam step is {info['wrap_ratio']:.2f}x the "
			              f"loudest step in the file — audible click")
		if info["edge_rms_ratio"] < LOOP_EDGE_RMS_MIN:
			raise Failure(f"{name}: loop edges are near-silent "
			              f"({info['edge_rms_ratio']:.4f}) — that is a faded loop, not a seamless one")
		rows.append(info)
		print(f"  stem {name:<12} {info['seconds']:6.3f}s  peak {info['peak_db']:6.2f} dB  "
		      f"LUFS {info['lufs']:6.1f}  centroid {info['centroid_hz']:6.0f} Hz  "
		      f"seam {info['wrap_ratio']:4.2f}x  {info['bytes'] / 1024:6.1f} KiB")

	from .synth import limit_peak
	preview = limit_peak(mix, PEAK_CEILING_DB)
	info, decoded = write_ogg(out_dir / "99_preview_full.ogg", preview)
	rows.append(info)
	print(f"  mix  {'99_preview_full':<12} {info['seconds']:6.3f}s  peak {info['peak_db']:6.2f} dB  "
	      f"LUFS {info['lufs']:6.1f}  seam {info['wrap_ratio']:4.2f}x  {info['bytes'] / 1024:6.1f} KiB")
	return rows, mix


# ---------------------------------------------------------------- verification


def verify_bass_tuning() -> list[tuple[str, float, float, float]]:
	"""Every note of the walking line, synthesised in isolation and pitch-measured.

	A Karplus-Strong loop that is one sample long in the wrong direction is 3 cents
	sharp at D2 and nobody notices until the bass fights the organ. So we measure.
	"""
	results = []
	gen = rng("bass_tuning_probe")
	n = n_of(1.0)
	seen: list[str] = []
	for bar in th.BASS_LINE:
		for name in bar:
			if name in seen:
				continue
			seen.append(name)
			target = th.freq(name)
			note = music.bass_note(target, n, 1.0, gen)
			window = note[n_of(0.12): n_of(0.12) + n_of(0.55)]
			got = pitch_autocorr(window, SR, fmin=target * 0.6, fmax=target * 1.8)
			cents = th.cents_between(got, target) if got > 0.0 else float("inf")
			results.append((name, target, got, cents))
	return results


def verify_stem_lengths(paths: list[Path]) -> None:
	lengths = {}
	for p in paths:
		info = sf.info(str(p))
		lengths[p.name] = info.frames
	unique = set(lengths.values())
	if len(unique) != 1:
		raise Failure(f"stems differ in length: {lengths}")
	if unique.pop() != th.LOOP_FRAMES:
		raise Failure(f"stems are {lengths} frames, expected {th.LOOP_FRAMES}")


# -------------------------------------------------------------------- manifest


def write_manifest(path: Path, sfx_rows: list[dict], music_rows: list[dict],
                   tuning: list[tuple[str, float, float, float]], seconds: float) -> None:
	lines: list[str] = []
	add = lines.append
	add("KINGPIN — generated audio manifest")
	add("=" * 78)
	add("")
	add("Everything below is synthesised by tools/audiogen (numpy/scipy only). No samples,")
	add("no external assets, no licences: we own every byte. Regenerate with")
	add("    python3 tools/audiogen/generate.py")
	add("The generator is deterministic — a re-run reproduces these files exactly.")
	add("")
	add("Levels: -1.5 dBFS is a ceiling, not a target. SFX peaks form a deliberate ladder")
	add("(knocker loudest, cash_tick and wall_tap far below) so gameplay code does not have")
	add("to ride volume_db on every call; music stems are matched by integrated loudness")
	add("(LUFS) instead, so the stack stays balanced as stems fade in.")
	add("")

	if sfx_rows:
		add("SFX — assets/audio/sfx/*.wav  (44.1 kHz, 16-bit PCM, mono)")
		add("-" * 78)
		add(f"{'file':<22}{'dur':>8}{'peak dB':>9}{'rms dB':>9}{'crest':>8}"
		    f"{'centroid':>10}{'decay':>9}{'KiB':>8}")
		for r in sfx_rows:
			add(f"{r['name']:<22}{r['seconds']:7.3f}s{r['peak_db']:9.2f}{r['rms_db']:9.2f}"
			    f"{r['crest_db']:8.1f}{r['centroid_hz']:9.0f}Hz{r['decay_s'] * 1000:8.0f}ms"
			    f"{r['bytes'] / 1024:8.1f}")
		total = sum(r["bytes"] for r in sfx_rows)
		add(f"{'subtotal':<22}{'':>8}{'':>9}{'':>9}{'':>8}{'':>10}{'':>9}{total / 1024:8.1f}")
		add("")

	if music_rows:
		add(f"MUSIC — assets/audio/music/city1/*.ogg  (44.1 kHz, Vorbis q{1.0 - VORBIS_COMPRESSION:.1f}, stereo)")
		add(f"'Eastport 72' — {th.BPM:.0f} BPM swung, D minor, 8-bar loop, "
		    f"{th.LOOP_FRAMES} frames ({th.LOOP_SECONDS:.4f} s) each.")
		add("Chords: bars 1-2 Dm6 | 3-4 Gm7 | 5 Bb7 | 6 A7 | 7 Dm6 | 8 A7.")
		add("-" * 78)
		add(f"{'file':<22}{'frames':>9}{'dur':>9}{'peak dB':>9}{'LUFS':>8}"
		    f"{'centroid':>10}{'seam':>7}{'KiB':>8}")
		for r in music_rows:
			add(f"{r['name']:<22}{r['frames']:9d}{r['seconds']:8.3f}s{r['peak_db']:9.2f}"
			    f"{r['lufs']:8.1f}{r['centroid_hz']:9.0f}Hz{r['wrap_ratio']:7.2f}"
			    f"{r['bytes'] / 1024:8.1f}")
		total = sum(r["bytes"] for r in music_rows)
		add(f"{'subtotal':<22}{'':>9}{'':>9}{'':>9}{'':>8}{'':>10}{'':>7}{total / 1024:8.1f}")
		add("")
		add("'seam' is the sample step across the loop point divided by the 99.9th-percentile")
		add("step inside the file, measured on the DECODED Vorbis. Below 1.0 means the join is")
		add("quieter than ordinary programme material, i.e. inaudible. 99_preview_full is the")
		add("eight stems summed, for listening checks only — the game never loads it.")
		add("")

	if tuning:
		worst = max(abs(c) for _, _, _, c in tuning)
		add(f"BASS TUNING — Karplus-Strong loop verified by autocorrelation "
		    f"(worst {worst:.2f} cents, tolerance {BASS_TUNING_TOLERANCE_CENTS:.0f})")
		add("-" * 78)
		row = []
		for name, target, got, cents in tuning:
			row.append(f"{name:<4}{target:8.2f}->{got:8.2f}Hz {cents:+5.2f}c")
			if len(row) == 3:
				add("  ".join(row))
				row = []
		if row:
			add("  ".join(row))
		add("")

	grand = sum(r["bytes"] for r in sfx_rows + music_rows)
	add(f"TOTAL COMMITTED AUDIO: {grand / 1024 / 1024:.2f} MiB "
	    f"({len(sfx_rows)} SFX + {len(music_rows)} music files)")
	add(f"Generated in {seconds:.1f} s.")
	path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ------------------------------------------------------------------------ main


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Synthesise all KINGPIN audio.")
	parser.add_argument("--only", choices=["sfx", "music"], default=None,
	                    help="render only one half of the set")
	parser.add_argument("--out", default="assets/audio", type=Path,
	                    help="output root (default: assets/audio)")
	args = parser.parse_args(argv)

	out = args.out
	started = time.time()
	sfx_rows: list[dict] = []
	music_rows: list[dict] = []
	tuning: list[tuple[str, float, float, float]] = []

	try:
		if args.only in (None, "sfx"):
			print(f"SFX -> {out / 'sfx'}")
			sfx_rows = render_sfx(out / "sfx")

		if args.only in (None, "music"):
			print(f"bass tuning check ({len(set(n for b in th.BASS_LINE for n in b))} distinct notes)")
			tuning = verify_bass_tuning()
			worst_name, _, _, worst = max(tuning, key=lambda r: abs(r[3]))
			print(f"  worst: {worst_name} {worst:+.2f} cents")
			if abs(worst) > BASS_TUNING_TOLERANCE_CENTS:
				raise Failure(f"bass note {worst_name} is {worst:+.2f} cents off "
				              f"(tolerance ±{BASS_TUNING_TOLERANCE_CENTS:.0f})")

			print(f"music -> {out / 'music' / 'city1'}  "
			      f"({th.LOOP_FRAMES} frames / {th.LOOP_SECONDS:.4f} s per stem)")
			music_rows, mix = render_music(out / "music" / "city1")
			verify_stem_lengths(sorted((out / "music" / "city1").glob("0*.ogg")))
			print(f"  combined mix: {lufs_integrated(mix, SR):.1f} LUFS "
			      f"(pre-limiter), peak {peak_db(mix):.2f} dB")
	except Failure as exc:
		print(f"\nFAILED: {exc}", file=sys.stderr)
		return 1

	elapsed = time.time() - started
	manifest = out / "MANIFEST.txt"
	if args.only is None:
		write_manifest(manifest, sfx_rows, music_rows, tuning, elapsed)
		print(f"\nmanifest -> {manifest}")
	total = sum(r["bytes"] for r in sfx_rows + music_rows)
	print(f"total committed audio: {total / 1024 / 1024:.2f} MiB in {elapsed:.1f} s")
	if total > 12 * 1024 * 1024:
		print("FAILED: over the 12 MiB budget", file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
