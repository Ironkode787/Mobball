#!/usr/bin/env python3
"""CLI: render every sound in the game.

    python3 tools/audiogen/generate.py [--only sfx|music] [--out assets/audio]

Deterministic — two runs produce byte-identical files. Every render is verified
numerically before it is allowed to land (levels, tuning, loop continuity), because
nobody is listening to CI.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

if __package__ in (None, ""):                      # allow `python3 tools/audiogen/generate.py`
	sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
	__package__ = "audiogen"

from . import music, sfx, voice  # noqa: E402
from . import theory as th  # noqa: E402
from .analysis import (  # noqa: E402
	describe, loop_report, lufs_integrated, partial_hz, peak_db, pitch_autocorr, sanity,
)
from .synth import SR, n_of, rng, soft_limit  # noqa: E402

# libsndfile's compression_level runs 0 (best quality) .. 1 (smallest);
# Vorbis quality = 1 - compression_level, so this is the spec's ~q0.6.
VORBIS_COMPRESSION = 0.4

PEAK_CEILING_DB = -1.5
BASS_TUNING_TOLERANCE_CENTS = 5.0
TUNED_SFX_TOLERANCE_CENTS = 6.0
LOOP_WRAP_RATIO_MAX = 1.5      # step across the seam vs. the loudest step in the file
LOOP_EDGE_RMS_MIN = 0.02       # both ends must actually be ringing, not faded to silence
SIZE_BUDGET_MB = 32.0          # raised again for wave 4 (the endgame set + city 2)

# --- wave 3 gates -------------------------------------------------------------
# A velocity layer is a *spectral* difference, so the centroid has to move with impact by
# more than measurement noise. Anything less and the layers are the same sound at three
# volumes, which the game already has (volume_db) and does not need three files for.
LAYER_CENTROID_RATIO_MIN = 1.12

# Claims the peak ladder makes about the new events, checked against the written files
# instead of trusted. Only the claims that matter are listed: the rank-up pair owns the
# top of the ladder and the Club is not allowed to take it.
PEAK_ORDER: tuple[tuple[str, str], ...] = (
	("knocker", "rankup_fanfare"),
	("rankup_fanfare", "jackpot"),
	("jackpot", "meeting_start"),
	("meeting_start", "meeting_jackpot"),
	("meeting_jackpot", "meeting_end"),
	("knocker", "bumper_hit_hard"),
	("knocker", "staircase_crest"),
	("staircase_crest", "reel_stop"),
	("reel_stop", "wheel_clatter"),
	# --- wave 4. Two new claims carry design weight and the rest keep the endgame's own
	# families in order. dome_loop is the biggest PITCHED sound in the game and is still
	# not allowed past the knocker; empire_start is the everything-lit moment and is
	# still not allowed past the rank-up pair, because a mode starting never outranks a
	# career moving. Telegraphs sit under the events they telegraph, for the reason
	# radio_squelch does: a warning warns, it does not announce.
	("knocker", "dome_loop"),
	("dome_loop", "rankup_fanfare"),
	("rankup_fanfare", "empire_start"),
	("empire_start", "jackpot"),
	("jackpot", "election_win"),
	("election_win", "boss_beaten"),
	("boss_beaten", "boss_start"),
	("boss_start", "boss_phase"),
	("boss_phase", "wrench_telegraph"),
	("empire_start", "empire_end"),
	("reunion_start", "heist_blown"),
	("heist_blown", "heist_start"),
	("heist_start", "heist_beat"),
	("drain", "pier_splash"),
	("pier_splash", "container_break"),
	("crane_pull", "crane_telegraph"),
	("shipment_out", "smuggling_start"),
	("sitdown", "chair_take"),
	("skip_town", "train_away"),
	("briefcase_drop", "briefcase_leave"),
)

VOICE_SECONDS = (0.80, 1.60)   # docs/08 §5 phrases: long enough to read, short enough to fire
VOICE_LUFS_TOLERANCE = 2.0     # a dialogue bank that changes level per speaker is unusable
VOICE_WAH_MIN = 1.15           # the mute has to actually move
VOICE_BUMPS_MIN = 3            # ...and the loudness has to have syllables in it
# A struck voice (Skids' bell) carries a phrase on three dings and a sigh, so it
# legitimately shows fewer loudness excursions than a blown one. It still has to show
# more than one, which is all "this is not a held note" ever meant.
VOICE_BUMPS_MIN_STRUCK = 2


class Failure(Exception):
	pass


# ------------------------------------------------- reproducible Ogg containers

# libsndfile seeds each Ogg bitstream's serial number randomly, so two runs produce
# byte-different files carrying bit-identical audio. That breaks "running twice produces
# identical files" and makes every regeneration a noisy diff in git. Rewriting the serial
# to a fixed value and recomputing each page's checksum fixes it; the result is an
# ordinary, valid Ogg stream.
OGG_SERIAL = 0x4B494E47  # "KING"

_OGG_CRC_TABLE: list[int] = []
for _i in range(256):
	_r = _i << 24
	for _ in range(8):
		_r = ((_r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if _r & 0x80000000 else (_r << 1) & 0xFFFFFFFF
	_OGG_CRC_TABLE.append(_r)


def _ogg_crc(page: memoryview) -> int:
	"""Ogg's CRC-32: poly 0x04c11db7, init 0, no reflection, no final xor."""
	crc = 0
	table = _OGG_CRC_TABLE
	for byte in page:
		crc = ((crc << 8) & 0xFFFFFFFF) ^ table[((crc >> 24) & 0xFF) ^ byte]
	return crc


def canonicalise_ogg(path: Path, serial: int = OGG_SERIAL) -> None:
	data = bytearray(path.read_bytes())
	pos = 0
	end = len(data)
	while pos < end:
		if bytes(data[pos:pos + 4]) != b"OggS":
			raise Failure(f"{path.name}: not an Ogg page at offset {pos}")
		segments = data[pos + 26]
		page_len = 27 + segments + sum(data[pos + 27: pos + 27 + segments])
		data[pos + 14: pos + 18] = serial.to_bytes(4, "little")
		data[pos + 22: pos + 26] = b"\x00\x00\x00\x00"
		crc = _ogg_crc(memoryview(data)[pos: pos + page_len])
		data[pos + 22: pos + 26] = crc.to_bytes(4, "little")
		pos += page_len
	path.write_bytes(bytes(data))


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
	canonicalise_ogg(path)
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


def _check_seam(name: str, info: dict) -> None:
	if info["wrap_ratio"] > LOOP_WRAP_RATIO_MAX:
		raise Failure(f"{name}: loop seam step is {info['wrap_ratio']:.2f}x the "
		              f"loudest step in the file — audible click")
	if info["edge_rms_ratio"] < LOOP_EDGE_RMS_MIN:
		raise Failure(f"{name}: loop edges are near-silent ({info['edge_rms_ratio']:.4f}) "
		              f"— that is a faded loop, not a seamless one")


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
		# The loopable events are held to the music stems' seam standard, measured on the
		# decoded PCM rather than on the float buffer we happen to have in hand.
		if event in sfx.LOOP_EVENTS:
			want = n_of(sfx.LOOP_EVENTS[event])
			if info["frames"] != want:
				raise Failure(f"{event}: {info['frames']} frames, expected {want}")
			back, _ = sf.read(str(out_dir / f"{event}.wav"), dtype="float64")
			info.update(loop_report(back))
			_check_seam(event, info)
		rows.append(info)
		mark = f"  seam {info['wrap_ratio']:4.2f}x" if event in sfx.LOOP_EVENTS else ""
		print(f"  sfx  {event:<18} {info['seconds']:5.3f}s  peak {info['peak_db']:6.2f} dB  "
		      f"rms {info['rms_db']:6.1f} dB  centroid {info['centroid_hz']:6.0f} Hz  "
		      f"decay {info['decay_s'] * 1000:5.0f} ms{mark}")
	return rows


def render_voices(out_dir: Path) -> list[dict]:
	"""The specialists' phrase bank (docs/08 §5), one WAV per speaker per mood."""
	rows: list[dict] = []
	for stem, speaker, mood in voice.files():
		buf = voice.render(speaker, mood)
		issues = sanity(buf)
		if issues:
			raise Failure(f"{stem}: {', '.join(issues)}")
		if peak_db(buf) > PEAK_CEILING_DB + 0.05:
			raise Failure(f"{stem}: peak {peak_db(buf):.2f} dBFS exceeds the ceiling")
		info = write_wav(out_dir / f"{stem}.wav", buf)
		if info["issues"]:
			raise Failure(f"{stem}: after encode — {', '.join(info['issues'])}")
		# Measured off the written file: what the game plays is what gets checked.
		back, _ = sf.read(str(out_dir / f"{stem}.wav"), dtype="float64")
		info.update(voice.report(back))
		info["speaker"] = speaker
		info["mood"] = mood

		lo, hi = VOICE_SECONDS
		if not lo - 1e-3 <= info["seconds"] <= hi + 1e-3:
			raise Failure(f"{stem}: {info['seconds']:.2f} s is outside the "
			              f"{lo:.1f}-{hi:.1f} s phrase window")
		off = abs(info["lufs"] - voice.VOICE_LUFS)
		if off > VOICE_LUFS_TOLERANCE:
			raise Failure(f"{stem}: {info['lufs']:.1f} LUFS is {off:.1f} dB off the bank's "
			              f"{voice.VOICE_LUFS:.1f} — speakers must not change the level")
		if info["wah"] < VOICE_WAH_MIN:
			raise Failure(f"{stem}: the mute barely moves ({info['wah']:.2f}x brightest to "
			              f"dullest) — that is a held note, not a phrase")
		floor = (VOICE_BUMPS_MIN_STRUCK if voice.SPEAKER_BY_NAME[speaker].strikes > 0
		         else VOICE_BUMPS_MIN)
		if info["bumps"] < floor:
			raise Failure(f"{stem}: only {info['bumps']} loudness excursions — no prosody")
		rows.append(info)
		print(f"  voice {stem:<16} {info['seconds']:5.2f}s  peak {info['peak_db']:6.2f} dB  "
		      f"LUFS {info['lufs']:6.1f}  centroid {info['centroid_hz']:6.0f} Hz  "
		      f"wah {info['wah']:4.2f}x  bumps {info['bumps']:2d}")
	return rows


def render_music(out_dir: Path) -> tuple[list[dict], np.ndarray]:
	rows: list[dict] = []
	mix = np.zeros((th.LOOP_FRAMES, 2))
	for name in th.SYNCED_STEM_NAMES:
		stereo = music.render_stem(name)
		if stereo.shape[0] != th.LOOP_FRAMES:
			raise Failure(f"{name}: {stereo.shape[0]} frames, expected {th.LOOP_FRAMES}")
		issues = sanity(stereo)
		if issues:
			raise Failure(f"{name}: {', '.join(issues)}")
		# The preview is the calm mix: the state stems are alternates, not extra layers.
		if name in th.STEM_NAMES:
			mix += stereo
		info, decoded = write_ogg(out_dir / f"{name}.ogg", stereo)
		if decoded.shape[0] != th.LOOP_FRAMES:
			raise Failure(f"{name}: decoded to {decoded.shape[0]} frames, "
			              f"expected {th.LOOP_FRAMES} — Vorbis padding broke the loop")
		_check_seam(name, info)
		rows.append(info)
		print(f"  stem {name:<14} {info['seconds']:6.3f}s  peak {info['peak_db']:6.2f} dB  "
		      f"LUFS {info['lufs']:6.1f}  centroid {info['centroid_hz']:6.0f} Hz  "
		      f"seam {info['wrap_ratio']:4.2f}x  {info['bytes'] / 1024:6.1f} KiB")

	# The Count's piano: a different tempo and a different loop length, so it is checked
	# against its own frame count and never against the stack's.
	piano = music.render_count_piano()
	if piano.shape[0] != th.COUNT_FRAMES:
		raise Failure(f"count_piano: {piano.shape[0]} frames, expected {th.COUNT_FRAMES}")
	issues = sanity(piano)
	if issues:
		raise Failure(f"count_piano: {', '.join(issues)}")
	info, decoded = write_ogg(out_dir / "count_piano.ogg", piano)
	if decoded.shape[0] != th.COUNT_FRAMES:
		raise Failure(f"count_piano: decoded to {decoded.shape[0]} frames, "
		              f"expected {th.COUNT_FRAMES}")
	_check_seam("count_piano", info)
	rows.append(info)
	print(f"  solo {'count_piano':<14} {info['seconds']:6.3f}s  peak {info['peak_db']:6.2f} dB  "
	      f"LUFS {info['lufs']:6.1f}  centroid {info['centroid_hz']:6.0f} Hz  "
	      f"seam {info['wrap_ratio']:4.2f}x  {info['bytes'] / 1024:6.1f} KiB")

	preview = soft_limit(mix, PEAK_CEILING_DB, knee_db=7.0)
	info, decoded = write_ogg(out_dir / "99_preview_full.ogg", preview)
	rows.append(info)
	print(f"  mix  {'99_preview_full':<14} {info['seconds']:6.3f}s  peak {info['peak_db']:6.2f} dB  "
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


def verify_stem_lengths(out_dir: Path) -> None:
	"""Every stem in the AudioStreamSynchronized must be the same number of frames.

	Named explicitly rather than globbed: the piano lives in the same folder and is
	deliberately a different length, and a glob that swept it in would either fail the
	build or (worse) be relaxed until it stopped checking anything.
	"""
	lengths = {}
	for name in th.SYNCED_STEM_NAMES:
		lengths[name] = sf.info(str(out_dir / f"{name}.ogg")).frames
	unique = set(lengths.values())
	if len(unique) != 1:
		raise Failure(f"stems differ in length: {lengths}")
	if unique.pop() != th.LOOP_FRAMES:
		raise Failure(f"stems are {lengths} frames, expected {th.LOOP_FRAMES}")
	piano = sf.info(str(out_dir / "count_piano.ogg")).frames
	if piano != th.COUNT_FRAMES:
		raise Failure(f"count_piano is {piano} frames, expected {th.COUNT_FRAMES}")


def verify_velocity_layers(rows: list[dict]) -> list[tuple[str, tuple[float, float, float]]]:
	"""Prove the impact layers differ in *spectrum*, not just in level.

	The centroid is measured off the written files. It has to rise strictly from soft to
	hard by more than LAYER_CENTROID_RATIO_MIN each step — a harder strike puts energy
	into the high modes, and if that is not visible here the three files are one file at
	three volumes and the whole feature is a lie the manifest is telling.
	"""
	by_name = {r["name"]: r for r in rows}
	out: list[tuple[str, tuple[float, float, float]]] = []
	for family, stems in sfx.VELOCITY_LAYERS.items():
		cents = []
		for stem in stems:
			row = by_name.get(f"{stem}.wav")
			if row is None:
				raise Failure(f"{family}: no rendered file for layer {stem}")
			cents.append(row["centroid_hz"])
		for i in range(2):
			ratio = cents[i + 1] / max(cents[i], 1e-9)
			if ratio < LAYER_CENTROID_RATIO_MIN:
				raise Failure(f"{family}: {stems[i]} -> {stems[i + 1]} is only {ratio:.2f}x "
				              f"brighter ({cents[i]:.0f} -> {cents[i + 1]:.0f} Hz); a "
				              f"velocity layer has to change the spectrum, not the level")
		out.append((family, (cents[0], cents[1], cents[2])))
	return out


def verify_peak_ladder(rows: list[dict]) -> None:
	"""Every ordering claim in PEAK_ORDER, checked against the written files."""
	by_name = {r["name"]: r["peak_db"] for r in rows}
	for louder, quieter in PEAK_ORDER:
		a = by_name.get(f"{louder}.wav")
		b = by_name.get(f"{quieter}.wav")
		if a is None or b is None:
			raise Failure(f"peak ladder: {louder} or {quieter} was not rendered")
		if not a > b:
			raise Failure(f"peak ladder: {quieter} ({b:.2f} dB) is not below "
			              f"{louder} ({a:.2f} dB)")


def verify_sfx_tuning(out_dir: Path) -> list[tuple[str, float, float, float]]:
	"""Measure the tuned events off disk and prove they land where they are notated.

	Struck bars are inharmonic (a chime's partials are 1 : 2.76 : 5.40), so the tuned
	thing is the fundamental *mode*, not the waveform's period — autocorrelation reports
	an in-tune chime as a hundred cents flat because it is answering a different
	question. Measured on the file, after the room and the 16-bit encode.
	"""
	results = []
	for event, (target, at) in sfx.PITCHED_EVENTS.items():
		data, _ = sf.read(str(out_dir / f"{event}.wav"), dtype="float64")
		window = data[n_of(at): n_of(at) + n_of(0.5)]
		got = partial_hz(window, SR, target * 0.80, target * 1.25)
		cents = th.cents_between(got, target) if got > 0.0 else float("inf")
		results.append((event, target, got, cents))
	return results


# -------------------------------------------------------------------- manifest


def write_manifest(path: Path, sfx_rows: list[dict], music_rows: list[dict],
                   tuning: list[tuple[str, float, float, float]],
                   sfx_tuning: list[tuple[str, float, float, float]],
                   voice_rows: list[dict],
                   layers: list[tuple[str, tuple[float, float, float]]]) -> None:
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
	add("(knocker and kickback loudest, spinner_tick and wall_tap far below) so gameplay code")
	add("does not have to ride volume_db on every call; music stems are matched by integrated")
	add("loudness (LUFS) instead, so the stack stays balanced as stems fade in. The orderings")
	add("the ladder actually promises — the rank-up pair over the Club's jackpot, the jackpot")
	add("over the Family Meeting stingers — are asserted against the written files at build")
	add("time and again in tests/test_audio_assets.gd, not left as a comment.")
	add("")

	if sfx_rows:
		loopers = ", ".join(sorted(sfx.LOOP_EVENTS))
		add("SFX — assets/audio/sfx/*.wav  (44.1 kHz, 16-bit PCM, mono)")
		add("Looping events are built periodic and carry a 'seam' figure; every other file is")
		add(f"a one-shot that starts and ends at true zero. Loops: {loopers}.")
		add("Wave 4 closes the vocabulary with the endgame (specs/m3-fall-rise.md AUDIO-4):")
		add("the Commission fights, the Docks, the Penthouse, the dome, the heists, the")
		add("election, Empire Mode, the Reunion, the briefcases and Skip Town. Two of its peak")
		add("placements are load-bearing and both are asserted below the table: dome_loop is")
		add("the biggest PITCHED sound in the game and still loses to the knocker, and")
		add("empire_start — everything lit, x10 on everything — still loses to the rank-up")
		add("pair, because a mode starting never outranks a career moving. Four files have a")
		add("LENGTH contract as well as a level one: wrench_telegraph and crane_telegraph are")
		add("exactly as long as the tells they cover, and skip_town/train_away are timed")
		add("against AudioDirector.play_farewell(), so all four are played at pitch 1.0.")
		add("-" * 78)
		add(f"{'file':<22}{'dur':>8}{'peak dB':>9}{'rms dB':>9}{'crest':>8}"
		    f"{'centroid':>10}{'decay':>9}{'seam':>7}{'KiB':>8}")
		for r in sfx_rows:
			seam = f"{r['wrap_ratio']:7.2f}" if "wrap_ratio" in r else f"{'—':>7}"
			add(f"{r['name']:<22}{r['seconds']:7.3f}s{r['peak_db']:9.2f}{r['rms_db']:9.2f}"
			    f"{r['crest_db']:8.1f}{r['centroid_hz']:9.0f}Hz{r['decay_s'] * 1000:8.0f}ms"
			    f"{seam}{r['bytes'] / 1024:8.1f}")
		total = sum(r["bytes"] for r in sfx_rows)
		add(f"{'subtotal':<22}{'':>8}{'':>9}{'':>9}{'':>8}{'':>10}{'':>9}{'':>7}"
		    f"{total / 1024:8.1f}")
		add("")

	if layers:
		add("VELOCITY LAYERS — docs/08 §8. Three files per physical event, picked at play")
		add("time by AudioDirector.play(event, {\"impact\": 0..1}); jitter still applies inside")
		add("the chosen rung. The MEDIUM rung IS the original file — same seed, same numbers,")
		add("byte-identical — so a call with no `impact` sounds exactly as it always has.")
		add("Brightness, not level, is the variable: the centroids below are measured off the")
		add(f"written files and the build fails unless each step is >= {LAYER_CENTROID_RATIO_MIN:.2f}x.")
		add("-" * 78)
		add(f"{'family':<16}{'soft':>11}{'medium':>11}{'hard':>11}{'soft->med':>12}{'med->hard':>12}")
		for family, (lo, mid, hi) in layers:
			add(f"{family:<16}{lo:9.0f}Hz{mid:9.0f}Hz{hi:9.0f}Hz"
			    f"{mid / lo:11.2f}x{hi / mid:11.2f}x")
		add("")

	if voice_rows:
		add("VOICES — assets/audio/voice/<specialist>_<n>.wav  (44.1 kHz, 16-bit PCM, mono)")
		add("docs/08 §5, the muted-brass mob: one instrument per specialist, three phrases each")
		add("(0 greeting · 1 quip · 2 grumble). Not melodies — speech contours. Every phrase is")
		add("3-7 syllables of continuous, unquantised pitch glide under a moving plunger mute,")
		add("with a loudness floor between syllables so it mumbles instead of articulating.")
		add("Skids is the exception and the joke: he is struck, not blown — three dings of a")
		add("bicycle bell over a sigh that carries the vowels the bell cannot.")
		add("'wah' is the brightest 60 ms window's centroid over the dullest (the mute moving);")
		add("'bumps' counts loudness excursions (prosody). Levelled by K-weighted loudness, not")
		add(f"peak: the bank sits at {voice.VOICE_LUFS:.0f} LUFS so nobody is louder for being a tuba.")
		add("-" * 78)
		add(f"{'file':<18}{'instrument':<14}{'mood':<10}{'dur':>7}{'peak dB':>9}{'LUFS':>7}"
		    f"{'centroid':>10}{'wah':>7}{'bumps':>7}{'KiB':>8}")
		for r in voice_rows:
			sp = voice.SPEAKER_BY_NAME[r["speaker"]]
			add(f"{r['name']:<18}{sp.instrument:<14}{r['mood']:<10}{r['seconds']:6.2f}s"
			    f"{r['peak_db']:9.2f}{r['lufs']:7.1f}{r['centroid_hz']:9.0f}Hz"
			    f"{r['wah']:6.2f}x{r['bumps']:7d}{r['bytes'] / 1024:8.1f}")
		total = sum(r["bytes"] for r in voice_rows)
		add(f"{'subtotal':<18}{'':<14}{'':<10}{'':>7}{'':>9}{'':>7}{'':>10}{'':>7}{'':>7}"
		    f"{total / 1024:8.1f}")
		add("")

	if music_rows:
		add(f"MUSIC — assets/audio/music/city1/*.ogg  (44.1 kHz, Vorbis q{1.0 - VORBIS_COMPRESSION:.1f}, stereo)")
		add(f"'Eastport 72' — {th.BPM:.0f} BPM swung, D minor, 8-bar loop, "
		    f"{th.LOOP_FRAMES} frames ({th.LOOP_SECONDS:.4f} s) each.")
		add("Chords: bars 1-2 Dm6 | 3-4 Gm7 | 5 Bb7 | 6 A7 | 7 Dm6 | 8 A7.")
		add("01-08 are the level stack (music_set_level); 09/10 are state layers on the SAME")
		add(f"sample-locked player. count_piano is NOT synced — {th.COUNT_BPM:.0f} BPM, "
		    f"{th.COUNT_BARS} bars, {th.COUNT_FRAMES} frames.")
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
		add("calm eight summed, for listening checks only — the game never loads it.")
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

	if sfx_tuning:
		worst = max(abs(c) for _, _, _, c in sfx_tuning)
		add(f"TUNED SFX — fundamental mode measured off the written WAV "
		    f"(worst {worst:.2f} cents, tolerance {TUNED_SFX_TOLERANCE_CENTS:.0f})")
		add("The chimes are D5/F5/A5 and the combo blips are the same three an octave up, so")
		add("a combo landing on a Wire draw is a chord rather than a mistake.")
		add("-" * 78)
		row = []
		for name, target, got, cents in sfx_tuning:
			row.append(f"{name:<16}{target:8.2f}->{got:8.2f}Hz {cents:+5.2f}c")
			if len(row) == 2:
				add("  ".join(row))
				row = []
		if row:
			add("  ".join(row))
		add("")

	grand = sum(r["bytes"] for r in sfx_rows + voice_rows + music_rows)
	add(f"TOTAL COMMITTED AUDIO: {grand / 1024 / 1024:.2f} MiB "
	    f"({len(sfx_rows)} SFX + {len(voice_rows)} voice + {len(music_rows)} music files), "
	    f"budget {SIZE_BUDGET_MB:.0f} MiB")
	path.write_text("\n".join(lines) + "\n", encoding="utf-8")


# ------------------------------------------------------------------------ main


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Synthesise all KINGPIN audio.")
	parser.add_argument("--only", choices=["sfx", "voice", "music"], default=None,
	                    help="render only one part of the set")
	parser.add_argument("--out", default="assets/audio", type=Path,
	                    help="output root (default: assets/audio)")
	args = parser.parse_args(argv)

	out = args.out
	started = time.time()
	sfx_rows: list[dict] = []
	voice_rows: list[dict] = []
	music_rows: list[dict] = []
	tuning: list[tuple[str, float, float, float]] = []
	sfx_tuning: list[tuple[str, float, float, float]] = []
	layers: list[tuple[str, tuple[float, float, float]]] = []

	try:
		if args.only in (None, "sfx"):
			print(f"SFX -> {out / 'sfx'}")
			sfx_rows = render_sfx(out / "sfx")
			sfx_tuning = verify_sfx_tuning(out / "sfx")
			worst_name, _, _, worst = max(sfx_tuning, key=lambda r: abs(r[3]))
			print(f"  tuned SFX: worst {worst_name} {worst:+.2f} cents "
			      f"({len(sfx_tuning)} checked)")
			if abs(worst) > TUNED_SFX_TOLERANCE_CENTS:
				raise Failure(f"{worst_name} is {worst:+.2f} cents off "
				              f"(tolerance ±{TUNED_SFX_TOLERANCE_CENTS:.0f})")
			layers = verify_velocity_layers(sfx_rows)
			for family, (lo, mid, hi) in layers:
				print(f"  layers {family:<12} centroid {lo:5.0f} -> {mid:5.0f} -> {hi:5.0f} Hz "
				      f"({mid / lo:.2f}x, {hi / mid:.2f}x)")
			verify_peak_ladder(sfx_rows)
			print(f"  peak ladder: {len(PEAK_ORDER)} ordering claims hold")

		if args.only in (None, "voice"):
			print(f"voices -> {out / 'voice'}  ({len(voice.SPEAKERS)} specialists "
			      f"x {len(voice.MOOD_NAMES)} moods)")
			voice_rows = render_voices(out / "voice")

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
			verify_stem_lengths(out / "music" / "city1")
			print(f"  combined mix: {lufs_integrated(mix, SR):.1f} LUFS "
			      f"(pre-limiter), peak {peak_db(mix):.2f} dB")
	except Failure as exc:
		print(f"\nFAILED: {exc}", file=sys.stderr)
		return 1

	elapsed = time.time() - started
	manifest = out / "MANIFEST.txt"
	if args.only is None:
		write_manifest(manifest, sfx_rows, music_rows, tuning, sfx_tuning, voice_rows, layers)
		print(f"\nmanifest -> {manifest}")
	total = sum(r["bytes"] for r in sfx_rows + voice_rows + music_rows)
	print(f"total committed audio: {total / 1024 / 1024:.2f} MiB in {elapsed:.1f} s")
	if total > SIZE_BUDGET_MB * 1024 * 1024:
		print(f"FAILED: over the {SIZE_BUDGET_MB:.0f} MiB budget", file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
